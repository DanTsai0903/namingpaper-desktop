## Why

namingpaper currently renames PDFs and discards the extracted metadata. Users who process dozens or hundreds of papers lose all that AI-extracted information the moment the command finishes. A persistent, searchable paper library with a web UI turns namingpaper from a one-shot renaming utility into a lightweight paper management tool — think a CLI-first, local-first Zotero — without heavyweight dependencies.

## What Changes

- Add a **SQLite-backed paper library** stored at `~/.namingpaper/library.db`
- **Unified add-to-library workflow**: one command does rename → summarize → categorize
- **Full-text search** across titles, authors, journals, abstracts, summaries, keywords, and categories
- **Filestash as the web UI** for browsing, previewing, and managing paper files
- **User's-own-folder model** with nested category subfolders
- All existing commands (`rename`, `batch`, etc.) remain unchanged

## User Workflow

### Core Flow (CLI)

```
namingpaper add paper.pdf                      # preview only (dry-run)
namingpaper add paper.pdf --execute            # apply rename + placement + DB write
namingpaper add *.pdf --execute                # multiple files
namingpaper add ~/Downloads/papers/ --execute  # entire directory
```

`add` and `import` follow namingpaper safety defaults: dry-run by default, `--execute` required for filesystem and DB mutations.

**What happens on `add`:**

1. **Rename** — AI extracts metadata and renames the file using the current template (existing logic)
2. **Summarize & tag** — AI reads the abstract and generates a short summary + keywords (e.g. `asset pricing`, `CAPM`, `cross-section`); both stored in DB
3. **Categorize** — AI suggests the best category folder based on summary + keywords; user is prompted to confirm or pick a different one
4. **File** — paper is **moved** to the chosen category folder with its new name (default); `--copy` keeps the source file and copies into the library

### Step 3 in detail — Category Selection

```
📄 Fama and French, (1993, JFE), Common risk factors....pdf

Summary: Identifies three common risk factors (market, size, value)
         in stock returns using cross-sectional regressions...

Suggested category: Finance/Asset Pricing

Available categories:
  1. Finance/Asset Pricing          ← AI suggestion
  2. Finance/Empirical
  3. Finance/Risk Management
  4. Economics/Macro
  5. [Create new category]
  6. [Skip — leave in Unsorted/]

Your choice [1]:
```

The user can accept the AI suggestion (press Enter), pick a different category, or create a new one.

### Folder Structure (nested subfolders allowed)

```
~/Papers/                          # papers_dir (user-configured)
├── Unsorted/                      # default landing spot
├── Finance/
│   ├── Asset Pricing/
│   │   ├── Fama and French, (1993, JFE), Common risk....pdf
│   │   └── Sharpe, (1964, JF), Capital asset prices....pdf
│   ├── Empirical/
│   └── Risk Management/
├── Machine Learning/
│   ├── NLP/
│   └── Computer Vision/
├── Economics/
│   ├── Macro/
│   └── Labor/
└── Statistics/
    ├── Bayesian/
    └── Time Series/
```

### Search (CLI)

```bash
# Natural language / ambiguous search — AI matches against summaries
namingpaper search "papers about pricing models in equity markets"
namingpaper search "how does monetary policy affect inflation expectations"

# Keyword search across all fields (title, authors, journal, summary)
namingpaper search "risk factors"

# Filter by specific fields
namingpaper search --author "Fama"
namingpaper search --year 2020-2024
namingpaper search --journal "JFE"
namingpaper search --category "Finance/Asset Pricing"

# Combine query + filters
namingpaper search "neural network" --category "Machine Learning" --year 2022-2024
```

**Two search modes:**

- **Keyword** (default, fast) — SQLite FTS5, matches exact words across all fields
- **Smart** (`--smart` flag or auto-detected when query has 6+ words) — AI interprets the query semantically and ranks papers by relevance against stored summaries

```
Results for "papers about pricing models in equity markets":

  ID   Score  Year  Authors              Category              Title
  ──── ───── ──── ──────────────────── ──────────────────── ──────────────────────────
  a3f2  0.95  1993  Fama and French      Finance/Asset Pricing Common risk factors in...
  b7c1  0.88  2015  Fama and French      Finance/Asset Pricing A five-factor model....
  c2d8  0.72  2006  Campbell and Vuolteenaho  Finance/Asset Pricing  Bad beta, good beta...

3 papers found. Use `namingpaper info <ID>` for details.
```

### Web UI Flow (Filestash)

Use Filestash as the paper library UI:

- **Browse**: category folders and files in a familiar web file-manager interface
- **Preview**: open PDFs directly in browser
- **Manage**: upload/move/rename/share files with Filestash operations
- **Search**: Filestash file/content search for file-level discovery

Paper-specific metadata search (`author`, `year`, `journal`, `keywords`, smart semantic query) remains in `namingpaper search` and related CLI commands.

## Capabilities

### New Capabilities

- `paper-database`: SQLite database layer — connection management, schema creation, migrations, CRUD operations, and FTS5 full-text search
- `paper-library`: High-level library operations — unified add workflow (rename → summarize → categorize → file), import directory, search with filters, dedup by SHA-256 content hash (default: skip duplicates and report existing record); user's-own-folder model where `papers_dir` points to user's directory and nested subfolders become categories
- `library-cli`: New CLI commands (`add`, `list`, `search`, `info`, `remove`, `import`, `sync`) integrated into the existing Typer app; `add` orchestrates the full rename→summarize→categorize pipeline with interactive category selection
- `filestash-ui-integration`: Use Filestash as the standard UI layer for file browsing/preview/sharing; `namingpaper` remains the metadata and workflow engine behind the scenes
- `ai-summary`: AI-powered paper summarization and keyword extraction — reads the abstract, generates a structured summary + a list of keywords (e.g. `asset pricing`, `CAPM`, `cross-section`); both stored in library DB and searchable
- `auto-categorize`: AI-powered categorization — discovers existing nested subfolders in `papers_dir` as categories, uses AI to match papers to the best category based on summary + keywords; user can confirm, override, create new, or skip

### Modified Capabilities

_(none — all existing rename/batch behavior is unchanged)_

## Impact

- **New dependencies**: none required for custom web UI (Filestash is used externally as the UI)
- **New modules (backend)**: `database.py`, `library.py`, `summarizer.py`, `categorizer.py`
- **New directories**: none for frontend assets
- **Modified modules**: `models.py` (new `Paper` model with `keywords` field, `SearchFilter`), `cli.py` (new library commands; no custom `serve` UI requirement), `config.py` (new `papers_dir` setting and Filestash integration settings as needed)
- **AI providers**: Reused for summarization and categorization — no new provider code needed
- **User data**: `~/.namingpaper/library.db` (database); papers stay in user's own folder
- **Package metadata**: `pyproject.toml` description, keywords, and optional deps updated
