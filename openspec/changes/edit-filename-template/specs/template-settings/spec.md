## ADDED Requirements

### Requirement: Template field in Settings

The `Settings` class SHALL include a `template` field of type `str` with a default value of `"default"`. The field SHALL accept either a preset name (`default`, `compact`, `full`, `simple`) or a custom template string containing valid placeholders.

#### Scenario: Default template when no config is set

- **WHEN** no `template` value exists in config file, environment, or CLI
- **THEN** the system SHALL use `"default"` as the template value

#### Scenario: Template set in config file

- **WHEN** user sets `template = "compact"` in `~/.namingpaper/config.toml`
- **THEN** the system SHALL use the `"compact"` preset for filename formatting

#### Scenario: Custom template in config file

- **WHEN** user sets `template = "{year} - {authors} - {title}"` in config file
- **THEN** the system SHALL use that custom template string for filename formatting

#### Scenario: Environment variable override

- **WHEN** user sets `NAMINGPAPER_TEMPLATE=simple`
- **THEN** the system SHALL use `"simple"` as the template, overriding config file values

### Requirement: CLI template flag overrides config

The CLI `--template` flag SHALL take precedence over the `template` value from config file or environment variable.

#### Scenario: CLI overrides config

- **WHEN** config file has `template = "compact"` and user passes `--template full` on CLI
- **THEN** the system SHALL use `"full"` for that invocation

#### Scenario: CLI not provided falls back to config

- **WHEN** config file has `template = "compact"` and user does not pass `--template`
- **THEN** the system SHALL use `"compact"` from config

### Requirement: Template validation at usage time

The system SHALL validate the template when it is used for renaming, not at config load time. An invalid template SHALL produce a clear error message identifying the invalid placeholder.

#### Scenario: Invalid placeholder in config

- **WHEN** config has `template = "{authors} - {invalid_field}"` and user runs `rename`
- **THEN** the system SHALL display an error identifying `{invalid_field}` as invalid and list valid placeholders

#### Scenario: Invalid config does not block unrelated commands

- **WHEN** config has an invalid template value
- **AND** user runs `namingpaper version`
- **THEN** the command SHALL succeed without template validation errors

### Requirement: Visual template builder in macOS app

The macOS app settings SHALL provide a visual template builder with two modes: preset selection and custom builder.

#### Scenario: Select a preset template

- **WHEN** user selects a preset (default, compact, full, simple) from the picker
- **THEN** the template text field SHALL populate with that preset's pattern
- **AND** the value SHALL be saved to config

#### Scenario: Insert placeholder via chip

- **WHEN** user taps a placeholder chip (e.g., "authors", "year", "journal", "title")
- **THEN** the corresponding `{placeholder}` text SHALL be inserted at the cursor position in the template text field

#### Scenario: Available placeholder chips

- **WHEN** the custom template builder is displayed
- **THEN** the system SHALL show tappable chips for: `authors`, `authors_full`, `authors_abbrev`, `year`, `journal`, `journal_abbrev`, `journal_full`, `title`

#### Scenario: Free-text separators

- **WHEN** user types separator characters (`,`, `-`, `(`, `)`, spaces, etc.) in the template text field
- **THEN** the characters SHALL be included as literal text in the template

#### Scenario: Live preview

- **WHEN** the template text field contains a valid template
- **THEN** the system SHALL display a live preview showing how the template formats an example paper (e.g., "Fama and French, (1993, JFE), Common risk factors...")

#### Scenario: Editing a preset switches to custom mode

- **WHEN** user selects a preset and then modifies the template text
- **THEN** the mode SHALL switch to "Custom" to indicate the template has been customized

#### Scenario: Invalid template warning

- **WHEN** the template text field contains an invalid placeholder
- **THEN** the system SHALL display an inline warning identifying the invalid placeholder
