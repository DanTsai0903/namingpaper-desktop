## ADDED Requirements

### Requirement: Category discovery from filesystem
The system SHALL discover existing categories by scanning subdirectories under `papers_dir`. Nested subdirectories SHALL be represented as path-style category strings (e.g., "Finance/Asset Pricing"). The `Unsorted` directory SHALL be excluded from the category list.

#### Scenario: Discover categories from existing folders
- **WHEN** `papers_dir` contains `Finance/Asset Pricing/`, `Finance/Empirical/`, and `Machine Learning/NLP/`
- **THEN** system returns categories ["Finance/Asset Pricing", "Finance/Empirical", "Machine Learning/NLP"]

#### Scenario: Empty papers directory
- **WHEN** `papers_dir` has no subdirectories (or only `Unsorted/`)
- **THEN** system returns an empty category list

### Requirement: AI category suggestion
The system SHALL use the AI provider to suggest the best matching category for a paper based on its summary, keywords, and the list of existing categories. The AI SHALL return a single suggested category from the existing list, or propose a new category path if none fit well.

#### Scenario: AI suggests existing category
- **WHEN** a paper about asset pricing is categorized and "Finance/Asset Pricing" exists
- **THEN** AI suggests "Finance/Asset Pricing"

#### Scenario: AI suggests new category
- **WHEN** a paper's topic does not match any existing category
- **THEN** AI proposes a new category path (e.g., "Biology/Genomics")

### Requirement: Interactive category confirmation
The system SHALL present the user with a numbered list of options: the AI suggestion (marked), existing categories, "[Create new category]", and "[Skip — leave in Unsorted/]". The user SHALL select by number or press Enter to accept the AI suggestion. In `--yes` mode, the AI suggestion is auto-accepted without prompting.

#### Scenario: User accepts AI suggestion
- **WHEN** the category prompt is shown and user presses Enter
- **THEN** the AI-suggested category is used

#### Scenario: User selects different category
- **WHEN** the category prompt is shown and user enters a different number
- **THEN** the selected category is used

#### Scenario: User creates new category
- **WHEN** user selects "[Create new category]"
- **THEN** system prompts for the category path and uses it

#### Scenario: User skips categorization
- **WHEN** user selects "[Skip — leave in Unsorted/]"
- **THEN** the paper is placed in `papers_dir/Unsorted/`

#### Scenario: Auto-accept in yes mode
- **WHEN** `--yes` flag is passed
- **THEN** the AI suggestion is used without prompting

### Requirement: Category stored in database
The system SHALL store the confirmed category path string in the paper's database record. The category SHALL be the relative path from `papers_dir` to the paper's parent directory (e.g., "Finance/Asset Pricing").

#### Scenario: Category persisted after add
- **WHEN** user confirms category "Finance/Asset Pricing" during add
- **THEN** the paper record's `category` field is set to "Finance/Asset Pricing"
