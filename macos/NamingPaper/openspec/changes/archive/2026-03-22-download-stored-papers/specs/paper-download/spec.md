## ADDED Requirements

### Requirement: Download papers by ID
The system SHALL allow users to download one or more papers by their ID to a specified output directory. The PDF file SHALL be copied (not moved) from the library to the output directory.

#### Scenario: Download single paper by ID
- **WHEN** user specifies a paper ID and an output directory
- **THEN** the system copies that paper's PDF to the output directory

#### Scenario: Download multiple papers by ID
- **WHEN** user specifies multiple paper IDs and an output directory
- **THEN** the system copies all specified papers' PDFs to the output directory

#### Scenario: Paper ID not found
- **WHEN** user specifies a paper ID that does not exist in the library
- **THEN** the system displays an error message identifying the unknown ID and skips it

### Requirement: Download papers by search query
The system SHALL allow users to download papers matching a search query.

#### Scenario: Download by keyword search
- **WHEN** user specifies a search query and an output directory
- **THEN** the system copies all matching papers' PDFs to the output directory

#### Scenario: No search results
- **WHEN** user specifies a search query that matches no papers
- **THEN** the system displays "No papers found matching query" and exits

### Requirement: Download papers by category
The system SHALL allow users to download all papers in a specified category.

#### Scenario: Download entire category
- **WHEN** user specifies a category name and an output directory
- **THEN** the system copies all papers in that category to the output directory

#### Scenario: Category not found
- **WHEN** user specifies a category that does not exist
- **THEN** the system displays "No papers found in category" and exits

### Requirement: Download all papers
The system SHALL allow users to download all papers in the library.

#### Scenario: Download all
- **WHEN** user requests to download all papers with an output directory
- **THEN** the system copies every paper in the library to the output directory

### Requirement: Category folder structure preservation
The system SHALL preserve the category folder structure by default. A flat mode SHALL place all PDFs directly in the output directory root.

#### Scenario: Structured output (default)
- **WHEN** user downloads papers without the flat flag
- **THEN** PDFs are placed in category subfolders under the output directory

#### Scenario: Flat output
- **WHEN** user downloads papers with the flat flag enabled
- **THEN** all PDFs are placed directly in the output directory root

#### Scenario: Flat mode filename collision
- **WHEN** two papers have the same filename in flat mode
- **THEN** the system appends the paper's short ID to the second file's name

### Requirement: Collision handling
The system SHALL skip files that already exist in the output directory by default. An overwrite flag SHALL force replacement.

#### Scenario: File exists - skip (default)
- **WHEN** a PDF already exists at the target path and overwrite is not enabled
- **THEN** the system skips that file and reports it as already existing

#### Scenario: File exists - overwrite
- **WHEN** a PDF already exists at the target path and overwrite is enabled
- **THEN** the system replaces the existing file

### Requirement: Missing source file handling
The system SHALL gracefully handle papers whose source PDF no longer exists on disk.

#### Scenario: Source file missing
- **WHEN** a paper's file_path points to a file that does not exist
- **THEN** the system skips that paper, warns the user, and suggests running namingpaper sync

### Requirement: Download summary
The system SHALL display a summary after the download completes.

#### Scenario: Summary after download
- **WHEN** a download operation completes
- **THEN** the system displays: total requested, successfully copied, skipped, and failed
