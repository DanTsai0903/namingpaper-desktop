import Foundation
import Observation

struct AddPaperItem: Identifiable {
    let id = UUID()
    let filename: String
    let url: URL
    var stage: AddStage = .extracting
    var error: String?
}

@Observable
class AddPaperViewModel {
    var items: [AddPaperItem] = []
    var isProcessing: Bool = false
    var isComplete: Bool = false

    private let cli = CLIService.shared

    func addFiles(_ urls: [URL]) {
        items = urls.map { AddPaperItem(filename: $0.lastPathComponent, url: $0) }
        isProcessing = true
        isComplete = false
        processNext(index: 0)
    }

    private func processNext(index: Int) {
        guard index < items.count else {
            Task { @MainActor in
                isProcessing = false
                isComplete = true
            }
            return
        }

        Task {
            await MainActor.run {
                items[index].stage = .extracting
            }

            do {
                let result = try await cli.addPaper(path: items[index].url.path)
                await MainActor.run {
                    if result.success {
                        items[index].stage = .done
                    } else {
                        items[index].stage = .failed
                        items[index].error = result.stderr.isEmpty ? "Unknown error" : result.stderr
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
}
