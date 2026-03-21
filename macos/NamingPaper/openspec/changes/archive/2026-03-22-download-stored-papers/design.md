## Context

NamingPaper stores papers in a SQLite database with PDFs organized under `papers_dir/<category>/`. Users need a way to copy papers as plain PDFs to an arbitrary output directory.

## Goals / Non-Goals

**Goals:**
- Download/export library papers as plain PDF files to any directory
- Support flexible selection: by ID, search query, category, or all papers
- Optionally preserve category folder structure
- Provide both CLI and macOS app interfaces

**Non-Goals:**
- Converting PDFs to other formats
- Including metadata files in the output
- Syncing the output directory
- Downloading papers from the internet

## Decisions

1. **Copy-based approach** — never move or symlink
2. **Reuse existing database query infrastructure**
3. **Category folder structure preserved by default**, `--flat` for flat output
4. **New top-level CLI command** `namingpaper download`
5. **Skip collisions by default**, `--overwrite` to replace

## Risks / Trade-offs

- Large libraries → `--limit` to cap output
- Missing files → skip and suggest `namingpaper sync`
- Flat mode filename collisions → append paper ID suffix
