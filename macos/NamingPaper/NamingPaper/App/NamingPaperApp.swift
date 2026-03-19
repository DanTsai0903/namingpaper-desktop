import SwiftUI

@main
struct NamingPaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var onboardingComplete = ConfigService.shared.configExists
    @State private var libraryViewModel: LibraryViewModel? = ConfigService.shared.configExists ? LibraryViewModel() : nil
    @State private var tabManager = TabManager()
    @AppStorage("appearance") private var appearance: String = "system"

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if onboardingComplete, let libraryViewModel {
                ContentView()
                    .environment(libraryViewModel)
                    .environment(tabManager)
                    .preferredColorScheme(colorScheme)
                    .frame(minWidth: 900, minHeight: 600)
                    .onDrop(of: [.pdf], isTargeted: Bindable(libraryViewModel).isDragTargeted) { providers in
                        libraryViewModel.handleDrop(providers: providers)
                        return true
                    }
                    .overlay {
                        if libraryViewModel.isDragTargeted {
                            DropZoneOverlay()
                        }
                    }
                    .overlay {
                        if libraryViewModel.showCommandPalette {
                            CommandPaletteView()
                                .environment(libraryViewModel)
                                .environment(tabManager)
                        }
                    }
                    .sheet(isPresented: Bindable(libraryViewModel).showAddPaperSheet, onDismiss: {
                        DispatchQueue.main.async {
                            libraryViewModel.addPaperViewModel.reset()
                        }
                    }) {
                        AddPaperSheet()
                            .environment(libraryViewModel)
                    }
                    .fileImporter(
                        isPresented: Bindable(libraryViewModel).showFilePicker,
                        allowedContentTypes: [.pdf],
                        allowsMultipleSelection: true
                    ) { result in
                        libraryViewModel.handleFileImport(result: result)
                    }
            } else {
                OnboardingView {
                    onboardingComplete = true
                    libraryViewModel = LibraryViewModel()
                }
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 900, minHeight: 600)
            }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About NamingPaper") {
                    AboutWindowController.shared.show()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("Add Papers...") {
                    libraryViewModel?.showFilePicker = true
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!onboardingComplete)
            }

            CommandGroup(after: .textEditing) {
                Button("Find in Library") {
                    libraryViewModel?.activateSidebarPanel(.search)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!onboardingComplete)

                Divider()

                Button("Command Palette") {
                    libraryViewModel?.showCommandPalette.toggle()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!onboardingComplete)
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
                    )
                }
                .keyboardShortcut("\\", modifiers: .command)
            }

            CommandGroup(before: .windowArrangement) {
                Button("Close Tab") {
                    tabManager.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(tabManager.activeTabID == nil)

                Button("Next Tab") {
                    tabManager.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(tabManager.openTabs.count < 2)

                Button("Previous Tab") {
                    tabManager.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(tabManager.openTabs.count < 2)
            }
        }

        Settings {
            PreferencesView()
        }
    }
}
