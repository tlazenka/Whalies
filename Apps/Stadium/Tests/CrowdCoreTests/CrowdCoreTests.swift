// Golden fixtures come from python/whaley_tools/stadium/crowd.py.

import Foundation
import Testing
import StadiumCore
@testable import CrowdCore

struct Fixture: Decodable {
    struct View: Decodable {
        let target: Int
        let basis: [[Int64]]
        let framed: [Int]
    }
    struct Ray: Decodable {
        let figure: Int
        let dyaw: Int64
        let dpitch: Int64
        let yaw: Int64
        let pitch: Int64
        let hit: [Int64]?
    }
    struct CrowdRun: Decodable {
        let samples: [[Int]]
        let called: [Int]
        let digest: String
    }
    let stands: StandsParameters
    let figures: [[Int64]]
    let camera: Camera
    let cameraViews: [View]
    let aim: AimParameters
    let scope: [[Int64]]
    let muzzle: Vec3
    let rays: [Ray]
    let crowd: CrowdParameters
    let schedule: [FanThought]
    let strikes: [String: [Int]]
    let catches: [String: [Int]]
    let crowdRun: CrowdRun

    static func load() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "crowd", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}

// Keep inputs aligned with scope_script in python/whaley_tools/stadium/crowd.py.
func scopeScript(_ t: Int, sensitivity s: Fixed) -> AimInput {
    if t == 20 { return AimInput(phase: .began, dx: Fixed(300.0), dy: Fixed(-200.0)) }
    if 21 <= t && t < 60 { return AimInput.move(7, -3, sensitivity: s) }
    if t == 60 { return AimInput(phase: .ended) }
    if t == 100 { return AimInput(phase: .ended) }
    if t == 150 { return AimInput(phase: .began) }
    if 151 <= t && t < 200 { return AimInput.move(-11, 5, sensitivity: s) }
    if t == 200 { return AimInput(phase: .cancelled) }
    if 250 <= t && t < 260 { return AimInput.move(40, 40, sensitivity: s) }
    if t == 300 { return AimInput(phase: .began) }
    if t == 301 { return AimInput(phase: .ended) }
    if t == 330 { return AimInput(phase: .began) }
    if 331 <= t && t < 380 { return AimInput.move(0, 70, sensitivity: s) }
    if t == 380 { return AimInput(phase: .ended) }
    return .none
}

@Test
func theStandsAreThePythonsFans() throws {
    let fixture = try Fixture.load()
    #expect(fixture.stands == StandsParameters.stadium)
    let figures = StandsParameters.stadium.figures()
    #expect(figures.count == 192)
    #expect(figures.map { [$0.x.raw, $0.base.raw, $0.z.raw, $0.headY.raw, $0.torsoY.raw] } == fixture.figures)
    let s = StandsParameters.stadium
    #expect(figures[0].x == .zero && figures[0].z == Fixed(45.0) - Fixed(70.0))
    #expect(figures[32].x.magnitude < Fixed(0.01) && Fixed(114.0) < figures[32].z)
    #expect(s.place(of: 72) == (row: 1, seat: 8))
}

@Test
func theCameraFramesWhatThePythonFrames() throws {
    let fixture = try Fixture.load()
    let figures = fixture.stands.figures()
    for view in fixture.cameraViews {
        let b = fixture.camera.basis(lookingAt: figures[view.target].head)
        #expect([b.forward, b.right, b.up].map { [$0.x.raw, $0.y.raw, $0.z.raw] } == view.basis, "basis on \(view.target)")
        #expect(figures.indices.filter { fixture.camera.frames(figures[$0].head, basis: b) } == view.framed, "framed on \(view.target)")
        #expect(view.framed.contains(view.target))
    }
}

@Test
func relativeAimingThroughTheScriptedRun() throws {
    let fixture = try Fixture.load()
    var scope = Scope(yaw: Fixed(0.25))
    var rows: [[Int64]] = []
    for t in 0..<fixture.scope.count {
        let fire = scope.step(aim: fixture.aim, input: scopeScript(t, sensitivity: fixture.aim.sensitivity[0]))
        rows.append([scope.yaw.raw, scope.pitch.raw, scope.holding ? 1 : 0, fire ? 1 : 0])
    }
    #expect(rows == fixture.scope)
    #expect(rows.indices.filter { rows[$0][3] == 1 } == [60, 301, 380])
}

@Test
func aHotDogMeetsTheFirstFanOnItsWay() throws {
    let fixture = try Fixture.load()
    let figures = fixture.stands.figures()
    for ray in fixture.rays {
        let d = Trig.direction(yaw: Fixed(raw: Trig.normalize(ray.yaw + ray.dyaw)), pitch: Fixed(raw: ray.pitch + ray.dpitch))
        let hit = firstHit(origin: fixture.muzzle, direction: d, figures: figures)
        #expect(hit.map { [Int64($0.figure), Int64($0.part.rawValue), $0.distance.raw] } == ray.hit, "ray at \(ray.figure)")
        let h = figures[ray.figure].head
        let dx = h.x - fixture.muzzle.x, dy = h.y - fixture.muzzle.y, dz = h.z - fixture.muzzle.z
        #expect(Trig.bearing(dx: dx, dz: dz).raw == ray.yaw)
        #expect(Trig.elevation(dy: dy, horizontal: Fixed.sqrt(dx * dx + dz * dz)).raw == ray.pitch)
    }
    let r = fixture.rays[0]
    let d = Trig.direction(yaw: Fixed(raw: r.yaw), pitch: Fixed(raw: r.pitch))
    #expect(firstHit(origin: fixture.muzzle, direction: d, figures: figures, skip: [r.figure])?.figure != r.figure)
}

@Test
func theCrowdsStatesThroughThoughtsStrikesAndCatches() throws {
    let fixture = try Fixture.load()
    let figures = fixture.stands.figures()
    var crowd = Crowd(count: figures.count, parameters: fixture.crowd)
    var called: Set<Int> = []
    var digest = ReplayDigest()
    var samples: [[Int]] = []
    for t in 0..<400 {
        let struck = Set(fixture.strikes[String(t)] ?? []), caught = Set(fixture.catches[String(t)] ?? [])
        for (k, s) in fixture.schedule.enumerated() {
            for (i, duration) in struck.sorted().map({ ($0, fixture.crowd.strikeTicks) }) + caught.sorted().map({ ($0, fixture.crowd.catchTicks) })
            where s.figure == i && s.isCalledOff(at: t, for: duration) {
                called.insert(k)
            }
        }
        let snapshot = crowd.step(struck: struck, caught: caught) { i in
            for (k, s) in fixture.schedule.enumerated() where s.figure == i && !called.contains(k) {
                if let ph = s.phase(at: t) { return ph }
            }
            return nil
        }
        CrowdDigest.mix(&digest, snapshot)
        if t % 10 == 0 { samples.append([t] + [3, 5, 9, 64].map { snapshot.states[$0].rawValue }) }
    }
    #expect(samples == fixture.crowdRun.samples)
    #expect(called.sorted() == fixture.crowdRun.called)
    #expect(digest.hex == fixture.crowdRun.digest)
}

@Test
func thoughtPhasesRevealOnlyTheFinalPicture() {
    let request = FanThought(figure: 4, start: 300, end: 360, spinTicks: 90)
    let other = FanThought(figure: 4, start: 500, end: 560, spinTicks: 90, symbol: .star)
    #expect(request.phase(at: 209) == nil && request.phase(at: 210) == .spinning && request.phase(at: 299) == .spinning)
    #expect(request.phase(at: 300) == .requesting && request.phase(at: 359) == .requesting && request.phase(at: 360) == nil)
    #expect(other.phase(at: 410) == .spinning && other.phase(at: 500) == .watching && other.phase(at: 560) == nil)
    #expect(request.isCalledOff(at: 100, for: 120) && !request.isCalledOff(at: 90, for: 120))
    #expect(request.isCalledOff(at: 359, for: 1) && !request.isCalledOff(at: 360, for: 1))
}

@Test
func theReelCyclesSlowsAndLandsOnEveryConfiguredSymbol() throws {
    for symbol in ThoughtSymbol.allCases {
        let thought = FanThought(figure: 4, start: 300, end: 390, spinTicks: 300, symbol: symbol)
        let frames = (0..<300).compactMap { thought.frame(at: $0) }
        #expect(frames.count == 300 && frames.allSatisfy(\.isSpinning))
        #expect(Set(frames.map(\.symbol)) == Set(ThoughtSymbol.allCases))
        #expect(frames.allSatisfy { 0 <= $0.progress && $0.progress < 1 })
        let lastSlot = try #require(thought.frame(at: 276))
        #expect(lastSlot.progress == 0 && lastSlot.nextSymbol == symbol)
        let lastFrame = try #require(thought.frame(at: 299))
        #expect(lastFrame.symbol == lastSlot.symbol && lastFrame.progress == 23.0 / 24.0)
        for tick in [300, 301, 389] {
            let settled = try #require(thought.frame(at: tick))
            #expect(!settled.isSpinning && settled.symbol == symbol && settled.nextSymbol == symbol && settled.progress == 0)
        }
        #expect(thought.frame(at: -1) == nil && thought.frame(at: 390) == nil)
    }
    #expect(ThoughtSymbol.allCases.filter(\.requiresHotDog) == [.hotDog])
}

@Test
func relativeAimingPromises() {
    let p = AimParameters(magnifications: [4], sensitivity: [Fixed(raw: 3)], pitchLimit: Fixed(0.1))
    let s = p.sensitivity[0]
    var scope = Scope(yaw: Fixed(0.25), pitch: .zero)
    let down = scope.step(aim: p, input: AimInput(phase: .began, dx: Fixed(300), dy: Fixed(-200)))
    #expect(!down && scope.yaw == Fixed(0.25) && scope.pitch == .zero && scope.holding)
    var yaw = Fixed(0.25).raw, pitch: Int64 = 0
    for k in [3, -5, 11, 0, -2] as [Int64] {
        _ = scope.step(aim: p, input: AimInput.move(k, -k, sensitivity: s))
        yaw += k; pitch -= k
        #expect(scope.yaw.raw == Trig.normalize(yaw) && scope.pitch.raw == pitch)
    }
    #expect((AimInput.drag(7, sensitivity: s) * s).raw == 7 && (AimInput.drag(-7, sensitivity: s) * s).raw == -7)
    let lift = scope.step(aim: p, input: AimInput(phase: .ended))
    let again = scope.step(aim: p, input: AimInput(phase: .ended))
    #expect(lift && !again)
    _ = scope.step(aim: p, input: AimInput(phase: .began))
    let taken = scope.step(aim: p, input: AimInput(phase: .cancelled))
    #expect(!taken && !scope.holding)
    let after = scope.step(aim: p, input: AimInput(phase: .ended))
    #expect(!after)
    let still = scope
    _ = scope.step(aim: p, input: AimInput.move(40, 40, sensitivity: s))
    #expect(scope == still)
}
