import Foundation

enum BackupFrequency: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    /// Calendar interval in seconds for the LaunchAgent
    var calendarInterval: [String: Int] {
        switch self {
        case .daily: return ["Hour": 2, "Minute": 0]    // 2:00 AM daily
        case .weekly: return ["Weekday": 1, "Hour": 2, "Minute": 0]  // Sunday 2:00 AM
        case .monthly: return ["Day": 1, "Hour": 2, "Minute": 0]     // 1st of month 2:00 AM
        }
    }
}

struct BackupSettings: Codable {
    var destinationPath: String
    var frequency: String  // raw value of BackupFrequency
    var retentionCount: Int
    var isAutoBackupEnabled: Bool

    static let `default` = BackupSettings(
        destinationPath: "",
        frequency: BackupFrequency.weekly.rawValue,
        retentionCount: 5,
        isAutoBackupEnabled: false
    )

    var frequencyEnum: BackupFrequency {
        BackupFrequency(rawValue: frequency) ?? .weekly
    }
}

class BackupScheduler {
    static let shared = BackupScheduler()

    private let settingsURL: URL
    private let launchAgentLabel = "com.namingpaper.backup"
    private let launchAgentDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        settingsURL = home.appendingPathComponent(".namingpaper/backup-settings.json")
        launchAgentDir = home.appendingPathComponent("Library/LaunchAgents")
    }

    private var launchAgentURL: URL {
        launchAgentDir.appendingPathComponent("\(launchAgentLabel).plist")
    }

    // MARK: - Settings

    func readSettings() -> BackupSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(BackupSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func writeSettings(_ settings: BackupSettings) throws {
        let dir = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }

    // MARK: - LaunchAgent Management

    /// Installs a LaunchAgent plist for automatic backups at the configured frequency.
    func installLaunchAgent(settings: BackupSettings) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: launchAgentDir, withIntermediateDirectories: true)

        let frequency = settings.frequencyEnum

        // Build the plist
        // The agent runs the app with a --backup flag via open command
        let appPath = Bundle.main.bundlePath
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [
                "/usr/bin/open",
                "-a", appPath,
                "--args", "--backup-now"
            ],
            "StartCalendarInterval": frequency.calendarInterval,
            "StandardOutPath": "/tmp/namingpaper-backup.log",
            "StandardErrorPath": "/tmp/namingpaper-backup-error.log"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)

        // Load the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", launchAgentURL.path]
        try process.run()
        process.waitUntilExit()
    }

    /// Removes the LaunchAgent plist and unloads it.
    func removeLaunchAgent() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: launchAgentURL.path) else { return }

        // Unload first
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", launchAgentURL.path]
        try? process.run()
        process.waitUntilExit()

        // Remove the file
        try fm.removeItem(at: launchAgentURL)
    }

    /// Updates the LaunchAgent based on current settings.
    /// If auto-backup is enabled, installs/updates the agent. If disabled, removes it.
    func updateSchedule(settings: BackupSettings) throws {
        if settings.isAutoBackupEnabled && !settings.destinationPath.isEmpty {
            // Remove old agent first to ensure clean reload
            try? removeLaunchAgent()
            try installLaunchAgent(settings: settings)
        } else {
            try removeLaunchAgent()
        }
    }
}
