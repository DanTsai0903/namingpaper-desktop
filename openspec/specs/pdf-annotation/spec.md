# Capability: pdf-annotation

## Purpose

Provides annotation tools for PDF documents including freehand drawing, shapes, text, sticky notes, image overlays, signatures, eraser, undo/redo, and save.

## Requirements

### Requirement: Freehand drawing

The system SHALL allow users to draw freehand strokes on any PDF page using a pencil tool. Strokes SHALL have configurable color, line width (1–20pt), and opacity (0.1–1.0). The system SHALL also provide a highlighter tool that renders strokes with fixed semi-transparency (opacity 0.3).

#### Scenario: Draw a freehand stroke

- **WHEN** user selects the pencil tool and draws on a PDF page
- **THEN** the system renders an ink annotation following the pointer path with the configured color, width, and opacity

#### Scenario: Use highlighter tool

- **WHEN** user selects the highlighter tool and draws on a PDF page
- **THEN** the system renders a semi-transparent ink annotation (opacity 0.3) with the configured color and a wider default stroke width

### Requirement: Shape annotations

The system SHALL allow users to place shape annotations on any PDF page. Supported shapes SHALL include rectangle, circle/oval, arrow, and line. Each shape SHALL have configurable stroke color, fill color (or no fill), stroke width, and opacity.

#### Scenario: Draw a rectangle

- **WHEN** user selects the rectangle tool and drags on a PDF page
- **THEN** the system renders a rectangle annotation defined by the drag start and end points with the configured stroke/fill properties

#### Scenario: Draw an arrow

- **WHEN** user selects the arrow tool and drags on a PDF page
- **THEN** the system renders a line annotation with an arrowhead at the end point

#### Scenario: Draw a circle

- **WHEN** user selects the circle tool and drags on a PDF page
- **THEN** the system renders an oval annotation bounded by the drag rectangle

### Requirement: Text annotations

The system SHALL allow users to place editable text boxes on any PDF page. Text annotations SHALL support configurable font family, font size (8–72pt), color, and alignment. The system SHALL allow inline editing by double-clicking the annotation.

#### Scenario: Add a text annotation

- **WHEN** user selects the text tool and clicks on a PDF page
- **THEN** the system places a free-text annotation at the click location with an active text cursor for immediate input

#### Scenario: Edit existing text annotation

- **WHEN** user double-clicks an existing text annotation
- **THEN** the system enters inline editing mode for that annotation, allowing the user to modify the text content

### Requirement: Sticky notes

The system SHALL allow users to place sticky note annotations on any PDF page. A sticky note SHALL display as a small icon that expands to show its text content when clicked. Sticky notes SHALL have configurable color.

#### Scenario: Add a sticky note

- **WHEN** user selects the sticky note tool and clicks on a PDF page
- **THEN** the system places a note annotation icon at the click location and opens a text input popover for entering the note content

#### Scenario: View sticky note content

- **WHEN** user clicks on an existing sticky note icon
- **THEN** the system displays a popover showing the note's text content, editable in place

### Requirement: Image overlay

The system SHALL allow users to insert images onto any PDF page. The user SHALL be able to select an image file (PNG, JPEG) from the file system. The inserted image SHALL be resizable and repositionable.

#### Scenario: Insert an image

- **WHEN** user selects the image tool and clicks on a PDF page
- **THEN** the system opens a file picker filtered to image types (PNG, JPEG), and upon selection, places the image as a stamp annotation at the click location

#### Scenario: Resize an inserted image

- **WHEN** user selects an image annotation and drags a resize handle
- **THEN** the system resizes the image annotation proportionally

### Requirement: Signature

The system SHALL allow users to place a signature on any PDF page. Users SHALL be able to draw a new signature in a signing pad or select a previously saved signature. The system SHALL persist saved signatures locally for reuse across sessions.

#### Scenario: Draw and place a new signature

- **WHEN** user selects the signature tool and chooses "Create New"
- **THEN** the system presents a drawing pad where the user draws their signature, and upon confirmation, places it as a stamp annotation on the page

#### Scenario: Reuse a saved signature

- **WHEN** user selects the signature tool and chooses a previously saved signature
- **THEN** the system places the selected signature as a stamp annotation on the page at the click location

#### Scenario: Persist signatures across sessions

- **WHEN** user saves a new signature
- **THEN** the signature is stored locally and appears in the saved signatures list in future sessions

### Requirement: Eraser

The system SHALL provide an eraser tool that removes annotation elements. The eraser SHALL use intersection-based removal: any annotation whose bounds intersect the eraser path SHALL be removed entirely (not partially).

#### Scenario: Erase an annotation

- **WHEN** user selects the eraser tool and drags over an annotation
- **THEN** the system removes all annotations whose bounds intersect the eraser stroke path

#### Scenario: Eraser does not affect PDF content

- **WHEN** user drags the eraser over original PDF content (text, images)
- **THEN** the original PDF content remains unchanged; only annotations are removed

### Requirement: Annotation selection and manipulation

The system SHALL allow users to select, move, and resize annotations. A selection tool SHALL highlight the selected annotation with handles. Users SHALL be able to delete a selected annotation via the Delete key.

#### Scenario: Select an annotation

- **WHEN** user selects the pointer/selection tool and clicks on an annotation
- **THEN** the system highlights the annotation with selection handles (corners and midpoints)

#### Scenario: Move an annotation

- **WHEN** user drags a selected annotation
- **THEN** the annotation moves to the new position on the same page

#### Scenario: Delete a selected annotation

- **WHEN** user presses the Delete key with an annotation selected
- **THEN** the system removes the annotation from the page

### Requirement: Undo and redo

The system SHALL maintain an undo/redo stack for all annotation actions (add, move, resize, delete, edit). The stack SHALL support at least 50 levels. Undo SHALL be triggered by Cmd+Z and redo by Cmd+Shift+Z.

#### Scenario: Undo an annotation action

- **WHEN** user presses Cmd+Z after adding an annotation
- **THEN** the system removes the most recently added annotation and pushes the action onto the redo stack

#### Scenario: Redo an undone action

- **WHEN** user presses Cmd+Shift+Z after undoing an action
- **THEN** the system reapplies the undone action

#### Scenario: Undo stack limit

- **WHEN** the undo stack contains 50 actions and the user performs a new action
- **THEN** the oldest action is discarded from the stack

### Requirement: Save annotated PDF

The system SHALL allow users to save annotated PDFs. Annotations SHALL be persisted as standard PDF annotations embedded in the file. The system SHALL support both overwrite (save in place) and save-as (new file) operations. Save SHALL be triggered by Cmd+S (overwrite) and Cmd+Shift+S (save-as).

#### Scenario: Save in place

- **WHEN** user presses Cmd+S while in edit mode
- **THEN** the system writes all annotations to the PDF file, overwriting the original

#### Scenario: Save as new file

- **WHEN** user presses Cmd+Shift+S while in edit mode
- **THEN** the system opens a save dialog and writes the annotated PDF to the user-specified location

#### Scenario: Annotations persist after save and reopen

- **WHEN** user saves an annotated PDF, closes it, and reopens it
- **THEN** all annotations are visible and editable as they were before closing
