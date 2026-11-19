// Golden fixtures come from python/whaley_tools/stadium/kart.py.

import Foundation
import Testing
import StadiumCore
@testable import WhaleKartCore

struct Fixture: Decodable {
    struct Sample: Decodable {
        let t: Int
        let car: [Int64]
        let cans: [[Int64]]
        let strain: [Int64]
    }
    struct ModelRun: Decodable {
        let samples: [Sample]
        let events: [[FixtureValue]]
        let car: [Int64]
        let offTrackTicks: Int
        let digest: String
    }
    struct Input: Decodable {
        let t: Int
        let held: Int
        let dx: Int64
        let dz: Int64
        let toss: Bool
        let tvx: Int64
        let tvz: Int64
    }
    let parameters: KartParameters
    let inputs: [Input]
    let models: [String: ModelRun]

    static func load() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "ring-3600", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    var ropeInputs: [RopeInput] {
        inputs.map { RopeInput(held: $0.held, dx: Fixed(raw: $0.dx), dz: Fixed(raw: $0.dz), toss: $0.toss, tvx: Fixed(raw: $0.tvx), tvz: Fixed(raw: $0.tvz)) }
    }
}

// Fixture events mix string event names with integer payloads.
enum FixtureValue: Decodable, Equatable {
    case int(Int), string(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        self = .string(try c.decode(String.self))
    }
}

func carValues(_ c: Car) -> [Int64] {
    [c.x.raw, c.z.raw, c.heading.raw, c.yawRate.raw, c.speed.raw, c.progress.raw, c.offset.raw, c.side.raw, c.offTrack ? 1 : 0]
}

func fixtureEvents(_ snapshots: [WorldSnapshot]) -> [[FixtureValue]] {
    snapshots.flatMap { s in
        s.events.map { e -> [FixtureValue] in
            switch e {
            case .clink(let can): return [.int(s.tick), .string("clink"), .int(can)]
            }
        }
    }
}

@Test(arguments: RopeModel.allCases)
func swiftCoreReproducesThePythonReferenceBitForBit(model: RopeModel) throws {
    let fixture = try Fixture.load()
    let run = try #require(fixture.models[model.rawValue])
    var world = WhaleKartWorld(parameters: fixture.parameters, model: model)
    var snapshots: [WorldSnapshot] = []
    for input in fixture.ropeInputs { snapshots.append(world.step(input)) }
    for sample in run.samples {
        let s = snapshots[sample.t]
        #expect(carValues(s.car) == sample.car, "kart at tick \(sample.t)")
        #expect(s.cans.map { [$0.position.x.raw, $0.position.y.raw, $0.position.z.raw] } == sample.cans, "cans at tick \(sample.t)")
        #expect(s.strain.map { $0.raw } == sample.strain, "strain at tick \(sample.t)")
    }
    #expect(fixtureEvents(snapshots) == run.events)
    #expect(carValues(world.car) == run.car)
    #expect(world.offTrackTicks == run.offTrackTicks)
    #expect(WhaleKartDigest.digest(snapshots).hex == run.digest)
}

@Test(arguments: RopeModel.allCases)
func replayIsIdenticalRunToRun(model: RopeModel) {
    let recording = DemoScript.recording(model: model)
    let first = recording.replay()
    let second = recording.replay()
    #expect(first == second)
    #expect(WhaleKartDigest.digest(first).hex == WhaleKartDigest.digest(second).hex)
}

@Test
func theScriptTheRingAndTheParametersMatchTheFixture() throws {
    let fixture = try Fixture.load()
    #expect((0..<DemoScript.ticks).map { DemoScript.input(at: $0) } == fixture.ropeInputs)
    #expect(KartParameters.stadium == fixture.parameters)
    let ring = KartParameters.stadium.trackPoints
    #expect(ring.count == 64)
    #expect(ring[0] == GroundPoint(.zero, Fixed(45.0) - Fixed(62.0)))
    for p in ring {
        let dx = p.x - KartParameters.fieldCentre.x, dz = p.z - KartParameters.fieldCentre.z
        #expect((Fixed.sqrt(dx * dx + dz * dz) - Fixed(62.0)).magnitude < Fixed(0.01))
    }
}

@Test(arguments: RopeModel.allCases)
func theKartKeepsTheRingCounterclockwise(model: RopeModel) {
    var world = WhaleKartWorld(model: model)
    let track = world.track
    var worst = Fixed.zero
    var travelled = Fixed.zero
    var last = world.car.progress
    for t in 0..<(4 * 3900) {
        let s = world.step(DemoScript.input(at: t % DemoScript.ticks))
        if t >= 180 {
            worst = max(worst, s.car.offset)
            #expect(s.car.yawRate <= .zero, "turning left at tick \(t)")
        }
        let step = Fixed(raw: floorMod((s.car.progress - last).raw, track.total.raw))
        #expect(step < Fixed(1.0), "forward along the ring at tick \(t)")
        travelled += step
        last = s.car.progress
    }
    #expect(world.offTrackTicks == 0)
    #expect(worst < Fixed(0.25), "furthest from the centreline once under way: \(worst.double) m")
    #expect(travelled.double > 3.9 * track.total.double, "four laps: \(travelled.double / track.total.double)")
}

@Test(arguments: RopeModel.allCases)
func nothingOnTheStringsMovesTheKart(model: RopeModel) {
    var played = WhaleKartWorld(model: model), alone = WhaleKartWorld(model: model)
    for t in 0..<DemoScript.ticks {
        let a = played.step(DemoScript.input(at: t)), b = alone.step(.none)
        #expect(a.car == b.car, "the kart at tick \(t)")
        if a.car != b.car { break }
    }
}

@Test
func theKartPullsAwayFromRestToItsCruisingSpeed() {
    let p = KartParameters.stadium
    var world = WhaleKartWorld(model: .pbd)
    #expect(world.car.speed == .zero)
    var reached = -1
    for t in 0..<600 {
        let s = world.step(.none)
        #expect(s.car.speed <= p.cruiseSpeed)
        if reached < 0 && s.car.speed == p.cruiseSpeed { reached = t }
    }
    #expect(reached >= 115 && reached <= 125, "cruising after \(reached) ticks")
    #expect(world.car.speed == p.cruiseSpeed)
}

@Test(arguments: RopeModel.allCases)
func aHeldCanStaysWithinReachAndNoCanIsLost(model: RopeModel) {
    let p = KartParameters.stadium
    var world = WhaleKartWorld(model: model)
    for t in 0..<DemoScript.ticks {
        let before = world.car
        let input = DemoScript.input(at: t)
        let s = world.step(input)
        if input.held >= 0 && !input.toss {
            let hitch = before.hitch(p, string: p.string(of: input.held))
            let reachLimit = p.segment * (p.place(of: input.held) + 1)
            #expect((s.cans[input.held].position - hitch).length <= reachLimit + Fixed(0.001), "can \(input.held) at tick \(t)")
        }
        for (i, can) in s.cans.enumerated() {
            let hitch = before.hitch(p, string: p.string(of: i))
            #expect((can.position - hitch).length < p.segment * (p.cans + 1), "can \(i) on its string at tick \(t)")
        }
    }
    let limited = reach(p, string: 0, place: 2, dx: Fixed(-6.0), dz: Fixed(-4.0))
    let ex = limited.dx - p.hitches[0], ez = limited.dz
    #expect((Fixed.sqrt(ex * ex + ez * ez) - p.segment * 3).magnitude < Fixed(0.001))
    #expect(p.isRight(3) && p.isRight(5) && !p.isRight(0) && !p.isRight(2) && !p.isRight(6) && !p.isRight(-1))
}

@Test
func worldToLocalInvertsLocalToWorld() {
    let p = KartParameters.stadium
    var world = WhaleKartWorld(model: .pbd)
    for _ in 0..<500 { world.step(.none) }
    let c = world.car
    let w = c.localToWorld(p, dx: Fixed(1.25), dz: Fixed(-2.5))
    let back = c.worldToLocal(p, x: w.x, z: w.z)
    #expect((back.dx - Fixed(1.25)).magnitude < Fixed(0.001) && (back.dz - Fixed(-2.5)).magnitude < Fixed(0.001))
}
