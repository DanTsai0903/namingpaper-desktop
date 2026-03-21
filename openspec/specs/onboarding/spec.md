# Capability: onboarding

## Purpose

First-launch welcome experience that lets users choose their papers directory and provides a quick-start tutorial before entering the main app.

## ADDED Requirements

### Requirement: First-launch detection

The app SHALL detect first launch by checking whether `~/.namingpaper/config.toml` exists. `ConfigService` SHALL expose a `configExists` property that returns `true` if the config file is present on disk.

#### Scenario: No config file exists

- **WHEN** the app launches and `~/.namingpaper/config.toml` does not exist
- **THEN** the app displays the onboarding view instead of the main library view

#### Scenario: Config file exists

- **WHEN** the app launches and `~/.namingpaper/config.toml` exists
- **THEN** the app skips onboarding and shows the main library view

### Requirement: Welcome step

The onboarding view SHALL display a welcome step as the first screen. The welcome step SHALL show the app icon, the title "Welcome to NamingPaper", and a one-line description of what the app does. A "Continue" button SHALL advance to the next step.

#### Scenario: User sees welcome

- **WHEN** the onboarding view appears
- **THEN** the user sees the app icon, title, description, and a "Continue" button

#### Scenario: User advances from welcome

- **WHEN** user clicks "Continue" on the welcome step
- **THEN** the view transitions to the library directory step with animation

### Requirement: Library directory selection step

The onboarding view SHALL display a directory selection step where the user chooses their papers directory. The step SHALL show a text field pre-filled with `~/Papers` (expanded to the full path) and a "Choose Folder..." button that opens a folder picker via `.fileImporter`. The step SHALL explain that this is where papers will be stored.

#### Scenario: Default directory shown

- **WHEN** the directory selection step appears
- **THEN** the path field shows the user's home directory appended with "Papers"

#### Scenario: User picks a custom directory

- **WHEN** user clicks "Choose Folder..." and selects a directory
- **THEN** the path field updates to show the selected directory path

#### Scenario: User proceeds with default

- **WHEN** user clicks "Continue" without changing the directory
- **THEN** the view advances to the tutorial step using `~/Papers` as the papers directory

### Requirement: Quick-start tutorial step

The onboarding view SHALL display a tutorial step with 4 feature cards. Each card SHALL have an SF Symbol icon, a title, and a one-line description. The cards SHALL cover: adding papers (drag-and-drop, Cmd+O, dock icon), organizing with categories, searching the library, and CLI integration for batch operations. A "Get Started" button SHALL complete onboarding.

#### Scenario: Tutorial cards displayed

- **WHEN** the tutorial step appears
- **THEN** the user sees 4 feature cards with icons and descriptions, and a "Get Started" button

#### Scenario: User completes onboarding

- **WHEN** user clicks "Get Started"
- **THEN** the app creates the chosen papers directory, writes `config.toml` with the chosen path and default settings, and transitions to the main library view

### Requirement: Directory creation and config write on completion

When the user completes onboarding, the app SHALL create the chosen papers directory (with intermediate directories) and write a `config.toml` file via `ConfigService.shared.writeConfig()`. If directory creation fails (e.g., permission denied), the app SHALL display an inline error and remain on the directory step.

#### Scenario: Directory created successfully

- **WHEN** user clicks "Get Started" and the chosen directory can be created
- **THEN** the directory exists on disk and `~/.namingpaper/config.toml` contains the chosen `papers_dir`

#### Scenario: Directory creation fails

- **WHEN** user clicks "Get Started" and the directory cannot be created
- **THEN** the app shows an error message on the directory step and does not advance

### Requirement: Step indicators

The onboarding view SHALL display step indicators (e.g., dots) showing the current step and total number of steps. The indicators SHALL update as the user progresses.

#### Scenario: Step indicators reflect progress

- **WHEN** the user is on step 2 of 3
- **THEN** the second indicator is highlighted and the others are not
