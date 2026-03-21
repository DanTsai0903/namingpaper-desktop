## ADDED Requirements

### Requirement: String Catalog localization infrastructure
The macOS app SHALL use an Xcode String Catalog (`Localizable.xcstrings`) as the single source of truth for all user-facing strings. All localizable strings SHALL use Swift's `String(localized:)` API or SwiftUI's automatic localization via `LocalizedStringKey`.

#### Scenario: String Catalog exists and is configured
- **WHEN** the Xcode project is opened
- **THEN** a `Localizable.xcstrings` file SHALL exist in the NamingPaper target with entries for all supported locales (en, zh-Hans, zh-Hant, es, ja, ko)

#### Scenario: No hardcoded English strings in views
- **WHEN** any SwiftUI view renders user-facing text
- **THEN** the text SHALL resolve through the String Catalog rather than being a hardcoded English literal

### Requirement: Supported locales
The app SHALL support the following locales: English (en), Chinese Simplified (zh-Hans), Chinese Traditional (zh-Hant), Spanish (es), Japanese (ja), and Korean (ko). English SHALL be the development language and fallback.

#### Scenario: Language follows system preference
- **WHEN** the user's macOS system language is set to one of the supported locales
- **THEN** the app SHALL display all UI text in that locale without requiring any in-app configuration

#### Scenario: Unsupported system language falls back to English
- **WHEN** the user's macOS system language is not one of the supported locales (e.g., French)
- **THEN** the app SHALL display all UI text in English

### Requirement: View labels and button text localization
All static labels, button titles, section headers, navigation titles, toggle labels, picker labels, and segmented control labels across all views SHALL be localized.

#### Scenario: Sidebar labels display in locale
- **WHEN** the app displays the sidebar in a supported locale
- **THEN** labels such as "All Papers", "Starred", "Categories", "Recent", and "Add Paper" SHALL appear in the locale's translation

#### Scenario: Preferences tab labels display in locale
- **WHEN** the user opens Preferences in a supported locale
- **THEN** tab labels "General", "Templates", and "AI Provider" SHALL appear in the locale's translation

#### Scenario: Paper detail action buttons display in locale
- **WHEN** the user views a paper's detail in a supported locale
- **THEN** buttons "Open in Preview", "Reveal in Finder", "Recategorize", and "Remove" SHALL appear in the locale's translation

#### Scenario: Add paper workflow labels display in locale
- **WHEN** the user opens the Add Paper sheet in a supported locale
- **THEN** step labels ("Configure", "Processing", "Review Results"), button labels ("Cancel", "Start Processing", "Add to Library", "Close"), and toggle/picker labels SHALL appear in the locale's translation

### Requirement: Placeholder and hint text localization
All placeholder text in text fields and search bars SHALL be localized.

#### Scenario: Search placeholder displays in locale
- **WHEN** the search bar is empty in a supported locale
- **THEN** the placeholder "Search papers..." SHALL appear in the locale's translation

#### Scenario: Text field placeholders display in locale
- **WHEN** a text field with placeholder text is shown (e.g., author input, category input, keyword input)
- **THEN** the placeholder text SHALL appear in the locale's translation

### Requirement: Error and status message localization
All error messages, validation messages, and transient status indicators SHALL be localized.

#### Scenario: AI provider error displays in locale
- **WHEN** the AI provider fails to connect and the system locale is a supported locale
- **THEN** the error message SHALL appear in the locale's translation

#### Scenario: Validation messages display in locale
- **WHEN** a validation error occurs (e.g., duplicate template name, missing placeholder)
- **THEN** the validation message SHALL appear in the locale's translation

### Requirement: Confirmation dialog and alert localization
All alert titles, messages, and action button labels in confirmation dialogs SHALL be localized.

#### Scenario: Delete category confirmation displays in locale
- **WHEN** the user right-clicks a category and selects Delete in a supported locale
- **THEN** the alert title, message (including interpolated paper count), and button labels ("Delete", "Cancel") SHALL appear in the locale's translation

#### Scenario: Remove paper confirmation displays in locale
- **WHEN** the user clicks Remove on a paper detail in a supported locale
- **THEN** the confirmation dialog title, message (including interpolated paper title), and action labels SHALL appear in the locale's translation

### Requirement: Onboarding flow localization
All onboarding screens — welcome text, feature descriptions, and button labels — SHALL be localized.

#### Scenario: Welcome screen displays in locale
- **WHEN** the user launches the app for the first time in a supported locale
- **THEN** the welcome title "Welcome to NamingPaper", subtitle, feature descriptions, and button labels SHALL appear in the locale's translation

### Requirement: Menu and keyboard shortcut localization
Application menu items defined in SwiftUI commands SHALL be localized. Keyboard shortcuts SHALL remain unchanged across locales.

#### Scenario: App menu items display in locale
- **WHEN** the user opens the app menu bar in a supported locale
- **THEN** menu items such as "About NamingPaper", "Add Papers...", and "Find in Library" SHALL appear in the locale's translation

#### Scenario: Keyboard shortcuts are locale-independent
- **WHEN** the user presses ⌘O in any locale
- **THEN** the Add Papers action SHALL trigger regardless of the display language

### Requirement: Interpolated strings preserve dynamic values
Localized strings that contain interpolated values (paper titles, author names, counts, version numbers, percentages) SHALL correctly insert the dynamic value in all locales.

#### Scenario: Paper count interpolation in delete confirmation
- **WHEN** a category with 5 papers is being deleted in Japanese locale
- **THEN** the confirmation message SHALL include the number 5 in the grammatically correct position for Japanese

#### Scenario: Version string interpolation
- **WHEN** the About view displays in Korean locale
- **THEN** the version string SHALL include the actual version number in the correct position

### Requirement: Command palette localization
Command palette action names and section headers SHALL be localized. User-generated content (paper titles, category names) SHALL NOT be translated.

#### Scenario: Command palette actions display in locale
- **WHEN** the user opens the command palette in a supported locale
- **THEN** action names ("Add Paper...", "Search Library", "Open Preferences", "Reveal in Finder", "Sync Library") and section headers ("Actions", "Papers") SHALL appear in the locale's translation

#### Scenario: Paper titles remain untranslated
- **WHEN** the command palette shows search results for papers
- **THEN** paper titles SHALL appear in their original language as stored in the database

### Requirement: Tooltip localization
All tooltip strings SHALL be localized.

#### Scenario: Toolbar tooltips display in locale
- **WHEN** the user hovers over toolbar buttons in a supported locale
- **THEN** tooltips such as "Add Papers (⌘O)", "Copy error message", and provider management tooltips SHALL appear in the locale's translation

### Requirement: Layout accommodates translation length variation
UI layouts SHALL accommodate translations that are longer or shorter than English without truncation or layout breakage.

#### Scenario: Longer translations do not truncate
- **WHEN** a translated string is significantly longer than its English equivalent (e.g., Spanish or Japanese)
- **THEN** the UI SHALL display the full string without truncation, using wrapping or flexible layout as needed

#### Scenario: CJK characters render correctly
- **WHEN** the app displays text in zh-Hans, zh-Hant, ja, or ko locales
- **THEN** CJK characters SHALL render at the correct size and with appropriate line breaking
