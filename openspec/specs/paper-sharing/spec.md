## ADDED Requirements

### Requirement: Export paper as bundle
The system SHALL allow users to export a paper as a `.namingpaper` bundle file. The bundle SHALL be a zip archive containing the PDF file and a `metadata.json` with the paper's full metadata (title, authors, year, journal, summary, keywords, category).

#### Scenario: Export single paper
- **WHEN** user right-clicks a paper and selects "Export as Bundle"
- **THEN** system creates a `.namingpaper` file containing the PDF and metadata, and prompts for a save location

#### Scenario: Export bundle contents
- **WHEN** a `.namingpaper` bundle is created
- **THEN** it contains exactly two entries: the original PDF file and a `metadata.json` file

### Requirement: Export collection as bundle
The system SHALL allow users to export multiple selected papers as a single `.namingpaper` bundle. The bundle SHALL contain all selected PDFs and a `metadata.json` with an array of paper metadata entries.

#### Scenario: Export multiple papers
- **WHEN** user selects 3 papers and chooses "Export as Bundle"
- **THEN** system creates a single `.namingpaper` file containing all 3 PDFs and their combined metadata

#### Scenario: Export entire category
- **WHEN** user right-clicks a category and selects "Export Category as Bundle"
- **THEN** system creates a bundle containing all papers in that category

### Requirement: Import paper from bundle
The system SHALL allow users to import papers from a `.namingpaper` bundle file. On import, the system SHALL extract the PDF(s), read metadata from `metadata.json`, and add each paper to the library through the standard add flow (with dedup checking via SHA-256).

#### Scenario: Import single-paper bundle
- **WHEN** user opens or drags a `.namingpaper` file containing one paper
- **THEN** system extracts the PDF, reads metadata, checks for duplicates, and adds the paper to the library

#### Scenario: Import multi-paper bundle
- **WHEN** user opens a `.namingpaper` file containing multiple papers
- **THEN** system imports each paper, skipping duplicates, and reports a summary

#### Scenario: Import duplicate paper
- **WHEN** a bundle contains a paper whose SHA-256 matches an existing library record
- **THEN** system skips that paper and reports it as already in the library

### Requirement: UTType registration for .namingpaper
The system SHALL register a Uniform Type Identifier for the `.namingpaper` file extension so that macOS associates these files with the NamingPaper app. Double-clicking a `.namingpaper` file SHALL open NamingPaper and trigger the import flow.

#### Scenario: Double-click opens app
- **WHEN** user double-clicks a `.namingpaper` file in Finder
- **THEN** NamingPaper opens (or comes to front) and begins the import flow

#### Scenario: Drag-and-drop import
- **WHEN** user drags a `.namingpaper` file onto the NamingPaper window
- **THEN** system begins the import flow for the bundle contents

### Requirement: Share via system share sheet
The system SHALL integrate with macOS share sheet, allowing users to share a paper bundle via AirDrop, Mail, Messages, or other share destinations.

#### Scenario: Share paper via AirDrop
- **WHEN** user selects a paper and uses the share button, then chooses AirDrop
- **THEN** system creates a temporary `.namingpaper` bundle and sends it via AirDrop
