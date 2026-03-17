import SwiftUI
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

    private var categoryTree: [CategoryNode] {
        CategoryNode.buildTree(from: viewModel.allCategories)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        List(selection: $viewModel.selectedCategory) {
            // Starred section
            if !viewModel.starredPapers.isEmpty {
                Section("Starred") {
                    ForEach(viewModel.starredPapers) { paper in
                        Label(paper.title, systemImage: "star.fill")
                            .font(.caption)
                            .lineLimit(1)
                    }
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
                }
                .buttonStyle(.plain)
                .fontWeight(viewModel.selectedCategory == nil ? .semibold : .regular)
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
                }
                .buttonStyle(.plain)
                .fontWeight(viewModel.selectedCategory == node.fullPath ? .semibold : .regular)
                .contextMenu { categoryContextMenu(node) }
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
                        countBadge(node.totalPaperCount)
                    }
                }
                .buttonStyle(.plain)
                .fontWeight(viewModel.selectedCategory == node.fullPath ? .semibold : .regular)
                .contextMenu { categoryContextMenu(node) }
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
        Divider()
        Button("Delete", role: .destructive) {
            categoryToDelete = node.fullPath
        }
    }

    // MARK: - Helpers

    private func submitNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        viewModel.createCategory(name: name)
        newCategoryName = ""
        showNewCategory = false
    }
}
