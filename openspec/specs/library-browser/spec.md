# Capability: library-browser

## Purpose

Provides the paper list table, category tree sidebar, recent papers panel, starred papers, and empty state onboarding for browsing the library.

## Requirements

### Requirement: Paper list table with sortable columns

The center column SHALL display papers in a `Table` view with columns: title, authors, year, and journal. Each column SHALL be sortable by clicking the column header. The default sort SHALL be by title ascending. The table SHALL support single-row selection. Selecting a row SHALL update the detail pane.

#### Scenario: Sort by year

- **WHEN** user clicks the "Year" column header
- **THEN** papers sort by year descending; clicking again sorts ascending

#### Scenario: Select a paper

- **WHEN** user clicks a row in the paper list
- **THEN** that paper's detail appears in the right pane

### Requirement: Category tree sidebar panel

The sidebar SHALL have a "Categories" panel as the default view. It SHALL display a tree of categories derived from the database (distinct `category` values). Clicking a category SHALL filter the paper list to show only papers in that category. An "All Papers" item at the top SHALL clear the filter.

#### Scenario: Filter by category

- **WHEN** user clicks "Machine Learning" in the category tree
- **THEN** the paper list shows only papers with category "Machine Learning"

#### Scenario: Show all papers

- **WHEN** user clicks "All Papers" at the top of the category tree
- **THEN** the paper list shows all papers without category filtering

#### Scenario: Category counts

- **WHEN** the category tree is displayed
- **THEN** each category shows a count badge with the number of papers in that category

### Requirement: Recent papers sidebar panel

The sidebar SHALL have a "Recent" panel showing the last 20 papers opened or added, sorted by most recent first. Clicking a paper in the recent list SHALL select it in the paper list and show its detail.

#### Scenario: Show recent papers

- **WHEN** user switches the sidebar to the "Recent" panel
- **THEN** the 20 most recently accessed papers are listed with title and date

#### Scenario: Open paper from recent list

- **WHEN** user clicks a paper in the recent list
- **THEN** that paper opens in a tab in the detail pane

### Requirement: Starred/pinned papers

Users SHALL be able to star/pin papers for quick access. Starred state SHALL persist across launches (stored in `@AppStorage` or a local plist). The sidebar SHALL have a "Starred" section visible in the Categories panel, above the category tree.

#### Scenario: Star a paper

- **WHEN** user clicks the star icon on a paper row or in the detail view
- **THEN** the paper appears in the "Starred" section of the sidebar

#### Scenario: Unstar a paper

- **WHEN** user clicks the star icon on an already-starred paper
- **THEN** the paper is removed from the "Starred" section

### Requirement: Empty state and onboarding

When the library is empty (no papers in database), the app SHALL show an onboarding view in the center column with: a welcome message, instructions to add papers (drag-and-drop or `Cmd+O`), and a check for CLI availability. If the CLI is not found, the onboarding SHALL prompt the user to configure it in Preferences.

#### Scenario: Empty library on first launch

- **WHEN** user launches the app with no papers in the database
- **THEN** an onboarding view appears explaining how to add papers

#### Scenario: CLI not found during onboarding

- **WHEN** the onboarding view checks for the CLI and cannot find it
- **THEN** a warning is shown with a button to open Preferences
