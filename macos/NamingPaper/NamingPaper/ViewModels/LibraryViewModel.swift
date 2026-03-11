import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Observation

enum SidebarPanel: String, CaseIterable {
    case categories = "Categories"
    case recent = "Recent"
    case search = "Search"
}

@Observable
class LibraryViewModel {
    // MARK: - State

    var papers: [Paper] = []
    var categories: [Category] = []
    var selectedPaperID: String?
    var selectedCategory: String?
    var sidebarPanel: SidebarPanel = .categories
    var sortOrder: PaperSortOrder = .title
    var sortAscending: Bool = true
    var isEmpty: Bool = true
    var schemaWarning: String?

    // Starred papers (persisted via UserDefaults)
    var starredPaperIDs: Set<String> = []

    // Recent papers
    var recentPaperIDs: [String] = []

    // Add paper workflow
    var isDragTargeted: Bool = false
    var showFilePicker: Bool = false
    var showAddPaperSheet: Bool = false
    var addPaperViewModel = AddPaperViewModel()

    // Command palette
    var showCommandPalette: Bool = false

    // Search
    var searchViewModel = SearchViewModel()

    // CLI availability
    var cliAvailable: Bool = false
    var newlyAddedIDs: Set<String> = []

    private let db = DatabaseService.shared
    private var pollTimer: Timer?

    // MARK: - Lifecycle

    init() {
        loadStarred()
        loadRecent()
        setupDockDropHandler()
        Task { await loadLibrary() }
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Data Loading

    @MainActor
    func loadLibrary() async {
        do {
            try await db.open()
        } catch {
            // DB doesn't exist yet — show empty state
        }

        schemaWarning = await db.schemaWarning

        let allPapers = await db.listPapers(limit: 10000, orderBy: sortOrder, ascending: sortAscending)
        papers = allPapers
        categories = await db.listCategories()
        isEmpty = allPapers.isEmpty

        // Pass user-configured CLI path from Preferences
        let storedCLIPath = UserDefaults.standard.string(forKey: "cliPath")
        _ = await CLIService.shared.findCLI(userConfiguredPath: storedCLIPath)
        let available = await CLIService.shared.isAvailable
        cliAvailable = available
    }

    @MainActor
    func refresh() async {
        if await db.hasChanged() {
            let oldIDs = Set(papers.map(\.id))
            let allPapers = await db.listPapers(limit: 10000, orderBy: sortOrder, ascending: sortAscending)
            papers = allPapers
            categories = await db.listCategories()
            isEmpty = allPapers.isEmpty

            // Track newly added
            let newIDs = Set(allPapers.map(\.id)).subtracting(oldIDs)
            if !newIDs.isEmpty {
                newlyAddedIDs = newIDs
                // Clear highlight after 2 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run { newlyAddedIDs.removeAll() }
                }
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }

        // Pause polling when app goes to background
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
        }

        // Resume polling when app comes to foreground
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard self?.pollTimer == nil else { return }
            self?.pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { await self?.refresh() }
            }
            // Also refresh immediately on activation
            Task { await self?.refresh() }
        }
    }

    // MARK: - Sidebar

    func activateSidebarPanel(_ panel: SidebarPanel) {
        sidebarPanel = panel
    }

    // MARK: - Category Filter

    var filteredPapers: [Paper] {
        if sidebarPanel == .search {
            return searchViewModel.searchResults
        }
        guard let cat = selectedCategory else { return papers }
        return papers.filter { $0.category == cat }
    }

    func selectCategory(_ category: String?) {
        selectedCategory = category
    }

    // MARK: - Starred

    func toggleStar(paperID: String) {
        if starredPaperIDs.contains(paperID) {
            starredPaperIDs.remove(paperID)
        } else {
            starredPaperIDs.insert(paperID)
        }
        saveStarred()
    }

    func isStarred(_ paperID: String) -> Bool {
        starredPaperIDs.contains(paperID)
    }

    var starredPapers: [Paper] {
        papers.filter { starredPaperIDs.contains($0.id) }
    }

    private func loadStarred() {
        starredPaperIDs = Set(UserDefaults.standard.stringArray(forKey: "starredPaperIDs") ?? [])
    }

    private func saveStarred() {
        UserDefaults.standard.set(Array(starredPaperIDs), forKey: "starredPaperIDs")
    }

    // MARK: - Recent

    func markRecent(paperID: String) {
        recentPaperIDs.removeAll { $0 == paperID }
        recentPaperIDs.insert(paperID, at: 0)
        if recentPaperIDs.count > 20 {
            recentPaperIDs = Array(recentPaperIDs.prefix(20))
        }
        saveRecent()
    }

    var recentPapers: [Paper] {
        let paperMap = Dictionary(uniqueKeysWithValues: papers.map { ($0.id, $0) })
        return recentPaperIDs.compactMap { paperMap[$0] }
    }

    private func loadRecent() {
        recentPaperIDs = UserDefaults.standard.stringArray(forKey: "recentPaperIDs") ?? []
    }

    private func saveRecent() {
        UserDefaults.standard.set(recentPaperIDs, forKey: "recentPaperIDs")
    }

    // MARK: - Sort

    func changeSort(_ order: PaperSortOrder) {
        if sortOrder == order {
            sortAscending.toggle()
        } else {
            sortOrder = order
            sortAscending = true
        }
        Task { await loadLibrary() }
    }

    // MARK: - Paper Lookup

    func paper(for id: String) -> Paper? {
        papers.first { $0.id == id }
    }

    // MARK: - Drag and Drop

    func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        urls.append(url)
                    } else if let data = item as? Data {
                        // Handle security-scoped bookmark data
                        if let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urls.append(url)
                        }
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard !urls.isEmpty else { return }
            self?.startAddWorkflow(urls: urls)
        }
    }

    func handleFileImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else { return }
        startAddWorkflow(urls: pdfURLs)
    }

    private func startAddWorkflow(urls: [URL]) {
        addPaperViewModel.addFiles(urls)
        showAddPaperSheet = true
    }

    // MARK: - Dock Drop Handler

    private func setupDockDropHandler() {
        AppDelegate.onFilesDropped = { [weak self] urls in
            DispatchQueue.main.async {
                self?.startAddWorkflow(urls: urls)
            }
        }

        // Process any pending URLs from before handler was set
        if !AppDelegate.pendingURLs.isEmpty {
            let urls = AppDelegate.pendingURLs
            AppDelegate.pendingURLs.removeAll()
            startAddWorkflow(urls: urls)
        }
    }

    // MARK: - Actions

    func removePaper(id: String) {
        Task {
            do {
                _ = try await CLIService.shared.removePaper(id: id)
                await refresh()
            } catch {
                // Handle error — could add an alert state
            }
        }
    }
}
