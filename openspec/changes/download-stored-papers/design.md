## Context

NamingPaper stores papers in a SQLite database (`~/.namingpaper/library.db`) with PDFs organized under `papers_dir/<category>/`. Users can export papers as `.namingpaper` bundles (zip with metadata), but there's no way to simply copy papers as plain PDFs to an arbitrary output directory. This is needed for offline reading, sharing with non-NamingPaper users, or transferring to other applications.

The CLI already has `add`, `search`, `list`, `remove`, and `sync` commands. The macOS app has a library browser with category sidebar and paper list.

## Goals / Non-Goals

**Goals:**
- Allow users to download/export library papers as plain PDF files to any directory
- Support flexible selection: by ID, search query, category, or all papers
- Optionally preserve category folder structure in the output
- Provide both CLI and macOS app interfaces

**Non-Goals:**
- Converting PDFs to other formats (ePub, HTML, etc.)
- Including metadata files in the output (that's what `.namingpaper` bundles are for)
- Syncing the output directory (one-way copy only)
- Downloading papers from the internet (URLs, DOIs, etc.)

## Decisions

### 1. Copy-based approach (not move or symlink)
Papers are always **copied** to the output directory, never moved. The library remains intact.
- **Why**: Moving would break the library database. Symlinks would break if the library moves. Copy is the safest and most portable approach.

### 2. Reuse existing database query infrastructure
The `download` command uses `Database.get_paper()`, `Database.search()`, and `Database.list_papers()` to select papers, then copies their `file_path` to the output directory.
- **Why**: No new query logic needed. The existing search/filter capabilities are already powerful enough.

### 3. Category folder structure preserved by default
Output directory mirrors `<category>/<filename>.pdf` structure by default. A `--flat` flag puts all PDFs in the root of the output directory.
- **Why**: Users organizing papers by category likely want that structure preserved. Flat mode covers the "dump everything" use case.

### 4. CLI command: `namingpaper download`
New top-level command, not a subcommand of `list` or `search`.
- **Why**: Download is a distinct action. Follows the same pattern as other top-level commands (`add`, `remove`, `sync`).

### 5. Collision handling: skip by default
If a file already exists in the output directory, skip it and report. `--overwrite` flag to replace.
- **Why**: Consistent with the project's safety-first philosophy (dry-run by default, `--execute` for mutations). Prevents accidental data loss.

## Risks / Trade-offs

- **Large libraries**: Copying hundreds of PDFs could take time and disk space → Mitigation: Show progress with paper count and total size estimate before starting. Respect `--limit` to cap output.
- **Missing files**: A paper's `file_path` may point to a file that no longer exists → Mitigation: Skip missing files, report them as warnings, suggest running `namingpaper sync`.
- **Filename collisions in flat mode**: Two papers in different categories could have the same filename → Mitigation: Append paper ID suffix when collision detected in flat mode.
