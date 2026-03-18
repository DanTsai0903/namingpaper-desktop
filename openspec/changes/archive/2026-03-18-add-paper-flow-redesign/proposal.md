## Why

The current "Add Paper" flow starts AI processing immediately after file selection, giving users no chance to configure options (provider, template, category preference). Users also cannot review or edit AI-generated results before they are committed to the library. This makes the flow feel uncontrollable — especially problematic when users want to use a specific provider, naming format, or direct papers into existing categories.

## What Changes

- **Add a configuration step between file selection and processing**: After files are selected (via drag-drop, file picker, or dock icon), show a configuration form instead of immediately starting AI processing. Options include:
  - AI provider selection (claude, openai, gemini, ollama, omlx)
  - Name format template (default, compact, full, simple)
  - Whether to prioritize existing categories over AI-suggested ones
  - Whether to enable reasoning/thinking mode (for models that support it, e.g. Qwen3 on oMLX, Claude with extended thinking)
  - Whether to rename the file or just categorize it (skip renaming, keep original filename)
- **Add a review/edit step after processing completes**: Instead of showing only pass/fail status, display the AI-suggested name and category for each paper. Users can edit both before confirming.
- **Add a confirm action to commit results**: Papers are only added to the library when the user explicitly confirms, after reviewing/editing results.
- **Pass template option through CLI**: `CLIService.addPaper` gains a `template` parameter forwarded as `--template` to the CLI.

## Capabilities

### New Capabilities

- `add-paper-options`: Configuration step UI and state — provider picker, template picker, category priority toggle, reasoning/thinking toggle, rename toggle (rename vs categorize-only), shown between file selection and AI processing.
- `add-paper-review`: Review/edit step UI and state — displays AI results (suggested name, category) per file, allows inline editing, and requires explicit confirm before committing to library.

### Modified Capabilities

- `add-papers`: The add workflow gains two new phases (configure → process → review) instead of the current single-phase (process). CLI integration adds `--template` support. The progress sheet becomes a multi-step flow.

## Impact

- **Views**: `AddPaperSheet.swift` — significant restructure into a multi-step flow (configure → processing → review)
- **ViewModels**: `AddPaperViewModel.swift` — new state for configuration options, AI results storage, and review/edit state
- **Services**: `CLIService.swift` — `addPaper()` gains `template` and `reasoning` parameters; needs to parse CLI stdout for the suggested filename/category instead of just success/fail
- **Models**: New or extended model for AI result per paper (suggested name, suggested category, editable fields)
- **CLI**: May need `--dry-run --json` or similar output mode so the app can capture AI suggestions without immediately committing the rename. May also need a `--reasoning` / `--no-reasoning` flag to control thinking mode (currently hardcoded off for Qwen3 in oMLX)
