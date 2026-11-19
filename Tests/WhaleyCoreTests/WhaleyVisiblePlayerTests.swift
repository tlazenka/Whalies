import XCTest
@testable import WhaleyCore

final class WhaleyVisiblePlayerTests: XCTestCase {
    private func frame(y: Double, bubbles: [WhaleySceneSnapshot.LiveEntity] = []) -> WhaleyProjection3D.World {
        let snapshot = WhaleySceneSnapshot(sequence: 0, session: "visible-player", level: 1,
            gameTime: 0, dead: false, player: .init(x: 3, y: Int(y)),
            elements: [.init(kind: .ground, x: 3, y: 0)], liveEntities: bubbles)
        return WhaleyProjection3D.project(snapshot, precisePlayer: .init(x: 3.5, y: y))
    }

    func testRenderListIncludesPlayerExactlyOnceEvenWithoutBubbles() {
        let world = frame(y: 2)
        XCTAssertEqual(world.renderObjects.filter { $0.kind == .player }, [world.player])
        XCTAssertEqual(world.renderObjects.first?.id, "player")
        XCTAssertEqual(world.renderObjects.count, world.objects.count + 1)
    }

    func testPlayerMovesInRenderListWhileCameraStaysAtJumpOrigin() throws {
        var camera = Whaley3DJumpCamera()
        let anchor = WhaleyProjection3D.Point(x: 3.5, y: 1.5, z: 0.65)
        // These are input frames, not a physics simulation: test that the renderer
        // receives the real player's changing position independently of the camera.
        for height in [2.0, 3.5, 5.0, 3.5, 2.0] {
            let world = frame(y: height)
            let player = try XCTUnwrap(world.renderObjects.first { $0.kind == .player })
            let eye = camera.update(playerBottom: .init(x: 3.5, y: height - 0.5, z: 0.65),
                airborne: true, jumpSequence: 1, jumpStartBottom: anchor, deltaSeconds: 1.0 / 30)
            XCTAssertEqual(player.center.y, height)
            XCTAssertEqual(eye, anchor)
            XCTAssertNotEqual(player.center, eye)
        }
    }

    func testRepeatedJumpFramesRetainPlayerAndFoundationIdentity() throws {
        let bubbles: [WhaleySceneSnapshot.LiveEntity] = [
            .init(id: "foundation-1", kind: .bubble, x: 3.5, y: 1.33)
        ]
        var camera = Whaley3DJumpCamera()
        let anchor = WhaleyProjection3D.Point(x: 3.5, y: 1.5, z: 0.65)
        var previousScenery: [WhaleyProjection3D.Object]?
        for jump in 1...4 {
            for height in [2.0, 4.8, 2.0] {
                let world = frame(y: height, bubbles: bubbles)
                let player = try XCTUnwrap(world.renderObjects.first { $0.kind == .player })
                XCTAssertEqual(player.id, "player")
                XCTAssertEqual(player.center.y, height)
                if let previousScenery { XCTAssertEqual(world.objects, previousScenery) }
                previousScenery = world.objects
                _ = camera.update(playerBottom: .init(x: 3.5, y: height - 0.5, z: 0.65),
                    airborne: true, jumpSequence: UInt64(jump), jumpStartBottom: anchor,
                    deltaSeconds: 1.0 / 30)
                XCTAssertEqual(camera.eye, anchor)
                XCTAssertTrue(world.renderObjects.contains { $0.id == "live:bubble:foundation-1" })
            }
        }
    }

    func testPoppedBubbleDisappearsWithoutRemovingWhaley() {
        let before = frame(y: 2, bubbles: [.init(id: "shot", kind: .bubble, x: 3.5, y: 1.33)])
        let after = frame(y: 3)
        XCTAssertTrue(before.renderObjects.contains { $0.id == "live:bubble:shot" })
        XCTAssertFalse(after.renderObjects.contains { $0.id == "live:bubble:shot" })
        XCTAssertEqual(before.renderObjects.first?.id, after.renderObjects.first?.id)
        XCTAssertEqual(after.renderObjects.first?.center.y, 3)
    }
}
