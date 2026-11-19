import StadiumCore

public struct CanState: Hashable, Sendable, Codable {
    public var position: Vec3
    public var grounded: Bool
    public var held: Bool
    public var taut: Bool
    public init(position: Vec3, grounded: Bool, held: Bool, taut: Bool) {
        self.position = position; self.grounded = grounded; self.held = held; self.taut = taut
    }
}

public enum WorldEvent: Hashable, Sendable, Codable {
    case clink(can: Int)
}

public struct RopeReport: Hashable, Sendable {
    public var cans: [CanState]
    /// Segment overstretch, ordered from each hitch outward; zero when slack.
    public var strain: [Fixed]
    public var events: [WorldEvent]
    public init(cans: [CanState], strain: [Fixed], events: [WorldEvent]) {
        self.cans = cans; self.strain = strain; self.events = events
    }
}
