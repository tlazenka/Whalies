import Foundation
import SpriteKit
import XCTest
import WhaleyObjectiveC
import WhaleySpriteKit

@MainActor
final class WhaleyDebugControlsTests: XCTestCase {
    private let preference = "whaley.debug.tileOverlaysEnabled"
    private let overlayNames = ["WhaleyCollisionOverlay", "WhaleyGeometry", "WhaleyCollisionLegend"]

    private func makeLevel() -> SKScene {
        WhaleyRuntimeBridgeLinkage.ensureLinked()
        WhaleyResources.configure()
        return WhaleyCreateSrcLevelOneScene()
    }

    private func game(in node: SKNode) throws -> SKNode {
        // Whaley's gameplay pause uses setIsPaused:, distinct from SKNode's
        // setPaused:. KVC addresses that actual legacy property in these tests.
        let type = try XCTUnwrap(NSClassFromString("Whaley"))
        func find(_ node: SKNode) -> SKNode? {
            if node.isKind(of: type) { return node }
            for child in node.children {
                if let result = find(child) { return result }
            }
            return nil
        }
        return try XCTUnwrap(find(node))
    }

    private func paused(_ game: SKNode) throws -> Bool {
        try XCTUnwrap(game.value(forKey: "isPaused") as? Bool)
    }

    func testOverlayToggleUpdatesTheActiveLevelAndStopsRemovedActions() throws {
        let previous = UserDefaults.standard.object(forKey: preference)
        UserDefaults.standard.removeObject(forKey: preference)
        let host = makeLevel()
        defer {
            WhaleySrcSetTileDebugOverlaysEnabled(false)
            UserDefaults.standard.set(previous, forKey: preference)
        }
        let originalGame = try game(in: host)
        XCTAssertFalse(WhaleySrcTileDebugOverlaysEnabled())
        for name in overlayNames { XCTAssertNil(host.childNode(withName: "//\(name)")) }

        WhaleySrcSetTileDebugOverlaysEnabled(true)
        XCTAssertTrue(WhaleySrcTileDebugOverlaysEnabled())
        let geometry = try XCTUnwrap(host.childNode(withName: "//WhaleyGeometry"))
        XCTAssertTrue(geometry.hasActions())
        XCTAssertFalse(try XCTUnwrap(host.childNode(withName: "//WhaleyCollisionOverlay")).children.isEmpty)
        for name in overlayNames { XCTAssertNotNil(host.childNode(withName: "//\(name)")) }
        XCTAssertTrue(try game(in: host) === originalGame)

        // Re-enabling cannot accumulate multiple sets or leave an old updater.
        WhaleySrcSetTileDebugOverlaysEnabled(true)
        XCTAssertNil(geometry.parent)
        XCTAssertFalse(geometry.hasActions())
        let replacement = try XCTUnwrap(host.childNode(withName: "//WhaleyGeometry"))
        for name in overlayNames {
            var count = 0
            host.enumerateChildNodes(withName: "//\(name)") { _, _ in count += 1 }
            XCTAssertEqual(count, 1, name)
        }

        WhaleySrcSetTileDebugOverlaysEnabled(false)
        XCTAssertFalse(WhaleySrcTileDebugOverlaysEnabled())
        XCTAssertNil(replacement.parent)
        XCTAssertFalse(replacement.hasActions())
        for name in overlayNames { XCTAssertNil(host.childNode(withName: "//\(name)")) }
        XCTAssertTrue(try game(in: host) === originalGame)
    }

    func testReplacementLevelReadsTheSavedOverlayPreference() {
        let previous = UserDefaults.standard.object(forKey: preference)
        UserDefaults.standard.set(true, forKey: preference)
        let host = makeLevel()
        defer {
            WhaleySrcSetTileDebugOverlaysEnabled(false)
            UserDefaults.standard.set(previous, forKey: preference)
        }
        for name in overlayNames { XCTAssertNotNil(host.childNode(withName: "//\(name)")) }
        WhaleySrcSetTileDebugOverlaysEnabled(false)
        let replacement = makeLevel()
        for name in overlayNames { XCTAssertNil(replacement.childNode(withName: "//\(name)")) }
    }

    func testArtStyleResourcesFollowTheLaunchEnvironment() {
        let host = makeLevel()
        defer { WhaleySrcDisposeHost(host) }
        let style = ProcessInfo.processInfo.environment["WHALEY_ART_STYLE"] ?? "whaleland"
        let usesWhaleland = style == "whaleland"
        XCTAssertEqual(WhaleySrcUsesWhalelandArt(), usesWhaleland)
        let scenery = ["tileset.png", "tileset2.png", "flame01.png", "flame02.png", "spout.png"]
            + (usesWhaleland ? ["tileset3.png"] : [])
        for name in scenery {
            let expected = usesWhaleland ? "whaleland-" + name : name
            XCTAssertEqual(WhaleySrcResourceURL(name)?.lastPathComponent, expected)
            XCTAssertEqual(WhaleyResources.url(name)?.lastPathComponent, expected)
        }
        XCTAssertEqual(WhaleySrcResourceURL("player.png")?.lastPathComponent, "player.png")
        XCTAssertEqual(WhaleySrcResourceURL("player-win.png")?.lastPathComponent, "player-win.png")
        XCTAssertEqual(WhaleySrcTexture("whaleland-flame01.png").filteringMode, .nearest)
        XCTAssertEqual(WhaleyResources.texture("whaleland-flame01.png").filteringMode, .nearest)
    }

    func testScrubReleaseRestoresThePreviousPauseAndIsIdempotent() throws {
        let host = makeLevel()
        let game = try game(in: host)
        defer { WhaleySrcSetSceneScrubPaused(false) }

        game.setValue(false, forKey: "isPaused")
        WhaleySrcSetSceneScrubPaused(true)
        WhaleySrcSetSceneScrubPaused(true)
        XCTAssertTrue(try paused(game))
        WhaleySrcSetSceneScrubPaused(false)
        XCTAssertFalse(try paused(game))

        // The player has already paused through the HUD before editing.
        game.setValue(true, forKey: "isPaused")
        WhaleySrcSetSceneScrubPaused(true)
        WhaleySrcSetSceneScrubPaused(false)
        WhaleySrcSetSceneScrubPaused(false)
        WhaleySrcSceneScrubEnd()
        WhaleySrcAccessibleBubbleEnd()
        XCTAssertTrue(try paused(game))
    }

    func testStaleProjectionCannotMoveOrUnpauseAReplacementLevel() throws {
        let host = makeLevel()
        let oldGame = try game(in: host)
        oldGame.setValue(false, forKey: "isPaused")
        WhaleySrcBeginTimeProjection()
        WhaleySrcSetSceneScrubPaused(true)

        let replacement = makeLevel()
        let newGame = try game(in: replacement)
        XCTAssertFalse(try paused(oldGame))
        newGame.setValue(true, forKey: "isPaused")
        let livePosition = WhaleySrcPlayerPosition()
        XCTAssertFalse(WhaleySrcProjectTime(0))
        WhaleySrcRestoreLiveProjection()
        WhaleySrcSetSceneScrubPaused(false)
        XCTAssertEqual(WhaleySrcPlayerPosition(), livePosition)
        XCTAssertTrue(try paused(newGame))
    }
}
