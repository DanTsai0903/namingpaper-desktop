import SwiftUI

struct SavedProvider: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var provider: String
    var model: String

    // API key stored in Keychain, not serialized to UserDefaults
    var apiKey: String {
        get { KeychainService.load(account: id.uuidString) }
        set { KeychainService.save(key: newValue, account: id.uuidString) }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, provider, model
    }
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
    @State private var nameCollisionWarning: Bool = false

    private let providers = ["ollama", "omlx", "claude", "openai", "gemini"]

    private func providerDisplayName(_ id: String) -> String {
        switch id {
        case "omlx": return "oMLX"
        case "ollama": return "ollama"
        default: return id.capitalized
        }
    }

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
                                Text(providerDisplayName(item.provider))
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

                HStack(spacing: 4) {
                    Button {
                        addNew()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("Add new provider")

                    Button {
                        if let id = selectedID {
                            delete(savedProviders.first { $0.id == id })
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedID == nil)
                    .help("Remove selected provider")

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(minWidth: 160, maxWidth: 200)

            // Right: edit form
            Form {
                Section("Configuration") {
                    TextField("Name", text: $editName, prompt: Text("Model 1"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: editName) { _, newName in
                            nameCollisionWarning = hasNameCollision(newName)
                        }

                    if nameCollisionWarning {
                        Text("A model with this name already exists")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker("AI Provider", selection: $editProvider) {
                        ForEach(providers, id: \.self) { p in
                            Text(providerDisplayName(p)).tag(p)
                        }
                    }

                    TextField("Model Name", text: $editModel, prompt: Text("Default"))
                        .textFieldStyle(.roundedBorder)
                }

                Section("API Key") {
                    SecureField("API Key", text: $editApiKey, prompt: Text(apiKeyPlaceholder))
                        .textFieldStyle(.roundedBorder)

                    Text("Stored securely in Keychain")
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
                        .disabled(selectedID == nil || nameCollisionWarning)

                        Button("Use This Provider") {
                            saveCurrentEdit()
                            if let id = selectedID, let item = savedProviders.first(where: { $0.id == id }) {
                                activate(item)
                            }
                        }
                        .disabled(selectedID == nil || nameCollisionWarning)

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
        case "ollama": return "Not required for ollama"
        case "omlx": return "Optional — only if oMLX has --api-key set"
        default: return "Enter \(providerDisplayName(editProvider)) API key"
        }
    }

    private func isActive(_ item: SavedProvider) -> Bool {
        item.provider == activeProvider && item.model == activeModel
    }

    // MARK: - Actions

    private func addNew() {
        let name = nextUniqueName()
        let new = SavedProvider(name: name, provider: "ollama", model: "")
        savedProviders.append(new)
        selectedID = new.id
        persistSavedProviders()
    }

    private func nextUniqueName() -> String {
        let existingNames = Set(savedProviders.map { $0.name })
        var index = savedProviders.count + 1
        while existingNames.contains("Model \(index)") {
            index += 1
        }
        return "Model \(index)"
    }

    private func hasNameCollision(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return savedProviders.contains { $0.id != selectedID && $0.name == trimmed }
    }

    private func delete(_ item: SavedProvider?) {
        guard let item else { return }
        // If deleting the active model, clear the CLI's well-known API key
        if isActive(item) {
            let config = ConfigService.shared.readConfig()
            KeychainService.delete(account: config.apiKeyTOMLName)
        }
        KeychainService.delete(account: item.id.uuidString)
        savedProviders.removeAll { $0.id == item.id }
        if selectedID == item.id {
            selectedID = savedProviders.first?.id
        }
        persistSavedProviders()
    }

    private func activate(_ item: SavedProvider) {
        activeProvider = item.provider
        activeModel = item.model
        // Write provider/model to config.toml (no API key)
        var config = ConfigService.shared.readConfig()
        config.provider = item.provider
        config.model = item.model
        config.apiKey = ""  // clear any existing key from config.toml
        try? ConfigService.shared.writeConfig(config)
        // Store API key in Keychain with well-known account so the CLI can read it
        KeychainService.save(key: item.apiKey, account: config.apiKeyTOMLName)
    }

    private func saveCurrentEdit() {
        guard let id = selectedID,
              let idx = savedProviders.firstIndex(where: { $0.id == id }) else { return }
        let trimmedName = editName.trimmingCharacters(in: .whitespaces)
        guard !hasNameCollision(trimmedName) else { return }
        savedProviders[idx].name = trimmedName.isEmpty ? nextUniqueName() : trimmedName
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
            var initial = SavedProvider(
                name: "Model 1",
                provider: config.provider.isEmpty ? "ollama" : config.provider,
                model: config.model
            )
            initial.apiKey = config.apiKey
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
