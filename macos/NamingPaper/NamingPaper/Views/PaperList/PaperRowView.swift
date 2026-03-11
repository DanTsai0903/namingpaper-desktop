import SwiftUI

struct PaperRowView: View {
    let paper: Paper
    let isStarred: Bool
    var highlightTerms: [String] = []
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? .yellow : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)

            if highlightTerms.isEmpty {
                Text(paper.title)
                    .lineLimit(1)
            } else {
                Text(highlightedText(paper.title, terms: highlightTerms))
                    .lineLimit(1)
            }
        }
    }

    private func highlightedText(_ text: String, terms: [String]) -> AttributedString {
        var attributed = AttributedString(text)
        let lowerText = text.lowercased()
        for term in terms where !term.isEmpty {
            let lowerTerm = term.lowercased()
            var searchStart = lowerText.startIndex
            while let range = lowerText.range(of: lowerTerm, range: searchStart..<lowerText.endIndex) {
                let attrStart = AttributedString.Index(range.lowerBound, within: attributed)
                let attrEnd = AttributedString.Index(range.upperBound, within: attributed)
                if let attrStart, let attrEnd {
                    attributed[attrStart..<attrEnd].foregroundColor = .accentColor
                    attributed[attrStart..<attrEnd].font = .body.bold()
                }
                searchStart = range.upperBound
            }
        }
        return attributed
    }
}
