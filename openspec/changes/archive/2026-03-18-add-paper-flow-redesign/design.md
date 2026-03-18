## Context

The macOS app's "Add Paper" flow currently calls `CLIService.addPaper()` immediately after file selection. This runs `namingpaper add --execute --yes --copy <path>`, which extracts metadata, renames, summarizes, categorizes, and persists — all in one shot. The user sees only pass/fail status per file and cannot configure options or review results.

The CLI already supports dry-run mode (omit `--execute`), which runs the full pipeline but skips file operations and database persistence. It also supports `--provider`, `--template`, and `--category` flags. The key gap is that the app doesn't expose these options and doesn't use dry-run for preview.

## Goals / Non-Goals

**Goals:**
- Let users configure AI provider, template, reasoning toggle, and category priority before processing starts
- Show AI-generated results (name, category) and let users edit them before committing
- Use the CLI's existing dry-run mode for the preview step, then execute with overrides for the commit step
- Keep the flow lightweight — configuration should have sensible defaults so users can skip straight to processing

**Non-Goals:**
- Changing the CLI's core `add` pipeline or `library.py` logic
- Adding a JSON output mode to the CLI (parse existing text output instead)
- Per-file configuration (all files in a batch share the same options)
- Persisting user's last-used options across sessions (can be added later)

## Decisions

### 1. Three-phase sheet flow: Configure → Process → Review

The `AddPaperSheet` becomes a multi-step flow controlled by an enum state (`AddFlowPhase`):

- **Configure**: Shown after file selection. Provider picker, template picker, reasoning toggle, category priority toggle. "Start Processing" button advances to next phase.
- **Processing**: Current progress view (per-file stage indicators). Runs automatically once entered.
- **Review**: Shows results table with editable name and category per file. "Add to Library" button commits.

**Why over separate sheets**: Keeps context in one place. The user sees their files throughout and can understand the full flow.

**Why not skip configure with a "quick add"**: We still want the configure phase to appear, but with defaults pre-filled so users can just click "Start" without changing anything. This preserves discoverability of options.

### 2. Two-pass CLI invocation: dry-run then execute

For each file:
1. **Dry-run pass**: `namingpaper add <path> --copy --provider X --template Y` (no `--execute`). Parse stdout for the suggested filename, category, metadata.
2. **Execute pass** (after user confirms): `namingpaper add <path> --execute --yes --copy --provider X --template Y --category <user-chosen>`. If the user edited the name, we can't pass that through CLI — handle via post-rename or a new `--filename` flag.

**Why two passes over a single --json flag**: Avoids CLI changes. Dry-run already produces all the info we need. The second pass with `--category` override respects user edits.

**Trade-off — edited filenames**: The CLI doesn't support a `--filename` override. Options:
- (a) Add `--filename` flag to CLI — clean but requires CLI change
- (b) Let CLI generate the name, then rename the file post-add — fragile
- (c) Only allow category edits, show name as read-only — simplest

**Decision**: Option (a) — add a `--filename` flag to the CLI `add` command. This is a small, backward-compatible addition and avoids fragile workarounds.

### 3. Reasoning toggle via `--reasoning` / `--no-reasoning` CLI flag

Add a boolean flag to the CLI `add` and `rename` commands. When `--no-reasoning` (default, preserving current behavior), Qwen3 thinking is disabled as today. When `--reasoning`, remove the `enable_thinking: False` override in oMLX and let the model use its native thinking mode.

The provider base class gains an optional `reasoning: bool` parameter passed through from CLI. Only oMLX uses it currently, but the plumbing supports future providers (Claude extended thinking, etc.).

**Why a CLI flag over config.toml**: It's a per-invocation choice — some papers may benefit from reasoning (complex multi-author papers) while others don't need it. Config.toml can provide a default, but the flag allows override.

### 4. Rename toggle (rename vs categorize-only)

A "Rename file" toggle (default on) controls whether the paper's filename is changed. When off, the CLI still extracts metadata, summarizes, and categorizes, but the file keeps its original filename. In the app, this is passed as `--no-rename` to the CLI.

**Implementation**: The CLI `add` command gains a `--no-rename` flag. When set, `library.add_paper()` skips `build_filename()` and uses the original PDF filename instead. Metadata extraction and categorization still run normally. In the review step, the name field is shown as read-only (original filename) when rename is disabled.

### 5. Category priority toggle

When "Prioritize existing categories" is enabled, the app passes an existing category name via `--category` only if the AI's suggestion matches one of the existing categories. Otherwise, it lets the AI suggest freely.

**Revised approach**: Actually, this is better handled in the review step. The configure toggle sets a preference, and in the review step, the category picker pre-selects the closest existing category match (or the AI suggestion if no match). This avoids overriding AI categorization entirely and gives the user final say.

### 6. Parsing CLI dry-run output

The CLI's dry-run output is a Rich table with fields: Title, Authors, Year, Journal, Summary, Keywords, Category, Destination. Parse this by:
- Looking for the "Destination" row to get the suggested filename/path
- Looking for the "Category" row to get the suggested category
- Capturing the full output for display

Since Rich formatting is disabled via `NO_COLOR=1` and `TERM=dumb` (already set in `CLIService`), the output is plain text and parseable with simple string matching.

### 7. AddPaperItem model extension

Extend `AddPaperItem` with result fields:

```
struct AddPaperResult {
    var suggestedName: String
    var suggestedCategory: String
    var editedName: String      // user's edit, defaults to suggestedName
    var editedCategory: String  // user's edit, defaults to suggestedCategory
    var title: String
    var authors: String
    var year: String
    var journal: String
}
```

`AddPaperItem` gains an optional `result: AddPaperResult?` populated after dry-run.

## Risks / Trade-offs

- **Parsing CLI text output is brittle** → Mitigation: the output format is stable, controlled by our own code, and Rich formatting is disabled. If it breaks, errors surface clearly (unparseable output → show raw text to user).
- **Two CLI invocations per file doubles processing time** → Mitigation: the second invocation (execute) reprocesses the PDF. This is wasteful but acceptable for now — the alternative (adding a "commit from dry-run" mode) is a larger CLI change. For batch adds, this could be slow. Future optimization: add a `--commit-preview` flag that skips re-extraction.
- **`--filename` flag is a CLI addition** → Small scope, backward-compatible. If we defer this, option (c) (read-only name) is a safe fallback.
- **Reasoning toggle may produce unexpected output** → Qwen3 thinking tokens appear in response. The base provider's JSON fallback parser (`_RE_JSON_OBJECT`) already handles thinking/reasoning text before JSON, so this should work. Test with reasoning enabled.

## Open Questions

- Should we add `--json` output to the CLI `add` command for more reliable parsing? (Deferred — text parsing works for now)
- Should the reasoning toggle be per-provider or global? (Starting with global toggle, revisit if needed)
- Should we persist the user's last-used configuration options? (Deferred to a follow-up)
