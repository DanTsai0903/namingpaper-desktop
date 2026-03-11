import SwiftUI

struct ContentView: View {
    @Environment(LibraryViewModel.self) var viewModel
    @Environment(TabManager.self) var tabManager

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            if viewModel.isEmpty {
                EmptyLibraryView()
            } else {
                PaperListView()
            }
        } detail: {
            VStack(spacing: 0) {
                if !tabManager.openTabs.isEmpty {
                    TabBarView()
                }

                if let activeID = tabManager.activeTabID,
                   let paper = viewModel.paper(for: activeID) {
                    PaperDetailView(paper: paper)
                        .id(paper.id)
                } else {
                    Text("Select a paper to view details")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationSplitViewStyle(.automatic)
    }
}
