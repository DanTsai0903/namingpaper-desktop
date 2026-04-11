import Foundation

extension Notification.Name {
    static let navigateToPage = Notification.Name("navigateToPage")
}

struct PaperChunk: Identifiable {
    let id: Int
    let paperId: String
    let pageNumber: Int
    let chunkIndex: Int
    let text: String
    let embedding: Data?
}

struct ChatConversation: Identifiable {
    let id: String
    let paperId: String
    let createdAt: String
}

struct ChatMessage: Identifiable {
    let id: Int
    let conversationId: String
    let role: String
    let content: String
    let citations: String?
    let createdAt: String
}

struct IndexMeta {
    let paperId: String
    let pdfModifiedAt: String
    let suggestedQuestions: [String]
    let indexedAt: String
    /// AI provider id used to embed this paper's chunks (e.g. "ollama", "omlx").
    /// Part of the cache key — different providers produce incompatible vector spaces.
    let provider: String
    /// Embedding model name used (typically the same as the chat model except for
    /// providers like Gemini that hardcode an embedding model). Part of the cache key.
    let embeddingModel: String
}
