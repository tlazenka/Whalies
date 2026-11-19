// 16.16 replay arithmetic must match python/whaley_tools/stadium/math.py bit for bit.

public struct Fixed: Hashable, Sendable, Comparable, Codable {
    public static let fractionBits: Int64 = 16
    public static let one = Fixed(raw: 1 << 16)
    public static let zero = Fixed(raw: 0)
    public static let half = Fixed(raw: 1 << 15)

    public var raw: Int64

    public init(raw: Int64) { self.raw = raw }

    /// Floating-point conversion is reserved for parameters and input quantization.
    public init(_ value: Double) { raw = Int64((value * 65536.0).rounded()) }

    public var double: Double { Double(raw) / 65536.0 }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(Int64.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(raw) }

    public static func < (lhs: Fixed, rhs: Fixed) -> Bool { lhs.raw < rhs.raw }
    public static func + (lhs: Fixed, rhs: Fixed) -> Fixed { Fixed(raw: lhs.raw + rhs.raw) }
    public static func - (lhs: Fixed, rhs: Fixed) -> Fixed { Fixed(raw: lhs.raw - rhs.raw) }
    public static prefix func - (value: Fixed) -> Fixed { Fixed(raw: -value.raw) }
    public static func += (lhs: inout Fixed, rhs: Fixed) { lhs.raw += rhs.raw }
    public static func -= (lhs: inout Fixed, rhs: Fixed) { lhs.raw -= rhs.raw }

    /// Arithmetic right shift floors negative products, matching Python.
    public static func * (lhs: Fixed, rhs: Fixed) -> Fixed { Fixed(raw: (lhs.raw * rhs.raw) >> 16) }

    public static func * (lhs: Fixed, rhs: Int) -> Fixed { Fixed(raw: lhs.raw * Int64(rhs)) }

    /// Divide magnitudes, then restore the sign to truncate toward zero.
    public static func / (lhs: Fixed, rhs: Fixed) -> Fixed {
        let q = (abs(lhs.raw) << 16) / abs(rhs.raw)
        return Fixed(raw: (lhs.raw >= 0) == (rhs.raw >= 0) ? q : -q)
    }

    public var magnitude: Fixed { Fixed(raw: abs(raw)) }

    public func clamped(_ lo: Fixed, _ hi: Fixed) -> Fixed { self < lo ? lo : (hi < self ? hi : self) }

    /// Integer square root avoids platform-dependent floating-point rounding.
    public static func isqrt(_ n: Int64) -> Int64 {
        if n <= 0 { return 0 }
        var n = n
        var bit: Int64 = 1
        while bit <= n >> 2 { bit <<= 2 }
        var r: Int64 = 0
        while bit != 0 {
            if n >= r + bit {
                n -= r + bit
                r = (r >> 1) + bit
            } else {
                r >>= 1
            }
            bit >>= 2
        }
        return r
    }

    public static func sqrt(_ a: Fixed) -> Fixed { Fixed(raw: isqrt(a.raw << 16)) }
}

/// Floor division, matching Python's `//` for signed operands.
public func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    let r = a % b
    return (r != 0 && ((r < 0) != (b < 0))) ? q - 1 : q
}

/// Requires a positive modulus; the result is always nonnegative.
public func floorMod(_ a: Int64, _ b: Int64) -> Int64 {
    let r = a % b
    return r < 0 ? r + b : r
}
