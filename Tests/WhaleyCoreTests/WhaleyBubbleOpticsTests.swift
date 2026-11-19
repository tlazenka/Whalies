import XCTest
@testable import WhaleyCore

final class WhaleyBubbleOpticsTests: XCTestCase {
    private func world() -> WhaleyProjection3D.World {
        let snapshot = WhaleySceneSnapshot(
            sequence: 1, session: "optics", level: 1, gameTime: 0,
            dead: false, player: .init(x: 3, y: 4),
            elements: [
                .init(kind: .wall, x: 2, y: 2),
                .init(kind: .wall, x: 2, y: 3),
                .init(kind: .ground, x: 2, y: 1),
                .init(kind: .flame, x: 7, y: 3),
                .init(kind: .coin, x: 4, y: 8),
                .init(kind: .bubble, x: 1, y: 6),
                .init(kind: .goal, x: 9, y: 9)
            ])
        return WhaleyProjection3D.project(snapshot)
    }

    func testCameraIsInsideSphereLookingStraightUp() {
        let camera = WhaleyBubbleOptics.camera(for: world())
        XCTAssertEqual(camera.direction, .init(x: 0, y: 1, z: 0))
        XCTAssertEqual(camera.eye.x, camera.center.x)
        XCTAssertEqual(camera.eye.z, camera.center.z)
        XCTAssertEqual(camera.eye.y, camera.center.y - camera.radius * 0.80, accuracy: 1e-9)
        XCTAssertLessThan(abs(camera.eye.y - camera.center.y), camera.radius)
    }

    func testLandmarkSignalsCoverDistinctHazardAndSurfaceTypes() {
        let signals = WhaleyBubbleOptics.signals(for: world())
        let byID = Dictionary(uniqueKeysWithValues: signals.map { ($0.id, $0.kind) })
        XCTAssertEqual(byID["wall:2:2"], .wall)
        XCTAssertEqual(byID["wall:2:3"], .platform)
        XCTAssertEqual(byID["ground:2:1"], .ground)
        XCTAssertEqual(byID["flame:7:3"], .flame)
        XCTAssertEqual(byID["coin:4:8"], .coin)
        XCTAssertEqual(byID["bubble:1:6"], .bubble)
        XCTAssertEqual(byID["goal:9:9"], .goal)
    }

    func testEverySpotLiesJustInsideTheBubbleAndConservesEnergy() {
        let world = world()
        let camera = WhaleyBubbleOptics.camera(for: world)
        func distance(_ p: WhaleyProjection3D.Point, _ q: WhaleyProjection3D.Point) -> Double {
            sqrt(pow(p.x - q.x, 2) + pow(p.y - q.y, 2) + pow(p.z - q.z, 2))
        }
        for light in WhaleyBubbleOptics.signals(for: world) {
            XCTAssertEqual(distance(light.refractedSpot, camera.center),
                           camera.radius - 0.035, accuracy: 0.001)
            XCTAssertEqual(distance(light.reflectedSpot, camera.center),
                           camera.radius - 0.055, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(light.reflectance, 0)
            XCTAssertLessThanOrEqual(light.reflectance, 1)
            XCTAssertEqual(light.reflectance + light.transmission, 1, accuracy: 1e-10)
        }
    }

    func testProjectionIsStableAndReadOnly() {
        let projected = world()
        let before = projected
        let first = WhaleyBubbleOptics.signals(for: projected)
        let second = WhaleyBubbleOptics.signals(for: projected)
        XCTAssertEqual(first, second)
        XCTAssertEqual(before, projected)
        XCTAssertEqual(WhaleyBubbleOptics.signals(for: projected, maximum: 2).count, 2)
        XCTAssertTrue(WhaleyBubbleOptics.signals(for: projected, maximum: 0).isEmpty)
    }

    func testNearNormalTransmissionHasSmallButNonZeroReflection() {
        let snapshot = WhaleySceneSnapshot(
            sequence: 1, session: "normal", level: 1, gameTime: 0,
            dead: false, player: .init(x: 0, y: 0),
            elements: [.init(kind: .coin, x: 0, y: 30)])
        let sample = WhaleyBubbleOptics.signals(
            for: WhaleyProjection3D.project(snapshot)
        )[0]
        XCTAssertGreaterThan(sample.reflectance, 0)
        XCTAssertLessThan(sample.reflectance, 0.1)
        XCTAssertGreaterThan(sample.transmission, 0.9)
    }

    func testGrazingSightlineCanProduceTotalInternalReflection() {
        let snapshot = WhaleySceneSnapshot(
            sequence: 1, session: "grazing", level: 1, gameTime: 0,
            dead: false, player: .init(x: 0, y: 0),
            elements: [.init(kind: .coin, x: 1000, y: 0)])
        let sample = WhaleyBubbleOptics.signals(
            for: WhaleyProjection3D.project(snapshot)
        )[0]
        XCTAssertEqual(sample.reflectance, 1, accuracy: 1e-8)
        XCTAssertEqual(sample.transmission, 0, accuracy: 1e-8)
    }

    func testMovingOpticalSphereToJumpAnchorKeepsCameraInside() {
        let projected = world()
        let anchoredEye = WhaleyProjection3D.Point(x: 9, y: 3, z: 0.65)
        let camera = WhaleyBubbleOptics.camera(
            for: projected, trackingEye: anchoredEye
        )
        XCTAssertEqual(camera.eye, anchoredEye)
        XCTAssertEqual(camera.center.x, anchoredEye.x)
        XCTAssertGreaterThan(camera.center.y, anchoredEye.y)
        XCTAssertLessThan(camera.center.y - camera.eye.y, camera.radius)
        let lights = WhaleyBubbleOptics.signals(
            for: projected, trackingEye: anchoredEye
        )
        XCTAssertFalse(lights.isEmpty)
        for light in lights {
            let p = light.refractedSpot
            let distance = sqrt(
                pow(p.x - camera.center.x, 2) +
                pow(p.y - camera.center.y, 2) +
                pow(p.z - camera.center.z, 2)
            )
            XCTAssertEqual(distance, camera.radius - 0.035, accuracy: 0.001)
        }
    }
}
