## MODIFIED Requirements

### Requirement: Existing commands unchanged
All existing commands (`rename`, `batch`, `templates`, `version`, `update`, `uninstall`, `config`, `add`, `search`, `list`, `info`, `remove`, `sync`) SHALL continue to work with identical behavior. The new `download` command SHALL be added without modifying any existing command interfaces. No backward-incompatible changes to existing CLI interfaces.

#### Scenario: Rename command unaffected
- **WHEN** user runs `namingpaper rename paper.pdf --execute`
- **THEN** behavior is identical to pre-download version

#### Scenario: Batch command unaffected
- **WHEN** user runs `namingpaper batch ~/papers --execute`
- **THEN** behavior is identical to pre-download version

## ADDED Requirements

### Requirement: Download command
The system SHALL provide a `namingpaper download` command that copies papers from the library to a specified output directory. The command SHALL follow the existing safety model: dry-run by default, `--execute` required to actually copy files. Options: `--execute`/`-x`, `--output`/`-o` (required, output directory path), `--query`/`-q` (search query), `--category`/`-c` (category filter), `--all` (download all papers), `--flat` (no category subfolders), `--overwrite` (replace existing files), `--limit N` (max papers to download).

#### Scenario: Download dry-run
- **WHEN** user runs `namingpaper download --query "risk factors" -o ~/Desktop/papers`
- **THEN** system displays the list of papers that would be copied and their target paths, without copying any files

#### Scenario: Download with execute
- **WHEN** user runs `namingpaper download --query "risk factors" -o ~/Desktop/papers --execute`
- **THEN** system copies matching papers to `~/Desktop/papers/<category>/` and displays a summary

#### Scenario: Download by category
- **WHEN** user runs `namingpaper download --category "Finance" -o ~/export --execute`
- **THEN** system copies all Finance papers to `~/export/Finance/`

#### Scenario: Download all papers flat
- **WHEN** user runs `namingpaper download --all --flat -o ~/all-papers --execute`
- **THEN** system copies all papers to `~/all-papers/` without category subfolders

#### Scenario: Download specific papers by ID
- **WHEN** user runs `namingpaper download a3f2 b4e1 -o ~/Desktop --execute`
- **THEN** system copies those two papers to the output directory

#### Scenario: No selection provided
- **WHEN** user runs `namingpaper download -o ~/Desktop` without any ID, query, category, or --all flag
- **THEN** system displays an error: "Specify paper IDs, --query, --category, or --all"
