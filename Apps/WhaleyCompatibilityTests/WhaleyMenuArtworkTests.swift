import ObjectiveC
import SpriteKit
import UIKit
import XCTest
import WhaleyObjectiveC
import WhaleySpriteKit

@MainActor
final class WhaleyMenuArtworkTests: XCTestCase {
    private let origins: [CGPoint] = [
        .init(x: 36.8, y: 321.2), .init(x: 125.6, y: 321.2), .init(x: 214.4, y: 321.2),
        .init(x: 36.8, y: 203.4), .init(x: 125.6, y: 203.4), .init(x: 214.4, y: 203.4)
    ]

    func testOriginalFramePaintingAndBlackHighlightGeometry() throws {
        try withMenu(rotations: Array(repeating: 0, count: 6)) { _, _, cards in
            for (index, card) in cards.enumerated() {
                XCTAssertEqual(card.position.x, origins[index].x, accuracy: 0.001)
                XCTAssertEqual(card.position.y, origins[index].y, accuracy: 0.001)
                XCTAssertEqual(card.xScale, 0.2, accuracy: 0.0001)
                XCTAssertEqual(card.yScale, 0.2, accuracy: 0.0001)
                let frame = try XCTUnwrap(card.childNode(withName: "picture-frame") as? SKSpriteNode)
                let painting = try XCTUnwrap(card.childNode(withName: "painting") as? SKSpriteNode)
                let highlight = try XCTUnwrap(card.childNode(withName: "highlight") as? SKSpriteNode)
                XCTAssertNotNil(frame.texture)
                let texture = try XCTUnwrap(painting.texture)
                let url = try XCTUnwrap(WhaleyResources.url("level\(index + 1).png"))
                let source = try XCTUnwrap(UIImage(contentsOfFile: url.path))
                XCTAssertEqual(source.size, CGSize(width: 320, height: 480))
                XCTAssertEqual(texture.size(), source.size,
                               "The gallery loads the standard painting variant")
                let tallSource = try image("level\(index + 1)-568h.png")
                XCTAssertEqual(tallSource.width, 320)
                XCTAssertEqual(tallSource.height, 568)
                XCTAssertEqual(frame.frame, CGRect(x: 0, y: 0, width: 344, height: 514))
                XCTAssertEqual(painting.frame, CGRect(x: 72, y: 107, width: 200, height: 300))
                XCTAssertEqual(highlight.frame, frame.frame)
                // SpriteKit may store grayscale black in an RGB color space.
                // Assert the opaque black color components, independently of node opacity.
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, colorAlpha: CGFloat = 0
                XCTAssertTrue(highlight.color.getRed(&red, green: &green, blue: &blue, alpha: &colorAlpha))
                XCTAssertEqual(red, 0, accuracy: 0.0001)
                XCTAssertEqual(green, 0, accuracy: 0.0001)
                XCTAssertEqual(blue, 0, accuracy: 0.0001)
                XCTAssertEqual(colorAlpha, 1, accuracy: 0.0001)
                XCTAssertEqual(highlight.alpha, 100.0 / 255.0, accuracy: 0.0001)
                XCTAssertTrue(highlight.isHidden)
                XCTAssertGreaterThan(frame.zPosition, painting.zPosition)
                XCTAssertGreaterThan(highlight.zPosition, frame.zPosition)
            }
        }
    }

    func testStoredClockwiseAnglesUseBottomLeftPivotAndNominalHitBounds() throws {
        let rotations = [3.0, -3, 2, -2, 1, -1]
        try withMenu(rotations: rotations) { _, menu, cards in
            let selector = NSSelectorFromString("levelAt:")
            let method = try XCTUnwrap(class_getInstanceMethod(object_getClass(menu), selector))
            typealias HitTest = @convention(c) (AnyObject, Selector, CGPoint) -> Int
            let hit = unsafeBitCast(method_getImplementation(method), to: HitTest.self)
            for (index, card) in cards.enumerated() {
                XCTAssertEqual(card.zRotation, -CGFloat(rotations[index]) * .pi / 180, accuracy: 0.0001)
                let pivot = card.convert(CGPoint.zero, to: menu)
                XCTAssertEqual(pivot.x, origins[index].x, accuracy: 0.001)
                XCTAssertEqual(pivot.y, origins[index].y, accuracy: 0.001)
                // Whaley2010 uses the nominal unrotated frame rectangle even
                // while the painting is swinging around its lower-left corner.
                for dx in [0.5, 68.3] {
                    for dy in [0.5, 102.3] {
                        let point = CGPoint(x: origins[index].x + dx, y: origins[index].y + dy)
                        XCTAssertEqual(hit(menu, selector, point), index + 1)
                    }
                }
                let outside = CGPoint(x: origins[index].x - 0.5, y: origins[index].y + 51.4)
                XCTAssertEqual(hit(menu, selector, outside), -1)
            }
        }
    }

    func testOriginalNailsStayUnderOpaqueFramePixelsAtEveryLegacyAngle() throws {
        try withMenu(rotations: Array(repeating: 0, count: 6)) { scene, _, cards in
            let background = try image("Default-568h@2x.png")
            let frameImage = try image("frame.png")
            XCTAssertEqual(background.width, 320)
            XCTAssertEqual(background.height, 568)
            XCTAssertEqual(frameImage.width, 344)
            XCTAssertEqual(frameImage.height, 514)
            // Measured pixel positions in the original, unchanged launch PNG.
            // Each nail has these five bright pixels; image coordinates start
            // at the top left, while scene coordinates start at the bottom left.
            let centers = [(65, 152), (160, 157), (244, 152), (68, 274), (159, 274), (253, 273)]
            let offsets = [(0, -1), (0, 0), (1, 0), (0, 1), (1, 1)]
            for (index, card) in cards.enumerated() {
                let frame = try XCTUnwrap(card.childNode(withName: "picture-frame") as? SKSpriteNode)
                for (dx, dy) in offsets {
                    let x = centers[index].0 + dx, y = centers[index].1 + dy
                    let nail = try pixel(background, x: x, y: y)
                    XCTAssertGreaterThan(nail[0], 175)
                    XCTAssertGreaterThan(nail[1], 175)
                    XCTAssertGreaterThan(nail[2], 175)
                    let scenePoint = CGPoint(x: Double(x) + 0.5, y: 568 - (Double(y) + 0.5))
                    for degrees in -3...3 {
                        card.zRotation = -CGFloat(degrees) * .pi / 180
                        // Exercise the production scene graph rather than a
                        // duplicated layout/rotation formula in the test.
                        let local = frame.convert(scenePoint, from: scene)
                        let u = local.x + frame.size.width * frame.anchorPoint.x
                        let v = frame.size.height * (1 - frame.anchorPoint.y) - local.y
                        for tx in [Int(floor(u)), Int(ceil(u))] {
                            for ty in [Int(floor(v)), Int(ceil(v))] {
                                let sample = try pixel(frameImage, x: tx, y: ty)
                                XCTAssertEqual(sample[3], 255,
                                    "Card \(index + 1), angle \(degrees), nail (\(x),\(y)) exposed")
                            }
                        }
                    }
                }
            }
        }
    }

    private func withMenu(
        rotations: [Double],
        body: (SKScene, SKNode, [SKNode]) throws -> Void
    ) throws {
        WhaleyRuntimeBridgeLinkage.ensureLinked()
        // The existing singleton is intentionally private to the Objective-C
        // game. Access its existing method/fields without exporting test APIs.
        let type = try XCTUnwrap(NSClassFromString("GameState"))
        let selector = NSSelectorFromString("gameState")
        let method = try XCTUnwrap(class_getClassMethod(type, selector))
        typealias Getter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let state = try XCTUnwrap(getter(type as AnyObject, selector).takeUnretainedValue() as? NSObject)
        let progress = try XCTUnwrap(state.value(forKey: "levelsAchieved") as? NSNumber)
        let levels = try XCTUnwrap(state.value(forKey: "levels") as? [NSObject])
        XCTAssertGreaterThanOrEqual(levels.count, 6)
        guard levels.count >= 6 else { return }
        let savedRotations = try levels.prefix(6).map {
            try XCTUnwrap($0.value(forKey: "levelImageRotation") as? NSNumber)
        }
        let resourceBundle = WhaleySrcResourceBundle()
        defer {
            state.setValue(progress, forKey: "levelsAchieved")
            for index in 0..<6 {
                levels[index].setValue(savedRotations[index], forKey: "levelImageRotation")
            }
            WhaleySrcSetResourceBundle(resourceBundle)
        }
        state.setValue(6, forKey: "levelsAchieved")
        for index in 0..<6 {
            levels[index].setValue(rotations[index], forKey: "levelImageRotation")
        }
        WhaleyResources.configure()
        let scene = WhaleyCreateSrcMainMenuScene()
        let first = try XCTUnwrap(scene.childNode(withName: "//level-1"))
        let menu = try XCTUnwrap(first.parent)
        let cards = try (1...6).map { try XCTUnwrap(menu.childNode(withName: "level-\($0)")) }
        try body(scene, menu, cards)
        // No progress save is called: persistent player data remains untouched.
    }

    private func image(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(WhaleySrcResourceURL(name))
        return try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        XCTAssertTrue((0..<image.width).contains(x) && (0..<image.height).contains(y))
        let cropped = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }
}
