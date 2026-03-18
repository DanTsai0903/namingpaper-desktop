import SwiftUI

struct TabBarView: View {
    @Environment(TabManager.self) var tabManager
    @State private var hoveredTabID: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabManager.openTabs) { tab in
                    tabItem(tab)
                }
            }
        }
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tabItem(_ tab: PaperTab) -> some View {
        let isActive = tabManager.activeTabID == tab.id

        return Button {
            tabManager.activeTabID = tab.id
        } label: {
            HStack(spacing: 4) {
                Text(tab.title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: 150)

                if hoveredTabID == tab.id || isActive {
                    Button {
                        tabManager.closeTab(id: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
    }
}
