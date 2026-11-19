import Foundation
import Testing
@testable import WhaleyCore

@Test func whaleyJSONDocumentExposesRunsAndLiveWorld() throws {
    let snapshot = WhaleySceneSnapshot(
        sequence: 1, session: "test", level: 2, gameTime: 3,
        dead: false, player: .init(x: 1, y: 2),
        elements: [.init(kind: .coin, x: 3, y: 4)]
    )
    let run = WhaleyRecordedRun(
        id: UUID(), level: 2, startedAt: Date(timeIntervalSince1970: 0),
        endedAt: nil, samples: [], inputs: []
    )
    let data = try WhaleyJSONDocument.data(snapshot: snapshot, runs: [run])
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let items = try #require(object["items"] as? [[String: Any]])
    #expect(items.count == 3)
    #expect(items.contains { ($0["type"] as? String) == "recorded-run" })
    #expect(items.contains { ($0["type"] as? String) == "live-world" })
    #expect(items.contains { ($0["type"] as? String) == "map-cell" })
}
