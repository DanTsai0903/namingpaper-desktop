# Tasks

## 1. CLI: New flags

- [x] 1.1 Add `--filename` / `-f` option to the `add` command in `cli.py`; pass it through to `library.add_paper()` as `filename_override`
- [x] 1.2 Implement `filename_override` in `library.add_paper()` — use it instead of `build_filename()` when provided; append `.pdf` if missing
- [x] 1.3 Add `--no-rename` flag to the `add` command in `cli.py`; pass it through to `library.add_paper()` as `no_rename`
- [x] 1.4 Implement `no_rename` in `library.add_paper()` — skip `build_filename()` and use the original PDF filename when set
- [x] 1.5 Add `--reasoning` / `--no-reasoning` flag to the `add` and `rename` commands in `cli.py`; pass through to provider creation
- [x] 1.6 Plumb `reasoning` bool through `providers/__init__.py` `get_provider()` and into `providers/base.py` `AIProvider.__init__`
- [x] 1.7 Update `omlx.py` `_build_payload()` to conditionally set `enable_thinking` based on the provider's `reasoning` flag instead of hardcoding `False`
- [x] 1.8 Add tests for `--filename` override, `--no-rename`, and `--reasoning` flag propagation

## 2. CLIService: Extended Swift interface

- [x] 2.1 Add `template`, `reasoning`, `filename`, and `noRename` parameters to `CLIService.addPaper()` and build the corresponding CLI arguments
- [x] 2.2 Add a `dryRunAddPaper()` method that calls `namingpaper add` without `--execute` and returns the raw stdout
- [x] 2.3 Implement stdout parser to extract suggested name (from "Destination" row) and category (from "Category" row) from dry-run output into a new `AddPaperDryRunResult` struct

## 3. Models: Add flow state

- [x] 3.1 Create `AddFlowPhase` enum with cases: `configure`, `processing`, `review`
- [x] 3.2 Create `AddPaperResult` struct with fields: `suggestedName`, `suggestedCategory`, `editedName`, `editedCategory`, `title`, `authors`, `year`, `journal`
- [x] 3.3 Extend `AddPaperItem` with optional `result: AddPaperResult?` field
- [x] 3.4 Add `AddPaperOptions` struct: `provider`, `template`, `categoryPriority`, `reasoning`, `renameFile` with sensible defaults

## 4. ViewModel: Multi-phase logic

- [x] 4.1 Add `phase: AddFlowPhase` property to `AddPaperViewModel`, starting at `.configure`
- [x] 4.2 Add `options: AddPaperOptions` property with defaults (provider from UserDefaults, template "default", reasoning off, category priority off)
- [x] 4.3 Refactor `addFiles()` to only populate items and stay in `.configure` phase — do not start processing
- [x] 4.4 Add `startProcessing()` method that transitions to `.processing` and runs dry-run CLI for each file, populating `AddPaperResult` per item
- [x] 4.5 Add `commitPapers()` method that runs execute CLI for each successful item using edited name/category, then transitions to done
- [x] 4.6 Implement category priority logic in `startProcessing()`: after dry-run, if toggle is on, match AI-suggested category against existing categories and pre-select the closest match as `editedCategory`

## 5. View: Configure step

- [x] 5.1 Restructure `AddPaperSheet` with a `switch` on `phase` to show different views per phase
- [x] 5.2 Build configure phase view: file list, provider picker (pre-selected from UserDefaults), template picker, reasoning toggle, rename toggle (on by default), category priority toggle
- [x] 5.3 Add "Start Processing" button that calls `startProcessing()`, and "Cancel" button that dismisses the sheet

## 6. View: Processing step

- [x] 6.1 Reuse existing per-file progress UI (stage icons, filenames, error messages) for the processing phase
- [x] 6.2 Auto-transition to review phase when all files finish processing

## 7. View: Review step

- [x] 7.1 Build review table: each row shows original filename, editable name field (TextField, read-only when rename is disabled), editable category picker (ComboBox with existing categories + AI suggestion), and metadata summary (title, authors, year)
- [x] 7.2 Show error rows as non-editable with error message displayed
- [x] 7.3 Add "Add to Library" button that calls `commitPapers()`, disabled when no successful results exist
- [x] 7.4 Add "Cancel" button that dismisses the sheet without committing
- [x] 7.5 Show per-file progress indicators during commit phase (spinner → checkmark/error)

## 8. Integration and polish

- [x] 8.1 Ensure library refresh (`forceRefresh()`) triggers after successful commit
- [x] 8.2 Reset ViewModel state (phase, options, items) when sheet is dismissed
- [ ] 8.3 Test full flow end-to-end: select files → configure → process → review/edit → commit
