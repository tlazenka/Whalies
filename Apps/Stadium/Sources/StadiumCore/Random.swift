// SplitMix64 with wrapping arithmetic; the recorded seed reproduces each draw.

public struct Rng: Hashable, Sendable, Codable {
    public private(set) var state: UInt64

    public init(seed: Int64) { state = UInt64(bitPattern: seed) }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Requires n > 0; returns a value in 0..<n.
    public mutating func below(_ n: Int64) -> Int64 { Int64(next() % UInt64(n)) }

    /// Both endpoints are inclusive.
    public mutating func between(_ lo: Int64, _ hi: Int64) -> Int64 { lo + below(hi - lo + 1) }

    public mutating func between(_ lo: Fixed, _ hi: Fixed) -> Fixed { Fixed(raw: between(lo.raw, hi.raw)) }
}
