#if canImport(UIKit) && canImport(SpriteKit) && canImport(WhaleyObjectiveC)
import SpriteKit
import WhaleyCore

/// Explicit Swift linkage root for the Objective-C-to-SpriteKit C exports.
/// The iOS app calls this before installing its game scene. The Release
/// linker also receives -u flags for each C entry point as an archive guard.
public enum WhaleyRuntimeBridgeLinkage {
    @inline(never)
    public static func ensureLinked() {
        // A balanced, observable call into this translation unit, not a fake
        // sprite-frame registration or a second gameplay implementation.
        let probe = WhaleyGameActionWait(0)
        WhaleyReleaseGameAction(probe)
    }
}

private final class GameActionBox {
    let action: GameAction
    init(_ action: GameAction) { self.action = action }
}

private func retain(_ action: GameAction) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(GameActionBox(action)).toOpaque()
}

private func action(_ pointer: UnsafeMutableRawPointer) -> GameAction {
    Unmanaged<GameActionBox>.fromOpaque(pointer).takeUnretainedValue().action
}

@_cdecl("WhaleyGameActionMoveTo")
public func WhaleyGameActionMoveTo(_ x: Double, _ y: Double, _ seconds: Double) -> UnsafeMutableRawPointer {
    retain(.move(to: .init(x: x, y: y), duration: .seconds(seconds)))
}

@_cdecl("WhaleyGameActionScaleTo")
public func WhaleyGameActionScaleTo(_ scale: Double, _ seconds: Double) -> UnsafeMutableRawPointer {
    retain(.scale(to: scale, duration: .seconds(seconds)))
}

@_cdecl("WhaleyGameActionRotateBy")
public func WhaleyGameActionRotateBy(_ degrees: Double, _ seconds: Double) -> UnsafeMutableRawPointer {
    retain(.rotate(byDegrees: degrees, duration: .seconds(seconds)))
}

@_cdecl("WhaleyGameActionWait")
public func WhaleyGameActionWait(_ seconds: Double) -> UnsafeMutableRawPointer {
    retain(.wait(.seconds(seconds)))
}

@_cdecl("WhaleyGameActionSequence")
public func WhaleyGameActionSequence(
    _ pointers: UnsafePointer<UnsafeMutableRawPointer?>,
    _ count: Int
) -> UnsafeMutableRawPointer {
    retain(
        .sequence(
            (0..<count)
                .compactMap { index in
                    pointers[index].map(action)
                }
        )
    )
}

@_cdecl("WhaleyGameActionRepeatForever")
public func WhaleyGameActionRepeatForever(_ pointer: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
    retain(.repeatForever(action(pointer)))
}

@_cdecl("WhaleyGameActionAnimate")
public func WhaleyGameActionAnimate(
    _ frameNames: UnsafePointer<UnsafePointer<CChar>?>,
    _ count: Int,
    _ frameSeconds: Double
) -> UnsafeMutableRawPointer {
    let names = (0..<count).compactMap { index in frameNames[index].map { String(cString: $0) } }
    return retain(.animate(frameNames: names, frameDuration: .seconds(frameSeconds)))
}

private final class SpriteFrameRegistry: @unchecked Sendable {
    struct Frame {
        let atlas: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let atlasWidth: Double
        let atlasHeight: Double
    }
    private let lock = NSLock()
    private var frames: [String: Frame] = [:]
    private var missing: Set<String> = []
    func register(_ name: String, _ frame: Frame) {
        lock.lock()
        defer { lock.unlock() }
        frames[name] = frame
        missing.remove(name)
    }
    func registerMissing(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        missing.insert(name)
        frames.removeValue(forKey: name)
    }
    func texture(named name: String) -> SKTexture {
        lock.lock()
        let frame = frames[name]
        let isMissing = missing.contains(name)
        lock.unlock()
        if isMissing { return SKTexture() }
        guard let f = frame else { return WhaleyResources.texture(name) }
        let atlas = WhaleyResources.texture(f.atlas)
        let rect = CGRect(
            x: f.x / f.atlasWidth,
            y: 1.0 - (f.y + f.height) / f.atlasHeight,
            width: f.width / f.atlasWidth,
            height: f.height / f.atlasHeight
        )
        let texture = SKTexture(rect: rect, in: atlas)
        texture.filteringMode = atlas.filteringMode
        return texture
    }
}
private let spriteFrameRegistry = SpriteFrameRegistry()

@_cdecl("WhaleyRegisterSpriteFrame")
public func WhaleyRegisterSpriteFrame(
    _ name: UnsafePointer<CChar>,
    _ atlas: UnsafePointer<CChar>,
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double,
    _ atlasWidth: Double,
    _ atlasHeight: Double
) {
    spriteFrameRegistry.register(
        String(cString: name),
        .init(
            atlas: String(cString: atlas),
            x: x,
            y: y,
            width: width,
            height: height,
            atlasWidth: atlasWidth,
            atlasHeight: atlasHeight
        )
    )
}

@_cdecl("WhaleyRegisterMissingSpriteFrame")
public func WhaleyRegisterMissingSpriteFrame(_ name: UnsafePointer<CChar>) {
    spriteFrameRegistry.registerMissing(String(cString: name))
}

@_cdecl("WhaleyRenderGameAction")
public func WhaleyRenderGameAction(
    _ pointer: UnsafeMutableRawPointer,
    _ ownerNode: UnsafeMutableRawPointer?
) -> UnsafeMutableRawPointer {
    let owner: SKNode? = ownerNode.map { Unmanaged<SKNode>.fromOpaque($0).takeUnretainedValue() }
    let rendered = SpriteKitGameAction.interpret(
        action(pointer),
        callback: { id, fallbackNode in invokeActionCallback(id, node: owner ?? fallbackNode) },
        texture: { spriteFrameRegistry.texture(named: $0) }
    )
    return Unmanaged.passRetained(rendered).toOpaque()
}

@_cdecl("WhaleyReleaseGameAction")
public func WhaleyReleaseGameAction(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<GameActionBox>.fromOpaque(pointer).release()
}

@_cdecl("WhaleyReleaseRenderedObject")
public func WhaleyReleaseRenderedObject(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<AnyObject>.fromOpaque(pointer).release()
}

private final class TileMapBox {
    var map: TileMap
    init(_ map: TileMap) { self.map = map }
}

@_cdecl("WhaleyTileMapCreate")
public func WhaleyTileMapCreate(
    _ width: Int32,
    _ height: Int32,
    _ tileWidth: Double,
    _ tileHeight: Double
) -> UnsafeMutableRawPointer {
    let map = TileMap(
        size: .init(width: Double(width), height: Double(height)),
        tileSize: .init(width: tileWidth, height: tileHeight),
        layers: [:]
    )
    return Unmanaged.passRetained(TileMapBox(map)).toOpaque()
}

@_cdecl("WhaleyTileMapSetLayer")
public func WhaleyTileMapSetLayer(
    _ pointer: UnsafeMutableRawPointer,
    _ name: UnsafePointer<CChar>,
    _ gids: UnsafePointer<UInt32>,
    _ count: Int
) {
    let box = Unmanaged<TileMapBox>.fromOpaque(pointer).takeUnretainedValue()
    let width = Int(box.map.size.width)
    let height = Int(box.map.size.height)
    guard count == width * height else { return }
    box.map.layers[String(cString: name)] = TileLayer(
        width: width,
        height: height,
        gids: Array(UnsafeBufferPointer(start: gids, count: count))
    )
}

@_cdecl("WhaleyTileMapGID")
public func WhaleyTileMapGID(
    _ pointer: UnsafeMutableRawPointer,
    _ layer: UnsafePointer<CChar>,
    _ column: Int32,
    _ row: Int32
) -> UInt32 {
    let box = Unmanaged<TileMapBox>.fromOpaque(pointer).takeUnretainedValue()
    return box.map.gid(
        in: String(cString: layer),
        at: .init(column: Int(column), row: Int(row))
    )
}

@_cdecl("WhaleyTileMapSetGID")
public func WhaleyTileMapSetGID(
    _ pointer: UnsafeMutableRawPointer,
    _ layer: UnsafePointer<CChar>,
    _ column: Int32,
    _ row: Int32,
    _ gid: UInt32
) {
    let box = Unmanaged<TileMapBox>.fromOpaque(pointer).takeUnretainedValue()
    let name = String(cString: layer)
    guard var tileLayer = box.map.layers[name] else { return }
    tileLayer.setGID(gid, at: .init(column: Int(column), row: Int(row)))
    box.map.layers[name] = tileLayer
}

@_cdecl("WhaleyReleaseTileMap")
public func WhaleyReleaseTileMap(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<TileMapBox>.fromOpaque(pointer).release()
}

@_cdecl("WhaleyGameActionFade")
public func WhaleyGameActionFade(_ durationSeconds: Double, _ opacity: Double) -> UnsafeMutableRawPointer {
    retain(.fade(toOpacity: opacity, duration: .seconds(durationSeconds)))
}

public typealias ActionCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
private struct RegisteredActionCallback {
    let context: UnsafeMutableRawPointer?
    let function: ActionCallback
}

private final class ActionCallbackRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nextID: UInt64 = 1
    private var entries: [UInt64: RegisteredActionCallback] = [:]

    func register(context: UnsafeMutableRawPointer?, function: ActionCallback) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        entries[id] = .init(context: context, function: function)
        return id
    }

    func entry(for id: UInt64) -> RegisteredActionCallback? {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]
    }
}

private let actionCallbackRegistry = ActionCallbackRegistry()

@_cdecl("WhaleyRegisterActionCallback")
public func WhaleyRegisterActionCallback(_ context: UnsafeMutableRawPointer?, _ function: ActionCallback) -> UInt64 {
    actionCallbackRegistry.register(context: context, function: function)
}

@_cdecl("WhaleyGameActionCallback")
public func WhaleyGameActionCallback(_ id: UInt64) -> UnsafeMutableRawPointer { retain(.callback(id)) }

private func invokeActionCallback(_ id: UInt64, node: SKNode) {
    guard let entry = actionCallbackRegistry.entry(for: id) else { return }
    entry.function(entry.context, Unmanaged.passUnretained(node).toOpaque())
}

private final class SchedulerBox {
    var scheduler = GameScheduler()
    var nextToken: UInt64 = 1
    var callbacks:
        [UInt64: (@convention(c) (UnsafeMutableRawPointer?, Double) -> Void, UnsafeMutableRawPointer?, Double)] = [:]
    var tokensBySchedule: [GameScheduleID: UInt64] = [:]
}

@_cdecl("WhaleySchedulerCreate")
public func WhaleySchedulerCreate() -> UnsafeMutableRawPointer { Unmanaged.passRetained(SchedulerBox()).toOpaque() }

@_cdecl("WhaleySchedulerSchedule")
public func WhaleySchedulerSchedule(
    _ pointer: UnsafeMutableRawPointer,
    _ interval: Double,
    _ context: UnsafeMutableRawPointer?,
    _ function: @convention(c) (UnsafeMutableRawPointer?, Double) -> Void
) -> UInt64 {
    let box = Unmanaged<SchedulerBox>.fromOpaque(pointer).takeUnretainedValue()
    let token = box.nextToken
    box.nextToken += 1
    let id = box.scheduler.schedule(callback: token, every: .seconds(interval))
    box.callbacks[token] = (function, context, interval)
    box.tokensBySchedule[id] = token
    return id.rawValue
}

@_cdecl("WhaleySchedulerCancel")
public func WhaleySchedulerCancel(_ pointer: UnsafeMutableRawPointer, _ rawID: UInt64) {
    let box = Unmanaged<SchedulerBox>.fromOpaque(pointer).takeUnretainedValue()
    let id = GameScheduleID(rawValue: rawID)
    box.scheduler.cancel(id)
    if let token = box.tokensBySchedule.removeValue(forKey: id) { box.callbacks[token] = nil }
}

@_cdecl("WhaleySchedulerAdvance")
public func WhaleySchedulerAdvance(_ pointer: UnsafeMutableRawPointer, _ delta: Double) {
    let box = Unmanaged<SchedulerBox>.fromOpaque(pointer).takeUnretainedValue()
    for token in box.scheduler.advance(by: .seconds(delta)) {
        if let (function, context, interval) = box.callbacks[token] { function(context, interval) }
    }
}

@_cdecl("WhaleyReleaseScheduler")
public func WhaleyReleaseScheduler(_ pointer: UnsafeMutableRawPointer) {
    Unmanaged<SchedulerBox>.fromOpaque(pointer).release()
}
#endif
