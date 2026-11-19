import Foundation
import SpriteKit
import XCTest
import WhaleySpriteKit
import WhaleyObjectiveC

@MainActor
final class WhaleyLevel2ResourceTests: XCTestCase {
    func testLevelTwoBuildsVisibleBackgroundSprites() throws {
        WhaleyResources.configure()
        // The original and tall-screen maps are distinct assets. These counts
        // come from each TMX's decompressed Background layer.
        let variants = [
            (name: "level2.tmx", rows: 15, gidOneCount: 871),
            (name: "level2-568h.tmx", rows: 17, gidOneCount: 1_221),
        ]
        for (name, rows, gidOneCount) in variants {
            let map = try XCTUnwrap(CCTMXTiledMap.tiledMap(withTMXFile: name))
            let background = try XCTUnwrap(map.layerNamed("Background"))
            XCTAssertEqual(map.mapSize.width, 175, name)
            XCTAssertEqual(map.mapSize.height, CGFloat(rows), name)
            let drawables = background.children.compactMap { $0 as? SKSpriteNode }
            XCTAssertEqual(drawables.count, gidOneCount + 59,
                           "\(name) needs one sprite per nonempty Background GID")
            XCTAssertTrue(drawables.allSatisfy {
                $0.texture != nil && !$0.isHidden && $0.alpha > 0 &&
                $0.size.width == 32 && $0.size.height == 32 &&
                $0.position.x >= 0 && $0.position.x <= 175 * 32 &&
                $0.position.y >= 0 && $0.position.y <= CGFloat(rows * 32)
            }, "Textures and projections must be valid")
            var counts: [Int: Int] = [:]
            for row in 0..<rows {
                for col in 0..<175 {
                    let gid = background.tileGIDAt(CGPoint(x: CGFloat(col), y: CGFloat(row)))
                    counts[gid, default: 0] += 1
                }
            }
            XCTAssertEqual(counts, [0: 1_695, 1: gidOneCount, 2: 59], name)
        }
    }

    func testLevelTwoVisualTileEditsUseCurrentBridgeState() throws {
        WhaleyResources.configure()
        let map = try XCTUnwrap(CCTMXTiledMap.tiledMap(withTMXFile: "level2-568h.tmx"))
        let background = try XCTUnwrap(map.layerNamed("Background"))
        let position = try XCTUnwrap(
            (0..<17).lazy.flatMap { row in
                (0..<175).lazy.map { col in CGPoint(x: CGFloat(col), y: CGFloat(row)) }
            }.first { background.tileGIDAt($0) == 1 }
        )
        XCTAssertEqual(background.children.compactMap { $0 as? SKSpriteNode }.count, 1_280)
        background.setTileGID(0, at: position)
        XCTAssertEqual(background.tileGIDAt(position), 0)
        XCTAssertEqual(background.children.compactMap { $0 as? SKSpriteNode }.count, 1_279)
        background.setTileGID(1, at: position)
        XCTAssertEqual(background.tileGIDAt(position), 1)
        XCTAssertEqual(background.children.compactMap { $0 as? SKSpriteNode }.count, 1_280)
    }

    func testLevelTwoTMXVisualTilesetIsBundled() throws {
        XCTAssertNotNil(WhaleyResources.url("tileset.png"),
                        "Level 2 uses tileset.png, not tileset2.png")
        for name in ["level2.tmx", "level2-568h.tmx"] {
            let url = try XCTUnwrap(WhaleyResources.url(name))
            let tmx = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(tmx.contains("source=\"tileset.png\""), name)
        }
    }
}
