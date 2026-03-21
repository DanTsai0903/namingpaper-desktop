# Capability: app-shell (delta)

## MODIFIED Requirements

### Requirement: Window and scene management

The app SHALL use `@main` with a `WindowGroup` scene and a `Settings` scene. The app SHALL set a minimum window size of 900x600. Column widths SHALL persist across launches via `@AppStorage`. On first launch (when `config.toml` does not exist), the `WindowGroup` SHALL display the onboarding view instead of the main `ContentView`. The `LibraryViewModel` SHALL NOT be initialized until onboarding is complete. After onboarding completes, the app SHALL transition to the normal three-column layout.

#### Scenario: Window respects minimum size

- **WHEN** user attempts to resize the window below 900x600
- **THEN** the window stops resizing at the minimum dimensions

#### Scenario: Column widths persist

- **WHEN** user adjusts column widths and relaunches the app
- **THEN** columns restore to the previously set widths

#### Scenario: First launch shows onboarding

- **WHEN** user launches the app for the first time (no config.toml)
- **THEN** the window displays the onboarding view and `LibraryViewModel` is not created

#### Scenario: Onboarding completes and transitions to library

- **WHEN** user finishes the onboarding flow
- **THEN** the `LibraryViewModel` is initialized and the three-column layout appears
