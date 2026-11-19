// Input is car-relative: dx points right; dz points forward from the rear.
// This keeps recorded gestures independent of the kart heading and rope model.

import StadiumCore

public struct RopeInput: Hashable, Sendable, Codable {
    /// Can index, or -1; left-string cans precede right-string cans.
    public var held: Int
    public var dx: Fixed
    public var dz: Fixed
    public var toss: Bool
    public var tvx: Fixed
    public var tvz: Fixed

    public init(held: Int = -1, dx: Fixed = .zero, dz: Fixed = .zero, toss: Bool = false, tvx: Fixed = .zero, tvz: Fixed = .zero) {
        self.held = held; self.dx = dx; self.dz = dz; self.toss = toss; self.tvx = tvx; self.tvz = tvz
    }

    public static let none = RopeInput()

    public var tossSpeedSquared: Fixed { tvx * tvx + tvz * tvz }
}
