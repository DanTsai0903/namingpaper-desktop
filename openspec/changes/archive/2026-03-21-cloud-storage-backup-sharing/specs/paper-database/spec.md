## MODIFIED Requirements

### Requirement: SQLite database initialization
The system SHALL create and manage a SQLite database at a configurable location (default: `~/.namingpaper/library.db`). On first use of any library command, the system SHALL create the database file and parent directory if they do not exist. The database SHALL use WAL journal mode for concurrent read access. When iCloud sync is enabled, the system SHALL support a secondary database location within the iCloud Drive sync container for export purposes.

#### Scenario: First library command creates database
- **WHEN** user runs any library command and the configured database path does not exist
- **THEN** system creates the directory and database file with the initial schema

#### Scenario: Existing database is reused
- **WHEN** user runs a library command and the database already exists at the configured path
- **THEN** system opens the existing database without data loss

#### Scenario: Database location configured via settings
- **WHEN** user has configured a custom database location in settings
- **THEN** system uses the configured path instead of the default `~/.namingpaper/library.db`

## ADDED Requirements

### Requirement: Database export to JSON manifest
The system SHALL provide an operation to export all paper records to a JSON manifest file. The manifest SHALL be a JSON object keyed by SHA-256 hash, with each value containing the full paper metadata and an `updatedAt` timestamp. This export SHALL be used by the sync layer.

#### Scenario: Full database export
- **WHEN** the sync layer requests a full export
- **THEN** system writes all paper records to a JSON file keyed by SHA-256 hash

#### Scenario: Incremental export
- **WHEN** the sync layer requests changes since a given timestamp
- **THEN** system returns only records with `updatedAt` after the given timestamp

### Requirement: Database import from JSON manifest
The system SHALL provide an operation to merge paper records from a JSON manifest into the local database. For each entry, the system SHALL check for an existing record by SHA-256 hash: if absent, insert; if present, apply last-write-wins based on `updatedAt`.

#### Scenario: Import new paper from manifest
- **WHEN** a manifest entry has a SHA-256 not present in the local database
- **THEN** system inserts the record into the local database

#### Scenario: Import updated metadata from manifest
- **WHEN** a manifest entry has a SHA-256 matching a local record and a later `updatedAt`
- **THEN** system updates the local record with the manifest metadata

#### Scenario: Local record is newer
- **WHEN** a manifest entry has a SHA-256 matching a local record and an earlier `updatedAt`
- **THEN** system keeps the local record unchanged

### Requirement: Change notification for sync
The system SHALL emit notifications when paper records are created, updated, or deleted. The sync layer SHALL observe these notifications to trigger manifest updates.

#### Scenario: Paper added triggers notification
- **WHEN** a new paper record is inserted into the database
- **THEN** system emits a `paperAdded` notification with the paper's SHA-256 and metadata

#### Scenario: Paper deleted triggers notification
- **WHEN** a paper record is deleted from the database
- **THEN** system emits a `paperDeleted` notification with the paper's SHA-256
