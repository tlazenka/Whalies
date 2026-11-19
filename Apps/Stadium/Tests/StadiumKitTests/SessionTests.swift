import Foundation
#if canImport(simd)
import simd
#endif
import Observation
import Testing
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame
@testable import StadiumKit

@MainActor
private func session(stadium: Bool = true) -> StadiumSession {
    let s = StadiumSession()
    s.audioOutput = .off
    s.stop()
    if stadium { s.reset(to: .stadium); s.stop() }
    return s
}

@MainActor
private func ticks(_ s: StadiumSession, _ n: Int) { for _ in 0..<n { s.advance() } }

@MainActor
private func play(_ s: StadiumSession, _ hand: inout StadiumScript.Hand, most: Int = 3000, until done: (StadiumSession) -> Bool) {
    for _ in 0..<most {
        let f = hand.input(s.game, at: s.game.tick).finger
        let at = CGPoint(x: f.x.double, y: f.y.double)
        switch f.phase {
        case .began: s.fingerBegan(at: at)
        case .moved: s.fingerMoved(to: at)
        case .ended: s.fingerEnded(at: at)
        case .cancelled: s.fingerCancelled()
        case .none: break
        }
        s.advance()
        if done(s) { return }
    }
}

@MainActor
private func has(_ s: StadiumSession, _ match: (RideEvent) -> Bool) -> Bool { s.snapshot.ride.events.contains(where: match) }

@MainActor
private func playPitcher(_ s: StadiumSession, _ hand: inout StadiumScript.PitcherHand, most: Int = 3700, until done: (StadiumSession) -> Bool) {
    for _ in 0..<most {
        let f = hand.input(s.game, at: s.game.tick).finger
        let at = CGPoint(x: f.x.double, y: f.y.double)
        switch f.phase {
        case .began: s.fingerBegan(at: at)
        case .moved: s.fingerMoved(to: at)
        case .ended: s.fingerEnded(at: at)
        case .cancelled: s.fingerCancelled()
        case .none: break
        }
        s.advance()
        if done(s) { return }
    }
}

@Test
@MainActor
func theRideStartsAndPlaysAgainOnTheViewsPicture() {
    let s = session(stadium: false)
    #expect(s.tick == 0 && s.recording.inputs.count == 1 && s.parameters.picture == .phone)
    let play = s.playID
    s.viewResized(SIMD2(393, 852))
    #expect(s.parameters.picture == PictureParameters(width: Fixed(393.0), height: Fixed(852.0)) && s.playID == play + 1 && s.tick == 0)
    #expect(s.map.scale == 1 && s.map.offsetX == 0)
    ticks(s, 30)
    #expect(s.tick == 30 && s.recording.inputs.count == 31)
    s.fingerBegan(at: CGPoint(x: 100, y: 300))
    s.fingerEnded(at: CGPoint(x: 100, y: 300))
    ticks(s, 2)
    s.viewResized(SIMD2(786, 1704))
    #expect(s.playID == play + 1 && s.map.scale == 2 && abs(s.map.offsetX) < 0.001)
    let seed = s.parameters.seed
    s.playAgain()
    s.stop()
    #expect(s.playID == play + 2 && s.parameters.picture.width == Fixed(786.0) && s.recording.inputs.count == 1 && s.parameters.seed != seed)
}

@Test
@MainActor
func theFingerReachesTheCoreOnePhaseATickInThePicturesPoints() throws {
    let s = session()
    let before = s.recording.inputs.count
    #expect(s.fingerBegan(at: CGPoint(x: 120, y: 300)))
    #expect(!s.fingerBegan(at: CGPoint(x: 300, y: 300)), "one finger at a time")
    s.fingerMoved(to: CGPoint(x: 130, y: 290))
    s.fingerMoved(to: CGPoint(x: 140, y: 280))       // Coalesce both reports into the latest move.
    s.fingerEnded(at: CGPoint(x: 140, y: 280))
    ticks(s, 4)
    let fingers = s.recording.inputs[before...].map(\.finger)
    #expect(fingers == [FingerInput(phase: .began, x: Fixed(120.0), y: Fixed(300.0)), FingerInput(phase: .moved, x: Fixed(140.0), y: Fixed(280.0)),
                        FingerInput(phase: .ended, x: Fixed(140.0), y: Fixed(280.0)), .none])
    #expect(s.game.bubbles.count == 1, "a tap off any bubble: one out of the exhaust")
    s.fingerBegan(at: CGPoint(x: 200, y: 400))
    s.fingerMoved(to: CGPoint(x: 210, y: 410))
    s.releaseEverything()
    ticks(s, 3)
    #expect(s.recording.inputs.suffix(3).map(\.finger.phase) == [.began, .moved, .cancelled])
    #expect(s.recording.inputs.last?.finger.x == Fixed(210.0))
}

@Test
@MainActor
func theViewBehindTheTurretIsTheCores() throws {
    let s = session()
    let size = SIMD2<Float>(390, 844)
    let p = s.parameters, h = p.ride.bullpenCart
    for _ in 0..<12 {
        ticks(s, 100)
        let car = s.snapshot.car
        let cam = s.camera
        let core = TurretCamera(car: car, parameters: p)
        let on = BullpenCartOnPicture(camera: core, car: car, bullpenCart: h)
        for (k, wheel) in Wheel.allCases.enumerated() {
            let rear = wheel == .rearLeft || wheel == .rearRight
            let centre = kartPoint(car, right: wheel.isLeft ? -h.wheelSide : h.wheelSide, forward: rear ? -h.wheelBack : h.wheelFront, up: h.wheelHeight)
            let q = try #require(cam.project(SceneMapping.scene(centre), viewSize: size))
            let rect = try #require(on.wheels[k])
            #expect(abs(Double(q.x) - rect.midX.double) < 0.5 && abs(Double(q.y) - rect.midY.double) < 0.5, "wheel \(k) at tick \(s.tick)")
        }
        for (k, dx) in [-h.pipeSide, h.pipeSide].enumerated() {
            let q = try #require(cam.project(SceneMapping.scene(kartPoint(car, right: dx, forward: -h.pipeBack, up: h.pipeHeight)), viewSize: size))
            let pipe = try #require(on.pipes[k])
            #expect(abs(Double(q.x) - pipe.x.double) < 0.5 && abs(Double(q.y) - pipe.y.double) < 0.5, "pipe \(k) at tick \(s.tick)")
        }
        let j = try #require(core.point(p.jumbotron))
        let q = try #require(cam.project(SceneMapping.scene(p.jumbotron), viewSize: size))
        #expect(abs(Double(q.x) - j.x.double) < 1 && abs(Double(q.y) - j.y.double) < 1 && q.x < 130 && q.y < 220, "the Jumbotron at tick \(s.tick)")
    }
    let fan = s.game.figures[90]
    if let q = s.game.camera.point(fan.head), let v = s.camera.project(SceneMapping.scene(fan.head), viewSize: size) {
        #expect(abs(Double(v.x) - q.x.double) < 1 && abs(Double(v.y) - q.y.double) < 1)
    }
}

@Test
@MainActor
func theGardenSectionsTreesShowOverTheBackWall() throws {
    let p = session().parameters
    let st = p.stands, iso = p.ride.garden
    let c = (x: st.centre.x.double, z: st.centre.z.double)
    let back = try #require(st.rows.last)
    let wall = back.radius.double + RideRig.wallBehind + RideRig.wallThickness / 2
    func bearing(_ v: SIMD3<Float>) -> (turns: Double, distance: Double) {
        let o = SceneMapping.stadium(v)
        let dx = o.x - c.x, dz = o.z - c.z
        return (SceneMapping.heading(dx: dx, dz: dz), (dx * dx + dz * dz).squareRoot())
    }
    let trees = RideRig.gardenTrees(parameters: p)
    try #require(trees.count == 7)
    #expect(Set(trees.map(\.green)) == [0, 1, 2])
    let feet = trees.map { bearing($0.foot) }
    #expect(abs(feet[0].turns - st.bearing(seat: iso.firstSeat).double) < 1e-5)
    #expect(abs(feet[6].turns - st.bearing(seat: iso.firstSeat + iso.seats - 1).double) < 1e-5)
    #expect(zip(feet, feet.dropFirst()).allSatisfy { $0.turns > $1.turns })
    for (t, foot) in zip(trees, feet) {
        #expect(foot.distance > wall + 2 && t.foot.y == 0, "behind the wall's back face, on the ground")
        #expect(abs(t.foot.y + t.height - t.crown[0].centre.y) < 1e-4, "the trunk up to the crown's middle")
        #expect(t.crown.allSatisfy { $0.centre.y - $0.radius > Float(RideRig.wallHeight) }, "over the wall's top")
    }
    // The Jumbotron is composited over the scene, so its screen must never cover a tree crown.
    let screen = Cameras.jumbotronCorners(parameters: p)
    let middle = screen.reduce(SIMD3<Float>(repeating: 0), +) / 4
    var least = Double.infinity
    for k in 0..<360 {
        let a = Double(k) / 180 * Double.pi
        for side in [-1.0, 0, 1] {
            let r = p.ride.ringRadius.double + side * p.ride.railHalf.double
            for onHim in [Fixed.zero, Fixed.one] {
                let turret = TurretCamera(x: Fixed(c.x + r * sin(a)), z: Fixed(c.z + r * cos(a)), parameters: p, onHim: onHim)
                let eye = SceneMapping.scene(turret.eye)
                func across(_ v: SIMD3<Float>) -> (angle: Double, distance: Double) {
                    let m = SIMD2<Double>(Double(middle.x - eye.x), Double(middle.z - eye.z))
                    let w = SIMD2<Double>(Double(v.x - eye.x), Double(v.z - eye.z))
                    return (atan2(m.x * w.y - m.y * w.x, m.x * w.x + m.y * w.y), (w * w).sum().squareRoot())
                }
                let angles = screen.map { across($0).angle }
                let low = try #require(angles.min()), high = try #require(angles.max())
                for ball in trees.flatMap(\.crown) {
                    let b = across(ball.centre)
                    let half = asin(Double(ball.radius) / b.distance)
                    least = min(least, max(b.angle - half - high, low - b.angle - half))
                }
            }
        }
    }
    #expect(least > Double.pi / 180, "a degree clear of the Jumbotron's screen: \(least * 180 / Double.pi) degrees")
}

@Test
@MainActor
func theCoresPictureOnAViewOfAnotherSize() {
    let picture = PictureParameters.phone
    let same = RideRig.PictureMap(picture: picture, viewSize: SIMD2(390, 844))
    #expect(same.view(x: Fixed(100.0), y: Fixed(200.0)) == CGPoint(x: 100, y: 200))
    let big = RideRig.PictureMap(picture: picture, viewSize: SIMD2(1000, 1688))
    let q = big.view(x: Fixed(195.0), y: Fixed(422.0))
    #expect(abs(q.x - 500) < 0.001 && abs(q.y - 844) < 0.001 && big.length(Fixed(44.0)) == 88)
    let back = big.picture(CGPoint(x: 600, y: 1000))
    #expect(abs(back.x.double - 245) < 0.001 && abs(back.y.double - 500) < 0.001)
    let s = session()
    let fan = s.game.figures[86]
    if let core = s.game.camera.point(fan.head), let v = s.camera.project(SceneMapping.scene(fan.head), viewSize: SIMD2(1000, 1688)) {
        let mapped = big.view(x: core.x, y: core.y)
        #expect(abs(Double(v.x) - Double(mapped.x)) < 2 && abs(Double(v.y) - Double(mapped.y)) < 2)
    }
}

@Test
@MainActor
func theViewZoomsOutAsTheCoreDoesAndSoDoesThePicture() throws {
    let s = session()
    var hand = StadiumScript.Hand(.ride)
    let size = SIMD2<Float>(390, 844)
    var widest = Fixed.one
    play(s, &hand) { t in
        widest = max(widest, t.snapshot.ride.zoom)
        return has(t) { if case .fired = $0 { true } else { false } }
    }
    let r = s.snapshot.ride
    #expect(widest > Fixed(1.3) && r.zoom > Fixed(1.3), "zoomed out by the lift")
    let cam = s.camera
    let tanHalf = tan(Double(cam.fieldOfViewDegrees) * Double.pi / 360)
    #expect(abs(tanHalf - s.parameters.ride.view.tanHalfV.double * r.zoom.double) < 1e-4)
    let core = TurretCamera(car: s.snapshot.car, parameters: s.parameters, zoom: r.zoom)
    for fan in [85, 90, 20] {
        if let q = core.point(s.game.figures[fan].head), let v = cam.project(SceneMapping.scene(s.game.figures[fan].head), viewSize: size) {
            #expect(abs(Double(v.x) - q.x.double) < 1 && abs(Double(v.y) - q.y.double) < 1, "fan \(fan) at the zoom")
        }
    }
    ticks(s, 90)
    #expect(s.snapshot.ride.zoom == .one && abs(Double(s.camera.fieldOfViewDegrees) - 60) < 0.01)
}

@Test
@MainActor
func theReticleBubblesFilmPulsesQuickerAndStopsWhenLocked() throws {
    #expect(RideRig.filmRate(aim: 0) == 2 && RideRig.filmRate(aim: 1) == 8 && RideRig.filmRate(aim: 0.5) == 5)
    #expect(RideRig.filmGlow(phase: 0) == 1 && abs(RideRig.filmGlow(phase: 0.5)) < 1e-12)
    let s = session()
    var hand = StadiumScript.Hand(.ride)
    #expect(s.filmPhase == 0)
    play(s, &hand) { $0.tick == 300 }
    #expect(s.filmPhase == 0, "no doll yet: a held bubble's film does not pulse")
    play(s, &hand) { has($0) { if case .grabbed = $0 { true } else { false } } && RideRig.live($0.snapshot) != nil }
    var last = s.filmPhase
    var steps: [Double] = []
    play(s, &hand) { t in
        steps.append(t.filmPhase - last)
        last = t.filmPhase
        return t.snapshot.ride.incident?.isLocked == true
    }
    #expect(steps.dropLast().allSatisfy { $0 >= 2.0 / 60 - 1e-9 && $0 <= 8.0 / 60 + 1e-9 } && steps.dropLast().last! > steps.first! && steps.last == 0)
    let locked = s.filmPhase
    ticks(s, 30)
    #expect(s.filmPhase == locked, "still while locked")
    let marks = RideRig.bubbles(s.snapshot, parameters: s.parameters, map: s.map)
    let reticle = try #require(marks.first { $0.aim != nil })
    #expect(reticle.locked && reticle.aim == 1 && reticle.held)
    let inc = try #require(s.snapshot.ride.incident)
    let head = try #require(s.game.camera.point(s.game.figures[inc.figure].head))
    let onView = s.map.view(x: head.x, y: head.y)
    #expect(abs(onView.x - reticle.centre.x) < 0.001 && abs(onView.y - reticle.centre.y) < 0.001)
}

@MainActor
private func body(_ f: Figure) -> [SIMD3<Float>] {
    let c = KartParameters.fieldCentre
    let fwd = simd_normalize(SIMD3<Float>(Float(c.x.double - f.x.double), 0, -Float(c.z.double - f.z.double)))
    let up = SIMD3<Float>(0, 1, 0), side = simd_cross(fwd, up)
    let head = SceneMapping.scene(f.head), torso = SceneMapping.scene(f.torso)
    var out = [head] + [fwd, -fwd, up, -up, side, -side].map { head + $0 * 0.25 }
    for a in [-1, 1] as [Float] {
        for b in [-1, 1] as [Float] {
            for d in [-1, 1] as [Float] { out.append(torso + side * (0.25 * a) + up * (0.45 * b) + fwd * (0.175 * d)) }
        }
    }
    return out
}

@Test
@MainActor
func theCrewsShotHoldsTheDollsFanAloneFromEverySeat() {
    let figures = StandsParameters.stadium.figures()
    let size = SIMD2<Float>(480, 270)
    var others: [String] = []
    for (i, f) in figures.enumerated() {
        for focus in stride(from: 0.0, through: 1.0, by: 0.125) {
            let cam = Cameras.crew(on: f, focus: focus)
            let middle = cam.project(SceneMapping.scene(f.head), viewSize: size)
            if middle.map({ abs($0.x - 240) > 0.01 || abs($0.y - 135) > 0.01 }) ?? true { others.append("fan \(i) not in the middle") }
            for (j, g) in figures.enumerated() where j != i {
                let inside = body(g).contains { p in cam.project(p, viewSize: size).map { $0.x >= 0 && $0.x <= 480 && $0.y >= 0 && $0.y <= 270 } ?? false }
                if inside { others.append("fan \(j) in fan \(i)'s shot at \(focus)") }
            }
        }
    }
    #expect(others.isEmpty, "\(others.prefix(5))")
    let f = figures[85], close = Cameras.crew(on: f, focus: 1)
    let risen = close.project(SceneMapping.scene(f.head) + SIMD3(0, 0.25, 0), viewSize: size)
    #expect(risen.map { $0.y > 10 } == true)
}

@Test
@MainActor
func theJumbotronDrawsTheFansThoughtFromTheFirstReelTick() throws {
    let s = session()
    func shot() -> RideRig.CrewShot? {
        RideRig.crewShot(s.snapshot, figures: s.game.figures, seats: s.parameters.stands.seats,
                         garden: { s.game.isInGarden($0) }, flight: s.lastFlight)
    }
    #expect(shot() == nil)
    while RideRig.live(s.snapshot) == nil && s.tick < 3000 { s.advance() }
    let inc = try #require(RideRig.live(s.snapshot))
    let first = try #require(shot())
    #expect(!first.parts(.torso).isEmpty && first.parts(.torso).allSatisfy { $0.paint == Look.shirt(inc.figure) })
    let head = try #require(first.parts(.head).first)
    #expect(abs(head.points[0].x - 240) < 0.5 && head.points[0].y > 135)
    #expect(!first.parts(.thoughtBubble).isEmpty && !first.parts(.thoughtSymbol).isEmpty)
    let firstSymbols = first.parts(.thoughtSymbol).map(\.points)
    ticks(s, 3)
    let shifted = try #require(shot())
    #expect(shifted.parts(.thoughtSymbol).map(\.points) != firstSymbols)

    // Both samples are after camera focus settles, isolating the reel's motion.
    ticks(s, inc.beep + 100 - s.tick)
    let early = try #require(shot())
    ticks(s, inc.start - 1 - s.tick)
    let beforeReveal = try #require(shot())
    #expect(early.parts(.head) == beforeReveal.parts(.head))
    #expect(early.parts(.torso) == beforeReveal.parts(.torso))
    ticks(s, 1)
    let revealed = try #require(shot())
    #expect(revealed.parts(.head) == beforeReveal.parts(.head))
    let frame = try #require(inc.thought(at: s.tick))
    #expect(!frame.isSpinning && frame.symbol == inc.symbol)
    #expect(revealed.parts(.thoughtSymbol).count == ThoughtArtwork.shapes(for: ThoughtArtwork.Key(frame)).filter { $0.layer == .symbol }.count)

    let c = session()
    var hand = StadiumScript.Hand(.right)
    play(c, &hand) { $0.snapshot.ride.lastResult != nil }
    let result = try #require(c.snapshot.ride.lastResult)
    #expect(result.result == .served)
    ticks(c, 19)
    let caught = try #require(RideRig.crewShot(c.snapshot, figures: c.game.figures, seats: c.parameters.stands.seats,
                                               garden: { c.game.isInGarden($0) }, flight: c.lastFlight))
    #expect(caught.parts(.hand).count == 1 && caught.parts(.doll).isEmpty && caught.parts(.dollHead).isEmpty)
    #expect(caught.parts(.hotDog).count == 1 && !caught.parts(.thoughtSymbol).isEmpty)
}

@Test
func fanBodiesStayStillWhileThoughtsSpinAndSettle() throws {
    let fan = StandsParameters.stadium.figures()[85]
    let rest = RideRig.pose(fan, state: .seated)
    let thoughtStates: [CrowdState] = [.thinking, .wantingHotDog, .watching]
    for state in thoughtStates {
        #expect(RideRig.pose(fan, state: state) == rest)
    }
    let caught = RideRig.pose(fan, state: .catching)
    #expect(caught.head == rest.head && caught.torso == rest.torso && caught.hand != nil)
    for symbol in ThoughtSymbol.allCases {
        let inc = Incident(beep: 100, figure: 85, garden: true, symbol: symbol, start: 400, end: 460)
        #expect(inc.thought(at: 99) == nil)
        #expect(inc.thought(at: 399)?.isSpinning == true)
        let final = try #require(inc.thought(at: 400))
        #expect(final.symbol == symbol && !final.isSpinning)
        #expect(inc.thought(at: 450) == final)
    }
}

@Test
func thoughtSymbolsStayInsideTheirSlotDuringEveryTransition() throws {
    var keys: Set<ThoughtArtwork.Key> = []
    for symbol in ThoughtSymbol.allCases {
        let thought = FanThought(figure: 0, start: 300, end: 390, spinTicks: 300, symbol: symbol)
        for tick in 0...300 {
            let frame = try #require(thought.frame(at: tick))
            let key = ThoughtArtwork.Key(frame)
            keys.insert(key)
            let shapes = ThoughtArtwork.shapes(for: key)
            #expect(shapes.contains { $0.layer == .bubble })
            for shape in shapes where shape.layer == .symbol {
                #expect(shape.points.count >= 3)
                #expect(shape.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 0.40001 && abs($0.y) <= 0.24001 })
            }
        }
    }
    #expect(keys.count <= 4 * 4 * 12, "the scene mesh cache is bounded independently of run length")
}

@Test
@MainActor
func thoughtBubblesFitTheCrewPictureAtEverySeatAndFocus() throws {
    let s = session()
    let figures = s.game.figures
    var snapshot = s.snapshot
    for (i, _) in figures.enumerated() {
        snapshot.ride.incident = Incident(beep: 0, figure: i, garden: s.game.isInGarden(i), symbol: .hotDog, start: 300, end: 360)
        for tick in [0, 30, 60, 90, 299, 300] {
            snapshot.tick = tick
            let shot = try #require(RideRig.crewShot(snapshot, figures: figures, seats: s.parameters.stands.seats,
                                                    garden: { s.game.isInGarden($0) }, flight: nil))
            let points = shot.parts(.thoughtBubble).flatMap(\.points)
            #expect(!points.isEmpty)
            #expect(points.allSatisfy { $0.x > 2 && $0.x < 478 && $0.y > 2 && $0.y < 268 }, "fan \(i), tick \(tick)")
        }
    }
}

@Test
@MainActor
func theJumbotronHoldsTheRevealedThoughtAndDeliveryResult() throws {
    func thought(symbol: ThoughtSymbol, shot: Int, result: ShotResult?) -> Incident {
        var inc = Incident(beep: 100, figure: 0, garden: false, symbol: symbol, start: 400, end: 460)
        inc.shot = shot
        inc.ended = shot
        inc.result = result
        return inc
    }
    #expect(RideRig.crewEnd(thought(symbol: .hotDog, shot: 420, result: .served)) == 480)
    #expect(RideRig.crewEnd(thought(symbol: .music, shot: 420, result: .unwanted)) == 480)
    #expect(RideRig.crewEnd(thought(symbol: .hotDog, shot: 250, result: .tooSoon)) == 310)
    #expect(RideRig.crewEnd(thought(symbol: .hotDog, shot: -1, result: .missedRequest)) == 490)
    #expect(RideRig.crewEnd(thought(symbol: .star, shot: -1, result: .heldFire)) == 490)

    let s = session()
    var hand = StadiumScript.Hand(.right)
    play(s, &hand) { $0.snapshot.ride.lastResult != nil }
    let inc = try #require(s.snapshot.ride.incident)
    let result = try #require(s.snapshot.ride.lastResult)
    #expect(result.result == .served && s.tick == inc.start + 20 && RideRig.caughtTick(inc) == s.tick)
    #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: result))
    #expect(RideRig.resultOnJumbotron(s.snapshot, parameters: s.parameters) == result && RideRig.ResultMark(result.result) == .check)
    #expect(inc.thought(at: s.tick)?.symbol == .hotDog)
    ticks(s, RideRig.catchShown - 1)
    #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: result))
    ticks(s, 1)
    #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .result(result))
    ticks(s, s.parameters.ride.alarm.resultShown - RideRig.catchShown - 1)
    #expect(RideRig.resultOnJumbotron(s.snapshot, parameters: s.parameters) == result)
    ticks(s, 1)
    #expect(RideRig.resultOnJumbotron(s.snapshot, parameters: s.parameters) == nil)

    let h = session()
    var p = StadiumParameters.stadium
    p.seed = 20261102
    h.reset(to: p)
    h.stop()
    var held = StadiumScript.Hand(.right)
    play(h, &held) { $0.snapshot.ride.lastResult != nil }
    let other = try #require(h.snapshot.ride.incident)
    let heldResult = try #require(h.snapshot.ride.lastResult)
    #expect(other.symbol != .hotDog && heldResult.result == .heldFire && h.tick == other.end)
    #expect(RideRig.jumbotron(h.snapshot, parameters: h.parameters) == .crew(result: heldResult))
    #expect(other.thought(at: h.tick)?.isSpinning == false)
    ticks(h, other.crewEnd - 1 - h.tick)
    #expect(RideRig.jumbotron(h.snapshot, parameters: h.parameters) == .crew(result: heldResult))
    ticks(h, 1)
    #expect(RideRig.jumbotron(h.snapshot, parameters: h.parameters) == .result(heldResult))
}

@Test
@MainActor
func theJumbotronKeepsTheCanonicalObservationUntilAnotherFrameArrives() {
    let s = session()
    let observed = WhaleyObservation(ready: true, number: 2, gameTime: 4,
                                    x: Fixed(100), y: Fixed(200), width: Fixed(32), height: Fixed(32),
                                    layer: LevelSpot(Fixed(-40), Fixed(-140)))
    let frame = JumbotronFrame(sessionID: s.whaleySessionID, sequence: 1, observation: observed)
    s.receiveWhaley(frame)
    s.receiveWhaley(frame)
    s.advance()
    #expect(s.game.whaley == observed)
    #expect(s.recording.inputs.last?.whaleyFrames == [frame])
    ticks(s, 20)
    #expect(s.game.whaley == observed, "Stadium does not run a second Whaley simulation")
    let recorded = s.recording.replay()
    #expect(recorded.last?.ride.whaley.observation == observed)
}

@Test
@MainActor
func aResetRejectsLateFramesFromThePreviousNativeSession() {
    let s = session()
    let oldID = s.whaleySessionID
    s.reset(to: .stadium)
    #expect(s.whaleySessionID != oldID)
    s.receiveWhaley(JumbotronFrame(sessionID: oldID, sequence: 99, observation: WhaleyObservation(ready: true, number: 6)))
    s.advance()
    #expect(!s.game.whaley.ready && s.game.whaley.number == 1)
    #expect(s.recording.inputs.last?.whaleyFrames.isEmpty == true)
}

@Test
@MainActor
func theBarsMenuSetsTheDebugLevelAndTheStaticMode() throws {
    let s = session()
    ticks(s, 1)
    #expect(RepeatState.allCases.map(RideRig.debugTitle) == ["Normal", "Hot dog cannon", "Whaley 2D", "Balk", "Interlude"])
    #expect(RideRig.menuTally(s.snapshot, parameters: s.parameters).map(\.text) == ["Points 0", "Called right 0", "Called wrong 0"])
    s.setRepeat(.whaley)
    s.setParked(true)
    #expect(s.repeatState == .whaley && s.parked, "as picked, before the tick")
    ticks(s, 1)
    let r = s.snapshot.ride.repeat
    #expect(s.tick == 2 && r.state == .whaley && r.parked && r.parkedAt == s.parameters.ride.repeat.spots.whaley)
    #expect(s.recording.inputs.last == StadiumInput(finger: .none, repeat: .whaley, parked: true))
    let at = s.snapshot.car
    ticks(s, 120)
    #expect(s.snapshot.car == at && s.snapshot.ride.whaley.shown, "held where the Jumbotron's game is on")
    #expect(s.menuTally == RideRig.menuTally(s.snapshot, parameters: s.parameters) && s.repeatState == .whaley && s.parked)
    let redrawn = Flag()
    withObservationTracking { _ = (s.menuTally, s.repeatState, s.parked) } onChange: { redrawn.on = true }
    ticks(s, 1)
    #expect(!redrawn.on, "the menu left alone by a tick that changes nothing in it")
    s.setRepeat(.pitcher)
    ticks(s, 60)
    #expect(s.snapshot.ride.repeat.parkedAt == s.parameters.ride.repeat.spots.pitcher && s.snapshot.ride.pitcher.inView)
    s.setParked(false)
    ticks(s, 60)
    #expect(!s.snapshot.ride.repeat.isHeld && s.snapshot.car.speed > Fixed(2.9))
    s.setRepeat(.off)
    ticks(s, 1)
    #expect(s.tick == 244 && s.repeatState == .off && !s.parked && !s.snapshot.ride.repeat.isHeld)
    let d = session()
    while RideRig.live(d.snapshot) == nil && d.tick < 3000 { d.advance() }
    #expect(d.tick == 636 && RideRig.menuTally(d.snapshot, parameters: d.parameters).first?.text == "A fan is choosing")
    #expect(d.menuTally.first?.text == "A fan is choosing", "the session's lines with it")
}

private final class Flag: @unchecked Sendable {
    var on = false
}

@Test
@MainActor
func theFanKeepsTheJumbotronWhileBaseballAndTheDrivingViewContinue() throws {
    let s = session()
    ticks(s, 3100)
    #expect(RideRig.bullpenCartOpacity(s.snapshot) == 1 && !s.snapshot.ride.pitcher.inView, "the Bullpen Cart as it is with him off the picture")
    #expect(s.camera == Cameras.turret(s.snapshot.car, parameters: s.parameters) && s.snapshot.ride.zoom == .one, "the cannon's view with him off")
    var hand = StadiumScript.PitcherHand(.plate)
    var dollFirst: [Int] = [], gameFirst: [Int] = []
    playPitcher(s, &hand) { s in
        if RideRig.crewDoll(s.snapshot) != nil {
            switch RideRig.jumbotron(s.snapshot, parameters: s.parameters) {
            case .crew(result: nil): dollFirst.append(s.tick)
            case .whaley: gameFirst.append(s.tick)
            default: break
            }
        }
        return has(s) { if case .captured = $0 { true } else { false } }
    }
    #expect(s.tick == 3249 && RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: nil))
    #expect(dollFirst.first == 3137 && dollFirst.last == 3249 && dollFirst.count == 113 && gameFirst.isEmpty)
    #expect(s.snapshot.ride.pitcher.inView && abs(RideRig.bullpenCartOpacity(s.snapshot) - RideRig.bullpenCartDimmed) < 1e-9, "the Bullpen Cart dimmed with him on the picture")
    let cannon = Cameras.turret(s.snapshot.car, parameters: s.parameters)
    #expect(s.snapshot.ride.zoom < Fixed(0.85))
    // Perspective zoom scales tan(fieldOfView / 2), not the angle itself.
    let viewScale = tan(Double(s.camera.fieldOfViewDegrees) * .pi / 360) / tan(Double(cannon.fieldOfViewDegrees) * .pi / 360)
    #expect(abs(viewScale - s.snapshot.ride.zoom.double) < 1e-6)
    let kart = Cameras.muzzle(s.snapshot.car, parameters: s.parameters)
    #expect(simd_length(s.camera.position - kart) < simd_length(cannon.position - kart) * 0.5, "the eye over the gunner's shoulder")
    #expect(abs(simd_dot(s.camera.forward, cannon.forward) - 1) < 0.01, "pointed about as the cannon turret is")
    #expect(has(s) { if case .crew(let subject) = $0 { subject == .ball } else { false } })
    let capture = RideRig.ballShot(s.snapshot, figures: s.game.figures, parameters: s.parameters)
    let ball = try #require(capture.parts(.ball).first)
    #expect(abs(ball.points[0].x - 240) < 0.5 && abs(ball.points[0].y - 135) < 0.5 && ball.radius > 4 && ball.paint == Look.white)
    #expect(capture.parts(.glow).count == 1 && capture.backdrop == Look.dirt)
    let onPicture = { (piece: RideRig.CrewShot.Piece) in piece.points.contains { $0.x >= 0 && $0.x <= 480 && $0.y >= 0 && $0.y <= 270 } }
    #expect(capture.parts(.player).contains { $0.paint == Look.teal && onPicture($0) }, "the pitcher in the picture")
    #expect(capture.parts(.playerHead).contains { onPicture($0) })
    #expect(s.crewLive?.target == SceneMapping.scene(s.snapshot.ride.pitcher.ball.pos) && s.crewLive?.position == Cameras.pressBox)
    var thrownAt: [Int] = []
    playPitcher(s, &hand, most: 200) { s in
        if has(s, { if case .thrown(let how, _, _) = $0 { how == .thrown } else { false } }) { thrownAt.append(s.tick) }
        #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: nil), "the fan keeps the screen at \(s.tick)")
        #expect(s.crewLive?.target == SceneMapping.scene(s.snapshot.ride.pitcher.ball.pos), "the press box camera on the ball at \(s.tick)")
        #expect(s.snapshot.ride.zoom < .one && s.snapshot.ride.pitcher.fade == .one, "the view in with him on the picture at \(s.tick)")
        return s.snapshot.ride.pitcher.ball.state == .settled
    }
    #expect(thrownAt == [3265], "the scripted flick releases the captured ball")
    #expect(s.tick == 3324 && s.snapshot.ride.pitcher.ball.state == .settled)
    // The elevated ball meets the batter before reaching the crouched catcher.
    let batterIndex = try #require(Fielder.all.firstIndex { $0.name == "batter" })
    #expect(has(s) { if case .fielded(.atPlate, let by, nil, .illegalPitch) = $0 { by == batterIndex } else { false } })
    let plate = RideRig.ballShot(s.snapshot, figures: s.game.figures, parameters: s.parameters)
    #expect(plate.parts(.player).contains { $0.paint == Look.white && onPicture($0) })
    let catcher = plate.parts(.player).filter { $0.paint == Look.red }
    #expect(!catcher.isEmpty && catcher.allSatisfy { $0.points.allSatisfy { $0.y > RideRig.crewSize.y } })
    let plateBall = try #require(plate.parts(.ball).first)
    #expect(abs(plateBall.points[0].x - 240) < 0.5 && abs(plateBall.points[0].y - 135) < 0.5)
    #expect(plate.backdrop == Look.dirt && plate.parts(.ball).count == 1)
    ticks(s, 15)
    #expect(s.tick == 3339 && RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: nil))
    #expect(has(s) { if case .crew(let subject) = $0 { subject == .pitcher } else { false } })
    let him = RideRig.pitcherShot(s.snapshot, parameters: s.parameters)
    let head = try #require(him.parts(.playerHead).first { onPicture($0) })
    #expect(abs(head.points[0].x - 240) < 2 && head.points[0].y < 135 && head.points[0].y > 0)
    #expect(him.parts(.legs).contains { $0.points.allSatisfy { $0.y > 135 } } && him.backdrop == Look.dirt)
    let status = try #require(s.snapshot.ride.lastThrow)
    #expect(status.outcome == .illegalPitch && status.points == 100)
    #expect(s.crewLive?.target == SceneMapping.scene(s.parameters.ride.pitcher.point(s.parameters.ride.pitcher.middle)))
    #expect(s.snapshot.ride.lastThrowTick == 3339 && RideRig.balkName(s.snapshot, parameters: s.parameters) == nil)
    ticks(s, 3437 - s.tick)
    let revealed = try #require(s.snapshot.ride.incident)
    #expect(revealed.start == 3437 && revealed.end == 3497)
    #expect(revealed.thought(at: s.tick)?.isSpinning == false && revealed.thought(at: s.tick)?.symbol == .hotDog)
    #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: nil))
    #expect(RideRig.balkName(s.snapshot, parameters: s.parameters) == nil && !s.snapshot.ride.whaley.shown)
    ticks(s, revealed.end - s.tick)
    let unanswered = try #require(s.snapshot.ride.lastResult)
    #expect(unanswered.result == .missedRequest && RideRig.ResultMark(unanswered.result) == .cross)
    #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: unanswered))
    #expect(RideRig.balkName(s.snapshot, parameters: s.parameters) == nil)
    ticks(s, revealed.crewEnd - 1 - s.tick)
    #expect(s.tick == 3526 && RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: unanswered))
    #expect(RideRig.balkName(s.snapshot, parameters: s.parameters) == nil)
    ticks(s, 1)
    #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .pitcher)
    #expect(RideRig.balkName(s.snapshot, parameters: s.parameters) == "ILLEGAL PITCH", "the still-current call returns after the fan hold")
    ticks(s, 3339 + s.parameters.ride.alarm.resultShown - 1 - s.tick)
    #expect(s.tick == 3578 && RideRig.balkName(s.snapshot, parameters: s.parameters) == "ILLEGAL PITCH")
    ticks(s, 1)
    #expect(RideRig.balkName(s.snapshot, parameters: s.parameters) == nil)
    ticks(s, 3608 - s.tick)
    #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .pitcher)
    ticks(s, 1)
    #expect(s.tick == 3609 && s.snapshot.ride.pitcher.crew == .free && s.crewLive == nil)
    #expect(!s.snapshot.ride.pitcher.inView && RideRig.bullpenCartOpacity(s.snapshot) == 1)
    #expect(s.camera == Cameras.turret(s.snapshot.car, parameters: s.parameters) && s.snapshot.ride.zoom == .one)
    #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .whaley(result: unanswered))
    let w = session()
    var wild = StadiumScript.PitcherHand(.wild)
    playPitcher(w, &wild) { has($0) { if case .fielded = $0 { true } else { false } } }
    let settled = RideRig.ballShot(w.snapshot, figures: w.game.figures, parameters: w.parameters)
    #expect(settled.parts(.ball).count == 1 && RideRig.jumbotron(w.snapshot, parameters: w.parameters) == .ball)
    if RideRig.standsRow(w.snapshot.ride.pitcher.ball.pos, parameters: w.parameters) != nil {
        #expect(!settled.parts(.torso).isEmpty && settled.backdrop != Look.field && settled.backdrop != Look.dirt)
    } else {
        #expect(settled.backdrop == Look.field, "in center field, the grass behind it")
    }
}

@Test
@MainActor
func fanPriorityDoesNotReshowExpiredBalksOrInventPickoffHeadlines() throws {
    let d = session()
    var drop = StadiumScript.PitcherHand(.drop)
    playPitcher(d, &drop) { $0.snapshot.ride.lastThrow != nil }
    let dropped = try #require(d.snapshot.ride.lastThrow)
    #expect(dropped.outcome == .dropped && dropped.points == 50 && d.snapshot.ride.lastThrowTick == d.tick)
    #expect(RideRig.jumbotron(d.snapshot, parameters: d.parameters).isCrew)
    #expect(RideRig.balkName(d.snapshot, parameters: d.parameters) == nil, "a balk cannot cover the fan reel")
    let fan = try #require(d.snapshot.ride.incident)
    ticks(d, fan.crewEnd - d.tick)
    #expect(!RideRig.jumbotron(d.snapshot, parameters: d.parameters).isCrew)
    #expect(d.tick >= d.snapshot.ride.lastThrowTick + d.parameters.ride.alarm.resultShown)
    #expect(RideRig.balkName(d.snapshot, parameters: d.parameters) == nil, "an expired call does not return after the fan")
    let p = session()
    var pickoff = StadiumScript.PitcherHand(.pickoff)
    playPitcher(p, &pickoff) { $0.snapshot.ride.lastThrow != nil }
    let picked = try #require(p.snapshot.ride.lastThrow)
    #expect(picked.outcome == .pickoff && picked.points == 0 && p.snapshot.ride.lastThrowTick == p.tick)
    #expect(RideRig.balkName(p.snapshot, parameters: p.parameters) == nil)
}

@Test
@MainActor
func aDollsResultIsMarkedACheckForEveryRightCallAndAnXForTheRest() {
    for result in ShotResult.allCases {
        let want: RideRig.ResultMark = result.success ? .check : .cross
        #expect(RideRig.ResultMark(result) == want, "\(result)")
    }
    #expect([ShotResult.served, .heldFire].allSatisfy { RideRig.ResultMark($0) == .check })
    #expect([ShotResult.tooSoon, .unwanted, .wrongItem, .wrongFan, .miss, .missedRequest].allSatisfy { RideRig.ResultMark($0) == .cross })
    #expect(RideRig.ResultMark.check.symbol == "checkmark" && RideRig.ResultMark.cross.symbol == "xmark")
}

@Test
@MainActor
func voiceOversBouncesAndItsShotsAtTheDollsFan() throws {
    for left in [true, false] {
        let a = session()
        ticks(a, 30)
        a.accessibleBounce(left: left)
        #expect(!a.acceptsStroke && !a.fingerBegan(at: CGPoint(x: 10, y: 10)), "no finger while a stroke runs")
        var hops: [Wheel] = []
        for _ in 0..<24 {
            a.advance()
            for e in a.snapshot.ride.events { if case .hop(let wheel, _, _) = e { hops.append(wheel) } }
        }
        #expect(hops.first == (left ? .rearLeft : .rearRight) && a.acceptsStroke, "the \(left ? "left" : "right") rear wheel")
    }
    let d = session()
    d.accessibleShot()
    #expect(d.acceptsStroke, "no doll, no shot")
    while RideRig.live(d.snapshot) == nil && d.tick < 3000 { d.advance() }
    let inc = try #require(RideRig.live(d.snapshot))
    d.accessibleShot()
    #expect(d.acceptsStroke, "the spinning reel does not start an assisted shot")
    ticks(d, inc.start - d.tick)
    d.accessibleShot()
    #expect(!d.acceptsStroke)
    while !has(d, { if case .result = $0 { true } else { false } }) && d.tick <= inc.end { d.advance() }
    let result = try #require(d.snapshot.ride.lastResult)
    #expect(result.figure == inc.figure && result.item == .hotDog && result.shot >= 0)
    #expect(result.result == ShotResult.judge(hit: inc.figure, figure: inc.figure, symbol: inc.symbol, item: .hotDog, revealed: result.shot >= inc.start))
    #expect(d.acceptsStroke && d.lastFlight?.tick == result.shot && d.lastFlight?.item == .hotDog)
}

@Test
@MainActor
func assistedFanShotsProceedWhileTheBalkFeedWaits() throws {
    let s = session()
    var hand = StadiumScript.PitcherHand(.plate)
    playPitcher(s, &hand) { $0.snapshot.ride.lastThrow != nil }
    let request = try #require(s.snapshot.ride.incident)
    ticks(s, request.start - s.tick)
    #expect(s.snapshot.ride.pitcher.crew == .pitcher && request.symbol == .hotDog)
    #expect(RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: nil))
    s.accessibleShot()
    #expect(!s.acceptsStroke)
    while s.snapshot.ride.incident?.isLive == true && s.tick <= request.end { s.advance() }
    let result = try #require(s.snapshot.ride.lastResult)
    #expect(result.beep == request.beep && result.shot >= request.start && result.shot < request.end,
            "the queued shot must run during the visible fan window despite the active balk")
    #expect(s.lastFlight?.tick == result.shot && s.lastFlight?.item == .hotDog)
    #expect(s.acceptsStroke && s.snapshot.ride.pitcher.crew == .pitcher)
}

@Test
@MainActor
func theCrewsPictureAndTheResultsWhile() throws {
    let s = session()
    while RideRig.live(s.snapshot) == nil && s.tick < 3000 { s.advance() }
    let inc = try #require(RideRig.live(s.snapshot))
    let fan = s.game.figures[inc.figure]
    let c = KartParameters.fieldCentre
    let toCentre = ((c.x.double - fan.x.double), (c.z.double - fan.z.double))
    func away(_ cam: PinholeCamera) -> Double {
        let out = SceneMapping.stadium(cam.position)
        let toCrew = (out.x - fan.x.double, out.z - fan.z.double)
        #expect(toCentre.0 * toCrew.0 + toCentre.1 * toCrew.1 > 0, "toward the field")
        return (toCrew.0 * toCrew.0 + toCrew.1 * toCrew.1).squareRoot()
    }
    let wide = try #require(s.crew)
    #expect(wide.target == SceneMapping.scene(fan.head) + SIMD3(0, 0.27, 0) && abs(wide.position.y - Float(fan.headY.double + 0.2)) < 1e-4)
    #expect(abs(away(wide) - 10) < 1e-3 && wide.fieldOfViewDegrees == 16)
    ticks(s, 90)
    let close = try #require(s.crew)
    #expect(abs(away(close) - 6) < 1e-3 && close.fieldOfViewDegrees == 16, "moved in on his head and shoulders")
    while !has(s, { if case .result = $0 { true } else { false } }) && s.tick < 3000 { s.advance() }
    let captured = try #require(s.snapshot.ride.lastResult)
    #expect(s.tick == 996 && captured.result == .missedRequest && RideRig.jumbotron(s.snapshot, parameters: s.parameters) == .crew(result: captured))
    #expect(RideRig.showingResult(s.snapshot, parameters: s.parameters) && RideRig.resultOnJumbotron(s.snapshot, parameters: s.parameters) == captured)
    #expect(RideRig.ResultMark(captured.result) == .cross)
    ticks(s, s.parameters.ride.alarm.resultShown - 1)
    #expect(RideRig.resultOnJumbotron(s.snapshot, parameters: s.parameters) == captured, "the last tick of its while")
    ticks(s, 1)
    #expect(!RideRig.showingResult(s.snapshot, parameters: s.parameters) && RideRig.resultOnJumbotron(s.snapshot, parameters: s.parameters) == nil)
}

@Test
@MainActor
func theJumbotronCutsAboutTheInfieldWhileNothingElseIsOn() throws {
    #expect((0..<6).map { RideRig.infieldCut(at: $0 * RideRig.infieldCutTicks) } == [.mound, .plate, .first, .second, .third, .mound])
    #expect(RideRig.infieldCut(at: 239) == .mound && RideRig.infieldCut(at: 240) == .plate && RideRig.infieldCutTicks == 240)
    let s = session()
    let p = s.parameters
    for cut in RideRig.InfieldCut.allCases {
        let cam = Cameras.crewInfield(cut, parameters: p)
        let middle = try #require(cam.project(cut.target(parameters: p), viewSize: RideRig.crewSize))
        #expect(cam.position == Cameras.pressBox && abs(middle.x - 240) < 0.5 && abs(middle.y - 135) < 0.5, "\(cut) on its place")
    }
    #expect(Cameras.crewInfield(.mound, parameters: p) == Cameras.crewPitcher(parameters: p), "the pitcher framed as while every camera is on him")
    let onPicture = { (piece: RideRig.CrewShot.Piece) in piece.points.contains { $0.x >= 0 && $0.x <= 480 && $0.y >= 0 && $0.y <= 270 } }
    func shirts(_ shot: RideRig.CrewShot, _ paint: Paint, _ x: ClosedRange<Float> = 0...480) -> Bool {
        shot.parts(.player).contains { $0.paint == paint && onPicture($0) && x.contains($0.points.map(\.x).reduce(0, +) / 4) }
    }
    func at(_ t: Int) -> StadiumSnapshot {
        while s.snapshot.tick < t { s.advance() }
        return s.snapshot
    }
    let mound = at(100)
    let runners = mound.ride.pitcher.runners
    #expect(runners.contains(.first) && !runners.contains(.second) && runners.contains(.third))
    let pitcher = RideRig.infieldShot(mound, parameters: p)
    #expect(RideRig.infieldCut(at: mound.tick) == .mound && pitcher.backdrop == Look.dirt && shirts(pitcher, Look.teal))
    #expect(pitcher.parts(.playerHead).contains { onPicture($0) && abs(($0.points.first?.x ?? 0) - 240) < 10 }, "the pitcher in the middle")
    let plate = RideRig.infieldShot(at(300), parameters: p)
    #expect(RideRig.infieldCut(at: 300) == .plate && shirts(plate, Look.red) && shirts(plate, Look.white), "the catcher and the batter")
    let board = at(600)
    #expect(RideRig.jumbotron(board, parameters: p) == .board && RideRig.infieldCut(at: 600) == .first)
    let first = RideRig.infieldShot(board, parameters: p)
    #expect(shirts(first, Look.teal) && shirts(first, Look.white) && first.backdrop == Look.dirt, "the first baseman and the runner")
    let second = RideRig.infieldShot(at(800), parameters: p)
    #expect(RideRig.infieldCut(at: 800) == .second && shirts(second, Look.teal, 0...120) && shirts(second, Look.teal, 360...480))
    #expect(!shirts(second, Look.white), "nobody on second")
    let result = at(1100)
    if case .result = RideRig.jumbotron(result, parameters: p) {} else { Issue.record("the result's while at 1,100") }
    let third = RideRig.infieldShot(result, parameters: p)
    #expect(RideRig.infieldCut(at: 1100) == .third && shirts(third, Look.teal) && shirts(third, Look.white), "the third baseman and the runner")
}

@Test
@MainActor
func theBubblesAsTheOverlayDrawsThem() throws {
    let s = session()
    s.fingerBegan(at: CGPoint(x: 40, y: 250))
    s.fingerEnded(at: CGPoint(x: 40, y: 250))
    ticks(s, 14)
    let marks = RideRig.bubbles(s.snapshot, parameters: s.parameters, map: s.map)
    let m = try #require(marks.first)
    #expect(m.centre == CGPoint(x: 40, y: 250) && m.radius == 22 && m.tint == .purple && m.frozen && !m.held && m.aim == nil && !m.locked)
    s.viewResized(SIMD2(780, 1688))
    let big = try #require(RideRig.bubbles(s.snapshot, parameters: s.parameters, map: s.map).first)
    #expect(big.radius == 44 && abs(Double(big.centre.y) - 2 * Double(m.centre.y)) < 0.001)
    let n = s.parameters.ride.hop.ticks
    #expect(RideRig.hopLift(0, ticks: n) == 0 && RideRig.hopLift(n / 2, ticks: n) > 0.34 && RideRig.hopLift(n, ticks: n) == 0)
    #expect(RideRig.beatGlow(s.snapshot) >= 0 && RideRig.beatGlow(s.snapshot) <= 1)
}
