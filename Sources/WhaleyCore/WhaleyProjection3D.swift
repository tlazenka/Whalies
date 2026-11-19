// A renderer-independent spatial projection of the existing Whaley snapshot.
// Projection never advances physics, evaluates collisions or owns gameplay state.
public enum WhaleyProjection3D {
    public struct Point: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    public struct Position2D: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public enum Kind: String, Sendable, Codable, Hashable {
        case player, wall, ground, bubble, coin, flame, goal
    }

    public struct Object: Sendable, Equatable, Identifiable {
        public let id: String
        public let kind: Kind
        public let center: Point
        public let size: Point
        public let bubbleRole: WhaleySceneSnapshot.BubbleRole?

        public init(id: String, kind: Kind, center: Point, size: Point,
                    bubbleRole: WhaleySceneSnapshot.BubbleRole? = nil) {
            self.id = id
            self.kind = kind
            self.center = center
            self.size = size
            self.bubbleRole = kind == .bubble ? bubbleRole : nil
        }
    }

    public struct World: Sendable, Equatable {
        public let level: Int
        public let gameTime: Double
        public let player: Object
        public let objects: [Object]
        public let session: String

        public init(level: Int, gameTime: Double, player: Object,
                    objects: [Object], session: String = "") {
            self.level = level
            self.gameTime = gameTime
            self.player = player
            self.objects = objects
            self.session = session
        }

        public var cameraFocus: Point { player.center }

        /// The complete visible scene. `objects` intentionally contains only
        /// scenery/projectiles; using it alone makes Whaley disappear, and an
        /// anchored camera then makes real repeated bounces look stationary.
        public var renderObjects: [Object] { [player] + objects }
    }

    private static func geometry(for kind: Kind) -> (Point, Double) {
        switch kind {
        case .wall, .ground:
            return (Point(x: 1, y: 1, z: 0.72), -0.15)
        case .bubble:
            return (Point(x: 0.66, y: 0.66, z: 0.66), 0.46)
        case .coin:
            return (Point(x: 0.45, y: 0.45, z: 0.20), 0.48)
        case .flame:
            return (Point(x: 0.60, y: 0.78, z: 0.55), 0.48)
        case .goal:
            return (Point(x: 0.84, y: 0.84, z: 0.84), 0.50)
        case .player:
            return (Point(x: 0.72, y: 0.72, z: 0.72), 0.65)
        }
    }

    private static func size(for kind: Kind, dimensions: WhaleySceneSnapshot.Dimensions?) -> Point {
        let fallback = geometry(for: kind).0
        guard let dimensions, dimensions.isValid else { return fallback }
        // XY comes from the engine. Z remains presentation-only extrusion.
        let depth = kind == .bubble ? min(dimensions.width, dimensions.height) : fallback.z
        return Point(x: dimensions.width, y: dimensions.height, z: depth)
    }

    /// One game tile maps to one 3D unit. Original X/Y stay in the same plane;
    /// Z is extrusion only, not a new axis of gameplay or a second simulation.
    public static func project(
        _ snapshot: WhaleySceneSnapshot,
        precisePlayer: Position2D? = nil
    ) -> World {
        let p = snapshot.player
        let precise = precisePlayer.flatMap { position -> Position2D? in
            position.x.isFinite && position.y.isFinite &&
                Float(position.x).isFinite && Float(position.y).isFinite ? position : nil
        }
        let recordedPlayer = snapshot.playerGeometry.flatMap { $0.isValid ? $0 : nil }
        let player = Object(
            id: "player",
            kind: .player,
            center: Point(x: precise?.x ?? recordedPlayer?.x ?? Double(p.x) + 0.5,
                          y: precise?.y ?? recordedPlayer?.y ?? Double(p.y) + 0.5, z: 0.65),
            size: size(for: .player, dimensions: recordedPlayer?.dimensions)
        )

        // The original cell snapshot remains a supported wire format. When
        // liveEntities is present (including an empty array), it becomes the
        // authoritative dynamic-object set; static tiles remain cell-based.
        // This avoids creating a ghost object in the previous cell when a
        // bubble crosses a tile boundary.
        let hasLiveEntities = snapshot.liveEntities != nil
        var byID: [String: Object] = [:]
        for element in snapshot.elements {
            guard let kind = Kind(rawValue: element.kind.rawValue), kind != .player else {
                continue
            }
            if hasLiveEntities && kind != .wall && kind != .ground { continue }
            let id = "\(kind.rawValue):\(element.x):\(element.y)"
            let (size, depth) = geometry(for: kind)
            byID[id] = Object(
                id: id, kind: kind,
                center: Point(x: Double(element.x) + 0.5,
                              y: Double(element.y) + 0.5, z: depth),
                size: size
            )
        }

        for live in snapshot.liveEntities ?? [] {
            guard let kind = Kind(rawValue: live.kind.rawValue),
                  kind != .wall && kind != .ground && kind != .player,
                  !live.id.isEmpty, live.x.isFinite, live.y.isFinite,
                  Float(live.x).isFinite, Float(live.y).isFinite
            else { continue }
            let depth = geometry(for: kind).1
            let id = "live:\(kind.rawValue):\(live.id)"
            byID[id] = Object(
                id: id, kind: kind,
                center: Point(x: live.x, y: live.y, z: depth),
                size: size(for: kind, dimensions: live.dimensions),
                bubbleRole: live.bubbleRole
            )
        }
        return World(
            level: snapshot.level,
            gameTime: snapshot.gameTime,
            player: player,
            objects: byID.values.sorted { $0.id < $1.id },
            session: snapshot.session
        )
    }
}
