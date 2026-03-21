import SwiftUI
import Combine

struct SyncStatusToolbarItem: View {
    @State private var syncStatus: SyncStatus = .disabled
    @State private var cancellable: AnyCancellable?

    var body: some View {
        if case .disabled = syncStatus {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                Image(systemName: syncStatus.systemImage)
                    .foregroundStyle(statusColor)
                    .imageScale(.small)

                if case .syncing = syncStatus {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .help(syncStatus.displayName)
            .onAppear {
                cancellable = SyncService.shared.statusPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { status in
                        syncStatus = status
                    }
            }
        }
    }

    private var statusColor: Color {
        switch syncStatus {
        case .synced: return .green
        case .syncing: return .blue
        case .offline: return .gray
        case .error: return .orange
        case .disabled: return .secondary
        }
    }
}

struct SyncConflictDialog: View {
    let conflict: SyncConflict
    let onResolve: (SyncConflictResolution) -> Void

    enum SyncConflictResolution {
        case keepLocal
        case deleteLocal
        case keepBoth
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Sync Conflict")
                .font(.headline)

            Text(conflictMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Keep Paper") {
                    onResolve(.keepLocal)
                }

                Button("Delete Paper") {
                    onResolve(.deleteLocal)
                }
                .foregroundStyle(.red)

                Button("Keep Both") {
                    onResolve(.keepBoth)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var conflictMessage: String {
        switch conflict.conflictType {
        case .remoteDeleted:
            return "\"\(conflict.title)\" was deleted on another device. What would you like to do with your local copy?"
        case .localDeleted:
            return "\"\(conflict.title)\" was deleted locally but still exists on another device. What would you like to do?"
        }
    }
}
