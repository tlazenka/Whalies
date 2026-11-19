import Foundation

public struct WhaleySceneSnapshot: Codable, Sendable, Equatable {
    public struct Cell: Codable, Sendable, Hashable {
        public let x: Int
        public let y: Int
        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }
    public enum Kind: String, Codable, Sendable { case wall, ground, bubble, coin, flame, goal }
    public struct Element: Codable, Sendable, Equatable {
        public let kind: Kind
        public let x: Int
        public let y: Int
        public init(kind: Kind, x: Int, y: Int) {
            self.kind = kind
            self.x = x
            self.y = y
        }
    }

    /// Scaled engine dimensions divided by tile width/height respectively.
    /// Depth is deliberately not recorded: gameplay still occupies an XY plane.
    public struct Dimensions: Codable, Sendable, Equatable, Hashable {
        public let width: Double
        public let height: Double
        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
        public var isValid: Bool {
            width.isFinite && height.isFinite && width > 0 && height > 0
                && Float(width).isFinite && Float(height).isFinite
                && Float(width) > 0 && Float(height) > 0
        }
    }

    public enum BubbleRole: String, Codable, Sendable, Hashable {
        case foundation
        case playerCreated
    }

    /// Unlike legacy integer player cells, this preserves the precise center
    /// and footprint for both live display and JSON recording/replay.
    public struct PlayerGeometry: Codable, Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let dimensions: Dimensions
        public init(x: Double, y: Double, dimensions: Dimensions) {
            self.x = x
            self.y = y
            self.dimensions = dimensions
        }
        public var isValid: Bool {
            x.isFinite && y.isFinite && Float(x).isFinite && Float(y).isFinite
                && dimensions.isValid
        }
    }

    /// A continuously positioned object captured from the authoritative scene.
    /// x/y are centers in tile units. Bubble centers use Projectile.position,
    /// not the bottom-left-origin conversion used for Player.
    public struct LiveEntity: Codable, Sendable, Equatable, Hashable {
        public let id: String
        public let kind: Kind
        public let x: Double
        public let y: Double
        public let dimensions: Dimensions?
        /// nil means unspecified/legacy, not a disposable bubble inferred by size.
        public let bubbleRole: BubbleRole?

        public init(id: String, kind: Kind, x: Double, y: Double,
                    dimensions: Dimensions? = nil, bubbleRole: BubbleRole? = nil) {
            self.id = id
            self.kind = kind
            self.x = x
            self.y = y
            self.dimensions = dimensions
            self.bubbleRole = bubbleRole
        }
    }
    public let sequence: Int
    public let session: String
    public let level: Int
    public let gameTime: Double
    public let dead: Bool
    public let player: Cell
    public let elements: [Element]
    /// nil means an older, cell-only snapshot; [] means no live entities.
    public let liveEntities: [LiveEntity]?
    public let playerGeometry: PlayerGeometry?
    public init(
        sequence: Int,
        session: String,
        level: Int,
        gameTime: Double,
        dead: Bool,
        player: Cell,
        elements: [Element],
        liveEntities: [LiveEntity]? = nil,
        playerGeometry: PlayerGeometry? = nil
    ) {
        self.sequence = sequence
        self.session = session
        self.level = level
        self.gameTime = gameTime
        self.dead = dead
        self.player = player
        self.elements = elements
        self.liveEntities = liveEntities
        self.playerGeometry = playerGeometry
    }
}

public enum WhaleyTerminalRenderer {
    public static func lines(_ snapshot: WhaleySceneSnapshot, size: Int) -> [String] {
        let size = max(1, size | 1)
        let half = size / 2
        let left = snapshot.player.x - half
        let bottom = snapshot.player.y - half
        var pixels: [WhaleySceneSnapshot.Cell: Character] = [:]
        for kind in [WhaleySceneSnapshot.Kind.wall, .ground, .coin, .goal, .bubble, .flame] {
            for element in snapshot.elements where element.kind == kind {
                let cell = WhaleySceneSnapshot.Cell(x: element.x, y: element.y)
                pixels[cell] =
                    switch kind {
                    case .wall: "#"
                    case .ground: "="
                    case .coin: "$"
                    case .goal: "O"
                    case .bubble: "o"
                    case .flame: "^"
                    }
            }
        }
        pixels[snapshot.player] = "W"
        var result = ["+" + String(repeating: "-", count: size) + "+"]
        for row in (0..<size).reversed() {
            let characters = (0..<size)
                .map { column in
                    pixels[.init(x: left + column, y: bottom + row)] ?? "·"
                }
            result.append("|" + String(characters) + "|")
        }
        result.append("+" + String(repeating: "-", count: size) + "+")
        return result
    }
}
