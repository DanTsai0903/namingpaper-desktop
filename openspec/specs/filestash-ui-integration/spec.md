## ADDED Requirements

### Requirement: Filestash as external UI boundary
The system SHALL treat Filestash as an external, independently deployed web UI component. No Filestash source code, plugins, or frontend assets SHALL be included in the namingpaper repository. All paper-specific metadata operations (search, categorization, summary) SHALL remain in `namingpaper` CLI commands.

#### Scenario: Filestash not required for CLI usage
- **WHEN** Filestash is not deployed
- **THEN** all `namingpaper` CLI commands (add, search, list, info, remove, sync) work fully

#### Scenario: Filestash mounted to papers_dir
- **WHEN** Filestash is configured to serve `papers_dir`
- **THEN** users can browse, preview, and manage paper files through the web UI

### Requirement: Documentation for Filestash setup
The system SHALL include documentation describing how to configure Filestash to mount `papers_dir` for paper browsing. The documentation SHALL cover the recommended Filestash backend configuration (local filesystem pointing to `papers_dir`).

#### Scenario: Setup documentation available
- **WHEN** user wants to set up Filestash for paper browsing
- **THEN** documentation describes the configuration steps for mounting `papers_dir`

### Requirement: Folder structure compatible with Filestash browsing
The system SHALL organize papers in `papers_dir` using plain filesystem directories as categories. The folder naming SHALL use human-readable names (no encoded IDs or hashes in folder names) so that Filestash displays a clean, navigable folder tree.

#### Scenario: Category folders are human-readable
- **WHEN** papers are organized into categories
- **THEN** folder names like "Finance/Asset Pricing" appear cleanly in Filestash's file browser
