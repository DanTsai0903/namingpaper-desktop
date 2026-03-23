## 1. Foundation — Models and Window Shell

- [ ] 1.1 Create `AnnotationTool` enum (pointer, pencil, highlighter, rectangle, circle, arrow, line, text, stickyNote, image, signature, eraser)
- [ ] 1.2 Create `ToolProperties` struct (color, strokeWidth, opacity, fillColor, fontFamily, fontSize, textAlignment)
- [ ] 1.3 Create `PDFEditorViewModel` (@Observable) with activeTool, toolProperties, hasUnsavedChanges, selectedAnnotation, and savedSignatures
- [ ] 1.4 Create `PDFEditorWindowController` (NSPanel + NSHostingView) with `open(url:title:)` static method, duplicate-window prevention by file URL, and close-delegate for unsaved changes confirmation
- [ ] 1.5 Create `PDFEditorView` (SwiftUI root) with placeholder toolbar, placeholder property panel, and embedded PDFView — verify the window opens and displays a PDF

## 2. AnnotatablePDFView — Event Handling Core

- [ ] 2.1 Create `AnnotatablePDFView` (PDFView subclass) with a reference to `PDFEditorViewModel`
- [ ] 2.2 Implement coordinate conversion helpers (view ↔ PDF page coordinates) using `convert(_:from:)` and `PDFPage.convert(_:for:)`
- [ ] 2.3 Implement mouse event passthrough — when pointer tool is active, forward all events to `super` for default scroll/zoom/text-selection behavior
- [ ] 2.4 Create `PDFEditorCanvasView` (NSViewRepresentable) wrapping `AnnotatablePDFView` with bindings to the view model
- [ ] 2.5 Wire `PDFEditorCanvasView` into `PDFEditorView`, replacing the placeholder PDFView

## 3. Freehand Drawing (Pencil & Highlighter)

- [ ] 3.1 Implement point accumulation in `mouseDown`/`mouseDragged` when pencil or highlighter tool is active
- [ ] 3.2 Render temporary stroke overlay during drag (using `draw(_:for:)` override or temporary CAShapeLayer)
- [ ] 3.3 On `mouseUp`, create a `PDFAnnotation` with subtype `.ink` from accumulated points, applying color/width/opacity from tool properties
- [ ] 3.4 For highlighter, force opacity to 0.3 and use a wider default stroke width
- [ ] 3.5 Register undo action for the added ink annotation

## 4. Shape Annotations

- [ ] 4.1 Implement drag-to-define-bounds for rectangle tool — create `.square` annotation on mouseUp with configured stroke/fill
- [ ] 4.2 Implement circle/oval tool — create `.circle` annotation bounded by the drag rectangle
- [ ] 4.3 Implement line tool — create `.line` annotation from drag start to end
- [ ] 4.4 Implement arrow tool — create `.line` annotation with `endLineStyle = .closedArrow`
- [ ] 4.5 Render a temporary shape preview during drag
- [ ] 4.6 Register undo actions for each shape annotation

## 5. Text and Sticky Note Annotations

- [ ] 5.1 Implement text tool — on click, create `.freeText` annotation at click location with configured font/size/color
- [ ] 5.2 Enable inline text editing on double-click of existing free-text annotations
- [ ] 5.3 Implement sticky note tool — on click, create `.text` (note) annotation and open a popover for content input
- [ ] 5.4 Implement sticky note popover for viewing/editing note content on click
- [ ] 5.5 Register undo actions for text and sticky note creation/edits

## 6. Image Overlay and Signature

- [ ] 6.1 Implement image tool — on click, present NSOpenPanel filtered to PNG/JPEG, create `.stamp` annotation with image appearance at click location
- [ ] 6.2 Create `SignatureDrawingView` — a SwiftUI drawing pad for capturing freehand signatures
- [ ] 6.3 Implement signature persistence — save/load PNG data to UserDefaults under `savedSignatures` key
- [ ] 6.4 Implement signature tool popover — show saved signatures and "Create New" option
- [ ] 6.5 Place selected/new signature as `.stamp` annotation on the page
- [ ] 6.6 Register undo actions for image and signature placement

## 7. Annotation Selection, Manipulation, and Eraser

- [ ] 7.1 Implement pointer tool — on click, detect annotation at click point and set as selectedAnnotation in view model
- [ ] 7.2 Render selection handles (corners and midpoints) around the selected annotation
- [ ] 7.3 Implement annotation dragging — move selected annotation on mouseDrag, register undo
- [ ] 7.4 Implement annotation resizing — drag handles to resize, register undo
- [ ] 7.5 Implement Delete key handling — remove selected annotation, register undo
- [ ] 7.6 Implement eraser tool — on drag, compute intersection of eraser path with annotation bounds and remove intersecting annotations, register undo for each removal

## 8. Undo/Redo

- [ ] 8.1 Bridge the window's `NSUndoManager` to `PDFEditorViewModel` (expose canUndo/canRedo as observable properties)
- [ ] 8.2 Verify all annotation actions (add, move, resize, delete, property change) register proper undo/redo actions
- [ ] 8.3 Set undo manager's `levelsOfUndo` to 50
- [ ] 8.4 Verify Cmd+Z and Cmd+Shift+Z work via the AppKit responder chain

## 9. Save

- [ ] 9.1 Implement save-in-place (Cmd+S) — write annotated PDF using `PDFDocument.write(to:)`, reset hasUnsavedChanges
- [ ] 9.2 Implement save-as (Cmd+Shift+S) — present NSSavePanel, write to user-specified location
- [ ] 9.3 Verify annotations persist after save, close, and reopen

## 10. Editor UI — Toolbar, Property Panel, and Shortcuts

- [ ] 10.1 Build `AnnotationToolbar` with tool buttons (SF Symbols icons), active tool highlighting, and shape submenu popover
- [ ] 10.2 Build `PropertyPanel` — contextual controls that switch based on active tool (color picker, stroke width slider, opacity slider, fill toggle, font picker, font size stepper, alignment)
- [ ] 10.3 Wire property panel to update selected annotation properties in real time
- [ ] 10.4 Add save button to toolbar with enabled/disabled state based on hasUnsavedChanges
- [ ] 10.5 Implement keyboard shortcuts for tool switching (V, P, H, T, E, etc.) scoped to editor window via `keyDown` override in AnnotatablePDFView
- [ ] 10.6 Implement cursor changes per active tool (crosshair, I-beam, pencil, eraser icons)

## 11. Entry Points — Open in Editor

- [ ] 11.1 Add "Open in Editor" button to `PaperDetailView` toolbar
- [ ] 11.2 Add "Open in Editor" to right-click context menu in `PaperListView`
- [ ] 11.3 Wire both entry points to call `PDFEditorWindowController.open(url:title:)`
