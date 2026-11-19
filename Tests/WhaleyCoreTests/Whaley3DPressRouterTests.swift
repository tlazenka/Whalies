import XCTest
@testable import WhaleyCore

final class Whaley3DPressRouterTests: XCTestCase {
    typealias R = Whaley3DPressRouter
    private func route(_ target: R.Target, _ x: Double = 0.5,
                       session: String = "scene-a") -> R.Intent {
        R.intent(for: target, currentSession: session, horizontalFraction: x)
    }

    func testEmptySpaceKeepsAllThreeShotZones() {
        XCTAssertEqual(route(.empty, 0), .shoot(.left))
        XCTAssertEqual(route(.empty, 0.2), .shoot(.left))
        XCTAssertEqual(route(.empty, 0.5), .shoot(.below))
        XCTAssertEqual(route(.empty, 0.8), .shoot(.right))
        XCTAssertEqual(route(.empty, 1), .shoot(.right))
    }

    func testZoneEdgesBelongToCenter() {
        XCTAssertEqual(route(.empty, 0.35), .shoot(.below))
        XCTAssertEqual(route(.empty, 0.65), .shoot(.below))
    }

    func testExistingBubbleWinsInEveryShotZone() {
        for x in [0.1, 0.5, 0.9] {
            XCTAssertEqual(route(.bubble(session: "scene-a", projectileID: "42", canGrow: true), x),
                           .grow(session: "scene-a", projectileID: "42"))
        }
    }

    func testFoundationPressDoesNotGrowOrCreateAnotherBubble() {
        for x in [0.1, 0.5, 0.9] {
            XCTAssertEqual(route(.bubble(session: "scene-a", projectileID: "foundation", canGrow: false), x), .ignore)
        }
    }

    func testUnknownOrMalformedBubbleCannotTurnIntoShot() {
        XCTAssertEqual(route(.bubble(session: "scene-a", projectileID: "", canGrow: true)), .ignore)
        XCTAssertEqual(route(.bubble(session: "scene-a", projectileID: "legacy", canGrow: false)), .ignore)
    }

    func testSceneReplacementRejectsOldBubble() {
        XCTAssertEqual(route(.bubble(session: "scene-old", projectileID: "42", canGrow: true)), .ignore)
    }

    func testUnavailableTargetNeverFallsBackToShooting() {
        XCTAssertEqual(route(.unavailable), .ignore)
    }

    func testNonBubbleBodyKeepsShootingAndDoesNotSelectThroughIt() {
        XCTAssertEqual(route(.body(session: "scene-a"), 0.1), .shoot(.left))
        XCTAssertEqual(route(.body(session: "scene-a"), 0.5), .shoot(.below))
        XCTAssertEqual(route(.body(session: "scene-a"), 0.9), .shoot(.right))
    }

    func testOldNonBubbleBodyIsAlsoRejected() {
        XCTAssertEqual(route(.body(session: "scene-old")), .ignore)
    }

    func testInvalidCoordinatesAndEmptySceneDoNothing() {
        for x in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            XCTAssertEqual(route(.empty, x), .ignore)
            XCTAssertEqual(route(.bubble(session: "scene-a", projectileID: "42", canGrow: true), x), .ignore)
        }
        XCTAssertEqual(route(.empty, session: ""), .ignore)
    }

    func testRejectedNativeSelectionConsumesPressUntilRelease() {
        var hold = Whaley3DHoldSession()
        XCTAssertTrue(hold.begin(session: "scene-a", simulationTime: 10))
        XCTAssertEqual(route(.bubble(session: "scene-a", projectileID: "42", canGrow: true)),
                       .grow(session: "scene-a", projectileID: "42"))
        // Native code rejects a bubble that has popped since the displayed hit.
        hold.cancel()
        XCTAssertFalse(hold.begin(session: "scene-a", simulationTime: 10.1))
        XCTAssertNil(hold.elapsed(session: "scene-a", simulationTime: 10.2))
        hold.release()
        XCTAssertTrue(hold.begin(session: "scene-a", simulationTime: 10.3))
    }

    func testReselectionGetsNewSimulationTimeBaseline() {
        var hold = Whaley3DHoldSession()
        XCTAssertTrue(hold.begin(session: "scene-a", simulationTime: 2))
        XCTAssertEqual(hold.elapsed(session: "scene-a", simulationTime: 3), 1)
        hold.release()
        XCTAssertTrue(hold.begin(session: "scene-a", simulationTime: 30))
        XCTAssertEqual(hold.elapsed(session: "scene-a", simulationTime: 30.25), 0.25)
        XCTAssertEqual(hold.elapsed(session: "scene-a", simulationTime: 30.25), 0.25)
    }
}
