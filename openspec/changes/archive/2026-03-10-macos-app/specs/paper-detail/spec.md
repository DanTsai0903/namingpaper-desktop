## ADDED Requirements

### Requirement: Metadata header

The detail pane SHALL display the paper's title in a large font at the top, followed by authors, year, journal name, a category badge (colored pill), and keywords as tag chips. If any field is missing, it SHALL be omitted without leaving blank space.

#### Scenario: Full metadata display

- **WHEN** a paper with all metadata fields is selected
- **THEN** the detail header shows title, authors, year, journal, category badge, and keyword tags

#### Scenario: Partial metadata

- **WHEN** a paper has no journal or keywords
- **THEN** those fields are omitted and the layout adjusts without gaps

### Requirement: Summary callout

The detail pane SHALL display the AI-generated summary in a visually distinct callout box below the metadata header. If no summary exists, the callout SHALL show "No summary available" in muted text.

#### Scenario: Summary present

- **WHEN** a paper with a summary is displayed
- **THEN** the summary appears in a styled callout box

#### Scenario: No summary

- **WHEN** a paper without a summary is displayed
- **THEN** the callout shows "No summary available"

### Requirement: Inline PDF preview

The detail pane SHALL embed a PDFKit `PDFView` below the summary callout. The PDF SHALL load from the file path stored in the database. The viewer SHALL support scrolling, zooming (pinch or Cmd+/Cmd-), and SHALL default to fit-width scaling. A zoom slider and page indicator SHALL appear at the bottom.

#### Scenario: PDF loads successfully

- **WHEN** a paper with a valid file path is selected
- **THEN** the PDF renders inline with scroll and zoom support

#### Scenario: PDF file missing

- **WHEN** the PDF file at the stored path does not exist
- **THEN** a placeholder message "PDF not found" is displayed instead of the viewer

#### Scenario: Zoom controls

- **WHEN** user presses `Cmd+` or uses the zoom slider
- **THEN** the PDF zoom level increases; `Cmd-` decreases it

### Requirement: Action toolbar

The detail pane SHALL include a toolbar with actions: "Open in Preview" (launches system PDF viewer), "Reveal in Finder" (opens Finder at file location), "Recategorize" (opens category dropdown), and "Remove" (removes paper via CLI). Actions that invoke the CLI SHALL show a confirmation dialog before executing.

#### Scenario: Open in Preview

- **WHEN** user clicks "Open in Preview"
- **THEN** the PDF opens in the default system PDF viewer via `NSWorkspace.open`

#### Scenario: Reveal in Finder

- **WHEN** user clicks "Reveal in Finder"
- **THEN** Finder opens with the PDF file selected

#### Scenario: Remove paper with confirmation

- **WHEN** user clicks "Remove"
- **THEN** a confirmation dialog appears; on confirm, `namingpaper remove --execute` runs and the paper is removed from the list

### Requirement: Inline category editing

Users SHALL be able to change a paper's category by clicking the category badge, which opens a dropdown with existing categories and a "New Category..." option. Selecting a category SHALL invoke `namingpaper` CLI to recategorize. The UI SHALL update immediately after the operation succeeds.

#### Scenario: Change category via dropdown

- **WHEN** user clicks the category badge and selects a different category
- **THEN** the CLI recategorizes the paper and the badge updates to the new category

#### Scenario: Create new category

- **WHEN** user selects "New Category..." from the dropdown and enters a name
- **THEN** the CLI recategorizes the paper into the new category
