#if canImport(SpriteKit)
import SpriteKit
import WhaleyCore
#if canImport(UIKit)
import WhaleyObjectiveC
#endif

public enum SpriteKitGameAction {
    public static func interpret(
        _ action: GameAction,
        callback: @escaping (UInt64, SKNode) -> Void = { _, _ in },
        texture: @escaping (String) -> SKTexture = { SKTexture(imageNamed: $0) }
    ) -> SKAction {
        switch action {
        case let .move(to, duration):
            return .move(to: CGPoint(x: to.x, y: to.y), duration: seconds(duration))
        case let .scale(to, duration):
            return .scale(to: to, duration: seconds(duration))
        case let .rotate(degrees, duration):
            return .rotate(byAngle: -degrees * .pi / 180, duration: seconds(duration))
        case let .wait(duration):
            return .wait(forDuration: seconds(duration))
        case let .fade(opacity, duration):
            return .fadeAlpha(to: opacity, duration: seconds(duration))
        case let .animate(frameNames, frameDuration):
            guard let timeline = SpriteFrameTimeline(count: frameNames.count,
                                                     interval: seconds(frameDuration)) else {
                return .wait(forDuration: 0)
            }
            // Fallback textures serve plain SKSpriteNode clients. CCSprite
            // resolves its COMPLETE descriptor from the existing Obj-C cache.
            let frames = frameNames.map(texture)
            return .customAction(withDuration: timeline.duration) { node, elapsed in
                let index = timeline.index(at: Double(elapsed))
                #if canImport(UIKit)
                if let owner = node as? WhaleySpriteFrameTarget {
                    _ = owner.applyWhaleyFrame(named: frameNames[index])
                    return
                }
                #endif
                // Never select a seemingly suitable child of an arbitrary
                // wrapper. Only an explicit frame target or actual sprite
                // accepts frame changes; movement/callbacks stay on node.
                if let drawable = node as? SKSpriteNode {
                    drawable.texture = frames[index]
                    drawable.size = frames[index].size()
                }
            }
        case let .sequence(actions):
            return .sequence(actions.map { interpret($0, callback: callback, texture: texture) })
        case let .repeatForever(action):
            return .repeatForever(interpret(action, callback: callback, texture: texture))
        case let .callback(id):
            return .customAction(withDuration: 0) { node, _ in
                callback(id, node)
            }
        }
    }

    private static func seconds(_ duration: GameDuration) -> TimeInterval {
        Double(duration.microseconds) / 1_000_000
    }
}
#endif
