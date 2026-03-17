import SwiftUI
import AppKit

struct PaperDetailView: View {
    let paper: Paper
    @Environment(LibraryViewModel.self) var viewModel
    @State private var showRemoveConfirmation = false
    @State private var showCategoryPicker = false
    @State private var newCategoryName = ""
    @State private var showNewCategoryField = false
    @State private var summaryExpanded = false
    @State private var keywordsExpanded = false

    // Editing state for keywords
    @State private var isEditingKeywords = false
    @State private var editingKeywordsText = ""

    // Editing state for summary
    @State private var isEditingSummary = false
    @State private var editingSummaryText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact metadata + summary at top (scrollable if needed)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    metadataHeader
                    summaryCallout
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: summaryExpanded || isEditingKeywords || isEditingSummary ? 350 : 180)

            Divider()

            // PDF fills remaining space
            pdfSection
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
                    Button("Remove and Delete File", role: .destructive) {
                        viewModel.removePaper(id: paper.id, deleteFile: true)
                    }
                    Button("Remove from Library Only") {
                        viewModel.removePaper(id: paper.id, deleteFile: false)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Remove \"\(paper.title)\" from your library?")
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

            Text(paper.authorsDisplay)
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

            // Keywords (collapsible, editable)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Button {
                        withAnimation { keywordsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: keywordsExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Label("Keywords", systemImage: "tag")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if keywordsExpanded && !isEditingKeywords {
                        Button {
                            editingKeywordsText = paper.keywordList.joined(separator: ", ")
                            isEditingKeywords = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit keywords")
                    }
                }

                if keywordsExpanded {
                    if isEditingKeywords {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Enter keywords, separated by commas", text: $editingKeywordsText)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            HStack {
                                Button("Save") {
                                    let keywords = editingKeywordsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                    viewModel.updateKeywords(paperID: paper.id, keywords: keywords)
                                    isEditingKeywords = false
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                Button("Cancel") {
                                    isEditingKeywords = false
                                }
                                .controlSize(.small)
                            }
                        }
                    } else if paper.keywordList.isEmpty {
                        Button {
                            editingKeywordsText = ""
                            isEditingKeywords = true
                        } label: {
                            Text("Add keywords...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        .buttonStyle(.plain)
                    } else {
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
        }
    }

    // MARK: - Summary

    private var summaryCallout: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Button {
                        withAnimation { summaryExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: summaryExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Label("Summary", systemImage: "text.quote")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if summaryExpanded && !isEditingSummary {
                        Button {
                            editingSummaryText = paper.summary
                            isEditingSummary = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit summary")
                    }
                }

                if summaryExpanded {
                    if isEditingSummary {
                        VStack(alignment: .leading, spacing: 6) {
                            TextEditor(text: $editingSummaryText)
                                .font(.body)
                                .frame(minHeight: 80)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(Color(nsColor: .textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.secondary.opacity(0.3))
                                )
                            HStack {
                                Button("Save") {
                                    viewModel.updateSummary(paperID: paper.id, summary: editingSummaryText)
                                    isEditingSummary = false
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                Button("Cancel") {
                                    isEditingSummary = false
                                }
                                .controlSize(.small)
                            }
                        }
                    } else if paper.summary.isEmpty {
                        Button {
                            editingSummaryText = ""
                            isEditingSummary = true
                        } label: {
                            Text("Add summary...")
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(paper.summary)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(paper.summary.isEmpty && !isEditingSummary ? Color.secondary.opacity(0.05) : Color.accentColor.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - PDF

    private var pdfSection: some View {
        Group {
            if paper.pdfExists {
                PDFPreviewView(url: paper.pdfURL!)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.05))
            }
        }
    }

    // MARK: - Category Picker

    private var categoryPickerPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Change Category")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(viewModel.allCategories) { cat in
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
                    TextField("e.g. Finance/Banking", text: $newCategoryName)
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
        viewModel.movePaper(paper, toCategory: category)
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
