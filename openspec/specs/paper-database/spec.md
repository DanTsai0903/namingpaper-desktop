## ADDED Requirements

### Requirement: SQLite database initialization
The system SHALL create and manage a SQLite database at `~/.namingpaper/library.db`. On first use of any library command, the system SHALL create the database file and parent directory if they do not exist. The database SHALL use WAL journal mode for concurrent read access.

#### Scenario: First library command creates database
- **WHEN** user runs any library command and `~/.namingpaper/library.db` does not exist
- **THEN** system creates the directory and database file with the initial schema

#### Scenario: Existing database is reused
- **WHEN** user runs a library command and `~/.namingpaper/library.db` already exists
- **THEN** system opens the existing database without data loss

### Requirement: Schema versioning and migration
The system SHALL track schema versions in a `schema_version` table and apply ordered migrations on database open. Migrations SHALL be forward-only. Before any destructive migration step, the system SHALL create a backup of the database file.

#### Scenario: Database at older schema version
- **WHEN** system opens a database with schema version N and current code expects version M > N
- **THEN** system applies migrations N+1 through M in order and updates the schema version

#### Scenario: Database at current version
- **WHEN** system opens a database already at the current schema version
- **THEN** no migrations are applied and the database opens normally

#### Scenario: Backup before destructive migration
- **WHEN** a migration includes a destructive step (column removal, table drop)
- **THEN** system copies `library.db` to `library.db.backup-vN` before applying the migration

### Requirement: Papers table schema
The system SHALL store paper records in a `papers` table with these columns: `id` (TEXT PRIMARY KEY, short hex hash), `sha256` (TEXT UNIQUE, content hash), `title` (TEXT NOT NULL), `authors` (TEXT NOT NULL, JSON array), `authors_full` (TEXT, JSON array), `year` (INTEGER NOT NULL), `journal` (TEXT NOT NULL), `journal_abbrev` (TEXT), `summary` (TEXT), `keywords` (TEXT, JSON array), `category` (TEXT), `file_path` (TEXT NOT NULL), `confidence` (REAL), `created_at` (TEXT NOT NULL, ISO 8601), `updated_at` (TEXT NOT NULL, ISO 8601).

#### Scenario: Insert a complete paper record
- **WHEN** a paper with all metadata fields is persisted
- **THEN** all fields are stored and retrievable by id

#### Scenario: Insert a paper with minimal metadata
- **WHEN** a paper with only required fields (id, sha256, title, authors, year, journal, file_path, created_at, updated_at) is persisted
- **THEN** optional fields (summary, keywords, category, journal_abbrev, authors_full, confidence) are stored as NULL

### Requirement: CRUD operations
The system SHALL provide create, read, update, and delete operations for paper records. All write operations (create, update, delete) SHALL be wrapped in transactions.

#### Scenario: Create a paper record
- **WHEN** a new paper record is inserted
- **THEN** the record is persisted and the id is returned

#### Scenario: Read a paper by id
- **WHEN** a paper is queried by its id
- **THEN** the full record is returned, or None if not found

#### Scenario: Update paper metadata
- **WHEN** a paper's metadata fields are updated (e.g., category, summary)
- **THEN** the specified fields are changed and `updated_at` is set to the current timestamp

#### Scenario: Delete a paper record
- **WHEN** a paper record is deleted by id
- **THEN** the record and its FTS index entry are removed

### Requirement: Duplicate detection by content hash
The system SHALL compute SHA-256 hash of PDF file contents and use it as the dedup key. Before inserting a new paper, the system SHALL check for an existing record with the same `sha256` value.

#### Scenario: Duplicate file detected
- **WHEN** a PDF with the same SHA-256 hash as an existing record is added
- **THEN** the system skips insertion and returns the existing record

#### Scenario: Unique file added
- **WHEN** a PDF with a SHA-256 hash not present in the database is added
- **THEN** the system proceeds with insertion

### Requirement: Full-text search with FTS5
The system SHALL maintain an FTS5 virtual table indexing `title`, `authors`, `journal`, `summary`, and `keywords` fields. The FTS index SHALL be updated transactionally with the base `papers` table on insert, update, and delete.

#### Scenario: Keyword search returns matching papers
- **WHEN** user searches for "risk factors"
- **THEN** system returns papers where any indexed field contains those terms, ranked by FTS5 relevance

#### Scenario: FTS index stays consistent after update
- **WHEN** a paper's summary is updated
- **THEN** subsequent searches reflect the updated summary content

#### Scenario: FTS index stays consistent after delete
- **WHEN** a paper record is deleted
- **THEN** the paper no longer appears in search results

### Requirement: Filtered queries
The system SHALL support filtering paper records by author, year (single or range), journal, and category. Filters SHALL be combinable with full-text search queries.

#### Scenario: Filter by author
- **WHEN** user queries with author filter "Fama"
- **THEN** system returns only papers where the authors array contains "Fama"

#### Scenario: Filter by year range
- **WHEN** user queries with year range 2020-2024
- **THEN** system returns only papers with year between 2020 and 2024 inclusive

#### Scenario: Combined keyword search and filter
- **WHEN** user searches "asset pricing" with journal filter "JFE"
- **THEN** system returns papers matching "asset pricing" in FTS that also have journal or journal_abbrev matching "JFE"
