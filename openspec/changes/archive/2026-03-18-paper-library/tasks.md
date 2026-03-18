## 1. Database Layer

- [x] 1.1 Create `src/namingpaper/database.py` with SQLite connection manager (WAL mode, `~/.namingpaper/library.db` path, auto-create directory)
- [x] 1.2 Implement schema versioning table and migration runner (forward-only, backup before destructive steps)
- [x] 1.3 Define initial schema migration: `papers` table with all columns (id, sha256, title, authors, authors_full, year, journal, journal_abbrev, summary, keywords, category, file_path, confidence, created_at, updated_at)
- [x] 1.4 Create FTS5 virtual table indexing title, authors, journal, summary, keywords — kept in sync via triggers or transactional writes
- [x] 1.5 Implement CRUD operations: create_paper, get_paper, update_paper, delete_paper (all transactional, delete removes FTS entry)
- [x] 1.6 Implement duplicate detection: lookup by SHA-256 hash before insert
- [x] 1.7 Implement FTS5 keyword search function returning ranked results
- [x] 1.8 Implement filtered queries (author, year/year-range, journal, category) combinable with FTS search
- [x] 1.9 Write tests for database layer (init, migrations, CRUD, dedup, FTS search, filtered queries)

## 2. Models and Config

- [x] 2.1 Add `Paper` model to `models.py` with all database fields (id, sha256, title, authors, authors_full, year, journal, journal_abbrev, summary, keywords, category, file_path, confidence, created_at, updated_at)
- [x] 2.2 Add `SearchFilter` model to `models.py` (author, year_from, year_to, journal, category, smart flag)
- [x] 2.3 Add `papers_dir` setting to `config.py` (default: `~/Papers`, env var: `NAMINGPAPER_PAPERS_DIR`)
- [x] 2.4 Write tests for new models and config settings

## 3. AI Summary and Keywords

- [x] 3.1 Create `src/namingpaper/summarizer.py` with summarization prompt that returns JSON with `summary` (2-4 sentences) and `keywords` (3-8 terms) fields
- [x] 3.2 Implement `summarize_paper` async function using existing `AIProvider` interface — accepts `PDFContent` and returns summary + keywords
- [x] 3.3 Add `_parse_summary_json` helper to parse AI response (handle markdown code blocks, partial results)
- [x] 3.4 Write tests for summarizer (mock AI responses, partial results, error handling)

## 4. Auto-Categorization

- [x] 4.1 Create `src/namingpaper/categorizer.py` with `discover_categories` function that scans `papers_dir` subdirectories (exclude `Unsorted/`)
- [x] 4.2 Implement `suggest_category` async function — sends summary, keywords, and existing category list to AI provider, returns suggested category
- [x] 4.3 Implement `prompt_category_selection` function — Rich-formatted interactive prompt with numbered options (AI suggestion marked, existing categories, create new, skip to Unsorted)
- [x] 4.4 Handle `--yes` mode: auto-accept AI suggestion without prompting
- [x] 4.5 Write tests for categorizer (discovery, suggestion parsing, skip/create-new paths)

## 5. Library Orchestration

- [x] 5.1 Create `src/namingpaper/library.py` with `add_paper` async function orchestrating: extract metadata → rename → summarize → categorize → file placement → DB persist
- [x] 5.2 Implement file placement logic: move (default) or copy (`--copy`) into `papers_dir/<category>/`, create folder if needed
- [x] 5.3 Implement SHA-256 hash computation and early dedup check before processing
- [x] 5.4 Implement `import_directory` function: iterate PDFs in a directory, call `add_paper` for each, collect results, report summary (added/skipped/errors)
- [x] 5.5 Implement `sync_library` function: scan `papers_dir` for untracked files, check DB for missing files, report discrepancies
- [x] 5.6 Implement `remove_paper` function: delete DB record, optionally delete file from disk
- [x] 5.7 Implement `search_library` function: FTS keyword search with filters, return list of Paper records
- [x] 5.8 Implement smart search mode: send query + paper summaries to AI for semantic ranking (auto-trigger on 6+ word queries or `--smart` flag)
- [x] 5.9 Write tests for library orchestration (mock provider and database, test full workflow, dedup, sync, remove)

## 6. CLI Commands

- [x] 6.1 Add `add` command to `cli.py` with options: path, --execute/-x, --yes/-y, --copy, --recursive/-r, --parallel N, --provider/-p, --model/-m, --ocr-model, --template/-t
- [x] 6.2 Add `search` command with options: query, --author, --year, --journal, --category, --smart
- [x] 6.3 Add `list` command with options: --category, --sort, --limit
- [x] 6.4 Add `info` command accepting paper ID, displaying full metadata with Rich formatting
- [x] 6.5 Add `remove` command with options: id, --delete-file, --execute/-x, --yes/-y
- [x] 6.6 Add `sync` command with options: --execute/-x, --yes/-y
- [x] 6.7 Implement dry-run output for `add` command: show planned rename, summary, keywords, category, target path
- [x] 6.8 Write CLI integration tests (dry-run add, search, list, info, remove, sync)

## 7. Integration and Documentation

- [x] 7.1 Verify existing `rename` and `batch` commands are unaffected (run existing test suite)
- [x] 7.2 Add Filestash setup documentation section to README
- [x] 7.3 Update pyproject.toml description and keywords for library capabilities
- [x] 7.4 End-to-end test: add a PDF, search for it, list it, get info, remove it
