## 1. ConfigService: first-launch detection

- [x] 1.1 Add `configExists` computed property to `ConfigService` that returns `true` if `config.toml` exists on disk

## 2. App-level onboarding gate

- [x] 2.1 Add `@State private var onboardingComplete: Bool` to `NamingPaperApp`, initialized from `ConfigService.shared.configExists`
- [x] 2.2 Conditionally show `OnboardingView` vs `ContentView` in `WindowGroup` — use `if`/`else` so `LibraryViewModel` is not initialized until onboarding completes
- [x] 2.3 Pass a completion callback from `NamingPaperApp` to `OnboardingView` that sets `onboardingComplete = true`

## 3. OnboardingView: structure and navigation

- [x] 3.1 Create `OnboardingView.swift` in `Views/Onboarding/` with `@State private var step: Int = 0` for 3-step flow
- [x] 3.2 Add step indicator dots at the bottom showing current step (3 total)
- [x] 3.3 Add animated transitions between steps

## 4. Step 1: Welcome

- [x] 4.1 Show app icon, "Welcome to NamingPaper" title, one-line description
- [x] 4.2 Add "Continue" button to advance to step 2

## 5. Step 2: Library directory selection

- [x] 5.1 Show explanation text, path display pre-filled with `~/Papers` (expanded), and "Choose Folder..." button
- [x] 5.2 Wire up `.fileImporter` with `allowedContentTypes: [.folder]` to update the selected path
- [x] 5.3 Add "Continue" button to advance to step 3
- [x] 5.4 Add inline error display for directory creation failures (shown later when "Get Started" is clicked)

## 6. Step 3: Quick-start tutorial

- [x] 6.1 Create 4 feature cards with SF Symbols: Add Papers (arrow.down.doc), Organize (folder), Search (magnifyingglass), CLI (terminal)
- [x] 6.2 Each card shows icon, title, and one-line description
- [x] 6.3 Add "Get Started" button that triggers completion

## 7. Completion: directory creation and config write

- [x] 7.1 On "Get Started" tap: create the chosen directory with `FileManager.default.createDirectory(withIntermediateDirectories: true)`
- [x] 7.2 Build `AppConfig` with chosen `papersDir` and defaults, call `ConfigService.shared.writeConfig()`
- [x] 7.3 If directory creation or config write fails, show error and navigate back to directory step
- [x] 7.4 On success, call the completion callback to transition to main app
