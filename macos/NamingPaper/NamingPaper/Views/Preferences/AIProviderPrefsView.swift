import SwiftUI

struct SavedProvider: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var provider: String
    var model: String
    var apiKey: String
}

struct AIProviderPrefsView: View {
    @AppStorage("aiProvider") private var activeProvider: String = "ollama"
    @AppStorage("aiModel") private var activeModel: String = ""
    @State private var savedProviders: [SavedProvider] = []
    @State private var selectedID: UUID?

    // Edit fields
    @State private var editName: String = ""
    @State private var editProvider: String = "ollama"
    @State private var editModel: String = ""
    @State private var editApiKey: String = ""
    @State private var saveConfirmation: Bool = false

    private let providers = ["ollama", "omlx", "claude", "openai", "gemini"]

    var body: some View {
        HSplitView {
            // Left: saved providers list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(savedProviders) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .fontWeight(isActive(item) ? .semibold : .regular)
                                Text(item.provider.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isActive(item) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        .tag(item.id)
                        .contextMenu {
                            Button("Use This Provider") { activate(item) }
                            Divider()
                            Button("Delete", role: .destructive) { delete(item) }
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 8) {
                    Button {
                        addNew()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add new provider")

                    Button {
                        if let id = selectedID {
                            delete(savedProviders.first { $0.id == id })
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedID == nil)
                    .help("Remove selected provider")

                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 160, maxWidth: 200)

            // Right: edit form
            Form {
                Section("Configuration") {
                    TextField("Name", text: $editName, prompt: Text("Model 1"))
                        .textFieldStyle(.roundedBorder)

                    Picker("AI Provider", selection: $editProvider) {
                        ForEach(providers, id: \.self) { p in
                            Text(p.capitalized).tag(p)
                        }
                    }

                    TextField("Model Name", text: $editModel, prompt: Text("Default"))
                        .textFieldStyle(.roundedBorder)
                }

                Section("API Key") {
                    SecureField("API Key", text: $editApiKey, prompt: Text(apiKeyPlaceholder))
                        .textFieldStyle(.roundedBorder)

                    Text("Stored in ~/.namingpaper/config.toml")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Button("Save") {
                            saveCurrentEdit()
                            saveConfirmation = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                saveConfirmation = false
                            }
                        }
                        .disabled(selectedID == nil)

                        Button("Use This Provider") {
                            saveCurrentEdit()
                            if let id = selectedID, let item = savedProviders.first(where: { $0.id == id }) {
                                activate(item)
                            }
                        }
                        .disabled(selectedID == nil)

                        if saveConfirmation {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
            .frame(minWidth: 300)
        }
        .frame(minHeight: 300)
        .onAppear { loadSavedProviders() }
        .onChange(of: selectedID) { _, newID in
            if let id = newID, let item = savedProviders.first(where: { $0.id == id }) {
                editName = item.name
                editProvider = item.provider
                editModel = item.model
                editApiKey = item.apiKey
            }
        }
    }

    private var apiKeyPlaceholder: String {
        switch editProvider {
        case "ollama": return "Not required for Ollama"
        case "omlx": return "Optional — only if oMLX has --api-key set"
        default: return "Enter \(editProvider.capitalized) API key"
        }
    }

    private func isActive(_ item: SavedProvider) -> Bool {
        item.provider == activeProvider && item.model == activeModel
    }

    // MARK: - Actions

    private func addNew() {
        let index = savedProviders.count + 1
        let new = SavedProvider(name: "Model \(index)", provider: "ollama", model: "", apiKey: "")
        savedProviders.append(new)
        selectedID = new.id
        persistSavedProviders()
    }

    private func delete(_ item: SavedProvider?) {
        guard let item else { return }
        savedProviders.removeAll { $0.id == item.id }
        if selectedID == item.id {
            selectedID = savedProviders.first?.id
        }
        persistSavedProviders()
    }

    private func activate(_ item: SavedProvider) {
        activeProvider = item.provider
        activeModel = item.model
        // Write API key to config.toml
        var config = ConfigService.shared.readConfig()
        config.provider = item.provider
        config.model = item.model
        config.apiKey = item.apiKey
        try? ConfigService.shared.writeConfig(config)
    }

    private func saveCurrentEdit() {
        guard let id = selectedID,
              let idx = savedProviders.firstIndex(where: { $0.id == id }) else { return }
        savedProviders[idx].name = editName.isEmpty ? "Model \(idx + 1)" : editName
        savedProviders[idx].provider = editProvider
        savedProviders[idx].model = editModel
        savedProviders[idx].apiKey = editApiKey
        persistSavedProviders()
    }

    // MARK: - Persistence

    private func loadSavedProviders() {
        if let data = UserDefaults.standard.data(forKey: "savedProviders"),
           let decoded = try? JSONDecoder().decode([SavedProvider].self, from: data) {
            savedProviders = decoded
        }

        // If no saved providers, create one from current config
        if savedProviders.isEmpty {
            let config = ConfigService.shared.readConfig()
            let initial = SavedProvider(
                name: "Model 1",
                provider: config.provider.isEmpty ? "ollama" : config.provider,
                model: config.model,
                apiKey: config.apiKey
            )
            savedProviders = [initial]
            persistSavedProviders()
        }

        selectedID = savedProviders.first?.id
    }

    private func persistSavedProviders() {
        if let data = try? JSONEncoder().encode(savedProviders) {
            UserDefaults.standard.set(data, forKey: "savedProviders")
        }
    }
}
