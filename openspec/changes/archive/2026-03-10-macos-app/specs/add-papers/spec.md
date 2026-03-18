## ADDED Requirements

### Requirement: Drag-and-drop with overlay

The main window SHALL accept PDF files via drag-and-drop using `.onDrop(of: [.pdf])`. When files are dragged over the window, a semi-transparent overlay SHALL appear with a drop zone indicator ("Drop PDFs to add to library"). Dropping SHALL trigger the add workflow.

#### Scenario: Drag PDF over window

- **WHEN** user drags a PDF file over the app window
- **THEN** a drop zone overlay appears indicating the file can be dropped

#### Scenario: Drop PDF files

- **WHEN** user drops one or more PDF files onto the window
- **THEN** the add workflow begins for each file

#### Scenario: Drag non-PDF file

- **WHEN** user drags a non-PDF file over the window
- **THEN** the drop zone overlay does not appear and the drop is rejected

### Requirement: File picker via Cmd+O

The app SHALL provide a file picker via `Cmd+O` (File > Add Papers) using `.fileImporter`. The picker SHALL allow multiple PDF selection. Selected files SHALL trigger the same add workflow as drag-and-drop.

#### Scenario: Add papers via file picker

- **WHEN** user presses `Cmd+O` and selects two PDF files
- **THEN** the add workflow begins for both files

### Requirement: Dock icon drop

The app SHALL accept PDF files dropped onto its dock icon via `NSApplicationDelegate.application(_:open:)`. Dropped files SHALL trigger the add workflow.

#### Scenario: Drop PDF on dock icon

- **WHEN** user drags a PDF file onto the app's dock icon
- **THEN** the add workflow begins for that file

### Requirement: Progress sheet with per-file status

When the add workflow begins, a modal sheet SHALL appear showing progress. Each file SHALL have a row with: filename, current stage (extracting, summarizing, categorizing, done), and a progress indicator. The sheet SHALL have a "Close" button that becomes active when all files are complete.

#### Scenario: Show progress for multiple files

- **WHEN** user drops 3 PDFs onto the window
- **THEN** a progress sheet appears with 3 rows, each showing the current processing stage

#### Scenario: File processing completes

- **WHEN** a file finishes all stages (extracting → summarizing → categorizing → done)
- **THEN** its row shows a checkmark and "Done" status

#### Scenario: File processing fails

- **WHEN** a file fails during processing (e.g., CLI error)
- **THEN** its row shows an error icon and the error message

### Requirement: CLI subprocess integration for add

Each file in the add workflow SHALL be processed by running `namingpaper add --execute --yes <path>` via `CLIService`. The subprocess stdout SHALL be parsed for stage progress. Multiple files SHALL be processed sequentially (one at a time).

#### Scenario: CLI add command execution

- **WHEN** a file enters the add workflow
- **THEN** `CLIService` runs `namingpaper add --execute --yes <path>` and reports output

### Requirement: Library refresh on completion

After all files in an add workflow are processed, the app SHALL refresh the paper list from the database. Newly added papers SHALL appear in the list with a brief highlight animation (fade-in or flash).

#### Scenario: New paper appears after add

- **WHEN** a paper is successfully added via the CLI
- **THEN** the paper list refreshes and the new paper appears with a highlight animation
