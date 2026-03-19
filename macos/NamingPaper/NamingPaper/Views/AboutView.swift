import SwiftUI
import AppKit

struct AboutView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("NamingPaper")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(version)")
                .foregroundStyle(.secondary)

            Link("github.com/DanTsai0903", destination: URL(string: "https://github.com/DanTsai0903")!)
                .font(.callout)

            Text("Copyright \u{00A9} 2026 DanTsai0903. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 320)
    }
}

class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "About NamingPaper"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: AboutView())
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }
}
