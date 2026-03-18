## ADDED Requirements

### Requirement: Read-only SQLite connection

`DatabaseService` SHALL open `~/.namingpaper/library.db` using `sqlite3_open_v2` with `SQLITE_OPEN_READONLY` flag. The connection SHALL be compatible with WAL mode (Python writes with WAL, Swift reads concurrently). If the database file does not exist, `DatabaseService` SHALL report an empty library without creating the file.

#### Scenario: Open existing database

- **WHEN** the app launches and `library.db` exists
- **THEN** `DatabaseService` opens a read-only connection and loads papers

#### Scenario: Database file missing

- **WHEN** the app launches and `library.db` does not exist
- **THEN** `DatabaseService` reports zero papers and the app shows the empty/onboarding state

#### Scenario: Concurrent read during CLI write

- **WHEN** the CLI is writing to the database while the app queries
- **THEN** the read completes successfully (WAL mode allows concurrent readers)

### Requirement: Paper model mapping

`DatabaseService` SHALL map rows from the `papers` table to a Swift `Paper` struct with fields: id, sha256, title, authors, authorsAll, year, journal, journalAbbrev, summary, keywords, category, filePath, confidence, createdAt, updatedAt. Unknown columns SHALL be ignored for forward compatibility.

#### Scenario: Map full paper row

- **WHEN** a row with all columns is read from the database
- **THEN** a `Paper` struct is created with all fields populated

#### Scenario: Database has extra columns

- **WHEN** the database has columns not known to the app (e.g., from a newer schema)
- **THEN** those columns are ignored and the paper loads without error

### Requirement: List papers with pagination

`DatabaseService` SHALL provide a method to list papers with optional limit and offset for pagination. The default limit SHALL be 100. Results SHALL be orderable by title, year, authors, or created_at.

#### Scenario: List first page of papers

- **WHEN** `listPapers(limit: 50, offset: 0, orderBy: .year)` is called
- **THEN** the first 50 papers ordered by year are returned

### Requirement: FTS5 keyword search

`DatabaseService` SHALL provide a method to search papers using the FTS5 index. The query SHALL be passed to `SELECT ... FROM papers_fts WHERE papers_fts MATCH ?` and joined with the papers table. Results SHALL include FTS5 rank for ordering.

#### Scenario: FTS5 search query

- **WHEN** `search(query: "machine learning")` is called
- **THEN** papers matching the FTS5 query are returned ordered by relevance rank

#### Scenario: Empty search query

- **WHEN** `search(query: "")` is called
- **THEN** all papers are returned (no FTS filtering)

### Requirement: Filtered queries

`DatabaseService` SHALL support filtering by author (substring match), year range (min/max), journal (exact match), and category (exact match). Filters SHALL combine with AND logic and work alongside FTS5 search.

#### Scenario: Filter by category and year

- **WHEN** `search(query: nil, category: "Finance", yearFrom: 2010, yearTo: 2020)` is called
- **THEN** only Finance papers from 2010-2020 are returned

### Requirement: Async data loading on background actor

All database queries SHALL run on a background actor (Swift `actor` or `Task` with background priority) to prevent blocking the main thread. Results SHALL be delivered to the main actor for UI updates.

#### Scenario: Large library loads without UI freeze

- **WHEN** the database has 500 papers and a search is executed
- **THEN** the UI remains responsive during query execution

### Requirement: Reactive updates on database change

`DatabaseService` SHALL detect changes to `library.db` on disk and trigger a refresh. Detection SHALL use periodic polling (every 2 seconds when the app is in the foreground) by checking the file modification timestamp. On change, the current view SHALL re-query the database.

#### Scenario: CLI adds a paper while app is open

- **WHEN** a paper is added via CLI while the app is running
- **THEN** the paper list updates within 2 seconds to include the new paper

#### Scenario: App is in background

- **WHEN** the app is not the frontmost application
- **THEN** polling pauses to conserve resources and resumes when the app becomes active

### Requirement: Schema version check

On connection, `DatabaseService` SHALL read the schema version from the `schema_version` table. If the version is higher than the app's known version, a non-blocking warning banner SHALL be displayed: "Database was updated by a newer version of namingpaper. Some features may not work correctly. Please update the app."

#### Scenario: Compatible schema version

- **WHEN** the database schema version matches or is lower than the app's known version
- **THEN** the app operates normally with no warnings

#### Scenario: Newer schema version

- **WHEN** the database schema version is higher than expected
- **THEN** a warning banner appears but the app continues to function with known columns
