import Foundation
import JSONViewKit
import Testing

@Test func sharedExplorerFiltersMomentItemsWithoutLosingTheirIDs() throws {
    let root = JSONNode.feed(items: [
        ["id": "moment/0", "properties": ["kind": "doll", "points": 0]],
        ["id": "moment/2", "properties": ["kind": "bounce", "points": 20]],
        ["id": "moment/3", "properties": ["kind": "bounce", "points": 30]],
    ])
    let model = JSONNodeViewModel(root: root)
    let initial = try #require(model.initialFilter(path: "$.properties.points", value: .number("20")))
    let scrubbed = try #require(root.filtering(model.adjusted(initial, translationX: 28)))
    #expect(JSONNode.itemIDs(in: scrubbed, from: root) == ["moment/3"])

    // A categorical projection drops each item's id leaf; identity still comes from the original document.
    let faceted = try #require(root.filtering(fieldName: "kind", categoricalValue: "bounce"))
    #expect(JSONNode.itemIDs(in: faceted, from: root) == ["moment/2", "moment/3"])
    #expect(model.featureRelativePath(from: "$.items[1].properties.points") == "$.properties.points")
    #expect(model.numericValues(at: "$.properties.points") == [0, 20, 30])
}

@Test func sharedExplorerKeepsWhaleyDocumentAndCommandSemantics() throws {
    let root = JSONNode.feed(items: [
        ["id": "run-1", "type": "recorded-run", "properties": ["level": 1]],
        ["id": "live-world", "type": "live-world", "properties": ["level": 2]],
    ], type: "whaley")
    let filter = FieldFilter.minimum(path: "$.properties.level", value: 2, values: [1, 2])
    let shown = try #require(root.filtering(filter))
    #expect(JSONNode.itemIDs(in: shown, from: root) == ["live-world"])
    #expect(dockerCommand(for: filter) == "swift run whaley query --file whaley-data.json '$.properties.level >= 2.0'")
    #expect(JSONNodeViewModel(root: root).featureNodes().count == 2)
}

@Test func explorerIdentityFallsBackToTheOriginalItemPath() throws {
    let root = JSONNode.feed(items: [
        ["properties": ["kind": "ignored"]],
        ["properties": ["kind": "selected"]],
    ])
    let shown = try #require(root.filtering(fieldName: "kind", categoricalValue: "selected"))
    #expect(JSONNode.itemIDs(in: shown, from: root) == ["$.items[1]"])
}
