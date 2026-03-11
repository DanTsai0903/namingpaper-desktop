import SwiftUI

struct PaperListView: View {
    @Environment(LibraryViewModel.self) var viewModel
    @Environment(TabManager.self) var tabManager
    @State private var sortOrder = [KeyPathComparator(\Paper.title)]

    var body: some View {
        @Bindable var viewModel = viewModel
        Table(viewModel.filteredPapers, selection: $viewModel.selectedPaperID, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title) { paper in
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
            }
            .width(min: 200)

            TableColumn("Authors", value: \.authors) { paper in
                if searchTerms.isEmpty {
                    Text(paper.authors)
                } else {
                    Text(highlightedText(paper.authors, terms: searchTerms))
                }
            }
            .width(min: 100, ideal: 150)

            TableColumn("Year", value: \.yearString)
                .width(50)

            TableColumn("Journal", value: \.journal)
                .width(min: 80, ideal: 120)
        }
        .onChange(of: viewModel.selectedPaperID) { _, newID in
            if let id = newID, let paper = viewModel.paper(for: id) {
                tabManager.openTab(for: paper)
                viewModel.markRecent(paperID: id)
            }
        }
        .onChange(of: sortOrder) { _, newOrder in
            if let first = newOrder.first {
                switch first.keyPath {
                case \Paper.title: viewModel.changeSort(.title)
                case \Paper.authors: viewModel.changeSort(.authors)
                case \Paper.yearString: viewModel.changeSort(.year)
                case \Paper.journal: viewModel.changeSort(.title)
                default: viewModel.changeSort(.title)
                }
            }
        }
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

struct EmptyLibraryView: View {
    @Environment(LibraryViewModel.self) var viewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Welcome to NamingPaper")
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
