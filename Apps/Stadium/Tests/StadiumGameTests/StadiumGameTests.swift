// Recorded geometry stays fixed while fan assertions use current reel rules.

import Foundation
import Testing
import StadiumCore
import WhaleKartCore
import CrowdCore
@testable import StadiumGame

struct Fixture: Decodable {
    struct Sample: Decodable {
        let t: Int
        let car: [Int64]
        let turret: Int64
        let zoom: Int64
        let steer: Int
        let hops: [Int]
        let level: Int64
        let tempo: Int64
        let phase: Int64
        let bubbles: [[Int64]]
        let states: [Int]
        let aim: Int64?
        let wheels: [[Int64]?]
        let pipes: [[Int64]?]
    }
    struct Result: Decodable {
        let beep: Int, figure: Int, garden: Bool, symbol: ThoughtSymbol, item: Int, result: Int, endTick: Int, shot: Int
    }
    struct Tally: Decodable {
        let laps: Int, alarms: Int, served: Int, tooSoon: Int, wrong: Int, heldFire: Int, garden: Int, bounces: Int, onBeat: Int, points: Int,
            bestStreak: Int
    }
    struct Run: Decodable {
        let samples: [Sample]
        let events: [[Int64]]
        let ticks: Int
        let results: [Result]
        let tally: Tally
    }
    let parameters: StadiumParameters
    let kartParameters: KartParameters
    let inputs: [StadiumInput]
    let run: Run
    struct Variant: Decodable {
        let seed: Int64
        let inputs: [StadiumInput]
        let run: Run
    }
    let variants: [String: Variant]

    static func load() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "ride", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}

func carValues(_ c: Car) -> [Int64] {
    [c.x.raw, c.z.raw, c.heading.raw, c.yawRate.raw, c.speed.raw, c.progress.raw, c.offset.raw, c.side.raw, c.offTrack ? 1 : 0]
}

// Match Python event order: tick, event code, payload.
func eventRows(_ s: StadiumSnapshot) -> [[Int64]] {
    s.ride.events.map { [Int64(s.tick)] + StadiumDigest.code($0) }
}

func isResult(_ e: RideEvent) -> Bool { if case .result = e { true } else { false } }

func expectSamples(_ snapshots: [StadiumSnapshot], _ run: Fixture.Run, fans: Range<Int>, _ label: String) {
    for sample in run.samples {
        let s = snapshots[sample.t], r = s.ride
        #expect(carValues(s.car) == sample.car, "\(label): the kart at tick \(sample.t)")
        #expect(s.turret.raw == sample.turret && r.zoom.raw == sample.zoom && r.steer == sample.steer && r.hops == sample.hops,
                "\(label): the turret, the zoom, the steer, the bounces at \(sample.t)")
        #expect(r.level.raw == sample.level && r.tempo.raw == sample.tempo && r.beatPhase == sample.phase, "\(label): the music at tick \(sample.t)")
        #expect(r.bubbles.map { [Int64($0.id), $0.x.raw, $0.y.raw, $0.scale.raw] } == sample.bubbles, "\(label): the bubbles at tick \(sample.t)")
        #expect(fans.map { s.crowd.states[$0].rawValue } == sample.states, "\(label): the crowd at tick \(sample.t)")
        #expect(r.incident.map { $0.aim.raw } == sample.aim, "\(label): the aim at \(sample.t)")
        #expect(r.bullpenCart.wheels.map { $0.map { [$0.x.raw, $0.y.raw, $0.w.raw, $0.h.raw] } } == sample.wheels, "\(label): the wheels at tick \(sample.t)")
        #expect(r.bullpenCart.pipes.map { $0.map { [$0.x.raw, $0.y.raw] } } == sample.pipes, "\(label): the pipes at tick \(sample.t)")
    }
}

func expectResults(_ snapshots: [StadiumSnapshot], _ run: Fixture.Run, _ label: String) throws {
    var results: [AlarmResult] = []
    for s in snapshots where s.ride.events.contains(where: isResult) { results.append(try #require(s.ride.lastResult)) }
    #expect(results.count == run.results.count, "\(label): the results")
    for (r, e) in zip(results, run.results) {
        #expect(r.beep == e.beep && r.figure == e.figure && r.garden == e.garden && r.symbol == e.symbol && r.item.rawValue == e.item
                && r.result.rawValue == e.result && r.endTick == e.endTick && r.shot == e.shot, "\(label): the result at \(e.endTick)")
    }
    let tally = try #require(snapshots.last?.ride.tally)
    let t = run.tally
    #expect(tally.laps == t.laps && tally.alarms == t.alarms && tally.served == t.served && tally.tooSoon == t.tooSoon && tally.wrong == t.wrong
            && tally.heldFire == t.heldFire && tally.garden == t.garden && tally.bounces == t.bounces && tally.onBeat == t.onBeat
            && tally.points == t.points && tally.bestStreak == t.bestStreak, "\(label): the tally")
}

@Test
func theRideKeepsTheRecordedDrivingAndShotGeometry() throws {
    let fixture = try Fixture.load()
    let snapshots = StadiumRecording(parameters: fixture.parameters, inputs: fixture.inputs).replay()
    #expect(snapshots.count == fixture.run.ticks)
    expectSamples(snapshots, fixture.run, fans: 0..<fixture.parameters.stands.seats, "the ride")
    #expect(snapshots.flatMap(eventRows) == fixture.run.events)
    try expectResults(snapshots, fixture.run, "the ride")
    expectThoughtDecisions(snapshots)
}

@Test
func theVariantsKeepTheirInputsAndExpectedDecisions() throws {
    let fixture = try Fixture.load()
    #expect(fixture.variants.keys.sorted() == StadiumScript.variants.map(\.kind.rawValue).sorted())
    for v in StadiumScript.variants {
        let kind = v.kind.rawValue
        let fv = try #require(fixture.variants[kind])
        #expect(fv.seed == v.seed, "the \(kind) variant's seed")
        let p = StadiumScript.parameters(v, fixture.parameters)
        let snapshots = StadiumRecording(parameters: p, inputs: fv.inputs).replay()
        #expect(snapshots.flatMap(eventRows) == fv.run.events, "the \(kind) variant's events")
        expectThoughtDecisions(snapshots)
        expectSamples(snapshots, fv.run, fans: 0..<fixture.parameters.stands.seats, "the \(kind) variant")
        try expectResults(snapshots, fv.run, "the \(kind) variant")
        let first = snapshots.first { $0.ride.events.contains(where: isResult) }?.ride.lastResult
        #expect(first?.result == v.result, "the \(kind) variant's first doll")
    }
}

@Test
func theHandsAndTheParametersAreTheFixtures() throws {
    let fixture = try Fixture.load()
    #expect(StadiumParameters.stadium == fixture.parameters)
    #expect(StadiumParameters.stadium.kart == fixture.kartParameters)
    #expect(fixture.kartParameters.cruiseSpeed == Fixed(6.0) && fixture.kartParameters.trackPoints.count == 64
            && fixture.kartParameters.trackPoints != KartParameters.stadium.trackPoints, "the ride's kart is the stadium's, on the ride's ring, at its cruise")
    #expect(StadiumScript.inputs() == fixture.inputs)
    for v in StadiumScript.variants {
        #expect(StadiumScript.inputs(kind: v.kind, parameters: StadiumScript.parameters(v)) == fixture.variants[v.kind.rawValue]?.inputs, "the \(v.kind) hand")
    }
}

@Test
func aRecordingReplaysIdenticallyAndSurvivesJSON() throws {
    let fixture = try Fixture.load()
    let recording = StadiumRecording(parameters: fixture.parameters, inputs: fixture.inputs)
    var game = recording.makeGame()
    let first = recording.inputs.map { game.step($0) }
    #expect(first.contains { $0.ride.incident?.symbol.requiresHotDog == true })
    #expect(first.contains { $0.ride.incident?.symbol.requiresHotDog == false })
    let data = try JSONEncoder().encode(recording)
    let decoded = try JSONDecoder().decode(StadiumRecording.self, from: data)
    #expect(decoded == recording && decoded.version == StadiumRecording.currentVersion)
    let replayed = decoded.replay()
    #expect(replayed == first)
    #expect(game.digest.hex == StadiumDigest.digest(replayed).hex)
    // Sort keys so the serialized comparison does not depend on dictionary order.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(decoding: try encoder.encode(recording), as: UTF8.self)
    #expect(json.contains("{}") && json.contains("\"finger\":{\"phase\":1,") && json.contains("Acme Snacks"))
}

@Test
func theScriptedRideTellsItsStory() throws {
    let snapshots = StadiumScript.recording().replay()
    var story: [String] = []
    for s in snapshots {
        for e in s.ride.events {
            switch e {
            case .bubble(let id, let pipe, _, _): story.append("bubble \(id) \(pipe == 0 ? "left" : "right")")
            case .grabbed(let id): story.append("grabbed \(id)")
            case .released(let id): story.append("released \(id)")
            case .popped(let id): story.append("popped \(id)")
            case .hop(let wheel, let bubble, let onBeat): story.append("hop \(wheel) \(bubble)\(onBeat ? " on" : "")")
            case .beep(_, let garden): story.append(garden ? "beep in garden" : "beep")
            case .locked(let id): story.append("locked \(id)")
            case .unlocked: story.append("unlocked")
            case .fired(let item, let figure, _, _): story.append("\(item.name) on \(figure)")
            case .result(let r): story.append(r.headline)
            case .lap(let n): story.append("lap \(n)")
            // This scripted ride does not exercise the other event types.
            default: break
            }
        }
    }
    let results = snapshots.filter { $0.ride.events.contains(where: isResult) }.compactMap(\.ride.lastResult)
    #expect(results.count == 2)
    let first = try #require(results.first), second = try #require(results.last)
    #expect(story == ["bubble 1 right", "grabbed 1",
                      "hop rearRight 1 on", "hop rearRight 1 on", "hop rearRight 1 on", "hop rearRight 1", "hop rearRight 1 on", "released 1",
                      "beep in garden", "bubble 2 right", "grabbed 2", "locked 2", "hop rearRight 1", "popped 1", "hop rearRight 1",
                      "hot dog on \(first.figure)", "HOT DOG SERVED!", "released 2",
                      "beep", "bubble 3 right", "grabbed 3", "locked 3", "hot dog on \(second.figure)", "NO HOT DOG WANTED", "released 3",
                      "beep in garden"])
    #expect(results.map(\.result) == [.served, .unwanted] && results.map { !$0.symbol.requiresHotDog } == [false, true] && results.map(\.garden) == [true, false])
    let points = snapshots.map(\.ride.tally.points)
    #expect(points[91] == 0 && points[92] == 10 && points[133] == 30 && points[169] == 60 && points[222] == 60 && points[242] == 70)
    #expect(snapshots[169].ride.streak == 3 && snapshots[222].ride.streak == 0 && snapshots[242].ride.streak == 1)
    #expect(snapshots[700].ride.zoom == .one && snapshots[900].ride.zoom > Fixed(1.3) && snapshots[1000].ride.zoom == .one)
    #expect(snapshots[91].ride.tempo == Fixed(76.0) && snapshots[175].ride.tempo == Fixed(104.0) && snapshots[600].ride.tempo == Fixed(76.0))
    let tally = try #require(snapshots.last?.ride.tally)
    #expect(tally.alarms == 3 && tally.garden == 2 && tally.served == 1 && tally.wrong == 1 && tally.bounces == 7 && tally.onBeat == 4
            && tally.points == 70 && tally.bestStreak == 3)
}
