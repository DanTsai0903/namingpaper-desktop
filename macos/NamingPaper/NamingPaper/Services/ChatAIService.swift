import Foundation

actor ChatAIService {
    struct ProviderConfig {
        let provider: String
        let model: String
        let apiKey: String
        let baseURL: String
    }

    private let config: ProviderConfig
    private var unloadTask: Task<Void, Never>?

    init(config: ProviderConfig) {
        self.config = config
    }

    // MARK: - Chat Completion

    func chatCompletion(systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        switch config.provider {
        case "ollama":
            return try await ollamaChat(systemPrompt: systemPrompt, messages: messages)
        case "omlx":
            let result = try await openAICompatibleChat(systemPrompt: systemPrompt, messages: messages, baseURL: config.baseURL.isEmpty ? "http://localhost:8000/v1" : config.baseURL)
            scheduleOMLXUnload()
            return result
        case "lmstudio":
            return try await openAICompatibleChat(systemPrompt: systemPrompt, messages: messages, baseURL: config.baseURL.isEmpty ? "http://localhost:1234/v1" : config.baseURL, ttl: 300)
        case "openai":
            return try await openAICompatibleChat(systemPrompt: systemPrompt, messages: messages, baseURL: "https://api.openai.com/v1")
        case "gemini":
            return try await geminiChat(systemPrompt: systemPrompt, messages: messages)
        case "claude":
            return try await claudeChat(systemPrompt: systemPrompt, messages: messages)
        default:
            throw ChatAIError.unsupportedProvider(config.provider)
        }
    }

    // MARK: - Embeddings

    func embed(texts: [String]) async throws -> [[Float]] {
        switch config.provider {
        case "ollama":
            return try await ollamaEmbed(texts: texts)
        case "omlx":
            let result = try await openAICompatibleEmbed(texts: texts, baseURL: config.baseURL.isEmpty ? "http://localhost:8000/v1" : config.baseURL)
            scheduleOMLXUnload()
            return result
        case "lmstudio":
            return try await openAICompatibleEmbed(texts: texts, baseURL: config.baseURL.isEmpty ? "http://localhost:1234/v1" : config.baseURL, ttl: 300)
        case "openai":
            return try await openAICompatibleEmbed(texts: texts, baseURL: "https://api.openai.com/v1")
        case "gemini":
            return try await geminiEmbed(texts: texts)
        case "claude":
            throw ChatAIError.embeddingsNotSupported
        default:
            throw ChatAIError.unsupportedProvider(config.provider)
        }
    }

    // MARK: - Ollama

    private func ollamaChat(systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        let base = config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        let url = URL(string: "\(base)/api/chat")!

        var msgs: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for m in messages {
            msgs.append(["role": m.role, "content": m.content])
        }

        let body: [String: Any] = [
            "model": config.model.isEmpty ? "qwen3:8b" : config.model,
            "messages": msgs,
            "stream": false,
            "keep_alive": 300
        ]

        let data = try await post(url: url, body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChatAIError.invalidResponse
        }
        return content
    }

    private func ollamaEmbed(texts: [String]) async throws -> [[Float]] {
        let base = config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        let url = URL(string: "\(base)/api/embed")!

        let body: [String: Any] = [
            "model": config.model.isEmpty ? "qwen3:8b" : config.model,
            "input": texts,
            "keep_alive": 300
        ]

        let data = try await post(url: url, body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddings = json["embeddings"] as? [[Double]] else {
            throw ChatAIError.embeddingsNotSupported
        }
        return embeddings.map { $0.map(Float.init) }
    }

    // MARK: - OpenAI-compatible (OpenAI, LM Studio, oMLX)

    private func openAICompatibleChat(systemPrompt: String, messages: [(role: String, content: String)], baseURL: String, ttl: Int? = nil) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!

        var msgs: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for m in messages {
            msgs.append(["role": m.role, "content": m.content])
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": msgs
        ]
        if let ttl { body["ttl"] = ttl }

        let data = try await post(url: url, body: body, authHeader: apiAuthHeader())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChatAIError.invalidResponse
        }
        return content
    }

    private func openAICompatibleEmbed(texts: [String], baseURL: String, ttl: Int? = nil) async throws -> [[Float]] {
        let url = URL(string: "\(baseURL)/embeddings")!

        var body: [String: Any] = [
            "model": config.model,
            "input": texts
        ]
        if let ttl { body["ttl"] = ttl }

        let data = try await post(url: url, body: body, authHeader: apiAuthHeader())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]] else {
            throw ChatAIError.embeddingsNotSupported
        }

        let sorted = dataArr.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
        return sorted.compactMap { item in
            (item["embedding"] as? [Double])?.map(Float.init)
        }
    }

    // MARK: - Gemini

    private func geminiChat(systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        let model = config.model.isEmpty ? "gemini-2.0-flash" : config.model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(config.apiKey)")!

        var contents: [[String: Any]] = []
        for m in messages {
            let role = m.role == "assistant" ? "model" : "user"
            contents.append(["role": role, "parts": [["text": m.content]]])
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": contents
        ]

        let data = try await post(url: url, body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw ChatAIError.invalidResponse
        }
        return text
    }

    private func geminiEmbed(texts: [String]) async throws -> [[Float]] {
        let model = "text-embedding-004"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):batchEmbedContents?key=\(config.apiKey)")!

        let requests = texts.map { text in
            ["model": "models/\(model)", "content": ["parts": [["text": text]]]] as [String: Any]
        }
        let body: [String: Any] = ["requests": requests]

        let data = try await post(url: url, body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddings = json["embeddings"] as? [[String: Any]] else {
            throw ChatAIError.embeddingsNotSupported
        }
        return embeddings.compactMap { ($0["values"] as? [Double])?.map(Float.init) }
    }

    // MARK: - Claude

    private func claudeChat(systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var msgs: [[String: String]] = []
        for m in messages {
            msgs.append(["role": m.role, "content": m.content])
        }

        let body: [String: Any] = [
            "model": config.model.isEmpty ? "claude-sonnet-4-20250514" : config.model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": msgs
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw ChatAIError.invalidResponse
        }
        return text
    }

    // MARK: - oMLX Model TTL

    /// Schedules an unload of the oMLX model after 300 seconds of inactivity.
    /// Each call resets the timer.
    private func scheduleOMLXUnload() {
        unloadTask?.cancel()
        unloadTask = Task {
            try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            unloadOMLXModel()
        }
    }

    private func unloadOMLXModel() {
        let base = config.baseURL.isEmpty ? "http://localhost:8000/v1" : config.baseURL
        // oMLX uses the short model name (last path component)
        let shortName = config.model.split(separator: "/").last.map(String.init) ?? config.model
        guard let url = URL(string: "\(base)/models/\(shortName)/unload") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let auth = apiAuthHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        // Fire and forget
        Task.detached { try? await URLSession.shared.data(for: request) }
    }

    // MARK: - HTTP Helpers

    private func apiAuthHeader() -> String? {
        config.apiKey.isEmpty ? nil : "Bearer \(config.apiKey)"
    }

    private func post(url: URL, body: [String: Any], authHeader: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ChatAIError.httpError(httpResponse.statusCode, errorBody)
        }
        return data
    }
}

enum ChatAIError: LocalizedError {
    case unsupportedProvider(String)
    case embeddingsNotSupported
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let p): return "Unsupported AI provider: \(p)"
        case .embeddingsNotSupported: return "This provider does not support embeddings"
        case .invalidResponse: return "Invalid response from AI provider"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        }
    }
}
