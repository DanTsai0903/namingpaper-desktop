## ADDED Requirements

### Requirement: Provider selection

The configuration step SHALL display a picker for AI provider. The picker SHALL list all available providers: claude, openai, gemini, ollama, omlx. The default selection SHALL match the provider configured in Preferences (UserDefaults `aiProvider` key), falling back to "ollama" if none is set.

#### Scenario: Provider picker shows available providers

- **WHEN** the configuration step is displayed
- **THEN** a provider picker shows options: claude, openai, gemini, ollama, omlx with the user's configured default pre-selected

#### Scenario: User selects a different provider

- **WHEN** user selects "gemini" from the provider picker
- **THEN** the selected provider is passed to the CLI via `--provider gemini`

### Requirement: Template selection

The configuration step SHALL display a picker for filename template. The picker SHALL list all preset templates: default, compact, full, simple. The default selection SHALL be "default".

#### Scenario: Template picker shows presets

- **WHEN** the configuration step is displayed
- **THEN** a template picker shows options: default, compact, full, simple with "default" pre-selected

#### Scenario: User selects a template

- **WHEN** user selects "compact" from the template picker
- **THEN** the selected template is passed to the CLI via `--template compact`

### Requirement: Category priority toggle

The configuration step SHALL display a toggle for "Prioritize existing categories". When enabled, the review step SHALL pre-select the closest matching existing category for each paper instead of the AI-suggested category. The default state SHALL be off.

#### Scenario: Toggle is off by default

- **WHEN** the configuration step is displayed
- **THEN** the "Prioritize existing categories" toggle is off

#### Scenario: Toggle affects review step behavior

- **WHEN** user enables "Prioritize existing categories" and processing completes
- **THEN** the review step pre-selects the closest existing category match for each paper's category field

### Requirement: Reasoning toggle

The configuration step SHALL display a toggle for "Enable reasoning". When enabled, the CLI invocation SHALL include a flag to enable thinking/reasoning mode for models that support it (e.g., Qwen3 on oMLX). The default state SHALL be off, preserving current behavior.

#### Scenario: Reasoning toggle off by default

- **WHEN** the configuration step is displayed
- **THEN** the "Enable reasoning" toggle is off

#### Scenario: Reasoning enabled

- **WHEN** user enables "Enable reasoning" and processing starts
- **THEN** the CLI invocation includes `--reasoning` flag

#### Scenario: Reasoning disabled

- **WHEN** the "Enable reasoning" toggle is off and processing starts
- **THEN** the CLI invocation does not include `--reasoning` flag (default behavior, thinking disabled)

### Requirement: Rename toggle

The configuration step SHALL display a "Rename file" toggle. When enabled (default), the AI-generated filename is used. When disabled, the original PDF filename is kept and only categorization is performed. The toggle state SHALL be passed to the CLI via `--no-rename` when disabled.

#### Scenario: Rename toggle on by default

- **WHEN** the configuration step is displayed
- **THEN** the "Rename file" toggle is on

#### Scenario: Rename disabled

- **WHEN** user disables the "Rename file" toggle and processing starts
- **THEN** the CLI invocation includes `--no-rename` flag and the review step shows the original filename as read-only

#### Scenario: Rename enabled

- **WHEN** the "Rename file" toggle is on and processing starts
- **THEN** the CLI invocation does not include `--no-rename` and the review step shows the AI-suggested name as editable

### Requirement: Start processing action

The configuration step SHALL have a "Start Processing" button. Pressing it SHALL transition the flow from the configure phase to the processing phase. The button SHALL be enabled as long as at least one file is selected.

#### Scenario: Start processing

- **WHEN** user clicks "Start Processing" with files selected
- **THEN** the flow transitions to the processing phase and AI processing begins with the configured options

#### Scenario: Cancel before processing

- **WHEN** user clicks "Cancel" during the configuration step
- **THEN** the sheet is dismissed without processing any files
