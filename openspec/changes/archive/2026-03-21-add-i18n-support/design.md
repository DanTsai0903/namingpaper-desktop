## Context

The NamingPaper macOS app currently has ~200+ hardcoded English strings across ~20 Swift files. There is no localization infrastructure — no `.lproj` directories, no `.strings` files, no String Catalogs. All user-facing text is inline in SwiftUI views and view models. The app targets macOS with Xcode 15+, which supports the modern String Catalog format (`.xcstrings`).

## Goals / Non-Goals

**Goals:**
- Add localization infrastructure using Xcode String Catalogs
- Extract all hardcoded strings to localizable keys
- Provide translations for zh-Hans, zh-Hant, es, ja, ko
- App language follows macOS system preference automatically

**Non-Goals:**
- In-app language switcher (rely on macOS system setting)
- Localizing the Python CLI tool or its output
- Localizing user-generated content (paper titles, author names, category names)
- RTL layout support (none of the target languages are RTL)
- Localizing template placeholder names (`{authors}`, `{year}`, etc.) — these are format tokens, not UI text

## Decisions

### 1. Use Xcode String Catalog (`.xcstrings`) over legacy `.strings` files

**Decision:** Single `Localizable.xcstrings` file.

**Rationale:** String Catalogs are Xcode 15+'s replacement for `.strings`/`.stringsdict`. They provide a unified JSON-based format with built-in pluralization support, automatic extraction of string keys from SwiftUI, and a visual editor in Xcode. Since the app already requires macOS 14+/Xcode 15+, there's no compatibility concern.

**Alternative considered:** Legacy `.strings` + `.stringsdict` per `.lproj` directory — more files to manage, no automatic extraction, harder to review in PRs.

### 2. Use `String(localized:)` and SwiftUI automatic localization

**Decision:** For SwiftUI views, rely on automatic `LocalizedStringKey` resolution (string literals in `Text()`, `Label()`, `Button()`, etc. are automatically localized). For view models and non-SwiftUI contexts, use `String(localized:)`.

**Rationale:** SwiftUI's automatic localization means most view strings need zero code changes beyond ensuring the key exists in the String Catalog. `String(localized:)` is the modern replacement for `NSLocalizedString` and integrates with String Catalogs.

**Alternative considered:** `NSLocalizedString` — older API, more verbose, no advantage with String Catalogs.

### 3. Use string literal as the key (English = key)

**Decision:** Use the English text as the localization key (e.g., `Text("All Papers")` where "All Papers" is both the key and the English value).

**Rationale:** This is SwiftUI's default behavior. It keeps code readable — you see the English text directly. The String Catalog maps these keys to translations. No need for abstract key names like `sidebar.all_papers`.

**Alternative considered:** Abstract dot-notation keys (`sidebar.all_papers`) — harder to read in code, requires maintaining a separate key-to-English mapping, no real benefit for a project of this size.

### 4. Use string interpolation with `LocalizedStringKey` for dynamic values

**Decision:** Use Swift's string interpolation directly: `Text("Delete \"\(name)\" and its \(count) paper(s)?")`. The String Catalog handles per-locale interpolation order and pluralization via `.stringsdict`-equivalent rules embedded in `.xcstrings`.

**Rationale:** String Catalogs natively support interpolation variations and plural rules per locale, so `\(count)` can resolve to the correct plural form in each language.

### 5. Provide translations via AI-assisted translation, reviewed manually

**Decision:** Generate initial translations using AI, then review for domain accuracy. Academic terminology (e.g., "library", "paper", "journal") must use the correct scholarly terms in each locale, not generic translations.

**Rationale:** ~200 strings × 5 locales = ~1000 translations. AI provides a strong starting point, but academic domain terms vary significantly (e.g., Japanese 論文 vs. 紙 for "paper").

### 6. Organize extraction by view file

**Decision:** Extract strings file-by-file, starting with the most visible surfaces (sidebar, paper list, detail view) and working inward (preferences, onboarding, command palette, error messages).

**Rationale:** Allows incremental progress and testing. Each file can be verified independently.

## Risks / Trade-offs

**[Layout breakage with longer translations]** → Test each view with the longest expected translations (Spanish and Japanese tend to be longer). Use flexible SwiftUI layouts (`fixedSize()` sparingly, prefer wrapping).

**[Incorrect academic terminology]** → Review translations for domain-specific terms. Key terms: "paper" (学術論文/논문/artículo académico), "library" (ライブラリ/图书馆 vs. 文库), "journal" (学术期刊/学術雑誌/revista).

**[String Catalog merge conflicts]** → The `.xcstrings` file is a single JSON file. Concurrent edits could cause merge conflicts. Mitigation: do all string extraction in one feature branch.

**[Missing translations at runtime]** → If a key has no translation for the current locale, Apple falls back to the development language (English). This is safe — worst case is untranslated English text appearing in a localized UI.

## Open Questions

- Should the About view copyright notice be localized, or kept in English for legal consistency?
- Should built-in template names ("default", "compact", "full", "simple") be localized in the picker UI? They are also used as identifiers.
