import Foundation
import SwiftUI
import Observation

struct PaperTab: Identifiable, Hashable {
    let id: String  // paper ID
    let title: String
}

@Observable
class TabManager {
    var openTabs: [PaperTab] = []
    var activeTabID: String?

    func openTab(for paper: Paper) {
        // If already open, switch to it
        if openTabs.contains(where: { $0.id == paper.id }) {
            activeTabID = paper.id
            return
        }
        let tab = PaperTab(id: paper.id, title: paper.title)
        openTabs.append(tab)
        activeTabID = paper.id
    }

    func closeTab(id: String) {
        guard let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        openTabs.remove(at: idx)

        if activeTabID == id {
            if openTabs.isEmpty {
                activeTabID = nil
            } else {
                let newIdx = min(idx, openTabs.count - 1)
                activeTabID = openTabs[newIdx].id
            }
        }
    }

    func closeActiveTab() {
        guard let id = activeTabID else { return }
        closeTab(id: id)
    }

    func selectNextTab() {
        guard openTabs.count > 1, let current = activeTabID,
              let idx = openTabs.firstIndex(where: { $0.id == current }) else { return }
        let next = (idx + 1) % openTabs.count
        activeTabID = openTabs[next].id
    }

    func selectPreviousTab() {
        guard openTabs.count > 1, let current = activeTabID,
              let idx = openTabs.firstIndex(where: { $0.id == current }) else { return }
        let prev = idx == 0 ? openTabs.count - 1 : idx - 1
        activeTabID = openTabs[prev].id
    }
}
