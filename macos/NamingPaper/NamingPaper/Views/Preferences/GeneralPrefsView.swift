import SwiftUI

struct GeneralPrefsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @State private var papersDir: String = ""

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Papers Directory") {
                    Text(papersDir)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .help("Change via CLI: namingpaper config set papers_dir /path")
                }
            }

            Section("Appearance") {
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
    }
}
