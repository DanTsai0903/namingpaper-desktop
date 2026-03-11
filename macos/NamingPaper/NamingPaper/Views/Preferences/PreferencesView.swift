import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AIProviderPrefsView()
                .tabItem {
                    Label("AI Provider", systemImage: "brain")
                }
        }
        .frame(width: 450, height: 300)
    }
}
