## ADDED Requirements

### Requirement: Add command
The system SHALL provide a `namingpaper add <path>` command that accepts a PDF file path or directory path. The command SHALL follow the existing safety model: dry-run by default, `--execute` required for mutations. Options: `--execute`/`-x`, `--yes`/`-y` (skip confirmation), `--copy` (keep source), `--recursive`/`-r` (for directories), `--parallel N`, `--provider`/`-p`, `--model`/`-m`, `--ocr-model`, `--template`/`-t`.

#### Scenario: Add single file dry-run
- **WHEN** user runs `namingpaper add paper.pdf`
- **THEN** system displays planned rename, summary, keywords, suggested category, and target path without making changes

#### Scenario: Add single file with execute
- **WHEN** user runs `namingpaper add paper.pdf --execute`
- **THEN** system performs the full add workflow with interactive category selection

#### Scenario: Add directory
- **WHEN** user runs `namingpaper add ~/Downloads/papers/ --execute`
- **THEN** system processes all PDFs in the directory through the add workflow

### Requirement: Search command
The system SHALL provide a `namingpaper search <query>` command that searches the library database. Options: `--author`, `--year` (single year or range like "2020-2024"), `--journal`, `--category`, `--smart` (enable AI semantic search). Default mode is FTS5 keyword search. Smart mode is auto-enabled when query contains 6+ words.

#### Scenario: Basic keyword search
- **WHEN** user runs `namingpaper search "risk factors"`
- **THEN** system displays matching papers in a table with ID, Year, Authors, Category, and Title columns

#### Scenario: Search with filters
- **WHEN** user runs `namingpaper search "pricing" --journal "JFE" --year 2020-2024`
- **THEN** system displays papers matching "pricing" that are also in JFE and from 2020-2024

#### Scenario: Smart search auto-trigger
- **WHEN** user runs `namingpaper search "papers about pricing models in equity markets"`
- **THEN** system auto-enables smart search (query has 6+ words) and ranks results by semantic relevance

#### Scenario: Empty results
- **WHEN** user searches for a term with no matches
- **THEN** system displays "No papers found" message

### Requirement: List command
The system SHALL provide a `namingpaper list` command that displays all papers in the library. Options: `--category` (filter by category), `--sort` (by year, author, title, or date-added; default: date-added), `--limit N` (default: 20).

#### Scenario: List all papers
- **WHEN** user runs `namingpaper list`
- **THEN** system displays the 20 most recently added papers in a table

#### Scenario: List by category
- **WHEN** user runs `namingpaper list --category "Finance/Asset Pricing"`
- **THEN** system displays only papers in that category

### Requirement: Info command
The system SHALL provide a `namingpaper info <id>` command that displays full details of a single paper: title, authors, year, journal, category, file path, summary, keywords, confidence score, and timestamps.

#### Scenario: Display paper info
- **WHEN** user runs `namingpaper info a3f2`
- **THEN** system displays all metadata fields for the paper with id "a3f2"

#### Scenario: Paper not found
- **WHEN** user runs `namingpaper info xxxx` and no paper has that id
- **THEN** system displays "Paper not found" error

### Requirement: Remove command
The system SHALL provide a `namingpaper remove <id>` command that removes a paper from the library database. Options: `--delete-file` (also delete the file from disk), `--execute`/`-x` (required for actual removal), `--yes`/`-y` (skip confirmation).

#### Scenario: Remove dry-run
- **WHEN** user runs `namingpaper remove a3f2`
- **THEN** system shows what would be removed but does not delete

#### Scenario: Remove with execute
- **WHEN** user runs `namingpaper remove a3f2 --execute`
- **THEN** system prompts for confirmation then removes the database record

### Requirement: Sync command
The system SHALL provide a `namingpaper sync` command that reconciles the database with the filesystem. Options: `--execute`/`-x` (apply fixes), `--yes`/`-y`.

#### Scenario: Sync dry-run
- **WHEN** user runs `namingpaper sync`
- **THEN** system reports untracked files and missing records without making changes

#### Scenario: Sync with execute
- **WHEN** user runs `namingpaper sync --execute`
- **THEN** system offers to add untracked files and remove missing records

### Requirement: Existing commands unchanged
All existing commands (`rename`, `batch`, `templates`, `version`, `update`, `uninstall`, `config`) SHALL continue to work with identical behavior. No backward-incompatible changes to existing CLI interfaces.

#### Scenario: Rename command unaffected
- **WHEN** user runs `namingpaper rename paper.pdf --execute`
- **THEN** behavior is identical to pre-library version

#### Scenario: Batch command unaffected
- **WHEN** user runs `namingpaper batch ~/papers --execute`
- **THEN** behavior is identical to pre-library version
