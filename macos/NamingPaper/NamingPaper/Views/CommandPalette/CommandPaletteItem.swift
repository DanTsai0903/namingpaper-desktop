import SwiftUI

struct CommandPaletteItem: View {
    let item: PaletteAction
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: item.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(item.title)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
