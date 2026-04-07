import Foundation
import PDFKit

actor DocumentIndexingService {
    private let db = DatabaseService.shared
    private let batchSize = 20

    struct IndexResult {
        let chunkCount: Int
        let hasEmbeddings: Bool
        let suggestedQuestions: [String]
    }

    // MARK: - Public API

    func indexIfNeeded(paper: Paper, aiService: ChatAIService) async -> IndexResult? {
        guard let url = paper.pdfURL, paper.pdfExists else { return nil }

        // Check cache
        if let meta = await db.loadIndexMeta(forPaper: paper.id) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modDate = (attrs?[.modificationDate] as? Date).map { ISO8601DateFormatter().string(from: $0) } ?? ""
            if meta.pdfModifiedAt == modDate {
                let chunks = await db.loadChunks(forPaper: paper.id)
                return IndexResult(
                    chunkCount: chunks.count,
                    hasEmbeddings: chunks.first?.embedding != nil,
                    suggestedQuestions: meta.suggestedQuestions
                )
            }
            // PDF changed — re-index
            await db.deleteChunks(forPaper: paper.id)
            await db.deleteIndexMeta(forPaper: paper.id)
        }

        return await performIndexing(paper: paper, url: url, aiService: aiService)
    }

    // MARK: - Indexing Pipeline

    private func performIndexing(paper: Paper, url: URL, aiService: ChatAIService) async -> IndexResult? {
        // 1. Extract text per page
        guard let document = PDFDocument(url: url) else { return nil }
        var pageTexts: [(page: Int, text: String)] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string, !text.isEmpty {
                pageTexts.append((page: i + 1, text: text))
            }
        }
        guard !pageTexts.isEmpty else { return nil }

        // 2. Chunk text
        let chunks = chunkPages(pageTexts)

        // 3. Try to generate embeddings
        var embeddedChunks: [(paperId: String, pageNumber: Int, chunkIndex: Int, text: String, embedding: Data?)] = []
        var hasEmbeddings = false

        do {
            let texts = chunks.map(\.text)
            var allEmbeddings: [[Float]] = []

            // Batch embedding requests
            for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, texts.count)
                let batch = Array(texts[batchStart..<batchEnd])
                let batchEmbeddings = try await aiService.embed(texts: batch)
                allEmbeddings.append(contentsOf: batchEmbeddings)
            }

            for (i, chunk) in chunks.enumerated() {
                let embData = i < allEmbeddings.count ? floatsToData(allEmbeddings[i]) : nil
                embeddedChunks.append((paperId: paper.id, pageNumber: chunk.page, chunkIndex: i, text: chunk.text, embedding: embData))
            }
            hasEmbeddings = true
        } catch {
            // Fallback: store chunks without embeddings
            for (i, chunk) in chunks.enumerated() {
                embeddedChunks.append((paperId: paper.id, pageNumber: chunk.page, chunkIndex: i, text: chunk.text, embedding: nil))
            }
        }

        // 4. Store in database
        let now = ISO8601DateFormatter().string(from: Date())
        await db.insertChunks(embeddedChunks, indexedAt: now)

        // 5. Generate suggested questions
        let questions = await generateSuggestedQuestions(paper: paper, chunks: chunks, aiService: aiService)

        // 6. Store index metadata
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modDate = (attrs?[.modificationDate] as? Date).map { ISO8601DateFormatter().string(from: $0) } ?? now
        await db.saveIndexMeta(paperId: paper.id, pdfModifiedAt: modDate, suggestedQuestions: questions, indexedAt: now)

        return IndexResult(chunkCount: chunks.count, hasEmbeddings: hasEmbeddings, suggestedQuestions: questions)
    }

    // MARK: - Chunking

    private struct TextChunk {
        let page: Int
        let text: String
    }

    private func chunkPages(_ pageTexts: [(page: Int, text: String)]) -> [TextChunk] {
        let targetTokens = 500
        let overlapTokens = 50
        var chunks: [TextChunk] = []

        var buffer = ""
        var bufferPage = pageTexts.first?.page ?? 1

        for (page, text) in pageTexts {
            let words = text.split(separator: " ", omittingEmptySubsequences: true)

            for word in words {
                buffer += (buffer.isEmpty ? "" : " ") + word
                let tokenEstimate = buffer.split(separator: " ").count

                if tokenEstimate >= targetTokens {
                    // Emit chunk — page spans at most from bufferPage to current page
                    chunks.append(TextChunk(page: bufferPage, text: buffer))

                    // Keep overlap
                    let allWords = buffer.split(separator: " ")
                    if allWords.count > overlapTokens {
                        buffer = allWords.suffix(overlapTokens).joined(separator: " ")
                    } else {
                        buffer = ""
                    }
                    bufferPage = page
                }
            }
        }

        // Remaining buffer
        if !buffer.trimmingCharacters(in: .whitespaces).isEmpty {
            chunks.append(TextChunk(page: bufferPage, text: buffer))
        }

        return chunks
    }

    // MARK: - Suggested Questions

    private func generateSuggestedQuestions(paper: Paper, chunks: [TextChunk], aiService: ChatAIService) async -> [String] {
        let firstChunk = chunks.first?.text ?? ""
        let sampleChunks = chunks.count > 3
            ? [chunks[chunks.count / 3].text, chunks[chunks.count * 2 / 3].text]
            : chunks.dropFirst().map(\.text)

        let prompt = """
        Based on this academic paper, generate exactly 3 short questions a reader might ask. \
        Return ONLY the questions, one per line, no numbering.

        Title: \(paper.title)
        Authors: \(paper.authorsDisplay)

        Abstract/Introduction:
        \(String(firstChunk.prefix(1500)))

        Sample content:
        \(sampleChunks.map { String($0.prefix(500)) }.joined(separator: "\n---\n"))
        """

        do {
            let response = try await aiService.chatCompletion(
                systemPrompt: "You generate concise research questions about academic papers. Return exactly 3 questions, one per line.",
                messages: [("user", prompt)]
            )
            let questions = response.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
            return Array(questions)
        } catch {
            return []
        }
    }

    // MARK: - Similarity Search

    func searchSimilar(query: String, paperId: String, aiService: ChatAIService, topK: Int = 6) async -> [(chunk: PaperChunk, score: Float)] {
        let chunks = await db.loadChunks(forPaper: paperId)
        guard !chunks.isEmpty else { return [] }

        // Check if chunks have embeddings
        let hasEmbeddings = chunks.first?.embedding != nil

        if hasEmbeddings {
            do {
                let queryEmbeddings = try await aiService.embed(texts: [query])
                guard let queryVec = queryEmbeddings.first else { return fallbackChunks(chunks, topK: topK) }

                var scored: [(chunk: PaperChunk, score: Float)] = []
                for chunk in chunks {
                    guard let embData = chunk.embedding else { continue }
                    let chunkVec = dataToFloats(embData)
                    let score = cosineSimilarity(queryVec, chunkVec)
                    scored.append((chunk, score))
                }

                scored.sort { $0.score > $1.score }
                return Array(scored.prefix(topK))
            } catch {
                return fallbackChunks(chunks, topK: topK)
            }
        } else {
            return fallbackChunks(chunks, topK: topK)
        }
    }

    private func fallbackChunks(_ chunks: [PaperChunk], topK: Int) -> [(chunk: PaperChunk, score: Float)] {
        Array(chunks.prefix(topK)).map { ($0, 0.0) }
    }

    // MARK: - Vector Math

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    private func floatsToData(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func dataToFloats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self))
        }
    }
}
