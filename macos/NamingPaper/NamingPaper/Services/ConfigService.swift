import Foundation

struct AppConfig {
    var papersDir: String
    var provider: String
    var model: String
    var apiKey: String
    var cliPath: String

    static let `default` = AppConfig(
        papersDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Papers").path,
        provider: "ollama",
        model: "",
        apiKey: "",
        cliPath: ""
    )
}

class ConfigService {
    static let shared = ConfigService()

    private let configPath: String

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
    }

    // MARK: - Minimal TOML Parser

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
            case "api_key", "gemini_api_key", "openai_api_key", "claude_api_key":
                config.apiKey = value
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

        return lines
    }
}
