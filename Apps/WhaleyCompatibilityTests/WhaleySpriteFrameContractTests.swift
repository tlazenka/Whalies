import Foundation
import Metal
import SpriteKit
import XCTest
import WhaleyCore
import WhaleyObjectiveC
import WhaleySpriteKit

@MainActor
final class WhaleySpriteFrameContractTests: XCTestCase {
    private func spout() throws -> CCSprite {
        WhaleyResources.configure()
        CCSpriteFrameCache.shared().addSpriteFrames(from: "spout.plist")
        return try XCTUnwrap(CCSprite.sprite(frameNamed: "spout1.png"))
    }

    func testEveryNamedFrameKeepsTheSameLogicalBoxAndBottomAnchor() throws {
        let sprite = try spout()
        let target = try XCTUnwrap(sprite as? WhaleySpriteFrameTarget)
        sprite.anchorPoint = .zero
        for (index, height) in [17.0, 22.0, 27.0, 32.0].enumerated() {
            XCTAssertTrue(target.applyWhaleyFrame(named: "spout\(index + 1).png"))
            XCTAssertEqual(sprite.contentSize, CGSize(width: 32, height: 32))
            XCTAssertEqual(sprite.textureRect.size, CGSize(width: 32, height: height))
            XCTAssertEqual(sprite.spriteKitNode.size, CGSize(width: 32, height: height))
            XCTAssertEqual(sprite.spriteKitNode.frame.minX, 0, accuracy: 0.001)
            XCTAssertEqual(sprite.spriteKitNode.frame.minY, 0, accuracy: 0.001)
        }
        sprite.flipY = true
        XCTAssertTrue(target.applyWhaleyFrame(named: "spout1.png"))
        XCTAssertEqual(sprite.spriteKitNode.frame.maxY, 32, accuracy: 0.001)
        sprite.flipX = true
        XCTAssertEqual(sprite.spriteKitNode.frame.minX, 0, accuracy: 0.001)
    }

    func testTextureRectAssignmentRecropsTheOriginalAtlas() throws {
        let sprite = try spout()
        let target = try XCTUnwrap(sprite as? WhaleySpriteFrameTarget)
        sprite.textureRect = CGRect(x: 34, y: 1, width: 32, height: 22)
        XCTAssertEqual(sprite.contentSize, CGSize(width: 32, height: 22))
        XCTAssertEqual(try XCTUnwrap(sprite.spriteKitNode.texture).size(), CGSize(width: 32, height: 22))
        sprite.textureRect = CGRect(x: 100, y: 1, width: 32, height: 32)
        XCTAssertEqual(try XCTUnwrap(sprite.spriteKitNode.texture).size(), CGSize(width: 32, height: 32))
        // Named display-frame application restores the entire descriptor,
        // including the offset, not just the newly cropped texture.
        sprite.anchorPoint = .zero
        XCTAssertTrue(target.applyWhaleyFrame(named: "spout4.png"))
        XCTAssertEqual(sprite.spriteKitNode.frame.minY, 0, accuracy: 0.001)
        XCTAssertTrue(target.applyWhaleyFrame(named: "spout1.png"))
        XCTAssertEqual(sprite.contentSize, CGSize(width: 32, height: 32))
        XCTAssertEqual(sprite.spriteKitNode.frame.minY, 0, accuracy: 0.001)
    }

    func testFrameApplicationDoesNotChangeOwnerOrOtherChildren() throws {
        let sprite = try spout()
        let target = try XCTUnwrap(sprite as? WhaleySpriteFrameTarget)
        let parent = SKNode()
        parent.addChild(sprite)
        sprite.position = CGPoint(x: 21, y: 34)
        sprite.xScale = 2
        sprite.yScale = 3
        sprite.alpha = 100.0 / 255.0
        sprite.spriteKitNode.color = .red
        sprite.spriteKitNode.colorBlendFactor = 1
        let decoy = SKSpriteNode(color: .blue, size: CGSize(width: 9, height: 11))
        sprite.addChild(decoy)
        let owner: SKNode = sprite
        owner.run(.wait(forDuration: 60), withKey: "unrelated")
        XCTAssertTrue(target.applyWhaleyFrame(named: "spout3.png"))
        XCTAssertTrue(sprite.parent === parent)
        XCTAssertEqual(sprite.position, CGPoint(x: 21, y: 34))
        XCTAssertEqual(sprite.xScale, 2)
        XCTAssertEqual(sprite.yScale, 3)
        XCTAssertEqual(sprite.alpha, 100.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(sprite.spriteKitNode.color, .red)
        XCTAssertEqual(decoy.size, CGSize(width: 9, height: 11))
        XCTAssertNotNil(owner.action(forKey: "unrelated"))
        let texture = sprite.spriteKitNode.texture
        XCTAssertFalse(target.applyWhaleyFrame(named: "not-a-registered-frame"))
        XCTAssertTrue(sprite.spriteKitNode.texture === texture)
        owner.removeAllActions()
    }

    func testRealSpriteKitAnimationUpdatesFramesAndCallsBackWithLogicalOwner() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("This SpriteKit execution test requires a Metal device")
        }
        let sprite = try spout()
        sprite.anchorPoint = .zero
        let scene = SKScene(size: CGSize(width: 320, height: 568))
        scene.addChild(sprite)
        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        var callbackCount = 0
        let model = GameAction.sequence([
            .animate(frameNames: (1...4).map { "spout\($0).png" }, frameDuration: .seconds(0.1)),
            .callback(71)
        ])
        let action = SpriteKitGameAction.interpret(model, callback: { id, owner in
            XCTAssertEqual(id, 71)
            XCTAssertTrue(owner === sprite)
            callbackCount += 1
        }, texture: { _ in SKTexture() })
        let owner: SKNode = sprite
        owner.run(action, withKey: "frame-contract")
        var heights: Set<Int> = []
        for tick in 0...90 {
            renderer.update(atTime: 1 + Double(tick) / 60)
            heights.insert(Int(sprite.textureRect.height))
            XCTAssertEqual(sprite.contentSize, CGSize(width: 32, height: 32))
            XCTAssertEqual(sprite.spriteKitNode.frame.minY, 0, accuracy: 0.001)
        }
        XCTAssertEqual(heights, [17, 22, 27, 32])
        XCTAssertEqual(callbackCount, 1)
        XCTAssertNil(owner.action(forKey: "frame-contract"))
        renderer.scene = nil
    }
}
