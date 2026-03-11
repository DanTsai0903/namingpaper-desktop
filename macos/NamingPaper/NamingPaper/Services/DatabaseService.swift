import Foundation
import SQLite3

enum PaperSortOrder: String {
    case title, year, authors, createdAt
}

actor DatabaseService {
    static let shared = DatabaseService()

    private let dbPath: String
    private var db: OpaquePointer?
    private var lastModified: Date?

    /// Known schema version — warn if DB is newer
    private let knownSchemaVersion = 1

    /// Schema warning message if DB is newer
    var schemaWarning: String?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        dbPath = home.appendingPathComponent(".namingpaper/library.db").path
    }

    // MARK: - Connection

    func open() throws {
        guard db == nil else { return }
        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(dbPath, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw DatabaseError.openFailed(msg)
        }
        db = handle
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
        case .createdAt: orderClause = "created_at \(dir)"
        }

        let sql = "SELECT * FROM papers ORDER BY \(orderClause) LIMIT ? OFFSET ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))
        sqlite3_bind_int(stmt, 2, Int32(offset))

        var papers: [Paper] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            papers.append(paperFromRow(stmt))
        }
        return papers
    }

    // MARK: - FTS5 Search

    func search(query: String) -> [Paper] {
        guard let db else { return [] }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return listPapers(limit: 1000)
        }

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

        sqlite3_bind_text(stmt, 1, (query as NSString).utf8String, -1, nil)

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
            params.append(query!)
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

    // MARK: - Change Detection

    func hasChanged() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
              let modified = attrs[.modificationDate] as? Date else {
            return false
        }
        if let last = lastModified, modified > last {
            lastModified = modified
            return true
        }
        return false
    }

    private func updateLastModified() {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
           let modified = attrs[.modificationDate] as? Date {
            lastModified = modified
        }
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

enum DatabaseError: LocalizedError {
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg):
            return "Failed to open database: \(msg)"
        }
    }
}
