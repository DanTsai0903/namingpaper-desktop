## Why

NamingPaper stores all data locally — the SQLite database at `~/.namingpaper/library.db` and PDF files under `~/Papers/`. There is no backup mechanism, no way to sync a library across multiple Macs, and no way to share papers with collaborators. A single disk failure or accidental deletion means losing the entire curated library. Cloud storage support addresses all three gaps: automated backup, multi-device sync, and paper sharing.

## What Changes

- Add iCloud Drive integration for syncing the paper library (database + PDF files) across devices
- Add manual and automatic backup to a user-chosen cloud folder (iCloud Drive, Dropbox, Google Drive — any folder-based cloud service)
- Add paper sharing via shareable links or export bundles (metadata + PDF)
- Add a sync status indicator in the macOS app UI
- Add conflict resolution when the same library is modified on multiple devices
- **BREAKING**: Library location may move from `~/.namingpaper/` to an iCloud-accessible container for users who opt in to sync

## Capabilities

### New Capabilities
- `cloud-sync`: iCloud Drive integration for syncing the SQLite database and PDF files across devices, including conflict detection and resolution
- `cloud-backup`: Automated and manual backup of the library to any folder-based cloud storage provider, with scheduling and retention policies
- `paper-sharing`: Export and share individual papers or collections as bundles (metadata + PDF), with optional shareable links

### Modified Capabilities
- `paper-database`: Storage location becomes configurable to support iCloud containers; database must handle merge conflicts from concurrent multi-device writes
- `paper-library`: Library operations must be sync-aware — additions, deletions, and moves need to propagate to the sync layer

## Impact

- **macOS app**: New sync settings UI, status indicators, conflict resolution dialogs; must handle iCloud container entitlements
- **Database layer**: `DatabaseService` needs conflict-aware merge logic; WAL mode helps but concurrent cross-device writes require additional safeguards
- **File operations**: `renamer.py` and file management must coordinate with cloud sync to avoid partial uploads or conflicts
- **Dependencies**: May require CloudKit framework or NSFileCoordination APIs for iCloud; no new Python dependencies expected
- **Entitlements**: App will need iCloud entitlements (`com.apple.developer.icloud-container-identifiers`) if using native iCloud APIs
- **CLI**: Minimal impact — CLI continues to operate on local files; sync is a macOS app concern
