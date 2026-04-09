import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var step = 0
    @State private var papersDir: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Papers").path
    @State private var showFolderPicker = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Group {
                switch step {
                case 0: welcomeStep
                case 1: directoryStep
                case 2: tutorialStep
                case 3: localAIStep
                default: EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.3), value: step)

            Spacer()

            stepIndicators
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                papersDir = url.path
                errorMessage = nil
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Welcome to NamingPaper")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Organize and manage your academic paper library")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Continue") {
                withAnimation { step = 1 }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.top, 8)
        }
    }

    // MARK: - Step 2: Directory Selection

    private var directoryStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Choose Your Library Folder")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This is where your papers will be stored.\nYou can change this later in Preferences.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Text(papersDir)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 350, alignment: .leading)
                    .padding(8)
                    .background(.quaternary)
                    .cornerRadius(6)

                Button("Choose Folder...") {
                    showFolderPicker = true
                }
            }
            .padding(.top, 4)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Continue") {
                withAnimation { step = 2 }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.top, 8)
        }
    }

    // MARK: - Step 3: Tutorial

    private var tutorialStep: some View {
        VStack(spacing: 20) {
            Text("Quick Start")
                .font(.title2)
                .fontWeight(.semibold)

            LazyVGrid(columns: [GridItem(.fixed(280)), GridItem(.fixed(280))], spacing: 16) {
                featureCard(
                    icon: "arrow.down.doc",
                    title: "Add Papers",
                    description: "Drag PDFs onto the window, press \u{2318}O, or drop onto the dock icon"
                )
                featureCard(
                    icon: "folder",
                    title: "Organize",
                    description: "Create categories to group related papers"
                )
                featureCard(
                    icon: "bubble.left.and.text.bubble.right",
                    title: "Chat with PDF",
                    description: "Ask questions about any paper and get AI-powered answers with context"
                )
                featureCard(
                    icon: "magnifyingglass",
                    title: "Search",
                    description: "Search across titles, authors, journals, and keywords"
                )
                Button {
                    withAnimation { step = 3 }
                } label: {
                    localAICard
                }
                .buttonStyle(.plain)
                featureCard(
                    icon: "terminal",
                    title: "CLI Integration",
                    description: "Use the namingpaper CLI to batch-rename and extract metadata"
                )
            }

            Button("Get Started") {
                completeOnboarding()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .padding(.top, 8)
        }
    }

    // MARK: - Step 4: Local AI Providers

    private var localAIStep: some View {
        VStack(spacing: 20) {
            ScrollView {
                LocalAIProvidersTutorialView()
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 12) {
                Button("Back") {
                    withAnimation { step = 2 }
                }
                .controlSize(.large)

                Button("Get Started") {
                    completeOnboarding()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Components

    private var localAICard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text("Local AI Providers")
                    .fontWeight(.medium)
                Text("Run AI on your Mac — no API key needed. We recommend oMLX for best Apple Silicon performance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("Setup guide")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
        )
    }

    private func featureCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    private func featureLinkCard(icon: String, title: String, description: String, links: [(label: String, url: String)]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        Link(link.label, destination: URL(string: link.url)!)
                            .font(.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    private var stepIndicators: some View {
        let activeStep = min(step, 2)
        return HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(index == activeStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Completion

    private func completeOnboarding() {
        do {
            try FileManager.default.createDirectory(
                atPath: papersDir,
                withIntermediateDirectories: true
            )
            var config = AppConfig.default
            config.papersDir = papersDir
            try ConfigService.shared.writeConfig(config)
            onComplete()
        } catch {
            errorMessage = String(localized: "Failed to set up library: \(error.localizedDescription)")
            withAnimation { step = 1 }
        }
    }
}
