## 1. Foundation — Models and Window Shell

- [x] 1.1 Create `AnnotationTool` enum (pointer, pencil, highlighter, rectangle, circle, arrow, line, text, stickyNote, image, signature, eraser)
- [x] 1.2 Create `ToolProperties` struct (color, strokeWidth, opacity, fillColor, fontFamily, fontSize, textAlignment)
- [x] 1.3 Create `PDFEditorViewModel` (@Observable) with activeTool, toolProperties, hasUnsavedChanges, selectedAnnotation, and savedSignatures
- [x] 1.4 Create `PDFEditorWindowController` (NSPanel + NSHostingView) with `open(url:title:)` static method, duplicate-window prevention by file URL, and close-delegate for unsaved changes confirmation
- [x] 1.5 Create `PDFEditorView` (SwiftUI root) with placeholder toolbar, placeholder property panel, and embedded PDFView — verify the window opens and displays a PDF

## 2. AnnotatablePDFView — Event Handling Core

- [x] 2.1 Create `AnnotatablePDFView` (PDFView subclass) with a reference to `PDFEditorViewModel`
- [x] 2.2 Implement coordinate conversion helpers (view ↔ PDF page coordinates) using `convert(_:from:)` and `PDFPage.convert(_:for:)`
- [x] 2.3 Implement mouse event passthrough — when pointer tool is active, forward all events to `super` for default scroll/zoom/text-selection behavior
- [x] 2.4 Create `PDFEditorCanvasView` (NSViewRepresentable) wrapping `AnnotatablePDFView` with bindings to the view model
- [x] 2.5 Wire `PDFEditorCanvasView` into `PDFEditorView`, replacing the placeholder PDFView

## 3. Freehand Drawing (Pencil & Highlighter)

- [x] 3.1 Implement point accumulation in `mouseDown`/`mouseDragged` when pencil or highlighter tool is active
- [x] 3.2 Render temporary stroke overlay during drag (using `draw(_:for:)` override or temporary CAShapeLayer)
- [x] 3.3 On `mouseUp`, create a `PDFAnnotation` with subtype `.ink` from accumulated points, applying color/width/opacity from tool properties
- [x] 3.4 For highlighter, force opacity to 0.3 and use a wider default stroke width
- [x] 3.5 Register undo action for the added ink annotation

## 4. Shape Annotations

- [x] 4.1 Implement drag-to-define-bounds for rectangle tool — create `.square` annotation on mouseUp with configured stroke/fill
- [x] 4.2 Implement circle/oval tool — create `.circle` annotation bounded by the drag rectangle
- [x] 4.3 Implement line tool — create `.line` annotation from drag start to end
- [x] 4.4 Implement arrow tool — create `.line` annotation with `endLineStyle = .closedArrow`
- [x] 4.5 Render a temporary shape preview during drag
- [x] 4.6 Register undo actions for each shape annotation

## 5. Text and Sticky Note Annotations

- [x] 5.1 Implement text tool — on click, create `.freeText` annotation at click location with configured font/size/color
- [x] 5.2 Enable inline text editing on double-click of existing free-text annotations
- [x] 5.3 Implement sticky note tool — on click, create `.text` (note) annotation and open a popover for content input
- [x] 5.4 Implement sticky note popover for viewing/editing note content on click
- [x] 5.5 Register undo actions for text and sticky note creation/edits

## 6. Image Overlay and Signature

- [x] 6.1 Implement image tool — on click, present NSOpenPanel filtered to PNG/JPEG, create `.stamp` annotation with image appearance at click location
- [x] 6.2 Create `SignatureDrawingView` — a SwiftUI drawing pad for capturing freehand signatures
- [x] 6.3 Implement signature persistence — save/load PNG data to UserDefaults under `savedSignatures` key
- [x] 6.4 Implement signature tool popover — show saved signatures and "Create New" option
- [x] 6.5 Place selected/new signature as `.stamp` annotation on the page
- [x] 6.6 Register undo actions for image and signature placement

## 7. Annotation Selection, Manipulation, and Eraser

- [x] 7.1 Implement pointer tool — on click, detect annotation at click point and set as selectedAnnotation in view model
- [x] 7.2 Render selection handles (corners and midpoints) around the selected annotation
- [x] 7.3 Implement annotation dragging — move selected annotation on mouseDrag, register undo
- [x] 7.4 Implement annotation resizing — drag handles to resize, register undo
- [x] 7.5 Implement Delete key handling — remove selected annotation, register undo
- [x] 7.6 Implement eraser tool — on drag, compute intersection of eraser path with annotation bounds and remove intersecting annotations, register undo for each removal

## 8. Undo/Redo

- [x] 8.1 Bridge the window's `NSUndoManager` to `PDFEditorViewModel` (expose canUndo/canRedo as observable properties)
- [x] 8.2 Verify all annotation actions (add, move, resize, delete, property change) register proper undo/redo actions
- [x] 8.3 Set undo manager's `levelsOfUndo` to 50
- [x] 8.4 Verify Cmd+Z and Cmd+Shift+Z work via the AppKit responder chain

## 9. Save

- [x] 9.1 Implement save-in-place (Cmd+S) — write annotated PDF using `PDFDocument.write(to:)`, reset hasUnsavedChanges
- [x] 9.2 Implement save-as (Cmd+Shift+S) — present NSSavePanel, write to user-specified location
- [x] 9.3 Verify annotations persist after save, close, and reopen

## 10. Editor UI — Toolbar, Property Panel, and Shortcuts

- [x] 10.1 Build `AnnotationToolbar` with tool buttons (SF Symbols icons), active tool highlighting, and shape submenu popover
- [x] 10.2 Build `PropertyPanel` — contextual controls that switch based on active tool (color picker, stroke width slider, opacity slider, fill toggle, font picker, font size stepper, alignment)
- [x] 10.3 Wire property panel to update selected annotation properties in real time
- [x] 10.4 Add save button to toolbar with enabled/disabled state based on hasUnsavedChanges
- [x] 10.5 Implement keyboard shortcuts for tool switching (V, P, H, T, E, etc.) scoped to editor window via `keyDown` override in AnnotatablePDFView
- [x] 10.6 Implement cursor changes per active tool (crosshair, I-beam, pencil, eraser icons)

## 11. Entry Points — Open in Editor

- [x] 11.1 Add "Open in Editor" button to `PaperDetailView` toolbar
- [x] 11.2 Add "Open in Editor" to right-click context menu in `PaperListView`
- [x] 11.3 Wire both entry points to call `PDFEditorWindowController.open(url:title:)`
