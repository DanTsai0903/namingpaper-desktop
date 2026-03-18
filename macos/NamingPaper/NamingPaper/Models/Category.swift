import Foundation

struct Category: Identifiable, Hashable {
    let name: String
    let paperCount: Int

    var id: String { name }
}

/// A node in the category tree, built from flat "parent/child" category names.
struct CategoryNode: Identifiable {
    let segment: String       // Display name for this level (e.g. "Econometrics")
    let fullPath: String      // Full category path (e.g. "Economics/Econometrics")
    let paperCount: Int       // Papers directly in this category
    var children: [CategoryNode]

    var id: String { fullPath }

    /// Total papers in this node and all descendants.
    var totalPaperCount: Int {
        paperCount + children.reduce(0) { $0 + $1.totalPaperCount }
    }

    /// Build a tree from a flat list of categories.
    static func buildTree(from categories: [Category]) -> [CategoryNode] {
        buildTree(from: categories, pathPrefix: "")
    }

    private static func buildTree(from categories: [Category], pathPrefix: String) -> [CategoryNode] {
        var rootMap: [String: [Category]] = [:]
        var rootCounts: [String: Int] = [:]

        for cat in categories {
            let parts = cat.name.split(separator: "/", maxSplits: 1)
            let root = String(parts[0])

            if parts.count == 1 {
                rootCounts[root, default: 0] += cat.paperCount
            } else {
                let remainder = String(parts[1])
                let child = Category(name: remainder, paperCount: cat.paperCount)
                rootMap[root, default: []].append(child)
            }
        }

        var rootNames: [String] = []
        var seen = Set<String>()
        for cat in categories {
            let root = String(cat.name.split(separator: "/", maxSplits: 1)[0])
            if seen.insert(root).inserted {
                rootNames.append(root)
            }
        }

        return rootNames.map { root in
            let fullPath = pathPrefix.isEmpty ? root : "\(pathPrefix)/\(root)"
            let children = rootMap[root].map { buildTree(from: $0, pathPrefix: fullPath) } ?? []
            return CategoryNode(
                segment: root,
                fullPath: fullPath,
                paperCount: rootCounts[root, default: 0],
                children: children
            )
        }
    }
}
