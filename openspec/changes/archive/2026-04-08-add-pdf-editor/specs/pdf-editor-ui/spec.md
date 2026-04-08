## ADDED Requirements

### Requirement: Editor window
The system SHALL open a dedicated editor window when the user chooses to edit a PDF. The editor window SHALL be separate from the main library window and SHALL contain its own PDF view with annotation capabilities. Multiple editor windows MAY be open simultaneously for different papers. The window title SHALL display the paper filename.

#### Scenario: Open editor from detail view
- **WHEN** user clicks the "Open in Editor" button in the paper detail view
- **THEN** the system opens a new editor window displaying the paper's PDF with the annotation toolbar active

#### Scenario: Open editor from context menu
- **WHEN** user right-clicks a paper in the library list and selects "Open in Editor"
- **THEN** the system opens a new editor window for that paper

#### Scenario: Multiple editor windows
- **WHEN** user opens editor windows for two different papers
- **THEN** both windows are open independently, each with their own annotation state

#### Scenario: Close editor with unsaved changes
- **WHEN** user closes an editor window with unsaved annotation changes
- **THEN** the system presents a confirmation dialog asking to save, discard, or cancel

### Requirement: Annotation toolbar
The editor window SHALL display a toolbar containing tool buttons for: pointer/selection, pencil, highlighter, shapes (rectangle, circle, arrow, line), text, sticky note, image, signature, and eraser. The toolbar SHALL visually indicate the currently active tool. Only one tool SHALL be active at a time.

#### Scenario: Display toolbar on window open
- **WHEN** the editor window opens
- **THEN** the toolbar is visible with all annotation tool buttons and the pointer tool selected by default

#### Scenario: Switch active tool
- **WHEN** user clicks a different tool button in the toolbar
- **THEN** the clicked tool becomes active with visual highlighting, and the previous tool is deactivated

#### Scenario: Shape tool submenu
- **WHEN** user clicks the shapes tool button
- **THEN** a submenu appears showing rectangle, circle, arrow, and line options

### Requirement: Property panel
The editor window SHALL display a contextual property panel that shows controls relevant to the currently active tool or selected annotation. Properties SHALL include: color picker, stroke width slider (1–20pt), opacity slider (0.1–1.0), fill color toggle, font family picker, font size stepper (8–72pt), and text alignment.

#### Scenario: Show properties for pencil tool
- **WHEN** user selects the pencil tool
- **THEN** the property panel displays color picker, stroke width slider, and opacity slider

#### Scenario: Show properties for text tool
- **WHEN** user selects the text tool
- **THEN** the property panel displays font family picker, font size stepper, color picker, and text alignment controls

#### Scenario: Show properties for selected annotation
- **WHEN** user selects an existing annotation with the pointer tool
- **THEN** the property panel displays editable properties relevant to that annotation type

#### Scenario: Update annotation properties
- **WHEN** user changes a property value while an annotation is selected
- **THEN** the selected annotation updates immediately to reflect the new property value

### Requirement: Keyboard shortcuts for tools
The editor window SHALL support keyboard shortcuts for quick tool switching. Shortcuts SHALL NOT conflict with existing application or system shortcuts.

#### Scenario: Select tool via keyboard
- **WHEN** user presses a tool shortcut key (e.g., V for pointer, P for pencil, H for highlighter, T for text, E for eraser)
- **THEN** the corresponding tool becomes active and the toolbar updates to reflect the selection

#### Scenario: Shortcuts scoped to editor window
- **WHEN** the editor window is not the key window and user presses a tool shortcut key
- **THEN** no tool switching occurs in the editor

### Requirement: Save controls
The editor window SHALL provide save controls accessible from the toolbar and menu bar. Save (Cmd+S) SHALL overwrite the current file. Save As (Cmd+Shift+S) SHALL prompt for a new file location.

#### Scenario: Save button in toolbar
- **WHEN** user has unsaved changes in the editor window
- **THEN** a save button is visible in the toolbar and is enabled

#### Scenario: Save button disabled when clean
- **WHEN** user has no unsaved changes in the editor window
- **THEN** the save button is visible but disabled (grayed out)

### Requirement: Cursor feedback
The editor window SHALL change the cursor to reflect the currently active tool. Each tool SHALL have a distinct cursor icon (e.g., crosshair for shapes, I-beam for text, pencil icon for drawing, eraser icon for eraser).

#### Scenario: Cursor changes with tool selection
- **WHEN** user switches to the pencil tool
- **THEN** the cursor changes to a pencil-style icon when hovering over the PDF page

#### Scenario: Default cursor for pointer tool
- **WHEN** the pointer/selection tool is active
- **THEN** the cursor is the standard arrow cursor
