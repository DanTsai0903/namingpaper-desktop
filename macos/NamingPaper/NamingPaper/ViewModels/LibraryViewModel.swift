import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Observation

enum SidebarPanel: String, CaseIterable {
    case categories = "Categories"
    case recent = "Recent"
    case search = "Search"

    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
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

    // Category management
    var showNewCategoryField: Bool = false

    // Command palette
    var showCommandPalette: Bool = false

    /// Display name for the library (last component of papersDir)
    var libraryName: String {
        let config = ConfigService.shared.readConfig()
        return URL(fileURLWithPath: config.papersDir).lastPathComponent
    }

    // Search
    var searchViewModel = SearchViewModel()

    // CLI availability
    var cliAvailable: Bool = false
    var newlyAddedIDs: Set<String> = []

    private let db = DatabaseService.shared
    private var pollTimer: Timer?
    private let directoryMonitor = DirectoryMonitor()

    // MARK: - Lifecycle

    init() {
        loadStarred()
        loadRecent()
        setupDockDropHandler()
        Task { await loadLibrary() }
        startPolling()
        startDirectoryMonitor()
    }

    deinit {
        pollTimer?.invalidate()
        directoryMonitor.stop()
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

        _ = await CLIService.shared.findCLI()
        let available = await CLIService.shared.isAvailable
        cliAvailable = available
    }

    /// Force reload from DB regardless of change detection — use after add/remove.
    @MainActor
    func forceRefresh() async {
        await db.forceReload()
        let allPapers = await db.listPapers(limit: 10000, orderBy: sortOrder, ascending: sortAscending)
        let oldIDs = Set(papers.map(\.id))
        papers = allPapers
        categories = await db.listCategories()
        isEmpty = allPapers.isEmpty

        let newIDs = Set(allPapers.map(\.id)).subtracting(oldIDs)
        if !newIDs.isEmpty {
            newlyAddedIDs = newIDs
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { newlyAddedIDs.removeAll() }
            }
        }
    }

    @MainActor
    func refresh() async {
        // Ensure DB is open (handles case where DB was created after app launch)
        if !(await db.isOpen), await db.databaseExists {
            try? await db.open()
        }
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

    // MARK: - Directory Monitoring

    private func startDirectoryMonitor() {
        let papersPath = ConfigService.shared.readConfig().papersDir
        directoryMonitor.onChange = { [weak self] in
            Task { [weak self] in
                guard let self, self.cliAvailable else { return }
                _ = try? await CLIService.shared.syncLibrary()
                await self.forceRefresh()
            }
        }
        directoryMonitor.start(path: papersPath)

        // Listen for library migration from Preferences
        NotificationCenter.default.addObserver(
            forName: .libraryDidMigrate, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restartDirectoryMonitor()
            Task { await self?.forceRefresh() }
        }
    }

    private func restartDirectoryMonitor() {
        let papersPath = ConfigService.shared.readConfig().papersDir
        directoryMonitor.start(path: papersPath)
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
            // Sync and refresh — files may have changed while app was inactive
            Task {
                if let self, self.cliAvailable {
                    _ = try? await CLIService.shared.syncLibrary()
                    await self.forceRefresh()
                }
            }
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

    func removePaper(id: String, deleteFile: Bool = true) {
        Task {
            do {
                _ = try await CLIService.shared.removePaper(id: id, deleteFile: deleteFile)
                await forceRefresh()
            } catch {
                // Handle error — could add an alert state
            }
        }
    }

    // MARK: - Category Management

    private var papersDir: URL {
        let config = ConfigService.shared.readConfig()
        return URL(fileURLWithPath: config.papersDir)
    }

    /// Merge DB categories with filesystem subdirectories so empty folders also appear.
    var allCategories: [Category] {
        let dbNames = Set(categories.map(\.name))
        var merged = categories
        let fsDirs = scanSubdirectories(at: papersDir, relativeTo: papersDir)
        for dir in fsDirs where !dbNames.contains(dir) {
            merged.append(Category(name: dir, paperCount: 0))
        }
        return merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Recursively scan for subdirectories relative to the papers root.
    private func scanSubdirectories(at url: URL, relativeTo root: URL) -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var result: [String] = []
        for item in items {
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let relative = item.path.replacingOccurrences(of: root.path + "/", with: "")
            result.append(relative)
            result.append(contentsOf: scanSubdirectories(at: item, relativeTo: root))
        }
        return result
    }

    func createCategory(name: String) {
        let dir = papersDir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task {
            _ = try? await CLIService.shared.syncLibrary()
            await forceRefresh()
        }
    }

    /// Number of papers in a category (including subcategories).
    func paperCount(for categoryName: String) -> Int {
        papers.filter { $0.category == categoryName || $0.category.hasPrefix(categoryName + "/") }.count
    }

    func deleteCategory(name: String) {
        let dir = papersDir.appendingPathComponent(name)

        Task {
            // Delete all papers in this category (and subcategories) via CLI
            let papersInCategory = papers.filter {
                $0.category == name || $0.category.hasPrefix(name + "/")
            }

            for paper in papersInCategory {
                _ = try? await CLIService.shared.removePaper(id: paper.id, deleteFile: true)
            }

            // Remove the category directory (cleans up .DS_Store, empty subdirs, etc.)
            try? FileManager.default.removeItem(at: dir)

            if selectedCategory == name || (selectedCategory?.hasPrefix(name + "/") == true) {
                await MainActor.run { selectedCategory = nil }
            }

            await forceRefresh()
        }
    }

    func renameCategory(from oldName: String, to newName: String) {
        guard !newName.isEmpty, oldName != newName else { return }
        let oldDir = papersDir.appendingPathComponent(oldName)
        let newDir = papersDir.appendingPathComponent(newName)
        guard (try? FileManager.default.moveItem(at: oldDir, to: newDir)) != nil else { return }
        if selectedCategory == oldName {
            selectedCategory = newName
        }
        Task {
            _ = try? await CLIService.shared.syncLibrary()
            await forceRefresh()
        }
    }

    func updateKeywords(paperID: String, keywords: [String]) {
        Task {
            let json = try? JSONSerialization.data(withJSONObject: keywords)
            let str = json.flatMap { String(data: $0, encoding: .utf8) } ?? keywords.joined(separator: ", ")
            _ = await db.updatePaperKeywords(id: paperID, keywords: str)
            await forceRefresh()
        }
    }

    func updateMetadata(paperID: String, title: String, authors: [String], authorsAll: [String], year: Int?, journal: String, journalAbbrev: String) {
        Task {
            let authorsJSON = (try? JSONSerialization.data(withJSONObject: authors)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let authorsAllJSON = (try? JSONSerialization.data(withJSONObject: authorsAll)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            _ = await db.updatePaperMetadata(
                id: paperID,
                title: title,
                authors: authorsJSON,
                authorsAll: authorsAllJSON,
                year: year,
                journal: journal,
                journalAbbrev: journalAbbrev
            )
            await forceRefresh()
        }
    }

    func updateSummary(paperID: String, summary: String) {
        Task {
            _ = await db.updatePaperSummary(id: paperID, summary: summary)
            await forceRefresh()
        }
    }

    func movePaper(_ paper: Paper, toCategory category: String) {
        Task {
            let sourceURL = URL(fileURLWithPath: paper.filePath)
            let filename = sourceURL.lastPathComponent
            let destDir = papersDir.appendingPathComponent(category)
            let destPath = destDir.appendingPathComponent(filename)

            do {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: sourceURL, to: destPath)
                // Update the DB record directly with new path and category
                _ = await db.updatePaper(id: paper.id, filePath: destPath.path, category: category)
                await forceRefresh()
            } catch {
                await forceRefresh()
            }
        }
    }
}

extension Notification.Name {
    static let libraryDidMigrate = Notification.Name("libraryDidMigrate")
}
