## Why

Users who have built a paper library in NamingPaper need a way to export papers to a specific folder.

## What Changes

- Add a CLI `namingpaper download` command
- Support downloading by paper ID, search query, category filter, or all papers
- Preserve category folder structure (optional flat mode)
- Add download actions in the macOS desktop app

## Capabilities

### New Capabilities
- `paper-download`: Export/download library papers as plain PDF files

### Modified Capabilities
- `library-cli`: Add `download` subcommand

## Impact

- **Code**: New `download.py` module, new CLI command, SwiftUI download actions
- **Dependencies**: None new
- **Existing behavior**: No changes to existing commands or UI flows
