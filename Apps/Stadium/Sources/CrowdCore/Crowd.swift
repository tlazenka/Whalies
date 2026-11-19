import StadiumCore

public enum CrowdState: Int, Hashable, Sendable, Codable, CaseIterable {
    case seated = 0
    case thinking = 1
    case wantingHotDog = 2
    case watching = 3
    case catching = 4
    case struck = 5

    public init(_ phase: ThoughtPhase) {
        switch phase {
        case .spinning: self = .thinking
        case .requesting: self = .wantingHotDog
        case .watching: self = .watching
        }
    }

    public var title: String {
        switch self {
        case .seated: "seated"
        case .thinking: "thinking"
        case .wantingHotDog: "wants a hot dog"
        case .watching: "watching"
        case .catching: "catching"
        case .struck: "struck"
        }
    }
}

public struct CrowdParameters: Hashable, Sendable, Codable {
    public var catchTicks: Int
    public var strikeTicks: Int

    public init(catchTicks: Int, strikeTicks: Int) { self.catchTicks = catchTicks; self.strikeTicks = strikeTicks }

    public static let stadium = CrowdParameters(catchTicks: 90, strikeTicks: 120)
}

public struct CrowdSnapshot: Hashable, Sendable, Codable {
    public var states: [CrowdState]
}

public struct Crowd: Hashable, Sendable {
    public let parameters: CrowdParameters
    public private(set) var states: [CrowdState]
    public private(set) var remaining: [Int]

    public init(count: Int, parameters: CrowdParameters = .stadium) {
        self.parameters = parameters
        states = Array(repeating: .seated, count: count)
        remaining = Array(repeating: 0, count: count)
    }

    /// Strike and catch reactions override the thought schedule until their timers expire.
    @discardableResult
    public mutating func step(struck: Set<Int>, caught: Set<Int>, phase: (Int) -> ThoughtPhase?) -> CrowdSnapshot {
        for i in 0..<states.count {
            if struck.contains(i) {
                states[i] = .struck
                remaining[i] = parameters.strikeTicks
                continue
            }
            if caught.contains(i) {
                states[i] = .catching
                remaining[i] = parameters.catchTicks
                continue
            }
            if remaining[i] > 0 {
                remaining[i] -= 1
                if remaining[i] > 0 { continue }
                states[i] = .seated
            }
            states[i] = phase(i).map { CrowdState($0) } ?? .seated
        }
        return CrowdSnapshot(states: states)
    }
}

public enum CrowdDigest {
    /// Keep field order aligned with Crowd.mix in python/whaley_tools/stadium/crowd.py.
    public static func mix(_ d: inout ReplayDigest, _ s: CrowdSnapshot) {
        for state in s.states { d.mix(state.rawValue) }
    }
}
