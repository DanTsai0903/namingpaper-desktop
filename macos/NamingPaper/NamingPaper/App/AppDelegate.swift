import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs dropped onto the dock icon, queued for processing
    static var pendingURLs: [URL] = []
    static var onFilesDropped: (([URL]) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let bundleURLs = urls.filter { $0.pathExtension.lowercased() == "namingpaper" }

        // Handle .namingpaper bundle imports
        for bundleURL in bundleURLs {
            Task {
                do {
                    let result = try await SharingService.shared.importBundle(at: bundleURL)
                    print("Imported \(result.imported) papers, skipped \(result.skipped) duplicates")
                } catch {
                    print("Bundle import error: \(error.localizedDescription)")
                }
            }
        }

        // Handle PDF drops
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

        // iCloud sync disabled — will be enabled in a future release
        // Reset any stale sync preference
        UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
    }

}
