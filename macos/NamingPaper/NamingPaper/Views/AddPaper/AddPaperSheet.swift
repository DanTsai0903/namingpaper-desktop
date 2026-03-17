import SwiftUI

struct AddPaperSheet: View {
    @Environment(LibraryViewModel.self) var viewModel
    @Environment(\.dismiss) var dismiss

    private let providers = ["", "claude", "openai", "gemini", "ollama", "omlx"]
    private let templates = ["default", "compact", "full", "simple"]

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
                Picker("Provider", selection: $addVM.options.provider) {
                    Text("Default").tag("")
                    ForEach(providers.dropFirst(), id: \.self) { p in
                        Text(p).tag(p)
                    }
                }

                Picker("Name Format", selection: $addVM.options.template) {
                    ForEach(templates, id: \.self) { t in
                        Text(t).tag(t)
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
                    addVM.reset()
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
                        addVM.reset()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        dismiss()
                        addVM.reset()
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

        VStack(alignment: .leading, spacing: 6) {
            if let result = currentItem.result {
                // Metadata summary line
                let meta = [result.title, result.authors, result.year, result.journal]
                    .filter { !$0.isEmpty }
                    .joined(separator: " \u{2022} ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Editable name
                if addVM.options.renameFile {
                    TextField("Filename", text: Binding(
                        get: { item.wrappedValue.result?.editedName ?? result.editedName },
                        set: { item.wrappedValue.result?.editedName = $0 }
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
                        get: { item.wrappedValue.result?.editedCategory ?? result.editedCategory },
                        set: { item.wrappedValue.result?.editedCategory = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)

                    let categories = buildCategoryList(suggested: result.suggestedCategory)
                    Menu {
                        ForEach(categories, id: \.self) { cat in
                            Button(cat) {
                                item.wrappedValue.result?.editedCategory = cat
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
}
