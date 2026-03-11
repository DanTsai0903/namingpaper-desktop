## 1. Project Scaffold

- [x] 1.1 Create `macos/NamingPaper/` directory structure with Xcode project and SwiftUI app target (macOS 14 deployment target)
- [x] 1.2 Create `NamingPaperApp.swift` with `@main`, `WindowGroup` scene, `Settings` scene, and minimum window size (900x600)
- [x] 1.3 Create `AppDelegate.swift` with `NSApplicationDelegate` for dock icon file drop handling

## 2. Models

- [x] 2.1 Create `Paper.swift` struct mirroring the `papers` table columns (id, sha256, title, authors, authorsAll, year, journal, journalAbbrev, summary, keywords, category, filePath, confidence, createdAt, updatedAt)
- [x] 2.2 Create `Category.swift` model for category grouping (name, paper count)

## 3. SQLite Reader Service

- [x] 3.1 Create `DatabaseService` actor that opens `~/.namingpaper/library.db` with `SQLITE_OPEN_READONLY` via the C API
- [x] 3.2 Implement `listPapers(limit:offset:orderBy:)` method returning `[Paper]`
- [x] 3.3 Implement `search(query:)` method using FTS5 MATCH with relevance ranking
- [x] 3.4 Implement filtered queries (author substring, year range, journal, category) combinable with FTS5
- [x] 3.5 Implement `listCategories()` returning category names with paper counts
- [x] 3.6 Implement schema version check — read `schema_version` table, warn if newer than expected
- [x] 3.7 Implement reactive polling — check file modification timestamp every 2 seconds when app is foreground, pause when backgrounded

## 4. CLI Bridge Service

- [x] 4.1 Create `CLIService` actor with CLI binary discovery (user-configured path → `~/.local/bin/namingpaper` → `$PATH`)
- [x] 4.2 Implement `run(command:arguments:)` method using `Process` with stdout/stderr `Pipe` capture on background thread
- [x] 4.3 Implement `addPaper(path:)` that runs `namingpaper add --execute --yes <path>` and parses output for stage progress
- [x] 4.4 Implement `removePaper(id:)` that runs `namingpaper remove --execute --yes <id>`

## 5. Config Service

- [x] 5.1 Create `ConfigService` that reads `~/.namingpaper/config.toml` for papers_dir, provider, model, and API key fields
- [x] 5.2 Implement TOML write-back for preferences changes (minimal hand-rolled parser for known keys)

## 6. Three-Column Layout and Navigation

- [x] 6.1 Create `ContentView` with `NavigationSplitView` (sidebar, list, detail) and `@AppStorage` column width persistence
- [x] 6.2 Create `SidebarView` with segmented control switching between Categories, Recent, and Search panels
- [x] 6.3 Implement sidebar toggle via `Cmd+\`

## 7. Library Browser (Center Column)

- [x] 7.1 Create `PaperListView` with SwiftUI `Table` (columns: title, authors, year, journal) and sortable column headers
- [x] 7.2 Create `PaperRowView` for table rows with star/pin toggle icon
- [x] 7.3 Create `CategoryTreeView` for sidebar Categories panel with "All Papers" at top, category list with count badges
- [x] 7.4 Create `RecentPapersView` for sidebar Recent panel showing last 20 papers
- [x] 7.5 Implement starred/pinned papers persisted via `@AppStorage`, with "Starred" section above category tree
- [x] 7.6 Create empty state / onboarding view for when library has zero papers (welcome message, add instructions, CLI check)

## 8. Tab System

- [x] 8.1 Create `TabManager` observable with `openTabs: [PaperTab]`, `activeTabID: String?`, open/close/switch methods
- [x] 8.2 Create `TabBarView` — horizontal scrollable row above detail column, close button on hover, truncated titles
- [x] 8.3 Wire keyboard shortcuts: `Cmd+W` close tab, `Cmd+Shift+]`/`[` switch tabs
- [x] 8.4 Prevent duplicate tabs — if paper already open, switch to existing tab

## 9. Paper Detail (Right Column)

- [x] 9.1 Create `PaperDetailView` with metadata header (title, authors, year, journal, category badge, keyword tags)
- [x] 9.2 Create summary callout box with "No summary available" fallback
- [x] 9.3 Create `PDFPreviewView` wrapping PDFKit `PDFView` via `NSViewRepresentable` with fit-width default, zoom slider, page indicator
- [x] 9.4 Handle missing PDF file — show "PDF not found" placeholder
- [x] 9.5 Create action toolbar: "Open in Preview", "Reveal in Finder", "Recategorize", "Remove" (with confirmation dialog)
- [x] 9.6 Implement inline category editing — click category badge to show dropdown of existing categories + "New Category..."

## 10. Search and Filtering

- [x] 10.1 Create search panel in sidebar with text input, activated by `Cmd+F`, debounced at 150ms
- [x] 10.2 Wire search input to `DatabaseService.search()` and update paper list with results
- [x] 10.3 Create filter chips below search field (author, year range, journal, category) with popover/dropdown for each
- [x] 10.4 Implement result highlighting — bold/color matching terms in title and author columns
- [x] 10.5 Implement search history — persist last 10 queries, show as suggestions when search field is focused and empty

## 11. Command Palette

- [x] 11.1 Create `CommandPaletteView` overlay triggered by `Cmd+P` — centered floating panel with text field and results list
- [x] 11.2 Implement fuzzy substring matching across action names and paper titles, grouped (actions first, then papers)
- [x] 11.3 Register actions: "Add Paper...", "Search Library", "Open Preferences", "Reveal in Finder", "Sync Library"
- [x] 11.4 Wire paper selection from palette to open/switch tab

## 12. Add Papers Workflow

- [x] 12.1 Implement `.onDrop(of: [.pdf])` on main window with `DropZoneOverlay` (semi-transparent overlay with drop icon)
- [x] 12.2 Implement file picker via `Cmd+O` using `.fileImporter(allowedContentTypes: [.pdf], allowsMultipleSelection: true)`
- [x] 12.3 Wire dock icon drop from `AppDelegate` to add workflow
- [x] 12.4 Create `AddPaperSheet` — modal progress sheet with per-file rows (filename, stage indicator, checkmark/error icon)
- [x] 12.5 Process files sequentially via `CLIService.addPaper()`, updating row status per stage
- [x] 12.6 Refresh library from database on completion, highlight newly added papers with animation

## 13. Preferences

- [x] 13.1 Create `PreferencesView` with tab bar (General, AI Provider)
- [x] 13.2 Create `GeneralPrefsView` — papers_dir path picker, CLI binary path picker, appearance toggle (system/light/dark)
- [x] 13.3 Create `AIProviderPrefsView` — provider dropdown (ollama/claude/openai/gemini), model name field, API key field (stored in Keychain)
- [x] 13.4 Wire preferences reads/writes to `ConfigService` and `@AppStorage`

## 14. Menu Bar and Keyboard Shortcuts

- [x] 14.1 Define `.commands` in `NamingPaperApp` for all keyboard shortcuts (Cmd+O, Cmd+F, Cmd+P, Cmd+W, Cmd+Shift+]/[, Cmd+\, Cmd+,)
- [x] 14.2 Disable context-dependent menu items when not applicable (e.g., Close Tab when no tabs open)
