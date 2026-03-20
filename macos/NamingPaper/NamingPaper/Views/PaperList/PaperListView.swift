import SwiftUI

struct PaperListView: View {
    @Environment(LibraryViewModel.self) var viewModel
    @Environment(TabManager.self) var tabManager
    @State private var sortOrder = [KeyPathComparator(\Paper.title)]
    @SceneStorage("paperTableColumns_v2") private var columnCustomization: TableColumnCustomization<Paper>
    @AppStorage("authorDisplay") private var authorDisplay: String = "last"
    @AppStorage("journalDisplay") private var journalDisplay: String = "full"

    /// Direct child subcategories of the currently selected category.
    private var childCategories: [CategoryNode] {
        guard let selected = viewModel.selectedCategory else { return [] }
        let tree = CategoryNode.buildTree(from: viewModel.allCategories)
        return findNode(path: selected, in: tree)?.children ?? []
    }

    /// The display title for the current view.
    private var panelTitle: String {
        if viewModel.sidebarPanel == .search {
            return "Search Results"
        }
        guard let cat = viewModel.selectedCategory else {
            return viewModel.libraryName
        }
        // Show last segment of the category path
        return cat.split(separator: "/").last.map(String.init) ?? cat
    }

    /// Papers directly in the selected category (not subcategories).
    private var directPapers: [Paper] {
        if viewModel.sidebarPanel == .search {
            return viewModel.searchViewModel.searchResults
        }
        guard let cat = viewModel.selectedCategory else { return viewModel.papers }
        return viewModel.papers.filter { $0.category == cat }
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            // Subcategory folders
            if !childCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(childCategories) { node in
                            Button {
                                viewModel.selectCategory(node.fullPath)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "folder.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                    Text(node.segment)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text("\(node.totalPaperCount)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(width: 80)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .dropDestination(for: Paper.self) { papers, _ in
                                for paper in papers where paper.category != node.fullPath {
                                    viewModel.movePaper(paper, toCategory: node.fullPath)
                                }
                                return !papers.isEmpty
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(Color.secondary.opacity(0.04))
                Divider()
            }

            // Paper table
            paperTable
                .background(TableConfigurator())
        }
        .navigationTitle(panelTitle)
        .onChange(of: viewModel.selectedPaperID) { _, newID in
            if let id = newID, let paper = viewModel.paper(for: id) {
                tabManager.openTab(for: paper)
                viewModel.markRecent(paperID: id)
                if viewModel.sidebarPanel == .search {
                    viewModel.searchViewModel.commitToHistory()
                }
            }
        }
        .onChange(of: sortOrder) { _, newOrder in
            if let first = newOrder.first {
                switch first.keyPath {
                case \Paper.title: viewModel.changeSort(.title)
                case \Paper.authors: viewModel.changeSort(.authors)
                case \Paper.yearString: viewModel.changeSort(.year)
                case \Paper.journal: viewModel.changeSort(.journal)
                case \Paper.createdAt: viewModel.changeSort(.createdAt)
                default: viewModel.changeSort(.title)
                }
            }
        }
    }

    private var paperTable: some View {
        @Bindable var viewModel = viewModel
        return Table(directPapers, selection: $viewModel.selectedPaperID, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("Title", value: \Paper.title) { paper in
                HStack(spacing: 4) {
                    PaperRowView(
                        paper: paper,
                        isStarred: viewModel.isStarred(paper.id),
                        highlightTerms: searchTerms
                    ) {
                        viewModel.toggleStar(paperID: paper.id)
                    }
                    .opacity(viewModel.newlyAddedIDs.contains(paper.id) ? 0.6 : 1.0)
                    .animation(.easeIn(duration: 0.5), value: viewModel.newlyAddedIDs.contains(paper.id))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectedPaperID = paper.id
                }
                .onDrag { paper.dragItemProvider }
            }
            .width(min: 200)
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Authors", value: \Paper.authors) { paper in
                let preferred = authorDisplay == "full" ? paper.authorsAllDisplay : paper.authorsDisplay
                let fallback = authorDisplay == "full" ? paper.authorsDisplay : paper.authorsAllDisplay
                let display = preferred.isEmpty ? fallback : preferred
                if searchTerms.isEmpty {
                    Text(display)
                } else {
                    Text(highlightedText(display, terms: searchTerms))
                }
            }
            .width(min: 100, ideal: 150)
            .customizationID("authors")

            TableColumn("Year", value: \Paper.yearString)
                .width(min: 40, ideal: 50)
                .customizationID("year")

            TableColumn("Journal", value: \Paper.journal) { paper in
                let preferred = journalDisplay == "abbrev" ? paper.journalAbbrev : paper.journal
                let fallback = journalDisplay == "abbrev" ? paper.journal : paper.journalAbbrev
                let display = preferred.isEmpty ? fallback : preferred
                Text(display)
            }
            .width(min: 80, ideal: 120)
            .customizationID("journal")

            TableColumn("Date Added", value: \Paper.createdAt) { paper in
                Text(paper.dateAddedDisplay)
            }
            .width(min: 80, ideal: 100)
            .customizationID("dateAdded")
            .defaultVisibility(.hidden)
        }
        .id("\(authorDisplay)-\(journalDisplay)")
    }

    /// Find a node by its full path in the tree.
    private func findNode(path: String, in nodes: [CategoryNode]) -> CategoryNode? {
        for node in nodes {
            if node.fullPath == path { return node }
            if let found = findNode(path: path, in: node.children) { return found }
        }
        return nil
    }

    private var searchTerms: [String] {
        guard viewModel.sidebarPanel == .search else { return [] }
        let query = viewModel.searchViewModel.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return query.split(separator: " ").map(String.init)
    }

    private func highlightedText(_ text: String, terms: [String]) -> AttributedString {
        var attributed = AttributedString(text)
        let lowerText = text.lowercased()
        for term in terms where !term.isEmpty {
            let lowerTerm = term.lowercased()
            var searchStart = lowerText.startIndex
            while let range = lowerText.range(of: lowerTerm, range: searchStart..<lowerText.endIndex) {
                let attrStart = AttributedString.Index(range.lowerBound, within: attributed)
                let attrEnd = AttributedString.Index(range.upperBound, within: attributed)
                if let attrStart, let attrEnd {
                    attributed[attrStart..<attrEnd].foregroundColor = .accentColor
                    attributed[attrStart..<attrEnd].font = .body.bold()
                }
                searchStart = range.upperBound
            }
        }
        return attributed
    }
}

/// Finds the underlying NSTableView and configures auto-resizing so columns
/// redistribute space when a column is shown or hidden.
private struct TableConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let tableView = Self.findTableView(from: view) else { return }
            tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            tableView.sizeToFit()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let tableView = Self.findTableView(from: nsView) else { return }
            tableView.sizeToFit()
        }
    }

    private static func findTableView(from view: NSView) -> NSTableView? {
        var current = view.superview
        while let parent = current {
            if let found = findDescendant(of: parent, type: NSTableView.self) {
                return found
            }
            current = parent.superview
        }
        return nil
    }

    private static func findDescendant<T: NSView>(of view: NSView, type: T.Type) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let found = findDescendant(of: subview, type: type) { return found }
        }
        return nil
    }
}

struct EmptyLibraryView: View {
    @Environment(LibraryViewModel.self) var viewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Welcome to \(viewModel.libraryName)")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your paper library is empty. Add papers to get started.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Label("Drag & drop PDFs onto this window", systemImage: "arrow.down.doc")
                Label("Press ⌘O to open a file picker", systemImage: "folder")
                Label("Drop PDFs onto the dock icon", systemImage: "dock.rectangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if !viewModel.cliAvailable {
                Divider()
                    .frame(width: 200)

                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("namingpaper CLI not found")
                        .font(.callout)
                }

                Text("Configure the CLI path in Preferences (⌘,)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
