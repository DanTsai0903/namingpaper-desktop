import Foundation

struct AppConfig {
    var papersDir: String
    var provider: String
    var model: String
    var apiKey: String
    var cliPath: String
    var template: String
    var baseURL: String
    var databasePath: String

    /// The TOML key name for the API key based on provider
    var apiKeyTOMLName: String {
        switch provider {
        case "gemini": return "gemini_api_key"
        case "openai": return "openai_api_key"
        case "claude": return "anthropic_api_key"
        case "omlx": return "omlx_api_key"
        case "lmstudio": return "lmstudio_api_key"
        default: return "api_key"
        }
    }

    /// The TOML key name for the base URL based on provider
    var baseURLTOMLName: String? {
        switch provider {
        case "ollama": return "ollama_base_url"
        case "omlx": return "omlx_base_url"
        case "lmstudio": return "lmstudio_base_url"
        default: return nil
        }
    }

    static let defaultDatabasePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".namingpaper/library.db").path

    static let `default` = AppConfig(
        papersDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Papers").path,
        provider: "ollama",
        model: "",
        apiKey: "",
        cliPath: "",
        template: "default",
        baseURL: "",
        databasePath: defaultDatabasePath
    )
}

class ConfigService {
    static let shared = ConfigService()

    private let configPath: String

    var configExists: Bool {
        FileManager.default.fileExists(atPath: configPath)
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configPath = home.appendingPathComponent(".namingpaper/config.toml").path
    }

    // MARK: - Read

    func readConfig() -> AppConfig {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return .default
        }
        return parseTOML(content)
    }

    // MARK: - Write

    func writeConfig(_ config: AppConfig) throws {
        var lines: [String] = []

        // Read existing file to preserve unknown keys
        if let content = try? String(contentsOfFile: configPath, encoding: .utf8) {
            lines = updateTOML(content, with: config)
        } else {
            lines = buildTOML(config)
        }

        let dir = (configPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
        // Restrict to owner-only since the file may contain API keys
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath)
    }

    // MARK: - Minimal TOML Parser

    private let apiKeyNames: Set<String> = [
        "api_key", "gemini_api_key", "openai_api_key", "anthropic_api_key", "claude_api_key", "omlx_api_key", "lmstudio_api_key"
    ]

    private let baseURLNames: Set<String> = [
        "ollama_base_url", "omlx_base_url", "lmstudio_base_url"
    ]

    private func parseTOML(_ content: String) -> AppConfig {
        var config = AppConfig.default
        var currentSection = ""

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Section header
            if trimmed.hasPrefix("["), let end = trimmed.firstIndex(of: "]") {
                currentSection = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
                continue
            }

            // Key = value
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)

            // Strip quotes
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }

            let fullKey = currentSection.isEmpty ? key : "\(currentSection).\(key)"

            switch fullKey {
            case "papers_dir": config.papersDir = value
            case "provider": config.provider = value
            case "model": config.model = value
            case "template": config.template = value
            case "database_path": config.databasePath = value
            case _ where apiKeyNames.contains(fullKey):
                config.apiKey = value
            case _ where baseURLNames.contains(fullKey):
                config.baseURL = value
            default: break
            }
        }

        return config
    }

    private func buildTOML(_ config: AppConfig) -> [String] {
        var lines: [String] = []
        if !config.papersDir.isEmpty {
            lines.append("papers_dir = \"\(config.papersDir)\"")
        }
        if !config.provider.isEmpty {
            lines.append("provider = \"\(config.provider)\"")
        }
        if !config.model.isEmpty {
            lines.append("model = \"\(config.model)\"")
        }
        if !config.apiKey.isEmpty {
            lines.append("\(config.apiKeyTOMLName) = \"\(config.apiKey)\"")
        }
        if !config.baseURL.isEmpty, let key = config.baseURLTOMLName {
            lines.append("\(key) = \"\(config.baseURL)\"")
        }
        if !config.template.isEmpty, config.template != "default" {
            lines.append("template = \"\(config.template)\"")
        }
        if !config.databasePath.isEmpty, config.databasePath != AppConfig.defaultDatabasePath {
            lines.append("database_path = \"\(config.databasePath)\"")
        }
        lines.append("")
        return lines
    }

    private func updateTOML(_ content: String, with config: AppConfig) -> [String] {
        var lines = content.components(separatedBy: .newlines)
        var found: Set<String> = []

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)

            switch key {
            case "papers_dir":
                lines[i] = "papers_dir = \"\(config.papersDir)\""
                found.insert("papers_dir")
            case "provider":
                lines[i] = "provider = \"\(config.provider)\""
                found.insert("provider")
            case "model":
                lines[i] = "model = \"\(config.model)\""
                found.insert("model")
            case "template":
                lines[i] = "template = \"\(config.template)\""
                found.insert("template")
            case "database_path":
                if !config.databasePath.isEmpty, config.databasePath != AppConfig.defaultDatabasePath {
                    lines[i] = "database_path = \"\(config.databasePath)\""
                } else {
                    lines[i] = "# database_path removed"
                }
                found.insert("database_path")
            case _ where apiKeyNames.contains(key):
                // Replace existing API key line with the correct provider-specific key
                if !config.apiKey.isEmpty {
                    lines[i] = "\(config.apiKeyTOMLName) = \"\(config.apiKey)\""
                } else {
                    lines[i] = "# \(key) removed"
                }
                found.insert("api_key")
            case _ where baseURLNames.contains(key):
                if !config.baseURL.isEmpty, let tomlKey = config.baseURLTOMLName {
                    lines[i] = "\(tomlKey) = \"\(config.baseURL)\""
                } else {
                    lines[i] = "# \(key) removed"
                }
                found.insert("base_url")
            default: break
            }
        }

        // Append missing keys
        if !found.contains("papers_dir"), !config.papersDir.isEmpty {
            lines.append("papers_dir = \"\(config.papersDir)\"")
        }
        if !found.contains("provider"), !config.provider.isEmpty {
            lines.append("provider = \"\(config.provider)\"")
        }
        if !found.contains("model"), !config.model.isEmpty {
            lines.append("model = \"\(config.model)\"")
        }
        if !found.contains("api_key"), !config.apiKey.isEmpty {
            lines.append("\(config.apiKeyTOMLName) = \"\(config.apiKey)\"")
        }
        if !found.contains("base_url"), !config.baseURL.isEmpty, let key = config.baseURLTOMLName {
            lines.append("\(key) = \"\(config.baseURL)\"")
        }
        if !found.contains("template"), !config.template.isEmpty, config.template != "default" {
            lines.append("template = \"\(config.template)\"")
        }
        if !found.contains("database_path"), !config.databasePath.isEmpty, config.databasePath != AppConfig.defaultDatabasePath {
            lines.append("database_path = \"\(config.databasePath)\"")
        }

        return lines
    }
}
