import XCTest
@testable import WhaleyCore

final class WhaleyProjection3DTests: XCTestCase {
    func testTileCoordinatesStayInXYPlaneWhileDepthIsPresentationOnly() {
        let snapshot = WhaleySceneSnapshot(
            sequence: 5, session: "demo", level: 2, gameTime: 3.5,
            dead: false, player: .init(x: 7, y: 9),
            elements: [.init(kind: .wall, x: 4, y: 8),
                       .init(kind: .coin, x: 6, y: 10)]
        )
        let world = WhaleyProjection3D.project(snapshot)
        XCTAssertEqual(world.level, 2)
        XCTAssertEqual(world.gameTime, 3.5)
        XCTAssertEqual(world.player.center, .init(x: 7.5, y: 9.5, z: 0.65))
        XCTAssertEqual(world.cameraFocus, world.player.center)
        XCTAssertEqual(world.objects.first(where: { $0.id == "wall:4:8" })?.center,
                       .init(x: 4.5, y: 8.5, z: -0.15))
        XCTAssertEqual(world.objects.first(where: { $0.id == "coin:6:10" })?.center,
                       .init(x: 6.5, y: 10.5, z: 0.48))
    }

    func testStableIDsAndOrderIgnoreInputElementOrderAndDuplicates() {
        let elements: [WhaleySceneSnapshot.Element] = [
            .init(kind: .bubble, x: 3, y: 4),
            .init(kind: .flame, x: 5, y: 2),
            .init(kind: .bubble, x: 3, y: 4),
        ]
        func snapshot(_ items: [WhaleySceneSnapshot.Element]) -> WhaleySceneSnapshot {
            .init(sequence: 1, session: "s", level: 1, gameTime: 0, dead: false,
                  player: .init(x: 0, y: 0), elements: items)
        }
        let forward = WhaleyProjection3D.project(snapshot(elements))
        let reverse = WhaleyProjection3D.project(snapshot(Array(elements.reversed())))
        XCTAssertEqual(forward.objects, reverse.objects)
        XCTAssertEqual(forward.objects.count, 2)
        XCTAssertEqual(Set(forward.objects.map(\.id)).count, 2)
    }

    func testContinuousPlayerPositionDoesNotChangeCellObjects() {
        let snapshot = WhaleySceneSnapshot(sequence: 1, session: "s", level: 1,
            gameTime: 0, dead: false, player: .init(x: 2, y: 4),
            elements: [.init(kind: .ground, x: 2, y: 3)])
        let coarse = WhaleyProjection3D.project(snapshot)
        let smooth = WhaleyProjection3D.project(snapshot,
            precisePlayer: .init(x: 2.125, y: 4.875))
        XCTAssertEqual(smooth.player.center, .init(x: 2.125, y: 4.875, z: 0.65))
        XCTAssertEqual(coarse.objects, smooth.objects)
        let invalid = WhaleyProjection3D.project(snapshot,
            precisePlayer: .init(x: .nan, y: .infinity))
        XCTAssertEqual(invalid.player.center, coarse.player.center)
    }

    func testMovingBubblesKeepIdentityAcrossTileBoundaries() {
        func frame(x: Double, y: Double) -> WhaleyProjection3D.World {
            let source = WhaleySceneSnapshot(
                sequence: 1, session: "s", level: 1, gameTime: x,
                dead: false, player: .init(x: 0, y: 0),
                elements: [.init(kind: .bubble, x: Int(x), y: Int(y))],
                liveEntities: [.init(id: "bubble-42", kind: .bubble, x: x, y: y)]
            )
            return WhaleyProjection3D.project(source)
        }
        let before = frame(x: 3.9, y: 4.2)
        let after = frame(x: 4.1, y: 4.4)
        XCTAssertEqual(before.objects.map(\.id), ["live:bubble:bubble-42"])
        XCTAssertEqual(after.objects.map(\.id), before.objects.map(\.id))
        XCTAssertEqual(before.objects[0].center.x, 3.9)
        XCTAssertEqual(after.objects[0].center.x, 4.1)
        XCTAssertEqual(after.objects[0].center.y, 4.4)
    }

    func testMultipleObjectsInSameCellRemainDistinct() {
        let snapshot = WhaleySceneSnapshot(
            sequence: 1, session: "s", level: 1, gameTime: 0,
            dead: false, player: .init(x: 0, y: 0),
            elements: [.init(kind: .bubble, x: 1, y: 1)],
            liveEntities: [
                .init(id: "1", kind: .bubble, x: 1.15, y: 1.35),
                .init(id: "2", kind: .bubble, x: 1.25, y: 1.40),
            ]
        )
        let world = WhaleyProjection3D.project(snapshot)
        XCTAssertEqual(world.objects.map(\.id), ["live:bubble:1", "live:bubble:2"])
        XCTAssertEqual(world.objects.count, 2)
    }

    func testEmptyLiveEntitiesSuppressStaleCellBasedDynamicObjects() {
        let snapshot = WhaleySceneSnapshot(
            sequence: 1, session: "s", level: 1, gameTime: 0,
            dead: false, player: .init(x: 0, y: 0),
            elements: [.init(kind: .wall, x: 0, y: 0),
                       .init(kind: .coin, x: 1, y: 2)],
            liveEntities: []
        )
        XCTAssertEqual(WhaleyProjection3D.project(snapshot).objects.map(\.id), ["wall:0:0"])
    }

    func testLegacySnapshotDecodesWithoutLiveEntities() throws {
        let raw = """
        {"sequence":1,"session":"x","level":1,"gameTime":0,"dead":false,
         "player":{"x":0,"y":0},"elements":[{"kind":"bubble","x":3,"y":4}]}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(WhaleySceneSnapshot.self, from: raw)
        XCTAssertNil(snapshot.liveEntities)
        XCTAssertEqual(WhaleyProjection3D.project(snapshot).objects.map(\.id), ["bubble:3:4"])
        let roundTrip = try JSONDecoder().decode(WhaleySceneSnapshot.self,
                                                  from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(roundTrip, snapshot)
    }

    func testInvalidContinuousDataIsRejected() {
        let snapshot = WhaleySceneSnapshot(
            sequence: 1, session: "s", level: 1, gameTime: 0,
            dead: false, player: .init(x: 0, y: 0), elements: [],
            liveEntities: [.init(id: "", kind: .bubble, x: 1, y: 1),
                           .init(id: "valid", kind: .coin, x: 2.1, y: 3.1),
                           .init(id: "infinity", kind: .flame, x: .infinity, y: 0)]
        )
        XCTAssertEqual(WhaleyProjection3D.project(snapshot).objects.map(\.id), ["live:coin:valid"])
    }

    func testPreciseEntitiesSurviveJSONRoundTrip() throws {
        let source = WhaleySceneSnapshot(
            sequence: 7, session: "replay", level: 3, gameTime: 2.5,
            dead: false, player: .init(x: 0, y: 1),
            elements: [.init(kind: .wall, x: 4, y: 5)],
            liveEntities: [.init(id: "stable-19", kind: .coin, x: 7.125, y: 8.875)]
        )
        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(WhaleySceneSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, source)
        XCTAssertEqual(decoded.liveEntities?.first?.id, "stable-19")
        XCTAssertEqual(
            WhaleyProjection3D.project(decoded).objects.map(\.id),
            ["live:coin:stable-19", "wall:4:5"]
        )
    }

    func testProjectionNeverChangesAuthoritativeSnapshot() {
        let original = WhaleySceneSnapshot(
            sequence: 9, session: "s", level: 3,
            gameTime: 2, dead: true, player: .init(x: -4, y: 1),
            elements: [.init(kind: .goal, x: 20, y: 6)]
        )
        let copy = original
        let projected = WhaleyProjection3D.project(original)
        XCTAssertEqual(original, copy)
        XCTAssertEqual(projected.player.center.x, -3.5)
        XCTAssertEqual(projected.objects.first?.kind, .goal)
    }
}
