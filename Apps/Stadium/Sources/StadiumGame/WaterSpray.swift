/// Renderers derive spray and lens effects from the same simulation start tick.
public struct WaterSpray: Hashable, Sendable {
    public static let leadTicks = 90
    public static let sprayTicks = 45
    public static let impactDelayTicks = 18
    public static let wetTicks = 180
    public static let totalTicks = max(sprayTicks, impactDelayTicks + wetTicks)

    public let round: Int
    public let startTick: Int

    public init(round: Int, startTick: Int) {
        self.round = round
        self.startTick = startTick
    }

    public var impactTick: Int { startTick + Self.impactDelayTicks }
    public var endTick: Int { startTick + Self.totalTicks }

    public func sprayProgress(at tick: Int) -> Double? {
        let age = tick - startTick
        guard age >= 0 && age < Self.sprayTicks else { return nil }
        return Double(age) / Double(Self.sprayTicks)
    }

    public func lensStrength(at tick: Int) -> Double {
        let age = tick - impactTick
        guard age >= 0 && age < Self.wetTicks else { return 0 }
        let remaining = 1 - Double(age) / Double(Self.wetTicks)
        return remaining * remaining
    }

    public func isActive(at tick: Int) -> Bool { tick >= startTick && tick < endTick }
}

/// Retain the last spray after it dries to prevent a second spray in the same round.
/// Blocked starts leave gameplay randomness unchanged.
struct WaterSpraySchedule: Hashable, Sendable {
    private var round = 1
    private var roundStartTick = 0
    private(set) var latest: WaterSpray? = nil

    mutating func advance(at tick: Int, round currentRound: Int, canBegin: Bool) {
        if currentRound != round {
            round = currentRound
            roundStartTick = tick
        }
        guard currentRound > 1, latest?.round != currentRound,
              tick >= roundStartTick + WaterSpray.leadTicks, canBegin else { return }
        latest = WaterSpray(round: currentRound, startTick: tick)
    }
}
