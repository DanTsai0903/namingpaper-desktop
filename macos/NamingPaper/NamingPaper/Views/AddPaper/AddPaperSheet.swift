import SwiftUI

struct AddPaperSheet: View {
    @Environment(LibraryViewModel.self) var viewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Adding Papers")
                .font(.headline)

            List {
                ForEach(viewModel.addPaperViewModel.items) { item in
                    HStack {
                        stageIcon(item.stage)

                        VStack(alignment: .leading) {
                            Text(item.filename)
                                .lineLimit(1)
                            if let error = item.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            } else {
                                Text(item.stage.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                }
            }
            .frame(minHeight: 200)

            HStack {
                if viewModel.addPaperViewModel.isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.addPaperViewModel.isProcessing)
            }
        }
        .padding()
        .frame(width: 450, minHeight: 300)
    }

    @ViewBuilder
    private func stageIcon(_ stage: AddStage) -> some View {
        switch stage {
        case .extracting, .summarizing, .categorizing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 20, height: 20)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 20, height: 20)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .frame(width: 20, height: 20)
        }
    }
}
