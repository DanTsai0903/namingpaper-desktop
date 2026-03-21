import Foundation
import Combine

struct BackupProgress {
    let totalFiles: Int
    let completedFiles: Int
    let totalBytes: Int64
    let completedBytes: Int64

    var fractionCompleted: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(completedFiles) / Double(totalFiles)
    }
}

struct BackupInfo {
    let url: URL
    let date: Date
    let sizeBytes: Int64
}

actor BackupService {
    static let shared = BackupService()

    private nonisolated(unsafe) let progressSubject = PassthroughSubject<BackupProgress, Never>()
    nonisolated var progressPublisher: AnyPublisher<BackupProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    // MARK: - Manual Backup

    /// Creates a timestamped backup of the library (database + PDFs) at the given destination.
    /// Returns the URL of the created backup directory.
    func createBackup(destination: URL) async throws -> URL {
        let config = ConfigService.shared.readConfig()
        let fm = FileManager.default

        // Create timestamped backup folder
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupDir = destination.appendingPathComponent("NamingPaper-Backup-\(timestamp)")
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Gather files to copy
        let dbPath = config.databasePath.isEmpty ? AppConfig.defaultDatabasePath : config.databasePath
        let papersDir = URL(fileURLWithPath: config.papersDir)

        var filesToCopy: [(source: URL, relativePath: String)] = []

        // Database file
        let dbURL = URL(fileURLWithPath: dbPath)
        if fm.fileExists(atPath: dbPath) {
            filesToCopy.append((dbURL, "library.db"))
        }

        // WAL and SHM files
        let walPath = dbPath + "-wal"
        let shmPath = dbPath + "-shm"
        if fm.fileExists(atPath: walPath) {
            filesToCopy.append((URL(fileURLWithPath: walPath), "library.db-wal"))
        }
        if fm.fileExists(atPath: shmPath) {
            filesToCopy.append((URL(fileURLWithPath: shmPath), "library.db-shm"))
        }

        // PDF files under papers_dir
        if fm.fileExists(atPath: papersDir.path) {
            let enumerator = fm.enumerator(at: papersDir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues?.isRegularFile == true else { continue }
                let relativePath = fileURL.path.replacingOccurrences(of: papersDir.path + "/", with: "Papers/")
                filesToCopy.append((fileURL, relativePath))
            }
        }

        // Calculate total size
        var totalBytes: Int64 = 0
        for (source, _) in filesToCopy {
            let attrs = try? fm.attributesOfItem(atPath: source.path)
            totalBytes += (attrs?[.size] as? Int64) ?? 0
        }

        // Copy files with progress
        var completedFiles = 0
        var completedBytes: Int64 = 0

        progressSubject.send(BackupProgress(totalFiles: filesToCopy.count, completedFiles: 0, totalBytes: totalBytes, completedBytes: 0))

        for (source, relativePath) in filesToCopy {
            let destFile = backupDir.appendingPathComponent(relativePath)
            let destDir = destFile.deletingLastPathComponent()
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destFile)

            completedFiles += 1
            let fileSize = (try? fm.attributesOfItem(atPath: source.path))?[.size] as? Int64 ?? 0
            completedBytes += fileSize
            progressSubject.send(BackupProgress(totalFiles: filesToCopy.count, completedFiles: completedFiles, totalBytes: totalBytes, completedBytes: completedBytes))
        }

        return backupDir
    }

    // MARK: - Restore from Backup

    /// Restores a library from a backup directory. Creates a safety backup first.
    /// Returns a list of missing PDF filenames (if any PDFs referenced in the backup DB are absent).
    func restoreFromBackup(backupDir: URL, safetyBackupDestination: URL) async throws -> [String] {
        let config = ConfigService.shared.readConfig()
        let fm = FileManager.default

        // Safety backup of current state
        _ = try await createBackup(destination: safetyBackupDestination)

        let dbPath = config.databasePath.isEmpty ? AppConfig.defaultDatabasePath : config.databasePath
        let papersDir = URL(fileURLWithPath: config.papersDir)

        // Restore database
        let backupDB = backupDir.appendingPathComponent("library.db")
        if fm.fileExists(atPath: backupDB.path) {
            // Close current DB connection before replacing
            await DatabaseService.shared.close()

            let dbURL = URL(fileURLWithPath: dbPath)
            try? fm.removeItem(at: dbURL)
            try fm.copyItem(at: backupDB, to: dbURL)

            // Also restore WAL/SHM if present
            let backupWAL = backupDir.appendingPathComponent("library.db-wal")
            let backupSHM = backupDir.appendingPathComponent("library.db-shm")
            if fm.fileExists(atPath: backupWAL.path) {
                try? fm.removeItem(atPath: dbPath + "-wal")
                try fm.copyItem(at: backupWAL, to: URL(fileURLWithPath: dbPath + "-wal"))
            }
            if fm.fileExists(atPath: backupSHM.path) {
                try? fm.removeItem(atPath: dbPath + "-shm")
                try fm.copyItem(at: backupSHM, to: URL(fileURLWithPath: dbPath + "-shm"))
            }

            // Reopen DB
            try await DatabaseService.shared.open()
        }

        // Restore PDF files
        let backupPapersDir = backupDir.appendingPathComponent("Papers")
        var missingFiles: [String] = []

        if fm.fileExists(atPath: backupPapersDir.path) {
            let enumerator = fm.enumerator(at: backupPapersDir, includingPropertiesForKeys: [.isRegularFileKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues?.isRegularFile == true else { continue }

                let relativePath = fileURL.path.replacingOccurrences(of: backupPapersDir.path + "/", with: "")
                let destFile = papersDir.appendingPathComponent(relativePath)
                let destDir = destFile.deletingLastPathComponent()

                do {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    if fm.fileExists(atPath: destFile.path) {
                        try fm.removeItem(at: destFile)
                    }
                    try fm.copyItem(at: fileURL, to: destFile)
                } catch {
                    missingFiles.append(relativePath)
                }
            }
        }

        return missingFiles
    }

    // MARK: - List Existing Backups

    /// Lists all NamingPaper backup directories at the given location, sorted newest first.
    func listBackups(at destination: URL) -> [BackupInfo] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }

        let backups = contents.compactMap { url -> BackupInfo? in
            let name = url.lastPathComponent
            guard name.hasPrefix("NamingPaper-Backup-") else { return nil }

            let dateStr = name.replacingOccurrences(of: "NamingPaper-Backup-", with: "")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let date = formatter.date(from: dateStr) ?? Date.distantPast

            let size = directorySize(url)
            return BackupInfo(url: url, date: date, sizeBytes: size)
        }

        return backups.sorted { $0.date > $1.date }
    }

    // MARK: - Retention Cleanup

    /// Deletes the oldest backups at the destination until the count is within the retention limit.
    func cleanupOldBackups(at destination: URL, retentionCount: Int) throws {
        let backups = listBackups(at: destination)
        guard backups.count > retentionCount else { return }

        let toDelete = backups.suffix(from: retentionCount)
        for backup in toDelete {
            try FileManager.default.removeItem(at: backup.url)
        }
    }

    // MARK: - Helpers

    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
