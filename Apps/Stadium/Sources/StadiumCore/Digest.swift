// FNV-1a over 64-bit integers, low byte first; matches python/whaley_tools/stadium/math.py.

public struct ReplayDigest: Sendable {
    public private(set) var value: UInt64 = 0xcbf29ce484222325

    public init() {}

    public mutating func mix(_ v: Int64) {
        var x = UInt64(bitPattern: v)
        for _ in 0..<8 {
            value ^= x & 0xff
            value = value &* 0x100000001b3
            x >>= 8
        }
    }

    public mutating func mix(_ v: Int) { mix(Int64(v)) }
    public mutating func mix(_ v: Fixed) { mix(v.raw) }
    public mutating func mix(_ v: Bool) { mix(Int64(v ? 1 : 0)) }
    public mutating func mix(_ v: Vec3) { mix(v.x); mix(v.y); mix(v.z) }

    public var hex: String { String(value, radix: 16) }
}
