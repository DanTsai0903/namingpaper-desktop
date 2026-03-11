import Foundation

struct Category: Identifiable, Hashable {
    let name: String
    let paperCount: Int

    var id: String { name }
}
