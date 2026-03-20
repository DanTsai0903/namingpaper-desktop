import SwiftUI

struct GeneralPrefsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("authorDisplay") private var authorDisplay: String = "last"
    @AppStorage("journalDisplay") private var journalDisplay: String = "full"
    @State private var papersDir: String = ""
    @State private var showMigratePicker = false
    @State private var isMigrating = false
    @State private var migrationError: String?
    @State private var pendingMigrationPath: String?
    @State private var showNotEmptyAlert = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Papers Directory") {
                    HStack {
                        Text(papersDir)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Move...") { showMigratePicker = true }
                            .disabled(isMigrating)
                    }
                }

                if isMigrating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Moving library...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let migrationError {
                    Text(migrationError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Display") {
                Picker("Authors Column", selection: $authorDisplay) {
                    Text("Last Name").tag("last")
                    Text("Full Name").tag("full")
                }

                Picker("Journal Column", selection: $journalDisplay) {
                    Text("Full Name").tag("full")
                    Text("Abbreviation").tag("abbrev")
                }

                Text("Falls back to the other format when the preferred one is not available for a paper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .onAppear {
            let config = ConfigService.shared.readConfig()
            papersDir = config.papersDir
        }
        .fileImporter(
            isPresented: $showMigratePicker,
            allowedContentTypes: [.folder]
        ) { result in
            guard case .success(let url) = result else { return }
            let newPath = url.path
            guard newPath != papersDir else { return }

            // Check if destination folder is empty
            let items = (try? FileManager.default.contentsOfDirectory(atPath: newPath)) ?? []
            let nonHidden = items.filter { !$0.hasPrefix(".") }
            if nonHidden.isEmpty {
                migrateLibrary(to: newPath)
            } else {
                pendingMigrationPath = newPath
                showNotEmptyAlert = true
            }
        }
        .alert("Folder Not Empty", isPresented: $showNotEmptyAlert) {
            Button("Cancel", role: .cancel) {
                pendingMigrationPath = nil
            }
            Button("Move Anyway") {
                if let path = pendingMigrationPath {
                    pendingMigrationPath = nil
                    migrateLibrary(to: path)
                }
            }
        } message: {
            Text("The selected folder already contains files. Existing files with the same name will be kept and library files will be skipped.")
        }
    }

    private func migrateLibrary(to newPath: String) {
        let oldPath = papersDir

        migrationError = nil
        isMigrating = true

        Task.detached {
            do {
                let fm = FileManager.default

                // Ensure destination exists
                try fm.createDirectory(atPath: newPath, withIntermediateDirectories: true)

                // Move contents from old directory to new
                let items = try fm.contentsOfDirectory(atPath: oldPath)
                for item in items {
                    let src = (oldPath as NSString).appendingPathComponent(item)
                    let dst = (newPath as NSString).appendingPathComponent(item)
                    // Skip if destination already has this item
                    if fm.fileExists(atPath: dst) { continue }
                    try fm.moveItem(atPath: src, toPath: dst)
                }

                // Update config.toml
                var config = ConfigService.shared.readConfig()
                config.papersDir = newPath
                try ConfigService.shared.writeConfig(config)

                // Sync DB to update file paths
                _ = try? await CLIService.shared.syncLibrary()

                await MainActor.run {
                    papersDir = newPath
                    isMigrating = false
                    NotificationCenter.default.post(name: .libraryDidMigrate, object: nil)
                }
            } catch {
                await MainActor.run {
                    migrationError = "Migration failed: \(error.localizedDescription)"
                    isMigrating = false
                }
            }
        }
    }
}
