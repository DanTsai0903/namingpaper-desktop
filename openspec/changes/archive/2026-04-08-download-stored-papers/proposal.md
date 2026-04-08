## Why

Users who have built a paper library in NamingPaper need a way to export papers to a specific folder — for offline reading, sharing with collaborators who don't use NamingPaper, or moving papers to a different device/application.

## What Changes

- Add a CLI `namingpaper download` command that copies papers from the library to a user-specified output directory
- Support downloading by paper ID, search query, category filter, or all papers
- Preserve category folder structure in the output directory (optional flat mode)
- Add download actions in the macOS desktop app (toolbar and context menu)

## Capabilities

### New Capabilities
- `paper-download`: Export/download library papers as plain PDF files to a user-specified directory

### Modified Capabilities
- `library-cli`: Add `download` subcommand to the existing CLI command set

## Impact

- **Code**: New `download.py` module, new CLI command, SwiftUI download flow in macOS app
- **Dependencies**: None new
- **Existing behavior**: No changes to existing commands or UI flows
