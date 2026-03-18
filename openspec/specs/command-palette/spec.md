# Capability: command-palette

## Purpose

Provides a quick-access command palette overlay for searching actions and papers, enabling keyboard-driven navigation.

## Requirements

### Requirement: Command palette overlay

The app SHALL display a command palette overlay when the user presses `Cmd+P`. The overlay SHALL appear as a floating panel centered near the top of the window, with a text input field and a scrollable results list below it. The overlay SHALL dismiss when the user presses `Esc` or clicks outside it.

#### Scenario: Open command palette

- **WHEN** user presses `Cmd+P`
- **THEN** the command palette overlay appears with the text field focused

#### Scenario: Dismiss command palette

- **WHEN** user presses `Esc` while command palette is open
- **THEN** the overlay dismisses and focus returns to the previous view

### Requirement: Fuzzy search across actions and papers

The command palette SHALL perform fuzzy substring matching against both action names and paper titles as the user types. Results SHALL be grouped: actions first, then papers. Each result SHALL show its type (action or paper) and title. The list SHALL update live as the user types.

#### Scenario: Search matches actions

- **WHEN** user types "add" in the command palette
- **THEN** the "Add Paper..." action appears in the results

#### Scenario: Search matches paper titles

- **WHEN** user types a partial paper title
- **THEN** matching papers appear in the results below actions

#### Scenario: Empty query shows all actions

- **WHEN** user opens command palette without typing
- **THEN** all available actions are listed

### Requirement: Action execution

The command palette SHALL support these actions: "Add Paper..." (opens file picker), "Search Library" (switches sidebar to search), "Open Preferences" (`Cmd+,`), "Reveal in Finder" (for active paper), "Sync Library". Selecting an action SHALL execute it and dismiss the palette.

#### Scenario: Execute action from palette

- **WHEN** user selects "Add Paper..." from the command palette
- **THEN** the palette dismisses and the file picker opens

### Requirement: Quick paper switching

Selecting a paper from command palette results SHALL open it in a tab (or switch to its existing tab). This SHALL work identically to clicking the paper in the list view.

#### Scenario: Jump to paper via palette

- **WHEN** user selects a paper from command palette results
- **THEN** the paper opens in a tab (or its existing tab activates) and the palette dismisses
