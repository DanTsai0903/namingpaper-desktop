import SwiftUI

struct AIProviderPrefsView: View {
    @AppStorage("aiProvider") private var provider: String = "ollama"
    @AppStorage("aiModel") private var model: String = ""
    @State private var apiKey: String = ""

    private let providers = ["ollama", "claude", "openai", "gemini"]

    var body: some View {
        Form {
            Section("Provider") {
                Picker("AI Provider", selection: $provider) {
                    ForEach(providers, id: \.self) { p in
                        Text(p.capitalized).tag(p)
                    }
                }

                TextField("Model Name", text: $model, prompt: Text("Default"))
                    .textFieldStyle(.roundedBorder)
            }

            Section("API Key") {
                SecureField("API Key", text: $apiKey, prompt: Text("Not required for Ollama"))
                    .textFieldStyle(.roundedBorder)

                Text("API key is stored in the config file at ~/.namingpaper/config.toml")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear {
            let config = ConfigService.shared.readConfig()
            if provider.isEmpty { provider = config.provider }
            if model.isEmpty { model = config.model }
            apiKey = config.apiKey
        }
        .onDisappear {
            // Save to config file
            var config = ConfigService.shared.readConfig()
            config.provider = provider
            config.model = model
            config.apiKey = apiKey
            try? ConfigService.shared.writeConfig(config)
        }
    }
}
