import Foundation
import Observation

@Observable
class SearchViewModel {
    var searchText: String = ""
    var authorFilter: String = ""
    var yearFrom: String = ""
    var yearTo: String = ""
    var journalFilter: String = ""
    var categoryFilter: String = ""
    var searchResults: [Paper] = []
    var isSearching: Bool = false
    var searchHistory: [String] = []

    private var searchTask: Task<Void, Never>?
    private let db = DatabaseService.shared
    private let maxHistory = 10

    init() {
        loadHistory()
    }

    func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)

        searchTask?.cancel()
        searchTask = Task { @MainActor in
            // Debounce 150ms
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            isSearching = true

            let hasFilters = !authorFilter.isEmpty || !yearFrom.isEmpty ||
                             !yearTo.isEmpty || !journalFilter.isEmpty || !categoryFilter.isEmpty

            let results: [Paper]
            if hasFilters || !query.isEmpty {
                results = await db.searchFiltered(
                    query: query.isEmpty ? nil : query,
                    author: authorFilter.isEmpty ? nil : authorFilter,
                    yearFrom: Int(yearFrom),
                    yearTo: Int(yearTo),
                    journal: journalFilter.isEmpty ? nil : journalFilter,
                    category: categoryFilter.isEmpty ? nil : categoryFilter
                )
            } else {
                results = await db.listPapers(limit: 200)
            }

            searchResults = results
            isSearching = false
        }
    }

    /// Save current search text to history. Call when a search result is actually used.
    func commitToHistory() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            addToHistory(query)
        }
    }

    func clearSearch() {
        searchText = ""
        authorFilter = ""
        yearFrom = ""
        yearTo = ""
        journalFilter = ""
        categoryFilter = ""
        searchResults = []
    }

    // MARK: - History

    func removeFromHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        saveHistory()
    }

    func clearHistory() {
        searchHistory.removeAll()
        saveHistory()
    }

    private func addToHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        searchHistory.insert(query, at: 0)
        if searchHistory.count > maxHistory {
            searchHistory = Array(searchHistory.prefix(maxHistory))
        }
        saveHistory()
    }

    private func loadHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: "searchHistory") ?? []
    }

    private func saveHistory() {
        UserDefaults.standard.set(searchHistory, forKey: "searchHistory")
    }
}
