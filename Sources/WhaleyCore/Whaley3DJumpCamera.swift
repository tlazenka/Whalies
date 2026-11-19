import Foundation

/// Presentation-only camera tracking in projected tile units. The original
/// engine owns jump detection, jump origins and the monotonic jump sequence.
public struct Whaley3DJumpCamera: Sendable {
    public typealias Point = WhaleyProjection3D.Point
    public private(set) var eye: Point?
    public private(set) var anchoredStart: Point?
    public private(set) var lastJumpSequence: UInt64?

    public init() {}

    /// Call on an explicit scene/session change. Sequence rollback also resets
    /// automatically, covering a same-level restart after one or more jumps.
    public mutating func reset() {
        eye = nil
        anchoredStart = nil
        lastJumpSequence = nil
    }

    @discardableResult
    public mutating func update(
        playerBottom: Point,
        airborne: Bool,
        jumpSequence: UInt64,
        jumpStartBottom: Point,
        deltaSeconds: Double
    ) -> Point {
        // Reject a bad capture without poisoning a previously valid camera.
        // In particular, don't consume a jump sequence before its data is valid.
        guard Self.isFinite(playerBottom) else {
            return eye ?? Point(x: 0, y: 0, z: 0)
        }
        if let previousSequence = lastJumpSequence, jumpSequence < previousSequence {
            reset()
        }

        if !airborne {
            anchoredStart = nil
        } else if jumpSequence > 0, lastJumpSequence != jumpSequence {
            // A real launch gets its own immutable world-space anchor. Falling
            // before the first launch (sequence zero) is not a new jump.
            anchoredStart = Self.isFinite(jumpStartBottom) ? jumpStartBottom : playerBottom
        }
        lastJumpSequence = jumpSequence
        let target = anchoredStart ?? playerBottom
        guard let previous = eye else {
            eye = target
            return target
        }

        // Smooth only the presentation. Never use the interpolated eye for
        // bubble placement: the authoritative jump origin remains unchanged.
        // Limit unusually large frame gaps to avoid a sudden camera leap.
        let dt = max(0, min(deltaSeconds.isFinite ? deltaSeconds : 0, 0.1))
        let alpha = 1 - exp(-dt / 0.22)
        let updated = Point(
            x: previous.x + (target.x - previous.x) * alpha,
            y: previous.y + (target.y - previous.y) * alpha,
            z: previous.z + (target.z - previous.z) * alpha
        )
        eye = updated
        return updated
    }

    private static func isFinite(_ point: Point) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }
}
