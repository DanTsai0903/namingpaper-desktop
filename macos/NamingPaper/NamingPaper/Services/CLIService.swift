import Foundation

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
}

actor CLIService {
    static let shared = CLIService()

    private var cliPath: String?

    // MARK: - CLI Discovery

    func findCLI(userConfiguredPath: String? = nil) -> String? {
        // 1. User-configured path
        if let path = userConfiguredPath, !path.isEmpty,
           FileManager.default.isExecutableFile(atPath: path) {
            cliPath = path
            return path
        }

        // 2. ~/.local/bin/namingpaper (uv/pipx default)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin/namingpaper").path
        if FileManager.default.isExecutableFile(atPath: localBin) {
            cliPath = localBin
            return localBin
        }

        // 3. Search $PATH
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

                // Inherit a minimal environment for Python/uv to work
                var env = ProcessInfo.processInfo.environment
                env["PYTHONUNBUFFERED"] = "1"
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let result = CLIResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? ""
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: CLIError.executionFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Add Paper

    func addPaper(path: String) async throws -> CLIResult {
        try await run(arguments: ["add", path, "--execute", "--yes"])
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
            return "namingpaper CLI not found. Configure the path in Preferences."
        case .executionFailed(let msg):
            return "CLI execution failed: \(msg)"
        }
    }
}
