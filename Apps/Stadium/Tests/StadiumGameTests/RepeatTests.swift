import Foundation
import Testing
import StadiumCore
import WhaleKartCore
import CrowdCore
@testable import StadiumGame

struct RepeatFixture: Decodable {
    struct Sample: Decodable {
        let t: Int
        let car: [Int64]
        let lap: Int
        let state: Int
        let direction: Int
        let turning: Int64
        let lo: Int64
        let hi: Int64
        let unwrapped: Int64
        let railed: Bool
        let pitcherInView: Bool
        let inQuadrant: Bool
        let whaleyShown: Bool
        let parked: Bool
        let held: Bool
    }
    struct Run: Decodable {
        let samples: [Sample]
        let events: [[Int64]]
        let ticks: Int
        let tally: BalkFixture.Tally
    }
    struct Entry: Decodable {
        let inputs: [StadiumInput]
        let toggles: [String: Int]
        let parks: [String: Bool]
        let run: Run
    }
    let parameters: StadiumParameters
    let runs: [String: Entry]

    static func load() throws -> RepeatFixture {
        let url = try #require(Bundle.module.url(forResource: "repeat", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(RepeatFixture.self, from: Data(contentsOf: url))
    }
}

private func isTurnaround(_ e: RideEvent) -> Bool { if case .turnaround = e { true } else { false } }
private func isLap(_ e: RideEvent) -> Bool { if case .lap = e { true } else { false } }

private func replay(_ p: StadiumParameters, _ inputs: [StadiumInput]) -> [(snapshot: StadiumSnapshot, inView: Bool)] {
    var game = StadiumGame(parameters: p)
    var out: [(StadiumSnapshot, Bool)] = []
    out.reserveCapacity(inputs.count)
    for input in inputs {
        let s = game.step(input)
        out.append((s, s.ride.pitcher.inView))
    }
    return out
}

@Test
func theToggleRunsKeepTheirRecordedMovementAndInputs() throws {
    let fixture = try RepeatFixture.load()
    #expect(fixture.runs.keys.sorted() == StadiumScript.repeatRuns.map(\.kind).sorted())
    #expect(fixture.parameters == StadiumScript.balkParameters())
    for run in StadiumScript.repeatRuns {
        let entry = try #require(fixture.runs[run.kind])
        #expect(entry.toggles == Dictionary(uniqueKeysWithValues: run.toggles.map { (String($0.key), $0.value.rawValue) }), "the \(run.kind) run's toggles")
        #expect(entry.parks == Dictionary(uniqueKeysWithValues: run.parks.map { (String($0.key), $0.value) }), "the \(run.kind) run's static mode")
        #expect(entry.inputs == StadiumScript.repeatInputs(toggles: run.toggles, parks: run.parks, ticks: run.ticks), "the \(run.kind) run's inputs")
        let replayed = replay(fixture.parameters, entry.inputs)
        let snapshots = replayed.map(\.snapshot)
        #expect(snapshots.count == entry.run.ticks)
        for sample in entry.run.samples {
            let s = snapshots[sample.t], r = s.ride.repeat
            #expect(carValues(s.car) == sample.car && s.ride.lap == sample.lap, "the \(run.kind) run's kart at \(sample.t)")
            #expect(r.state.rawValue == sample.state && r.direction == sample.direction && r.turning.raw == sample.turning,
                    "the \(run.kind) run's toggle at \(sample.t)")
            #expect(r.lo.raw == sample.lo && r.hi.raw == sample.hi && r.unwrapped.raw == sample.unwrapped, "the \(run.kind) run's stretch at \(sample.t)")
            #expect(s.ride.railed == sample.railed && replayed[sample.t].inView == sample.pitcherInView, "the \(run.kind) run's rail and view at \(sample.t)")
            #expect(s.ride.whaley.inQuadrant == sample.inQuadrant && s.ride.whaley.shown == sample.whaleyShown,
                    "the \(run.kind) run's home quadrant and Jumbotron's game at \(sample.t)")
            #expect(r.parked == sample.parked && r.isHeld == sample.held, "the \(run.kind) run's static mode at \(sample.t)")
        }
        #expect(snapshots.flatMap(eventRows) == entry.run.events, "the \(run.kind) run's events")
        expectThoughtDecisions(snapshots)
        let tally = try #require(snapshots.last?.ride.tally)
        #expect(tally.laps == entry.run.tally.laps && tally.alarms == entry.run.tally.alarms, "the \(run.kind) run's tally")
    }
}

@Test
func thePitchersStretchRepeats() throws {
    let p = StadiumScript.balkParameters()
    let rp = p.ride.repeat
    let replayed = replay(p, StadiumScript.repeatInputs(toggles: [0: .pitcher], ticks: 5400))
    let snapshots = replayed.map(\.snapshot)
    let turns = snapshots.filter { $0.ride.events.contains(where: isTurnaround) }.map { s in
        (s.tick, s.ride.repeat.direction, s.ride.repeat.unwrapped)
    }
    #expect(turns.map(\.0) == [3427, 3814, 4201, 4588, 4975, 5362])
    #expect(turns.map(\.1) == [-1, 1, -1, 1, -1, 1])
    #expect(turns.allSatisfy { $0.1 < 0 ? ($0.2 - rp.pitcher[1]).magnitude < Fixed(0.5) : ($0.2 - rp.pitcher[0]).magnitude < Fixed(0.5) },
            "each turn at the stretch's end or beginning")
    #expect(snapshots[0].ride.repeat.state == .pitcher && snapshots[0].ride.repeat.lo == rp.pitcher[0] && snapshots[0].ride.repeat.hi == rp.pitcher[1])
    #expect(snapshots[3427].ride.repeat.isTurning && !snapshots[3490].ride.repeat.isTurning)
    #expect(snapshots[3460].car.speed < Fixed(4.5) && snapshots[3600].car.speed == Fixed(6.0))
    #expect(snapshots[3600].ride.repeat.direction == -1 && snapshots[3600].car.progress < snapshots[3500].car.progress, "driving back")
    let later = snapshots.filter { $0.tick >= 3427 }.map(\.ride.repeat.unwrapped)
    #expect(later.allSatisfy { rp.pitcher[0] - Fixed(2.0) <= $0 && $0 <= rp.pitcher[1] + Fixed(2.0) })
    let inView = replayed.filter { $0.snapshot.tick >= 3427 && $0.inView }.count
    #expect(inView > (5400 - 3427) * 3 / 5, "in view \(inView) of \(5400 - 3427)")
    #expect(snapshots.last?.ride.tally.laps == 0 && snapshots.last?.ride.repeat.ever == true)
}

@Test
func theCannonsStretchRepeats() throws {
    let p = StadiumScript.balkParameters()
    let rp = p.ride.repeat
    let replayed = replay(p, StadiumScript.repeatInputs(toggles: [0: .cannon], ticks: 6600))
    let snapshots = replayed.map(\.snapshot)
    let turns = snapshots.filter { $0.ride.events.contains(where: isTurnaround) }.map { ($0.tick, $0.ride.repeat.direction) }
    #expect(turns.map(\.0) == [2622, 5306] && turns.map(\.1) == [-1, 1])
    #expect(replayed.allSatisfy { !$0.inView })
    let laps = snapshots.filter { $0.ride.events.contains { if case .lap = $0 { true } else { false } } }.map { ($0.tick, $0.ride.lap) }
    #expect(laps.map(\.0) == [5276, 5417] && laps.map(\.1) == [-1, 0])
    let all = snapshots.map(\.ride.repeat.unwrapped)
    #expect(all.allSatisfy { rp.cannon[0] - Fixed(2.0) <= $0 && $0 <= rp.cannon[1] + Fixed(2.0) })
    let beeps = snapshots.filter { $0.ride.events.contains(where: { if case .beep = $0 { true } else { false } }) }.map(\.tick)
    #expect(beeps == [636, 1571, 2406, 3129, 3994, 4762, 5722])
}

@Test
func theToggleSwitchedOffTurnsTheKartForwardAgain() throws {
    let p = StadiumScript.balkParameters()
    let replayed = replay(p, StadiumScript.repeatInputs(toggles: [0: .pitcher, 3600: .off], ticks: 4800))
    let snapshots = replayed.map(\.snapshot)
    let s3600 = snapshots[3600].ride
    #expect(s3600.repeat.state == .off && s3600.repeat.direction == 1 && s3600.repeat.isTurning)
    #expect(s3600.events.contains { if case .repeat(let st) = $0 { st == .off } else { false } })
    #expect(s3600.events.contains { if case .turnaround(let d) = $0 { d == 1 } else { false } })
    #expect(snapshots[3812].ride.events.contains { if case .lap(let n) = $0 { n == 1 } else { false } })
    #expect(snapshots[4291].ride.events.contains(.interlude(begun: true, fan: 153, number: 1)))
    #expect(snapshots.last.map { $0.ride.repeat.unwrapped >= p.ride.interlude.at && $0.ride.interlude.on != nil } == true, "waiting at its point")
    var game = StadiumGame(parameters: p)
    for _ in 0..<2700 { game.step(.none) }
    let s = game.step(StadiumInput(finger: .none, repeat: .cannon))
    #expect(s.ride.repeat.lo == p.ride.repeat.cannon[0] + game.track.total && s.ride.repeat.hi == p.ride.repeat.cannon[1] + game.track.total)
    #expect(s.ride.repeat.direction == 1 && !s.ride.repeat.isTurning)
}

@Test
func theToggleIsAnInput() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let none = String(decoding: try encoder.encode(StadiumInput.none), as: UTF8.self)
    let set = String(decoding: try encoder.encode(StadiumInput(finger: .none, repeat: .pitcher)), as: UTF8.self)
    #expect(none == "{}" && set == "{\"repeat\":3}")
    let decoded = try JSONDecoder().decode(StadiumInput.self, from: Data(set.utf8))
    #expect(decoded.repeat == .pitcher && decoded.finger.phase == .none && decoded.parked == nil)
    let parked = String(decoding: try encoder.encode(StadiumInput(finger: .none, repeat: .whaley, parked: true)), as: UTF8.self)
    #expect(parked == "{\"parked\":true,\"repeat\":2}")
    let back = try JSONDecoder().decode(StadiumInput.self, from: Data("{\"parked\":false}".utf8))
    #expect(back.parked == false && back.repeat == nil && back != .none)
    #expect(RepeatState.off.next == .cannon && RepeatState.cannon.next == .whaley && RepeatState.whaley.next == .pitcher
            && RepeatState.pitcher.next == .interlude && RepeatState.interlude.next == .off)
    #expect(RepeatState.allCases.map(\.rawValue) == [0, 1, 2, 3, 4]
            && RepeatState.allCases.map(\.name) == ["normal", "cannon", "whaley", "pitcher", "interlude"])
}

@Test
func theWhaleySectionRepeats() throws {
    let p = StadiumScript.balkParameters()
    let rp = p.ride.repeat
    let total = StadiumGame(parameters: p).track.total
    #expect(rp.whaley == [Fixed(312.0), Fixed(351.0)] && rp.pitcher[1] < rp.whaley[0])
    let replayed = replay(p, StadiumScript.repeatInputs(toggles: [0: .whaley], ticks: 3000))
    let snapshots = replayed.map(\.snapshot)
    #expect(snapshots[0].ride.repeat.lo == rp.whaley[0] - total && snapshots[0].ride.repeat.hi == rp.whaley[1] - total, "the instance round the lap's start")
    let turns = snapshots.filter { $0.ride.events.contains(where: isTurnaround) }.map { ($0.tick, $0.ride.repeat.direction) }
    #expect(turns.map(\.0) == [454, 960, 1466, 1972, 2478, 2984] && turns.map(\.1) == [-1, 1, -1, 1, -1, 1])
    let laps = snapshots.filter { $0.ride.events.contains { if case .lap = $0 { true } else { false } } }.map { ($0.tick, $0.ride.lap) }
    #expect(laps.map(\.0) == [939, 1060, 1951, 2073, 2963] && laps.map(\.1) == [-1, 0, -1, 0, -1], "back and forth across the lap's start")
    #expect(snapshots.allSatisfy { $0.ride.whaley.inQuadrant }, "never out of the quadrant")
    #expect(replayed.allSatisfy { !$0.inView }, "the pitcher never on the picture, even through a turn")
    let beeps = snapshots.filter { $0.ride.events.contains(where: { if case .beep = $0 { true } else { false } }) }.map(\.tick)
    #expect(beeps == [636, 1571, 2351])
    #expect(snapshots.allSatisfy { $0.ride.whaley.shown == !($0.ride.incident?.onJumbotron(at: $0.tick) ?? false) })
    var spans: [Int] = []
    var last: Bool?
    for s in snapshots where s.ride.whaley.shown != last {
        spans.append(s.tick)
        last = s.ride.whaley.shown
    }
    #expect(spans == [0, 636, 1026, 1571, 1961, 2351, 2741])
}

@Test
func theStaticModeHoldsTheKart() throws {
    let p = StadiumScript.balkParameters()
    let spots = p.ride.repeat.spots
    #expect(spots == RepeatSpots(cannon: Fixed(42.0), pitcher: Fixed(298.0), whaley: Fixed(30.0), interlude: Fixed(40.0)))
    for (state, spot, ticks) in [(RepeatState.cannon, spots.cannon, 1800), (.whaley, spots.whaley, 1200), (.pitcher, spots.pitcher, 1500)] {
        let replayed = replay(p, StadiumScript.repeatInputs(toggles: [0: state], parks: [0: true], ticks: ticks))
        let snapshots = replayed.map(\.snapshot)
        let at = snapshots[0].car
        #expect(snapshots.allSatisfy { $0.car == at && $0.ride.repeat.parkedAt == spot }, "the \(state.name) level held at its spot")
        #expect(at.speed == .zero && (at.progress - spot).magnitude < Fixed(0.01) && at.offset < Fixed(0.01), "set down on the ring at rest")
        #expect(snapshots[0].ride.events.contains(.parked(true)) && snapshots.allSatisfy { !$0.ride.railed })
        #expect(!snapshots.contains { $0.ride.events.contains { isTurnaround($0) || isLap($0) } }, "no turn and no lap")
        let beeps = snapshots.filter { $0.ride.events.contains(where: { if case .beep = $0 { true } else { false } }) }.map(\.tick)
        switch state {
        case .cannon:
            #expect(snapshots.allSatisfy { !$0.ride.whaley.inQuadrant } && replayed.allSatisfy { !$0.inView } && beeps == [636, 1571],
                    "the Jumbotron on the doll's fan, the dolls going off")
        case .whaley:
            #expect(snapshots.allSatisfy { $0.ride.whaley.inQuadrant } && replayed.allSatisfy { !$0.inView } && beeps == [636])
            #expect(snapshots.allSatisfy { $0.ride.whaley.shown == !(636..<1026).contains($0.tick) }, "the game shown but for the doll's fan's while")
        default:
            #expect(replayed.allSatisfy { $0.inView } && snapshots.last?.ride.pitcher.fade == .one && (snapshots.last?.ride.zoom ?? .one) < Fixed(0.9),
                    "on the pitcher, the Bullpen Cart faded, the view zoomed in")
            #expect(beeps.isEmpty, "zoomed in on him, no fan on the dolls' band")
        }
    }
    let replayed = replay(p, StadiumScript.repeatInputs(toggles: [0: .cannon, 600: .pitcher, 1800: .off], parks: [0: true, 900: false, 1500: true], ticks: 2400))
    let snapshots = replayed.map(\.snapshot)
    #expect(snapshots[599].ride.repeat.parkedAt == spots.cannon && snapshots[600].ride.repeat.parkedAt == spots.pitcher, "a new level, a new spot")
    #expect(snapshots[600].ride.repeat.lo == p.ride.repeat.pitcher[0] && snapshots[600].ride.repeat.hi == p.ride.repeat.pitcher[1])
    #expect(snapshots[900].ride.events.contains(.parked(false)) && !snapshots[900].ride.repeat.isHeld && snapshots[900].car.speed > .zero, "let go, on from the spot")
    let turns = snapshots.filter { $0.ride.events.contains(where: isTurnaround) }.map { ($0.tick, $0.ride.repeat.direction) }
    #expect(turns.map(\.0) == [1083, 1451] && turns.map(\.1) == [-1, 1], "the pitcher's stretch repeated")
    #expect(snapshots[1500].ride.repeat.parkedAt == spots.pitcher && snapshots[1500].car == snapshots[1799].car, "held again")
    #expect(snapshots[1800].ride.repeat.state == .off && snapshots[1800].ride.repeat.parked && !snapshots[1800].ride.repeat.isHeld)
    let laps = snapshots.filter { $0.ride.events.contains { if case .lap = $0 { true } else { false } } }.map { ($0.tick, $0.ride.lap) }
    #expect(laps.map(\.0) == [2025] && laps.map(\.1) == [1], "normal play: on round the ring, the set-downs counting no lap")
    #expect(snapshots.last?.ride.repeat.parkedEver == true)
}

@Test
func theScriptedRideNeverUsesTheToggle() throws {
    let snapshots = StadiumScript.recording().replay()
    #expect(snapshots.allSatisfy { !$0.ride.repeat.ever && $0.ride.repeat.state == .off && $0.ride.repeat.direction == 1 })
    expectThoughtDecisions(snapshots)
}
