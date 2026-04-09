import Foundation
import SwiftUI

struct CLIResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var success: Bool { exitCode == 0 }
}

enum AddStage: String {
    case extracting = "Extracting"
    case summarizing = "Summarizing"
    case categorizing = "Categorizing"
    case done = "Done"
    case failed = "Failed"

    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

enum AddFlowPhase {
    case configure
    case processing
    case review
}

struct AddPaperResult {
    var suggestedName: String
    var suggestedCategory: String
    var editedName: String
    var editedCategory: String
    var title: String
    var authors: String
    var year: String
    var journal: String
    var journalFull: String
    var confidence: Double?
    /// Cached JSON metadata from dry-run to pass on commit (avoids re-extraction)
    var cachedMetadataJSON: String?

    init(from dryRun: CLIService.DryRunResult) {
        self.suggestedName = dryRun.suggestedName
        self.suggestedCategory = dryRun.suggestedCategory
        self.editedName = dryRun.suggestedName
        self.editedCategory = dryRun.suggestedCategory
        self.title = dryRun.title
        self.authors = dryRun.authors
        self.year = dryRun.year
        self.journal = dryRun.journal
        self.journalFull = dryRun.journal
        self.confidence = nil
    }

    init(from paper: CLIService.AddPaperJSONPaper) {
        self.suggestedName = paper.filename
        self.suggestedCategory = paper.category ?? ""
        self.editedName = paper.filename
        self.editedCategory = paper.category ?? ""
        self.title = paper.title
        self.authors = paper.authors.joined(separator: ", ")
        self.year = String(paper.year)
        self.journal = paper.journalAbbrev ?? paper.journal
        self.journalFull = paper.journal
        self.confidence = paper.confidence

        // Build the cached metadata JSON using Codable for type safety
        let cached = PreExtractedMetadata(
            title: paper.title,
            authors: paper.authors,
            authorsFullNames: paper.authorsFullNames,
            year: paper.year,
            journal: paper.journal,
            journalAbbrev: paper.journalAbbrev,
            summary: paper.summary,
            keywords: paper.keywords ?? [],
            category: paper.category,
            confidence: paper.confidence
        )
        if let data = try? JSONEncoder().encode(cached),
           let str = String(data: data, encoding: .utf8) {
            self.cachedMetadataJSON = str
        }
    }
}

/// Codable struct for serializing cached metadata to pass via --metadata-json.
/// Keys match what the Python CLI expects in `pre_extracted`.
struct PreExtractedMetadata: Codable {
    let title: String
    let authors: [String]
    let authorsFullNames: [String]
    let year: Int
    let journal: String
    let journalAbbrev: String?
    let summary: String?
    let keywords: [String]
    let category: String?
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case title, authors, year, journal, summary, keywords, category, confidence
        case authorsFullNames = "authors_full"
        case journalAbbrev = "journal_abbrev"
    }
}

struct AddPaperOptions {
    var selectedSavedProviderID: UUID?
    var provider: String = ""
    var model: String = ""
    var ocrModel: String = ""
    var template: String = ConfigService.shared.readConfig().template
    var categoryPriority: Bool = false
    var reasoning: Bool = false
    var renameFile: Bool = true
}

actor CLIService {
    static let shared = CLIService()

    /// Maps NAMINGPAPER_* env var names (read by the CLI's Pydantic Settings) to the
    /// Keychain account names used by KeychainService. Setting these avoids the CLI
    /// calling `/usr/bin/security`, which triggers Keychain prompts on every run.
    static let providerKeyAccounts: [String: String] = [
        "NAMINGPAPER_ANTHROPIC_API_KEY": "anthropic_api_key",
        "NAMINGPAPER_OPENAI_API_KEY": "openai_api_key",
        "NAMINGPAPER_GEMINI_API_KEY": "gemini_api_key",
        "NAMINGPAPER_OMLX_API_KEY": "omlx_api_key",
        "NAMINGPAPER_LMSTUDIO_API_KEY": "lmstudio_api_key",
    ]

    private var cliPath: String?

    // MARK: - CLI Discovery

    func findCLI() -> String? {
        // 1. ~/.local/bin/namingpaper (uv tool / pipx default)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin/namingpaper").path
        if FileManager.default.isExecutableFile(atPath: localBin) {
            cliPath = localBin
            return localBin
        }

        // 2. Search $PATH
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = "\(dir)/namingpaper"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    cliPath = candidate
                    return candidate
                }
            }
        }

        return nil
    }

    var isAvailable: Bool {
        cliPath != nil || findCLI() != nil
    }

    // MARK: - Run Command

    func run(arguments: [String]) async throws -> CLIResult {
        guard let path = cliPath ?? findCLI() else {
            throw CLIError.notFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                // Inherit environment; disable Rich color/formatting for pipe output
                var env = ProcessInfo.processInfo.environment
                env["PYTHONUNBUFFERED"] = "1"
                env["NO_COLOR"] = "1"
                env["TERM"] = "dumb"
                env["COLUMNS"] = "500"

                // Pass API keys via env vars so the CLI's Pydantic Settings picks them up
                // instead of shelling out to `/usr/bin/security`, which re-prompts every run
                // (the Keychain ACL on items created by this app doesn't include `security`).
                for (envName, account) in Self.providerKeyAccounts {
                    let key = KeychainService.load(account: account)
                    if !key.isEmpty {
                        env[envName] = key
                    }
                }

                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()

                    // Read both pipes concurrently to avoid deadlock when
                    // one pipe's buffer fills while we block reading the other.
                    var stdoutData = Data()
                    var stderrData = Data()

                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.wait()

                    process.waitUntilExit()

                    let result = CLIResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? ""
                    )

                    if !result.success {
                        NSLog("[namingpaper] exit=%d stderr=%@ stdout=%@",
                              result.exitCode, result.stderr, result.stdout)
                    }

                    continuation.resume(returning: result)
                } catch {
                    NSLog("[namingpaper] launch error: %@", error.localizedDescription)
                    continuation.resume(throwing: CLIError.executionFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - JSON Result Types

    struct AddPaperJSONPaper: Codable {
        let title: String
        let authors: [String]
        let authorsFullNames: [String]
        let year: Int
        let journal: String
        let journalAbbrev: String?
        let summary: String?
        let keywords: [String]?
        let category: String?
        let filename: String
        let destination: String
        let confidence: Double?

        enum CodingKeys: String, CodingKey {
            case title, authors, year, journal, summary, keywords, category, filename, destination, confidence
            case authorsFullNames = "authors_full"
            case journalAbbrev = "journal_abbrev"
        }
    }

    struct AddPaperJSONResult: Codable {
        let status: String
        let source: String?
        let error: String?
        let existingId: String?
        let paper: AddPaperJSONPaper?

        enum CodingKeys: String, CodingKey {
            case status, source, error, paper
            case existingId = "existing_id"
        }
    }

    // MARK: - Add Paper

    func addPaper(
        path: String,
        provider: String? = nil,
        model: String? = nil,
        ocrModel: String? = nil,
        category: String? = nil,
        template: String? = nil,
        filename: String? = nil,
        noRename: Bool = false,
        reasoning: Bool? = nil,
        metadataJSON: String? = nil
    ) async throws -> CLIResult {
        var args = ["add", path, "--execute", "--yes", "--copy"]
        if let provider, !provider.isEmpty {
            args += ["--provider", provider]
        }
        if let model, !model.isEmpty {
            args += ["--model", model]
        }
        if let ocrModel, !ocrModel.isEmpty {
            args += ["--ocr-model", ocrModel]
        }
        if let category, !category.isEmpty {
            args += ["--category", category]
        }
        if let template, !template.isEmpty {
            args += ["--template", template]
        }
        if let filename, !filename.isEmpty {
            args += ["--filename", filename]
        }
        if noRename {
            args.append("--no-rename")
        }
        if let reasoning {
            args.append(reasoning ? "--reasoning" : "--no-reasoning")
        }
        if let metadataJSON, !metadataJSON.isEmpty {
            args += ["--metadata-json", metadataJSON]
        }
        return try await run(arguments: args)
    }

    // MARK: - Dry-Run Add Paper

    struct DryRunResult {
        let suggestedName: String
        let suggestedCategory: String
        let title: String
        let authors: String
        let year: String
        let journal: String
        let rawOutput: String
    }

    func dryRunAddPaper(
        path: String,
        provider: String? = nil,
        model: String? = nil,
        ocrModel: String? = nil,
        template: String? = nil,
        noRename: Bool = false,
        reasoning: Bool? = nil
    ) async throws -> CLIResult {
        var args = ["add", path, "--copy", "--yes", "--json"]
        if let provider, !provider.isEmpty {
            args += ["--provider", provider]
        }
        if let model, !model.isEmpty {
            args += ["--model", model]
        }
        if let ocrModel, !ocrModel.isEmpty {
            args += ["--ocr-model", ocrModel]
        }
        if let template, !template.isEmpty {
            args += ["--template", template]
        }
        if noRename {
            args.append("--no-rename")
        }
        if let reasoning {
            args.append(reasoning ? "--reasoning" : "--no-reasoning")
        }
        return try await run(arguments: args)
    }

    /// Parse JSON output from `add --json`. Returns nil if JSON parsing fails (fallback to Rich table).
    static func parseJSONOutput(_ stdout: String) -> AddPaperJSONResult? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AddPaperJSONResult.self, from: data)
    }

    static func parseDryRunOutput(_ stdout: String) -> DryRunResult? {
        // Rich table output uses Unicode box-drawing borders:
        //   │ Title       │ The Macroeconomic Effects of False Announcements │
        //   │ Authors     │ Oh, Waldman                                      │
        //   │ Destination │ /Users/.../Oh and                                │
        //   │             │ Waldman, (1990, QJE), The Macro....pdf           │
        // Multi-line values have an empty field column on continuation lines.
        let fields = ["Title", "Authors", "Year", "Journal", "Category", "Destination"]
        var parsed: [String: String] = [:]
        var currentField: String? = nil

        for line in stdout.components(separatedBy: "\n") {
            // Split on │ (Unicode box-drawing vertical bar)
            let parts = line.components(separatedBy: "│")
            // A valid table row has 4 parts: ["", " Field ", " Value ", ""]
            guard parts.count >= 3 else {
                currentField = nil
                continue
            }

            let fieldCol = parts[1].trimmingCharacters(in: .whitespaces)
            let valueCol = parts[2].trimmingCharacters(in: .whitespaces)

            if !fieldCol.isEmpty {
                // New field row
                if fields.contains(fieldCol) {
                    currentField = fieldCol
                    parsed[fieldCol] = valueCol
                } else {
                    currentField = nil
                }
            } else if let field = currentField, !valueCol.isEmpty {
                // Continuation line for multi-line value
                parsed[field] = (parsed[field] ?? "") + " " + valueCol
            }
        }

        let destination = parsed["Destination"] ?? ""
        let category = parsed["Category"] ?? ""

        guard !destination.isEmpty || !category.isEmpty else { return nil }

        // Extract filename from the full destination path
        // The path may have been joined from multiple lines
        let suggestedName: String
        if destination.hasSuffix(".pdf") {
            // Find the last path component
            suggestedName = (destination as NSString).lastPathComponent
        } else {
            suggestedName = (destination as NSString).lastPathComponent
        }

        return DryRunResult(
            suggestedName: suggestedName,
            suggestedCategory: category,
            title: parsed["Title"] ?? "",
            authors: parsed["Authors"] ?? "",
            year: parsed["Year"] ?? "",
            journal: parsed["Journal"] ?? "",
            rawOutput: stdout
        )
    }

    // MARK: - Remove Paper

    func removePaper(id: String, deleteFile: Bool = false) async throws -> CLIResult {
        var args = ["remove", id, "--execute", "--yes"]
        if deleteFile {
            args.append("--delete-file")
        }
        return try await run(arguments: args)
    }

    // MARK: - Sync

    func syncLibrary() async throws -> CLIResult {
        try await run(arguments: ["sync", "--execute", "--yes"])
    }
}

enum CLIError: LocalizedError {
    case notFound
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "namingpaper CLI not found. Install it with: uv tool install namingpaper"
        case .executionFailed(let msg):
            return "CLI execution failed: \(msg)"
        }
    }
}
