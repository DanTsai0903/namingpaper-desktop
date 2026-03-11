import SwiftUI
import AppKit

struct PaperDetailView: View {
    let paper: Paper
    @Environment(LibraryViewModel.self) var viewModel
    @State private var showRemoveConfirmation = false
    @State private var showCategoryPicker = false
    @State private var newCategoryName = ""
    @State private var showNewCategoryField = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Metadata header
                metadataHeader

                // Summary callout
                summaryCallout

                // PDF preview
                pdfSection
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openInPreview()
                } label: {
                    Label("Open in Preview", systemImage: "eye")
                }

                Button {
                    revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Button {
                    showCategoryPicker.toggle()
                } label: {
                    Label("Recategorize", systemImage: "tag")
                }
                .popover(isPresented: $showCategoryPicker) {
                    categoryPickerPopover
                }

                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .confirmationDialog("Remove Paper", isPresented: $showRemoveConfirmation) {
                    Button("Remove from Library", role: .destructive) {
                        viewModel.removePaper(id: paper.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Remove \"\(paper.title)\" from your library? The PDF file will not be deleted.")
                }
            }
        }
    }

    // MARK: - Metadata Header

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(paper.title)
                .font(.title)
                .fontWeight(.bold)
                .textSelection(.enabled)

            Text(paper.authors)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                if let year = paper.year {
                    Text(String(year))
                        .font(.callout)
                }

                if !paper.journal.isEmpty {
                    Text(paper.journal)
                        .font(.callout)
                        .italic()
                }

                // Category badge
                if !paper.category.isEmpty {
                    Button {
                        showCategoryPicker.toggle()
                    } label: {
                        Text(paper.category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Keywords
            if !paper.keywordList.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(paper.keywordList, id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !paper.summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Summary", systemImage: "text.quote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(paper.summary)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                HStack {
                    Image(systemName: "text.quote")
                        .foregroundStyle(.secondary)
                    Text("No summary available")
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - PDF

    private var pdfSection: some View {
        Group {
            if paper.pdfExists {
                PDFPreviewView(url: paper.pdfURL!)
                    .frame(minHeight: 500)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("PDF not found")
                        .foregroundStyle(.secondary)
                    Text(paper.filePath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Category Picker

    private var categoryPickerPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Change Category")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(viewModel.categories) { cat in
                Button {
                    recategorize(to: cat.name)
                    showCategoryPicker = false
                } label: {
                    HStack {
                        Text(cat.name)
                        if cat.name == paper.category {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()

            if showNewCategoryField {
                HStack {
                    TextField("New category", text: $newCategoryName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard !newCategoryName.isEmpty else { return }
                        recategorize(to: newCategoryName)
                        showCategoryPicker = false
                        showNewCategoryField = false
                        newCategoryName = ""
                    }
                }
            } else {
                Button("New Category...") {
                    showNewCategoryField = true
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 200)
    }

    // MARK: - Actions

    private func openInPreview() {
        guard let url = paper.pdfURL, paper.pdfExists else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealInFinder() {
        guard let url = paper.pdfURL, paper.pdfExists else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func recategorize(to category: String) {
        guard category != paper.category else { return }
        Task {
            // Move file to new category directory via file system
            let sourcePath = paper.filePath
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let filename = sourceURL.lastPathComponent

            // Determine papers_dir from config
            let config = ConfigService.shared.readConfig()
            let papersDir = URL(fileURLWithPath: config.papersDir)
            let destDir = papersDir.appendingPathComponent(category)
            let destPath = destDir.appendingPathComponent(filename)

            do {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: sourceURL, to: destPath)
                // Sync library to pick up the change
                _ = try? await CLIService.shared.syncLibrary()
                await viewModel.refresh()
            } catch {
                // If move fails, just refresh to stay consistent
                await viewModel.refresh()
            }
        }
    }
}

// Simple flow layout for keyword tags
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
