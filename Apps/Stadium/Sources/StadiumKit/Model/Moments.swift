import Foundation
import StadiumCore
import StadiumGame
import JSONViewKit

struct Moment: Equatable, Identifiable {
    enum Kind: String, CaseIterable, Sendable {
        case bubble, bounce, doll, shot, capture
        case thrown = "throw"
        case balk, coin, goal, death, zoom, lap, interlude, round
        case touch, scrub, facet, cleared, tab, done
    }

    enum Level: String, CaseIterable, Sendable {
        case cannon = "Hot dog cannon"
        case balk = "Balk"
        case whaley = "Whaley 2D"
        case interlude = "Interlude"
    }

    enum Value: Equatable, Sendable {
        case int(Int)
        case number(Double)
        case text(String)
        case flag(Bool)

        // Match JSONSerialization's NSNumber representation on Apple platforms and Linux.
        var json: Any {
            switch self {
            case .int(let n): return NSNumber(value: n)
            case .number(let x): return NSNumber(value: x)
            case .text(let s): return s
            case .flag(let b): return NSNumber(value: b)
            }
        }
    }

    var id: Int
    var tick: Int
    // An interlude belongs to the round it closes.
    var round: Int
    var level: Level
    var kind: Kind
    var title: String
    // Round summaries store their score in details["total"] to avoid counting it twice.
    var points: Int
    var details: [String: Value]

    var seconds: Double { (Double(tick) / 6).rounded() / 10 }

    var item: [String: Any] {
        var properties: [String: Any] = [
            "title": title, "kind": kind.rawValue, "level": level.rawValue, "round": NSNumber(value: round),
            "tick": NSNumber(value: tick), "seconds": NSNumber(value: seconds), "points": NSNumber(value: points),
        ]
        for (name, value) in details { properties[name] = value.json }
        return ["id": "moment/\(id)", "type": "Feature", "geometry": NSNull(), "properties": properties]
    }

    func int(_ name: String) -> Int {
        if case .int(let n)? = details[name] { return n }
        return 0
    }

    func text(_ name: String) -> String {
        if case .text(let s)? = details[name] { return s }
        return ""
    }
}

enum PhoneTab: String, CaseIterable, Sendable {
    case stats = "Stats"
    case wrapped = "Wrapped"
}

struct PhoneFeed {
    var number: Int
    var root: JSONNode
    var count: Int
    var cards: [WrappedInsight]
}

struct MomentLog {
    private(set) var moments: [Moment] = []
    private var last = RideTally()
    private var roundStart = 0
    private var roundTally = RideTally()
    private var roundRun = 0
    private var released: (how: ReleaseKind, speed: Fixed)?
    private var during = false

    init() {}

    static func round(_ s: StadiumSnapshot) -> Int { s.ride.interlude.round }

    static func level(_ s: StadiumSnapshot, _ kind: Moment.Kind, during: Bool) -> Moment.Level {
        if during { return .interlude }
        switch kind {
        case .capture, .thrown, .balk: return .balk
        case .coin, .goal, .death, .zoom: return .whaley
        case .doll, .shot: return .cannon
        default: break
        }
        if (s.ride.whaley.inQuadrant && s.ride.pitcher.crew == .free) || s.ride.jumbo.zoom != nil { return .whaley }
        if s.ride.pitcher.inView { return .balk }
        return .cannon
    }

    // Award each tally delta once: beat points go to the first qualifying bounce in this tick.
    mutating func observe(_ s: StadiumSnapshot, parameters p: StadiumParameters) {
        let r = s.ride, t = s.tick
        let round = Self.round(s)
        // The core can retain the previous round's streak until the next scoring bounce.
        let scored = r.tally.onBeat > last.onBeat
        if scored { roundRun = max(roundRun, r.streak) }
        let cap = p.ride.beat.streakCap
        var beat = scored ? p.ride.beat.basePoints * min(r.streak, cap) : 0
        var coins = r.tally.coins - last.coins, goals = r.tally.goals - last.goals
        // Recover the state before this tick's interlude transition, then apply events in order.
        during = r.interlude.on != nil
        for e in r.events {
            if case .interlude(let begun, _, _) = e {
                during = !begun
                break
            }
        }
        for e in r.events {
            switch e {
            case .bubble(_, let pipe, _, _):
                let side = pipe == 0 ? "left" : "right"
                add(s, .bubble, round, "A bubble out of the \(side) pipe", details: ["pipe": .text(side)])
            case .hop(let wheel, _, let onBeat):
                let points = onBeat ? beat : 0
                if points > 0 { beat = 0 }
                let run = onBeat ? r.streak : 0
                let title = onBeat ? "Bounce on the beat" + (run > 1 ? " \u{00D7}\(min(run, cap))" : "") : "Bounce off the beat"
                add(s, .bounce, round, title, points: points,
                    details: ["wheel": .text(Self.name(wheel)), "onBeat": .flag(onBeat), "run": .int(run), "bpm": .int(Int(r.tempo.double.rounded()))])
            case .result(let result):
                guard let a = r.lastResult else { break }
                var details: [String: Moment.Value] = [
                    "result": .text(Self.words(result)), "right": .flag(result.success), "fan": .int(a.figure), "garden": .flag(a.garden),
                    "symbol": .text(a.symbol.label), "requiresHotDog": .flag(a.symbol == .hotDog), "item": .text(a.shot >= 0 ? a.item.name : "none"), "beep": .int(a.beep),
                ]
                if a.shot >= 0 { details["reaction"] = .number(Self.tenths(a.shot - a.beep)) }
                add(s, .doll, round, "Thought \u{00B7} \(Self.sentence(Self.words(result)))", details: details)
            case .fired(let item, let figure, let part, let distance):
                let whom = figure >= 0 ? "fan \(figure)" : "nobody"
                let title = during ? "The hot dog for \(whom)" : "A \(item.name) at \(whom)"
                add(s, .shot, round, title, details: [
                    "item": .text(item.name), "fan": .int(figure), "part": .text(figure < 0 ? "none" : (part == 0 ? "head" : "torso")),
                    "metres": .number((distance.double * 10).rounded() / 10),
                ])
            case .captured:
                add(s, .capture, round, "The pitcher's ball captured", details: [:])
            case .thrown(let how, let speed, _):
                released = (how, speed)
            case .fielded(let who, _, let base, let outcome):
                let call = outcome.headline.lowercased()
                var details: [String: Moment.Value] = [
                    "caughtBy": .text(who.name), "base": .text(base?.name ?? "none"), "outcome": .text(call), "balk": .flag(outcome.isBalk),
                ]
                if let rel = released {
                    details["how"] = .text(Self.name(rel.how))
                    details["speed"] = .number((rel.speed.double * 10).rounded() / 10)
                }
                released = nil
                add(s, .thrown, round, "The ball \u{00B7} \(Self.sentence(call))", details: details)
            case .balk(let outcome, let points, let until):
                let call = outcome.headline.lowercased()
                add(s, .balk, round, "Balk \u{00B7} \(Self.sentence(call))", points: points,
                    details: ["call": .text(call), "camerasOnHim": .number(Self.tenths(until - t))])
            case .lap(let n):
                add(s, .lap, round, "Lap \(n)", details: ["lap": .int(n)])
            case .zoom(let inward, _) where inward:
                add(s, .zoom, round, "The camera onto the Jumbotron", details: [:])
            case .interlude(let begun, let fan, let number):
                during = begun
                if begun {
                    closeRound(s, number: number)
                    add(s, .interlude, number, "Interlude \(number) \u{00B7} fan \(fan) on his phone", details: ["fan": .int(fan), "number": .int(number)])
                } else {
                    roundStart = t
                    roundTally = r.tally
                    roundRun = 0
                }
            default:
                break
            }
        }
        during = r.interlude.on != nil
        if r.whaley.engaged {
            let level = r.whaley.observation.number
            for e in r.whaley.events {
                switch e {
                case .coin where coins > 0:
                    coins -= 1
                    add(s, .coin, round, "Whaley took a coin", points: p.ride.whaley.coinPoints, details: ["whaleyLevel": .int(level)])
                case .goal where goals > 0:
                    goals -= 1
                    add(s, .goal, round, "Whaley reached the goal", points: p.ride.whaley.goalPoints, details: ["whaleyLevel": .int(level)])
                case .died:
                    add(s, .death, round, "Whaley died", details: ["whaleyLevel": .int(level)])
                default:
                    break
                }
            }
        }
        last = r.tally
    }

    private mutating func closeRound(_ s: StadiumSnapshot, number: Int) {
        let now = s.ride.tally, was = roundTally
        let right = (now.served + now.heldFire) - (was.served + was.heldFire)
        let wrong = now.wrong - was.wrong
        let points = now.points - was.points
        add(s, .round, number, "Round \(number) \u{00B7} \(Self.count(points, "point", "points"))", details: [
            "total": .int(points), "bounces": .int(now.bounces - was.bounces), "onBeat": .int(now.onBeat - was.onBeat), "bestRun": .int(roundRun),
            "dolls": .int(right + wrong), "calledRight": .int(right), "calledWrong": .int(wrong), "balks": .int(now.balks - was.balks),
            "coins": .int(now.coins - was.coins), "goals": .int(now.goals - was.goals), "length": .number(Self.tenths(s.tick - roundStart)),
        ])
    }

    private mutating func add(_ s: StadiumSnapshot, _ kind: Moment.Kind, _ round: Int, _ title: String, points: Int = 0, details: [String: Moment.Value]) {
        moments.append(Moment(id: moments.count, tick: s.tick, round: round, level: Self.level(s, kind, during: during), kind: kind, title: title,
                              points: points, details: details))
    }

    mutating func phone(_ kind: Moment.Kind, tick: Int, round: Int, title: String, details: [String: Moment.Value]) {
        moments.append(Moment(id: moments.count, tick: tick, round: round, level: .interlude, kind: kind, title: title, points: 0, details: details))
    }

    static let phoneKinds: Set<Moment.Kind> = [.touch, .scrub, .facet, .cleared, .tab, .done]
    static let whaleyKinds: Set<Moment.Kind> = [.coin, .goal, .death]

    func phoneMoments(_ number: Int) -> [Moment] {
        moments.filter { $0.round == number && Self.phoneKinds.contains($0.kind) }
    }

    func feed(number: Int) -> PhoneFeed {
        PhoneFeed(number: number, root: JSONNode.feed(items: moments.map(\.item), type: "stadium-moments"), count: moments.count, cards: cards(round: number))
    }

    func cards(round n: Int) -> [WrappedInsight] {
        var out: [WrappedInsight] = []
        let inRound = moments.filter { $0.round == n && $0.kind != .round }
        if let r = moments.last(where: { $0.kind == .round && $0.round == n }) {
            let bounces = r.int("bounces")
            let detail: String
            if bounces == 0 {
                detail = "and not a bounce this time round"
            } else {
                detail = "from \(Self.count(bounces, "bounce", "bounces")), \(r.int("onBeat")) on the beat, the best run \(r.int("bestRun"))"
            }
            out.append(WrappedInsight(id: "round-points", eyebrow: "Round \(n)", value: Self.count(r.int("total"), "point", "points"), detail: detail))
        }
        let dolls = inRound.filter { $0.kind == .doll }
        if dolls.isEmpty {
            out.append(WrappedInsight(id: "round-dolls", eyebrow: "Fan thoughts", value: "No fan thoughts", detail: "none this round"))
        } else {
            let right = dolls.filter { $0.details["right"] == .flag(true) }.count
            let calls = ShotResult.allCases.compactMap { result -> String? in
                let k = dolls.filter { $0.text("result") == Self.words(result) }.count
                return k == 0 ? nil : "\(k) \(Self.words(result, count: k))"
            }
            out.append(WrappedInsight(id: "round-dolls", eyebrow: "Fan thoughts", value: "\(right) of \(dolls.count) called right",
                                      detail: calls.joined(separator: ", ")))
        }
        let balks = inRound.filter { $0.kind == .balk }
        if !balks.isEmpty {
            let points = balks.reduce(0) { $0 + $1.points }
            out.append(WrappedInsight(id: "round-balks", eyebrow: "The balks", value: Self.count(balks.count, "balk", "balks"),
                                      detail: "+\(points) points from the umpire's calls"))
        }
        let whaley = inRound.filter { Self.whaleyKinds.contains($0.kind) }
        if !whaley.isEmpty {
            let coins = whaley.filter { $0.kind == .coin }.count, goals = whaley.filter { $0.kind == .goal }.count
            let deaths = whaley.filter { $0.kind == .death }.count
            let points = whaley.reduce(0) { $0 + $1.points }
            let detail = "\(Self.count(goals, "goal", "goals")), \(Self.count(deaths, "death", "deaths")), +\(points) points"
            out.append(WrappedInsight(id: "round-whaley", eyebrow: "Whaley 2D", value: Self.count(coins, "coin", "coins"), detail: detail))
        }
        if let best = inRound.filter({ $0.points > 0 }).max(by: { $0.points < $1.points || ($0.points == $1.points && $0.id > $1.id) }) {
            out.append(WrappedInsight(id: "round-best", eyebrow: "The best moment", value: "+\(best.points)",
                                      detail: "\(best.title), \(Self.clock(best.tick)) in"))
        }
        if n > 1 {
            let phone = phoneMoments(n - 1)
            let touches = phone.filter { $0.kind == .touch }.count
            let scrubs = phone.filter { $0.kind == .scrub }.count, facets = phone.filter { $0.kind == .facet }.count
            let value = touches == 0 ? "Not a touch" : Self.count(touches, "touch", "touches")
            var detail = touches == 0 ? "the phone sat in his hands" : Self.count(scrubs, "scrub", "scrubs") + " and " + Self.count(facets, "facet", "facets")
            if phone.contains(where: { $0.kind == .done }) {
                detail += ", selected Done to continue"
            }
            out.append(WrappedInsight(id: "round-phone", eyebrow: "Last time on the phone", value: value, detail: detail))
        }
        let laps = moments.filter { $0.kind == .lap }.count
        out.append(WrappedInsight(id: "round-game", eyebrow: "The game so far", value: Self.count(last.points, "point", "points"),
                                  detail: "\(Self.count(n, "round", "rounds")), \(Self.count(laps, "lap", "laps"))"))
        return out
    }

    static func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    static func tenths(_ ticks: Int) -> Double { (Double(ticks) / 6).rounded() / 10 }

    static func clock(_ tick: Int) -> String {
        let s = tick / 60
        return "\(s / 60):\(s % 60 < 10 ? "0" : "")\(s % 60)"
    }

    static func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    static func name(_ wheel: Wheel) -> String {
        switch wheel {
        case .rearLeft: "rear left"
        case .rearRight: "rear right"
        case .frontLeft: "front left"
        case .frontRight: "front right"
        }
    }

    static func name(_ how: ReleaseKind) -> String {
        switch how {
        case .thrown: "thrown"
        case .dropped: "dropped"
        case .held: "held"
        }
    }

    static func words(_ r: ShotResult, count k: Int = 1) -> String {
        switch r {
        case .served: k == 1 ? "hot dog served" : "hot dogs served"
        case .tooSoon: k == 1 ? "shot before the reel settled" : "shots before the reel settled"
        case .unwanted: k == 1 ? "unwanted hot dog" : "unwanted hot dogs"
        case .wrongItem: k == 1 ? "wrong item" : "wrong items"
        case .wrongFan: k == 1 ? "wrong fan" : "wrong fans"
        case .miss: k == 1 ? "miss" : "misses"
        case .missedRequest: k == 1 ? "hot dog request missed" : "hot dog requests missed"
        case .heldFire: k == 1 ? "correct hold" : "correct holds"
        }
    }
}
