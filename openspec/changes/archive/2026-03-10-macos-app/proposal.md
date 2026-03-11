## Why

namingpaper has a powerful paper library backend (SQLite + FTS5, AI summarization, categorization) but is CLI-only. Researchers managing dozens or hundreds of papers need a visual interface for browsing, searching, previewing PDFs, and organizing by category — tasks that are cumbersome in a terminal. A native macOS app with an Obsidian-inspired UI provides the best experience: file-over-app philosophy, minimal chrome, keyboard-driven navigation, and deep OS integration.

## What Changes

- **New SwiftUI macOS application** in a `macos/` directory within the repository
- **Obsidian-inspired UI**: sidebar navigation (categories, recent, search), tab-based paper views, command palette (`Cmd+P`), minimal chrome with focus on content
- The app reads `~/.namingpaper/library.db` (SQLite) directly for all read operations
- Write operations (add paper, summarize, categorize) delegate to the `namingpaper` CLI via subprocess
- **No changes to existing CLI or Python code** — the app is a pure consumer of the existing database and CLI
- Dark mode / light mode (follows system)
- Distributed as a standalone `.app` bundle

## User Workflow

### Launch and Browse

- Launch app → three-column layout like Obsidian:
  - **Left sidebar**: switchable panels — Category tree, Recent papers, Search results
  - **Center list**: papers in the selected view (table rows with title, authors, year, journal)
  - **Right pane**: paper detail or PDF preview for the selected paper
- Sidebar collapses with `Cmd+\` for a focused reading view
- Multiple papers can be open as tabs (like Obsidian notes)

### Navigation

- **Category tree** (default sidebar tab): folder hierarchy from `papers_dir`, click to filter
- **Recent**: last 20 papers opened or added, sorted by access time
- **Starred/Pinned**: mark papers for quick access

### Search

- `Cmd+F` or click search icon in sidebar → switches sidebar to search results panel
- Live FTS5 search as you type, results appear instantly
- Filter chips below the search bar: author, year range, journal, category
- Results show highlighted matching terms

### Command Palette

- `Cmd+P` opens a command palette (like Obsidian/VS Code)
- Quick actions: "Add paper...", "Search...", "Open preferences", "Recategorize...", "Reveal in Finder"
- Also doubles as a quick paper switcher — type a paper title to jump to it

### Paper Detail (Tab View)

- Opens in a tab when clicking a paper (or `Enter` key)
- **Top section**: title (large), authors, year, journal, category badge, keywords as tags
- **Summary section**: AI-generated summary in a callout box
- **PDF preview**: inline PDFKit viewer below metadata, scrollable, zoomable
- **Actions toolbar**: "Open in Preview", "Reveal in Finder", "Recategorize", "Remove"
- Edit category inline — dropdown with existing categories + create new

### Add Papers

- Drag-and-drop PDFs onto the app window (drop zone overlay appears)
- Or `Cmd+O` / File → Add Papers (file picker)
- Or drag onto the dock icon
- Triggers `namingpaper add --execute --yes` in background
- Shows a progress sheet with per-file status (extracting → summarizing → categorizing → done)
- Newly added papers appear in the library immediately with a brief highlight animation

### Preferences (`Cmd+,`)

- **General**: `papers_dir` path picker, default template selection
- **AI Provider**: provider dropdown (ollama/claude/openai/gemini), model name, API key fields
- Reads/writes `~/.namingpaper/config.toml`

## Capabilities

### New Capabilities

- `app-shell`: SwiftUI app scaffold — three-column NavigationSplitView, window management, menu bar with keyboard shortcuts, tab system for multiple open papers, preferences window, appearance (dark/light/system), and `namingpaper` CLI bridge (subprocess wrapper for write operations)
- `command-palette`: Command palette overlay (`Cmd+P`) — fuzzy search across actions and paper titles, quick paper switching, action execution
- `library-browser`: Main library view — center list of papers (sortable columns: title, authors, year, journal), category tree sidebar panel, recent papers panel, starred/pinned papers, empty states and onboarding
- `paper-detail`: Paper detail tab view — metadata header (title, authors, year, journal, category badge, keyword tags), summary callout, inline PDF preview (PDFKit), action toolbar, inline category editing
- `search-ui`: Search and filter interface — live FTS5 search in sidebar panel, filter chips (author, year, journal, category), result highlighting, search history
- `add-papers`: Add paper workflow — drag-and-drop zone with overlay, file picker (`Cmd+O`), dock icon drop, progress sheet with per-file status, CLI subprocess integration, library refresh on completion
- `sqlite-reader`: Direct SQLite read layer — Swift wrapper around the `library.db` schema (papers table + FTS5), query builder for keyword search and filtered queries, async data loading, reactive updates when DB changes on disk

### Modified Capabilities

_(none — the macOS app is additive; no changes to existing CLI or library behavior)_

## Impact

- **New directory**: `macos/NamingPaper/` containing the Xcode project and SwiftUI source
- **New language**: Swift (the app is entirely Swift/SwiftUI; no Python in the app)
- **Dependencies**: SQLite (built into macOS), PDFKit (built into macOS), no third-party Swift packages needed for v1
- **Build**: Xcode project, builds to a `.app` bundle
- **Distribution**: Direct `.app` download initially; Mac App Store possible later
- **Existing code**: No modifications to Python CLI, library, or database schema
- **Database contract**: The app depends on the `papers` table schema and FTS5 index from `database.py` — schema changes require app updates
