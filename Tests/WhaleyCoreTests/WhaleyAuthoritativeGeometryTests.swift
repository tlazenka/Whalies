import Foundation
import XCTest
@testable import WhaleyCore

final class WhaleyAuthoritativeGeometryTests: XCTestCase {
    typealias Snapshot = WhaleySceneSnapshot
    private func snapshot(_ live: [Snapshot.LiveEntity], session: String = "run-A",
                          player: Snapshot.PlayerGeometry? = nil) -> Snapshot {
        .init(sequence: 1, session: session, level: 2, gameTime: 3, dead: false,
              player: .init(x: 2, y: 3), elements: [], liveEntities: live,
              playerGeometry: player)
    }
    private func bubble(_ size: Double, id: String = "shot", role: Snapshot.BubbleRole? = .playerCreated) -> Snapshot.LiveEntity {
        .init(id: id, kind: .bubble, x: 4.25, y: 5.5,
              dimensions: .init(width: size, height: size), bubbleRole: role)
    }
    func testGrowthChangesDimensionsWithoutChangingCenterOrIdentity() {
        let a = WhaleyProjection3D.project(snapshot([bubble(0.5)])).objects[0]
        let b = WhaleyProjection3D.project(snapshot([bubble(2)])).objects[0]
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.center, b.center)
        XCTAssertEqual(b.size, .init(x: 2, y: 2, z: 2))
        XCTAssertEqual(a.bubbleRole, .playerCreated)
        XCTAssertEqual(b.bubbleRole, .playerCreated)
    }
    func testNonSquareTilesRetainIndependentXYDimensions() {
        let object = Snapshot.LiveEntity(id: "a", kind: .bubble, x: 2, y: 6,
            dimensions: .init(width: 2, height: 4), bubbleRole: .foundation)
        let result = WhaleyProjection3D.project(snapshot([object])).objects[0]
        XCTAssertEqual(result.center, .init(x: 2, y: 6, z: 0.46))
        XCTAssertEqual(result.size, .init(x: 2, y: 4, z: 2))
    }
    func testRolesAreExplicitNotInferredFromSize() {
        let objects = WhaleyProjection3D.project(snapshot([
            bubble(1, id: "foundation", role: .foundation),
            bubble(1, id: "shot", role: .playerCreated),
            bubble(1, id: "legacy", role: nil)])).objects
        XCTAssertEqual(objects.count, 3)
        XCTAssertEqual(objects.first { $0.id.hasSuffix(":foundation") }?.bubbleRole, .foundation)
        XCTAssertEqual(objects.first { $0.id.hasSuffix(":shot") }?.bubbleRole, .playerCreated)
        XCTAssertNil(objects.first { $0.id.hasSuffix(":legacy") }?.bubbleRole)
    }
    func testPlayerGeometryPreservesBottomAndSurvivesReplay() throws {
        let source = snapshot([], player: .init(x: 2.75, y: 6.75,
            dimensions: .init(width: 1.5, height: 1.5)))
        let replay = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(source))
        let player = WhaleyProjection3D.project(replay).player
        XCTAssertEqual(player.center.x, 2.75)
        XCTAssertEqual(player.center.y - player.size.y / 2, 6)
        XCTAssertEqual(player.size.x, 1.5)
        XCTAssertEqual(replay.player, .init(x: 2, y: 3))
    }
    func testLegacyJSONRemainsReadableWithFallbackDimensions() throws {
        let raw = """
        {"sequence":1,"session":"old","level":1,"gameTime":0,"dead":false,
         "player":{"x":0,"y":0},"elements":[],
         "liveEntities":[{"id":"b","kind":"bubble","x":3.25,"y":4.5}]}
        """
        let old = try JSONDecoder().decode(Snapshot.self, from: Data(raw.utf8))
        XCTAssertNil(old.playerGeometry)
        XCTAssertNil(old.liveEntities![0].dimensions)
        XCTAssertNil(old.liveEntities![0].bubbleRole)
        let projected = WhaleyProjection3D.project(old)
        XCTAssertEqual(projected.objects[0].size, .init(x: 0.66, y: 0.66, z: 0.66))
        XCTAssertEqual(projected.objects[0].center.x, 3.25)
    }
    func testFullJSONRoundTripIncludesDimensionsAndRoles() throws {
        let source = snapshot([bubble(2), bubble(0.66, id: "base", role: .foundation)])
        let data = try JSONEncoder().encode(source)
        XCTAssertEqual(try JSONDecoder().decode(Snapshot.self, from: data), source)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let live = try XCTUnwrap(json["liveEntities"] as? [[String: Any]])
        XCTAssertEqual(live[0]["bubbleRole"] as? String, "playerCreated")
        XCTAssertEqual((live[0]["dimensions"] as? [String: Double])?["width"], 2)
    }
    func testInvalidDimensionsNeverReachRenderer() {
        for value in [Double.nan, .infinity, -.infinity, 0, -1, .greatestFiniteMagnitude, .leastNonzeroMagnitude] {
            let object = Snapshot.LiveEntity(id: "bad", kind: .bubble, x: 2, y: 3,
                dimensions: .init(width: value, height: 1))
            let result = WhaleyProjection3D.project(snapshot([object])).objects[0]
            XCTAssertEqual(result.size, .init(x: 0.66, y: 0.66, z: 0.66))
        }
    }
    func testNonBubbleCannotAcquireBubbleRole() {
        let coin = Snapshot.LiveEntity(id: "coin", kind: .coin, x: 2, y: 3,
            dimensions: .init(width: 0.5, height: 0.75), bubbleRole: .foundation)
        let result = WhaleyProjection3D.project(snapshot([coin])).objects[0]
        XCTAssertNil(result.bubbleRole)
        XCTAssertEqual(result.size, .init(x: 0.5, y: 0.75, z: 0.20))
    }
    func testPopRemovesOnlyDisposableBubbleAndKeepsPlayerVisible() {
        let base = bubble(0.66, id: "base", role: .foundation)
        let before = WhaleyProjection3D.project(snapshot([base, bubble(2)]))
        let after = WhaleyProjection3D.project(snapshot([base]))
        XCTAssertEqual(before.renderObjects.count, 3)
        XCTAssertEqual(after.renderObjects.count, 2)
        XCTAssertEqual(after.renderObjects.filter { $0.kind == .player }.count, 1)
        XCTAssertEqual(after.objects[0].bubbleRole, .foundation)
    }
    func testSceneIdentityIsPreservedEvenForSameLevelRetry() {
        let a = WhaleyProjection3D.project(snapshot([bubble(1)], session: "first"))
        let b = WhaleyProjection3D.project(snapshot([bubble(1)], session: "retry"))
        XCTAssertEqual(a.level, b.level)
        XCTAssertNotEqual(a.session, b.session)
    }
    func testCellOnlySnapshotsRetainTheirGeometry() {
        let old = Snapshot(sequence: 1, session: "old", level: 1, gameTime: 0,
            dead: false, player: .init(x: 0, y: 0), elements: [.init(kind: .bubble, x: 4, y: 5)])
        let object = WhaleyProjection3D.project(old).objects[0]
        XCTAssertEqual(object.center, .init(x: 4.5, y: 5.5, z: 0.46))
        XCTAssertEqual(object.size.x, 0.66)
    }
    func testExplicitPlayerPositionRetainsAuthoritativeDimensions() {
        let source = snapshot([], player: .init(x: 3, y: 4,
            dimensions: .init(width: 1, height: 2)))
        let player = WhaleyProjection3D.project(source, precisePlayer: .init(x: 5, y: 6)).player
        XCTAssertEqual(player.center.x, 5)
        XCTAssertEqual(player.size.y, 2)
    }
    func testFloatOverflowCoordinatesAreNotRendered() {
        let bad = Snapshot.LiveEntity(id: "bad", kind: .bubble, x: .greatestFiniteMagnitude, y: 0)
        XCTAssertTrue(WhaleyProjection3D.project(snapshot([bad])).objects.isEmpty)
    }
    func testProjectionIsDeterministicAndDoesNotMutateSnapshot() {
        let source = snapshot([bubble(2)])
        let copy = source
        XCTAssertEqual(WhaleyProjection3D.project(source), WhaleyProjection3D.project(source))
        XCTAssertEqual(source, copy)
    }
}
