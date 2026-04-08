## Context

NamingPaper is a macOS SwiftUI app with a single-window, three-panel layout (sidebar, paper list, detail). PDFs are currently rendered read-only via `PDFKitView` (an `NSViewRepresentable` wrapping `PDFView`). The app uses `@Observable` view models, environment-based state sharing, and has an existing pattern for AppKit windows via `AboutWindowController` (using `NSPanel` + `NSHostingView`).

The PDF editor needs to open in a **separate window** — not embedded in the detail pane — so users can annotate without disrupting their library workflow.

## Goals / Non-Goals

**Goals:**
- Provide a dedicated editor window for annotating PDFs with freehand drawing, shapes, text, sticky notes, images, signatures, and eraser
- Use Apple's PDFKit annotation APIs (`PDFAnnotation`, `PDFPage.addAnnotation`) for standard, portable annotations
- Support undo/redo, save/save-as, and keyboard shortcuts
- Allow multiple editor windows open simultaneously
- Keep the editor self-contained — no impact on the existing library/detail view beyond adding an "Open in Editor" entry point

**Non-Goals:**
- Replacing the existing read-only PDF preview in the detail pane
- Collaborative or cloud-synced annotations
- OCR or text recognition on annotations
- Custom annotation file formats (we use standard PDF annotations only)
- Tablet/trackpad pressure sensitivity (first iteration)

## Decisions

### 1. Window management: `NSPanel` + `NSHostingView` (AppKit-managed)

Use an `NSPanel` managed by a `PDFEditorWindowController` class, following the existing `AboutWindowController` pattern. The panel hosts a SwiftUI `PDFEditorView` via `NSHostingView`.

**Why not SwiftUI `Window` scene?** SwiftUI's `Window` / `WindowGroup` with `openWindow` requires a scene declaration at app level and has limited control over window lifecycle (close confirmation, title updates, preventing duplicate opens for the same file). The AppKit approach gives full control over window identity, close-delegate behavior (unsaved changes prompt), and multiple independent instances — which we need.

**Why not `NSWindow`?** `NSPanel` is a lightweight `NSWindow` subclass that doesn't appear in the Window menu by default and can be non-activating if needed — appropriate for a tool-like editor window. It also matches the existing About window pattern.

### 2. Annotation engine: PDFKit's built-in `PDFAnnotation` API

All annotations (ink, shapes, text, stamps, notes) map directly to standard `PDFAnnotation` subtypes:
- Freehand/highlighter → `.ink` annotations with `PDFAnnotationSubtype.ink`
- Shapes → `.square`, `.circle`, `.line` annotations
- Arrows → `.line` with `endLineStyle = .closedArrow`
- Text → `.freeText` annotations
- Sticky notes → `.text` (popup note) annotations
- Images/signatures → `.stamp` annotations with custom appearance via `PDFAppearanceCharacteristics` or drawing into the annotation's appearance stream

**Why not a custom Canvas overlay?** PDFKit annotations are natively part of the PDF — they save, render, and interoperate with other PDF viewers (Preview, Acrobat) without custom serialization. A Canvas overlay would require manual coordinate mapping, custom persistence, and wouldn't produce standard PDF annotations.

### 3. Architecture: MVVM with `PDFEditorViewModel`

```
PDFEditorWindowController (AppKit)
  └─ NSHostingView
       └─ PDFEditorView (SwiftUI)
            ├─ AnnotationToolbar
            ├─ PropertyPanel
            └─ PDFEditorCanvasView (NSViewRepresentable → PDFView subclass)

PDFEditorViewModel (@Observable)
  ├─ activeTool: AnnotationTool
  ├─ toolProperties: ToolProperties (color, width, opacity, font)
  ├─ undoManager: UndoManager (bridged from NSView)
  ├─ hasUnsavedChanges: Bool
  └─ savedSignatures: [SignatureData]
```

- **`PDFEditorViewModel`**: Owns editor state (active tool, properties, dirty flag). Passed as environment to all child views.
- **`PDFEditorCanvasView`**: An `NSViewRepresentable` wrapping a `PDFView` subclass (`AnnotatablePDFView`) that intercepts mouse/trackpad events to create annotations based on the active tool.
- **`AnnotationToolbar`** / **`PropertyPanel`**: Pure SwiftUI views bound to the view model.

**Why a PDFView subclass?** We need to override `mouseDown`, `mouseDragged`, `mouseUp` to intercept drawing gestures before PDFView's default handling. A subclass (`AnnotatablePDFView`) is the cleanest way to do this while preserving scroll/zoom behavior when the pointer tool is active.

### 4. Undo/redo: Bridge `NSUndoManager`

Use the `PDFView`'s window's `NSUndoManager` (provided by AppKit's responder chain). Each annotation action (add, move, resize, delete, property change) registers an undo action. The SwiftUI toolbar observes `undoManager.canUndo` / `canRedo` for button state.

**Why not a custom undo stack?** `NSUndoManager` integrates with the system (Cmd+Z responder chain), supports grouping, and the window's undo manager is already wired into AppKit's event handling. A custom stack would duplicate this and risk conflicts.

### 5. Freehand drawing: Accumulate points, create ink annotation on mouseUp

During `mouseDragged`, collect `CGPoint` coordinates into a path array and render a temporary overlay (via `draw(_:for:)` override or a temporary annotation). On `mouseUp`, create a single `PDFAnnotation` of subtype `.ink` with the collected path and add it to the page.

**Why not live annotations during drag?** Continuously creating/removing annotations during drag is expensive. Collecting points and drawing a temporary path, then committing a single annotation, is smoother and simpler to undo (one undo action per stroke).

### 6. Signature persistence: UserDefaults with PNG data

Store saved signatures as an array of PNG `Data` blobs in `UserDefaults` (key: `savedSignatures`). Each signature is captured from a drawing pad view, rasterized to PNG, and stored. When placed, the PNG is embedded as a `.stamp` annotation's appearance.

**Why not files in Application Support?** Signatures are small (typically <50KB each) and few in number (<10). UserDefaults is simpler and avoids file management. If signatures grow large or numerous in the future, migration to files is straightforward.

### 7. Entry point: "Open in Editor" action

Add an "Open in Editor" button to:
- `PaperDetailView` toolbar (alongside existing Preview, Reveal in Finder, etc.)
- Right-click context menu in `PaperListView`

The action calls a static method `PDFEditorWindowController.open(url:title:)` which either focuses an existing editor window for that file or creates a new one.

## Risks / Trade-offs

**[Complex mouse event handling in PDFView subclass]** → PDFView's default mouse handling is undocumented in parts. Mitigation: Only intercept events when a drawing tool is active; pass through to `super` for pointer/selection tool so default behavior (text selection, link clicking) is preserved.

**[Stamp annotation appearance for images/signatures]** → Creating custom appearance streams for `.stamp` annotations requires drawing into a `PDFAnnotation`'s appearance via `draw(with:in:)` override or setting the annotation's image property. Mitigation: Prototype this early; fall back to creating a temporary PDF page from the image if direct appearance setting proves unreliable.

**[Coordinate system mapping]** → PDFKit uses PDF coordinates (origin at bottom-left), while mouse events use view coordinates (origin at top-left). Mitigation: Use `PDFView.convert(_:from:)` and `PDFPage.convert(_:for:)` consistently for all coordinate transformations.

**[Window lifecycle and memory]** → Multiple editor windows must not leak. Mitigation: Use `isReleasedWhenClosed = true` for editor panels (unlike About window), and ensure the view model is released with the window. Track open windows by file URL to prevent duplicate editors for the same file.

**[Large PDFs performance]** → Adding many annotations to large PDFs could slow rendering. Mitigation: PDFKit handles annotation rendering natively and is optimized for this. Monitor performance and consider lazy annotation loading if needed in future iterations.
