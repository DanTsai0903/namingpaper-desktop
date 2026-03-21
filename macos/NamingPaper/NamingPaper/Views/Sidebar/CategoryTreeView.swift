import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CategoryTreeView: View {
    @Environment(LibraryViewModel.self) var viewModel
    @State private var newCategoryName = ""
    @State private var renamingCategory: String?
    @State private var renameText = ""
    @State private var showNewCategory = false
    @State private var categoryToDelete: String?
    @State private var expandedCategories: Set<String> = []
    @State private var hasAutoExpanded = false
    @State private var starredExpanded = true

    private var categoryTree: [CategoryNode] {
        CategoryNode.buildTree(from: viewModel.allCategories)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        List(selection: $viewModel.selectedCategory) {
            // Starred section
            if !viewModel.starredPapers.isEmpty {
                Section(isExpanded: $starredExpanded) {
                    ForEach(viewModel.starredPapers) { paper in
                        Label(paper.title, systemImage: "star.fill")
                            .font(.caption)
                            .lineLimit(1)
                    }
                } header: {
                    Text("Starred")
                }
            }

            // All Papers
            Section {
                Button {
                    viewModel.selectCategory(nil)
                } label: {
                    HStack {
                        Label("All Papers", systemImage: "books.vertical")
                        Spacer()
                        Text("\(viewModel.papers.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fontWeight(viewModel.selectedCategory == nil ? .semibold : .regular)
                .listRowBackground(
                    viewModel.selectedCategory == nil
                        ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor)
                        : nil
                )
                .foregroundStyle(viewModel.selectedCategory == nil ? .white : .primary)

                Button {
                    viewModel.showFilePicker = true
                } label: {
                    Label("Add Paper", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add Papers (⌘O)")
            }

            // Categories
            Section("Categories") {
                ForEach(categoryTree) { node in
                    categoryNodeView(node)
                }

                // New category inline field
                if showNewCategory {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(.secondary)
                        TextField("e.g. Economics/Econometrics", text: $newCategoryName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                submitNewCategory()
                            }
                            .onExitCommand {
                                showNewCategory = false
                                newCategoryName = ""
                            }
                        Button("Add") {
                            submitNewCategory()
                        }
                        .buttonStyle(.borderless)
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .font(.callout)
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            guard !hasAutoExpanded else { return }
            hasAutoExpanded = true
            for node in categoryTree where !node.children.isEmpty {
                expandedCategories.insert(node.fullPath)
            }
        }
        .alert("Delete Category", isPresented: Binding(
            get: { categoryToDelete != nil },
            set: { if !$0 { categoryToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let name = categoryToDelete {
                    viewModel.deleteCategory(name: name)
                }
                categoryToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
            }
        } message: {
            if let name = categoryToDelete {
                let count = viewModel.paperCount(for: name)
                if count > 0 {
                    Text("Delete \"\(name)\" and its \(count) paper(s)? The PDF files will also be deleted.")
                } else {
                    Text("Delete the empty category \"\(name)\"?")
                }
            }
        }
    }

    // MARK: - Tree Node View

    private func categoryNodeView(_ node: CategoryNode) -> AnyView {
        if node.children.isEmpty {
            AnyView(leafRow(node))
        } else {
            AnyView(
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedCategories.contains(node.fullPath) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedCategories.insert(node.fullPath)
                            } else {
                                expandedCategories.remove(node.fullPath)
                            }
                        }
                    )
                ) {
                    ForEach(node.children) { child in
                        categoryNodeView(child)
                    }
                } label: {
                    parentRow(node)
                }
            )
        }
    }

    // MARK: - Leaf Row (no children)

    private func leafRow(_ node: CategoryNode) -> some View {
        Group {
            if renamingCategory == node.fullPath {
                renameField(node)
            } else {
                Button {
                    viewModel.selectCategory(node.fullPath)
                } label: {
                    HStack {
                        Label(node.segment, systemImage: "folder")
                        Spacer()
                        countBadge(node.paperCount)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fontWeight(viewModel.selectedCategory == node.fullPath ? .semibold : .regular)
                .contextMenu { categoryContextMenu(node) }
                .dropDestination(for: Paper.self) { papers, _ in
                    for paper in papers where paper.category != node.fullPath {
                        viewModel.movePaper(paper, toCategory: node.fullPath)
                    }
                    return !papers.isEmpty
                }
            }
        }
    }

    // MARK: - Parent Row (has children)

    private func parentRow(_ node: CategoryNode) -> some View {
        Group {
            if renamingCategory == node.fullPath {
                renameField(node)
            } else {
                Button {
                    viewModel.selectCategory(node.fullPath)
                } label: {
                    HStack {
                        Label(node.segment, systemImage: "folder")
                        Spacer()
                        if expandedCategories.contains(node.fullPath) {
                            if node.paperCount > 0 {
                                countBadge(node.paperCount)
                            }
                        } else {
                            countBadge(node.totalPaperCount)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fontWeight(viewModel.selectedCategory == node.fullPath ? .semibold : .regular)
                .contextMenu { categoryContextMenu(node) }
                .dropDestination(for: Paper.self) { papers, _ in
                    for paper in papers where paper.category != node.fullPath {
                        viewModel.movePaper(paper, toCategory: node.fullPath)
                    }
                    return !papers.isEmpty
                }
            }
        }
    }

    // MARK: - Shared Components

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    private func renameField(_ node: CategoryNode) -> some View {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            TextField("Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.renameCategory(from: node.fullPath, to: renameText)
                    renamingCategory = nil
                }
                .onExitCommand {
                    renamingCategory = nil
                }
        }
    }

    @ViewBuilder
    private func categoryContextMenu(_ node: CategoryNode) -> some View {
        Button("New Subcategory...") {
            newCategoryName = node.fullPath + "/"
            showNewCategory = true
        }
        Button("Rename...") {
            renameText = node.fullPath
            renamingCategory = node.fullPath
        }
        Button("Download to Folder...") {
            downloadCategory(node.fullPath)
        }
        Divider()
        Button("Delete", role: .destructive) {
            categoryToDelete = node.fullPath
        }
    }

    // MARK: - Helpers

    private func downloadCategory(_ categoryPath: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Download"
        panel.message = "Choose a folder to save papers from \"\(categoryPath)\""

        guard panel.runModal() == .OK, let destDir = panel.url else { return }
        let papers = viewModel.papers.filter { $0.category == categoryPath }
        var copied = 0
        var failed = 0
        for paper in papers {
            guard let sourceURL = paper.pdfURL, paper.pdfExists else {
                failed += 1
                continue
            }
            let destFile = destDir.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destFile.path) {
                    try FileManager.default.removeItem(at: destFile)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destFile)
                copied += 1
            } catch {
                failed += 1
            }
        }

        let alert = NSAlert()
        if copied > 0 {
            alert.messageText = "Download Complete"
            var info = "Downloaded \(copied) paper(s) to the selected folder."
            if failed > 0 {
                info += "\n\(failed) paper(s) could not be downloaded."
            }
            alert.informativeText = info
            alert.alertStyle = .informational
            alert.runModal()
            NSWorkspace.shared.open(destDir)
        } else {
            alert.messageText = "Download Failed"
            alert.informativeText = "No papers could be downloaded. Some files may be missing."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func submitNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        viewModel.createCategory(name: name)
        newCategoryName = ""
        showNewCategory = false
    }
}
