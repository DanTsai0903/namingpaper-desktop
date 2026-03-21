## Why

NamingPaper's macOS UI is entirely English. Adding localization for Chinese (Simplified and Traditional), Spanish, Japanese, and Korean makes the app accessible to a much larger academic audience — these are some of the largest research communities globally.

## What Changes

- Add Apple String Catalog (`Localizable.xcstrings`) localization infrastructure to the macOS app
- Extract all user-facing strings from SwiftUI views, menus, alerts, and preferences into localizable keys
- Add translations for 5 new locales: zh-Hans, zh-Hant, es, ja, ko
- App language follows macOS system language preference automatically (standard Apple behavior)
- No changes to the CLI tool or Python backend — this is macOS UI only

## Capabilities

### New Capabilities
- `ui-localization`: Localization infrastructure (String Catalogs), string extraction, and translations for zh-Hans, zh-Hant, es, ja, ko in the macOS app

### Modified Capabilities

_(none — no existing spec-level requirements change)_

## Impact

- **Views**: All SwiftUI views with hardcoded English strings need string extraction (~15+ view files)
- **Menus/Alerts**: Menu items, confirmation dialogs, error messages need localization
- **Xcode project**: New String Catalog asset, localization settings in project config
- **Build**: No new dependencies — uses Apple's built-in String Catalog system (Xcode 15+)
- **Testing**: Need to verify layouts don't break with longer translations (e.g., German-length Spanish strings, CJK character width)
