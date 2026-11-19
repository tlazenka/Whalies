// Whaley owns gameplay and collisions; Stadium exchanges projections and recorded observations.
import StadiumCore
import WhaleKartCore

public struct WhaleyParameters: Hashable, Sendable, Codable {
    public var quadrant: [Fixed]
    public var face: Fixed
    public var screenWidth: Int
    public var screenHeight: Int
    public var coinPoints: Int
    public var goalPoints: Int
    public var zoomWidth: Fixed
    public var zoomTicks: Int
    public var zoomSide: Fixed
    public var zoomTop: Fixed
    public var zoomBottom: Fixed

    public static let stadium = WhaleyParameters(
        quadrant: [degrees(135), degrees(225)], face: Fixed(0.55),
        screenWidth: 320, screenHeight: 180, coinPoints: 25, goalPoints: 250,
        zoomWidth: Fixed(320.0), zoomTicks: 20, zoomSide: Fixed(8.0),
        zoomTop: Fixed(110.0), zoomBottom: Fixed(40.0)
    )
}

func pixels(_ value: Int) -> Fixed { Fixed(raw: Int64(value) << 16) }

public struct LevelSpot: Hashable, Sendable, Codable {
    public var x: Fixed
    public var y: Fixed
    public init(_ x: Fixed, _ y: Fixed) { self.x = x; self.y = y }
}

public struct WhaleyObservation: Hashable, Sendable, Codable {
    public var ready: Bool
    public var number: Int
    public var gameTime: Double
    public var x: Fixed
    public var y: Fixed
    public var width: Fixed
    public var height: Fixed
    public var layer: LevelSpot
    public var dead: Bool
    public var won: Bool

    public init(ready: Bool = false, number: Int = 1, gameTime: Double = 0,
                x: Fixed = .zero, y: Fixed = .zero, width: Fixed = .zero, height: Fixed = .zero,
                layer: LevelSpot = LevelSpot(.zero, .zero), dead: Bool = false, won: Bool = false) {
        self.ready = ready; self.number = number; self.gameTime = gameTime
        self.x = x; self.y = y; self.width = width; self.height = height
        self.layer = layer; self.dead = dead; self.won = won
    }
    public var centreX: Fixed { x + Fixed(raw: width.raw / 2) }
    public var centreY: Fixed { y + Fixed(raw: height.raw / 2) }
}

/// Bubble centers use native screen points with a bottom-left origin.
public struct WhaleyOver: Hashable, Sendable {
    public var id: Int
    public var screenX: Fixed
    public var screenY: Fixed
    public var size: Fixed
    public var moved: Bool
    public var uses: Int
    public var fixed: Bool
}

public enum WhaleyEvent: Hashable, Sendable, Codable {
    case bubbleContact(id: Int, remainingUses: Int, popped: Bool, bounced: Bool)
    case coin
    case died
    case goal

    public var integers: [Int64] {
        switch self {
        case .bubbleContact(let id, let uses, let popped, let bounced):
            [1, Int64(id), Int64(uses), popped ? 1 : 0, bounced ? 1 : 0]
        case .coin: [2]
        case .died: [3]
        case .goal: [4]
        }
    }
}

/// Sequence numbers increase within a session. Save each batch with the consuming
/// Stadium tick so headless replay can reproduce native outcomes.
public struct JumbotronFrame: Hashable, Sendable, Codable {
    public var sessionID: String
    public var sequence: Int
    public var observation: WhaleyObservation
    public var events: [WhaleyEvent]

    public init(sessionID: String, sequence: Int, observation: WhaleyObservation, events: [WhaleyEvent] = []) {
        self.sessionID = sessionID; self.sequence = sequence
        self.observation = observation; self.events = events
    }
}

public struct WhaleySnapshot: Hashable, Sendable {
    public var inQuadrant: Bool
    public var shown: Bool
    public var engaged: Bool
    public var over: [WhaleyOver]
    public var events: [WhaleyEvent]
    public var observation: WhaleyObservation
}

public struct ScreenGeometry: Hashable, Sendable {
    public let face: Vec3
    public let normal: Vec3
    public let right: Vec3
    public let halfWidth: Fixed
    public let halfHeight: Fixed
    public let pixelsPerMetre: Fixed
    public let metresPerPixel: Fixed

    public init(parameters p: StadiumParameters) {
        let w = p.ride.whaley
        let j = p.jumbotron
        let centre = KartParameters.fieldCentre
        let tx = centre.x - j.x, tz = centre.z - j.z
        let length = Fixed.sqrt(tx * tx + tz * tz)
        normal = Vec3(tx / length, .zero, tz / length)
        right = Trig.right(Trig.bearing(dx: -normal.x, dz: -normal.z))
        face = Vec3(j.x + normal.x * w.face, j.y, j.z + normal.z * w.face)
        halfWidth = Fixed(raw: p.jumbotronWidth.raw >> 1)
        halfHeight = Fixed(raw: p.jumbotronHeight.raw >> 1)
        pixelsPerMetre = pixels(w.screenWidth) / p.jumbotronWidth
        metresPerPixel = p.jumbotronWidth / pixels(w.screenWidth)
    }

    /// Clockwise from top-left, as viewed from the field.
    public var corners: [Vec3] {
        let signs: [(Int, Int)] = [(-1, 1), (1, 1), (1, -1), (-1, -1)]
        return signs.map { (su, sv) in
            let across: Vec3 = right.scaled(by: halfWidth * su)
            let up = Vec3(.zero, halfHeight * sv, .zero)
            return face + across + up
        }
    }
}

