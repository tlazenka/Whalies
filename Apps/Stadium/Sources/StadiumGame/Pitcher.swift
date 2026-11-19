import StadiumCore
import CrowdCore

/// Local coordinates point toward third base (+x), up (+y), and home plate (+z).
public struct PitcherParameters: Hashable, Sendable, Codable {
    public var rubber: Vec3
    public var head: Vec3
    public var middle: Vec3
    public var feet: Vec3
    public var glove: Vec3
    public var headR: Fixed
    public var torsoR: Fixed
    public var tossHeight: Fixed
    public var tossAir: Int
    public var tossHeld: Int
    public var fadeEase: Fixed
    public var fadeSnap: Fixed
    public var onHimBehind: Fixed
    public var onHimUp: Fixed
    public var zoomIn: Fixed
    public var gardenMargin: Fixed
    public var dollReach: Fixed
    public var captureRadius: Fixed
    public var holdLimit: Int
    /// Measure flicks in screen points per tick; speedPerPoint converts to metres per second.
    public var flickTicks: Int
    public var flickMin: Fixed
    public var speedPerPoint: Fixed
    public var maxSpeed: Fixed
    public var depthGain: Fixed
    public var launch: Fixed
    /// gravity is the velocity decrement per tick; bounceKeep and rollKeep retain horizontal speed.
    public var gravity: Fixed
    public var ballRadius: Fixed
    public var restitution: Fixed
    public var bounceKeep: Fixed
    public var rollKeep: Fixed
    public var settleSpeed: Fixed
    public var flightMax: Int
    public var wallRadius: Fixed
    public var wallHeight: Fixed
    public var standsBack: Fixed
    public var standsRise: Fixed
    public var fieldRange: Fixed
    public var fieldHeight: Fixed
    public var fanReach: Fixed
    public var ownAfter: Int
    public var pickUp: Fixed
    /// Keep the ball on screen briefly after calls that do not turn the crew toward the pitcher.
    public var crewAfterCall: Int
    /// points and hold are indexed by the first four ThrowOutcome raw values.
    public var points: [Int]
    public var hold: [Int]
    public var callDelay: Int
    public var reset: Int

    public init(rubber: Vec3, head: Vec3, middle: Vec3, feet: Vec3, glove: Vec3, headR: Fixed, torsoR: Fixed, tossHeight: Fixed, tossAir: Int,
                tossHeld: Int, fadeEase: Fixed, fadeSnap: Fixed, onHimBehind: Fixed, onHimUp: Fixed, zoomIn: Fixed, gardenMargin: Fixed,
                dollReach: Fixed, captureRadius: Fixed,
                holdLimit: Int, flickTicks: Int, flickMin: Fixed, speedPerPoint: Fixed, maxSpeed: Fixed, depthGain: Fixed, launch: Fixed, gravity: Fixed,
                ballRadius: Fixed, restitution: Fixed, bounceKeep: Fixed, rollKeep: Fixed, settleSpeed: Fixed, flightMax: Int, wallRadius: Fixed,
                wallHeight: Fixed, standsBack: Fixed, standsRise: Fixed, fieldRange: Fixed, fieldHeight: Fixed, fanReach: Fixed, ownAfter: Int,
                pickUp: Fixed, crewAfterCall: Int, points: [Int], hold: [Int], callDelay: Int, reset: Int) {
        self.rubber = rubber; self.head = head; self.middle = middle; self.feet = feet; self.glove = glove; self.headR = headR; self.torsoR = torsoR
        self.tossHeight = tossHeight; self.tossAir = tossAir; self.tossHeld = tossHeld; self.fadeEase = fadeEase; self.fadeSnap = fadeSnap
        self.onHimBehind = onHimBehind; self.onHimUp = onHimUp; self.zoomIn = zoomIn; self.gardenMargin = gardenMargin
        self.dollReach = dollReach; self.captureRadius = captureRadius; self.holdLimit = holdLimit
        self.flickTicks = flickTicks; self.flickMin = flickMin; self.speedPerPoint = speedPerPoint; self.maxSpeed = maxSpeed; self.depthGain = depthGain
        self.launch = launch; self.gravity = gravity; self.ballRadius = ballRadius; self.restitution = restitution; self.bounceKeep = bounceKeep
        self.rollKeep = rollKeep; self.settleSpeed = settleSpeed; self.flightMax = flightMax; self.wallRadius = wallRadius; self.wallHeight = wallHeight
        self.standsBack = standsBack; self.standsRise = standsRise; self.fieldRange = fieldRange; self.fieldHeight = fieldHeight; self.fanReach = fanReach
        self.ownAfter = ownAfter; self.pickUp = pickUp; self.crewAfterCall = crewAfterCall; self.points = points
        self.hold = hold; self.callDelay = callDelay; self.reset = reset
    }

    public static let stadium = PitcherParameters(
        rubber: Vec3(Fixed(0.0), Fixed(0.25), Fixed(18.44)),
        head: Vec3(Fixed(0.0), Fixed(1.85), Fixed(-0.05)), middle: Vec3(Fixed(0.0), Fixed(0.95), Fixed(0.3)),
        feet: Vec3(Fixed(0.0), Fixed(0.0), Fixed(0.35)), glove: Vec3(Fixed(0.25), Fixed(1.1), Fixed(0.0)),
        headR: Fixed(0.15), torsoR: Fixed(0.35),
        tossHeight: Fixed(0.8), tossAir: 48, tossHeld: 24,
        fadeEase: Fixed(0.1), fadeSnap: Fixed(1.0 / 256.0), onHimBehind: Fixed(3.0), onHimUp: Fixed(2.7), zoomIn: Fixed(0.5), gardenMargin: Fixed(0.02),
        dollReach: Fixed(125.0),
        captureRadius: Fixed(32.0), holdLimit: 180,
        flickTicks: 4, flickMin: Fixed(6.0), speedPerPoint: .one, maxSpeed: Fixed(32.0), depthGain: Fixed(2.0), launch: degrees(25),
        gravity: Fixed(9.8 / 60.0), ballRadius: Fixed(0.037), restitution: Fixed(0.45), bounceKeep: Fixed(0.75), rollKeep: Fixed(0.97),
        settleSpeed: Fixed(0.3), flightMax: 360, wallRadius: Fixed(69.5), wallHeight: Fixed(1.5), standsBack: Fixed(80.0), standsRise: Fixed(5.0),
        fieldRange: Fixed(4.0), fieldHeight: Fixed(3.0), fanReach: Fixed(0.3), ownAfter: 10, pickUp: Fixed(5.0),
        crewAfterCall: 60,
        points: [150, 100, 50, 50], hold: [270, 270, 360, 180], callDelay: 15, reset: 120
    )

    /// Third base is -x from the rubber; home plate is -z.
    public func point(_ local: Vec3) -> Vec3 { Vec3(rubber.x - local.x, rubber.y + local.y, rubber.z - local.z) }

    public var figure: Figure {
        Figure(x: rubber.x, base: rubber.y, z: rubber.z, headY: rubber.y + head.y, torsoY: rubber.y + middle.y, headR: headR, torsoR: torsoR)
    }
}

public enum Base: Int, Hashable, Sendable, Codable, CaseIterable {
    case first = 0, second = 1, third = 2

    public var name: String {
        switch self {
        case .first: "first"
        case .second: "second"
        case .third: "third"
        }
    }
}

public enum Catcher: Int, Hashable, Sendable, Codable {
    case atPlate = 0, atBase = 1, outfield = 2, pitcherHimself = 3, fan = 4, nobody = 5

    public var name: String {
        switch self {
        case .atPlate: "at the plate"
        case .atBase: "at a base"
        case .outfield: "in the outfield"
        case .pitcherHimself: "the pitcher"
        case .fan: "a fan"
        case .nobody: "nobody"
        }
    }
}

public struct Fielder: Hashable, Sendable {
    public var name: String
    public var who: Catcher
    public var base: Base?
    public var x: Fixed
    public var z: Fixed
    public var headY: Fixed
    public var torsoY: Fixed

    public static let all = [
        Fielder(name: "catcher", who: .atPlate, base: nil, x: Fixed(0.0), z: Fixed(-1.5), headY: Fixed(1.0), torsoY: Fixed(0.55)),
        Fielder(name: "batter", who: .atPlate, base: nil, x: Fixed(-0.9), z: Fixed(-0.4), headY: Fixed(1.7), torsoY: Fixed(1.0)),
        Fielder(name: "umpire", who: .atPlate, base: nil, x: Fixed(0.0), z: Fixed(-2.6), headY: Fixed(1.6), torsoY: Fixed(1.0)),
        Fielder(name: "first baseman", who: .atBase, base: .first, x: Fixed(18.9), z: Fixed(18.6), headY: Fixed(1.75), torsoY: Fixed(1.0)),
        Fielder(name: "second baseman", who: .atBase, base: .second, x: Fixed(6.0), z: Fixed(33.0), headY: Fixed(1.75), torsoY: Fixed(1.0)),
        Fielder(name: "shortstop", who: .atBase, base: .second, x: Fixed(-6.0), z: Fixed(33.0), headY: Fixed(1.75), torsoY: Fixed(1.0)),
        Fielder(name: "third baseman", who: .atBase, base: .third, x: Fixed(-18.9), z: Fixed(18.6), headY: Fixed(1.75), torsoY: Fixed(1.0)),
        Fielder(name: "left fielder", who: .outfield, base: nil, x: Fixed(-30.0), z: Fixed(85.0), headY: Fixed(1.75), torsoY: Fixed(1.0)),
        Fielder(name: "center fielder", who: .outfield, base: nil, x: Fixed(0.0), z: Fixed(102.0), headY: Fixed(1.75), torsoY: Fixed(1.0)),
        Fielder(name: "right fielder", who: .outfield, base: nil, x: Fixed(30.0), z: Fixed(85.0), headY: Fixed(1.75), torsoY: Fixed(1.0)),
    ]

    public func figure(_ pz: PitcherParameters) -> Figure {
        Figure(x: x, base: .zero, z: z, headY: headY, torsoY: torsoY, headR: pz.headR, torsoR: pz.torsoR)
    }

    /// Runners are presentation only and never field a ball.
    public static let runnerSpots = [Vec3(Fixed(18.0), Fixed(0.0), Fixed(20.8)), Vec3(Fixed(-1.4), Fixed(0.0), Fixed(37.4)),
                                     Vec3(Fixed(-17.9), Fixed(0.0), Fixed(18.0))]

    public static let runnerSets: [[Base]] = [[.first], [.second], [.first, .second], [.first, .third]]
}

public func nearFigure(_ f: Figure, _ point: Vec3, reach: Fixed, ballRadius: Fixed) -> Bool {
    for (centre, radius) in [(f.head, f.headR + ballRadius), (f.torso, f.torsoR + reach + ballRadius)] {
        let d = point - centre
        if d.dot(d) <= radius * radius { return true }
    }
    return false
}

public func withinSteps(_ f: Figure, _ point: Vec3, steps: Fixed, height: Fixed) -> Bool {
    let dx = point.x - f.x, dz = point.z - f.z
    return point.y - f.base <= height && dx * dx + dz * dz <= steps * steps
}

public enum BallState: Int, Hashable, Sendable, Codable {
    case tossing = 0
    case captured = 1
    case flying = 2
    case settled = 3
    case dead = 4
}

public struct Ball: Hashable, Sendable, Codable {
    public var state: BallState
    public var pos: Vec3
    public var vel = Vec3(.zero, .zero, .zero)
    public var bubble = -1
    public var depth = Fixed.zero
    public var since: Int
    public var rolling = false

    public init(state: BallState, pos: Vec3, since: Int) { self.state = state; self.pos = pos; self.since = since }
}

/// held means an automatic drop after the hold limit; cancelled touches use dropped.
public enum ReleaseKind: Int, Hashable, Sendable, Codable {
    case thrown = 0, dropped = 1, held = 2
}

/// Raw values 0...3 index the balk points and camera holds; keep their order stable.
public enum ThrowOutcome: Int, Hashable, Sendable, Codable, CaseIterable {
    /// The simulation treats a catch at an empty base as a balk.
    case unoccupiedBase = 0
    /// The simulation treats a delivery to the plate while off the rubber as an illegal pitch.
    case illegalPitch = 1
    /// Holding the ball too long or throwing it out of play leaves the pitcher without it.
    case noBall = 2
    /// A release without a flick.
    case dropped = 3
    case pickoff = 4
    case hisOwn = 5

    public var isBalk: Bool { rawValue < ThrowOutcome.pickoff.rawValue }

    public var headline: String {
        switch self {
        case .unoccupiedBase: "UNOCCUPIED BASE"
        case .illegalPitch: "ILLEGAL PITCH"
        case .noBall: "NO BALL ON THE RUBBER"
        case .dropped: "DROPPED BALL"
        case .pickoff: "PICKOFF"
        case .hisOwn: "HIS OWN"
        }
    }

    /// Numbers follow Baseball Reference's balk list; rule identifies the Official Baseball Rule.
    public var number: String? {
        switch self {
        case .unoccupiedBase: "4"
        case .illegalPitch: "5"
        case .noBall: "8/9"
        case .dropped: "11"
        default: nil
        }
    }
    public var rule: String? {
        switch self {
        case .unoccupiedBase: "6.02(a)(4)"
        case .illegalPitch: "6.02(a)(5), 6.02(a)(7)"
        case .noBall: "6.02(a)(8), 6.02(a)(9)"
        case .dropped: "6.02(a)(11)"
        default: nil
        }
    }

    public static func judge(who: Catcher, base: Base?, runners: [Base]) -> ThrowOutcome {
        if who == .atPlate { return .illegalPitch }
        if who == .atBase { return base.map { runners.contains($0) } == true ? .pickoff : .unoccupiedBase }
        if who == .pitcherHimself { return .hisOwn }
        return .noBall
    }
}

/// Unreached event ticks and an absent catcher index use -1.
public struct Throw: Hashable, Sendable, Codable {
    public var captured: Int
    public var released = -1
    public var how: ReleaseKind?
    public var speed = Fixed.zero
    public var way = Fixed.zero
    public var ended = -1
    public var who = Catcher.nobody
    public var by = -1
    public var base: Base?
    public var outcome: ThrowOutcome?
    public var call = -1
    public var trail: [PicturePoint]
    public var finger: PicturePoint

    public init(captured: Int, finger: PicturePoint) { self.captured = captured; trail = [finger]; self.finger = finger }
}

public struct BalkCall: Hashable, Sendable, Codable {
    public var type: ThrowOutcome
    public var released: Int
    public var call: Int
    public var points: Int
    public var until: Int
}

public struct ThrowStatus: Hashable, Sendable, Codable {
    public var captured: Int
    public var released: Int
    public var how: ReleaseKind?
    public var who: Catcher
    public var by: Int
    public var base: Base?
    public var outcome: ThrowOutcome
    public var points: Int
    public var call: Int
}

public enum CrewSubject: Int, Hashable, Sendable, Codable {
    case free = 0, ball = 1, pitcher = 2
    case fan = 3

    public var name: String {
        switch self {
        case .free: "free"
        case .ball: "the ball"
        case .pitcher: "the pitcher"
        case .fan: "the interlude's fan"
        }
    }
}

public struct PitcherSnapshot: Hashable, Sendable {
    public var inView: Bool
    public var fade: Fixed
    public var crew: CrewSubject
    public var engaged: Bool
    public var tossStart: Int
    public var ball: Ball
    public var runners: [Base]
    public var throwInPlay: Throw?
    public var attentionFrom: Int
    public var attentionUntil: Int

    public func camerasOnHim(at t: Int) -> Bool { attentionFrom <= t && t < attentionUntil }
}
