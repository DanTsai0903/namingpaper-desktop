## 1. Config: Add template field to Settings

- [x] 1.1 Add `template: str = Field(default="default")` to `Settings` class in `config.py`
- [x] 1.2 Add `NAMINGPAPER_TEMPLATE` to the environment variables table in README

## 2. CLI: Fall back to settings template

- [x] 2.1 Update `rename` command to use `settings.template` when `--template` is not provided
- [x] 2.2 Update `batch` command to use `settings.template` when `--template` is not provided
- [x] 2.3 Update `add` command to use `settings.template` when `--template` is not provided
- [x] 2.4 Add template validation with clear error message (show invalid placeholder + list valid ones)

## 3. CLI: Update config show and templates commands

- [x] 3.1 Include the configured `template` value in `namingpaper config --show` output
- [x] 3.2 Update `namingpaper templates` to indicate which preset is currently configured

## 4. Tests

- [x] 4.1 Test default template value when no config is set
- [x] 4.2 Test template loaded from config file (preset name)
- [x] 4.3 Test custom template string from config file
- [x] 4.4 Test CLI `--template` overrides config value
- [x] 4.5 Test invalid template in config produces clear error at rename time, not at load time

## 5. macOS App: Visual template builder UI

- [x] 5.1 Add template section to SettingsView with preset picker (default, compact, full, simple)
- [x] 5.2 Add custom template text field that populates when a preset is selected
- [x] 5.3 Add placeholder chips (authors, authors_full, authors_abbrev, year, journal, journal_abbrev, journal_full, title) that insert `{placeholder}` at cursor
- [x] 5.4 Add live preview that formats an example paper with the current template
- [x] 5.5 Auto-switch to "Custom" mode when user edits a preset's template text
- [x] 5.6 Add inline validation warning for invalid placeholders
- [x] 5.7 Save template value to config when changed
