import Foundation
import SwiftUI

@Observable
class ChatViewModel {
    var messages: [DisplayMessage] = []
    var isLoading = false
    var isIndexing = false
    var indexingProgress: String = ""
    var suggestedQuestions: [String] = []
    var hasIndex = false
    var errorMessage: String?

    private let paper: Paper
    private var conversationId: String?
    private var aiService: ChatAIService?
    private let indexingService = DocumentIndexingService()
    private let db = DatabaseService.shared
    private var currentTask: Task<Void, Never>?
    /// The active provider/model `aiService` was built from. Mirrored here so we can
    /// pass them as part of the indexing cache key — re-indexing must trigger when
    /// either changes, since embeddings from different providers/models live in
    /// incompatible vector spaces.
    private var activeProviderId: String = ""
    private var activeEmbeddingModel: String = ""

    enum RegenerateMode {
        case same
        case bullets
        case paragraphs
    }

    struct DisplayMessage: Identifiable {
        var id: String
        let role: String
        let content: String
        let timestamp: Date

        var isUser: Bool { role == "user" }
    }

    init(paper: Paper) {
        self.paper = paper
    }

    // MARK: - Setup

    func setup() async {
        aiService = buildAIService()
        guard let aiService else {
            errorMessage = "No AI provider configured"
            return
        }

        // Load existing conversation
        await loadConversation()

        // Index if needed
        isIndexing = true
        indexingProgress = "Indexing document..."
        if let result = await indexingService.indexIfNeeded(paper: paper, aiService: aiService, provider: activeProviderId, embeddingModel: activeEmbeddingModel) {
            suggestedQuestions = result.suggestedQuestions
            hasIndex = true
        }
        isIndexing = false
    }

    // MARK: - Send Message

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading, let aiService else { return }

        // Ensure conversation exists
        if conversationId == nil {
            await createNewConversation()
        }

        // Add user message
        let userId = await persistMessage(role: "user", content: trimmed)
        let userMsg = DisplayMessage(
            id: userId.map { String($0) } ?? UUID().uuidString,
            role: "user",
            content: trimmed,
            timestamp: Date()
        )
        messages.append(userMsg)

        isLoading = true
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                // Retrieve relevant chunks
                let results = await self.indexingService.searchSimilar(query: trimmed, paperId: self.paper.id, aiService: aiService)
                try Task.checkCancellation()
                let contextChunks = results.map { "[Page \($0.chunk.pageNumber)] \($0.chunk.text)" }.joined(separator: "\n\n---\n\n")

                // Build conversation history for API
                let historyMessages = self.messages.map { (role: $0.role, content: $0.content) }

                let systemPrompt = self.buildSystemPrompt(contextChunks: contextChunks)
                let response = try await aiService.chatCompletion(systemPrompt: systemPrompt, messages: historyMessages)
                try Task.checkCancellation()

                // Fallback: small local models often ignore the inline-citation rule.
                let retrievedChunks = results.map { (page: $0.chunk.pageNumber, text: $0.chunk.text) }
                let finalResponse = Self.ensureCitations(response: response, retrievedChunks: retrievedChunks)

                let assistantId = await self.persistMessage(role: "assistant", content: finalResponse)
                let assistantMsg = DisplayMessage(
                    id: assistantId.map { String($0) } ?? UUID().uuidString,
                    role: "assistant",
                    content: finalResponse,
                    timestamp: Date()
                )
                self.messages.append(assistantMsg)
            } catch is CancellationError {
                // Silent — user requested stop
            } catch let error as URLError where error.code == .cancelled {
                // Silent — URLSession cancellation
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
        currentTask = task
        await task.value
        currentTask = nil
        // Clear suggested questions after first interaction
        suggestedQuestions = []
    }

    // MARK: - Stop / Edit / Regenerate

    /// Cancel the in-flight chat request, if any.
    func stopGeneration() {
        currentTask?.cancel()
    }

    /// Pull a user message back into the input field for editing. Removes the message
    /// and everything after it from both the UI and the database. Returns the original
    /// content so the caller can populate the input field.
    func editUserMessage(id: String) async -> String? {
        guard let idx = messages.firstIndex(where: { $0.id == id }),
              messages[idx].role == "user" else { return nil }
        let content = messages[idx].content
        let removed = Array(messages[idx...])
        messages.removeSubrange(idx...)
        for msg in removed {
            if let dbId = Int(msg.id) {
                await db.deleteMessage(id: dbId)
            }
        }
        return content
    }

    /// Re-ask in a way that's visible in the chat: appends a NEW user bubble
    /// (carrying either the original question or a format-instruction-prefixed
    /// copy of the previous answer), then generates a fresh assistant response
    /// below it. Nothing in the existing chat is removed.
    /// - `same`: new user bubble is the original question text
    /// - `bullets` / `paragraphs`: new user bubble is the format prompt followed by
    ///   the previous assistant response, so the model reformats it in place
    func regenerateAssistantMessage(id: String, mode: RegenerateMode) async {
        guard !isLoading,
              let assistantIdx = messages.firstIndex(where: { $0.id == id }),
              messages[assistantIdx].role == "assistant",
              let aiService else { return }

        let oldAssistant = messages[assistantIdx]

        // Walk backward to find the user question that produced this answer —
        // we need it for `.same` mode and for keying RAG retrieval.
        var foundQIdx: Int? = nil
        var i = assistantIdx - 1
        while i >= 0 {
            if messages[i].role == "user" {
                foundQIdx = i
                break
            }
            i -= 1
        }
        guard let qIdx = foundQIdx else { return }
        let originalQuestion = messages[qIdx].content

        // Compose the new user-turn text. For format modes the previous assistant
        // answer is embedded inline so the user can see exactly what's being
        // reformatted (matches the screenshot the user shared).
        let newUserText: String
        switch mode {
        case .same:
            newUserText = originalQuestion
        case .bullets:
            newUserText = "Convert to concise bullet points. Only important information, no repetition, no intro, in a consistent format:\n\n\(oldAssistant.content)"
        case .paragraphs:
            newUserText = "Rewrite as clear, flowing paragraphs:\n\n\(oldAssistant.content)"
        }

        // Persist + show the new user bubble immediately so the user sees the
        // re-ask before the model has finished generating.
        let newUserId = await persistMessage(role: "user", content: newUserText)
        let newUserMsg = DisplayMessage(
            id: newUserId.map { String($0) } ?? UUID().uuidString,
            role: "user",
            content: newUserText,
            timestamp: Date()
        )
        messages.append(newUserMsg)

        isLoading = true
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                // Retrieval is keyed off the original question so the model still
                // sees the same paper context the first answer would have.
                let results = await self.indexingService.searchSimilar(query: originalQuestion, paperId: self.paper.id, aiService: aiService)
                try Task.checkCancellation()
                let contextChunks = results.map { "[Page \($0.chunk.pageNumber)] \($0.chunk.text)" }.joined(separator: "\n\n---\n\n")

                // Send the full chat including the user bubble we just appended,
                // so the model has every turn in scope.
                let history = self.messages.map { (role: $0.role, content: $0.content) }

                let systemPrompt = self.buildSystemPrompt(contextChunks: contextChunks)
                let raw = try await aiService.chatCompletion(systemPrompt: systemPrompt, messages: history)
                try Task.checkCancellation()

                let retrievedChunks = results.map { (page: $0.chunk.pageNumber, text: $0.chunk.text) }
                let response = Self.ensureCitations(response: raw, retrievedChunks: retrievedChunks)

                let newId = await self.persistMessage(role: "assistant", content: response)
                let newMsg = DisplayMessage(
                    id: newId.map { String($0) } ?? UUID().uuidString,
                    role: "assistant",
                    content: response,
                    timestamp: Date()
                )
                self.messages.append(newMsg)
            } catch is CancellationError {
                // Silent
            } catch let error as URLError where error.code == .cancelled {
                // Silent
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
        currentTask = task
        await task.value
        currentTask = nil
    }

    // MARK: - Provider Switching

    /// Rebuild the AI service after the active provider changes (e.g. user picks a different
    /// provider from the chat panel). Re-runs indexing so embeddings match the new provider.
    func refreshProvider() async {
        aiService = buildAIService()
        guard let aiService else {
            errorMessage = "No AI provider configured"
            return
        }
        errorMessage = nil
        isIndexing = true
        indexingProgress = "Re-indexing for new provider..."
        if let result = await indexingService.indexIfNeeded(paper: paper, aiService: aiService, provider: activeProviderId, embeddingModel: activeEmbeddingModel) {
            suggestedQuestions = result.suggestedQuestions
            hasIndex = true
        }
        isIndexing = false
    }

    // MARK: - Summarize

    func summarize() async {
        await sendMessage("Please provide a comprehensive summary of this paper, including the main research question, methodology, key findings, and conclusions.")
    }

    // MARK: - New Conversation

    func startNewConversation() async {
        conversationId = nil
        messages = []
        errorMessage = nil
        // Reload suggested questions from index meta
        if let meta = await db.loadIndexMeta(forPaper: paper.id) {
            suggestedQuestions = meta.suggestedQuestions
        }
    }

    // MARK: - Citation Fallback

    /// Small local models (e.g. Qwen3.5-2B) often ignore the inline `[p.N]` citation
    /// rule in the system prompt. This fallback post-processes the response: it groups
    /// lines into paragraphs/bullet items, matches each group against the retrieved
    /// chunks (via word overlap, falling back to the top embedding-ranked chunk), and
    /// appends `[p.N]` inline at the end of each substantive group.
    /// `retrievedChunks` must be in descending embedding-similarity order (first = best).
    /// Skipped entirely if the response already contains any inline citation.
    private static func ensureCitations(response: String, retrievedChunks: [(page: Int, text: String)]) -> String {
        let citationPattern = #"\[pp?\.\s*\d+(?:\s*[-–]\s*\d+)?\]|\(pp?\.\s*\d+(?:\s*[-–]\s*\d+)?\)|\[page\s+\d+\]"#
        if response.range(of: citationPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return response
        }
        guard !retrievedChunks.isEmpty else { return response }

        // Precompute chunk word sets once.
        let chunkWordSets: [(page: Int, words: Set<String>)] = retrievedChunks.map {
            (page: $0.page, words: wordSet(from: $0.text))
        }
        let fallbackPage = retrievedChunks[0].page  // best-ranked by embedding similarity

        // Group consecutive non-empty lines into logical units. A unit is either:
        //  - a single bullet / list item (line starting with `- `, `* `, `+ `, or `1. `)
        //  - a paragraph (contiguous non-empty lines, blank line separates)
        // Each unit is cited as a whole (one `[p.N]` at the end of its last line).
        let lines = response.components(separatedBy: "\n")
        var out: [String] = []
        var group: [Int] = []  // indices into `lines`

        func isBulletStart(_ line: String) -> Bool {
            line.range(of: #"^\s*([-*+]\s+|\d+[.)]\s+)"#, options: .regularExpression) != nil
        }

        func flushGroup() {
            guard !group.isEmpty else { return }
            // Join the group into a single text blob for scoring.
            let blob = group.map { lines[$0] }.joined(separator: " ")
            let stripped = blob.replacingOccurrences(of: #"^(\s*[-*+]\s+|\s*\d+[.)]\s+)"#, with: "", options: .regularExpression)
            let segWords = wordSet(from: stripped)

            // Decide whether this group deserves a citation.
            // Require at least some real content (not just markdown structure).
            let trimmedBlob = blob.trimmingCharacters(in: .whitespaces)
            let isHeader = trimmedBlob.hasPrefix("#")
            let isDivider = trimmedBlob.hasPrefix("---")
            let tooShort = trimmedBlob.count < 25
            let shouldCite = !isHeader && !isDivider && !tooShort

            if shouldCite {
                // Score each chunk by word overlap; fall back to the top-ranked chunk.
                var bestPage = fallbackPage
                var bestScore = 0.0
                if !segWords.isEmpty {
                    for chunk in chunkWordSets {
                        let overlap = Double(segWords.intersection(chunk.words).count)
                        let score = overlap / Double(segWords.count)
                        if score > bestScore {
                            bestScore = score
                            bestPage = chunk.page
                        }
                    }
                }

                // Append the citation to the LAST line of the group.
                for (offset, idx) in group.enumerated() {
                    if offset == group.count - 1 {
                        out.append(appendCitation(line: lines[idx], page: bestPage))
                    } else {
                        out.append(lines[idx])
                    }
                }
            } else {
                for idx in group { out.append(lines[idx]) }
            }
            group.removeAll(keepingCapacity: true)
        }

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushGroup()
                out.append(line)
                continue
            }
            // A new bullet starts a new group, even without a blank line between.
            if isBulletStart(line), !group.isEmpty {
                flushGroup()
            }
            group.append(idx)
        }
        flushGroup()

        return out.joined(separator: "\n")
    }

    /// Tokenize text into lowercase tokens longer than 3 chars (naturally filters
    /// common stopwords and focuses on content-bearing terms, including math symbols
    /// like `covariance`, `matrix`, `inference`).
    private static func wordSet(from text: String) -> Set<String> {
        let allowed = CharacterSet.letters.union(.decimalDigits)
        let tokens = text.lowercased().unicodeScalars
            .split { !allowed.contains($0) }
            .map { String(String.UnicodeScalarView($0)) }
            .filter { $0.count > 3 }
        return Set(tokens)
    }

    /// Append ` [p.N]` to a line, placing it before any trailing sentence punctuation
    /// so the final period/colon stays at the end.
    private static func appendCitation(line: String, page: Int) -> String {
        let trailing: Set<Character> = [".", "!", "?", ";", ":", ","]
        var prefix = line
        var suffix = ""
        while let last = prefix.last, trailing.contains(last) {
            suffix = String(last) + suffix
            prefix.removeLast()
        }
        // Avoid citing lines that are only whitespace after stripping punctuation.
        if prefix.trimmingCharacters(in: .whitespaces).isEmpty {
            return line
        }
        return "\(prefix) [p.\(page)]\(suffix)"
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(contextChunks: String) -> String {
        var prompt = """
        You are a helpful research assistant analyzing the academic paper: "\(paper.title)"
        Authors: \(paper.authorsDisplay)
        """

        if let year = paper.year {
            prompt += "\nYear: \(year)"
        }
        if !paper.journal.isEmpty {
            prompt += "\nJournal: \(paper.journal)"
        }

        prompt += """

        \nBelow are relevant excerpts from the paper. Each excerpt is prefixed with a PDF page tag like [Page 3].
        Use them to answer the user's question accurately.

        CITATION RULES (you MUST follow these strictly):
        - Every claim or fact you state MUST include a citation using the format [p.N], where N is the PDF page number from the [Page N] tag at the start of each excerpt.
        - IMPORTANT: Use the PDF page numbers from the [Page N] tags, NOT any printed journal page numbers that appear in the text content.
        - For example, if an excerpt starts with [Page 5], cite it as [p.5] — even if the text mentions "page 525" as a journal page number.
        - Place the citation inline right after the claim: "The model achieves 95% accuracy [p.5]."
        - For ranges across excerpts: [pp.3-5]
        - Multiple citations: "Results show X [p.3] and Y [p.7]."
        - Do NOT omit citations. Every specific claim needs one.

        --- PAPER EXCERPTS ---
        \(contextChunks)
        --- END EXCERPTS ---

        Answer based on the paper content. If the information isn't in the provided excerpts, say so.
        """

        return prompt
    }

    // MARK: - Persistence

    private func loadConversation() async {
        let conversations = await db.loadConversations(forPaper: paper.id)
        guard let latest = conversations.first else { return }

        conversationId = latest.id
        let dbMessages = await db.loadMessages(forConversation: latest.id)
        messages = dbMessages.map { msg in
            DisplayMessage(
                id: "\(msg.id)",
                role: msg.role,
                content: msg.content,
                timestamp: ISO8601DateFormatter().date(from: msg.createdAt) ?? Date()
            )
        }
    }

    private func createNewConversation() async {
        let id = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        await db.createConversation(id: id, paperId: paper.id, createdAt: now)
        conversationId = id
    }

    private func persistMessage(role: String, content: String) async -> Int? {
        guard let conversationId else { return nil }
        let now = ISO8601DateFormatter().string(from: Date())
        let id = await db.insertMessage(conversationId: conversationId, role: role, content: content, citations: nil, createdAt: now)
        return id == 0 ? nil : id
    }

    // MARK: - Provider Config

    private func buildAIService() -> ChatAIService? {
        let activeProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "ollama"
        let activeModel = UserDefaults.standard.string(forKey: "aiModel") ?? ""
        self.activeProviderId = activeProvider
        self.activeEmbeddingModel = activeModel

        // Load saved providers to find the active one's full config
        var apiKey = ""
        var baseURL = ""

        if let data = UserDefaults.standard.data(forKey: "savedProviders"),
           let providers = try? JSONDecoder().decode([SavedProvider].self, from: data) {
            if let active = providers.first(where: { $0.provider == activeProvider && $0.model == activeModel }) {
                apiKey = active.apiKey
                baseURL = active.baseURL
            } else if let first = providers.first(where: { $0.provider == activeProvider }) {
                apiKey = first.apiKey
                baseURL = first.baseURL
            }
        }

        // Fallback: read from config file and keychain
        if apiKey.isEmpty || baseURL.isEmpty {
            let config = ConfigService.shared.readConfig()
            if apiKey.isEmpty { apiKey = config.apiKey }
            if apiKey.isEmpty { apiKey = KeychainService.load(account: config.apiKeyTOMLName) }
            if baseURL.isEmpty { baseURL = config.baseURL }
        }

        return ChatAIService(config: .init(
            provider: activeProvider,
            model: activeModel,
            apiKey: apiKey,
            baseURL: baseURL
        ))
    }
}
