// Recorded baseball movement stays fixed while fan assertions use current reel rules.

import Foundation
import Testing
import StadiumCore
import WhaleKartCore
import CrowdCore
@testable import StadiumGame

struct BalkFixture: Decodable {
    struct Pitcher: Decodable {
        let inView: Bool
        let fade: Int64
        // Fixture codes: 0 = free, 1 = ball, 2 = pitcher.
        let crew: Int
        let ball: Int
        let pos: [Int64]
        let runners: [Int]
        // Capture tick, or -1 when no throw is in play.
        let throwTick: Int
        let call: Int
        let attention: [Int]
        private enum CodingKeys: String, CodingKey { case inView, fade, crew, ball, pos, runners, throwTick = "throw", call, attention }
    }
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
        let states: [Int]?
        let aim: Int64?
        let wheels: [[Int64]?]
        let pipes: [[Int64]?]
        let pitcher: Pitcher
    }
    struct Tally: Decodable {
        let laps: Int, alarms: Int, served: Int, tooSoon: Int, wrong: Int, heldFire: Int, garden: Int, bounces: Int, onBeat: Int, points: Int,
            bestStreak: Int, balks: Int, balkPoints: Int
    }
    struct Balk: Decodable {
        let type: Int, released: Int, call: Int, points: Int, until: Int
    }
    struct Run: Decodable {
        let samples: [Sample]
        let events: [[Int64]]
        let ticks: Int
        let balks: [Balk]
    }
    struct Story: Decodable {
        let kind: String
        let seed: Int64
        let inputs: [StadiumInput]
        let run: Run
    }
    struct Variant: Decodable {
        let seed: Int64
        let inputs: [StadiumInput]
        let run: Run
    }
    let parameters: StadiumParameters
    let kartParameters: KartParameters
    let story: Story
    let variants: [String: Variant]

    static func load() throws -> BalkFixture {
        let url = try #require(Bundle.module.url(forResource: "balk", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(BalkFixture.self, from: Data(contentsOf: url))
    }
}

private func expectBalkSamples(_ snapshots: [StadiumSnapshot], _ run: BalkFixture.Run, fans: Range<Int>, _ label: String) {
    for sample in run.samples {
        let s = snapshots[sample.t], r = s.ride, pz = r.pitcher
        #expect(carValues(s.car) == sample.car, "\(label): the kart at tick \(sample.t)")
        #expect(s.turret.raw == sample.turret && r.zoom.raw == sample.zoom && r.steer == sample.steer && r.hops == sample.hops,
                "\(label): the turret, the zoom, the steer, the bounces at \(sample.t)")
        #expect(r.level.raw == sample.level && r.tempo.raw == sample.tempo && r.beatPhase == sample.phase, "\(label): the music at tick \(sample.t)")
        #expect(r.bubbles.map { [Int64($0.id), $0.x.raw, $0.y.raw, $0.scale.raw] } == sample.bubbles, "\(label): the bubbles at tick \(sample.t)")
        if let states = sample.states {
            #expect(fans.map { s.crowd.states[$0].rawValue } == states, "\(label): the crowd before the cutaway at tick \(sample.t)")
        }
        #expect(r.incident.map { $0.aim.raw } == sample.aim, "\(label): the aim at \(sample.t)")
        #expect(r.bullpenCart.wheels.map { $0.map { [$0.x.raw, $0.y.raw, $0.w.raw, $0.h.raw] } } == sample.wheels, "\(label): the wheels at tick \(sample.t)")
        #expect(r.bullpenCart.pipes.map { $0.map { [$0.x.raw, $0.y.raw] } } == sample.pipes, "\(label): the pipes at tick \(sample.t)")
        let f = sample.pitcher
        #expect(pz.inView == f.inView && pz.fade.raw == f.fade, "\(label): the pitcher on the picture and the Bullpen Cart's fade at \(sample.t)")
        #expect(pz.crew.rawValue == f.crew, "\(label): the camera crew's subject at \(sample.t)")
        #expect(pz.ball.state.rawValue == f.ball && [pz.ball.pos.x.raw, pz.ball.pos.y.raw, pz.ball.pos.z.raw] == f.pos, "\(label): the ball at \(sample.t)")
        #expect(pz.runners.map(\.rawValue) == f.runners, "\(label): the runners at \(sample.t)")
        #expect((pz.throwInPlay?.captured ?? -1) == f.throwTick && (pz.throwInPlay?.call ?? -1) == f.call, "\(label): the throw at \(sample.t)")
        #expect([pz.attentionFrom, pz.attentionUntil] == f.attention, "\(label): the cameras at \(sample.t)")
    }
}

private func expectBalkResults(_ snapshots: [StadiumSnapshot], _ run: BalkFixture.Run, _ label: String) throws {
    let tally = try #require(snapshots.last?.ride.tally)
    #expect(tally.balks == run.balks.count && tally.balkPoints == run.balks.reduce(0) { $0 + $1.points })
    #expect(tally.points == tally.balkPoints, "this input has no driving rewards; camera cutaways add no points")
    expectThoughtDecisions(snapshots)
    var balks: [BalkCall] = []
    for s in snapshots {
        for e in s.ride.events {
            if case .balk(let type, let points, let until) = e {
                balks.append(BalkCall(type: type, released: s.ride.pitcher.throwInPlay?.released ?? -1, call: s.tick, points: points, until: until))
            }
        }
    }
    #expect(balks.count == run.balks.count, "\(label): the balks called")
    for (b, e) in zip(balks, run.balks) {
        #expect(b.type.rawValue == e.type && b.released == e.released && b.call == e.call && b.points == e.points && b.until == e.until,
                "\(label): the balk at \(e.call)")
    }
}

private func isCaptured(_ e: RideEvent) -> Bool { if case .captured = e { true } else { false } }
private func isThrown(_ e: RideEvent) -> Bool { if case .thrown = e { true } else { false } }
private func isBalk(_ e: RideEvent) -> Bool { if case .balk = e { true } else { false } }

private func firstOutcome(_ snapshots: [StadiumSnapshot]) -> ThrowOutcome? {
    for s in snapshots {
        for e in s.ride.events {
            if case .fielded(_, _, _, let outcome) = e { return outcome }
        }
    }
    return nil
}

@Test
func theBalkStoryPreservesTheRecordedDrivingAndBaseball() throws {
    let fixture = try BalkFixture.load()
    #expect(fixture.story.kind == StadiumScript.balkStory.kind.rawValue && fixture.story.seed == StadiumScript.balkStory.seed)
    let snapshots = StadiumRecording(parameters: fixture.parameters, inputs: fixture.story.inputs).replay()
    #expect(snapshots.count == fixture.story.run.ticks)
    expectBalkSamples(snapshots, fixture.story.run, fans: 0..<fixture.parameters.stands.seats, "the story")
    #expect(snapshots.flatMap(eventRows).filter { $0[1] != 11 } == fixture.story.run.events)
    try expectBalkResults(snapshots, fixture.story.run, "the story")
}

@Test
func theBalkVariantsPreserveTheRecordedDrivingAndBaseball() throws {
    let fixture = try BalkFixture.load()
    #expect(fixture.variants.keys.sorted() == StadiumScript.balkVariants.map(\.kind.rawValue).sorted())
    for v in StadiumScript.balkVariants {
        let kind = v.kind.rawValue
        let fv = try #require(fixture.variants[kind])
        #expect(fv.seed == StadiumScript.balkStory.seed, "the \(kind) variant's seed")
        let snapshots = StadiumRecording(parameters: fixture.parameters, inputs: fv.inputs).replay()
        #expect(snapshots.flatMap(eventRows).filter { $0[1] != 11 } == fv.run.events, "the \(kind) variant's events")
        expectThoughtDecisions(snapshots)
        expectBalkSamples(snapshots, fv.run, fans: 0..<fixture.parameters.stands.seats, "the \(kind) variant")
        try expectBalkResults(snapshots, fv.run, "the \(kind) variant")
        #expect(firstOutcome(snapshots) == v.outcome, "the \(kind) variant's first throw")
    }
}

@Test
func thePitcherHandsAndTheParametersAreTheFixtures() throws {
    let fixture = try BalkFixture.load()
    #expect(StadiumScript.balkParameters() == fixture.parameters)
    #expect(StadiumParameters.stadium.ride.pitcher == fixture.parameters.ride.pitcher)
    #expect(StadiumParameters.stadium.kart == fixture.kartParameters)
    #expect(StadiumScript.pitcherInputs(kind: StadiumScript.balkStory.kind) == fixture.story.inputs)
    for v in StadiumScript.balkVariants {
        #expect(StadiumScript.pitcherInputs(kind: v.kind) == fixture.variants[v.kind.rawValue]?.inputs, "the \(v.kind) hand")
    }
}

@Test
func theThrowsAreJudgedAsTheRulesRead() {
    typealias Case = (who: Catcher, base: Base?, runners: [Base], want: ThrowOutcome)
    let cases: [Case] = [
        (.atPlate, nil, [.first], .illegalPitch), (.atBase, .first, [.first], .pickoff), (.atBase, .second, [.first], .unoccupiedBase),
        (.atBase, .third, [.first, .second], .unoccupiedBase), (.atBase, .third, [.first, .third], .pickoff), (.atBase, .first, [.second], .unoccupiedBase),
        (.outfield, nil, [.first], .noBall), (.fan, nil, [.first], .noBall), (.nobody, nil, [.first], .noBall), (.pitcherHimself, nil, [.first], .hisOwn),
    ]
    for c in cases {
        #expect(ThrowOutcome.judge(who: c.who, base: c.base, runners: c.runners) == c.want, "\(c.who.name) at \(c.base?.name ?? "no base") with runners on \(c.runners.map(\.name))")
    }
    #expect(ThrowOutcome.allCases.filter(\.isBalk).map(\.rawValue) == [0, 1, 2, 3])
    #expect(PitcherParameters.stadium.points.count == 4 && PitcherParameters.stadium.hold.count == 4)
}

@Test
func theScriptedRideNeverReachesThePitcher() throws {
    let fixture = try Fixture.load()
    let snapshots = StadiumRecording(parameters: fixture.parameters, inputs: fixture.inputs).replay()
    #expect(snapshots.allSatisfy { !$0.ride.pitcher.engaged && !$0.ride.pitcher.inView && $0.ride.pitcher.ball.state == .tossing })
    #expect(snapshots.allSatisfy { $0.ride.pitcher.fade == .zero && $0.ride.pitcher.crew == .free })
    expectThoughtDecisions(snapshots)
    let tally = try #require(snapshots.last?.ride.tally)
    #expect(tally.balks == 0 && tally.balkPoints == 0)
}

@Test
func theBalkStoryTellsItsStory() throws {
    let p = StadiumScript.balkParameters()
    let snapshots = StadiumRecording(parameters: p, inputs: StadiumScript.pitcherInputs(kind: .plate)).replay()
    var story: [String] = []
    for s in snapshots where s.tick >= 3100 {
        for e in s.ride.events {
            switch e {
            case .beep(let figure, let garden): story.append("beep \(figure)\(garden ? " in garden" : "")")
            case .bubble(let id, _, _, _): story.append("bubble \(id)")
            case .grabbed(let id): story.append("grabbed \(id)")
            case .released(let id): story.append("released \(id)")
            case .captured(let id): story.append("captured \(id)")
            case .crew(let subject): story.append("Jumbotron \(subject.name)")
            case .thrown(let how, _, _): story.append("thrown \(how)")
            case .fielded(let who, let by, _, let outcome): story.append("\(who.name) \(by): \(outcome.headline)")
            case .balk(let type, let points, let until): story.append("BALK \(type.headline) \(points) until \(until)")
            case .newBall(let runners): story.append("new ball \(runners.map(\.name))")
            case .result(let r): story.append(r.headline)
            case .lap(let n): story.append("lap \(n)")
            default: break
            }
        }
    }
    #expect(story == ["beep 20 in garden", "bubble 1", "grabbed 1", "captured 1", "Jumbotron the ball", "released 1", "thrown thrown",
                      "at the plate 1: ILLEGAL PITCH", "BALK ILLEGAL PITCH 100 until 3609", "Jumbotron the pitcher",
                      "new ball [\"first\", \"second\"]", "lap 1", "HOT DOG MISSED", "Jumbotron free"])
    #expect(snapshots[3200].ride.pitcher.runners == [.first, .third] && snapshots[3470].ride.pitcher.runners == [.first, .second])
    #expect(snapshots[3200].ride.pitcher.ball.state == .tossing && snapshots[3260].ride.pitcher.ball.state == .captured
            && snapshots[3290].ride.pitcher.ball.state == .flying && snapshots[3330].ride.pitcher.ball.state == .settled
            && snapshots[3350].ride.pitcher.ball.state == .dead && snapshots[3470].ride.pitcher.ball.state == .tossing)
    #expect(!snapshots[3136].ride.pitcher.inView && snapshots[3137].ride.pitcher.inView && snapshots[3416].ride.pitcher.inView
            && !snapshots[3417].ride.pitcher.inView)
    #expect(snapshots[3136].ride.pitcher.fade == .zero && snapshots[3140].ride.pitcher.fade > Fixed(0.3) && snapshots[3189].ride.pitcher.fade < .one
            && snapshots[3190].ride.pitcher.fade == .one && snapshots[3300].ride.pitcher.fade == .one && snapshots[3430].ride.pitcher.fade < Fixed(0.3)
            && snapshots[3469].ride.pitcher.fade > .zero && snapshots[3470].ride.pitcher.fade == .zero)
    #expect(snapshots[3136].ride.zoom == .one && snapshots[3137].ride.zoom < .one && snapshots[3200].ride.zoom < Fixed(0.85)
            && snapshots[3200].ride.zoom > Fixed(0.83) && snapshots[3416].ride.zoom < Fixed(0.85) && snapshots[3470].ride.zoom == .one)
    #expect(snapshots.filter { $0.ride.pitcher.fade == .zero }.allSatisfy { ($0.ride.zoom - .one).magnitude <= p.ride.view.zoomSnap }, "the cannon's zoom with him off")
    #expect(snapshots[3248].ride.pitcher.crew == .free && snapshots[3249].ride.pitcher.crew == .ball && snapshots[3330].ride.pitcher.crew == .ball
            && snapshots[3338].ride.pitcher.crew == .ball && snapshots[3339].ride.pitcher.crew == .pitcher
            && snapshots[3608].ride.pitcher.crew == .pitcher && snapshots[3609].ride.pitcher.crew == .free)
    let s3339 = snapshots[3339].ride
    #expect(s3339.pitcher.attentionFrom == 3339 && s3339.pitcher.attentionUntil == 3609 && s3339.pitcher.camerasOnHim(at: 3437))
    let status = try #require(s3339.lastThrow)
    #expect(status.outcome == .illegalPitch && status.points == 100 && status.who == .atPlate && status.by == 1 && status.call == 3339
            && status.released == 3265 && status.captured == 3249 && s3339.lastThrowTick == 3339)
    let results = snapshots.filter { $0.ride.events.contains(where: isResult) }.compactMap(\.ride.lastResult)
    #expect(results.count == 4 && results.last?.result == .missedRequest && results.last?.beep == 3137 && results.last?.endTick == 3497)
    let tally = try #require(snapshots.last?.ride.tally)
    #expect(tally.balks == 1 && tally.balkPoints == 100 && tally.points == 100 && tally.wrong == 3
            && tally.bounces == 0)
    #expect(snapshots.last?.ride.pitcher.engaged == true)
}

@Test
func theBalkVariantsKeepTheirBaseballCallsAndNeverServeAHotDog() throws {
    let p = StadiumScript.balkParameters()
    var lines: [String: String] = [:]
    for v in StadiumScript.balkVariants {
        let snapshots = StadiumRecording(parameters: p, inputs: StadiumScript.pitcherInputs(kind: v.kind, ticks: 4300)).replay()
        var who = "", outcome = "", points = 0
        for snapshot in snapshots {
            for event in snapshot.ride.events {
                if case .fielded(let catcher, _, _, let call) = event, outcome.isEmpty { who = catcher.name; outcome = call.headline }
                if case .balk(_, let scored, _) = event { points += scored }
            }
        }
        lines[v.kind.rawValue] = "\(who): \(outcome), \(points)"
        let decision = try #require(snapshots.first { $0.ride.lastResult?.beep == 3137 }?.ride.lastResult)
        #expect(decision.result == .missedRequest && decision.shot == -1)
        #expect(snapshots.last?.ride.tally.served == 0)
        expectThoughtDecisions(snapshots)
    }
    #expect(lines["base"] == "at a base: UNOCCUPIED BASE, 150")
    #expect(lines["pickoff"] == "at a base: PICKOFF, 0")
    #expect(lines["wild"] == "nobody: NO BALL ON THE RUBBER, 50")
    #expect(lines["drop"] == "the pitcher: DROPPED BALL, 50")
    #expect(lines["hold"] == "the pitcher: NO BALL ON THE RUBBER, 50")
    #expect(lines["self"] == "the pitcher: HIS OWN, 0")
    #expect(lines["cancel"] == "the pitcher: DROPPED BALL, 50")
}

@Test
func baseballCoverageCannotPostponeTheFanReelOrItsResponseWindow() throws {
    let p = StadiumScript.balkParameters()
    let snapshots = StadiumRecording(parameters: p, inputs: StadiumScript.pitcherInputs(kind: .plate)).replay()
    let first = try #require(snapshots[3137].ride.incident)
    #expect(first.start == 3437 && first.end == 3497 && first.symbol == .hotDog)
    // Capture, flight, and the call overlap this reel and its response window.
    for tick in 3249..<3497 {
        let snapshot = snapshots[tick]
        let incident = try #require(snapshot.ride.incident)
        #expect(incident.start == first.start && incident.end == first.end && incident.isLive)
        #expect(StadiumGame.showsFan(crew: snapshot.ride.pitcher.crew,
                                     dollOnJumbotron: incident.onJumbotron(at: tick), zoomed: snapshot.ride.jumbo.zoom != nil))
        #expect(incident.thought(at: tick)?.isSpinning == (tick < first.start))
        #expect(!snapshot.ride.events.contains(where: isResult))
    }
    #expect(snapshots[3437].ride.pitcher.crew == .pitcher)
    #expect(snapshots[3437].ride.incident?.thought(at: 3437)?.symbol == .hotDog)
    #expect(snapshots[3497].ride.lastResult?.result == .missedRequest)
    #expect(snapshots[3497].ride.tally.points == 100 && snapshots[3497].ride.tally.served == 0)
    #expect(snapshots[3526].ride.incident?.onJumbotron(at: 3526) == true)
    #expect(snapshots[3527].ride.incident?.onJumbotron(at: 3527) == false)
}

@Test
func theViewIsTheCannonsAndTheCrewFollowsTheBall() throws {
    let p = StadiumScript.balkParameters()
    var cuts: [String: [[Int]]] = [:]
    var wrong: [String] = []
    for kind in [StadiumScript.balkStory.kind] + StadiumScript.balkVariants.map(\.kind) {
        let snapshots = StadiumRecording(parameters: p, inputs: StadiumScript.pitcherInputs(kind: kind)).replay()
        let label = kind.rawValue
        for s in snapshots {
            let pz = s.ride.pitcher
            if pz.fade == .zero && (s.ride.zoom - .one).magnitude > p.ride.view.zoomSnap { wrong.append("\(label): the view zoomed with the fade gone at \(s.tick)") }
            if s.ride.zoom > .one { wrong.append("\(label): the view zoomed out at \(s.tick)") }
            if pz.fade == .one && s.ride.zoom > Fixed(0.9) && s.tick > 3200 { wrong.append("\(label): the view not in with the fade full at \(s.tick)") }
            if pz.fade == .one && !pz.inView { wrong.append("\(label): the Bullpen Cart faded with him off the picture at \(s.tick)") }
            if pz.fade == .zero && pz.inView && s.tick > 3140 { wrong.append("\(label): the Bullpen Cart not faded with him on the picture at \(s.tick)") }
            if s.tick % 100 == 0 {
                let plain = TurretCamera(car: s.car, parameters: p), now = TurretCamera(car: s.car, parameters: p, zoom: s.ride.zoom, onHim: pz.fade)
                let back = (now.eye - Vec3(s.car.x, .zero, s.car.z)), plainBack = (plain.eye - Vec3(s.car.x, .zero, s.car.z))
                if pz.fade == .zero && now.eye != plain.eye { wrong.append("\(label): the eye off the cannon's spot at \(s.tick)") }
                if pz.fade > .zero && Fixed.sqrt(back.x * back.x + back.z * back.z) >= Fixed.sqrt(plainBack.x * plainBack.x + plainBack.z * plainBack.z) {
                    wrong.append("\(label): the eye not nearer the turret with the fade up at \(s.tick)")
                }
                if now.yaw != plain.yaw { wrong.append("\(label): the view turned at \(s.tick)") }
            }
            let onHim = pz.camerasOnHim(at: s.tick)
            let away = pz.ball.state == .captured || pz.ball.state == .flying || pz.ball.state == .settled
            let after = s.ride.lastThrow.map { !$0.outcome.isBalk && s.tick < s.ride.lastThrowTick + p.ride.pitcher.crewAfterCall } ?? false
            let want: CrewSubject = onHim ? .pitcher : (away || after ? .ball : .free)
            if pz.crew != want { wrong.append("\(label): the crew on \(pz.crew.name), not \(want.name), at \(s.tick)") }
            for e in s.ride.events {
                if case .crew(let subject) = e { cuts[label, default: []].append([s.tick, subject.rawValue]) }
            }
        }
    }
    #expect(wrong.isEmpty, "\(wrong.prefix(5))")
    func cut(_ kind: String) -> [[Int]] { cuts[kind] ?? [] }
    #expect(cut("plate") == [[3249, 1], [3339, 2], [3609, 0]])
    #expect(cut("base") == [[3249, 1], [3357, 2], [3627, 0]])
    #expect(cut("pickoff") == [[3249, 1], [3417, 0]], "a second on the ball past the pickoff's call, then free")
    #expect(cut("wild") == [[3249, 1], [3632, 2]], "the ball's six seconds, then the hold outlasts the run")
    #expect(cut("drop") == [[3249, 1], [3287, 2], [3467, 0]])
    #expect(cut("hold") == [[3249, 1], [3454, 2]])
    #expect(cut("self") == [[3249, 1], [3355, 0]], "a second on the ball in his glove past his own catch's call")
    #expect(cut("cancel") == [[3249, 1], [3287, 2], [3467, 0]])
}

@Test
func theBullpenCartFadesAndTheViewZoomsInWhileHeIsOnThePicture() throws {
    let p = StadiumScript.balkParameters()
    let v = p.ride.view
    let pitcherParameters = p.ride.pitcher
    let w = p.picture.width, h = p.picture.height
    var game = StadiumGame(parameters: p)
    var inView: [Int] = [], last = Fixed.zero, wrong: [String] = []
    var fullAt = -1, goneAt = -1, closest = Fixed.one
    for _ in 0..<3700 {
        let s = game.step(.none)
        let pz = s.ride.pitcher
        if pz.inView { inView.append(s.tick) }
        if pz.inView && pz.fade < last { wrong.append("the fade falling with him on the picture at \(s.tick)") }
        if !pz.inView && pz.fade > last { wrong.append("the fade rising with him off the picture at \(s.tick)") }
        if pz.fade == .one && fullAt < 0 { fullAt = s.tick }
        if fullAt >= 0 && !pz.inView && pz.fade == .zero && goneAt < 0 { goneAt = s.tick }
        if pz.fade == .zero && (s.ride.zoom - .one).magnitude > v.zoomSnap { wrong.append("the view zoomed with the fade gone at \(s.tick)") }
        closest = min(closest, s.ride.zoom)
        if pz.fade == .one {
            let cam = game.camera
            guard let j = cam.project(p.jumbotron) else { wrong.append("the Jumbotron behind the eye at \(s.tick)"); continue }
            if j.x < w * v.zoomMarginX - Fixed(0.5) || j.y < h * v.zoomMarginY - Fixed(0.5) { wrong.append("the Jumbotron out of its margin at \(s.tick)") }
            for (i, f) in game.figures.enumerated() where game.isInGarden(i) {
                guard let q = cam.project(f.head) else { wrong.append("an garden seat behind the eye at \(s.tick)"); continue }
                if q.x < .zero || q.x > w || q.y < .zero || q.y > h { wrong.append("garden seat \(i) off the picture at \(s.tick)") }
            }
            let back = cam.eye - Vec3(s.car.x, .zero, s.car.z)
            if (Fixed.sqrt(back.x * back.x + back.z * back.z) - pitcherParameters.onHimBehind).magnitude > Fixed(0.05) || cam.eye.y != pitcherParameters.onHimUp {
                wrong.append("the eye off the gunner's shoulder at \(s.tick)")
            }
            if s.ride.bullpenCart.pipes.contains(where: { $0 == nil }) { wrong.append("a pipe behind the eye at \(s.tick)") }
        }
        last = pz.fade
    }
    #expect(wrong.isEmpty, "\(wrong.prefix(5))")
    #expect(inView.first == 3137 && inView.last == 3416 && inView.count == 3416 - 3137 + 1, "on the picture without a break")
    #expect(fullAt == 3190 && goneAt == 3470)
    #expect(closest > Fixed(0.83) && closest < Fixed(0.85), "in 1.19 times at the most: \(1 / closest.double)")
    #expect(game.inView == false && game.fade == .zero && game.pitcherInView(camera: game.baseCamera) == false)
    #expect(game.baseCamera.eye.y == v.up && game.camera.eye == game.baseCamera.eye, "the cannon's eye with the fade gone")
}

@Test
func theCapturedBallRidesInTheBubble() throws {
    let p = StadiumScript.balkParameters()
    let inputs = StadiumScript.pitcherInputs(kind: .hold)
    var game = StadiumGame(parameters: p)
    var captured: StadiumSnapshot?
    for input in inputs.prefix(3300) {
        let s = game.step(input)
        if s.ride.events.contains(where: isCaptured) { captured = s }
        if let c = captured, s.tick > c.tick, s.ride.pitcher.ball.state == .captured {
            let b = try #require(s.ride.bubbles.first { $0.id == s.ride.pitcher.ball.bubble })
            let q = try #require(game.camera.point(s.ride.pitcher.ball.pos))
            #expect(b.x == q.x && b.y == q.y, "the bubble's middle on the ball at \(s.tick)")
            #expect(b.isBeingMoved && b.isFrozen, "held")
        }
    }
    let c = try #require(captured)
    #expect(c.tick == 3249 && c.ride.pitcher.ball.bubble == 1 && c.ride.pitcher.throwInPlay?.captured == 3249)
    let d = game.ball.pos - c.ride.pitcher.ball.pos
    #expect(d.length < Fixed(3.0), "the ball near where it was captured")
}

@Test
func theBallKeptTooLongIsCalled() throws {
    let p = StadiumScript.balkParameters()
    let snapshots = StadiumRecording(parameters: p, inputs: StadiumScript.pitcherInputs(kind: .hold)).replay()
    let thrown = try #require(snapshots.first { $0.ride.events.contains(where: isThrown) })
    #expect(thrown.tick == 3249 + p.ride.pitcher.holdLimit)
    #expect(thrown.ride.events.contains { if case .thrown(let how, _, _) = $0 { how == .held } else { false } })
    #expect(thrown.ride.events.contains { if case .released(let id) = $0 { id == 1 } else { false } }, "the bubble let go of")
    let called = try #require(snapshots.first { $0.ride.events.contains(where: isBalk) })
    #expect(called.ride.events.contains { if case .balk(let type, let points, _) = $0 { type == .noBall && points == 50 } else { false } })
    #expect(called.ride.pitcher.attentionUntil - called.tick == p.ride.pitcher.hold[ThrowOutcome.noBall.rawValue])
}

@Test
func theDollsReachAcrossTheFieldWhileThePitcherIsInView() throws {
    let p = StadiumScript.balkParameters()
    var game = StadiumGame(parameters: p)
    var beeps: [(tick: Int, figure: Int, inView: Bool, depth: Fixed)] = []
    for _ in 0..<3700 {
        let s = game.step(.none)
        for e in s.ride.events {
            if case .beep(let figure, _) = e {
                let head = try #require(game.camera.project(game.figures[figure].head))
                // Reach is measured before pitcher fade and zoom alter the camera.
                beeps.append((s.tick, figure, s.ride.pitcher.inView, head.depth))
            }
        }
    }
    #expect(beeps.map(\.tick) == [636, 1571, 2406, 3137] && beeps.map(\.figure) == [85, 26, 26, 20])
    #expect(beeps.last?.inView == true, "the fourth doll goes off as the pitcher comes into view")
    #expect(beeps.dropLast().allSatisfy { !$0.inView }, "the others with the pitcher out of view")
    let across = try #require(beeps.last)
    #expect(p.ride.alarm.maxDepth < across.depth && across.depth <= p.ride.pitcher.dollReach,
            "the fourth fan needs the expanded reach")
    #expect(beeps.dropLast().allSatisfy { $0.depth <= p.ride.alarm.maxDepth }, "the other fans use the ordinary reach")
}
