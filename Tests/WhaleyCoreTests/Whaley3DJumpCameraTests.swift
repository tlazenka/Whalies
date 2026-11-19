import XCTest
@testable import WhaleyCore

final class Whaley3DJumpCameraTests: XCTestCase {
    typealias Point = WhaleyProjection3D.Point
    private let origin = Point(x: 3, y: 2, z: 0.65)
    private let next = Point(x: 7, y: 11, z: 0.65)

    func testTracksBottomWhileGrounded() {
        var rig = Whaley3DJumpCamera()
        XCTAssertEqual(rig.update(playerBottom: origin, airborne: false,
            jumpSequence: 0, jumpStartBottom: origin, deltaSeconds: 0), origin)
        let result = rig.update(playerBottom: next, airborne: false,
            jumpSequence: 0, jumpStartBottom: next, deltaSeconds: 0.1)
        XCTAssertGreaterThan(result.x, origin.x)
        XCTAssertLessThan(result.x, next.x)
        XCTAssertNil(rig.anchoredStart)
    }

    func testAscentAndDescentRetainTheSameJumpAnchor() {
        var rig = Whaley3DJumpCamera()
        _ = rig.update(playerBottom: origin, airborne: false,
            jumpSequence: 0, jumpStartBottom: origin, deltaSeconds: 0)
        for height in [4.0, 8, 15, 10, 6, 3] {
            let result = rig.update(playerBottom: Point(x: 9, y: height, z: 0.65),
                airborne: true, jumpSequence: 1, jumpStartBottom: origin, deltaSeconds: 0.033)
            XCTAssertEqual(result, origin)
            XCTAssertEqual(rig.anchoredStart, origin)
        }
    }

    func testNextBounceSmoothlyReanchors() {
        var rig = Whaley3DJumpCamera()
        _ = rig.update(playerBottom: origin, airborne: true,
            jumpSequence: 1, jumpStartBottom: origin, deltaSeconds: 0)
        let result = rig.update(playerBottom: Point(x: 7, y: 19, z: 0.65),
            airborne: true, jumpSequence: 2, jumpStartBottom: next, deltaSeconds: 0.033)
        XCTAssertEqual(rig.anchoredStart, next)
        XCTAssertGreaterThan(result.y, origin.y)
        XCTAssertLessThan(result.y, next.y)
        for _ in 0..<60 {
            _ = rig.update(playerBottom: Point(x: 7, y: 19, z: 0.65),
                airborne: true, jumpSequence: 2, jumpStartBottom: next, deltaSeconds: 0.033)
        }
        XCTAssertEqual(rig.eye!.y, next.y, accuracy: 0.01)
    }

    func testLandingReleasesAnchorAndResumesTracking() {
        var rig = Whaley3DJumpCamera()
        _ = rig.update(playerBottom: origin, airborne: true,
            jumpSequence: 1, jumpStartBottom: origin, deltaSeconds: 0)
        let result = rig.update(playerBottom: next, airborne: false,
            jumpSequence: 1, jumpStartBottom: origin, deltaSeconds: 0.1)
        XCTAssertNil(rig.anchoredStart)
        XCTAssertGreaterThan(result.y, origin.y)
        XCTAssertLessThan(result.y, next.y)
    }

    func testZeroDurationDoesNotSnapOnNextBounce() {
        var rig = Whaley3DJumpCamera()
        _ = rig.update(playerBottom: origin, airborne: false,
            jumpSequence: 0, jumpStartBottom: origin, deltaSeconds: 0)
        XCTAssertEqual(rig.update(playerBottom: next, airborne: true,
            jumpSequence: 1, jumpStartBottom: next, deltaSeconds: 0), origin)
    }

    func testFallingBeforeFirstJumpDoesNotInventAnAnchor() {
        var rig = Whaley3DJumpCamera()
        let result = rig.update(playerBottom: next, airborne: true,
            jumpSequence: 0, jumpStartBottom: origin, deltaSeconds: 0)
        XCTAssertNil(rig.anchoredStart)
        XCTAssertEqual(result, next)
    }

    func testSameLevelRestartDiscardsOldJump() {
        var rig = Whaley3DJumpCamera()
        _ = rig.update(playerBottom: next, airborne: true,
            jumpSequence: 5, jumpStartBottom: next, deltaSeconds: 0)
        let result = rig.update(playerBottom: origin, airborne: true,
            jumpSequence: 0, jumpStartBottom: Point(x: 0, y: 0, z: 0), deltaSeconds: 0.033)
        XCTAssertEqual(result, origin)
        XCTAssertNil(rig.anchoredStart)
        XCTAssertEqual(rig.lastJumpSequence, 0)
    }

    func testAnchorCannotDriftWithinTheSameJump() {
        var rig = Whaley3DJumpCamera()
        _ = rig.update(playerBottom: origin, airborne: true,
            jumpSequence: 1, jumpStartBottom: origin, deltaSeconds: 0)
        XCTAssertEqual(rig.update(playerBottom: next, airborne: true,
            jumpSequence: 1, jumpStartBottom: next, deltaSeconds: 0.1), origin)
        XCTAssertEqual(rig.anchoredStart, origin)
    }

    func testNonfinitePlayerCaptureDoesNotConsumeNewJump() {
        var rig = Whaley3DJumpCamera()
        _ = rig.update(playerBottom: origin, airborne: false,
            jumpSequence: 0, jumpStartBottom: origin, deltaSeconds: 0)
        let result = rig.update(playerBottom: Point(x: .nan, y: 1, z: 0),
            airborne: true, jumpSequence: 1, jumpStartBottom: next, deltaSeconds: 0.1)
        XCTAssertEqual(result, origin)
        XCTAssertEqual(rig.lastJumpSequence, 0)
        _ = rig.update(playerBottom: next, airborne: true,
            jumpSequence: 1, jumpStartBottom: next, deltaSeconds: 0.1)
        XCTAssertEqual(rig.anchoredStart, next)
    }

    func testNonfiniteAnchorFallsBackToValidPlayerBottom() {
        var rig = Whaley3DJumpCamera()
        let result = rig.update(playerBottom: origin, airborne: true,
            jumpSequence: 1, jumpStartBottom: Point(x: .infinity, y: 2, z: 0), deltaSeconds: 0)
        XCTAssertEqual(result, origin)
        XCTAssertEqual(rig.anchoredStart, origin)
    }

    func testInvalidFrameDurationsDoNotMoveCamera() {
        var rig = Whaley3DJumpCamera()
        _ = rig.update(playerBottom: origin, airborne: false,
            jumpSequence: 0, jumpStartBottom: origin, deltaSeconds: 0)
        for dt in [Double.nan, .infinity, -1] {
            XCTAssertEqual(rig.update(playerBottom: next, airborne: true,
                jumpSequence: 1, jumpStartBottom: next, deltaSeconds: dt), origin)
        }
    }

    func testExplicitResetAndEnteringMidJump() {
        var rig = Whaley3DJumpCamera()
        _ = rig.update(playerBottom: origin, airborne: true,
            jumpSequence: 3, jumpStartBottom: origin, deltaSeconds: 0)
        rig.reset()
        XCTAssertNil(rig.eye)
        XCTAssertNil(rig.lastJumpSequence)
        XCTAssertEqual(rig.update(playerBottom: Point(x: 7, y: 20, z: 0.65),
            airborne: true, jumpSequence: 4, jumpStartBottom: next, deltaSeconds: 0), next)
    }

    func testSmoothingIsFrameRateIndependentForNormalFrameIntervals() {
        var slow = Whaley3DJumpCamera()
        var fast = Whaley3DJumpCamera()
        _ = slow.update(playerBottom: origin, airborne: false,
            jumpSequence: 0, jumpStartBottom: origin, deltaSeconds: 0)
        _ = fast.update(playerBottom: origin, airborne: false,
            jumpSequence: 0, jumpStartBottom: origin, deltaSeconds: 0)
        _ = slow.update(playerBottom: next, airborne: true,
            jumpSequence: 1, jumpStartBottom: next, deltaSeconds: 0.1)
        for _ in 0..<2 {
            _ = fast.update(playerBottom: next, airborne: true,
                jumpSequence: 1, jumpStartBottom: next, deltaSeconds: 0.05)
        }
        XCTAssertEqual(slow.eye!.x, fast.eye!.x, accuracy: 1e-12)
        XCTAssertEqual(slow.eye!.y, fast.eye!.y, accuracy: 1e-12)
    }
}
