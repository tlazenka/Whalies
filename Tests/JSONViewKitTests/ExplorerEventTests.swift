#if canImport(UIKit) && os(iOS)
import Foundation
import Testing
@testable import JSONViewKit

@MainActor
@Test func explorerObserversBelongToTheirHostAndWorkWithoutPersistence() {
    let root = JSONNode.feed(items: [])
    var firstEvents: [String] = []
    var secondEvents: [String] = []
    let first = JSONNodeView(root: root, onEvent: { event, _ in firstEvents.append(event) })
    let second = JSONNodeView(root: root, onEvent: { event, _ in secondEvents.append(event) })

    first.record("filter_finished", properties: ["resultsAfter": 2])
    second.record("filter_cleared")
    first.record("filter_suggestion_selected")

    #expect(firstEvents == ["filter_finished", "filter_suggestion_selected"])
    #expect(secondEvents == ["filter_cleared"])
}
#endif
