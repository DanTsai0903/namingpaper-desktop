# Edit Filename Template

## Why

Users must pass `--template` on every CLI invocation to use a non-default filename template. There is no way to persist a preferred template in the config file (`~/.namingpaper/config.toml`), forcing repetitive command-line flags for users who always want the same format.

## What Changes

- Add a `template` field to the `Settings` class so users can set their preferred template in `config.toml` or via the `NAMINGPAPER_TEMPLATE` env var
- CLI `--template` flag overrides the config value (consistent with existing config priority: CLI > env > config > defaults)
- When no `--template` is passed on CLI, use the configured template (falling back to `"default"` preset)
- The macOS app settings UI should expose a visual template builder: placeholder chips (authors, year, journal, title, etc.) that users can tap to insert, combined with free-text separators (commas, parentheses, dashes, etc.) to assemble a custom template

## Capabilities

### New Capabilities

- `template-settings`: Persisting and managing the filename template preference in config, including validation, preset selection, and custom template support

### Modified Capabilities

## Impact

- `config.py` — new `template` field in `Settings`
- `cli.py` — `rename`, `batch`, and `add` commands read template from settings when not provided via CLI flag
- `template.py` — no structural changes, but `get_template()` and `validate_template()` may be called at config load time
- macOS app `SettingsView` — add template picker/editor UI
