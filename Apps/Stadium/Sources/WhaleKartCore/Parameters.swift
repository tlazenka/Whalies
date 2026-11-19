import StadiumCore

public struct KartParameters: Hashable, Sendable, Codable {
    /// Hitch offsets are metres right of the kart axis; left is negative.
    public var hitches: [Fixed]
    /// Cans per string, ordered from the hitch outward.
    public var cans: Int
    public var segment: Fixed
    public var canRadius: Fixed
    public var hitchOffset: Fixed
    public var dt: Fixed
    public var gravity: Fixed
    public var damping: Fixed
    public var groundFriction: Fixed
    public var tautEps: Fixed
    public var iterations: Int
    public var tossUp: Fixed
    public var airborneTicks: Int
    public var cruiseSpeed: Fixed
    public var accel: Fixed
    public var decel: Fixed
    /// Pure pursuit uses a lookahead distance in metres and a steerGain of 1/pi for turns.
    public var lookahead: Fixed
    public var steerGain: Fixed
    public var yawMax: Fixed
    public var roadHalf: Fixed
    public var trackPoints: [GroundPoint]

    public init(hitches: [Fixed], cans: Int, segment: Fixed, canRadius: Fixed, hitchOffset: Fixed, dt: Fixed, gravity: Fixed,
                damping: Fixed, groundFriction: Fixed, tautEps: Fixed, iterations: Int, tossUp: Fixed, airborneTicks: Int,
                cruiseSpeed: Fixed, accel: Fixed, decel: Fixed, lookahead: Fixed, steerGain: Fixed, yawMax: Fixed, roadHalf: Fixed,
                trackPoints: [GroundPoint]) {
        self.hitches = hitches; self.cans = cans; self.segment = segment; self.canRadius = canRadius; self.hitchOffset = hitchOffset
        self.dt = dt; self.gravity = gravity; self.damping = damping; self.groundFriction = groundFriction; self.tautEps = tautEps
        self.iterations = iterations; self.tossUp = tossUp; self.airborneTicks = airborneTicks; self.cruiseSpeed = cruiseSpeed
        self.accel = accel; self.decel = decel; self.lookahead = lookahead; self.steerGain = steerGain; self.yawMax = yawMax
        self.roadHalf = roadHalf; self.trackPoints = trackPoints
    }

    public var canCount: Int { hitches.count * cans }

    public func string(of can: Int) -> Int { can / cans }
    public func place(of can: Int) -> Int { can % cans }

    public func isRight(_ can: Int) -> Bool { can >= 0 && can < canCount && Fixed.zero < hitches[string(of: can)] }

    /// Home plate is the origin; +z points to center field and +x to right field.
    public static let fieldCentre = GroundPoint(.zero, Fixed(45.0))

    /// Counterclockwise points from start, using fixed-point arithmetic for replay parity.
    public static func ringPoints(centre: GroundPoint, radius: Fixed, count: Int, start: Fixed) -> [GroundPoint] {
        let step = Trig.turn / Int64(count)
        return (0..<count).map { k in
            let a = Fixed(raw: Trig.normalize(start.raw - Int64(k) * step))
            return GroundPoint(centre.x + radius * Trig.sin(a), centre.z + radius * Trig.cos(a))
        }
    }

    /// Near and far arcs join through outward semicircles, starting at the near midpoint.
    /// arc must be odd so that midpoint is a vertex.
    public static func loopPoints(centre: GroundPoint, toward: Fixed, near: Fixed, far: Fixed, span: Fixed, arc: Int = 17,
                                  turn: Int = 10) -> [GroundPoint] {
        let mid = Fixed(raw: (near.raw + far.raw) / 2), r = Fixed(raw: (far.raw - near.raw) / 2)
        let half = Trig.turn / 2
        func at(_ c: GroundPoint, _ radius: Fixed, _ b: Int64) -> GroundPoint {
            let a = Fixed(raw: Trig.normalize(b))
            return GroundPoint(c.x + radius * Trig.sin(a), c.z + radius * Trig.cos(a))
        }
        let t = toward.raw, s = span.raw, n = Int64(arc - 1), m = Int64(turn)
        let nearArc = (0..<arc).map { k in at(centre, near, t - s + (2 * s * Int64(k)) / n) }
        let farArc = (0..<arc).map { k in at(centre, far, t + s - (2 * s * Int64(k)) / n) }
        let hi = at(centre, mid, t + s), lo = at(centre, mid, t - s)
        let turnHi = (1..<turn).map { k in at(hi, r, t + s + half - (half * Int64(k)) / m) }
        let turnLo = (1..<turn).map { k in at(lo, r, t - s - (half * Int64(k)) / m) }
        let middle = arc / 2
        return Array(nearArc[middle...]) + turnHi + farArc + turnLo + Array(nearArc[..<middle])
    }

    public static let stadium = KartParameters(
        hitches: [Fixed(-0.5), Fixed(0.5)], cans: 3,
        segment: Fixed(1.2), canRadius: Fixed(0.15), hitchOffset: Fixed(1.5),
        dt: Fixed(1.0 / 60.0), gravity: Fixed(9.8), damping: Fixed(0.98), groundFriction: Fixed(0.90), tautEps: Fixed(0.02), iterations: 4,
        tossUp: Fixed(3.0), airborneTicks: 24,
        cruiseSpeed: Fixed(6.0), accel: Fixed(3.0), decel: Fixed(6.0),
        lookahead: Fixed(8.0), steerGain: Fixed(0.3183), yawMax: Fixed(0.12),
        roadHalf: Fixed(5.0),
        trackPoints: ringPoints(centre: fieldCentre, radius: Fixed(62.0), count: 64, start: Fixed(raw: 2 * Trig.quarter))
    )
}
