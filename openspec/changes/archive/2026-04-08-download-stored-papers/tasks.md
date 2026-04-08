## 1. Core Download Logic

- [x] 1.1 Create `src/namingpaper/download.py` with a `download_papers()` function that takes a list of Paper objects, output directory, flat flag, and overwrite flag, and copies PDFs to the target paths
- [x] 1.2 Implement category folder structure preservation (create `<output>/<category>/<filename>.pdf`)
- [x] 1.3 Implement flat mode (all PDFs in output root, append paper ID on filename collision)
- [x] 1.4 Implement collision handling: skip existing files by default, overwrite when flag is set
- [x] 1.5 Implement missing source file handling: skip and warn, suggest `namingpaper sync`
- [x] 1.6 Return a download summary dataclass (total, copied, skipped, failed)

## 2. CLI Command

- [x] 2.1 Add `download` command to `cli.py` with options: `--output`/`-o`, `--query`/`-q`, `--category`/`-c`, `--all`, `--flat`, `--overwrite`, `--limit`, `--execute`/`-x`, and positional paper IDs
- [x] 2.2 Implement paper selection logic: resolve IDs via `Database.get_paper()`, query via `Database.search()`, category via `Database.list_papers()`, or all via `Database.list_papers()` with no filter
- [x] 2.3 Implement dry-run output showing papers and target paths
- [x] 2.4 Implement execute mode that calls `download_papers()` and displays the summary
- [x] 2.5 Validate that at least one selection method is provided (IDs, --query, --category, or --all)

## 3. macOS App Integration

- [x] 3.1 Add "Download to Folder" toolbar button in paper detail view
- [x] 3.2 Implement folder picker dialog (NSOpenPanel) for selecting the output directory
- [x] 3.3 Add context menu with Download, Reveal, Share, Move to Category, Remove for selected papers
- [x] 3.4 Enable multi-selection in paper table (Set<String> selection)
- [x] 3.5 Show summary alert after download completes, show error alert on failure

## 4. Tests

- [x] 4.1 Write unit tests for `download_papers()`: structured output, flat output, collision skip, collision overwrite, missing source file
- [x] 4.2 Write unit tests for flat mode filename collision resolution (ID suffix)
- [x] 4.3 Write CLI integration tests for dry-run and execute modes
- [x] 4.4 Write CLI integration test for "no selection provided" error case
