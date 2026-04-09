import Foundation

actor ChatAIService {
    struct ProviderConfig {
        let provider: String
        let model: String
        let apiKey: String
        let baseURL: String
    }

    private let config: ProviderConfig

    init(config: ProviderConfig) {
        self.config = config
    }

    // MARK: - Chat Completion

    func chatCompletion(systemPrompt: String, messages: [(role: String, content: String)]) async throws -> String {
        switch config.provider {
        case "ollama":
            return try await ollamaChat(systemPrompt: systemPrompt, messages: messages, keepAlive: 300)
        case "omlx":
            setOMLXTTL(seconds: 300)
            return try await openAICompatibleChat(systemPrompt: systemPrompt, messages: messages, baseURL: config.baseURL.isEmpty ? "http://localhost:8000/v1" : config.baseURL)
        case "lmstudio":
            return try await openAICompatibleChat(
                systemPrompt: systemPrompt,
                messages: messages,
                baseURL: config.baseURL.isEmpty ? "http://localhost:1234/v1" : config.baseURL,
                ttl: 300
            )
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
            return try await ollamaEmbed(texts: texts, keepAlive: 300)
        case "omlx":
            setOMLXTTL(seconds: 300)
            return try await openAICompatibleEmbed(texts: texts, baseURL: config.baseURL.isEmpty ? "http://localhost:8000/v1" : config.baseURL)
        case "lmstudio":
            return try await openAICompatibleEmbed(
                texts: texts,
                baseURL: config.baseURL.isEmpty ? "http://localhost:1234/v1" : config.baseURL,
                ttl: 300
            )
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

    private func ollamaChat(systemPrompt: String, messages: [(role: String, content: String)], keepAlive: Int? = nil) async throws -> String {
        let base = config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        let url = URL(string: "\(base)/api/chat")!

        var msgs: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for m in messages {
            msgs.append(["role": m.role, "content": m.content])
        }

        var body: [String: Any] = [
            "model": config.model.isEmpty ? "qwen3:8b" : config.model,
            "messages": msgs,
            "stream": false
        ]
        if let keepAlive {
            body["keep_alive"] = keepAlive
        }

        let data = try await post(url: url, body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChatAIError.invalidResponse
        }
        return stripThinkingBlocks(content)
    }

    private func ollamaEmbed(texts: [String], keepAlive: Int? = nil) async throws -> [[Float]] {
        let base = config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        let url = URL(string: "\(base)/api/embed")!

        var body: [String: Any] = [
            "model": config.model.isEmpty ? "qwen3:8b" : config.model,
            "input": texts
        ]
        if let keepAlive {
            body["keep_alive"] = keepAlive
        }

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
        if let ttl {
            // LM Studio's OpenAI-compatible API accepts a `ttl` field that controls
            // how long to keep the model loaded after this request finishes.
            body["ttl"] = ttl
        }

        let data = try await post(url: url, body: body, authHeader: apiAuthHeader())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChatAIError.invalidResponse
        }
        return stripThinkingBlocks(content)
    }

    private func openAICompatibleEmbed(texts: [String], baseURL: String, ttl: Int? = nil) async throws -> [[Float]] {
        let url = URL(string: "\(baseURL)/embeddings")!

        var body: [String: Any] = [
            "model": config.model,
            "input": texts
        ]
        if let ttl {
            body["ttl"] = ttl
        }

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
        return stripThinkingBlocks(text)
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
        return stripThinkingBlocks(text)
    }

    // MARK: - oMLX Model TTL

    /// Configure oMLX to auto-unload the model after `seconds` of idle time.
    /// Sent fire-and-forget BEFORE each chat/embed request via the admin API:
    ///   PUT /admin/api/models/{model_id}/settings  {"ttl_seconds": N}
    /// oMLX itself tracks last access and unloads when the idle window expires.
    private func setOMLXTTL(seconds: Int) {
        // Strip `/v1` (or any trailing path) from the configured base URL to reach
        // the admin API root (admin endpoints live alongside `/v1`, not inside it).
        let configured = config.baseURL.isEmpty ? "http://localhost:8000/v1" : config.baseURL
        guard let v1URL = URL(string: configured) else { return }
        var components = URLComponents()
        components.scheme = v1URL.scheme
        components.host = v1URL.host
        components.port = v1URL.port
        // oMLX uses the short model name (last path component) in URLs
        let shortName = config.model.split(separator: "/").last.map(String.init) ?? config.model
        components.path = "/admin/api/models/\(shortName)/settings"
        guard let url = components.url else { return }

        let body: [String: Any] = ["ttl_seconds": seconds]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = apiAuthHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = data
        // Fire and forget — the TTL update is idempotent and we don't want to
        // block the chat request waiting for it.
        Task.detached { try? await URLSession.shared.data(for: request) }
    }

    // MARK: - Response Cleaning

    /// Strip `<think>…</think>` blocks that reasoning models (e.g. Qwen3, DeepSeek) emit.
    private nonisolated func stripThinkingBlocks(_ text: String) -> String {
        text.replacingOccurrences(of: #"<think>[\s\S]*?</think>\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Local reasoning models (oMLX/Ollama/LM Studio with Qwen3, DeepSeek, etc.) can take
        // several minutes to produce a long response with a <think> block. The response is
        // non-streaming, so the entire output must arrive before the first byte — keep this
        // generous so summaries from small local models don't time out.
        request.timeoutInterval = 600

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
