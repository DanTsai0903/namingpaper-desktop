import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs dropped onto the dock icon, queued for processing
    static var pendingURLs: [URL] = []
    static var onFilesDropped: (([URL]) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else { return }

        if let handler = Self.onFilesDropped {
            handler(pdfURLs)
        } else {
            Self.pendingURLs.append(contentsOf: pdfURLs)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Process any URLs that arrived before the handler was set
        if !Self.pendingURLs.isEmpty, let handler = Self.onFilesDropped {
            handler(Self.pendingURLs)
            Self.pendingURLs.removeAll()
        }
    }
}
