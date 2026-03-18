"""SQLite database layer for the paper library."""

import hashlib
import json
import shutil
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from namingpaper.models import Paper, SearchFilter

# Default database path
DEFAULT_DB_PATH = Path.home() / ".namingpaper" / "library.db"

# Schema migrations: list of (version, description, sql_statements)
# Each migration is a tuple of (version, description, list_of_sql, is_destructive)
MIGRATIONS: list[tuple[int, str, list[str], bool]] = [
    (
        1,
        "Initial schema: papers table and FTS5 index",
        [
            """CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER NOT NULL,
                applied_at TEXT NOT NULL
            )""",
            """CREATE TABLE IF NOT EXISTS papers (
                id TEXT PRIMARY KEY,
                sha256 TEXT UNIQUE NOT NULL,
                title TEXT NOT NULL,
                authors TEXT NOT NULL,
                authors_full TEXT,
                year INTEGER NOT NULL,
                journal TEXT NOT NULL,
                journal_abbrev TEXT,
                summary TEXT,
                keywords TEXT,
                category TEXT,
                file_path TEXT NOT NULL,
                confidence REAL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )""",
            """CREATE VIRTUAL TABLE IF NOT EXISTS papers_fts USING fts5(
                title, authors, journal, summary, keywords,
                content='papers',
                content_rowid='rowid'
            )""",
            # Triggers to keep FTS in sync
            """CREATE TRIGGER IF NOT EXISTS papers_ai AFTER INSERT ON papers BEGIN
                INSERT INTO papers_fts(rowid, title, authors, journal, summary, keywords)
                VALUES (new.rowid, new.title, new.authors, new.journal, new.summary, new.keywords);
            END""",
            """CREATE TRIGGER IF NOT EXISTS papers_ad AFTER DELETE ON papers BEGIN
                INSERT INTO papers_fts(papers_fts, rowid, title, authors, journal, summary, keywords)
                VALUES ('delete', old.rowid, old.title, old.authors, old.journal, old.summary, old.keywords);
            END""",
            """CREATE TRIGGER IF NOT EXISTS papers_au AFTER UPDATE ON papers BEGIN
                INSERT INTO papers_fts(papers_fts, rowid, title, authors, journal, summary, keywords)
                VALUES ('delete', old.rowid, old.title, old.authors, old.journal, old.summary, old.keywords);
                INSERT INTO papers_fts(rowid, title, authors, journal, summary, keywords)
                VALUES (new.rowid, new.title, new.authors, new.journal, new.summary, new.keywords);
            END""",
        ],
        False,
    ),
]


class Database:
    """SQLite database manager for the paper library."""

    def __init__(self, db_path: Path | None = None):
        self.db_path = db_path or DEFAULT_DB_PATH
        self._conn: sqlite3.Connection | None = None

    def open(self) -> None:
        """Open the database connection, creating it if needed."""
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.db_path))
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._apply_migrations()

    def close(self) -> None:
        """Close the database connection."""
        if self._conn:
            self._conn.close()
            self._conn = None

    def __enter__(self) -> "Database":
        self.open()
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    @property
    def conn(self) -> sqlite3.Connection:
        if self._conn is None:
            raise RuntimeError("Database not open. Call open() or use as context manager.")
        return self._conn

    # -- Schema versioning and migrations --

    def _get_schema_version(self) -> int:
        """Get the current schema version, or 0 if no migrations applied."""
        try:
            row = self.conn.execute(
                "SELECT MAX(version) FROM schema_version"
            ).fetchone()
            return row[0] or 0
        except sqlite3.OperationalError:
            return 0

    def _apply_migrations(self) -> None:
        """Apply pending migrations."""
        current = self._get_schema_version()
        for version, _desc, statements, destructive in MIGRATIONS:
            if version <= current:
                continue
            if destructive:
                backup_path = self.db_path.with_suffix(f".db.backup-v{current}")
                shutil.copy2(self.db_path, backup_path)
            with self.conn:
                for sql in statements:
                    self.conn.execute(sql)
                self.conn.execute(
                    "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
                    (version, datetime.now(timezone.utc).isoformat()),
                )

    # -- CRUD operations --

    def create_paper(self, paper: Paper) -> Paper:
        """Insert a new paper record. Returns the paper with id set."""
        with self.conn:
            self.conn.execute(
                """INSERT INTO papers
                   (id, sha256, title, authors, authors_full, year, journal,
                    journal_abbrev, summary, keywords, category, file_path,
                    confidence, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    paper.id,
                    paper.sha256,
                    paper.title,
                    json.dumps(paper.authors),
                    json.dumps(paper.authors_full) if paper.authors_full else None,
                    paper.year,
                    paper.journal,
                    paper.journal_abbrev,
                    paper.summary,
                    json.dumps(paper.keywords) if paper.keywords else None,
                    paper.category,
                    str(paper.file_path),
                    paper.confidence,
                    paper.created_at,
                    paper.updated_at,
                ),
            )
        return paper

    def get_paper(self, paper_id: str) -> Paper | None:
        """Get a paper by id."""
        row = self.conn.execute(
            "SELECT * FROM papers WHERE id = ?", (paper_id,)
        ).fetchone()
        if row is None:
            return None
        return self._row_to_paper(row)

    def get_paper_by_hash(self, sha256: str) -> Paper | None:
        """Get a paper by content hash."""
        row = self.conn.execute(
            "SELECT * FROM papers WHERE sha256 = ?", (sha256,)
        ).fetchone()
        if row is None:
            return None
        return self._row_to_paper(row)

    def update_paper(self, paper_id: str, **fields: object) -> bool:
        """Update specific fields of a paper record.

        Returns True if the paper was found and updated.
        """
        if not fields:
            return False
        fields["updated_at"] = datetime.now(timezone.utc).isoformat()
        # Serialize list fields
        for key in ("authors", "authors_full", "keywords"):
            if key in fields and isinstance(fields[key], list):
                fields[key] = json.dumps(fields[key])
        if "file_path" in fields:
            fields["file_path"] = str(fields["file_path"])
        set_clause = ", ".join(f"{k} = ?" for k in fields)
        values = list(fields.values()) + [paper_id]
        with self.conn:
            cursor = self.conn.execute(
                f"UPDATE papers SET {set_clause} WHERE id = ?", values
            )
        return cursor.rowcount > 0

    def delete_paper(self, paper_id: str) -> bool:
        """Delete a paper by id. Returns True if found and deleted."""
        with self.conn:
            cursor = self.conn.execute(
                "DELETE FROM papers WHERE id = ?", (paper_id,)
            )
        return cursor.rowcount > 0

    def list_papers(
        self,
        category: str | None = None,
        sort_by: str = "created_at",
        limit: int = 20,
    ) -> list[Paper]:
        """List papers with optional category filter and sorting."""
        valid_sorts = {"created_at", "year", "title", "authors"}
        if sort_by not in valid_sorts:
            sort_by = "created_at"
        order = "DESC" if sort_by == "created_at" else "ASC"

        query = "SELECT * FROM papers"
        params: list[object] = []
        if category:
            query += " WHERE category = ?"
            params.append(category)
        query += f" ORDER BY {sort_by} {order} LIMIT ?"
        params.append(limit)

        rows = self.conn.execute(query, params).fetchall()
        return [self._row_to_paper(r) for r in rows]

    # -- Search --

    def search(
        self,
        query: str | None = None,
        filters: SearchFilter | None = None,
    ) -> list[Paper]:
        """Search papers using FTS5 and/or filters."""
        if query and not filters:
            return self._fts_search(query)
        if not query and filters:
            return self._filtered_search(filters)
        if query and filters:
            return self._combined_search(query, filters)
        return self.list_papers()

    def _fts_search(self, query: str) -> list[Paper]:
        """Full-text search using FTS5."""
        rows = self.conn.execute(
            """SELECT papers.* FROM papers
               JOIN papers_fts ON papers.rowid = papers_fts.rowid
               WHERE papers_fts MATCH ?
               ORDER BY rank""",
            (query,),
        ).fetchall()
        return [self._row_to_paper(r) for r in rows]

    def _filtered_search(self, filters: SearchFilter) -> list[Paper]:
        """Search with field filters only."""
        where_clauses, params = self._build_filter_clauses(filters)
        query = "SELECT * FROM papers"
        if where_clauses:
            query += " WHERE " + " AND ".join(where_clauses)
        query += " ORDER BY year DESC"
        return [self._row_to_paper(r) for r in self.conn.execute(query, params).fetchall()]

    def _combined_search(self, query: str, filters: SearchFilter) -> list[Paper]:
        """FTS search combined with field filters."""
        where_clauses, params = self._build_filter_clauses(filters)
        sql = """SELECT papers.* FROM papers
                 JOIN papers_fts ON papers.rowid = papers_fts.rowid
                 WHERE papers_fts MATCH ?"""
        all_params: list[object] = [query]
        if where_clauses:
            sql += " AND " + " AND ".join(where_clauses)
            all_params.extend(params)
        sql += " ORDER BY rank"
        return [self._row_to_paper(r) for r in self.conn.execute(sql, all_params).fetchall()]

    def _build_filter_clauses(
        self, filters: SearchFilter
    ) -> tuple[list[str], list[object]]:
        """Build WHERE clauses from a SearchFilter."""
        clauses: list[str] = []
        params: list[object] = []
        if filters.author:
            clauses.append("papers.authors LIKE ?")
            params.append(f"%{filters.author}%")
        if filters.year_from is not None:
            clauses.append("papers.year >= ?")
            params.append(filters.year_from)
        if filters.year_to is not None:
            clauses.append("papers.year <= ?")
            params.append(filters.year_to)
        if filters.journal:
            clauses.append("(papers.journal LIKE ? OR papers.journal_abbrev LIKE ?)")
            params.extend([f"%{filters.journal}%", f"%{filters.journal}%"])
        if filters.category:
            clauses.append("papers.category = ?")
            params.append(filters.category)
        return clauses, params

    # -- Helpers --

    @staticmethod
    def _row_to_paper(row: sqlite3.Row) -> Paper:
        """Convert a database row to a Paper model."""
        return Paper(
            id=row["id"],
            sha256=row["sha256"],
            title=row["title"],
            authors=json.loads(row["authors"]),
            authors_full=json.loads(row["authors_full"]) if row["authors_full"] else [],
            year=row["year"],
            journal=row["journal"],
            journal_abbrev=row["journal_abbrev"],
            summary=row["summary"],
            keywords=json.loads(row["keywords"]) if row["keywords"] else [],
            category=row["category"],
            file_path=row["file_path"],
            confidence=row["confidence"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )


def compute_file_hash(file_path: Path) -> str:
    """Compute SHA-256 hash of a file."""
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def generate_paper_id(sha256: str) -> str:
    """Generate a short paper ID from the content hash."""
    return sha256[:8]
