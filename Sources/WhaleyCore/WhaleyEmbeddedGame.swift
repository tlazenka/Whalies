import Foundation

/// Configuration for another application surface hosting the existing native game.
/// A session ID identifies the host's lifetime, not an independently simulated world.
public struct WhaleyEmbeddedConfiguration: Codable, Hashable, Sendable {
    public let sessionID: String
    public let level: Int
    public let width: Double
    public let height: Double
    /// A containing game can keep its own soundtrack while using the native
    /// Whaley simulation. Standalone and existing embedded callers remain audible.
    public let soundEffectsEnabled: Bool

    public init(sessionID: String, level: Int = 1, width: Double = 320, height: Double = 180,
                soundEffectsEnabled: Bool = true) {
        self.sessionID = sessionID
        self.level = level
        self.width = width
        self.height = height
        self.soundEffectsEnabled = soundEffectsEnabled
    }

    private enum CodingKeys: String, CodingKey { case sessionID, level, width, height, soundEffectsEnabled }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        level = try values.decode(Int.self, forKey: .level)
        width = try values.decode(Double.self, forKey: .width)
        height = try values.decode(Double.self, forKey: .height)
        soundEffectsEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEffectsEnabled) ?? true
    }

    public var isValid: Bool {
        !sessionID.isEmpty && (1...6).contains(level)
            && width.isFinite && height.isFinite && width >= 32 && height >= 32
    }
}

/// A projectile supplied by a containing world. Positions are centers in logical
/// screen points, measured from the bottom-left. The native game transforms them
/// through its current camera and alone decides contact, bounce and consumption.
/// The containing world draws these bubbles; the native collision proxies are hidden.
public struct WhaleyEmbeddedBubble: Codable, Hashable, Sendable {
    public let id: String
    public let x: Double
    public let y: Double
    public let diameter: Double
    public let remainingUses: Int
    public let fixed: Bool
    public let held: Bool

    public init(id: String, x: Double, y: Double, diameter: Double,
                remainingUses: Int, fixed: Bool, held: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.diameter = diameter
        self.remainingUses = remainingUses
        self.fixed = fixed
        self.held = held
    }

    public var isValid: Bool {
        !id.isEmpty && x.isFinite && y.isFinite && diameter.isFinite && diameter > 0
            && remainingUses >= 0
    }
}

/// Outcomes emitted at the canonical engine's actual collision/collection sites.
/// Consumers can assign their own rewards without reimplementing those rules.
public enum WhaleyEmbeddedEvent: Codable, Hashable, Sendable {
    case bubbleContact(id: String, remainingUses: Int, popped: Bool, bounced: Bool)
    case coinCollected
    case died
    case levelCompleted
}

/// A read-only observation of the authoritative game. Player coordinates are its
/// lower-left origin in level points; layerX/layerY are the game's camera offset.
/// Each event batch is delivered once. Sequence increases for this host session.
public struct WhaleyEmbeddedFrame: Codable, Hashable, Sendable {
    public let sessionID: String
    public let sequence: Int
    public let level: Int
    public let gameTime: Double
    public let layerX: Double
    public let layerY: Double
    public let playerX: Double
    public let playerY: Double
    public let playerWidth: Double
    public let playerHeight: Double
    public let dead: Bool
    public let completed: Bool
    public let events: [WhaleyEmbeddedEvent]

    public init(sessionID: String, sequence: Int, level: Int, gameTime: Double,
                layerX: Double, layerY: Double, playerX: Double, playerY: Double,
                playerWidth: Double, playerHeight: Double, dead: Bool, completed: Bool,
                events: [WhaleyEmbeddedEvent]) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.level = level
        self.gameTime = gameTime
        self.layerX = layerX
        self.layerY = layerY
        self.playerX = playerX
        self.playerY = playerY
        self.playerWidth = playerWidth
        self.playerHeight = playerHeight
        self.dead = dead
        self.completed = completed
        self.events = events
    }
}
