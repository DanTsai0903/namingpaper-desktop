import SwiftUI

struct MessageBubbleView: View {
    let message: ChatViewModel.DisplayMessage
    @State private var webViewHeight: CGFloat = 100

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 60)
                userBubble
            } else {
                assistantBubble
                Spacer(minLength: 60)
            }
        }
    }

    private var userBubble: some View {
        Text(message.content)
            .font(.body)
            .padding(10)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .textSelection(.enabled)
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.teal)
                .font(.caption)
                .frame(width: 20, height: 20)
                .padding(.top, 4)

            MarkdownLatexView(content: message.content, dynamicHeight: $webViewHeight)
                .frame(height: webViewHeight)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Citation Parsing & Rendering

struct CitationTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                FlowCitationText(segments: parseCitations(String(line)))
            }
        }
    }
}

struct FlowCitationText: View {
    let segments: [CitationSegment]

    var body: some View {
        // Use a wrapping HStack for inline text + clickable citation badges
        let textParts = segments
        WrappingHStack(alignment: .leading, spacing: 2) {
            ForEach(Array(textParts.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let str):
                    Text(str)
                        .font(.body)
                case .citation(let label, let page):
                    CitationBadge(label: label, page: page) { page in
                        NotificationCenter.default.post(name: .navigateToPage, object: nil, userInfo: ["page": page])
                    }
                }
            }
        }
    }
}

/// Simple wrapping horizontal layout for inline text + badges
struct WrappingHStack: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            let availableWidth = bounds.width - position.x
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: ProposedViewSize(width: availableWidth, height: nil))
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let availableWidth = maxWidth - x
            let size = subview.sizeThatFits(ProposedViewSize(width: availableWidth, height: nil))
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let finalSize = subview.sizeThatFits(ProposedViewSize(width: maxWidth - x, height: nil))
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, finalSize.height)
            x += finalSize.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

enum CitationSegment {
    case text(String)
    case citation(label: String, page: Int)
}

/// Parse [p.N], [p. N], [page N], [pp. N-M] patterns
func parseCitations(_ text: String) -> [CitationSegment] {
    let pattern = #"\[(?:pp?\.\s*(\d+)(?:-(\d+))?|page\s+(\d+))\]"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        return [.text(text)]
    }

    var segments: [CitationSegment] = []
    var lastEnd = text.startIndex
    let nsText = text as NSString

    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

    for match in matches {
        let matchRange = Range(match.range, in: text)!

        // Text before the citation
        if lastEnd < matchRange.lowerBound {
            segments.append(.text(String(text[lastEnd..<matchRange.lowerBound])))
        }

        let fullMatch = String(text[matchRange])

        // Extract page number
        var page = 0
        for groupIdx in 1..<match.numberOfRanges {
            if match.range(at: groupIdx).location != NSNotFound {
                let groupStr = nsText.substring(with: match.range(at: groupIdx))
                page = Int(groupStr) ?? 0
                break
            }
        }

        segments.append(.citation(label: fullMatch, page: page))
        lastEnd = matchRange.upperBound
    }

    if lastEnd < text.endIndex {
        segments.append(.text(String(text[lastEnd...])))
    }

    return segments.isEmpty ? [.text(text)] : segments
}

// MARK: - Citation Badge View (for clickable badges)

struct CitationBadge: View {
    let label: String
    let page: Int
    let action: (Int) -> Void

    var body: some View {
        Button {
            action(page)
        } label: {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.teal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
