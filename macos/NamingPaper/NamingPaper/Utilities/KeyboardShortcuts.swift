import SwiftUI

// Centralized keyboard shortcut definitions
enum AppShortcuts {
    static let addPaper = KeyboardShortcut("o", modifiers: .command)
    static let find = KeyboardShortcut("f", modifiers: .command)
    static let commandPalette = KeyboardShortcut("p", modifiers: .command)
    static let closeTab = KeyboardShortcut("w", modifiers: .command)
    static let nextTab = KeyboardShortcut("]", modifiers: [.command, .shift])
    static let previousTab = KeyboardShortcut("[", modifiers: [.command, .shift])
    static let toggleSidebar = KeyboardShortcut("\\", modifiers: .command)
    static let preferences = KeyboardShortcut(",", modifiers: .command)
}
