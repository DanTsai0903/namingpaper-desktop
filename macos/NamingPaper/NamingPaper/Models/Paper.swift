import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let namingpaperPaper = UTType(exportedAs: "com.namingpaper.paper")
}

struct Paper: Identifiable, Hashable, Codable, Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .namingpaperPaper)
    }
    let id: String
    let sha256: String
    let title: String
    let authors: String
    let authorsAll: String
    let year: Int?
    let journal: String
    let journalAbbrev: String
    let summary: String
    let keywords: String
    let category: String
    let filePath: String
    let confidence: Double?
    let createdAt: String
    let updatedAt: String

    var yearString: String {
        year.map(String.init) ?? ""
    }

    /// Display-friendly authors string (strips JSON array brackets/quotes)
    var authorsDisplay: String {
        parseJSONArray(authors)?.joined(separator: ", ") ?? authors
    }

    /// Display-friendly full authors string
    var authorsAllDisplay: String {
        parseJSONArray(authorsAll)?.joined(separator: ", ") ?? authorsAll
    }

    var keywordList: [String] {
        guard !keywords.isEmpty else { return [] }
        // Handle JSON array format
        if let parsed = parseJSONArray(keywords) {
            return parsed
        }
        return keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func parseJSONArray(_ str: String) -> [String]? {
        guard str.hasPrefix("["),
              let data = str.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return nil
        }
        return array
    }

    var pdfURL: URL? {
        let path = filePath
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    var pdfExists: Bool {
        guard let url = pdfURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
