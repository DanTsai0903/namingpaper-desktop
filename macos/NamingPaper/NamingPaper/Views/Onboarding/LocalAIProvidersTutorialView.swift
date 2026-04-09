import SwiftUI

struct LocalAIProvidersTutorialView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Title
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "cpu")
                        .font(.title)
                        .foregroundColor(.accentColor)
                    Text("Local AI Providers")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text("Run AI entirely on your Mac — no API key, no internet required.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            providerSection(
                name: "oMLX",
                badge: "Recommended",
                icon: "star.fill",
                iconColor: .orange,
                url: "https://omlx.ai",
                description: "Native Apple Silicon app with best-in-class performance on M-series Macs. Uses Metal for GPU acceleration.",
                steps: [
                    "Download oMLX from omlx.ai",
                    "Open oMLX and download a model (we recommend Qwen3.5-2B-MLX-4bit)",
                    "oMLX runs an OpenAI-compatible server at http://localhost:8000",
                    "In NamingPaper Preferences → AI Provider, choose \"Local (OpenAI-compatible)\" and set the base URL to http://localhost:8000/v1",
                ]
            )

            Divider()

            providerSection(
                name: "Ollama",
                badge: nil,
                icon: "circle.hexagongrid",
                iconColor: .accentColor,
                url: "https://ollama.com",
                description: "Easy-to-use CLI tool with a large model library. Works on Intel and Apple Silicon Macs.",
                steps: [
                    "Download Ollama from ollama.com",
                    "Run: ollama pull llama3 (or any model)",
                    "Ollama runs at http://localhost:11434 by default",
                    "In NamingPaper Preferences → AI Provider, choose \"Ollama\" and set the model name",
                ]
            )

            Divider()

            providerSection(
                name: "LM Studio",
                badge: nil,
                icon: "display",
                iconColor: .purple,
                url: "https://lmstudio.ai",
                description: "GUI app for discovering, downloading, and running local models. Great for exploring different models.",
                steps: [
                    "Download LM Studio from lmstudio.ai",
                    "Search and download a model in the Discover tab",
                    "Start the local server (default: http://localhost:1234)",
                    "In NamingPaper Preferences → AI Provider, choose \"Local (OpenAI-compatible)\" and set the base URL to http://localhost:1234/v1",
                ]
            )
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func providerSection(
        name: String,
        badge: String?,
        icon: String,
        iconColor: Color,
        url: String,
        description: String,
        steps: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(name)
                    .font(.headline)
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
                Spacer()
                Link("Download", destination: URL(string: url)!)
                    .font(.caption)
            }

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                        Text(step)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
