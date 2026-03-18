## ADDED Requirements

### Requirement: Unified add workflow
The system SHALL provide an `add` operation that orchestrates: (1) rename using the existing extraction pipeline, (2) AI summarization and keyword extraction, (3) AI category suggestion with user confirmation, (4) file placement into the category folder, and (5) database persistence. Each step SHALL use the output of previous steps.

#### Scenario: Full add workflow in dry-run mode
- **WHEN** user runs `add` on a PDF without `--execute`
- **THEN** system shows the planned rename, generated summary/keywords, suggested category, and target path, but performs no filesystem or database mutations

#### Scenario: Full add workflow with execute
- **WHEN** user runs `add` on a PDF with `--execute`
- **THEN** system renames the file, generates summary/keywords, prompts for category confirmation, moves the file to the category folder, and persists the record to the database

#### Scenario: Add with copy mode
- **WHEN** user runs `add` with `--copy` and `--execute`
- **THEN** the source file is preserved and a copy is placed in the category folder

### Requirement: Papers directory configuration
The system SHALL use a configurable `papers_dir` setting (default: `~/Papers`) as the root directory for organized papers. The system SHALL create `papers_dir` and an `Unsorted/` subdirectory on first use if they do not exist.

#### Scenario: Default papers directory
- **WHEN** no `papers_dir` is configured
- **THEN** system uses `~/Papers` as the root

#### Scenario: Custom papers directory
- **WHEN** user sets `papers_dir` in config or environment variable `NAMINGPAPER_PAPERS_DIR`
- **THEN** system uses the specified path as the root

#### Scenario: Directory creation on first use
- **WHEN** `papers_dir` does not exist and user runs `add --execute`
- **THEN** system creates `papers_dir` and `papers_dir/Unsorted/`

### Requirement: File placement into category folders
The system SHALL move (default) or copy (`--copy`) the renamed paper into `papers_dir/<category>/`. If the category folder does not exist, the system SHALL create it. If no category is selected, the system SHALL place the paper in `papers_dir/Unsorted/`.

#### Scenario: File placed in selected category
- **WHEN** user confirms category "Finance/Asset Pricing" during `add --execute`
- **THEN** the renamed file is moved to `papers_dir/Finance/Asset Pricing/`

#### Scenario: File placed in Unsorted when category skipped
- **WHEN** user skips category selection during `add --execute`
- **THEN** the renamed file is moved to `papers_dir/Unsorted/`

#### Scenario: New category folder created
- **WHEN** user selects a category whose folder does not exist
- **THEN** system creates the folder and places the file there

### Requirement: Duplicate handling during add
The system SHALL compute SHA-256 of the source file before processing. If the hash matches an existing database record, the system SHALL skip the file and report the existing record's location.

#### Scenario: Duplicate detected during add
- **WHEN** user runs `add` on a PDF whose SHA-256 matches an existing library record
- **THEN** system reports "Already in library" with the existing file path and skips processing

#### Scenario: Non-duplicate proceeds normally
- **WHEN** user runs `add` on a PDF with no matching SHA-256 in the database
- **THEN** system proceeds with the full add workflow

### Requirement: Import directory
The system SHALL support adding all PDFs in a directory (and optionally subdirectories with `--recursive`) through the same add workflow. Papers SHALL be processed sequentially by default, with optional `--parallel N` for concurrent processing.

#### Scenario: Import a directory
- **WHEN** user runs `add` on a directory path with `--execute`
- **THEN** system processes each PDF in the directory through the add workflow

#### Scenario: Import with recursive scan
- **WHEN** user runs `add` on a directory with `--recursive` and `--execute`
- **THEN** system processes PDFs in the directory and all subdirectories

#### Scenario: Duplicates skipped during import
- **WHEN** a directory contains PDFs already in the library
- **THEN** system skips duplicates and reports them in the summary

### Requirement: Library sync command
The system SHALL provide a `sync` operation that reconciles the database with the filesystem under `papers_dir`. Files present on disk but not in the database SHALL be reported as untracked. Records in the database whose `file_path` no longer exists SHALL be reported as missing.

#### Scenario: Detect untracked files
- **WHEN** user runs `sync` and PDFs exist in `papers_dir` not tracked in the database
- **THEN** system lists untracked files and offers to add them

#### Scenario: Detect missing files
- **WHEN** user runs `sync` and database records point to files that no longer exist
- **THEN** system lists missing records and offers to remove them from the database

### Requirement: Remove paper from library
The system SHALL provide a `remove` operation that deletes the database record for a paper. By default, the file on disk is NOT deleted. With `--delete-file`, the system SHALL also delete the file from disk.

#### Scenario: Remove record only
- **WHEN** user runs `remove` on a paper ID without `--delete-file`
- **THEN** the database record is removed but the file remains on disk

#### Scenario: Remove record and file
- **WHEN** user runs `remove` on a paper ID with `--delete-file` and `--execute`
- **THEN** both the database record and the file on disk are deleted
