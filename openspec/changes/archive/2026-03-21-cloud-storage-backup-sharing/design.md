## Context

NamingPaper stores papers locally: SQLite database at `~/.namingpaper/library.db` (WAL mode, actor-isolated `DatabaseService`) and PDF files under `~/Papers/`. The macOS app has sandboxing disabled, uses FSEvents-based `DirectoryMonitor` for file change detection, and stores config in `~/.namingpaper/config.toml`. There is currently no cloud integration, backup mechanism, or sharing capability.

The app's `Paper` model uses SHA-256 content hashes for dedup and tracks `createdAt`/`updatedAt` timestamps — both useful primitives for sync conflict detection.

## Goals / Non-Goals

**Goals:**
- Let users back up their entire library (DB + PDFs) to any folder-based cloud storage
- Sync a library across multiple Macs via iCloud Drive
- Share individual papers or collections as portable bundles
- Handle conflicts gracefully when the same library is edited on multiple devices
- Preserve the existing local-only workflow for users who don't opt in

**Non-Goals:**
- Real-time collaborative editing (Google Docs-style)
- CloudKit record-level sync (too complex; iCloud Drive file-level sync is sufficient)
- Server-side infrastructure or account system
- Syncing the CLI tool's config or provider settings
- Cross-platform sync (Windows/Linux) — macOS only for now
- Streaming or partial PDF sync — entire files sync atomically

## Decisions

### 1. iCloud Drive file-level sync over CloudKit

**Choice:** Use iCloud Drive (via `NSFileCoordination` / `NSFilePresenter`) to sync the library folder, rather than CloudKit record-based sync.

**Why:** CloudKit would require modeling every paper as a CKRecord, managing a custom sync engine, and handling CloudKit's 1MB asset limits per record. iCloud Drive treats our library as a folder of files — the OS handles upload/download, and we only need to handle conflicts at the file level. This also means users see their library in Finder.

**Alternatives considered:**
- CloudKit records: More granular control but massive implementation complexity; 1MB record limit forces chunking PDFs
- Third-party sync (Dropbox SDK, Google Drive API): Vendor lock-in, requires API keys, ongoing maintenance
- Custom sync server: Requires infrastructure, auth system — way out of scope

### 2. Separate sync database from local database

**Choice:** Keep the local `~/.namingpaper/library.db` as the working database. Sync a separate export in the iCloud Drive container. On each device, import changes from the synced copy into the local DB.

**Why:** SQLite does not support concurrent writes from multiple processes on different machines via a shared file — WAL mode helps with local concurrency but iCloud Drive can't guarantee write ordering across devices. A shared SQLite file over iCloud Drive would corrupt. Instead, we export a JSON manifest (`library.json`) alongside the PDFs into iCloud Drive, and each device merges from that manifest.

**Alternatives considered:**
- Direct SQLite file sync: High corruption risk with concurrent writes across devices
- CRDT-based database (e.g., cr-sqlite): Promising but adds a complex dependency; can revisit later
- SQLite replication (Litestream): Designed for server backup, not peer-to-peer device sync

### 3. JSON manifest as the sync format

**Choice:** The synced folder contains PDFs organized by category and a `library.json` manifest with all paper metadata, keyed by SHA-256 hash.

**Structure:**
```
~/Library/Mobile Documents/com~apple~CloudDocs/NamingPaper/
├── library.json          # metadata manifest
├── Unsorted/
│   └── paper1.pdf
├── Finance/
│   └── paper2.pdf
└── .sync-meta.json       # last sync timestamps per device
```

**Why:** JSON is human-readable, diffable, and trivially mergeable compared to SQLite binary blobs. SHA-256 keys make dedup and conflict detection straightforward. The `.sync-meta.json` tracks per-device sync state to enable incremental updates.

**Alternatives considered:**
- SQLite export/import: Binary format complicates conflict resolution
- Individual JSON files per paper: Too many small files, iCloud Drive performs poorly with thousands of tiny files

### 4. Last-write-wins with conflict surfacing

**Choice:** For metadata conflicts (same paper edited on two devices), use last-write-wins based on `updatedAt` timestamps. For structural conflicts (paper added on one device, deleted on another), surface a conflict to the user.

**Why:** Metadata conflicts (e.g., category change) are low-stakes and rare — last-write-wins is pragmatic. Structural conflicts (add vs. delete) need user input because data loss is at stake. This avoids the complexity of a full CRDT while handling the important cases.

### 5. Backup as folder snapshot

**Choice:** Backup is a timestamped copy of the library folder to a user-chosen destination, independent of iCloud sync.

**Why:** Backup and sync are different concerns. Users may want backup without sync (single device, external drive). A simple folder copy with a timestamp (`NamingPaper-Backup-2026-03-21/`) is reliable, understandable, and works with any cloud folder (Dropbox, Google Drive, OneDrive).

**Scheduling:** Use macOS `LaunchAgent` plist for automatic backups (daily/weekly). Manual backup via a button in Settings.

### 6. Paper sharing via export bundles

**Choice:** Export a `.namingpaper` bundle (zip archive) containing the PDF and a `metadata.json` file. Import reconstructs the paper in the recipient's library.

**Why:** Self-contained, no server needed, works via email/AirDrop/any file transfer. The `.namingpaper` extension lets macOS associate it with the app for double-click import.

**Alternatives considered:**
- Shareable links (presigned URLs): Requires a server or cloud API — out of scope for v1
- Plain PDF copy: Loses metadata

## Risks / Trade-offs

**[iCloud Drive latency]** → Files may take seconds to minutes to sync. Mitigation: Show sync status indicators (uploading/downloading/up-to-date) and never block the UI on sync completion.

**[Conflict resolution UX]** → Users may not understand merge conflicts. Mitigation: Default to last-write-wins for metadata; only surface conflicts for add-vs-delete cases with a clear "Keep Both / Keep Local / Keep Remote" dialog.

**[Large libraries]** → Libraries with thousands of PDFs (GBs of data) may strain iCloud Drive. Mitigation: Sync metadata eagerly, PDFs lazily (download on demand). Show storage usage in settings.

**[Clock skew]** → `updatedAt` timestamps may drift across devices. Mitigation: Use ISO 8601 with timezone; accept that small skew is tolerable for last-write-wins on low-stakes metadata.

**[First sync]** → Initial sync of an existing library could be slow and bandwidth-heavy. Mitigation: Show progress, allow background sync, let users choose which categories to sync.

**[Entitlements]** → iCloud Drive access requires the `com.apple.developer.icloud-container-identifiers` entitlement and an iCloud container configured in the developer portal. Mitigation: Plan for this during the build/signing process; test with a development iCloud container first.

## Migration Plan

1. **Phase 1 — Backup:** Shipped. Folder-based backup with manual/scheduled options and restore.
2. **Phase 2 — iCloud Sync:** Code implemented but **deferred** — requires paid Apple Developer Program ($99/year) for iCloud entitlements. Personal development teams do not support iCloud capabilities. UI shows "coming in a future release."
3. **Phase 3 — Sharing:** Shipped. `.namingpaper` export bundles with UTType registration, import, drag-and-drop, and share sheet.

**Rollback:** Each phase is independent. Disabling sync reverts to local-only mode — the local database is always authoritative. Backup snapshots provide recovery points.

## Resolved Questions

- **Selective sync (by category)?** No — sync is all-or-nothing. Keeps the implementation simple and avoids partial-state bugs.
- **Maximum library size?** No artificial limit — support as large a library as possible. Use lazy PDF download and incremental manifest updates to handle large collections.
- **CLI backup support?** No — backup and sync are macOS-app-only features.
- **iCloud sign-out handling?** Yes — the app must detect iCloud sign-out and gracefully degrade to local-only mode, preserving all local data and notifying the user that sync is paused.
