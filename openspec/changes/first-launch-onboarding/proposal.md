# Proposal

## Why

On first launch, the app silently defaults to `~/Papers` as the library directory and drops the user into an empty library view with no guidance. New users don't understand what the app does, how to use it, or that they need the CLI installed. There's no opportunity to choose where papers are stored before the app starts using the default location.

## What Changes

- Add a first-launch detection mechanism (check whether `~/.namingpaper/config.toml` exists)
- Show a welcome/onboarding screen on first launch that:
  - Briefly introduces what NamingPaper does
  - Lets the user choose their papers directory (with a sensible default of `~/Papers`)
  - Shows a short tutorial walkthrough explaining key features (drag-and-drop, CLI integration, categories)
  - Writes the chosen directory to `config.toml` and creates it if needed
- After onboarding completes, transition to the normal app view
- Subsequent launches skip onboarding and go straight to the library

## Capabilities

### New Capabilities

- `onboarding`: First-launch welcome screen with library directory picker and tutorial guidance

### Modified Capabilities

- `app-shell`: Gate the main content behind onboarding completion check; show onboarding view on first launch instead of the three-column layout

## Impact

- **Code**: New `OnboardingView` in Views, minor change to `NamingPaperApp` or `ContentView` to conditionally show onboarding
- **Services**: `ConfigService` used to detect first launch (no config file = first launch) and write initial config
- **Filesystem**: Creates `~/.namingpaper/config.toml` and the chosen papers directory during onboarding
- **User experience**: Existing users unaffected (config.toml already exists, onboarding skipped)
