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
        // Pre-fill provider from UserDefaults
        if let saved = UserDefaults.standard.string(forKey: "aiProvider"), !saved.isEmpty {
            options.provider = saved
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
                    template: options.template,
                    noRename: !options.renameFile,
                    reasoning: options.reasoning ? true : nil
                )
                await MainActor.run {
                    if cliResult.success,
                       let parsed = CLIService.parseDryRunOutput(cliResult.stdout) {
                        var paperResult = AddPaperResult(from: parsed)

                        // Category priority: prefer existing category match
                        if options.categoryPriority {
                            let suggested = paperResult.suggestedCategory.lowercased()
                            if let match = existingCategories.first(where: { $0.lowercased() == suggested }) {
                                paperResult.editedCategory = match
                            }
                        }

                        // If no-rename, show original filename
                        if !options.renameFile {
                            paperResult.editedName = items[index].filename
                            paperResult.suggestedName = items[index].filename
                        }

                        items[index].result = paperResult
                        items[index].stage = .done
                    } else {
                        items[index].stage = .failed
                        let errorMsg = [cliResult.stderr, cliResult.stdout]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                        items[index].error = errorMsg.isEmpty ? "Unknown error" : errorMsg
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
                    category: result.editedCategory,
                    template: options.template,
                    filename: options.renameFile ? result.editedName : nil,
                    noRename: !options.renameFile,
                    reasoning: options.reasoning ? true : nil
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
        items = []
        phase = .configure
        isProcessing = false
        isComplete = false
        isCommitting = false
        hasCommitted = false
        options = AddPaperOptions()
        if let saved = UserDefaults.standard.string(forKey: "aiProvider"), !saved.isEmpty {
            options.provider = saved
        }
    }
}
