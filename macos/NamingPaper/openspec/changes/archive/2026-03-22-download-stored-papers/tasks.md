## 1. Core Download Logic

- [x] 1.1 Create src/namingpaper/download.py with download_papers() function
- [x] 1.2 Implement category folder structure preservation
- [x] 1.3 Implement flat mode with filename collision resolution
- [x] 1.4 Implement collision handling: skip or overwrite
- [x] 1.5 Implement missing source file handling
- [x] 1.6 Return a DownloadSummary dataclass

## 2. CLI Command

- [x] 2.1 Add download command to cli.py with all options
- [x] 2.2 Implement paper selection logic
- [x] 2.3 Implement dry-run output
- [x] 2.4 Implement execute mode with summary display
- [x] 2.5 Validate selection method provided

## 3. macOS App Integration

- [x] 3.1 Add Download to Folder toolbar button in paper detail view
- [x] 3.2 Implement folder picker dialog (NSOpenPanel)
- [x] 3.3 Add context menu with Download, Reveal, Share, Move to Category, Remove
- [x] 3.4 Enable multi-selection in paper table
- [x] 3.5 Show summary alert after download, error alert on failure

## 4. Tests

- [x] 4.1 Write unit tests for download_papers()
- [x] 4.2 Write unit tests for flat mode collision resolution
- [x] 4.3 Write CLI integration tests for dry-run and execute
- [x] 4.4 Write CLI integration test for no-selection error
