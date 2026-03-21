import SwiftUI

struct AddPaperSheet: View {
    @Environment(LibraryViewModel.self) var viewModel
    @Environment(\.dismiss) var dismiss

    @State private var savedProviders: [SavedProvider] = []
    @State private var templates: [SavedTemplate] = []

    private var builtInTemplateNames: [String] { ["default", "compact", "full", "simple"] }

    private func providerDisplayName(_ id: String) -> String {
        switch id {
        case "omlx": return "oMLX"
        case "ollama": return "ollama"
        default: return id.capitalized
        }
    }

    var body: some View {
        @Bindable var addVM = viewModel.addPaperViewModel

        VStack(spacing: 0) {
            // Header
            HStack {
                Text(headerTitle)
                    .font(.headline)
                Spacer()
                Text("\(addVM.items.count) file\(addVM.items.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding()

            Divider()

            // Phase content
            switch addVM.phase {
            case .configure:
                configureView
            case .processing:
                processingView
            case .review:
                reviewView
            }
        }
        .frame(minWidth: 600, minHeight: 400, maxHeight: 650)
        .onAppear {
            addVM.existingCategories = viewModel.categories.map(\.name)
            if let data = UserDefaults.standard.data(forKey: "savedProviders"),
               let decoded = try? JSONDecoder().decode([SavedProvider].self, from: data) {
                savedProviders = decoded
            }
            if let data = UserDefaults.standard.data(forKey: "savedTemplates"),
               let decoded = try? JSONDecoder().decode([SavedTemplate].self, from: data) {
                templates = decoded
            } else {
                templates = builtInTemplateNames.map {
                    SavedTemplate(name: $0, pattern: "", isBuiltIn: true)
                }
            }
        }
    }

    private var headerTitle: String {
        switch viewModel.addPaperViewModel.phase {
        case .configure: return "Configure"
        case .processing: return "Processing"
        case .review: return "Review Results"
        }
    }

    // MARK: - Configure Phase

    private var configureView: some View {
        @Bindable var addVM = viewModel.addPaperViewModel

        return VStack(spacing: 12) {
            // File list
            List {
                ForEach(addVM.items) { item in
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)
                        Text(item.filename)
                            .lineLimit(1)
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 150)

            // Options
            Form {
                Picker("Model", selection: $addVM.options.selectedSavedProviderID) {
                    ForEach(savedProviders) { sp in
                        Text("\(sp.name) (\(providerDisplayName(sp.provider)))")
                            .tag(UUID?.some(sp.id))
                    }
                }
                .onChange(of: addVM.options.selectedSavedProviderID) { _, newID in
                    if let id = newID, let sp = savedProviders.first(where: { $0.id == id }) {
                        addVM.options.provider = sp.provider
                        addVM.options.model = sp.model
                        addVM.options.ocrModel = sp.ocrModel
                        // Set the API key for the CLI via Keychain
                        let config = ConfigService.shared.readConfig()
                        KeychainService.save(key: sp.apiKey, account: config.apiKeyTOMLName)
                    } else {
                        addVM.options.provider = ""
                        addVM.options.model = ""
                        addVM.options.ocrModel = ""
                    }
                }

                Picker("Name Format", selection: $addVM.options.template) {
                    ForEach(templates) { t in
                        let label: String = t.name
                        Text(label).tag(t.isBuiltIn ? t.name : t.pattern)
                    }
                }

                Toggle("Rename file", isOn: $addVM.options.renameFile)

                Toggle("Enable reasoning", isOn: $addVM.options.reasoning)

                Toggle("Prioritize existing categories", isOn: $addVM.options.categoryPriority)
            }
            .formStyle(.grouped)

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Start Processing") {
                    addVM.startProcessing()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(addVM.items.isEmpty)
            }
            .padding()
        }
    }

    // MARK: - Processing Phase

    private var processingView: some View {
        let addVM = viewModel.addPaperViewModel

        return VStack(spacing: 12) {
            List {
                ForEach(addVM.items) { item in
                    HStack {
                        stageIcon(item.stage)

                        VStack(alignment: .leading) {
                            Text(item.filename)
                                .lineLimit(1)
                            if let error = item.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(nil)
                                    .textSelection(.enabled)
                            } else {
                                Text(item.stage.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                }
            }

            HStack {
                if addVM.isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Review Phase

    private var reviewView: some View {
        @Bindable var addVM = viewModel.addPaperViewModel

        return VStack(spacing: 12) {
            List {
                ForEach($addVM.items) { $item in
                    if let _ = item.result {
                        reviewRow(item: $item)
                    } else if item.stage == .failed {
                        errorRow(item: item)
                    }
                }
            }

            // Buttons
            HStack {
                if addVM.hasCommitted {
                    // Post-commit: show Close button
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    if addVM.isCommitting {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Adding...")
                            .foregroundStyle(.secondary)
                    }

                    Button("Add to Library") {
                        addVM.commitPapers()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!addVM.hasSuccessfulResults || addVM.isCommitting)
                }
            }
            .padding()
        }
        .onChange(of: addVM.hasCommitted) { _, committed in
            if committed {
                Task { await viewModel.forceRefresh() }
            }
        }
    }

    @ViewBuilder
    private func reviewRow(item: Binding<AddPaperItem>) -> some View {
        let addVM = viewModel.addPaperViewModel
        let currentItem = item.wrappedValue
        let itemID = currentItem.id

        VStack(alignment: .leading, spacing: 6) {
            if let result = currentItem.result {
                // Metadata summary line with confidence
                HStack(spacing: 6) {
                    let meta = [result.title, result.authors, result.year, result.journal]
                        .filter { !$0.isEmpty }
                        .joined(separator: " \u{2022} ")
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let confidence = result.confidence {
                        confidenceBadge(confidence)
                    }
                }

                // Editable name
                if addVM.options.renameFile {
                    TextField("Filename", text: Binding(
                        get: { addVM.items.first(where: { $0.id == itemID })?.result?.editedName ?? result.editedName },
                        set: { newValue in
                            if let idx = addVM.items.firstIndex(where: { $0.id == itemID }) {
                                addVM.items[idx].result?.editedName = newValue
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                } else {
                    Text(currentItem.filename)
                        .foregroundStyle(.secondary)
                }

                // Editable category (free-text with dropdown)
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    TextField("Category", text: Binding(
                        get: { addVM.items.first(where: { $0.id == itemID })?.result?.editedCategory ?? result.editedCategory },
                        set: { newValue in
                            if let idx = addVM.items.firstIndex(where: { $0.id == itemID }) {
                                addVM.items[idx].result?.editedCategory = newValue
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)

                    let categories = buildCategoryList(suggested: result.suggestedCategory)
                    Menu {
                        ForEach(categories, id: \.self) { cat in
                            Button(cat) {
                                if let idx = addVM.items.firstIndex(where: { $0.id == itemID }) {
                                    addVM.items[idx].result?.editedCategory = cat
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                }
            }

            // Commit status / error
            if currentItem.stage == .extracting && addVM.isCommitting {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5)
                    Text("Adding...").font(.caption).foregroundStyle(.secondary)
                }
            } else if currentItem.stage == .failed, let error = currentItem.error {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(nil)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(error, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy error message")
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func errorRow(item: AddPaperItem) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .lineLimit(1)
                if let error = item.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(nil)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            if let error = item.error {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy error message")
            }
        }
        .padding(.vertical, 4)
    }

    private func buildCategoryList(suggested: String?) -> [String] {
        var cats = viewModel.categories.map(\.name)
        if let suggested, !suggested.isEmpty, !cats.contains(suggested) {
            cats.insert(suggested, at: 0)
        }
        return cats
    }

    @ViewBuilder
    private func stageIcon(_ stage: AddStage) -> some View {
        switch stage {
        case .extracting, .summarizing, .categorizing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 20, height: 20)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 20, height: 20)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private func confidenceBadge(_ confidence: Double) -> some View {
        let pct = Int(confidence * 100)
        let color: Color = confidence >= 0.8 ? .green : confidence >= 0.5 ? .orange : .red
        Text("\(pct)%")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
