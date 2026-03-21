## ADDED Requirements

### Requirement: Manual backup to folder
The system SHALL allow users to create a backup of the entire library (database + PDFs) to a user-chosen folder. The backup SHALL be a timestamped directory named `NamingPaper-Backup-YYYY-MM-DD-HHmmss/` containing a copy of the SQLite database and all PDF files preserving the category folder structure.

#### Scenario: Manual backup from settings
- **WHEN** user clicks "Back Up Now" in settings and selects a destination folder
- **THEN** system creates a timestamped backup directory containing a copy of `library.db` and all PDF files under `papers_dir`

#### Scenario: Backup to cloud-synced folder
- **WHEN** user selects a Dropbox, Google Drive, or iCloud Drive folder as the backup destination
- **THEN** system creates the backup in that folder; the cloud service handles upload

#### Scenario: Backup progress indication
- **WHEN** a backup is in progress
- **THEN** system shows a progress bar with file count and total size

### Requirement: Automatic scheduled backup
The system SHALL support automatic backup on a user-configured schedule (daily, weekly, or monthly). The schedule SHALL be implemented via a macOS `LaunchAgent` plist. The system SHALL retain backups according to a configurable retention count (default: 5).

#### Scenario: Configure daily automatic backup
- **WHEN** user enables automatic backup with daily frequency and selects a destination
- **THEN** system installs a LaunchAgent that triggers a backup daily at the configured time

#### Scenario: Retention policy cleanup
- **WHEN** an automatic backup completes and the number of backups exceeds the retention count
- **THEN** the oldest backup directories are deleted until the count matches the retention setting

#### Scenario: Disable automatic backup
- **WHEN** user disables automatic backup in settings
- **THEN** system removes the LaunchAgent; existing backups are not deleted

### Requirement: Backup restoration
The system SHALL allow users to restore a library from a backup. Restoration SHALL replace the current database and optionally restore PDF files to `papers_dir`. The system SHALL create a backup of the current state before restoring.

#### Scenario: Restore from backup
- **WHEN** user selects a backup directory and clicks "Restore"
- **THEN** system backs up the current library, then replaces `library.db` with the backup copy and restores PDF files to `papers_dir`

#### Scenario: Safety backup before restore
- **WHEN** user initiates a restore
- **THEN** system creates a pre-restore backup of the current state before overwriting

#### Scenario: Restore with missing PDFs
- **WHEN** a backup contains database records but some PDF files are missing from the backup
- **THEN** system restores available files and reports which papers have missing PDFs

### Requirement: Backup settings persistence
The system SHALL persist backup settings (destination path, schedule frequency, retention count) in the app's configuration. These settings SHALL survive app restarts.

#### Scenario: Settings persist across restart
- **WHEN** user configures backup destination and schedule, then quits and reopens the app
- **THEN** backup settings are preserved and automatic backups continue on schedule
