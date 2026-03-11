import SwiftUI

struct CategoryTreeView: View {
    @Environment(LibraryViewModel.self) var viewModel

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
                ForEach(viewModel.categories) { category in
                    Button {
                        viewModel.selectCategory(category.name)
                    } label: {
                        HStack {
                            Label(category.name, systemImage: "folder")
                            Spacer()
                            Text("\(category.paperCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .fontWeight(viewModel.selectedCategory == category.name ? .semibold : .regular)
                }
            }
        }
        .listStyle(.sidebar)
    }
}
