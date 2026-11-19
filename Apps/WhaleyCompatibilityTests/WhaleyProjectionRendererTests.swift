import XCTest
import RealityKit
import WhaleyCore

final class WhaleyProjectionRendererTests: XCTestCase {
    @MainActor private func world(size: Double, session: String = "run", includeShot: Bool = true) -> WhaleyProjection3D.World {
        let entities: [WhaleySceneSnapshot.LiveEntity] = includeShot ? [
            .init(id: "b", kind: .bubble, x: 4, y: 5,
                  dimensions: .init(width: size, height: size), bubbleRole: .playerCreated)
        ] : []
        return WhaleyProjection3D.project(.init(sequence: 1, session: session, level: 1,
            gameTime: 0, dead: false, player: .init(x: 0, y: 0), elements: [], liveEntities: entities))
    }
    @MainActor func testGrowthUpdatesExistingRealityKitEntityAndScale() throws {
        let renderer = WhaleyRealityProjectionRenderer()
        renderer.render(world(size: 0.5), trackingEye: nil)
        let first = try XCTUnwrap(renderer.root.children.first { $0.name == "live:bubble:b" })
        let position = first.position
        renderer.render(world(size: 2), trackingEye: nil)
        let second = try XCTUnwrap(renderer.root.children.first { $0.name == "live:bubble:b" })
        XCTAssertTrue(first === second)
        XCTAssertEqual(second.position, position)
        XCTAssertEqual(second.scale, SIMD3<Float>(repeating: 2))
        renderer.render(world(size: 0.75), trackingEye: nil)
        XCTAssertEqual(second.scale, SIMD3<Float>(repeating: 0.75))
    }
    @MainActor func testPopRemovesBubbleButNotPlayer() throws {
        let renderer = WhaleyRealityProjectionRenderer()
        renderer.render(world(size: 1), trackingEye: nil)
        renderer.render(world(size: 1, includeShot: false), trackingEye: nil)
        XCTAssertNil(renderer.root.children.first { $0.name == "live:bubble:b" })
        XCTAssertNotNil(renderer.root.children.first { $0.name == "player" })
    }
    @MainActor func testSameLevelRetryReplacesOldSessionEntities() throws {
        let renderer = WhaleyRealityProjectionRenderer()
        renderer.render(world(size: 1, session: "first"), trackingEye: nil)
        let first = try XCTUnwrap(renderer.root.children.first { $0.name == "live:bubble:b" })
        renderer.render(world(size: 2, session: "retry"), trackingEye: nil)
        let next = try XCTUnwrap(renderer.root.children.first { $0.name == "live:bubble:b" })
        XCTAssertFalse(first === next)
        XCTAssertNil(first.parent)
    }
}
