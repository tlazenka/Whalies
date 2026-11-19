import Foundation
import XCTest
@testable import WhaleyCore

final class SceneScrubHUDPlacementTests: XCTestCase {
    let viewport = CGRect(x: 0, y: 44, width: 390, height: 766)
    let target = CGRect(x: 170, y: 300, width: 32, height: 32)

    func testCapturedPlacementsCompareByGeometryAndSide() {
        let first = SceneScrubHUDPlacement(originalTarget: target,
            initialTouch: CGPoint(x: 180, y: 320), viewport: viewport)
        let same = SceneScrubHUDPlacement(originalTarget: target,
            initialTouch: CGPoint(x: 180, y: 320), viewport: viewport)
        let moved = SceneScrubHUDPlacement(originalTarget: target.offsetBy(dx: 30, dy: 0),
            initialTouch: CGPoint(x: 210, y: 320), viewport: viewport)
        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, moved)
    }

    func testInitialPlacementIsAboveOriginalTarget() {
        let placement = SceneScrubHUDPlacement(originalTarget: target,
            initialTouch: CGPoint(x: 180, y: 320), viewport: viewport)
        XCTAssertEqual(placement.side, .above)
        XCTAssertEqual(placement.frame.midX, target.midX)
        XCTAssertLessThanOrEqual(placement.frame.maxY, target.minY - 60)
        XCTAssertEqual(placement.anchor, CGPoint(x: target.midX, y: target.minY))
    }

    func testOffsetFingerDoesNotChangeTargetCenter() {
        let placement = SceneScrubHUDPlacement(originalTarget: target,
            initialTouch: CGPoint(x: 201, y: 320), viewport: viewport)
        XCTAssertEqual(placement.frame.midX, target.midX)
        XCTAssertNotEqual(placement.frame.midX, 201)
    }

    func testCapturedPlacementSurvivesSubsequentFingerAndTargetMovement() {
        var movingTarget = target
        var movingFinger = CGPoint(x: 180, y: 320)
        let placement = SceneScrubHUDPlacement(originalTarget: movingTarget,
            initialTouch: movingFinger, viewport: viewport)
        let initialFrame = placement.frame(in: viewport)
        for step in 1...20 {
            movingTarget.origin.x += 32
            movingFinger.x += CGFloat(step)
            movingFinger.y -= 5
            XCTAssertEqual(placement.frame(in: viewport), initialFrame)
            XCTAssertEqual(placement.anchor, CGPoint(x: target.midX, y: target.minY))
        }
    }

    func testNewGestureAcquiresANewPosition() {
        let first = SceneScrubHUDPlacement(originalTarget: target,
            initialTouch: target.origin, viewport: viewport)
        let second = SceneScrubHUDPlacement(originalTarget: target.offsetBy(dx: 50, dy: 150),
            initialTouch: CGPoint(x: 230, y: 470), viewport: viewport)
        XCTAssertNotEqual(first.frame, second.frame)
    }

    func testTopEdgeFallbackIsChosenOnceAndFitsTheSafeArea() {
        let placement = SceneScrubHUDPlacement(
            originalTarget: CGRect(x: 170, y: 55, width: 32, height: 32),
            initialTouch: CGPoint(x: 180, y: 70), viewport: viewport)
        XCTAssertEqual(placement.side, .below)
        XCTAssertTrue(viewport.insetBy(dx: 8, dy: 8).contains(placement.frame))
        XCTAssertGreaterThanOrEqual(placement.frame.minY, 87 + 60)
    }

    func testHorizontalEdgesClampWithoutFollowingTheFinger() {
        for x: CGFloat in [0, 378] {
            let placement = SceneScrubHUDPlacement(
                originalTarget: CGRect(x: x, y: 300, width: 12, height: 12),
                initialTouch: CGPoint(x: x, y: 310), viewport: viewport)
            XCTAssertTrue(viewport.insetBy(dx: 8, dy: 8).contains(placement.frame))
        }
    }

    func testSmallAndChangedViewportsKeepTheHUDInside() {
        let placement = SceneScrubHUDPlacement(originalTarget: target,
            initialTouch: target.origin, viewport: viewport)
        let small = CGRect(x: 0, y: 20, width: 120, height: 180)
        XCTAssertTrue(small.insetBy(dx: 8, dy: 8).contains(placement.frame(in: small)))
        XCTAssertEqual(placement.frame(in: viewport), placement.frame)
    }

    func testEmptyViewportHasNoNegativeSize() {
        let placement = SceneScrubHUDPlacement(originalTarget: .zero,
            initialTouch: .zero, viewport: .zero)
        XCTAssertEqual(placement.frame, .zero)
    }
}
