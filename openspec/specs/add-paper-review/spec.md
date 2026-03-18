## ADDED Requirements

### Requirement: Display AI results per file

After processing completes, the review step SHALL display a results table showing each file with: original filename, AI-suggested name, AI-suggested category, title, authors, and year. Successfully processed files SHALL show editable results. Failed files SHALL show the error message.

#### Scenario: All files processed successfully

- **WHEN** processing completes with all files successful
- **THEN** the review step shows each file with its suggested name and category, all editable

#### Scenario: Some files failed

- **WHEN** processing completes with 2 successful and 1 failed file
- **THEN** the review step shows 2 files with editable results and 1 file with an error message

#### Scenario: All files failed

- **WHEN** processing completes with all files failed
- **THEN** the review step shows error messages for each file and the "Add to Library" button is disabled

### Requirement: Edit suggested name

The review step SHALL allow users to edit the AI-suggested filename for each successfully processed file. The edited name SHALL be used when committing to the library. The text field SHALL default to the AI-suggested name.

#### Scenario: User edits filename

- **WHEN** user changes the suggested name from "Fama and French, (1993, JFE), Common risk factors..." to "Fama-French 1993 Risk Factors.pdf"
- **THEN** the edited name is used when the paper is added to the library

#### Scenario: User keeps suggested name

- **WHEN** user does not edit the suggested name
- **THEN** the AI-suggested name is used when the paper is added to the library

### Requirement: Edit suggested category

The review step SHALL allow users to edit the AI-suggested category for each successfully processed file. The category field SHALL be a combo picker that shows existing categories from the library plus the AI-suggested category. Users SHALL also be able to type a new category name.

#### Scenario: User selects existing category

- **WHEN** user changes the category from AI-suggested "Machine Learning" to existing category "Finance"
- **THEN** the paper is added to the "Finance" category

#### Scenario: User types new category

- **WHEN** user types "Behavioral Economics" as the category (not in existing list)
- **THEN** the paper is added to a new "Behavioral Economics" category

#### Scenario: Category priority pre-selects existing match

- **WHEN** "Prioritize existing categories" was enabled in the configure step and the AI suggested "Asset Pricing" and an existing category "Asset Pricing" exists
- **THEN** the category field pre-selects the existing "Asset Pricing" category

### Requirement: Confirm and add to library

The review step SHALL have an "Add to Library" button. Pressing it SHALL execute the CLI `add` command with `--execute` for each successful file, using the user's edited name and category. The button SHALL be disabled while no successfully processed files exist.

#### Scenario: Confirm adds papers

- **WHEN** user clicks "Add to Library" with 3 reviewed papers
- **THEN** the CLI runs `namingpaper add --execute --yes --copy --category <edited> --filename <edited>` for each file and the papers are added to the library

#### Scenario: Progress during commit

- **WHEN** user clicks "Add to Library"
- **THEN** each file shows a progress indicator while being committed, transitioning to a checkmark on success

#### Scenario: Commit failure

- **WHEN** the execute step fails for a file
- **THEN** the file shows an error message and other files continue processing

### Requirement: Cancel from review

The review step SHALL have a "Cancel" button that dismisses the sheet without committing any papers to the library. Files are not added, moved, or modified.

#### Scenario: Cancel discards all results

- **WHEN** user clicks "Cancel" in the review step
- **THEN** the sheet is dismissed and no papers are added to the library
