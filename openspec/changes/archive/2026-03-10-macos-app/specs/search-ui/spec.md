## ADDED Requirements

### Requirement: Live FTS5 search in sidebar

The sidebar SHALL have a "Search" panel activated by `Cmd+F` or clicking the search icon. The panel SHALL contain a text input field. As the user types, the app SHALL query the FTS5 index and display matching papers in the paper list column. Results SHALL update live with each keystroke (debounced to 150ms).

#### Scenario: Live search as user types

- **WHEN** user types "neural network" in the search field
- **THEN** papers matching "neural network" via FTS5 appear in the paper list within 150ms of the last keystroke

#### Scenario: Activate search panel

- **WHEN** user presses `Cmd+F`
- **THEN** the sidebar switches to the Search panel with the text field focused

#### Scenario: Clear search

- **WHEN** user clears the search field (or presses Esc)
- **THEN** the paper list returns to the previous view (category filter or all papers)

### Requirement: Filter chips

Below the search field, the app SHALL display filter chips for: author, year range, journal, and category. Tapping a chip SHALL present a popover or dropdown to set the filter value. Active filters SHALL be visually distinguished (filled chip). Multiple filters SHALL combine with AND logic.

#### Scenario: Add author filter

- **WHEN** user taps the "Author" chip and types "Fama"
- **THEN** results are filtered to papers where author contains "Fama", combined with the text query

#### Scenario: Add year range filter

- **WHEN** user taps "Year" chip and sets range 2010-2020
- **THEN** only papers from 2010 to 2020 are shown

#### Scenario: Remove a filter

- **WHEN** user taps the "x" on an active filter chip
- **THEN** that filter is removed and results update

### Requirement: Result highlighting

When FTS5 search results are displayed in the paper list, the matching terms SHALL be highlighted (bold or color) in the title and author columns.

#### Scenario: Highlighted match terms

- **WHEN** user searches "risk factors"
- **THEN** the words "risk" and "factors" are visually highlighted in matching paper titles

### Requirement: Search history

The search panel SHALL remember the last 10 search queries. When the search field is focused and empty, previous queries SHALL appear as suggestions below the field. Tapping a suggestion SHALL populate the search field and execute the search.

#### Scenario: Show search history

- **WHEN** user focuses the search field with no text
- **THEN** the last 10 search queries appear as clickable suggestions

#### Scenario: Use search history entry

- **WHEN** user clicks a previous query in the history list
- **THEN** the search field populates with that query and results update
