import XCTest
@testable import WhaleyCore

final class Whaley3DHoldSessionTests: XCTestCase {
    func testOneNativeAttemptPerPressDespiteRepeatedChanges() {
        var hold = Whaley3DHoldSession()
        XCTAssertTrue(hold.begin(session: "scene", simulationTime: 10))
        for _ in 0..<100 { XCTAssertFalse(hold.begin(session: "scene", simulationTime: 11)) }
        XCTAssertEqual(hold.elapsed(session: "scene", simulationTime: 12), 2)
    }

    func testPausedClockDoesNotAccumulateGrowth() {
        var hold = Whaley3DHoldSession()
        hold.begin(session: "scene", simulationTime: 10)
        XCTAssertEqual(hold.elapsed(session: "scene", simulationTime: 10.25), 0.25)
        for _ in 0..<300 {
            XCTAssertEqual(hold.elapsed(session: "scene", simulationTime: 10.25), 0.25)
        }
        XCTAssertEqual(hold.elapsed(session: "scene", simulationTime: 10.5), 0.5)
    }

    func testInterruptionRequiresReleaseBeforeNextShot() {
        var hold = Whaley3DHoldSession()
        hold.begin(session: "scene", simulationTime: 0)
        hold.cancel()
        XCTAssertFalse(hold.isHolding)
        XCTAssertFalse(hold.acceptsNewPress)
        XCTAssertNil(hold.elapsed(session: "scene", simulationTime: 100))
        XCTAssertFalse(hold.begin(session: "scene", simulationTime: 100))
        hold.release()
        XCTAssertTrue(hold.begin(session: "scene", simulationTime: 100))
        XCTAssertEqual(hold.elapsed(session: "scene", simulationTime: 100), 0)
    }

    func testNativeRejectionDoesNotRetryDuringTheSamePress() {
        var hold = Whaley3DHoldSession()
        XCTAssertTrue(hold.begin(session: "scene", simulationTime: 0))
        // The native BeginBubble call returned false (paused/dead/no accepted shot).
        hold.cancel()
        for _ in 0..<10 { XCTAssertFalse(hold.begin(session: "scene", simulationTime: 2)) }
        hold.release()
        XCTAssertTrue(hold.begin(session: "scene", simulationTime: 2))
    }

    func testSameLevelRetryRejectsOldHoldBeforeAnyGrowth() {
        var hold = Whaley3DHoldSession()
        hold.begin(session: "scene-a", simulationTime: 20)
        XCTAssertNil(hold.elapsed(session: "scene-b", simulationTime: 20.5))
        XCTAssertFalse(hold.isHolding)
        XCTAssertFalse(hold.begin(session: "scene-b", simulationTime: 20.5))
    }

    func testNewPressInNewSceneIsNotCancelledByOldDisplayedSession() {
        var hold = Whaley3DHoldSession()
        hold.begin(session: "scene-a", simulationTime: 20)
        hold.release()
        // Begin uses a fresh native capture even if the rendered frame is older.
        XCTAssertTrue(hold.begin(session: "scene-b", simulationTime: 0))
        XCTAssertEqual(hold.elapsed(session: "scene-b", simulationTime: 0.125), 0.125)
        XCTAssertTrue(hold.isHolding)
    }

    func testRewindAfterProgressCancelsEvenAboveTheStartTime() {
        var hold = Whaley3DHoldSession()
        hold.begin(session: "scene", simulationTime: 10)
        XCTAssertEqual(hold.elapsed(session: "scene", simulationTime: 12), 2)
        XCTAssertNil(hold.elapsed(session: "scene", simulationTime: 11))
        XCTAssertNil(hold.elapsed(session: "scene", simulationTime: 13))
        XCTAssertFalse(hold.acceptsNewPress)
    }

    func testIneligiblePlayerCancelsGrowthUntilRelease() {
        var hold = Whaley3DHoldSession()
        hold.begin(session: "scene", simulationTime: 0)
        XCTAssertNil(hold.elapsed(session: "scene", simulationTime: 1, canContinue: false))
        XCTAssertNil(hold.elapsed(session: "scene", simulationTime: 2, canContinue: true))
        hold.release()
        XCTAssertTrue(hold.acceptsNewPress)
    }

    func testInvalidInitialClockConsumesThePress() {
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            var hold = Whaley3DHoldSession()
            XCTAssertFalse(hold.begin(session: "scene", simulationTime: invalid))
            XCTAssertFalse(hold.begin(session: "scene", simulationTime: 0))
            hold.release()
            XCTAssertTrue(hold.begin(session: "scene", simulationTime: 0))
        }
    }

    func testEmptySessionIsRejected() {
        var hold = Whaley3DHoldSession()
        XCTAssertFalse(hold.begin(session: "", simulationTime: 0))
        XCTAssertFalse(hold.acceptsNewPress)
        hold.release()
        XCTAssertTrue(hold.begin(session: "scene", simulationTime: 0))
        XCTAssertNil(hold.elapsed(session: "", simulationTime: 1))
    }

    func testInvalidSubsequentClockCancels() {
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            var hold = Whaley3DHoldSession()
            hold.begin(session: "scene", simulationTime: 0)
            XCTAssertNil(hold.elapsed(session: "scene", simulationTime: invalid))
            XCTAssertFalse(hold.isHolding)
            XCTAssertFalse(hold.acceptsNewPress)
        }
    }

    func testRepeatedReleaseAndIdleCancellationAreHarmless() {
        var hold = Whaley3DHoldSession()
        hold.cancel()
        hold.cancel()
        XCTAssertTrue(hold.acceptsNewPress)
        hold.release()
        hold.release()
        XCTAssertNil(hold.elapsed(session: "scene", simulationTime: 10))
        XCTAssertTrue(hold.begin(session: "scene", simulationTime: 10))
    }

    func testSamplingFrequencyDoesNotChangeElapsedDuration() {
        var sparse = Whaley3DHoldSession(), frequent = Whaley3DHoldSession()
        sparse.begin(session: "scene", simulationTime: 2)
        frequent.begin(session: "scene", simulationTime: 2)
        for tick in 0...120 {
            _ = frequent.elapsed(session: "scene", simulationTime: 2 + Double(tick) / 60)
        }
        XCTAssertEqual(sparse.elapsed(session: "scene", simulationTime: 4), 2)
        XCTAssertEqual(frequent.elapsed(session: "scene", simulationTime: 4), 2)
    }

    func testReleaseStartsANewClock() {
        var hold = Whaley3DHoldSession()
        hold.begin(session: "scene", simulationTime: 0)
        _ = hold.elapsed(session: "scene", simulationTime: 10)
        hold.release()
        XCTAssertTrue(hold.begin(session: "scene", simulationTime: 20))
        XCTAssertEqual(hold.elapsed(session: "scene", simulationTime: 20.25), 0.25)
    }
}
