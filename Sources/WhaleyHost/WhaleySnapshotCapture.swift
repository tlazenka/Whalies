#if canImport(UIKit) && canImport(SpriteKit)
import CoreGraphics
import Foundation
import WhaleyCore
import WhaleyObjectiveC

/// One conversion of authoritative Objective-C state for RealityKit and the
/// read-only CLI relay. Geometry and roles are observations, not a simulation.
@MainActor
public struct WhaleyLiveSceneCapture {
    public let snapshot: WhaleySceneSnapshot
    public let precisePlayer: WhaleyProjection3D.Position2D
    public let tileWidth: Double
    public let tileHeight: Double

    private static var captureSession: String?
    private static var captureSequence = 0

    public static func current() -> Self? {
        let level = WhaleySrcCurrentLevelNumber()
        guard level > 0 else { return nil }
        let data = WhaleySrcSceneSnapshotElements()
        let tileWidth = (data["tileWidth"] as? NSNumber)?.doubleValue ?? 0
        let tileHeight = (data["tileHeight"] as? NSNumber)?.doubleValue ?? 0
        guard tileWidth > 0, tileHeight > 0,
              tileWidth.isFinite, tileHeight.isFinite else { return nil }

        func dimensions(_ raw: Any?) -> WhaleySceneSnapshot.Dimensions? {
            guard let raw = raw as? [String: Any],
                  let width = (raw["width"] as? NSNumber)?.doubleValue,
                  let height = (raw["height"] as? NSNumber)?.doubleValue else { return nil }
            let result = WhaleySceneSnapshot.Dimensions(width: width, height: height)
            return result.isValid ? result : nil
        }
        var playerGeometry: WhaleySceneSnapshot.PlayerGeometry?
        if let raw = data["playerGeometry"] as? [String: Any],
           let x = (raw["x"] as? NSNumber)?.doubleValue,
           let y = (raw["y"] as? NSNumber)?.doubleValue,
           let size = dimensions(raw["dimensions"]) {
            let value = WhaleySceneSnapshot.PlayerGeometry(x: x, y: y, dimensions: size)
            if value.isValid { playerGeometry = value }
        }

        // Preserve the player's original-origin integer cells for the terminal.
        let origin = WhaleySrcPlayerPosition()
        let center = WhaleySrcPlayerCenter()
        let px = Double(origin.x) / tileWidth
        let py = Double(origin.y) / tileHeight
        let exactX = playerGeometry?.x ?? Double(center.x) / tileWidth
        let exactY = playerGeometry?.y ?? Double(center.y) / tileHeight
        guard px.isFinite, py.isFinite, exactX.isFinite, exactY.isFinite,
              let cellX = Int(exactly: floor(px)),
              let cellY = Int(exactly: floor(py)) else { return nil }

        let elements: [WhaleySceneSnapshot.Element] =
            (data["elements"] as? [[String: Any]] ?? []).compactMap { raw in
                guard let name = raw["kind"] as? String,
                      let kind = WhaleySceneSnapshot.Kind(rawValue: name),
                      let x = (raw["x"] as? NSNumber)?.intValue,
                      let y = (raw["y"] as? NSNumber)?.intValue else { return nil }
                return .init(kind: kind, x: x, y: y)
            }
        let liveEntities: [WhaleySceneSnapshot.LiveEntity]? =
            (data["liveEntities"] as? [[String: Any]]).map { objects in
                objects.compactMap { raw in
                    guard let id = raw["id"] as? String,
                          let name = raw["kind"] as? String,
                          let kind = WhaleySceneSnapshot.Kind(rawValue: name),
                          let x = (raw["x"] as? NSNumber)?.doubleValue,
                          let y = (raw["y"] as? NSNumber)?.doubleValue,
                          !id.isEmpty, x.isFinite, y.isFinite else { return nil }
                    let role = (raw["bubbleRole"] as? String)
                        .flatMap(WhaleySceneSnapshot.BubbleRole.init(rawValue:))
                    return .init(id: id, kind: kind, x: x, y: y,
                        dimensions: dimensions(raw["dimensions"]),
                        bubbleRole: kind == .bubble ? role : nil)
                }
            }
        let session = (data["session"] as? String) ?? "live-2d"
        if session != captureSession {
            captureSession = session
            captureSequence = 0
        }
        // All consumers share capture order; a publisher may observe gaps.
        captureSequence += 1
        return .init(
            snapshot: WhaleySceneSnapshot(
                sequence: captureSequence, session: session,
                level: level, gameTime: WhaleySrcGameTime(),
                dead: WhaleySrcAdventurePlayerIsDead(),
                player: .init(x: cellX, y: cellY), elements: elements,
                liveEntities: liveEntities, playerGeometry: playerGeometry),
            precisePlayer: .init(x: exactX, y: exactY),
            tileWidth: tileWidth, tileHeight: tileHeight)
    }
}

#endif
