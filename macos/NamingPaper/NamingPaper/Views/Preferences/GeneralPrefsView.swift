import SwiftUI

struct GeneralPrefsView: View {
    @AppStorage("papersDir") private var papersDir: String = ""
    @AppStorage("cliPath") private var cliPath: String = ""
    @AppStorage("appearance") private var appearance: String = "system"
    @State private var showDirPicker = false
    @State private var showCLIPicker = false

    var body: some View {
        Form {
            Section("Library") {
                HStack {
                    TextField("Papers Directory", text: $papersDir)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") { showDirPicker = true }
                        .fileImporter(
                            isPresented: $showDirPicker,
                            allowedContentTypes: [.folder]
                        ) { result in
                            if case .success(let url) = result {
                                papersDir = url.path
                            }
                        }
                }

                HStack {
                    TextField("CLI Path", text: $cliPath, prompt: Text("Auto-detect"))
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") { showCLIPicker = true }
                        .fileImporter(
                            isPresented: $showCLIPicker,
                            allowedContentTypes: [.unixExecutable]
                        ) { result in
                            if case .success(let url) = result {
                                cliPath = url.path
                            }
                        }
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
            if papersDir.isEmpty {
                let config = ConfigService.shared.readConfig()
                papersDir = config.papersDir
            }
        }
    }
}
