## 1. Database Layer Extensions

- [x] 1.1 Add JSON manifest export method to `DatabaseService` — serialize all paper records to a JSON object keyed by SHA-256 hash
- [x] 1.2 Add incremental export method — return only records with `updatedAt` after a given timestamp
- [x] 1.3 Add JSON manifest import/merge method — for each entry, insert if absent or update if remote `updatedAt` is newer (last-write-wins)
- [x] 1.4 Add change notification emissions (`paperAdded`, `paperUpdated`, `paperDeleted`) to all write operations in `DatabaseService`
- [x] 1.5 Make database location configurable in `ConfigService` (default remains `~/.namingpaper/library.db`)

## 2. Backup — Core

- [x] 2.1 Create `BackupService` actor with manual backup method — copies `library.db` and all PDFs under `papers_dir` to a timestamped `NamingPaper-Backup-YYYY-MM-DD-HHmmss/` directory at a user-chosen destination
- [x] 2.2 Add backup progress tracking — file count and total size reporting via a publisher
- [x] 2.3 Implement backup restoration — replace current `library.db` and restore PDFs from a selected backup directory, with a safety backup of the current state first
- [x] 2.4 Handle restore with missing PDFs — restore what's available and report missing files

## 3. Backup — Scheduling & Settings

- [x] 3.1 Add backup settings to `ConfigService` — destination path, schedule frequency (daily/weekly/monthly), retention count (default: 5)
- [x] 3.2 Implement LaunchAgent plist generation and installation for automatic scheduled backups
- [x] 3.3 Implement retention policy cleanup — delete oldest backup directories when count exceeds the configured retention limit
- [x] 3.4 Implement LaunchAgent removal when automatic backup is disabled

## 4. Backup — UI

- [x] 4.1 Add Backup section to Settings view — destination folder picker, "Back Up Now" button, schedule frequency picker, retention count stepper
- [x] 4.2 Add backup progress sheet with progress bar during manual backup
- [x] 4.3 Add restore UI — backup directory picker, confirmation dialog, progress indicator
- [x] 4.4 Show list of existing backups with dates and sizes in Settings

## 5–9. iCloud Sync — DEFERRED

> **Status:** Code implemented but disabled at runtime. Requires a paid Apple Developer Program membership for iCloud entitlements. Personal development teams do not support iCloud capabilities.
>
> **What's in place:** `SyncService` actor, `SyncStatusView`, `SyncConflictDialog`, `SyncPrefsView` (showing "coming in a future release"), entitlements removed from `NamingPaper.entitlements`, sync initialization removed from `AppDelegate`.
>
> **To re-enable:** (1) Enroll in paid Apple Developer Program, (2) configure `iCloud.com.namingpaper.app` container in developer portal, (3) re-add iCloud entitlements, (4) restore sync initialization in `AppDelegate`, (5) restore full `SyncPrefsView` UI, (6) restore `SyncStatusToolbarItem` in `ContentView`.

## 10. Paper Sharing — Export

- [x] 10.1 Create `SharingService` — builds `.namingpaper` zip bundles containing PDF(s) and `metadata.json`
- [x] 10.2 Add "Export as Bundle" context menu action for single paper — creates `.namingpaper` file and prompts for save location
- [x] 10.3 Add "Export as Bundle" for multiple selected papers — creates a single bundle with all PDFs and combined metadata array
- [x] 10.4 Add "Export Category as Bundle" context menu action on category groups

## 11. Paper Sharing — Import

- [x] 11.1 Implement `.namingpaper` bundle import — extract zip, read `metadata.json`, add each paper through standard add flow with SHA-256 dedup
- [x] 11.2 Register UTType for `.namingpaper` file extension in Info.plist — associate with NamingPaper app
- [x] 11.3 Handle `onOpenURL` / file open events — double-clicking a `.namingpaper` file triggers the import flow
- [x] 11.4 Support drag-and-drop of `.namingpaper` files onto the app window

## 12. Paper Sharing — Share Sheet

- [x] 12.1 Integrate with macOS share sheet (`NSSharingServicePicker`) — create a temporary `.namingpaper` bundle and pass to share destinations (AirDrop, Mail, Messages)
- [x] 12.2 Add Share button to paper detail view and context menu

## 13. Sync-Aware Library Operations

- [x] 13.1 Update file placement logic — when sync is enabled, also copy PDFs to the sync container category folder
- [x] 13.2 Update paper removal — when sync is enabled, also remove from sync container and update manifest
- [x] 13.3 Update library `sync` command — when iCloud sync is enabled, also reconcile with the sync container (offer to import untracked remote papers)
