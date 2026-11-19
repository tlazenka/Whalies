import Metal
import SpriteKit
import UIKit
import XCTest
import WhaleyObjectiveC
import WhaleySpriteKit

@MainActor
final class WhaleyBubbleResourceTests: XCTestCase {
    // Completing the original six levels selects infinite_bubble.png for
    // every existing and newly created projectile. Both variants must ship
    // in the package resource bundle, independent of the host's resources.
    func testBothBubbleImagesResolveToRealPackagePixels() throws {
        WhaleyRuntimeBridgeLinkage.ensureLinked()
        WhaleyResources.configure()
        for name in ["bubble01.png", "infinite_bubble.png"] {
            let url = try XCTUnwrap(WhaleySrcResourceURL(name), name)
            let image = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage, name)
            XCTAssertEqual(image.width, 128, name)
            XCTAssertEqual(image.height, 128, name)
            let alpha = try alphaSamples(image)
            XCTAssertTrue(alpha.contains(0), "\(name) needs a transparent surround")
            XCTAssertTrue(alpha.contains { $0 > 0 }, "\(name) must contain visible bubble pixels")

            let sprite = CCSprite.sprite(fileNamed: name)
            XCTAssertEqual(sprite.contentSize, CGSize(width: 128, height: 128), name)
            XCTAssertEqual(sprite.spriteKitNode.size, sprite.contentSize, name)
            XCTAssertEqual(try XCTUnwrap(sprite.spriteKitNode.texture).size(), sprite.contentSize, name)
            XCTAssertTrue(sprite.spriteKitNode.parent === sprite, name)
            sprite.scaleX = 44.0 / 128.0
            sprite.scaleY = 44.0 / 128.0
            XCTAssertEqual(sprite.calculateAccumulatedFrame().width, 44, accuracy: 0.001, name)
            XCTAssertEqual(sprite.calculateAccumulatedFrame().height, 44, accuracy: 0.001, name)
        }
    }

    func testTintedAndInfiniteBubblesRenderAfterScaling() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Bubble rendering requires a Metal device")
        }
        WhaleyRuntimeBridgeLinkage.ensureLinked()
        WhaleyResources.configure()
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        let scene = SKScene(size: view.bounds.size)
        scene.backgroundColor = .clear
        view.presentScene(scene)
        defer { view.presentScene(nil) }

        for name in ["bubble01.png", "infinite_bubble.png"] {
            let sprite = CCSprite.sprite(fileNamed: name)
            sprite.position = CGPoint(x: 32, y: 32)
            sprite.scaleX = 44.0 / 128.0
            sprite.scaleY = 44.0 / 128.0
            if name == "bubble01.png" {
                sprite.color = ccc3(153, 153, 255)
            }
            scene.addChild(sprite)
            let texture = try XCTUnwrap(view.texture(from: sprite), name)
            let alpha = try alphaSamples(texture.cgImage())
            XCTAssertTrue(alpha.contains { $0 > 0 }, "\(name) rendered no visible pixels")
            XCTAssertTrue(alpha.contains(0), "\(name) lost its transparent surround")
            sprite.removeFromParent()
        }
    }

    private func alphaSamples(_ image: CGImage) throws -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    }
}
