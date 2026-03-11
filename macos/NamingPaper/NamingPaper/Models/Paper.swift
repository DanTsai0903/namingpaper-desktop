import Foundation

struct Paper: Identifiable, Hashable {
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

    var keywordList: [String] {
        guard !keywords.isEmpty else { return [] }
        return keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
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
