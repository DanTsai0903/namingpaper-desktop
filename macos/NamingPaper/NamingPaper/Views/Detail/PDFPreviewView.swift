import SwiftUI
import PDFKit

struct PDFPreviewView: View {
    let url: URL
    @State private var zoomLevel: Double = 1.0
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var searchResults: [PDFSelection] = []
    @State private var currentResultIndex: Int = 0
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PDFKitView(
                    url: url,
                    zoomLevel: $zoomLevel,
                    currentPage: $currentPage,
                    totalPages: $totalPages,
                    searchResults: $searchResults,
                    currentResultIndex: $currentResultIndex
                )
                .onReceive(NotificationCenter.default.publisher(for: .navigateToPage)) { notification in
                    if let page = notification.userInfo?["page"] as? Int {
                        currentPage = min(page, totalPages)
                    }
                }

                if showSearch {
                    searchBar
                        .padding(8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            // Controls bar
            HStack {
                // Page indicator
                Text("Page \(currentPage) of \(totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Search toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSearch.toggle()
                        if showSearch {
                            searchFieldFocused = true
                        } else {
                            clearSearch()
                        }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)

                Divider()
                    .frame(height: 14)

                // Zoom controls
                Button {
                    zoomLevel = max(0.25, zoomLevel - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("-", modifiers: .command)

                Slider(value: $zoomLevel, in: 0.25...4.0, step: 0.25)
                    .frame(width: 120)

                Button {
                    zoomLevel = min(4.0, zoomLevel + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("+", modifiers: .command)

                Text("\(Int(zoomLevel * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)

            TextField("Search in PDF…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($searchFieldFocused)
                .onSubmit { performSearch() }

            if !searchResults.isEmpty {
                Text("\(currentResultIndex + 1)/\(searchResults.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button { navigateResult(delta: -1) } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button { navigateResult(delta: 1) } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            } else if !searchText.isEmpty {
                Text("No results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSearch = false
                    clearSearch()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .frame(maxWidth: 320)
    }

    private func performSearch() {
        NotificationCenter.default.post(
            name: .pdfPerformSearch,
            object: nil,
            userInfo: ["query": searchText]
        )
    }

    private func navigateResult(delta: Int) {
        guard !searchResults.isEmpty else { return }
        currentResultIndex = (currentResultIndex + delta + searchResults.count) % searchResults.count
    }

    private func clearSearch() {
        searchText = ""
        searchResults = []
        currentResultIndex = 0
        NotificationCenter.default.post(name: .pdfClearSearch, object: nil)
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    @Binding var zoomLevel: Double
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    @Binding var searchResults: [PDFSelection]
    @Binding var currentResultIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        context.coordinator.pdfView = pdfView

        if let doc = pdfView.document {
            DispatchQueue.main.async {
                totalPages = doc.pageCount
            }
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.performSearch(_:)),
            name: .pdfPerformSearch,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clearSearch),
            name: .pdfClearSearch,
            object: nil
        )

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
            if let doc = pdfView.document {
                DispatchQueue.main.async {
                    totalPages = doc.pageCount
                    currentPage = 1
                }
            }
        }

        let newScale = CGFloat(zoomLevel)
        if abs(pdfView.scaleFactor - newScale) > 0.01 {
            pdfView.scaleFactor = newScale
        }

        // Navigate to a specific page if currentPage changed
        if let doc = pdfView.document,
           let currentPDFPage = pdfView.currentPage {
            let visibleIndex = doc.index(for: currentPDFPage)
            let targetIndex = currentPage - 1
            if targetIndex != visibleIndex, targetIndex >= 0, targetIndex < doc.pageCount,
               let targetPage = doc.page(at: targetIndex) {
                pdfView.go(to: targetPage)
            }
        }

        // Highlight current search result
        context.coordinator.highlightCurrentResult()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged() {
            guard let pdfView, let currentPDFPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            let pageIndex = doc.index(for: currentPDFPage)
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex + 1
            }
        }

        @objc func performSearch(_ notification: Notification) {
            guard let pdfView, let doc = pdfView.document,
                  let query = notification.userInfo?["query"] as? String,
                  !query.isEmpty else { return }

            let results = doc.findString(query, withOptions: [.caseInsensitive])
            DispatchQueue.main.async {
                self.parent.searchResults = results
                self.parent.currentResultIndex = 0
            }

            // Apply yellow highlight to all matches
            pdfView.highlightedSelections = results

            // Scroll to first result
            if let first = results.first {
                pdfView.go(to: first)
                pdfView.setCurrentSelection(first, animate: true)
            }
        }

        @objc func clearSearch() {
            guard let pdfView else { return }
            pdfView.highlightedSelections = nil
            pdfView.clearSelection()
            DispatchQueue.main.async {
                self.parent.searchResults = []
                self.parent.currentResultIndex = 0
            }
        }

        func highlightCurrentResult() {
            guard let pdfView,
                  !parent.searchResults.isEmpty,
                  parent.currentResultIndex < parent.searchResults.count else { return }

            let selection = parent.searchResults[parent.currentResultIndex]
            pdfView.go(to: selection)
            pdfView.setCurrentSelection(selection, animate: true)
        }
    }
}

extension Notification.Name {
    static let pdfPerformSearch = Notification.Name("pdfPerformSearch")
    static let pdfClearSearch = Notification.Name("pdfClearSearch")
}
