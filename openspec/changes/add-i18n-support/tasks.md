## 1. Localization Infrastructure

- [x] 1.1 Add localization settings to the Xcode project (enable en, zh-Hans, zh-Hant, es, ja, ko in project config)
- [x] 1.2 Create `Localizable.xcstrings` String Catalog file in the NamingPaper target

## 2. String Extraction — Core Views

- [x] 2.1 Extract strings from `ContentView.swift`
- [x] 2.2 Extract strings from `SidebarView.swift` and `CategoryTreeView.swift`
- [x] 2.3 Extract strings from `PaperListView.swift` and `RecentPapersView.swift`
- [x] 2.4 Extract strings from `PaperDetailView.swift` (labels, buttons, confirmation dialogs, keyword/summary editing)
- [x] 2.5 Extract strings from `PDFPreviewView.swift` (page count, zoom percentage)
- [x] 2.6 Extract strings from `TabBarView.swift`

## 3. String Extraction — Add Paper & Onboarding

- [x] 3.1 Extract strings from `AddPaperSheet.swift` (step labels, buttons, toggles, picker labels)
- [x] 3.2 Extract strings from `DropZoneOverlay.swift`
- [x] 3.3 Extract strings from `OnboardingView.swift` (welcome text, feature descriptions, buttons)

## 4. String Extraction — Preferences

- [x] 4.1 Extract strings from `PreferencesView.swift` (tab labels)
- [x] 4.2 Extract strings from `GeneralPrefsView.swift` (directory, display options, theme, alerts)
- [x] 4.3 Extract strings from `AIProviderPrefsView.swift` (provider config labels, placeholders, validation messages)
- [x] 4.4 Extract strings from `TemplatePrefsView.swift` (template editing labels, validation, placeholders)

## 5. String Extraction — App, Menus, and Misc

- [x] 5.1 Extract strings from `NamingPaperApp.swift` (menu items and commands)
- [x] 5.2 Extract strings from `AboutView.swift` (app name, version string)
- [x] 5.3 Extract strings from `CheckForUpdatesView.swift`
- [x] 5.4 Extract strings from `CommandPaletteView.swift` (action names, section headers, placeholder)

## 6. String Extraction — View Models

- [x] 6.1 Extract error messages from `AddPaperViewModel.swift` using `String(localized:)`
- [x] 6.2 Extract any user-facing strings from `LibraryViewModel.swift` and `SearchViewModel.swift`

## 7. Translations

- [x] 7.1 Add Chinese Simplified (zh-Hans) translations to String Catalog
- [x] 7.2 Add Chinese Traditional (zh-Hant) translations to String Catalog
- [x] 7.3 Add Spanish (es) translations to String Catalog
- [x] 7.4 Add Japanese (ja) translations to String Catalog
- [x] 7.5 Add Korean (ko) translations to String Catalog

## 8. Verification

- [x] 8.1 Build and verify app launches without warnings about missing localization keys
- [ ] 8.2 Verify each locale renders correctly (spot-check sidebar, detail view, preferences, onboarding)
- [ ] 8.3 Verify interpolated strings (paper count in delete confirmation, version string) work in all locales
- [ ] 8.4 Verify CJK character rendering and layout does not truncate or break
