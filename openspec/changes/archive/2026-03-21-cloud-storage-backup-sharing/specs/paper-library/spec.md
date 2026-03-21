## MODIFIED Requirements

### Requirement: File placement into category folders
The system SHALL move (default) or copy (`--copy`) the renamed paper into `papers_dir/<category>/`. If the category folder does not exist, the system SHALL create it. If no category is selected, the system SHALL place the paper in `papers_dir/Unsorted/`. When iCloud sync is enabled, file placement SHALL also copy the PDF to the corresponding category folder in the sync container.

#### Scenario: File placed in selected category
- **WHEN** user confirms category "Finance/Asset Pricing" during `add --execute`
- **THEN** the renamed file is moved to `papers_dir/Finance/Asset Pricing/`

#### Scenario: File placed in Unsorted when category skipped
- **WHEN** user skips category selection during `add --execute`
- **THEN** the renamed file is moved to `papers_dir/Unsorted/`

#### Scenario: New category folder created
- **WHEN** user selects a category whose folder does not exist
- **THEN** system creates the folder and places the file there

#### Scenario: Sync container updated on file placement
- **WHEN** a paper is placed into a category folder and iCloud sync is enabled
- **THEN** the PDF is also copied to the sync container under the same category structure

### Requirement: Remove paper from library
The system SHALL provide a `remove` operation that deletes the database record for a paper. By default, the file on disk is NOT deleted. With `--delete-file`, the system SHALL also delete the file from disk. When iCloud sync is enabled, removal SHALL also remove the paper from the sync container.

#### Scenario: Remove record only
- **WHEN** user runs `remove` on a paper ID without `--delete-file`
- **THEN** the database record is removed but the file remains on disk

#### Scenario: Remove record and file
- **WHEN** user runs `remove` on a paper ID with `--delete-file` and `--execute`
- **THEN** both the database record and the file on disk are deleted

#### Scenario: Remove propagates to sync container
- **WHEN** a paper is removed from the library and iCloud sync is enabled
- **THEN** the paper's PDF and manifest entry are also removed from the sync container

### Requirement: Library sync command
The system SHALL provide a `sync` operation that reconciles the database with the filesystem under `papers_dir`. Files present on disk but not in the database SHALL be reported as untracked. Records in the database whose `file_path` no longer exists SHALL be reported as missing. When iCloud sync is enabled, the sync command SHALL also reconcile with the sync container.

#### Scenario: Detect untracked files
- **WHEN** user runs `sync` and PDFs exist in `papers_dir` not tracked in the database
- **THEN** system lists untracked files and offers to add them

#### Scenario: Detect missing files
- **WHEN** user runs `sync` and database records point to files that no longer exist
- **THEN** system lists missing records and offers to remove them from the database

#### Scenario: Reconcile with sync container
- **WHEN** user runs `sync` with iCloud sync enabled
- **THEN** system also checks for papers in the sync container not in the local library and offers to import them
