import SwiftUI

struct SyncPrefsView: View {
    var body: some View {
        Form {
            Section {
                Toggle("iCloud Sync", isOn: .constant(false))
                    .disabled(true)

                Label("iCloud Sync is coming in a future release.", systemImage: "icloud")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
