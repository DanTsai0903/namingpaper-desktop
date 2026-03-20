import SwiftUI

struct SidebarView: View {
    @Environment(LibraryViewModel.self) var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            // Schema warning banner
            if let warning = viewModel.schemaWarning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(warning)
                        .font(.caption)
                }
                .padding(8)
                .background(.yellow.opacity(0.1))
            }

            // Panel switcher
            Picker("", selection: $viewModel.sidebarPanel) {
                ForEach(SidebarPanel.allCases, id: \.self) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            // Panel content
            switch viewModel.sidebarPanel {
            case .categories:
                CategoryTreeView()
            case .recent:
                RecentPapersView()
            case .search:
                SearchSidebarView()
            }

        }
        .frame(minWidth: 180)
    }
}

struct SearchSidebarView: View {
    @Environment(LibraryViewModel.self) var viewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 8) {
            TextField("Search papers...", text: $viewModel.searchViewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit { viewModel.searchViewModel.performSearch() }
                .onChange(of: viewModel.searchViewModel.searchText) { _, _ in
                    viewModel.searchViewModel.performSearch()
                }
                .onExitCommand {
                    viewModel.searchViewModel.clearSearch()
                    viewModel.activateSidebarPanel(.categories)
                }
                .padding(.horizontal, 8)

            // Filter chips
            FilterChipsView()

            // Search history (when field is focused and empty)
            if isSearchFocused && viewModel.searchViewModel.searchText.isEmpty
                && !viewModel.searchViewModel.searchHistory.isEmpty {
                HStack {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All") {
                        viewModel.searchViewModel.clearHistory()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                List {
                    ForEach(viewModel.searchViewModel.searchHistory, id: \.self) { query in
                        Button(query) {
                            viewModel.searchViewModel.searchText = query
                            viewModel.searchViewModel.performSearch()
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let query = viewModel.searchViewModel.searchHistory[index]
                            viewModel.searchViewModel.removeFromHistory(query)
                        }
                    }
                }
                .listStyle(.plain)
            }

            Spacer()
        }
        .padding(.top, 4)
        .onAppear { isSearchFocused = true }
    }
}

struct FilterChipsView: View {
    @Environment(LibraryViewModel.self) var viewModel
    @State private var showAuthorFilter = false
    @State private var showYearFilter = false
    @State private var showJournalFilter = false
    @State private var showCategoryFilter = false

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                FilterChip(
                    label: "Author",
                    isActive: !viewModel.searchViewModel.authorFilter.isEmpty,
                    onTap: { showAuthorFilter.toggle() },
                    onClear: {
                        viewModel.searchViewModel.authorFilter = ""
                        viewModel.searchViewModel.performSearch()
                    }
                )
                .popover(isPresented: $showAuthorFilter) {
                    TextField("Author name", text: $viewModel.searchViewModel.authorFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .padding()
                        .onSubmit {
                            showAuthorFilter = false
                            viewModel.searchViewModel.performSearch()
                        }
                }

                FilterChip(
                    label: "Year",
                    isActive: !viewModel.searchViewModel.yearFrom.isEmpty || !viewModel.searchViewModel.yearTo.isEmpty,
                    onTap: { showYearFilter.toggle() },
                    onClear: {
                        viewModel.searchViewModel.yearFrom = ""
                        viewModel.searchViewModel.yearTo = ""
                        viewModel.searchViewModel.performSearch()
                    }
                )
                .popover(isPresented: $showYearFilter) {
                    HStack {
                        TextField("From", text: $viewModel.searchViewModel.yearFrom)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("–")
                        TextField("To", text: $viewModel.searchViewModel.yearTo)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    .padding()
                    .onSubmit {
                        showYearFilter = false
                        viewModel.searchViewModel.performSearch()
                    }
                }

                FilterChip(
                    label: "Journal",
                    isActive: !viewModel.searchViewModel.journalFilter.isEmpty,
                    onTap: { showJournalFilter.toggle() },
                    onClear: {
                        viewModel.searchViewModel.journalFilter = ""
                        viewModel.searchViewModel.performSearch()
                    }
                )
                .popover(isPresented: $showJournalFilter) {
                    TextField("Journal", text: $viewModel.searchViewModel.journalFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .padding()
                        .onSubmit {
                            showJournalFilter = false
                            viewModel.searchViewModel.performSearch()
                        }
                }

                FilterChip(
                    label: "Category",
                    isActive: !viewModel.searchViewModel.categoryFilter.isEmpty,
                    onTap: { showCategoryFilter.toggle() },
                    onClear: {
                        viewModel.searchViewModel.categoryFilter = ""
                        viewModel.searchViewModel.performSearch()
                    }
                )
                .popover(isPresented: $showCategoryFilter) {
                    VStack {
                        ForEach(viewModel.categories) { cat in
                            Button(cat.name) {
                                viewModel.searchViewModel.categoryFilter = cat.name
                                showCategoryFilter = false
                                viewModel.searchViewModel.performSearch()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

struct FilterChip: View {
    let label: String
    let isActive: Bool
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onTap) {
                Text(label)
                    .font(.caption)
            }
            .buttonStyle(.plain)

            if isActive {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}
