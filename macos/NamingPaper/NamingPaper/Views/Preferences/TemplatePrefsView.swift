import SwiftUI

struct SavedTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var pattern: String
    var isBuiltIn: Bool = false
}

struct TemplatePrefsView: View {
    @State private var templates: [SavedTemplate] = []
    @State private var selectedID: UUID?
    @State private var activeTemplateID: UUID?

    // Edit fields
    @State private var editName: String = ""
    @State private var editPattern: String = ""
    @State private var saveConfirmation: Bool = false
    @State private var nameCollisionWarning: Bool = false

    private let builtInTemplates: [(name: String, pattern: String)] = [
        ("default", "{authors}, ({year}, {journal}), {title}"),
        ("compact", "{authors} ({year}) {title}"),
        ("full", "{authors}, ({year}, {journal_full}), {title}"),
        ("simple", "{authors} - {year} - {title}"),
    ]

    private var selectedTemplate: SavedTemplate? {
        guard let id = selectedID else { return nil }
        return templates.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            templateList
            templateEditor
        }
        .frame(minHeight: 300)
        .onAppear { loadTemplates() }
        .onChange(of: selectedID) { _, newID in
            if let id = newID, let item = templates.first(where: { $0.id == id }) {
                editName = item.name
                editPattern = item.pattern
                nameCollisionWarning = false
            }
        }
    }

    // MARK: - Left Panel

    private var templateList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedID) {
                ForEach(templates) { item in
                    templateRow(item)
                }
            }
            .listStyle(.sidebar)

            Divider()

            listToolbar
        }
        .frame(minWidth: 180, maxWidth: 220)
    }

    private func templateRow(_ item: SavedTemplate) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.callout)
                    .fontWeight(item.id == activeTemplateID ? .semibold : .regular)
                Text(item.pattern)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if item.id == activeTemplateID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .tag(item.id)
        .contextMenu {
            Button("Use This Template") { activate(item) }
            if !item.isBuiltIn {
                Divider()
                Button("Delete", role: .destructive) { delete(item) }
            }
        }
    }

    private var listToolbar: some View {
        HStack(spacing: 4) {
            Button { addNew() } label: {
                Image(systemName: "plus").frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Add new template")

            Button {
                if let t = selectedTemplate, !t.isBuiltIn { delete(t) }
            } label: {
                Image(systemName: "minus").frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(selectedTemplate == nil || selectedTemplate?.isBuiltIn == true)
            .help("Remove selected template")

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Right Panel

    @ViewBuilder
    private var templateEditor: some View {
        if selectedID != nil {
            Form {
                templateFields
                placeholderChips
                previewSection
                actionButtons
            }
            .padding()
            .frame(minWidth: 300)
        } else {
            VStack {
                Spacer()
                Text("Select a template or create a new one")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(minWidth: 300)
        }
    }

    private var templateFields: some View {
        Section("Template") {
            TextField("Name", text: $editName)
                .textFieldStyle(.roundedBorder)
                .disabled(selectedTemplate?.isBuiltIn == true)
                .onChange(of: editName) { _, newName in
                    nameCollisionWarning = hasNameCollision(newName)
                }

            if nameCollisionWarning {
                Text("A template with this name already exists")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField("Pattern", text: $editPattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(selectedTemplate?.isBuiltIn == true)
        }
    }

    private var placeholderChips: some View {
        Section("Insert Placeholder") {
            FlowLayout(spacing: 4) {
                ForEach(TemplatePlaceholder.all, id: \.value) { p in
                    Button(p.label) { editPattern += p.value }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(.caption, design: .monospaced))
                        .disabled(selectedTemplate?.isBuiltIn == true)
                }
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            if let error = templateValidationError(editPattern) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                Text(templatePreview(editPattern))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    private var actionButtons: some View {
        Section {
            HStack {
                if selectedTemplate?.isBuiltIn != true {
                    Button("Save") {
                        saveCurrentEdit()
                        saveConfirmation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            saveConfirmation = false
                        }
                    }
                    .disabled(nameCollisionWarning || templateValidationError(editPattern) != nil)
                }

                Button("Use This Template") {
                    if selectedTemplate?.isBuiltIn != true {
                        saveCurrentEdit()
                    }
                    if let id = selectedID, let item = templates.first(where: { $0.id == id }) {
                        activate(item)
                    }
                }
                .disabled(nameCollisionWarning || templateValidationError(editPattern) != nil)

                if saveConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Helpers

    private static let validPlaceholders: Set<String> = [
        "authors", "authors_full", "authors_abbrev", "year",
        "journal", "journal_abbrev", "journal_full", "title"
    ]

    private func templateValidationError(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\{(\\w+)\\}") else { return nil }
        let matches = regex.matches(in: pattern, range: NSRange(pattern.startIndex..., in: pattern))

        if matches.isEmpty {
            return String(localized: "Template must contain at least one placeholder")
        }

        for match in matches {
            if let range = Range(match.range(at: 1), in: pattern) {
                let name = String(pattern[range])
                if !Self.validPlaceholders.contains(name) {
                    return String(localized: "Invalid placeholder: {\(name)}")
                }
            }
        }
        return nil
    }

    private func templatePreview(_ pattern: String) -> String {
        let sample: [(key: String, val: String)] = [
            ("authors_full", "Eugene F. Fama and Kenneth R. French"),
            ("authors_abbrev", "Fama, E. F. and French, K. R."),
            ("authors", "Fama and French"),
            ("journal_abbrev", "JFE"),
            ("journal_full", "Journal of Financial Economics"),
            ("journal", "JFE"),
            ("year", "1993"),
            ("title", "Common risk factors in the returns on stocks and bonds"),
        ]
        var result = pattern
        for item in sample {
            result = result.replacingOccurrences(of: "{\(item.key)}", with: item.val)
        }
        return result + ".pdf"
    }

    // MARK: - Actions

    private func addNew() {
        let name = nextUniqueName()
        let new = SavedTemplate(name: name, pattern: "{authors} ({year}) {title}")
        templates.append(new)
        selectedID = new.id
        persistTemplates()
    }

    private func nextUniqueName() -> String {
        let existingNames = Set(templates.map { $0.name })
        var index = templates.filter({ !$0.isBuiltIn }).count + 1
        while existingNames.contains("Template \(index)") {
            index += 1
        }
        return "Template \(index)"
    }

    private func hasNameCollision(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return templates.contains { $0.id != selectedID && $0.name == trimmed }
    }

    private func delete(_ item: SavedTemplate) {
        guard !item.isBuiltIn else { return }
        if item.id == activeTemplateID {
            if let defaultT = templates.first(where: { $0.name == "default" }) {
                activate(defaultT)
            }
        }
        templates.removeAll { $0.id == item.id }
        if selectedID == item.id {
            selectedID = templates.first?.id
        }
        persistTemplates()
    }

    private func activate(_ item: SavedTemplate) {
        activeTemplateID = item.id
        var config = ConfigService.shared.readConfig()
        config.template = item.isBuiltIn ? item.name : item.pattern
        try? ConfigService.shared.writeConfig(config)
        persistTemplates()
    }

    private func saveCurrentEdit() {
        guard let id = selectedID,
              let idx = templates.firstIndex(where: { $0.id == id }),
              !templates[idx].isBuiltIn else { return }
        let trimmedName = editName.trimmingCharacters(in: .whitespaces)
        guard !hasNameCollision(trimmedName) else { return }
        templates[idx].name = trimmedName.isEmpty ? nextUniqueName() : trimmedName
        templates[idx].pattern = editPattern
        if id == activeTemplateID {
            var config = ConfigService.shared.readConfig()
            config.template = editPattern
            try? ConfigService.shared.writeConfig(config)
        }
        persistTemplates()
    }

    // MARK: - Persistence

    private func loadTemplates() {
        var loaded: [SavedTemplate] = []
        if let data = UserDefaults.standard.data(forKey: "savedTemplates"),
           let decoded = try? JSONDecoder().decode([SavedTemplate].self, from: data) {
            loaded = decoded
        }

        var builtIns: [SavedTemplate] = []
        for preset in builtInTemplates {
            if let existing = loaded.first(where: { $0.isBuiltIn && $0.name == preset.name }) {
                builtIns.append(existing)
            } else {
                builtIns.append(SavedTemplate(name: preset.name, pattern: preset.pattern, isBuiltIn: true))
            }
        }

        let customs = loaded.filter { !$0.isBuiltIn }
        templates = builtIns + customs

        let config = ConfigService.shared.readConfig()
        let configTemplate = config.template
        if let match = templates.first(where: { $0.name == configTemplate || $0.pattern == configTemplate }) {
            activeTemplateID = match.id
        } else {
            activeTemplateID = templates.first?.id
        }

        selectedID = activeTemplateID ?? templates.first?.id
        persistTemplates()
    }

    private func persistTemplates() {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: "savedTemplates")
        }
    }
}

// MARK: - Placeholder data

private enum TemplatePlaceholder {
    struct Item: Hashable {
        let label: String
        let value: String
    }

    static let all: [Item] = [
        Item(label: "authors", value: "{authors}"),
        Item(label: "authors_full", value: "{authors_full}"),
        Item(label: "authors_abbrev", value: "{authors_abbrev}"),
        Item(label: "year", value: "{year}"),
        Item(label: "journal", value: "{journal}"),
        Item(label: "journal_abbrev", value: "{journal_abbrev}"),
        Item(label: "journal_full", value: "{journal_full}"),
        Item(label: "title", value: "{title}"),
    ]
}
