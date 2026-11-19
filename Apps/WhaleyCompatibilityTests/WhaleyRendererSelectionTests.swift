import XCTest
import RealityKit
import WhaleyCore

@MainActor
final class WhaleyRendererSelectionTests: XCTestCase {
    typealias P = WhaleyProjection3D
    private func world(session: String = "s", role: WhaleySceneSnapshot.BubbleRole? = .playerCreated,
                       includeBubble: Bool = true, diameter: Double = 1) -> P.World {
        .init(level: 1, gameTime: 0,
            player: .init(id: "player", kind: .player, center: .init(x: 0, y: 3, z: 0.65),
                          size: .init(x: 1, y: 1, z: 0.72)),
            objects: includeBubble ? [
                .init(id: "live:bubble:42", kind: .bubble, center: .init(x: 0, y: 2, z: 0.46),
                      size: .init(x: diameter, y: diameter, z: diameter), bubbleRole: role)
            ] : [], session: session)
    }

    func testBodiesHaveInputShapesButNoIndependentPhysics() throws {
        let renderer = WhaleyRealityProjectionRenderer()
        renderer.render(world(), trackingEye: nil)
        let bubble = try XCTUnwrap(renderer.root.findEntity(named: "live:bubble:42"))
        XCTAssertNotNil(bubble.components[InputTargetComponent.self])
        let shape = try XCTUnwrap(bubble.components[CollisionComponent.self])
        XCTAssertEqual(shape.filter.group, CollisionGroup(rawValue: 0))
        XCTAssertEqual(shape.filter.mask, CollisionGroup(rawValue: 0))
        XCTAssertNil(bubble.components[PhysicsBodyComponent.self])
        XCTAssertEqual(renderer.pressTarget(for: bubble),
                       .bubble(session: "s", projectileID: "42", canGrow: true))
        let shell = try XCTUnwrap(renderer.root.findEntity(named: "Unbreakable Optical Bubble"))
        XCTAssertNil(shell.components[InputTargetComponent.self])
        XCTAssertNil(shell.components[CollisionComponent.self])
    }

    func testGrowthPreservesEntityIdentityAndResizesItsInputSpace() throws {
        let renderer = WhaleyRealityProjectionRenderer()
        renderer.render(world(), trackingEye: nil)
        let before = try XCTUnwrap(renderer.root.findEntity(named: "live:bubble:42"))
        renderer.render(world(diameter: 2.2), trackingEye: nil)
        let after = try XCTUnwrap(renderer.root.findEntity(named: "live:bubble:42"))
        XCTAssertTrue(before === after)
        XCTAssertEqual(after.scale.x, 2.2, accuracy: 0.00001)
        XCTAssertEqual(after.scale.y, 2.2, accuracy: 0.00001)
        XCTAssertNotNil(after.components[CollisionComponent.self])
    }

    func testFoundationAndNonBubbleRouting() throws {
        let renderer = WhaleyRealityProjectionRenderer()
        renderer.render(world(role: .foundation), trackingEye: nil)
        let foundation = try XCTUnwrap(renderer.root.findEntity(named: "live:bubble:42"))
        XCTAssertEqual(renderer.pressTarget(for: foundation),
                       .bubble(session: "s", projectileID: "42", canGrow: false))
        let player = try XCTUnwrap(renderer.root.findEntity(named: "player"))
        XCTAssertEqual(renderer.pressTarget(for: player), .body(session: "s"))
    }

    func testPoppedAndReplacedEntitiesRejectLateGestureValues() throws {
        let renderer = WhaleyRealityProjectionRenderer()
        renderer.render(world(), trackingEye: nil)
        let old = try XCTUnwrap(renderer.root.findEntity(named: "live:bubble:42"))
        renderer.render(world(includeBubble: false), trackingEye: nil)
        XCTAssertEqual(renderer.pressTarget(for: old), .unavailable)
        renderer.render(world(session: "new"), trackingEye: nil)
        let new = try XCTUnwrap(renderer.root.findEntity(named: "live:bubble:42"))
        XCTAssertFalse(old === new)
        XCTAssertEqual(renderer.pressTarget(for: old), .unavailable)
        XCTAssertEqual(renderer.pressTarget(for: new),
                       .bubble(session: "new", projectileID: "42", canGrow: true))
    }
}
