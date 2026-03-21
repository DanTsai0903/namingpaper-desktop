import Foundation
import Combine

enum SyncStatus: Equatable {
    case disabled
    case synced
    case syncing
    case offline
    case error(String)

    var displayName: String {
        switch self {
        case .disabled: return "Sync Off"
        case .synced: return "Synced"
        case .syncing: return "Syncing..."
        case .offline: return "Offline"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var systemImage: String {
        switch self {
        case .disabled: return "icloud.slash"
        case .synced: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .offline: return "icloud.slash"
        case .error: return "exclamationmark.icloud"
        }
    }
}

struct SyncConflict: Identifiable {
    let id = UUID()
    let sha256: String
    let title: String
    let conflictType: ConflictType

    enum ConflictType {
        case remoteDeleted   // Paper deleted on remote, still exists locally
        case localDeleted    // Paper deleted locally, still exists on remote
    }
}

actor SyncService {
    static let shared = SyncService()

    private let syncContainerPath: URL
    private var manifestURL: URL { syncContainerPath.appendingPathComponent("library.json") }
    private var syncMetaURL: URL { syncContainerPath.appendingPathComponent(".sync-meta.json") }

    private nonisolated(unsafe) let statusSubject = CurrentValueSubject<SyncStatus, Never>(.disabled)
    nonisolated var statusPublisher: AnyPublisher<SyncStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    private nonisolated(unsafe) let conflictSubject = PassthroughSubject<SyncConflict, Never>()
    nonisolated var conflictPublisher: AnyPublisher<SyncConflict, Never> {
        conflictSubject.eraseToAnyPublisher()
    }

    private var isEnabled = false
    private var filePresenter: ManifestFilePresenter?
    private var notificationObservers: [Any] = []

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        syncContainerPath = home
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/NamingPaper")
    }

    // MARK: - Enable / Disable

    func enableSync() async {
        isEnabled = true

        // Check iCloud availability (entitlement + sign-in)
        guard checkiCloudAvailability() else {
            statusSubject.send(.offline)
            return
        }

        statusSubject.send(.syncing)

        // Create sync container if needed
        let fm = FileManager.default
        if !fm.fileExists(atPath: syncContainerPath.path) {
            try? fm.createDirectory(at: syncContainerPath, withIntermediateDirectories: true)
        }

        // Initialize sync meta if needed
        if !fm.fileExists(atPath: syncMetaURL.path) {
            let meta: [String: Any] = [:]
            if let data = try? JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted) {
                try? data.write(to: syncMetaURL, options: .atomic)
            }
        }

        // Check if remote manifest exists (joining existing sync)
        if fm.fileExists(atPath: manifestURL.path) {
            await performInboundSync()
        }

        // Export local library to manifest
        await exportToManifest()

        // Update sync meta
        updateSyncMeta()

        // Start monitoring
        startMonitoring()
        observeDatabaseChanges()

        statusSubject.send(.synced)
    }

    func disableSync() {
        isEnabled = false
        stopMonitoring()
        removeObservers()
        statusSubject.send(.disabled)
    }

    // MARK: - Device Identifier

    private var deviceIdentifier: String {
        // Use hardware UUID as stable identifier
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if let range = output.range(of: "IOPlatformUUID\" = \"") {
            let start = range.upperBound
            if let end = output[start...].firstIndex(of: "\"") {
                return String(output[start..<end])
            }
        }
        // Fallback to hostname
        return ProcessInfo.processInfo.hostName
    }

    // MARK: - Outbound Sync (Local → Manifest)

    private func exportToManifest() async {
        guard isEnabled else { return }

        // Prepare manifest data while still on the actor
        let manifest = await DatabaseService.shared.exportManifest()
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else {
            statusSubject.send(.error("Failed to serialize manifest"))
            return
        }

        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(writingItemAt: manifestURL, options: .forReplacing, error: &error) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                statusSubject.send(.error("Failed to write manifest"))
            }
        }
    }

    private func copyPDFToSyncContainer(paper: Paper) {
        guard isEnabled else { return }
        let fm = FileManager.default
        let sourceURL = URL(fileURLWithPath: paper.filePath)
        guard fm.fileExists(atPath: sourceURL.path) else { return }

        let category = paper.category.isEmpty ? "Unsorted" : paper.category
        let destDir = syncContainerPath.appendingPathComponent(category)
        let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: destURL, options: .forReplacing, error: &error) { url in
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            try? fm.removeItem(at: url)
            try? fm.copyItem(at: sourceURL, to: url)
        }
    }

    private func removePDFFromSyncContainer(sha256: String) async {
        guard isEnabled else { return }
        // Read manifest to find the file
        guard let manifest = readManifest(),
              let entry = manifest[sha256],
              let filePath = entry["filePath"] as? String else { return }

        let fileName = (filePath as NSString).lastPathComponent
        let category = entry["category"] as? String ?? "Unsorted"
        let fileURL = syncContainerPath.appendingPathComponent(category).appendingPathComponent(fileName)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &error) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Inbound Sync (Manifest → Local)

    func performInboundSync() async {
        guard isEnabled else { return }
        statusSubject.send(.syncing)

        guard let remoteManifest = readManifest() else {
            statusSubject.send(.synced)
            return
        }

        let config = ConfigService.shared.readConfig()
        let papersDir = URL(fileURLWithPath: config.papersDir)
        let fm = FileManager.default

        // Get local papers for comparison
        let localPapers = await DatabaseService.shared.listPapers(limit: Int.max, offset: 0)
        let localBySHA = Dictionary(uniqueKeysWithValues: localPapers.map { ($0.sha256, $0) })

        for (sha256, entry) in remoteManifest {
            if let localPaper = localBySHA[sha256] {
                // Paper exists locally — check for metadata update (last-write-wins)
                let remoteUpdated = entry["updatedAt"] as? String ?? ""
                if remoteUpdated > localPaper.updatedAt {
                    _ = await DatabaseService.shared.importManifest(from: [sha256: entry])
                }
            } else {
                // New paper from remote — copy PDF and insert record
                let category = entry["category"] as? String ?? "Unsorted"
                let remoteFilePath = entry["filePath"] as? String ?? ""
                let fileName = (remoteFilePath as NSString).lastPathComponent
                let syncFileURL = syncContainerPath.appendingPathComponent(category).appendingPathComponent(fileName)

                if fm.fileExists(atPath: syncFileURL.path) {
                    let destDir = papersDir.appendingPathComponent(category)
                    let destURL = destDir.appendingPathComponent(fileName)
                    try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    if !fm.fileExists(atPath: destURL.path) {
                        try? fm.copyItem(at: syncFileURL, to: destURL)
                    }
                    // Update the file path to local location
                    var updatedEntry = entry
                    updatedEntry["filePath"] = destURL.path
                    _ = await DatabaseService.shared.importManifest(from: [sha256: updatedEntry])
                }
            }
        }

        // Check for papers deleted on remote (exist locally but not in remote manifest)
        let remoteSHA256s = Set(remoteManifest.keys)
        for localPaper in localPapers {
            if !remoteSHA256s.contains(localPaper.sha256) {
                // Paper was deleted on remote — surface conflict
                conflictSubject.send(SyncConflict(
                    sha256: localPaper.sha256,
                    title: localPaper.title,
                    conflictType: .remoteDeleted
                ))
            }
        }

        statusSubject.send(.synced)
    }

    // MARK: - File Monitoring (NSFilePresenter)

    private func startMonitoring() {
        let presenter = ManifestFilePresenter(url: manifestURL) {
            // Manifest changed externally — trigger inbound sync
            Task {
                await SyncService.shared.performInboundSync()
            }
        }
        filePresenter = presenter
        NSFileCoordinator.addFilePresenter(presenter)
    }

    private func stopMonitoring() {
        if let presenter = filePresenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            filePresenter = nil
        }
    }

    // MARK: - Database Change Observers

    private func observeDatabaseChanges() {
        let addedObserver = NotificationCenter.default.addObserver(
            forName: .paperAdded, object: nil, queue: nil
        ) { [weak self] notification in
            guard let sha256 = notification.userInfo?["sha256"] as? String else { return }
            Task {
                guard let self else { return }
                // Find the paper and copy to sync container
                if let paper = await DatabaseService.shared.findPaperBySHA256(sha256) {
                    await self.copyPDFToSyncContainer(paper: paper)
                }
                await self.exportToManifest()
                await self.updateSyncMeta()
            }
        }

        let updatedObserver = NotificationCenter.default.addObserver(
            forName: .paperUpdated, object: nil, queue: nil
        ) { [weak self] _ in
            Task {
                guard let self else { return }
                await self.exportToManifest()
                await self.updateSyncMeta()
            }
        }

        let deletedObserver = NotificationCenter.default.addObserver(
            forName: .paperDeleted, object: nil, queue: nil
        ) { [weak self] notification in
            guard let sha256 = notification.userInfo?["sha256"] as? String else { return }
            Task {
                guard let self else { return }
                await self.removePDFFromSyncContainer(sha256: sha256)
                await self.exportToManifest()
                await self.updateSyncMeta()
            }
        }

        notificationObservers = [addedObserver, updatedObserver, deletedObserver]
    }

    private func removeObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers = []
    }

    // MARK: - Sync Meta

    private func updateSyncMeta() {
        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(writingItemAt: syncMetaURL, options: .forMerging, error: &error) { url in
            var meta: [String: Any] = [:]
            if let data = try? Data(contentsOf: url),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                meta = existing
            }

            meta[deviceIdentifier] = [
                "lastSync": ISO8601DateFormatter().string(from: Date()),
                "hostname": ProcessInfo.processInfo.hostName
            ]

            if let data = try? JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - iCloud Availability

    func checkiCloudAvailability() -> Bool {
        // ubiquityIdentityToken only checks if user is signed into iCloud,
        // but doesn't verify the app has the iCloud entitlement.
        // url(forUbiquityContainerIdentifier:) returns nil if the app lacks entitlements.
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        return FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.namingpaper.app") != nil
    }

    /// Call from AppDelegate on iCloud identity change notification
    func handleiCloudIdentityChange() async {
        if checkiCloudAvailability() {
            if isEnabled {
                statusSubject.send(.syncing)
                await performInboundSync()
                await exportToManifest()
                statusSubject.send(.synced)
            }
        } else {
            if isEnabled {
                statusSubject.send(.offline)
                stopMonitoring()
            }
        }
    }

    // MARK: - Helpers

    private func readManifest() -> [String: [String: Any]]? {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var result: [String: [String: Any]]?

        coordinator.coordinate(readingItemAt: manifestURL, options: [], error: &error) { url in
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
            result = json
        }
        return result
    }

    /// Get sync container size for display
    func syncContainerSize() -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: syncContainerPath, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}

// MARK: - ManifestFilePresenter

private class ManifestFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.presentedItemURL = url
        self.onChange = onChange
        super.init()
    }

    func presentedItemDidChange() {
        onChange()
    }
}
