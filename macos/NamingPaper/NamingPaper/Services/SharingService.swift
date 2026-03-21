import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let namingpaperBundle = UTType(exportedAs: "com.namingpaper.bundle")
}

actor SharingService {
    static let shared = SharingService()

    // MARK: - Export Single Paper

    /// Creates a .namingpaper bundle (zip) for a single paper.
    /// Returns the URL of the created bundle file.
    func exportPaper(_ paper: Paper, to destination: URL) throws -> URL {
        try exportPapers([paper], to: destination)
    }

    // MARK: - Export Multiple Papers

    /// Creates a .namingpaper bundle (zip) containing multiple papers.
    func exportPapers(_ papers: [Paper], to destination: URL) throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Build metadata
        var metadataEntries: [[String: Any]] = []
        for paper in papers {
            var entry: [String: Any] = [
                "sha256": paper.sha256,
                "title": paper.title,
                "authors": paper.authors,
                "authorsAll": paper.authorsAll,
                "journal": paper.journal,
                "journalAbbrev": paper.journalAbbrev,
                "summary": paper.summary,
                "keywords": paper.keywords,
                "category": paper.category,
                "createdAt": paper.createdAt,
                "updatedAt": paper.updatedAt
            ]
            if let year = paper.year { entry["year"] = year }
            if let confidence = paper.confidence { entry["confidence"] = confidence }

            // Copy PDF to temp dir
            let sourceURL = URL(fileURLWithPath: paper.filePath)
            if fm.fileExists(atPath: sourceURL.path) {
                let destPDF = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
                try fm.copyItem(at: sourceURL, to: destPDF)
                entry["fileName"] = sourceURL.lastPathComponent
            }

            metadataEntries.append(entry)
        }

        // Write metadata.json
        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        let jsonData = try JSONSerialization.data(withJSONObject: metadataEntries, options: .prettyPrinted)
        try jsonData.write(to: metadataURL)

        // Create zip
        let bundleName: String
        if papers.count == 1 {
            let safeName = papers[0].title.prefix(50)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            bundleName = "\(safeName).namingpaper"
        } else {
            bundleName = "NamingPaper Export (\(papers.count) papers).namingpaper"
        }

        let bundleURL = destination.appendingPathComponent(bundleName)

        // Use ditto to create zip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, bundleURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SharingError.exportFailed("Failed to create bundle archive")
        }

        return bundleURL
    }

    // MARK: - Import Bundle

    /// Imports papers from a .namingpaper bundle file.
    /// Returns (imported: Int, skipped: Int) counts.
    func importBundle(at bundleURL: URL) async throws -> (imported: Int, skipped: Int) {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Extract zip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", bundleURL.path, tempDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SharingError.importFailed("Failed to extract bundle")
        }

        // Read metadata
        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        guard fm.fileExists(atPath: metadataURL.path) else {
            throw SharingError.importFailed("Bundle missing metadata.json")
        }

        let data = try Data(contentsOf: metadataURL)
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SharingError.importFailed("Invalid metadata.json format")
        }

        let config = ConfigService.shared.readConfig()
        let papersDir = URL(fileURLWithPath: config.papersDir)
        var imported = 0
        var skipped = 0

        for entry in entries {
            guard let sha256 = entry["sha256"] as? String else { continue }

            // Check for duplicate
            let existing = await DatabaseService.shared.findPaperBySHA256(sha256)
            if existing != nil {
                skipped += 1
                continue
            }

            // Copy PDF to papers directory
            guard let fileName = entry["fileName"] as? String else { continue }
            let sourcePDF = tempDir.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: sourcePDF.path) else { continue }

            let category = entry["category"] as? String ?? "Unsorted"
            let destDir = papersDir.appendingPathComponent(category)
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            let destPDF = destDir.appendingPathComponent(fileName)

            if !fm.fileExists(atPath: destPDF.path) {
                try fm.copyItem(at: sourcePDF, to: destPDF)
            }

            // Insert into database
            var manifestEntry = entry
            manifestEntry["filePath"] = destPDF.path
            manifestEntry["id"] = String(sha256.prefix(8))
            let manifest = [sha256: manifestEntry]
            let result = await DatabaseService.shared.importManifest(from: manifest)
            imported += result.inserted
        }

        return (imported, skipped)
    }

    // MARK: - Create Temporary Bundle for Sharing

    /// Creates a temporary .namingpaper bundle and returns its URL for use with share sheet.
    func createTemporaryBundle(for papers: [Paper]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return try exportPapers(papers, to: tempDir)
    }
}

enum SharingError: LocalizedError {
    case exportFailed(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportFailed(let msg): return "Export failed: \(msg)"
        case .importFailed(let msg): return "Import failed: \(msg)"
        }
    }
}
