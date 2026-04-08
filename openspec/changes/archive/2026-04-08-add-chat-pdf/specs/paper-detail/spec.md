## MODIFIED Requirements

### Requirement: Action toolbar

The detail pane SHALL include a toolbar with actions: "Open in Preview" (launches system PDF viewer), "Reveal in Finder" (opens Finder at file location), "Recategorize" (opens category dropdown), "Remove" (removes paper via CLI), and a "Chat" toggle button (activates chat mode). The Chat toggle SHALL use a `bubble.left.and.text.bubble.right` system image. Actions that invoke the CLI SHALL show a confirmation dialog before executing.

#### Scenario: Open in Preview

- **WHEN** user clicks "Open in Preview"
- **THEN** the PDF opens in the default system PDF viewer via `NSWorkspace.open`

#### Scenario: Reveal in Finder

- **WHEN** user clicks "Reveal in Finder"
- **THEN** Finder opens with the PDF file selected

#### Scenario: Remove paper with confirmation

- **WHEN** user clicks "Remove"
- **THEN** a confirmation dialog appears; on confirm, `namingpaper remove --execute` runs and the paper is removed from the list

#### Scenario: Toggle chat mode on

- **WHEN** user clicks the "Chat" toolbar button
- **THEN** the detail view switches to split-pane layout with PDF left and chat panel right

#### Scenario: Toggle chat mode off

- **WHEN** user clicks the "Chat" toolbar button while chat mode is active
- **THEN** the detail view returns to the standard metadata + PDF vertical layout

#### Scenario: Chat button disabled without PDF

- **WHEN** the selected paper has no PDF file
- **THEN** the Chat toolbar button is disabled
