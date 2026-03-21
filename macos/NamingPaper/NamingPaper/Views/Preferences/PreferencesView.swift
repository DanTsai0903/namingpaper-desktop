import SwiftUI

struct PreferencesView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPrefsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            TemplatePrefsView()
                .tabItem {
                    Label("Templates", systemImage: "doc.text")
                }
                .tag(1)

            AIProviderPrefsView()
                .tabItem {
                    Label("AI Provider", systemImage: "brain")
                }
                .tag(2)

            BackupPrefsView()
                .tabItem {
                    Label("Backup", systemImage: "externaldrive.badge.timemachine")
                }
                .tag(3)

            SyncPrefsView()
                .tabItem {
                    Label("iCloud Sync", systemImage: "icloud")
                }
                .tag(4)
        }
        .frame(width: 550, height: 450)
    }
}
