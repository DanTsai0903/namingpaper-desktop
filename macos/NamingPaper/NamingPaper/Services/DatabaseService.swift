import Foundation
import SQLite3

enum PaperSortOrder: String {
    case title, year, authors, journal, createdAt
}

actor DatabaseService {
    static let shared = DatabaseService()

    private let dbPath: String
    private var db: OpaquePointer?
    private var lastModified: Date?

    /// Known schema version — warn if DB is newer
    private let knownSchemaVersion = 2

    /// Schema warning message if DB is newer
    var schemaWarning: String?

    init() {
        let config = ConfigService.shared.readConfig()
        if !config.databasePath.isEmpty {
            dbPath = config.databasePath
        } else {
            dbPath = AppConfig.defaultDatabasePath
        }
    }

    // MARK: - Connection

    func open() throws {
        guard db == nil else { return }
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        var handle: OpaquePointer?
        // READWRITE is required for WAL-mode databases to properly read via -shm
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw DatabaseError.openFailed(msg)
        }
        db = handle
        migrateToV2()
        checkSchemaVersion()
        updateLastModified()
    }

    func close() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
    }

    var isOpen: Bool { db != nil }

    var databaseExists: Bool {
        FileManager.default.fileExists(atPath: dbPath)
    }

    // MARK: - Schema Version

    private func checkSchemaVersion() {
        guard let db else { return }
        let sql = "SELECT MAX(version) FROM schema_version"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let version = Int(sqlite3_column_int(stmt, 0))
            if version > knownSchemaVersion {
                schemaWarning = "Database was updated by a newer version of namingpaper. Some features may not work correctly. Please update the app."
            }
        }
    }

    // MARK: - List Papers

    func listPapers(limit: Int = 100, offset: Int = 0, orderBy: PaperSortOrder = .title, ascending: Bool = true) -> [Paper] {
        guard let db else { return [] }

        let dir = ascending ? "ASC" : "DESC"
        let orderClause: String
        switch orderBy {
        case .title: orderClause = "title COLLATE NOCASE \(dir)"
        case .year: orderClause = "year \(dir)"
        case .authors: orderClause = "authors COLLATE NOCASE \(dir)"
        case .journal: orderClause = "journal COLLATE NOCASE \(dir)"
        case .createdAt: orderClause = "created_at \(dir)"
        }

        let sql = "SELECT * FROM papers ORDER BY \(orderClause) LIMIT ? OFFSET ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(limit))
        sqlite3_bind_int64(stmt, 2, Int64(offset))

        var papers: [Paper] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            papers.append(paperFromRow(stmt))
        }
        return papers
    }

    // MARK: - FTS5 Search

    /// Convert user query to FTS5 prefix query: each word gets a `*` suffix
    /// so "asset pric" matches "asset pricing", "assets", "prices", etc.
    private func fts5PrefixQuery(_ query: String) -> String {
        query.split(separator: " ")
            .map { String($0).replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
            .joined(separator: " ")
    }

    func search(query: String) -> [Paper] {
        guard let db else { return [] }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return listPapers(limit: 1000)
        }

        // Try FTS5 prefix search first
        let ftsQuery = fts5PrefixQuery(query)
        let sql = """
            SELECT p.* FROM papers p
            JOIN papers_fts fts ON p.rowid = fts.rowid
            WHERE papers_fts MATCH ?
            ORDER BY rank
            LIMIT 200
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)

        var papers: [Paper] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            papers.append(paperFromRow(stmt))
        }

        // Fallback to LIKE search if FTS returns nothing (handles substring matches)
        if papers.isEmpty {
            return likeFallbackSearch(query)
        }
        return papers
    }

    private func likeFallbackSearch(_ query: String) -> [Paper] {
        guard let db else { return [] }
        let pattern = "%\(query)%"
        let sql = """
            SELECT * FROM papers
            WHERE title LIKE ? OR authors LIKE ? OR journal LIKE ?
               OR summary LIKE ? OR keywords LIKE ?
            ORDER BY title COLLATE NOCASE ASC
            LIMIT 200
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for i: Int32 in 1...5 {
            sqlite3_bind_text(stmt, i, (pattern as NSString).utf8String, -1, nil)
        }

        var papers: [Paper] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            papers.append(paperFromRow(stmt))
        }
        return papers
    }

    // MARK: - Filtered Queries

    func searchFiltered(
        query: String? = nil,
        author: String? = nil,
        yearFrom: Int? = nil,
        yearTo: Int? = nil,
        journal: String? = nil,
        category: String? = nil
    ) -> [Paper] {
        guard let db else { return [] }

        var conditions: [String] = []
        var params: [Any] = []

        // FTS5 join if query provided
        let hasQuery = query != nil && !query!.trimmingCharacters(in: .whitespaces).isEmpty
        let baseSQL: String

        if hasQuery {
            baseSQL = "SELECT p.* FROM papers p JOIN papers_fts fts ON p.rowid = fts.rowid WHERE papers_fts MATCH ?"
            params.append(fts5PrefixQuery(query!))
        } else {
            baseSQL = "SELECT * FROM papers p WHERE 1=1"
        }

        if let author, !author.isEmpty {
            conditions.append("p.authors LIKE ?")
            params.append("%\(author)%")
        }
        if let yearFrom {
            conditions.append("p.year >= ?")
            params.append(yearFrom)
        }
        if let yearTo {
            conditions.append("p.year <= ?")
            params.append(yearTo)
        }
        if let journal, !journal.isEmpty {
            conditions.append("p.journal = ?")
            params.append(journal)
        }
        if let category, !category.isEmpty {
            conditions.append("p.category = ?")
            params.append(category)
        }

        var sql = baseSQL
        for cond in conditions {
            sql += " AND \(cond)"
        }
        sql += hasQuery ? " ORDER BY rank LIMIT 500" : " ORDER BY title COLLATE NOCASE ASC LIMIT 500"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            if let str = param as? String {
                sqlite3_bind_text(stmt, idx, (str as NSString).utf8String, -1, nil)
            } else if let num = param as? Int {
                sqlite3_bind_int(stmt, idx, Int32(num))
            }
        }

        var papers: [Paper] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            papers.append(paperFromRow(stmt))
        }
        return papers
    }

    // MARK: - Categories

    func listCategories() -> [Category] {
        guard let db else { return [] }

        let sql = "SELECT category, COUNT(*) as cnt FROM papers WHERE category IS NOT NULL AND category != '' GROUP BY category ORDER BY category COLLATE NOCASE ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var categories: [Category] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let count = Int(sqlite3_column_int(stmt, 1))
            categories.append(Category(name: name, paperCount: count))
        }
        return categories
    }

    func totalPaperCount() -> Int {
        guard let db else { return 0 }
        let sql = "SELECT COUNT(*) FROM papers"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    // MARK: - Update Paper

    func updatePaper(id: String, filePath: String, category: String) -> Bool {
        guard let db else { return false }

        let sql = "UPDATE papers SET file_path = ?, category = ?, updated_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (filePath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (category as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (id as NSString).utf8String, -1, nil)

        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            NotificationCenter.default.post(name: .paperUpdated, object: nil, userInfo: ["id": id])
        }
        return success
    }

    // MARK: - Update Metadata

    func updatePaperMetadata(id: String, title: String, authors: String, authorsAll: String, year: Int?, journal: String, journalAbbrev: String) -> Bool {
        guard let db else { return false }

        let sql = "UPDATE papers SET title = ?, authors = ?, authors_full = ?, year = ?, journal = ?, journal_abbrev = ?, updated_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (authors as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (authorsAll as NSString).utf8String, -1, nil)
        if let year {
            sqlite3_bind_int(stmt, 4, Int32(year))
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_text(stmt, 5, (journal as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (journalAbbrev as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (now as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, (id as NSString).utf8String, -1, nil)

        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            NotificationCenter.default.post(name: .paperUpdated, object: nil, userInfo: ["id": id])
        }
        return success
    }

    // MARK: - Update Keywords

    func updatePaperKeywords(id: String, keywords: String) -> Bool {
        guard let db else { return false }

        let sql = "UPDATE papers SET keywords = ?, updated_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (keywords as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (now as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (id as NSString).utf8String, -1, nil)

        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            NotificationCenter.default.post(name: .paperUpdated, object: nil, userInfo: ["id": id])
        }
        return success
    }

    // MARK: - Update Summary

    func updatePaperSummary(id: String, summary: String) -> Bool {
        guard let db else { return false }

        let sql = "UPDATE papers SET summary = ?, updated_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (summary as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (now as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (id as NSString).utf8String, -1, nil)

        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            NotificationCenter.default.post(name: .paperUpdated, object: nil, userInfo: ["id": id])
        }
        return success
    }

    // MARK: - Delete Paper

    func deletePaper(id: String) -> Bool {
        guard let db else { return false }

        // Get SHA-256 before deleting for the notification
        let paper = findPaperById(id)
        let sha256 = paper?.sha256 ?? ""

        let sql = "DELETE FROM papers WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)

        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            NotificationCenter.default.post(name: .paperDeleted, object: nil, userInfo: ["id": id, "sha256": sha256])
        }
        return success
    }

    func findPaperById(_ id: String) -> Paper? {
        guard let db else { return nil }
        let sql = "SELECT * FROM papers WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return paperFromRow(stmt)
        }
        return nil
    }

    // MARK: - Change Detection

    func hasChanged() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
              let modified = attrs[.modificationDate] as? Date else {
            // DB file doesn't exist yet — if we haven't opened before, check again
            if db == nil && databaseExists {
                return true
            }
            return false
        }
        if lastModified == nil {
            lastModified = modified
            return true
        }
        if let last = lastModified, modified > last {
            lastModified = modified
            // Reopen connection so SQLite reads fresh data
            reopenConnection()
            return true
        }
        return false
    }

    /// Force-reload: close and reopen connection, reset change tracking.
    /// Use after a write operation (e.g. CLI add/remove) to guarantee fresh data.
    func forceReload() {
        if let db {
            sqlite3_close(db)
        }
        db = nil

        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &handle, flags, nil)
        if rc == SQLITE_OK, let handle {
            db = handle
        }
        updateLastModified()
    }

    /// Close and reopen the database to pick up external changes
    private func reopenConnection() {
        if let db {
            sqlite3_close(db)
        }
        db = nil

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &handle, flags, nil)
        if rc == SQLITE_OK, let handle {
            db = handle
        }
    }

    private func updateLastModified() {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
           let modified = attrs[.modificationDate] as? Date {
            lastModified = modified
        }
    }

    // MARK: - JSON Manifest Export

    /// Export all paper records as a JSON-compatible dictionary keyed by SHA-256 hash
    func exportManifest() -> [String: [String: Any]] {
        let papers = listPapers(limit: Int(Int32.max), offset: 0)
        var manifest: [String: [String: Any]] = [:]
        for paper in papers {
            manifest[paper.sha256] = paperToManifestEntry(paper)
        }
        return manifest
    }

    /// Export only records with updatedAt after the given timestamp
    func exportManifestIncremental(since: String) -> [String: [String: Any]] {
        guard let db else { return [:] }

        let sql = "SELECT * FROM papers WHERE updated_at > ? ORDER BY updated_at ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (since as NSString).utf8String, -1, nil)

        var manifest: [String: [String: Any]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let paper = paperFromRow(stmt)
            manifest[paper.sha256] = paperToManifestEntry(paper)
        }
        return manifest
    }

    private func paperToManifestEntry(_ paper: Paper) -> [String: Any] {
        var entry: [String: Any] = [
            "id": paper.id,
            "title": paper.title,
            "authors": paper.authors,
            "authorsAll": paper.authorsAll,
            "journal": paper.journal,
            "journalAbbrev": paper.journalAbbrev,
            "summary": paper.summary,
            "keywords": paper.keywords,
            "category": paper.category,
            "filePath": paper.filePath,
            "createdAt": paper.createdAt,
            "updatedAt": paper.updatedAt
        ]
        if let year = paper.year { entry["year"] = year }
        if let confidence = paper.confidence { entry["confidence"] = confidence }
        return entry
    }

    /// Write the full manifest to a JSON file at the given path
    func writeManifest(to url: URL) throws {
        let manifest = exportManifest()
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - JSON Manifest Import

    /// Merge paper records from a JSON manifest into the local database.
    /// For each entry: insert if absent (by SHA-256), update if remote updatedAt is newer.
    /// Returns (inserted: Int, updated: Int) counts.
    @discardableResult
    func importManifest(from manifest: [String: [String: Any]]) -> (inserted: Int, updated: Int) {
        guard self.db != nil else { return (0, 0) }
        var inserted = 0
        var updated = 0

        for (sha256, entry) in manifest {
            // Check if paper exists locally
            let existing = findPaperBySHA256(sha256)

            if let existing {
                // Compare updatedAt — last-write-wins
                let remoteUpdated = entry["updatedAt"] as? String ?? ""
                if remoteUpdated > existing.updatedAt {
                    if updatePaperFromManifest(id: existing.id, entry: entry) {
                        updated += 1
                        NotificationCenter.default.post(name: .paperUpdated, object: nil, userInfo: ["sha256": sha256, "id": existing.id])
                    }
                }
            } else {
                // Insert new record
                if insertPaperFromManifest(sha256: sha256, entry: entry) {
                    inserted += 1
                    let id = entry["id"] as? String ?? ""
                    NotificationCenter.default.post(name: .paperAdded, object: nil, userInfo: ["sha256": sha256, "id": id])
                }
            }
        }
        return (inserted, updated)
    }

    func findPaperBySHA256(_ sha256: String) -> Paper? {
        guard let db else { return nil }
        let sql = "SELECT * FROM papers WHERE sha256 = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sha256 as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return paperFromRow(stmt)
        }
        return nil
    }

    private func insertPaperFromManifest(sha256: String, entry: [String: Any]) -> Bool {
        guard let db else { return false }
        let sql = """
            INSERT INTO papers (id, sha256, title, authors, authors_full, year, journal, journal_abbrev,
                                summary, keywords, category, file_path, confidence, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        let id = entry["id"] as? String ?? UUID().uuidString.prefix(8).lowercased()
        let title = entry["title"] as? String ?? ""
        let authors = entry["authors"] as? String ?? ""
        let authorsAll = entry["authorsAll"] as? String ?? ""
        let journal = entry["journal"] as? String ?? ""
        let journalAbbrev = entry["journalAbbrev"] as? String ?? ""
        let summary = entry["summary"] as? String ?? ""
        let keywords = entry["keywords"] as? String ?? ""
        let category = entry["category"] as? String ?? ""
        let filePath = entry["filePath"] as? String ?? ""
        let createdAt = entry["createdAt"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let updatedAt = entry["updatedAt"] as? String ?? ISO8601DateFormatter().string(from: Date())

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (sha256 as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (authors as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (authorsAll as NSString).utf8String, -1, nil)
        if let year = entry["year"] as? Int {
            sqlite3_bind_int(stmt, 6, Int32(year))
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_text(stmt, 7, (journal as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, (journalAbbrev as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 9, (summary as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 10, (keywords as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 11, (category as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 12, (filePath as NSString).utf8String, -1, nil)
        if let confidence = entry["confidence"] as? Double {
            sqlite3_bind_double(stmt, 13, confidence)
        } else {
            sqlite3_bind_null(stmt, 13)
        }
        sqlite3_bind_text(stmt, 14, (createdAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 15, (updatedAt as NSString).utf8String, -1, nil)

        return sqlite3_step(stmt) == SQLITE_DONE
    }

    private func updatePaperFromManifest(id: String, entry: [String: Any]) -> Bool {
        guard let db else { return false }
        let sql = """
            UPDATE papers SET title = ?, authors = ?, authors_full = ?, year = ?, journal = ?,
                journal_abbrev = ?, summary = ?, keywords = ?, category = ?, confidence = ?, updated_at = ?
            WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, ((entry["title"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, ((entry["authors"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, ((entry["authorsAll"] as? String ?? "") as NSString).utf8String, -1, nil)
        if let year = entry["year"] as? Int {
            sqlite3_bind_int(stmt, 4, Int32(year))
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_text(stmt, 5, ((entry["journal"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, ((entry["journalAbbrev"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, ((entry["summary"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, ((entry["keywords"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 9, ((entry["category"] as? String ?? "") as NSString).utf8String, -1, nil)
        if let confidence = entry["confidence"] as? Double {
            sqlite3_bind_double(stmt, 10, confidence)
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        sqlite3_bind_text(stmt, 11, ((entry["updatedAt"] as? String ?? "") as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 12, (id as NSString).utf8String, -1, nil)

        return sqlite3_step(stmt) == SQLITE_DONE
    }

    // MARK: - Chat Schema Migration (v2)

    private func migrateToV2() {
        guard let db else { return }
        // Check if migration is needed by testing for paper_chunks table
        let checkSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='paper_chunks'"
        var checkStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(checkStmt) }
        if sqlite3_step(checkStmt) == SQLITE_ROW { return } // Already migrated

        let migrations = [
            """
            CREATE TABLE IF NOT EXISTS paper_chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                paper_id TEXT NOT NULL,
                page_number INTEGER NOT NULL,
                chunk_index INTEGER NOT NULL,
                text TEXT NOT NULL,
                embedding BLOB,
                indexed_at TEXT NOT NULL,
                FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_paper_chunks_paper_id ON paper_chunks(paper_id)",
            """
            CREATE TABLE IF NOT EXISTS paper_index_meta (
                paper_id TEXT PRIMARY KEY,
                pdf_modified_at TEXT NOT NULL,
                suggested_questions TEXT,
                indexed_at TEXT NOT NULL,
                FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS chat_conversations (
                id TEXT PRIMARY KEY,
                paper_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_chat_conversations_paper_id ON chat_conversations(paper_id)",
            """
            CREATE TABLE IF NOT EXISTS chat_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                citations TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation_id ON chat_messages(conversation_id)",
            "PRAGMA foreign_keys = ON"
        ]

        for sql in migrations {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }

    // MARK: - Paper Chunks

    func insertChunks(_ chunks: [(paperId: String, pageNumber: Int, chunkIndex: Int, text: String, embedding: Data?)], indexedAt: String) {
        guard let db else { return }

        let sql = "INSERT INTO paper_chunks (paper_id, page_number, chunk_index, text, embedding, indexed_at) VALUES (?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for chunk in chunks {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, (chunk.paperId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(chunk.pageNumber))
            sqlite3_bind_int(stmt, 3, Int32(chunk.chunkIndex))
            sqlite3_bind_text(stmt, 4, (chunk.text as NSString).utf8String, -1, nil)
            if let embedding = chunk.embedding {
                embedding.withUnsafeBytes { ptr in
                    _ = sqlite3_bind_blob(stmt, 5, ptr.baseAddress, Int32(embedding.count), nil)
                }
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            sqlite3_bind_text(stmt, 6, (indexedAt as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
    }

    func deleteChunks(forPaper paperId: String) {
        guard let db else { return }
        let sql = "DELETE FROM paper_chunks WHERE paper_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (paperId as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    func loadChunks(forPaper paperId: String) -> [PaperChunk] {
        guard let db else { return [] }
        let sql = "SELECT id, paper_id, page_number, chunk_index, text, embedding FROM paper_chunks WHERE paper_id = ? ORDER BY chunk_index"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (paperId as NSString).utf8String, -1, nil)

        var chunks: [PaperChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(stmt, 0))
            let paperId = String(cString: sqlite3_column_text(stmt, 1))
            let pageNumber = Int(sqlite3_column_int(stmt, 2))
            let chunkIndex = Int(sqlite3_column_int(stmt, 3))
            let text = String(cString: sqlite3_column_text(stmt, 4))
            var embedding: Data?
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
                let bytes = sqlite3_column_blob(stmt, 5)
                let count = Int(sqlite3_column_bytes(stmt, 5))
                if let bytes, count > 0 {
                    embedding = Data(bytes: bytes, count: count)
                }
            }
            chunks.append(PaperChunk(id: id, paperId: paperId, pageNumber: pageNumber, chunkIndex: chunkIndex, text: text, embedding: embedding))
        }
        return chunks
    }

    // MARK: - Index Metadata

    func saveIndexMeta(paperId: String, pdfModifiedAt: String, suggestedQuestions: [String], indexedAt: String) {
        guard let db else { return }
        let questionsJSON = (try? JSONSerialization.data(withJSONObject: suggestedQuestions)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let sql = "INSERT OR REPLACE INTO paper_index_meta (paper_id, pdf_modified_at, suggested_questions, indexed_at) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (paperId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (pdfModifiedAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (questionsJSON as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (indexedAt as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    func loadIndexMeta(forPaper paperId: String) -> IndexMeta? {
        guard let db else { return nil }
        let sql = "SELECT paper_id, pdf_modified_at, suggested_questions, indexed_at FROM paper_index_meta WHERE paper_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (paperId as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let pdfModifiedAt = String(cString: sqlite3_column_text(stmt, 1))
        let questionsStr = String(cString: sqlite3_column_text(stmt, 2))
        let indexedAt = String(cString: sqlite3_column_text(stmt, 3))

        let questions: [String] = (try? JSONSerialization.jsonObject(with: Data(questionsStr.utf8)) as? [String]) ?? []
        return IndexMeta(paperId: paperId, pdfModifiedAt: pdfModifiedAt, suggestedQuestions: questions, indexedAt: indexedAt)
    }

    func deleteIndexMeta(forPaper paperId: String) {
        guard let db else { return }
        let sql = "DELETE FROM paper_index_meta WHERE paper_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (paperId as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    // MARK: - Chat Conversations

    func createConversation(id: String, paperId: String, createdAt: String) {
        guard let db else { return }
        let sql = "INSERT INTO chat_conversations (id, paper_id, created_at) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (paperId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (createdAt as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    func loadConversations(forPaper paperId: String) -> [ChatConversation] {
        guard let db else { return [] }
        let sql = "SELECT id, paper_id, created_at FROM chat_conversations WHERE paper_id = ? ORDER BY created_at DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (paperId as NSString).utf8String, -1, nil)

        var conversations: [ChatConversation] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            conversations.append(ChatConversation(
                id: String(cString: sqlite3_column_text(stmt, 0)),
                paperId: String(cString: sqlite3_column_text(stmt, 1)),
                createdAt: String(cString: sqlite3_column_text(stmt, 2))
            ))
        }
        return conversations
    }

    // MARK: - Chat Messages

    @discardableResult
    func insertMessage(conversationId: String, role: String, content: String, citations: String?, createdAt: String) -> Int {
        guard let db else { return 0 }
        let sql = "INSERT INTO chat_messages (conversation_id, role, content, citations, created_at) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (conversationId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (role as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (content as NSString).utf8String, -1, nil)
        if let citations {
            sqlite3_bind_text(stmt, 4, (citations as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_text(stmt, 5, (createdAt as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        return Int(sqlite3_last_insert_rowid(db))
    }

    func deleteMessage(id: Int) {
        guard let db else { return }
        let sql = "DELETE FROM chat_messages WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(id))
        sqlite3_step(stmt)
    }

    func loadMessages(forConversation conversationId: String) -> [ChatMessage] {
        guard let db else { return [] }
        let sql = "SELECT id, conversation_id, role, content, citations, created_at FROM chat_messages WHERE conversation_id = ? ORDER BY created_at ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (conversationId as NSString).utf8String, -1, nil)

        var messages: [ChatMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let citationsStr: String? = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 4)) : nil
            messages.append(ChatMessage(
                id: Int(sqlite3_column_int64(stmt, 0)),
                conversationId: String(cString: sqlite3_column_text(stmt, 1)),
                role: String(cString: sqlite3_column_text(stmt, 2)),
                content: String(cString: sqlite3_column_text(stmt, 3)),
                citations: citationsStr,
                createdAt: String(cString: sqlite3_column_text(stmt, 5))
            ))
        }
        return messages
    }

    // MARK: - Row Mapping

    private func paperFromRow(_ stmt: OpaquePointer?) -> Paper {
        func col(_ idx: Int32) -> String {
            guard let cStr = sqlite3_column_text(stmt, idx) else { return "" }
            return String(cString: cStr)
        }

        func colInt(_ idx: Int32) -> Int? {
            sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, idx))
        }

        func colDouble(_ idx: Int32) -> Double? {
            sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, idx)
        }

        return Paper(
            id: col(0),
            sha256: col(1),
            title: col(2),
            authors: col(3),
            authorsAll: col(4),
            year: colInt(5),
            journal: col(6),
            journalAbbrev: col(7),
            summary: col(8),
            keywords: col(9),
            category: col(10),
            filePath: col(11),
            confidence: colDouble(12),
            createdAt: col(13),
            updatedAt: col(14)
        )
    }
}

// MARK: - Paper Change Notifications

extension Notification.Name {
    static let paperAdded = Notification.Name("paperAdded")
    static let paperUpdated = Notification.Name("paperUpdated")
    static let paperDeleted = Notification.Name("paperDeleted")
}

enum DatabaseError: LocalizedError {
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg):
            return "Failed to open database: \(msg)"
        }
    }
}
