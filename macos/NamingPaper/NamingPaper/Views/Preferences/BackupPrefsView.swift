import SwiftUI

struct BackupPrefsView: View {
    @State private var settings: BackupSettings = .default
    @State private var backups: [BackupInfo] = []
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var backupProgress: BackupProgress?
    @State private var statusMessage = ""
    @State private var showRestoreConfirmation = false
    @State private var selectedRestoreBackup: BackupInfo?

    var body: some View {
        Form {
            // MARK: - Destination
            Section {
                HStack {
                    Text("Backup Location:")
                    Text(settings.destinationPath.isEmpty ? "Not set" : abbreviatePath(settings.destinationPath))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        chooseDestination()
                    }
                }
            }

            // MARK: - Manual Backup
            Section {
                HStack {
                    Button("Back Up Now") {
                        Task { await performBackup() }
                    }
                    .disabled(settings.destinationPath.isEmpty || isBackingUp)

                    if isBackingUp, let progress = backupProgress {
                        ProgressView(value: progress.fractionCompleted)
                            .frame(width: 120)
                        Text("\(progress.completedFiles)/\(progress.totalFiles) files")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .foregroundStyle(statusMessage.contains("Error") ? .red : .secondary)
                        .font(.caption)
                }
            }

            // MARK: - Automatic Backup
            Section {
                Toggle("Automatic Backup", isOn: $settings.isAutoBackupEnabled)
                    .onChange(of: settings.isAutoBackupEnabled) { _, newValue in
                        saveSettings()
                        if !newValue {
                            try? BackupScheduler.shared.removeLaunchAgent()
                        }
                    }
                    .disabled(settings.destinationPath.isEmpty)

                if settings.isAutoBackupEnabled {
                    Picker("Frequency:", selection: $settings.frequency) {
                        ForEach(BackupFrequency.allCases) { freq in
                            Text(freq.displayName).tag(freq.rawValue)
                        }
                    }
                    .onChange(of: settings.frequency) { _, _ in
                        saveSettings()
                    }

                    Stepper("Keep last \(settings.retentionCount) backups", value: $settings.retentionCount, in: 1...50)
                        .onChange(of: settings.retentionCount) { _, _ in
                            saveSettings()
                        }
                }
            }

            // MARK: - Existing Backups
            if !backups.isEmpty {
                Section("Existing Backups") {
                    ForEach(backups, id: \.url) { backup in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(formatDate(backup.date))
                                    .font(.body)
                                Text(formatSize(backup.sizeBytes))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            Spacer()
                            Button("Restore") {
                                selectedRestoreBackup = backup
                                showRestoreConfirmation = true
                            }
                            .disabled(isRestoring)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            settings = BackupScheduler.shared.readSettings()
            refreshBackupList()
        }
        .alert("Restore from Backup", isPresented: $showRestoreConfirmation) {
            Button("Restore", role: .destructive) {
                if let backup = selectedRestoreBackup {
                    Task { await performRestore(from: backup) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your current library with the backup. A safety backup of your current data will be created first.")
        }
    }

    // MARK: - Actions

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Backup Location"

        if panel.runModal() == .OK, let url = panel.url {
            settings.destinationPath = url.path
            saveSettings()
            refreshBackupList()
        }
    }

    private func performBackup() async {
        guard !settings.destinationPath.isEmpty else { return }
        isBackingUp = true
        statusMessage = ""

        // Subscribe to progress
        let cancellable = BackupService.shared.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { progress in
                backupProgress = progress
            }

        do {
            let destination = URL(fileURLWithPath: settings.destinationPath)
            let backupDir = try await BackupService.shared.createBackup(destination: destination)

            // Retention cleanup
            try? await BackupService.shared.cleanupOldBackups(at: destination, retentionCount: settings.retentionCount)

            statusMessage = "Backup created at \(backupDir.lastPathComponent)"
            refreshBackupList()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        cancellable.cancel()
        isBackingUp = false
        backupProgress = nil
    }

    private func performRestore(from backup: BackupInfo) async {
        isRestoring = true
        statusMessage = ""

        do {
            let safetyDest = URL(fileURLWithPath: settings.destinationPath)
            let missingFiles = try await BackupService.shared.restoreFromBackup(
                backupDir: backup.url,
                safetyBackupDestination: safetyDest
            )

            if missingFiles.isEmpty {
                statusMessage = "Restore complete"
            } else {
                statusMessage = "Restored with \(missingFiles.count) missing files"
            }
            refreshBackupList()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isRestoring = false
    }

    private func saveSettings() {
        try? BackupScheduler.shared.writeSettings(settings)
        try? BackupScheduler.shared.updateSchedule(settings: settings)
    }

    private func refreshBackupList() {
        guard !settings.destinationPath.isEmpty else {
            backups = []
            return
        }
        Task {
            let dest = URL(fileURLWithPath: settings.destinationPath)
            let list = await BackupService.shared.listBackups(at: dest)
            await MainActor.run { backups = list }
        }
    }

    // MARK: - Formatting

    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
