import StadiumCore

public struct Figure: Hashable, Sendable, Codable {
    public var x: Fixed
    public var base: Fixed
    public var z: Fixed
    public var headY: Fixed
    public var torsoY: Fixed
    public var headR: Fixed
    public var torsoR: Fixed

    public init(x: Fixed, base: Fixed, z: Fixed, headY: Fixed, torsoY: Fixed, headR: Fixed, torsoR: Fixed) {
        self.x = x; self.base = base; self.z = z; self.headY = headY; self.torsoY = torsoY; self.headR = headR; self.torsoR = torsoR
    }

    public var head: Vec3 { Vec3(x, headY, z) }
    public var torso: Vec3 { Vec3(x, torsoY, z) }
    public var seat: Vec3 { Vec3(x, base, z) }
}

/// Encodes as [radius, base].
public struct StandRow: Hashable, Sendable, Codable {
    public var radius: Fixed
    public var base: Fixed
    public init(radius: Fixed, base: Fixed) { self.radius = radius; self.base = base }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        radius = try c.decode(Fixed.self); base = try c.decode(Fixed.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(radius); try c.encode(base)
    }
}

public struct StandsParameters: Hashable, Sendable, Codable {
    public var centre: GroundPoint
    public var rows: [StandRow]
    public var seats: Int
    /// The first seat's bearing; subsequent seats run counterclockwise.
    public var start: Fixed
    public var headHeight: Fixed
    public var torsoHeight: Fixed
    public var headR: Fixed
    public var torsoR: Fixed

    public init(centre: GroundPoint, rows: [StandRow], seats: Int, start: Fixed, headHeight: Fixed, torsoHeight: Fixed, headR: Fixed, torsoR: Fixed) {
        self.centre = centre; self.rows = rows; self.seats = seats; self.start = start; self.headHeight = headHeight
        self.torsoHeight = torsoHeight; self.headR = headR; self.torsoR = torsoR
    }

    public static let stadium = StandsParameters(
        centre: GroundPoint(.zero, Fixed(45.0)),
        rows: [StandRow(radius: Fixed(70.0), base: Fixed(2.0)), StandRow(radius: Fixed(74.0), base: Fixed(4.5)), StandRow(radius: Fixed(78.0), base: Fixed(7.0))],
        seats: 64,
        start: Fixed(raw: 2 * Trig.quarter),
        headHeight: Fixed(1.4), torsoHeight: Fixed(0.8), headR: Fixed(0.25), torsoR: Fixed(0.45)
    )

    public func bearing(seat k: Int) -> Fixed {
        Fixed(raw: Trig.normalize(start.raw - Int64(k) * (Trig.turn / Int64(seats))))
    }

    public func figures() -> [Figure] {
        var out: [Figure] = []
        for row in rows {
            for k in 0..<seats {
                let a = bearing(seat: k)
                out.append(Figure(x: centre.x + row.radius * Trig.sin(a), base: row.base, z: centre.z + row.radius * Trig.cos(a),
                                  headY: row.base + headHeight, torsoY: row.base + torsoHeight, headR: headR, torsoR: torsoR))
            }
        }
        return out
    }

    public func place(of figure: Int) -> (row: Int, seat: Int) { (figure / seats, figure % seats) }
}
