## Context

NamingPaper has a complete paper library backend (SQLite + FTS5, AI summarization, categorization) exposed through CLI commands. This design covers a native macOS SwiftUI application that provides an Obsidian-inspired visual interface for browsing, searching, and managing the library. The app is a pure consumer of the existing database and CLI — no changes to Python code.

## Goals

- Provide a keyboard-driven, minimal-chrome UI for managing academic papers
- Read directly from `library.db` for instant browsing and search
- Delegate all write operations to the `namingpaper` CLI subprocess
- Ship as a standalone `.app` with zero third-party Swift dependencies
- Match Obsidian's three-column layout, tab system, and command palette UX

## Non-Goals

- Replacing or duplicating CLI functionality in Swift
- Building a cross-platform app (macOS only)
- Implementing a custom PDF renderer (use built-in PDFKit)
- Mac App Store distribution for v1
- Syncing across devices or cloud storage
- Editing paper metadata directly (beyond category reassignment)

## Decisions

### 1. Architecture: MVVM with Observable

**Choice:** SwiftUI MVVM using `@Observable` (macOS 14+)

The app targets macOS 14 Sonoma or later to use the modern `@Observable` macro instead of `ObservableObject`. This simplifies view models and eliminates `@Published` boilerplate.

Core layers:
- **Models**: Swift structs mirroring the `papers` table schema
- **Views**: SwiftUI views composing the three-column layout
- **ViewModels**: `@Observable` classes managing state and coordinating data access
- **Services**: `DatabaseService` (SQLite reads), `CLIService` (subprocess writes)

### 2. Database Access: SQLite.swift vs Raw C API

**Choice:** Raw SQLite3 C API via Swift (built into macOS)

Using the C API directly avoids any third-party dependency. The read queries are straightforward (SELECT, FTS5 MATCH) and don't warrant a full ORM. A thin `DatabaseService` class wraps the C API with Swift-friendly methods.

Key considerations:
- Open database in **read-only mode** (`SQLITE_OPEN_READONLY`) to prevent accidental writes
- Use WAL mode compatibility — the Python side writes with WAL, reads work concurrently
- Poll for changes using `sqlite3_update_hook` or periodic re-query (every 2 seconds when app is focused)
- All DB access on a background actor to keep UI responsive

### 3. CLI Bridge: Subprocess for Writes

**Choice:** `Process` (Foundation) executing `namingpaper` CLI commands

Write operations (`add`, `remove`, `sync`) shell out to the CLI:
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/path/to/namingpaper")
process.arguments = ["add", "--execute", "--yes", pdfPath]
```

Discovery order for the CLI binary:
1. User-configured path in preferences
2. `~/.local/bin/namingpaper` (uv/pipx default)
3. Search `$PATH`

The app captures stdout/stderr via `Pipe` for progress reporting. A `CLIService` actor manages subprocess lifecycle and emits progress events.

### 4. Window Layout: NavigationSplitView Three-Column

**Choice:** `NavigationSplitView` with `.automatic` style

```
┌──────────┬────────────────────┬──────────────────────────┐
│ Sidebar  │   Paper List       │   Detail / PDF Preview   │
│          │                    │                          │
│ Categories│  [table rows]     │   Title, Authors, Year   │
│ Recent   │                    │   Summary callout        │
│ Search   │                    │   PDF viewer             │
│          │                    │                          │
└──────────┴────────────────────┴──────────────────────────┘
```

- **Sidebar** (column 1): Segmented control switching between Categories, Recent, Search
- **List** (column 2): `Table` view with sortable columns (title, authors, year, journal)
- **Detail** (column 3): Paper metadata + PDFKit inline viewer

Sidebar toggles with `Cmd+\`. Column widths are user-adjustable and persisted via `@AppStorage`.

### 5. Tab System

**Choice:** Custom tab bar above the detail column

SwiftUI doesn't have a native document-tab API for non-document apps. Implement a custom `TabBarView`:
- Horizontal scrollable row of tab items
- Each tab holds a paper ID and displays truncated title
- Close button on hover (like browser tabs)
- `Cmd+W` closes active tab, `Cmd+Shift+]` / `Cmd+Shift+[` switches tabs
- State managed by `TabManager` observable: `openTabs: [PaperTab]`, `activeTabID: String?`

### 6. Command Palette

**Choice:** Custom overlay triggered by `Cmd+P`

A floating search field with filtered results list, overlaid on the main window:
- Fuzzy matching against action names and paper titles
- Actions: "Add Paper...", "Search Library", "Open Preferences", "Reveal in Finder", etc.
- Paper results: jump to or open in new tab
- Dismiss with `Esc` or clicking outside
- Implemented as a `.sheet` or `ZStack` overlay with `@FocusState`

### 7. PDF Preview

**Choice:** PDFKit via `NSViewRepresentable`

Wrap `PDFView` from PDFKit in a SwiftUI `NSViewRepresentable`:
- Loads PDF from the file path stored in the database
- Supports scroll, zoom, page navigation
- Auto-scales to fit width by default
- Minimal controls (zoom slider, page indicator)

### 8. Add Papers: Drag-and-Drop

**Choice:** SwiftUI `.onDrop` modifier + file picker

- Main window accepts `.onDrop(of: [.pdf])` with a visual overlay
- File picker via `.fileImporter(isPresented:allowedContentTypes:)`
- Dock icon drop via `NSApplicationDelegate.application(_:open:)`
- Each dropped file triggers `CLIService.addPaper(path:)` which runs the subprocess
- Progress tracked in a sheet with per-file status rows

### 9. Preferences

**Choice:** `Settings` scene (SwiftUI native preferences)

```swift
Settings {
    PreferencesView()
}
```

Tabs:
- **General**: papers_dir path picker, CLI binary path, appearance (system/light/dark)
- **AI Provider**: provider dropdown, model name, API key (stored in Keychain)

Reads/writes `~/.namingpaper/config.toml` using a simple TOML parser (hand-rolled for the few keys needed, avoiding a dependency).

### 10. Project Structure

```
macos/
  NamingPaper/
    NamingPaper.xcodeproj/
    NamingPaper/
      App/
        NamingPaperApp.swift          # @main, Scene setup
        AppDelegate.swift             # Dock drop, lifecycle
      Models/
        Paper.swift                   # Swift mirror of papers table
        Category.swift                # Category grouping
      ViewModels/
        LibraryViewModel.swift        # Main data source
        SearchViewModel.swift         # FTS5 search state
        AddPaperViewModel.swift       # Add workflow state
        TabManager.swift              # Tab state
      Views/
        Sidebar/
          SidebarView.swift           # Category tree, recent, search
          CategoryTreeView.swift
          RecentPapersView.swift
        PaperList/
          PaperListView.swift         # Center column table
          PaperRowView.swift
        Detail/
          PaperDetailView.swift       # Right column
          PDFPreviewView.swift        # PDFKit wrapper
          TabBarView.swift
        CommandPalette/
          CommandPaletteView.swift
          CommandPaletteItem.swift
        AddPaper/
          AddPaperSheet.swift
          DropZoneOverlay.swift
        Preferences/
          PreferencesView.swift
          GeneralPrefsView.swift
          AIProviderPrefsView.swift
      Services/
        DatabaseService.swift         # SQLite read-only access
        CLIService.swift              # namingpaper subprocess bridge
        ConfigService.swift           # TOML read/write
      Utilities/
        KeyboardShortcuts.swift       # Centralized shortcut definitions
```

### 11. Minimum macOS Version

**Choice:** macOS 14 Sonoma

Required for `@Observable`, modern `Table` API, and `.inspector` modifier. This covers ~85% of active Macs as of 2026.

## Risks and Trade-offs

### Database Schema Coupling
The Swift app reads `library.db` directly, creating a tight coupling to the Python-defined schema. If the schema changes (new columns, renamed fields), the app must be updated.
**Mitigation:** The app reads only columns it knows about and ignores extras. Schema version is checked on launch — if newer than expected, show a warning to update the app.

### CLI Binary Discovery
The app depends on finding the `namingpaper` CLI on the user's system. Different install methods (uv, pipx, brew) put it in different locations.
**Mitigation:** Preferences allow manual path override. First-launch onboarding checks common locations and prompts if not found.

### Concurrent Database Access
Python CLI writes while the Swift app reads. SQLite WAL mode supports this, but edge cases exist (e.g., reading during a migration).
**Mitigation:** Open in read-only mode. If a read fails, retry after a short delay. Show a non-blocking banner if the database is temporarily locked.

### No Third-Party Dependencies
Avoiding dependencies means hand-rolling some utilities (TOML parsing, fuzzy search). This keeps the app lightweight but adds implementation effort.
**Mitigation:** Keep implementations minimal — TOML parsing only needs to handle the few config keys namingpaper uses. Fuzzy search can start as simple substring matching.

### macOS 14 Minimum
Excludes users on macOS 13 or earlier (~15% of Macs).
**Mitigation:** Acceptable trade-off for modern SwiftUI APIs that significantly reduce implementation complexity. The CLI remains available for all platforms.
