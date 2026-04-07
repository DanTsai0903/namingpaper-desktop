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

    struct DisplayMessage: Identifiable {
        let id: String
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
        if let result = await indexingService.indexIfNeeded(paper: paper, aiService: aiService) {
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
        let userMsg = DisplayMessage(id: UUID().uuidString, role: "user", content: trimmed, timestamp: Date())
        messages.append(userMsg)
        await persistMessage(role: "user", content: trimmed)

        isLoading = true
        errorMessage = nil

        do {
            // Retrieve relevant chunks
            let results = await indexingService.searchSimilar(query: trimmed, paperId: paper.id, aiService: aiService)
            let contextChunks = results.map { "[Page \($0.chunk.pageNumber)] \($0.chunk.text)" }.joined(separator: "\n\n---\n\n")

            // Build conversation history for API
            let historyMessages = messages.map { (role: $0.role, content: $0.content) }

            let systemPrompt = buildSystemPrompt(contextChunks: contextChunks)
            let response = try await aiService.chatCompletion(systemPrompt: systemPrompt, messages: historyMessages)

            let assistantMsg = DisplayMessage(id: UUID().uuidString, role: "assistant", content: response, timestamp: Date())
            messages.append(assistantMsg)
            await persistMessage(role: "assistant", content: response)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        // Clear suggested questions after first interaction
        suggestedQuestions = []
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
        if let result = await indexingService.indexIfNeeded(paper: paper, aiService: aiService) {
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

        \nBelow are relevant excerpts from the paper. Use them to answer the user's question accurately.
        IMPORTANT: When referencing specific content, cite the page number using the format [p.N] (e.g., [p.3]).
        For page ranges, use [pp. N-M]. Always include citations when making specific claims.

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

    private func persistMessage(role: String, content: String) async {
        guard let conversationId else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        await db.insertMessage(conversationId: conversationId, role: role, content: content, citations: nil, createdAt: now)
    }

    // MARK: - Provider Config

    private func buildAIService() -> ChatAIService? {
        let activeProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "ollama"
        let activeModel = UserDefaults.standard.string(forKey: "aiModel") ?? ""

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
