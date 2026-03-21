import SwiftUI

struct GeneralPrefsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("authorDisplay") private var authorDisplay: String = "last"
    @AppStorage("journalDisplay") private var journalDisplay: String = "full"
    @AppStorage("appLanguage") private var appLanguage: String = "system"
    @State private var papersDir: String = ""
    @State private var showMigratePicker = false
    @State private var isMigrating = false
    @State private var migrationError: String?
    @State private var pendingMigrationPath: String?
    @State private var showNotEmptyAlert = false
    @State private var showRelaunchAlert = false

    private let supportedLanguages: [(tag: String, name: String)] = [
        ("system", "System"),
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("es", "Español"),
        ("ja", "日本語"),
        ("ko", "한국어"),
    ]

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

            Section {
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
                Picker("Language", selection: $appLanguage) {
                    ForEach(supportedLanguages, id: \.tag) { lang in
                        Text(lang.name).tag(lang.tag)
                    }
                }
                .onChange(of: appLanguage) { _, newValue in
                    setLanguage(newValue)
                }

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
        .alert("Relaunch to Apply", isPresented: $showRelaunchAlert) {
            Button("Relaunch Now") { relaunchApp() }
            Button("Later", role: .cancel) { }
        } message: {
            Text("The app needs to relaunch for the language change to take effect.")
        }
    }

    private func setLanguage(_ tag: String) {
        if tag == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([tag], forKey: "AppleLanguages")
        }
        showRelaunchAlert = true
    }

    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        NSApp.terminate(nil)
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
                    migrationError = String(localized: "Migration failed: \(error.localizedDescription)")
                    isMigrating = false
                }
            }
        }
    }
}
