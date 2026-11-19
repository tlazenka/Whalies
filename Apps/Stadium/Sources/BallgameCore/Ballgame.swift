// Recorded runs are credited at each half-inning end; recorded errors are spaced
// evenly within that half. The clock compresses the game without inventing events.

import StadiumCore

public struct ErrorRecord: Hashable, Sendable, Codable {
    public var inning: Int
    /// 0 = top, 1 = bottom.
    public var half: Int
    public var chargedToHome: Bool
    public var fielder: String
    /// Index into Ballgame.positions, or -1 when unknown.
    public var position: Int
    /// Index into Ballgame.kinds.
    public var kind: Int
    public var runScored: Bool

    public init(inning: Int, half: Int, chargedToHome: Bool, fielder: String, position: Int, kind: Int, runScored: Bool) {
        self.inning = inning; self.half = half; self.chargedToHome = chargedToHome; self.fielder = fielder
        self.position = position; self.kind = kind; self.runScored = runScored
    }
}

public struct BallgameRecord: Hashable, Sendable, Codable {
    public var gamePk: Int
    public var date: String
    public var away: String
    public var home: String
    public var awayScore: Int
    public var homeScore: Int
    /// Each inning is [away runs, home runs]; -1 means the bottom was not played.
    public var innings: [[Int]]
    public var errors: [ErrorRecord]

    public init(gamePk: Int, date: String, away: String, home: String, awayScore: Int, homeScore: Int, innings: [[Int]], errors: [ErrorRecord]) {
        self.gamePk = gamePk; self.date = date; self.away = away; self.home = home; self.awayScore = awayScore
        self.homeScore = homeScore; self.innings = innings; self.errors = errors
    }

    public struct Half: Hashable, Sendable {
        public var inning: Int
        public var half: Int
        public var runs: Int
    }

    public var halves: [Half] {
        var out: [Half] = []
        for (i, pair) in innings.enumerated() {
            out.append(Half(inning: i + 1, half: 0, runs: pair[0]))
            if pair[1] >= 0 { out.append(Half(inning: i + 1, half: 1, runs: pair[1])) }
        }
        return out
    }

    public func errors(inning: Int, half: Int) -> [Int] {
        errors.enumerated().filter { $0.element.inning == inning && $0.element.half == half }.map { $0.offset }
    }

    public func score(beforeHalf index: Int) -> (away: Int, home: Int) {
        var away = 0, home = 0
        for h in halves.prefix(max(0, index)) {
            if h.half == 0 { away += h.runs } else { home += h.runs }
        }
        return (away, home)
    }

    public func halfIndex(of h: HalfInning) -> Int? {
        halves.firstIndex { $0.inning == h.inning && $0.half == h.half }
    }
}

public struct HalfInning: Hashable, Sendable, Codable {
    public var inning: Int
    /// 0 = top, 1 = bottom.
    public var half: Int
    public init(inning: Int, half: Int) { self.inning = inning; self.half = half }
    public var title: String { "\(half == 0 ? "top" : "bottom") of the \(Ballgame.ordinal(inning))" }
}

public struct BallgameParameters: Hashable, Sendable, Codable {
    public var halfInningTicks: Int
    public var breakTicks: Int
    /// startHalf indexes record.halves; startTick is the tick offset within that half.
    public var startHalf: Int
    public var startTick: Int

    public init(halfInningTicks: Int, breakTicks: Int, startHalf: Int = 0, startTick: Int = 0) {
        self.halfInningTicks = halfInningTicks; self.breakTicks = breakTicks; self.startHalf = startHalf; self.startTick = startTick
    }

    public static let demo = BallgameParameters(halfInningTicks: 140, breakTicks: 20)

    private enum CodingKeys: String, CodingKey { case halfInningTicks, breakTicks, startHalf, startTick }

    /// Missing start fields decode from the first pitch for older parameter files.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        halfInningTicks = try c.decode(Int.self, forKey: .halfInningTicks)
        breakTicks = try c.decode(Int.self, forKey: .breakTicks)
        startHalf = try c.decodeIfPresent(Int.self, forKey: .startHalf) ?? 0
        startTick = try c.decodeIfPresent(Int.self, forKey: .startTick) ?? 0
    }
}

public enum BallgameEvent: Hashable, Sendable, Codable {
    case start(inning: Int, half: Int)
    /// index identifies the error in the recorded list.
    case error(index: Int, inning: Int, half: Int, chargedToHome: Bool, runScored: Bool)
    /// 0 = away, 1 = home.
    case runs(team: Int, count: Int, inning: Int, half: Int)
    case final(away: Int, home: Int)
    case end(inning: Int, half: Int, errors: Int)

    public var isError: Bool {
        if case .error = self { return true } else { return false }
    }
}

public struct BallgameSnapshot: Hashable, Sendable, Codable {
    public var tick: Int
    public var halfIndex: Int
    public var ticksIntoHalf: Int
    public var inning: Int
    public var half: Int
    public var awayScore: Int
    public var homeScore: Int
    public var over: Bool
    public var events: [BallgameEvent]
}

public struct Ballgame: Hashable, Sendable {
    public static let kinds = ["throwing", "fielding", "pickoff", "missed catch", "catcher interference", "dropped foul", "interference"]
    public static let positions = ["P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF"]
    public static let marlins = "Miami Marlins"

    public let record: BallgameRecord
    public let parameters: BallgameParameters
    public let halves: [BallgameRecord.Half]
    public private(set) var tick = 0
    public private(set) var halfIndex = 0
    public private(set) var ticksIntoHalf = 0
    public private(set) var awayScore = 0
    public private(set) var homeScore = 0
    public private(set) var over = false
    public private(set) var firedErrors = 0
    public private(set) var errorsThisHalf = 0

    public init(record: BallgameRecord, parameters: BallgameParameters = .demo) {
        self.record = record
        self.parameters = parameters
        halves = record.halves
        fastForward(toHalf: parameters.startHalf, tick: parameters.startTick)
    }

    /// Match a replay from the first pitch, including runs and errors before this point.
    private mutating func fastForward(toHalf halfIndex: Int, tick k: Int) {
        if halfIndex == 0 && k == 0 { return }
        for i in 0...halfIndex {
            let h = halves[i]
            if i < halfIndex || k > parameters.halfInningTicks - 1 {
                if h.half == 0 { awayScore += h.runs } else { homeScore += h.runs }
            }
            let n = record.errors(inning: h.inning, half: h.half).count
            for j in 0..<n where i < halfIndex || (j + 1) * parameters.halfInningTicks / (n + 1) < k {
                firedErrors += 1
                if i == halfIndex { errorsThisHalf += 1 }
            }
        }
        self.halfIndex = halfIndex
        ticksIntoHalf = k
    }

    public static func record(gamePk: Int) -> BallgameRecord? { Season2026.games.first { $0.gamePk == gamePk } }

    public static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    public var current: (inning: Int, half: Int) {
        let h = over ? halves[halves.count - 1] : halves[halfIndex]
        return (h.inning, h.half)
    }

    /// Keeps the last half after the game ends.
    public var currentHalf: HalfInning { let c = current; return HalfInning(inning: c.inning, half: c.half) }

    public var inPlay: Bool { !over && ticksIntoHalf < parameters.halfInningTicks }

    @discardableResult
    public mutating func step() -> BallgameSnapshot {
        let t = tick
        var events: [BallgameEvent] = []
        if !over {
            let h = halves[halfIndex]
            let length = parameters.halfInningTicks + parameters.breakTicks
            let k = ticksIntoHalf
            if k == 0 {
                events.append(.start(inning: h.inning, half: h.half))
                errorsThisHalf = 0
            }
            let errs = record.errors(inning: h.inning, half: h.half)
            let n = errs.count
            for (j, index) in errs.enumerated() {
                if k == (j + 1) * parameters.halfInningTicks / (n + 1) {
                    let e = record.errors[index]
                    events.append(.error(index: index, inning: h.inning, half: h.half, chargedToHome: e.chargedToHome, runScored: e.runScored))
                    firedErrors += 1
                    errorsThisHalf += 1
                }
            }
            if k == parameters.halfInningTicks - 1 {
                if h.half == 0 { awayScore += h.runs } else { homeScore += h.runs }
                if h.runs > 0 { events.append(.runs(team: h.half == 1 ? 1 : 0, count: h.runs, inning: h.inning, half: h.half)) }
            }
            if k == length - 1 {
                events.append(.end(inning: h.inning, half: h.half, errors: errorsThisHalf))
                halfIndex += 1
                ticksIntoHalf = 0
                if halfIndex == halves.count {
                    over = true
                    events.append(.final(away: awayScore, home: homeScore))
                }
            } else {
                ticksIntoHalf += 1
            }
        }
        tick += 1
        let c = current
        return BallgameSnapshot(tick: t, halfIndex: halfIndex, ticksIntoHalf: ticksIntoHalf, inning: c.inning, half: c.half,
                                awayScore: awayScore, homeScore: homeScore, over: over, events: events)
    }
}

public enum BallgameDigest {
    /// Keep field order aligned with Ballgame.digest_tick in python/whaley_tools/stadium/ballgame.py.
    public static func mix(_ d: inout ReplayDigest, _ s: BallgameSnapshot) {
        d.mix(s.tick); d.mix(s.halfIndex); d.mix(s.ticksIntoHalf); d.mix(s.inning); d.mix(s.half)
        d.mix(s.awayScore); d.mix(s.homeScore); d.mix(s.over); d.mix(s.events.count)
        for e in s.events {
            switch e {
            case .start(let inning, let half): d.mix(0); d.mix(inning); d.mix(half)
            case .error(let index, let inning, let half, let home, let run): d.mix(1); d.mix(index); d.mix(inning); d.mix(half); d.mix(home); d.mix(run)
            case .runs(let team, let count, let inning, let half): d.mix(2); d.mix(team); d.mix(count); d.mix(inning); d.mix(half)
            case .final(let away, let home): d.mix(3); d.mix(away); d.mix(home)
            case .end(let inning, let half, let errors): d.mix(5); d.mix(inning); d.mix(half); d.mix(errors)
            }
        }
    }

    public static func digest(_ snapshots: [BallgameSnapshot]) -> ReplayDigest {
        var d = ReplayDigest()
        for s in snapshots { mix(&d, s) }
        return d
    }
}
