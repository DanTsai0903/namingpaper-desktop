## Context

The filename template is currently only configurable per-invocation via `--template` / `-t`. The `Settings` class in `config.py` has no `template` field. Users who prefer a non-default template must pass `--template` every time.

The config priority chain (CLI > env > config > defaults) already works for other settings like `max_authors` and `ai_provider`. Adding `template` follows the same pattern.

## Goals / Non-Goals

**Goals:**

- Let users persist their preferred template in `config.toml` or via `NAMINGPAPER_TEMPLATE` env var
- CLI `--template` continues to override the persisted value
- Validate the template at config load time and surface clear errors
- Expose template selection in the macOS app settings UI

**Non-Goals:**

- User-defined named presets (custom preset registry) — out of scope
- Template preview/dry-run in the settings UI — can be added later
- Changing the built-in preset definitions

## Decisions

### 1. Store template as a string field in Settings

Add `template: str = Field(default="default")` to the `Settings` class. The value can be a preset name (`"default"`, `"compact"`, etc.) or a custom template string with placeholders.

**Rationale:** This matches how the CLI already accepts `--template` — a single string that `get_template()` resolves. No new types or abstractions needed.

**Alternative considered:** Separate `template_preset` and `template_custom` fields — rejected as unnecessary complexity since `get_template()` already handles both cases.

### 2. Validate at usage time, not load time

Template validation happens when the template is actually used (in `build_filename_from_template`), not at `Settings.load()`. An invalid template in config should produce a clear error at rename time, not crash the entire CLI on startup.

**Rationale:** Other settings like `ai_provider` are validated at usage time too. Failing at load time would block unrelated commands (e.g., `namingpaper version`).

### 3. CLI commands fall back to settings when --template is not provided

In `cli.py`, when `template` is `None` (no CLI flag), read `settings.template` instead of hardcoding `"default"`. The resolution chain: CLI `--template` → `NAMINGPAPER_TEMPLATE` env → `config.toml` `template` → `"default"`.

### 4. macOS app: visual template builder

The settings UI provides two modes:

- **Preset picker** — select from built-in presets (default, compact, full, simple)
- **Custom builder** — a visual editor where:
  - Placeholder chips (authors, year, journal, title, etc.) are displayed as tappable boxes
  - Tapping a chip inserts `{placeholder}` at the cursor position in the template text field
  - Users type separators (`, `, ` - `, `(`, `)`, etc.) directly in the text field between placeholders
  - A live preview shows how the template would format an example paper
  - The assembled template is stored as a single string (e.g., `"{authors}, ({year}, {journal}), {title}"`)

Selecting a preset populates the text field with that preset's pattern. Users can then customize from there, which switches the mode to "Custom".

The stored value is always a plain template string — the visual builder is purely a UI convenience.

## Risks / Trade-offs

- **[Invalid template in config]** → Clear error message at rename time with the invalid placeholder name. User can fix config or override with `--template`.
- **[Breaking change if default changes]** → Not applicable; default stays `"default"` preset, matching current behavior with no `--template` flag.
