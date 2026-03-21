import SwiftUI

struct CommandPaletteView: View {
    @Environment(LibraryViewModel.self) var viewModel
    @Environment(TabManager.self) var tabManager
    @State private var query: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.showCommandPalette = false
                }

            // Palette panel
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Type a command or paper name...", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit {
                            executeFirstResult()
                        }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Results
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Actions
                        let matchingActions = filteredActions
                        if !matchingActions.isEmpty {
                            Text("Actions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(matchingActions) { item in
                                CommandPaletteItem(item: item) {
                                    execute(item)
                                }
                            }
                        }

                        // Papers
                        let matchingPapers = filteredPapers
                        if !matchingPapers.isEmpty {
                            Text("Papers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(matchingPapers) { paper in
                                Button {
                                    tabManager.openTab(for: paper)
                                    viewModel.showCommandPalette = false
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.secondary)
                                        Text(paper.title)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(paper.yearString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 500)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { isFocused = true }
        .onExitCommand { viewModel.showCommandPalette = false }
    }

    // MARK: - Data

    private var allActions: [PaletteAction] {
        [
            PaletteAction(id: "add", title: String(localized: "Add Paper..."), icon: "plus.circle", action: .addPaper),
            PaletteAction(id: "search", title: String(localized: "Search Library"), icon: "magnifyingglass", action: .search),
            PaletteAction(id: "prefs", title: String(localized: "Open Preferences"), icon: "gearshape", action: .preferences),
            PaletteAction(id: "reveal", title: String(localized: "Reveal in Finder"), icon: "folder", action: .revealInFinder),
            PaletteAction(id: "sync", title: String(localized: "Sync Library"), icon: "arrow.triangle.2.circlepath", action: .sync),
        ]
    }

    private var filteredActions: [PaletteAction] {
        guard !query.isEmpty else { return allActions }
        let lower = query.lowercased()
        return allActions.filter { $0.title.lowercased().contains(lower) }
    }

    private var filteredPapers: [Paper] {
        guard !query.isEmpty else { return [] }
        let lower = query.lowercased()
        return viewModel.papers.filter { $0.title.lowercased().contains(lower) }.prefix(10).map { $0 }
    }

    private func executeFirstResult() {
        if let action = filteredActions.first {
            execute(action)
        } else if let paper = filteredPapers.first {
            tabManager.openTab(for: paper)
            viewModel.showCommandPalette = false
        }
    }

    private func execute(_ action: PaletteAction) {
        viewModel.showCommandPalette = false
        switch action.action {
        case .addPaper:
            viewModel.showFilePicker = true
        case .search:
            viewModel.activateSidebarPanel(.search)
        case .preferences:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .revealInFinder:
            if let id = tabManager.activeTabID, let paper = viewModel.paper(for: id),
               let url = paper.pdfURL, paper.pdfExists {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case .sync:
            Task {
                _ = try? await CLIService.shared.syncLibrary()
                await viewModel.refresh()
            }
        }
    }
}

enum PaletteActionType {
    case addPaper, search, preferences, revealInFinder, sync
}

struct PaletteAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    let action: PaletteActionType
}
