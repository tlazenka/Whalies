import Foundation
import XCTest
import WhaleyHost

final class WhaleyHUDLayoutTests: XCTestCase {
    func testTopBandTouchesSceneEdgeWithoutASeam() throws {
        let center = try XCTUnwrap(WhaleyHUDLayout.center(
            sceneSize: CGSize(width: 320, height: 568),
            projectedTop: CGPoint(x: 160, y: 568)))
        XCTAssertEqual(center, CGPoint(x: 160, y: 552))
        XCTAssertEqual(center.y + WhaleyHUDLayout.barHeight / 2, 568)
    }

    func testLetterboxingAndCroppedViewportUseTheVisibleTop() throws {
        for top: CGFloat in [700, 568, 500] {
            let center = try XCTUnwrap(WhaleyHUDLayout.center(
                sceneSize: CGSize(width: 320, height: 568),
                projectedTop: CGPoint(x: 160, y: top)))
            XCTAssertEqual(center.y + WhaleyHUDLayout.barHeight / 2, min(top, 568))
        }
    }
}
