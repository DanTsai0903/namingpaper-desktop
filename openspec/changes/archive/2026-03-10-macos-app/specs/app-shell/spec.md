## ADDED Requirements

### Requirement: Three-column NavigationSplitView layout

The app SHALL present a three-column layout using `NavigationSplitView`: sidebar (column 1), paper list (column 2), and detail pane (column 3). The sidebar SHALL be toggleable with `Cmd+\`.

#### Scenario: App launches with three-column layout

- **WHEN** user launches the app
- **THEN** the window displays sidebar, paper list, and detail columns

#### Scenario: Toggle sidebar visibility

- **WHEN** user presses `Cmd+\`
- **THEN** the sidebar column collapses or expands, preserving list and detail columns

### Requirement: Window and scene management

The app SHALL use `@main` with a `WindowGroup` scene and a `Settings` scene. The app SHALL set a minimum window size of 900x600. Column widths SHALL persist across launches via `@AppStorage`.

#### Scenario: Window respects minimum size

- **WHEN** user attempts to resize the window below 900x600
- **THEN** the window stops resizing at the minimum dimensions

#### Scenario: Column widths persist

- **WHEN** user adjusts column widths and relaunches the app
- **THEN** columns restore to the previously set widths

### Requirement: Menu bar with keyboard shortcuts

The app SHALL provide a menu bar with standard macOS menus (File, Edit, View, Window, Help). Custom menu items SHALL include: Add Paper (`Cmd+O`), Search (`Cmd+F`), Command Palette (`Cmd+P`), Close Tab (`Cmd+W`), Next Tab (`Cmd+Shift+]`), Previous Tab (`Cmd+Shift+[`), Toggle Sidebar (`Cmd+\`), Preferences (`Cmd+,`).

#### Scenario: Keyboard shortcut triggers menu action

- **WHEN** user presses `Cmd+O`
- **THEN** the Add Paper file picker opens

#### Scenario: Menu items reflect current state

- **WHEN** no tabs are open
- **THEN** the Close Tab menu item is disabled

### Requirement: Tab system for multiple open papers

The app SHALL display a custom tab bar above the detail column. Each tab SHALL show a truncated paper title and a close button visible on hover. Users SHALL open papers in new tabs by clicking or pressing `Enter` on a paper in the list. `Cmd+W` SHALL close the active tab. `Cmd+Shift+]` and `Cmd+Shift+[` SHALL switch between tabs.

#### Scenario: Open paper in new tab

- **WHEN** user clicks a paper in the list (or presses `Enter`)
- **THEN** a new tab opens showing that paper's detail, and it becomes the active tab

#### Scenario: Close active tab

- **WHEN** user presses `Cmd+W` with a tab active
- **THEN** the active tab closes and the adjacent tab becomes active

#### Scenario: Switch between tabs

- **WHEN** user presses `Cmd+Shift+]`
- **THEN** the next tab to the right becomes active (wraps to first if at end)

#### Scenario: No duplicate tabs

- **WHEN** user clicks a paper that is already open in a tab
- **THEN** the existing tab for that paper becomes active instead of opening a duplicate

### Requirement: Appearance follows system

The app SHALL support dark mode, light mode, and system-automatic appearance. The default SHALL be system-automatic. Users SHALL change appearance in Preferences.

#### Scenario: System appearance change

- **WHEN** macOS switches from light to dark mode and app is set to system-automatic
- **THEN** the app immediately adopts dark mode styling

### Requirement: CLI bridge service

The app SHALL locate the `namingpaper` CLI binary using this discovery order: (1) user-configured path in Preferences, (2) `~/.local/bin/namingpaper`, (3) searching `$PATH`. The `CLIService` SHALL execute CLI commands as subprocesses using `Process`, capture stdout/stderr via `Pipe`, and run on a background thread to avoid blocking the UI.

#### Scenario: CLI binary found at configured path

- **WHEN** user has set a CLI path in Preferences and it exists
- **THEN** all CLI operations use that binary path

#### Scenario: CLI binary not found

- **WHEN** the CLI binary cannot be found at any discovery location
- **THEN** the app shows an alert directing the user to set the path in Preferences

#### Scenario: CLI command execution

- **WHEN** a write operation is triggered (add, remove, sync)
- **THEN** `CLIService` spawns a `Process`, captures output, and reports results without blocking the UI
