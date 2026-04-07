import SwiftUI

struct ChatPanelView: View {
    let paper: Paper
    @State private var viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @State private var savedProviders: [SavedProvider] = []
    @AppStorage("aiProvider") private var activeProvider: String = "ollama"
    @AppStorage("aiModel") private var activeModel: String = ""
    @Environment(\.openSettings) private var openSettings

    init(paper: Paper) {
        self.paper = paper
        self._viewModel = State(initialValue: ChatViewModel(paper: paper))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        greetingSection
                        suggestedQuestionsSection
                        messagesSection
                        if viewModel.isLoading {
                            loadingIndicator
                        }
                    }
                    .padding()
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            if viewModel.isIndexing {
                indexingBar
            }

            if let error = viewModel.errorMessage {
                errorBar(error)
            }

            Divider()

            // Input bar
            inputBar
        }
        .task {
            loadSavedProviders()
            await viewModel.setup()
        }
    }

    // MARK: - Provider Picker

    private var activeProviderLabel: String {
        if let match = savedProviders.first(where: { $0.provider == activeProvider && $0.model == activeModel }) {
            return match.name
        }
        return providerDisplayName(activeProvider)
    }

    private var providerMenu: some View {
        Menu {
            ForEach(savedProviders) { item in
                Button {
                    activate(item)
                } label: {
                    HStack {
                        Text("\(item.name) — \(providerDisplayName(item.provider))")
                        if item.provider == activeProvider && item.model == activeModel {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if savedProviders.isEmpty {
                Text("No providers configured")
            }
            Divider()
            Button("Open AI Settings…") {
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .openAIProviderSettings, object: nil)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption)
                Text(activeProviderLabel)
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Change AI provider for chat")
    }

    private func providerDisplayName(_ id: String) -> String {
        switch id {
        case "omlx": return "oMLX"
        case "ollama": return "Ollama"
        case "lmstudio": return "LM Studio"
        default: return id.capitalized
        }
    }

    private func loadSavedProviders() {
        if let data = UserDefaults.standard.data(forKey: "savedProviders"),
           let decoded = try? JSONDecoder().decode([SavedProvider].self, from: data) {
            savedProviders = decoded
        }
    }

    private func activate(_ item: SavedProvider) {
        activeProvider = item.provider
        activeModel = item.model
        var config = ConfigService.shared.readConfig()
        config.provider = item.provider
        config.model = item.model
        config.baseURL = item.baseURL
        config.apiKey = ""
        try? ConfigService.shared.writeConfig(config)
        KeychainService.save(key: item.apiKey, account: config.apiKeyTOMLName)
        Task { await viewModel.refreshProvider() }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.teal)
                    .font(.title3)
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(3)
            }

            if !paper.summary.isEmpty {
                let bullets = paper.summary
                    .split(separator: ".", maxSplits: 3, omittingEmptySubsequences: true)
                    .prefix(3)
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\u{2022}")
                            .foregroundStyle(.secondary)
                        Text(bullet + ".")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                Task { await viewModel.summarize() }
            } label: {
                Label("Summarize this paper", systemImage: "text.justify.leading")
            }
            .buttonStyle(.bordered)
            .tint(.teal)
            .disabled(viewModel.isLoading || viewModel.isIndexing)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Suggested Questions

    @ViewBuilder
    private var suggestedQuestionsSection: some View {
        if !viewModel.suggestedQuestions.isEmpty && viewModel.messages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.suggestedQuestions, id: \.self) { question in
                    Button {
                        Task { await viewModel.sendMessage(question) }
                    } label: {
                        HStack {
                            Text(question)
                                .font(.callout)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.circle")
                                .foregroundStyle(.teal)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading || viewModel.isIndexing)
                }
            }
        }
    }

    // MARK: - Messages

    private var messagesSection: some View {
        ForEach(viewModel.messages) { message in
            MessageBubbleView(message: message)
                .id(message.id)
        }
    }

    // MARK: - Loading

    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.teal)
            ProgressView()
                .controlSize(.small)
            Text("Thinking...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Indexing Bar

    private var indexingBar: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(viewModel.indexingProgress)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.teal.opacity(0.1))
    }

    // MARK: - Error Bar

    private func errorBar(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Dismiss") {
                viewModel.errorMessage = nil
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.startNewConversation() }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New conversation")

            providerMenu

            TextField("Ask any question...", text: $inputText)
                .textFieldStyle(.plain)
                .onSubmit { sendCurrent() }
                .disabled(viewModel.isLoading || viewModel.isIndexing)

            Button {
                sendCurrent()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.isEmpty || viewModel.isLoading ? Color.secondary : Color.teal)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || viewModel.isLoading || viewModel.isIndexing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func sendCurrent() {
        let text = inputText
        inputText = ""
        Task { await viewModel.sendMessage(text) }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastID = viewModel.messages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}
