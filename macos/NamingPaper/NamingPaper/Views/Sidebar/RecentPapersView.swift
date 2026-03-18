import SwiftUI

struct RecentPapersView: View {
    @Environment(LibraryViewModel.self) var viewModel
    @Environment(TabManager.self) var tabManager

    var body: some View {
        List {
            if viewModel.recentPapers.isEmpty {
                Text("No recent papers")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewModel.recentPapers) { paper in
                    Button {
                        tabManager.openTab(for: paper)
                        viewModel.markRecent(paperID: paper.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paper.title)
                                .lineLimit(1)
                                .font(.body)
                            Text(paper.authors)
                                .lineLimit(1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }
}
