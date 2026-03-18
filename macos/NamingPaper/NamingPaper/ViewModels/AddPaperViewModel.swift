import Foundation
import Observation
import AppKit

struct AddPaperItem: Identifiable {
    let id = UUID()
    let filename: String
    let url: URL
    var stage: AddStage = .extracting
    var error: String?
    var result: AddPaperResult?
}

@Observable
class AddPaperViewModel {
    var items: [AddPaperItem] = []
    var phase: AddFlowPhase = .configure
    var isProcessing: Bool = false
    var isComplete: Bool = false
    var isCommitting: Bool = false
    var hasCommitted: Bool = false
    var options = AddPaperOptions()

    private let cli = CLIService.shared

    /// Available existing categories, set from LibraryViewModel
    var existingCategories: [String] = []

    init() {
        // Pre-fill from active saved provider
        loadActiveProvider()
    }

    private func loadActiveProvider() {
        let activeProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? ""
        let activeModel = UserDefaults.standard.string(forKey: "aiModel") ?? ""
        if let data = UserDefaults.standard.data(forKey: "savedProviders"),
           let saved = try? JSONDecoder().decode([SavedProvider].self, from: data),
           let active = saved.first(where: { $0.provider == activeProvider && $0.model == activeModel }) {
            options.selectedSavedProviderID = active.id
            options.provider = active.provider
            options.model = active.model
        } else if !activeProvider.isEmpty {
            options.provider = activeProvider
        }
    }

    var hasSuccessfulResults: Bool {
        items.contains { $0.result != nil }
    }

    func addFiles(_ urls: [URL]) {
        items = urls.map { AddPaperItem(filename: $0.lastPathComponent, url: $0) }
        phase = .configure
        isProcessing = false
        isComplete = false
        isCommitting = false
    }

    func startProcessing() {
        phase = .processing
        isProcessing = true
        isComplete = false
        processNext(index: 0)
    }

    private func processNext(index: Int) {
        guard index < items.count else {
            Task { @MainActor in
                isProcessing = false
                isComplete = true
                phase = .review
            }
            return
        }

        Task {
            await MainActor.run {
                items[index].stage = .extracting
            }

            do {
                let cliResult = try await cli.dryRunAddPaper(
                    path: items[index].url.path,
                    provider: options.provider.isEmpty ? nil : options.provider,
                    model: options.model.isEmpty ? nil : options.model,
                    template: options.template,
                    noRename: !options.renameFile,
                    reasoning: options.reasoning ? true : nil
                )
                await MainActor.run {
                    // Try JSON parsing first, fall back to Rich table parsing
                    var paperResult: AddPaperResult?
                    if cliResult.success,
                       let jsonResult = CLIService.parseJSONOutput(cliResult.stdout),
                       jsonResult.status == "ok",
                       let paper = jsonResult.paper {
                        paperResult = AddPaperResult(from: paper)
                    } else if cliResult.success,
                              let parsed = CLIService.parseDryRunOutput(cliResult.stdout) {
                        // Fallback for older CLI versions without --json
                        paperResult = AddPaperResult(from: parsed)
                    }

                    if var result = paperResult {
                        // Category priority: prefer existing category match
                        if options.categoryPriority {
                            let suggested = result.suggestedCategory.lowercased()
                            if let match = existingCategories.first(where: { $0.lowercased() == suggested }) {
                                result.editedCategory = match
                            }
                        }

                        // If no-rename, show original filename
                        if !options.renameFile {
                            result.editedName = items[index].filename
                            result.suggestedName = items[index].filename
                        }

                        items[index].result = result
                        items[index].stage = .done
                    } else {
                        items[index].stage = .failed
                        // Check for JSON error response
                        if let jsonResult = CLIService.parseJSONOutput(cliResult.stdout),
                           let error = jsonResult.error {
                            items[index].error = error
                        } else {
                            let errorMsg = [cliResult.stderr, cliResult.stdout]
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                                .joined(separator: "\n")
                            items[index].error = errorMsg.isEmpty ? "Unknown error" : errorMsg
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    items[index].stage = .failed
                    items[index].error = error.localizedDescription
                }
            }

            processNext(index: index + 1)
        }
    }

    func commitPapers() {
        isCommitting = true
        commitNext(index: 0)
    }

    private func commitNext(index: Int) {
        // Find next item with a successful result
        guard let nextIndex = (index..<items.count).first(where: { items[$0].result != nil && items[$0].stage != .failed }) else {
            Task { @MainActor in
                isCommitting = false
                hasCommitted = true
            }
            return
        }

        Task {
            await MainActor.run {
                items[nextIndex].stage = .extracting // Show spinner during commit
            }

            do {
                guard let result = items[nextIndex].result else { return }
                let cliResult = try await cli.addPaper(
                    path: items[nextIndex].url.path,
                    provider: options.provider.isEmpty ? nil : options.provider,
                    model: options.model.isEmpty ? nil : options.model,
                    category: result.editedCategory,
                    template: options.template,
                    filename: options.renameFile ? result.editedName : nil,
                    noRename: !options.renameFile,
                    reasoning: options.reasoning ? true : nil,
                    metadataJSON: result.cachedMetadataJSON
                )
                await MainActor.run {
                    if cliResult.success {
                        items[nextIndex].stage = .done
                    } else {
                        items[nextIndex].stage = .failed
                        let errorMsg = [cliResult.stderr, cliResult.stdout]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                        items[nextIndex].error = errorMsg.isEmpty ? "Commit failed" : errorMsg
                    }
                }
            } catch {
                await MainActor.run {
                    items[nextIndex].stage = .failed
                    items[nextIndex].error = error.localizedDescription
                }
            }

            commitNext(index: nextIndex + 1)
        }
    }

    func reset() {
        // Clear phase first so the review ForEach stops rendering before items are emptied,
        // preventing "Index out of range" crashes from stale bindings.
        phase = .configure
        items = []
        isProcessing = false
        isComplete = false
        isCommitting = false
        hasCommitted = false
        options = AddPaperOptions()
        loadActiveProvider()
    }
}
