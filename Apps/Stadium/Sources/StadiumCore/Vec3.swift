// Coordinates use y up and encode as [x, y, z].

public struct Vec3: Hashable, Sendable, Codable {
    public var x: Fixed
    public var y: Fixed
    public var z: Fixed

    public init(_ x: Fixed, _ y: Fixed, _ z: Fixed) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vec3(.zero, .zero, .zero)

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Fixed.self); y = try c.decode(Fixed.self); z = try c.decode(Fixed.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x); try c.encode(y); try c.encode(z)
    }

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }

    public func scaled(by s: Fixed) -> Vec3 { Vec3(x * s, y * s, z * s) }

    public func dot(_ b: Vec3) -> Fixed { x * b.x + y * b.y + z * b.z }

    public var length: Fixed { Fixed.sqrt(dot(self)) }

    /// Multiply before dividing to preserve fixed-point rounding.
    public func scaledTo(length: Fixed, target: Fixed) -> Vec3 {
        Vec3((x * target) / length, (y * target) / length, (z * target) / length)
    }

    /// Multiplication floors negative components; integer division would truncate.
    public var half: Vec3 { Vec3(x * Fixed.half, y * Fixed.half, z * Fixed.half) }
}

/// Ground coordinates encode as [x, z].
public struct GroundPoint: Hashable, Sendable, Codable {
    public var x: Fixed
    public var z: Fixed

    public init(_ x: Fixed, _ z: Fixed) { self.x = x; self.z = z }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Fixed.self); z = try c.decode(Fixed.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x); try c.encode(z)
    }
}
