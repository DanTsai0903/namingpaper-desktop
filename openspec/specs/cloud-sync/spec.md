## ADDED Requirements

### Requirement: iCloud Drive sync container
The system SHALL use an iCloud Drive folder at `~/Library/Mobile Documents/com~apple~CloudDocs/NamingPaper/` as the sync container. The system SHALL create this folder on first sync enable. The sync container SHALL mirror the papers directory structure with PDFs organized by category.

#### Scenario: First-time sync enable
- **WHEN** user enables iCloud sync in settings and the sync container does not exist
- **THEN** system creates the iCloud Drive folder and begins initial sync

#### Scenario: Sync container already exists
- **WHEN** user enables iCloud sync and the sync container already exists (e.g., from another device)
- **THEN** system merges remote content into the local library without duplicating papers

### Requirement: JSON manifest sync format
The system SHALL maintain a `library.json` manifest in the sync container containing all paper metadata keyed by SHA-256 hash. The manifest SHALL include each paper's title, authors, year, journal, summary, keywords, category, filename, and `updatedAt` timestamp. The system SHALL update the manifest whenever the local database changes.

#### Scenario: Local paper added
- **WHEN** a paper is added to the local library while sync is enabled
- **THEN** the PDF is copied to the sync container under its category folder and `library.json` is updated with the paper's metadata

#### Scenario: Local paper deleted
- **WHEN** a paper is removed from the local library while sync is enabled
- **THEN** the PDF is removed from the sync container and `library.json` is updated to remove the entry

#### Scenario: Local paper metadata updated
- **WHEN** a paper's metadata (e.g., category) is changed locally
- **THEN** `library.json` is updated with the new metadata and `updatedAt` timestamp; if category changed, the PDF is moved to the new category folder in the sync container

### Requirement: Sync metadata tracking
The system SHALL maintain a `.sync-meta.json` file in the sync container tracking per-device sync state. Each device SHALL be identified by a stable device identifier. The file SHALL record the last sync timestamp and manifest version for each device.

#### Scenario: Device records sync state
- **WHEN** a sync operation completes on a device
- **THEN** `.sync-meta.json` is updated with the device's identifier and current timestamp

#### Scenario: New device joins sync
- **WHEN** a device enables sync and `.sync-meta.json` exists with entries from other devices
- **THEN** the new device adds its own entry and performs a full import of papers not already in its local library

### Requirement: Inbound sync from remote changes
The system SHALL monitor the sync container for changes using `NSFilePresenter` or `NSFileCoordination`. When `library.json` is modified by another device, the system SHALL merge remote changes into the local library.

#### Scenario: New paper from remote device
- **WHEN** `library.json` contains a paper (by SHA-256) not in the local database
- **THEN** system downloads the PDF from the sync container, copies it to the local papers directory, and inserts the record into the local database

#### Scenario: Paper deleted on remote device
- **WHEN** a paper present locally is removed from `library.json` by another device
- **THEN** system surfaces a conflict dialog: "Paper X was deleted on another device. Remove locally or keep?"

#### Scenario: Metadata updated on remote device
- **WHEN** a paper's metadata in `library.json` has a newer `updatedAt` than the local record
- **THEN** system updates the local record with the remote metadata (last-write-wins)

### Requirement: Conflict resolution
The system SHALL detect conflicts when the same paper is modified on multiple devices between syncs. For metadata-only conflicts, the system SHALL use last-write-wins based on `updatedAt`. For structural conflicts (add vs. delete), the system SHALL prompt the user.

#### Scenario: Metadata conflict resolved by last-write-wins
- **WHEN** a paper's category was changed on both devices since the last sync
- **THEN** the change with the later `updatedAt` timestamp wins and is applied on both devices

#### Scenario: Add-delete conflict prompts user
- **WHEN** one device deleted a paper that another device still has
- **THEN** system shows a dialog with options: "Keep Paper", "Delete Paper", or "Keep Both" (re-add)

### Requirement: Sync status indicator
The system SHALL display a sync status icon in the macOS app toolbar. The status SHALL show one of: synced (up-to-date), syncing (in progress), offline (no iCloud), or error (conflict or failure). The system SHALL also show per-paper sync status in the library browser.

#### Scenario: All papers synced
- **WHEN** the local library matches the sync container manifest
- **THEN** toolbar shows a green checkmark "Synced" status

#### Scenario: Sync in progress
- **WHEN** files are being uploaded or downloaded to/from the sync container
- **THEN** toolbar shows a progress indicator with "Syncing..." status

#### Scenario: Sync error
- **WHEN** a conflict or iCloud error occurs during sync
- **THEN** toolbar shows an orange warning icon; clicking it shows the error details

### Requirement: Sync enable/disable
The system SHALL allow users to enable or disable iCloud sync in Settings. Disabling sync SHALL stop monitoring the sync container but SHALL NOT delete the sync container or its contents. Re-enabling sync SHALL trigger a full reconciliation.

#### Scenario: Disable sync
- **WHEN** user disables iCloud sync in settings
- **THEN** system stops monitoring the sync container; local library continues to work normally

#### Scenario: Re-enable sync
- **WHEN** user re-enables iCloud sync after it was disabled
- **THEN** system performs a full reconciliation between local library and sync container

### Requirement: iCloud sign-out detection
The system SHALL detect when the user signs out of iCloud while sync is enabled. On sign-out, the system SHALL gracefully degrade to local-only mode, preserving all local data intact, and notify the user that sync is paused. When the user signs back in, the system SHALL resume sync automatically.

#### Scenario: User signs out of iCloud
- **WHEN** the user signs out of iCloud while sync is enabled
- **THEN** system pauses sync, preserves all local data, and shows a notification: "iCloud sync paused — sign in to iCloud to resume"

#### Scenario: User signs back into iCloud
- **WHEN** the user signs back into iCloud after a sign-out
- **THEN** system resumes sync and performs a full reconciliation

#### Scenario: App launches without iCloud
- **WHEN** the app launches with sync enabled but iCloud is not available
- **THEN** system operates in local-only mode and shows the sync status as "offline"
