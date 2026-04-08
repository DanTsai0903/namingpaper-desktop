## Why

NamingPaper currently provides a read-only PDF preview. Users who want to annotate papers — adding highlights, text notes, signatures, or images — must switch to an external app. An in-app PDF editor lets users mark up papers without leaving the library, keeping their annotation workflow integrated with paper management. Inspired by [LeedPDF](https://github.com/rudi-q/leed_pdf_viewer), which demonstrates a rich annotation experience with freehand drawing, shape tools, sticky notes, and smart eraser.

## What Changes

- Open a **dedicated editor window** for PDF annotation (separate from the library/detail view) with tools for:
  - **Freehand drawing**: Pencil tool with customizable color, thickness, and opacity; highlighter tool with semi-transparent strokes
  - **Shape tools**: Rectangles, circles/ovals, arrows, and lines with stroke/fill options
  - **Text annotations**: Freeform text boxes with font, size, and color controls; inline editing
  - **Sticky notes**: Quick comment annotations that expand on click
  - **Image overlay**: Insert images (figures, diagrams, stamps) onto pages
  - **Signature**: Draw a signature or place a saved one; persist signatures for reuse
  - **Eraser**: Smart eraser that removes intersecting annotation elements
- Add an "Open in Editor" action from the paper detail view or context menu to launch the editor window
- Add **undo/redo** support for all annotation actions (Cmd+Z / Cmd+Shift+Z)
- Add ability to **save** annotated PDFs (overwrite or save-as copy)
- Add property controls: color picker, line width slider, opacity slider, font selector
- Support keyboard shortcuts for tool selection (matching LeedPDF's quick-switch pattern)

## Capabilities

### New Capabilities
- `pdf-annotation`: Core annotation engine — manages annotation types (freehand, shapes, text, sticky notes, images, signatures), rendering, selection, moving/resizing, eraser, undo/redo stack, and persistence using PDFKit's annotation APIs
- `pdf-editor-ui`: Dedicated editor window with toolbar, tool selection, property panels (color, stroke, font, opacity), keyboard shortcuts, save controls, and "Open in Editor" entry point from the library

### Modified Capabilities
<!-- No existing spec-level behavior changes needed. The PDF preview view will be extended
     but the core reading capability requirements remain unchanged. -->

## Impact

- **Code**: New `PDFEditorWindow` and supporting views/view models; adds an "Open in Editor" action to `PaperDetailView` and context menus
- **Frameworks**: Relies on Apple's `PDFKit` (`PDFAnnotation`, `PDFPage.addAnnotation`) — no new external dependencies needed
- **Data**: Annotations are stored within the PDF file itself (standard PDF annotations), so no database schema changes needed. Saved signatures stored in app preferences or local storage.
- **File system**: Saving edited PDFs modifies files in the library; needs to coordinate with existing file management in library services
- **UX**: Editor opens in a separate window, keeping the library view undisturbed; multiple editor windows may be open simultaneously
