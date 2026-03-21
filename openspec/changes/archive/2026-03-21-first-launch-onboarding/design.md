# Design

## Context

On first launch, no `~/.namingpaper/config.toml` exists. The app currently defaults to `~/Papers` and shows an empty library view. There is no onboarding — new users must figure things out on their own.

The app already has:

- `ConfigService` that reads/writes `config.toml` and returns defaults when the file is missing
- `GeneralPrefsView` with a directory picker and migration logic for moving an existing library
- `EmptyLibraryView` shown when `viewModel.isEmpty == true`
- `DirectoryMonitor` that silently fails if the papers directory doesn't exist

## Goals / Non-Goals

**Goals:**

- Let users choose their papers directory before the app creates anything on disk
- Provide a brief tutorial so new users understand the key workflows (add papers, categories, CLI)
- Write `config.toml` and create the papers directory at the end of onboarding
- Make onboarding feel native to macOS — clean, minimal, not a wizard

**Non-Goals:**

- CLI installation during onboarding (out of scope — just mention it exists)
- AI provider configuration (belongs in Preferences)
- Importing an existing library from another tool
- Showing onboarding again after completion

## Decisions

### 1. First-launch detection: check for `config.toml`

Use `FileManager.default.fileExists(atPath: configPath)` to detect first launch. If `~/.namingpaper/config.toml` does not exist, the user has never completed onboarding.

**Why not `UserDefaults`?** The config file is the source of truth for the CLI too. If a user deletes `~/.namingpaper/` to reset, onboarding should reappear. `UserDefaults` would persist independently and get out of sync.

**Why not check for `library.db`?** The DB is created by the CLI, not the app. A user could have a config but no DB yet (CLI not run). Config existence is the right signal for "app has been set up."

Add a `configExists` property to `ConfigService` to expose this check.

### 2. Gate onboarding in `NamingPaperApp.body`

Wrap the `WindowGroup` content in a conditional:

- If `configExists == false` → show `OnboardingView`
- If `configExists == true` → show `ContentView` (current behavior)

Use `@State private var onboardingComplete: Bool` initialized from `ConfigService.shared.configExists`. When onboarding finishes, set this to `true` to trigger the transition.

**Why `NamingPaperApp` and not `ContentView`?** The `LibraryViewModel` shouldn't be initialized until onboarding completes — it immediately starts polling, monitoring, and hitting the DB. Gating at the app level avoids wasted work.

### 3. OnboardingView as a multi-step flow with a single view

Use a `@State private var step: Int` to move through 3 steps within one view, animated with `.transition()`:

1. **Welcome** — App icon, "Welcome to NamingPaper", one-line description
2. **Choose Library** — Directory picker with `~/Papers` as default, "Choose Folder" button using `.fileImporter`, brief explanation of what this directory is for
3. **Quick Start Guide** — 3-4 cards showing key features: drag-and-drop to add papers, categories for organization, search across your library, CLI for batch operations

A "Get Started" button on the final step writes config and creates the directory.

**Why not a sheet/modal?** The onboarding *is* the entire first experience. A sheet over an empty window looks broken. A full-window view feels intentional.

**Why not separate views per step?** Three steps is simple enough for one view with conditional rendering. No need for a `TabView` or navigation stack.

### 4. Directory creation and config write on completion

When the user taps "Get Started":

1. Create the chosen directory with `FileManager.default.createDirectory(withIntermediateDirectories: true)`
2. Build an `AppConfig` with the chosen `papersDir` and defaults for everything else
3. Call `ConfigService.shared.writeConfig(config)` — this also creates `~/.namingpaper/` if needed
4. Set `onboardingComplete = true` to transition to the main app

This ensures no files are created on disk until the user explicitly confirms.

### 5. Tutorial content: static, not interactive

The quick-start guide shows static cards with SF Symbols and short descriptions. No interactive tutorial or step-by-step walkthrough — users learn better by doing, and the empty library view already has instructional text.

Cards:

- **Add Papers** (arrow.down.doc) — "Drag PDFs onto the window, use Cmd+O, or drop onto the dock icon"
- **Organize** (folder) — "Create categories to group related papers"
- **Search** (magnifyingglass) — "Search across titles, authors, journals, and keywords"
- **CLI Integration** (terminal) — "Use the namingpaper CLI to batch-rename and auto-extract metadata"

## Risks / Trade-offs

- **[Risk] User cancels directory picker without choosing** → Keep `~/Papers` as the pre-filled default. The user can proceed without ever opening the picker if the default is fine.
- **[Risk] Chosen directory is not writable** → Catch the error from `createDirectory` and show an inline error message, keeping the user on the directory step.
- **[Risk] `LibraryViewModel` initialized before onboarding completes** → Gate at `NamingPaperApp` level so the view model is only created after `onboardingComplete == true`. Use `if`/`else` (not `.opacity` or `.overlay`) so SwiftUI doesn't eagerly initialize the `ContentView` branch.
