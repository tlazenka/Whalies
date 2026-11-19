import Foundation
import Testing
import StadiumCore
import WhaleKartCore
import CrowdCore
@testable import StadiumGame

private let p = StadiumParameters.stadium
private let rb = p.ride.bubbles

// Input is calculated from state before each tick.
@discardableResult
private func drive(_ game: inout StadiumGame, ticks n: Int, _ input: (StadiumGame) -> StadiumInput = { _ in .none }) -> [StadiumSnapshot] {
    var out: [StadiumSnapshot] = []
    for _ in 0..<n { out.append(game.step(input(game))) }
    return out
}

@discardableResult
private func drive(_ game: inout StadiumGame, hand: inout StadiumScript.Hand, until done: (StadiumSnapshot) -> Bool, most: Int = 2000)
    -> [StadiumSnapshot] {
    var out: [StadiumSnapshot] = []
    for _ in 0..<most {
        let s = game.step(hand.input(game, at: game.tick))
        out.append(s)
        if done(s) { break }
    }
    return out
}

private func events(_ s: [StadiumSnapshot]) -> [RideEvent] { s.flatMap(\.ride.events) }
private func has(_ s: StadiumSnapshot, _ match: (RideEvent) -> Bool) -> Bool { s.ride.events.contains(where: match) }
private func isBeep(_ e: RideEvent) -> Bool { if case .beep = e { true } else { false } }
private func isLocked(_ e: RideEvent) -> Bool { if case .locked = e { true } else { false } }
private func isGrabbed(_ e: RideEvent) -> Bool { if case .grabbed = e { true } else { false } }
private func isFired(_ e: RideEvent) -> Bool { if case .fired = e { true } else { false } }

private func bullpenCart(_ game: StadiumGame) -> BullpenCartOnPicture { BullpenCartOnPicture(camera: game.camera, car: game.car, bullpenCart: p.ride.bullpenCart) }

@Test
func theHitBoxIsGrayWhales() {
    let r = PictureRect(x: .zero, y: .zero, w: Fixed(10.0), h: Fixed(10.0))
    func hits(_ x: Double, _ y: Double, _ d: Double, _ ro: Int, _ wo: Int, _ ho: Int) -> Bool {
        HitBox.rectIntersectsCircle(r, x: Fixed(x), y: Fixed(y), diameter: Fixed(d), radiusOffset: ro, widthOffset: wo, heightOffset: ho)
    }
    #expect(hits(5, 5, 4, 0, 0, 0), "a circle inside")
    #expect(hits(-3, 5, 8, 0, 0, 0) && !hits(-3, 5, 8, -1, 0, 0), "the radius offset takes a point off")
    #expect(!hits(-3, 5, 8, 0, -1, 0), "the width offset takes a point off each side")
    #expect(!hits(11, 5, 4, 0, 0, 0) && hits(10.5, 5, 4, 0, 0, 0), "the far edge is a point in")
    #expect(hits(5, -1.5, 4, 0, 0, 0) && !hits(5, -1.5, 4, 0, 0, -1), "the height offset too")
}

@Test
func theTurretFacesTheJumbotronAndTheViewKeepsItTopLeft() {
    var game = StadiumGame(parameters: p)
    let w = p.picture.width, h = p.picture.height, centre = KartParameters.fieldCentre
    let front = p.stands.rows[0].radius - p.stands.torsoR
    var samples = 0
    for s in drive(&game, ticks: 3600) where s.tick % 50 == 0 {
        let cam = TurretCamera(car: s.car, parameters: p)
        #expect(s.turret == Trig.bearing(dx: p.jumbotron.x - s.car.x, dz: p.jumbotron.z - s.car.z), "the turret faces the Jumbotron")
        let j = cam.point(p.jumbotron)
        #expect(j.map { $0.x < w * Fixed(0.3) && $0.y < h * Fixed(0.25) } == true, "the Jumbotron at the top left at tick \(s.tick)")
        let kart = cam.point(Vec3(s.car.x, .zero, s.car.z))
        #expect(kart.map { ($0.x - Fixed(raw: w.raw >> 1)).magnitude < .one && Fixed(raw: h.raw >> 1) < $0.y } == true, "the kart below the middle")
        let dx = cam.eye.x - centre.x, dz = cam.eye.z - centre.z
        #expect(Fixed.sqrt(dx * dx + dz * dz) + Fixed(2.0) < front, "the eye clear of the crowd at tick \(s.tick)")
        samples += 1
    }
    #expect(samples == 72 && game.lap == 1, "a lap and more round the ring")
}

@Test
func theBullpenCartsWheelsAndPipesAreOnThePicture() throws {
    let game = StadiumGame(parameters: p)
    let cam = game.camera, h = p.ride.bullpenCart
    let on = BullpenCartOnPicture(camera: cam, car: game.car, bullpenCart: h)
    let wheels = try on.wheels.map { try #require($0) }
    let pipes = try on.pipes.map { try #require($0) }
    #expect(wheels.count == 4 && pipes.count == 2)
    for (k, wheel) in Wheel.allCases.enumerated() {
        let centre = kartPoint(game.car, right: wheel.isLeft ? -h.wheelSide : h.wheelSide,
                               forward: wheel == .rearLeft || wheel == .rearRight ? -h.wheelBack : h.wheelFront, up: h.wheelHeight)
        let q = try #require(cam.project(centre))
        #expect(wheels[k].w == wheels[k].h && wheels[k].w == (h.wheelRadius * cam.focal) / q.depth * 2, "a wheel's square")
        #expect(wheels[k].midX.raw - q.x.raw <= 1 && wheels[k].midY.raw - q.y.raw <= 1)
    }
    func d(_ a: PicturePoint, _ r: PictureRect) -> Fixed { a.distance(to: PicturePoint(x: r.midX, y: r.midY)) }
    #expect(d(pipes[0], wheels[0]) < d(pipes[0], wheels[2]) && d(pipes[1], wheels[1]) < d(pipes[1], wheels[3]))
    for (k, dx) in [-h.pipeSide, h.pipeSide].enumerated() {
        #expect(pipes[k] == cam.point(kartPoint(game.car, right: dx, forward: -h.pipeBack, up: h.pipeHeight)))
    }
}

@Test
func aTapShootsABubbleOutOfTheNearerPipe() throws {
    var game = StadiumGame(parameters: p)
    let pipes = bullpenCart(game).pipes.map { $0! }
    let finger = PicturePoint(x: Fixed(40.0), y: Fixed(250.0))
    let k = finger.distance(to: pipes[0]) < finger.distance(to: pipes[1]) ? 0 : 1
    let s = game.step(.began(finger.x, finger.y))
    #expect(s.ride.events == [.bubble(id: 1, pipe: k, x: finger.x, y: finger.y)])
    var b = try #require(game.bubbles.first)
    #expect(b.x == pipes[k].x && b.y == pipes[k].y && !b.isFrozen && b.scale == StadiumGame.interpolate(from: .zero, to: rb.smallScale, step: 1, total: 6))
    drive(&game, ticks: 5)
    b = try #require(game.bubbles.first)
    #expect(b.scale == rb.smallScale && !b.isFrozen, "swollen at the pipe")
    drive(&game, ticks: 6)
    b = try #require(game.bubbles.first)
    #expect(b.x == finger.x && b.y == finger.y && b.isFrozen, "flown to the finger, and frozen")
    var near = StadiumGame(parameters: p)
    let q = bullpenCart(near).pipes[1]!
    let t = near.step(.began(q.x + Fixed(10.0), q.y + Fixed(30.0)))
    #expect(t.ride.events.first == .bubble(id: 1, pipe: 1, x: q.x, y: q.y) && near.bubbles.first?.isFrozen == true)
}

@Test
func aFingerOnABubbleSwellsItCarriesItAndLetsItGo() throws {
    var game = StadiumGame(parameters: p)
    let y = Fixed(250.0)
    game.step(.began(Fixed(40.0), y))
    game.step(.ended(Fixed(40.0), y))
    drive(&game, ticks: 12)
    let frozen = try #require(game.bubbles.first)
    let grab = (frozen.x + Fixed(10.0), frozen.y)
    var s = game.step(.began(grab.0, grab.1))
    #expect(s.ride.events == [.grabbed(id: frozen.id)])
    drive(&game, ticks: 5)
    var b = try #require(game.heldBubble)
    #expect(b.scale == .one)
    let offset = Fixed(10.0) / rb.smallScale
    #expect(b.offsetX == offset && b.x == grab.0 - offset)
    game.step(.moved(Fixed(100.0), Fixed(300.0)))
    b = try #require(game.heldBubble)
    #expect(b.x == Fixed(100.0) - offset && b.y == Fixed(300.0))
    s = game.step(.ended(Fixed(100.0), Fixed(300.0)))
    #expect(s.ride.events == [.released(id: b.id)])
    drive(&game, ticks: 6)
    b = try #require(game.bubbles.first)
    #expect(b.scale == rb.smallScale && !b.isBeingMoved && b.x == Fixed(100.0) - offset + offset * (.one - rb.smallScale))
    game.step(.began(b.x, b.y))
    game.step(.ended(b.x, b.y))
    let rest = drive(&game, ticks: 6)
    #expect(events(rest) == [.popped(id: b.id)] && game.bubbles.isEmpty)
}

@Test
func aBubbleNewlyOnAWheelBouncesItAndTheBounceSteersTheKartAway() throws {
    let snapshots = StadiumScript.recording().replay()
    let first = snapshots[92]
    #expect(first.ride.events == [.hop(wheel: .rearRight, bubble: 1, onBeat: true)])
    #expect(snapshots[92...111].allSatisfy { $0.ride.steer == -1 && $0.car.yawRate < .zero } && snapshots[112].ride.steer == 0)
    #expect(first.ride.hops == [0, 19, 0, 0] && first.ride.bubbles.first?.usesLeft == rb.uses && first.ride.bubbles.first?.isBeingMoved == true)
    #expect(snapshots[93..<133].allSatisfy { $0.ride.events.isEmpty })
    #expect(snapshots[706].ride.events == [.hop(wheel: .rearRight, bubble: 1, onBeat: false)])
    #expect(snapshots[706].ride.bubbles.first { $0.id == 1 }?.tint == .red)
    #expect(snapshots[742].ride.events == [.popped(id: 1), .hop(wheel: .rearRight, bubble: 1, onBeat: false)])
    #expect(Wheel.rearLeft.steer == 1 && Wheel.frontLeft.steer == 1 && Wheel.rearRight.steer == -1 && Wheel.frontRight.steer == -1)
    var game = StadiumGame(parameters: p)
    var hand = StadiumScript.Hand(.ride)
    drive(&game, hand: &hand, until: { $0.tick == 60 })
    let b = try #require(game.heldBubble)
    let wheel = try #require(bullpenCart(game).wheels[1])
    let s = game.step(.moved(wheel.midX + b.offsetX, wheel.midY + b.offsetY))
    #expect(s.ride.events.first == .popped(id: b.id) && game.bubbles.isEmpty)
}

@Test
func theGuardRailsKeepTheKartOnTheTrackWithoutAJump() {
    let kp = p.kart, track = Track(parameters: kp), rail = p.ride.railHalf
    let most = (kp.yawMax * kp.dt).raw
    func turned(_ a: Fixed, _ b: Fixed) -> Int64 {
        var d = Trig.normalize(b.raw - a.raw)
        if d > Trig.turn / 2 { d -= Trig.turn }
        return d
    }
    var car = Car(parameters: kp, track: track)
    var start = car.progress, laps = 0, railed = 0
    for _ in 0..<4500 {
        let before = car.heading
        if car.step(parameters: kp, track: track, steer: .zero, railHalf: rail) { railed += 1 }
        #expect(car.offset <= rail + Fixed(raw: 64) && !car.offTrack)
        #expect(abs(turned(before, car.heading)) <= most, "never more than full steer a tick")
        if car.progress < start - Fixed(100.0) { laps += 1 }
        start = car.progress
    }
    #expect(laps == 1 && railed > 0 && car.side > .zero, "on the outer rail")
    car = Car(parameters: kp, track: track)
    for _ in 0..<1500 {
        let before = car.heading
        car.step(parameters: kp, track: track, steer: -.one, railHalf: rail)
        #expect(car.offset <= rail + Fixed(raw: 64))
        #expect(abs(turned(before, car.heading)) <= 2 * most)
    }
    #expect(car.side < .zero, "on the inner rail")
    #expect(car.speed == kp.cruiseSpeed)
}

@Test
func theDollsGoOffOnTheClockByFansOnThePicturesBand() throws {
    var otherPictures = 0, hotDogs = 0, garden = 0, others = 0
    for seed in Int64(20261101)...Int64(20261110) {
        var q = p
        q.seed = seed
        var game = StadiumGame(parameters: q)
        var rng = Rng(seed: seed)
        let due = Int(rng.between(Int64(q.ride.alarm.firstLo), Int64(q.ride.alarm.firstHi)))
        #expect(game.nextAlarm == due)
        let run = drive(&game, ticks: 1200)
        let beep = try #require(run.first { has($0, isBeep) })
        #expect(beep.tick >= due)
        let inc = try #require(beep.ride.incident)
        let a = q.ride.alarm, cam = TurretCamera(car: beep.car, parameters: q)
        let head = try #require(cam.project(game.figures[inc.figure].head))
        let top = try #require(cam.project(kartPoint(beep.car, right: .zero, forward: .zero, up: a.clearHeight)))
        #expect(head.depth <= a.maxDepth && q.picture.width * a.bandLeft <= head.x && head.x <= q.picture.width * a.bandRight)
        #expect(q.picture.height * a.bandTop <= head.y && head.y <= min(q.picture.height * a.bandBottom, top.y - a.clearMargin))
        #expect(inc.start == beep.tick + a.lead && inc.garden == q.ride.garden.contains(figure: inc.figure, seatsARow: q.stands.seats))
        if !inc.symbol.requiresHotDog { otherPictures += 1 } else { hotDogs += 1 }
        if inc.garden { garden += 1 } else { others += 1 }
        #expect(run[beep.tick].ride.lit && !run[beep.tick + a.flashTicks].ride.lit && run[beep.tick + 2 * a.flashTicks].ride.lit)
        let end = try #require(run.first { $0.tick > beep.tick && has($0, isResult) })
        #expect(end.tick == inc.end && inc.end == inc.start + a.leniency && end.ride.lastResult?.result == (!inc.symbol.requiresHotDog ? .heldFire : .missedRequest))
        #expect(a.gapLo <= end.ride.nextAlarm - end.tick && end.ride.nextAlarm - end.tick <= a.gapHi)
    }
    #expect(otherPictures > 0 && hotDogs > 0 && garden > 0 && others > 0, "both decisions, in the garden section and out")
}

@Test
func theReelGivesEverySymbolTheSameResponseWindow() throws {
    for (seed, otherPicture) in [(Int64(20261101), false), (Int64(20261102), true)] {
        var q = p
        q.seed = seed
        let snapshots = StadiumScript.recording(kind: .none, parameters: q).replay()
        let beep = try #require(snapshots.first { has($0, isBeep) })
        let inc = try #require(beep.ride.incident)
        let a = q.ride.alarm
        #expect(!inc.symbol.requiresHotDog == otherPicture && inc.start == beep.tick + a.lead && inc.end == inc.start + a.leniency && a.lead == 300 && a.leniency == 60)
        #expect(snapshots[beep.tick..<inc.start].allSatisfy { $0.crowd.states[inc.figure] == .thinking })
        #expect(snapshots[inc.start..<inc.end].allSatisfy { $0.crowd.states[inc.figure] == (otherPicture ? .watching : .wantingHotDog) })
        let close = try #require(snapshots.first { has($0, isResult) })
        #expect(close.tick == inc.end && close.ride.lastResult?.result == (otherPicture ? .heldFire : .missedRequest))
    }
    let v = try #require(StadiumScript.variants.first { $0.kind == .wrong })
    let q = StadiumScript.parameters(v)
    var game = StadiumGame(parameters: q)
    var hand = StadiumScript.Hand(.wrong)
    drive(&game, hand: &hand, until: { has($0, isLocked) })
    let inc = try #require(game.incident)
    #expect(inc.symbol.requiresHotDog)
    drive(&game, ticks: inc.end - 1 - game.tick)
    #expect(game.crowd.states[inc.figure] == .wantingHotDog && game.incident?.isLive == true)
    let s = game.step(.ended(game.fingerX, game.fingerY))
    #expect(s.tick == inc.end - 1 && s.ride.lastResult?.result == .served && s.crowd.states[inc.figure] == .catching)
}

@Test
func aHeldBubbleLocksOnTheFanButAnEarlyShotDoesNotWin() throws {
    let v = try #require(StadiumScript.variants.first { $0.kind == .right })
    let q = StadiumScript.parameters(v)
    var game = StadiumGame(parameters: q)
    var hand = StadiumScript.Hand(.right)
    let carried = drive(&game, hand: &hand, until: { has($0, isLocked) })
    let lock = try #require(carried.last)
    let grab = try #require(carried.firstIndex { has($0, isGrabbed) })
    let aims = carried[grab...].map { $0.ride.incident!.aim }
    #expect(aims.first == .zero && aims.last == .one && aims.dropLast().last! > Fixed(0.5))
    let inc = try #require(lock.ride.incident)
    #expect(inc.isLocked && inc.lockTick == lock.tick && inc.item == .hotDog)
    for dx in [Fixed(-90.0), Fixed(-45.0), .zero, Fixed(45.0), Fixed(90.0)] {
        let s = game.step(.moved(game.fingerX + dx, game.fingerY))
        let head = try #require(TurretCamera(car: s.car, parameters: q, zoom: s.ride.zoom).point(game.figures[inc.figure].head))
        let b = try #require(s.ride.bubbles.first { $0.id == inc.locked })
        #expect(s.ride.events.isEmpty && b.x == head.x && b.y == head.y && b.isBeingMoved && s.ride.incident?.aim == .one)
    }
    let s = game.step(.ended(game.fingerX, game.fingerY))
    #expect(s.ride.events.map { if case .fired(let item, let figure, _, _) = $0 { "\(item.name) \(figure)" } else { "\($0)" } }
            == ["hot dog \(inc.figure)", "\(RideEvent.result(.tooSoon))", "\(RideEvent.released(id: inc.locked))"])
    let after = try #require(s.ride.incident)
    #expect(after.locked == -1 && after.shot == s.tick && after.result == .tooSoon && game.heldBubble == nil)
    #expect(game.bubbles.contains { $0.id == inc.locked && !$0.isBeingMoved })
}

@Test
func theViewZoomsOutWhileLockedToKeepTheFanAndTheJumbotronInView() throws {
    let snapshots = StadiumScript.recording().replay()
    let v = StadiumParameters.stadium.ride.view, w = p.picture.width, h = p.picture.height
    let mx = w * v.zoomMarginX, my = h * v.zoomMarginY
    let first = try #require(snapshots.first { has($0, isLocked) })
    let fired = try #require(snapshots.first { has($0, isFired) })
    let fan = try #require(first.ride.incident?.figure)
    let figures = p.stands.figures()
    var widest = Fixed.one
    for s in snapshots[first.tick..<fired.tick] {
        let inc = try #require(s.ride.incident)
        #expect(inc.isLocked)
        let cam = TurretCamera(car: s.car, parameters: p, zoom: s.ride.zoom)
        let head = try #require(cam.point(figures[fan].head))
        let j = try #require(cam.point(p.jumbotron))
        // Allow for camera easing when checking the horizontal margin.
        #expect(mx - Fixed(8.0) <= head.x && head.x <= w - mx + Fixed(8.0) && my <= head.y && head.y <= h - my, "the fan at tick \(s.tick)")
        #expect(mx <= j.x && j.x <= w - mx && my <= j.y && j.y <= h - my, "the Jumbotron at tick \(s.tick)")
        #expect(s.ride.bubbles.first { $0.id == inc.locked }.map { $0.x == head.x && $0.y == head.y } == true)
        widest = max(widest, s.ride.zoom)
    }
    #expect(snapshots[first.tick].ride.zoom == .one && widest > Fixed(1.3) && widest < v.zoomMax)
    #expect(fired.ride.events.contains { if case .fired(_, let figure, _, _) = $0 { figure == fan } else { false } })
    for (a, b) in zip(snapshots, snapshots.dropFirst()) {
        #expect((b.ride.zoom - a.ride.zoom).magnitude <= (v.zoomMax - .one) * v.zoomEase)
    }
    let back = try #require(snapshots[fired.tick...].first { $0.ride.zoom == .one })
    #expect(back.tick - fired.tick < 60 && snapshots[fired.tick + 1].ride.zoom < fired.ride.zoom)
}

@Test
func onlyTheSettledHotDogPictureAcceptsAHotDog() {
    for symbol in ThoughtSymbol.allCases {
        for item in Item.allCases {
            let wanted: ShotResult = symbol.requiresHotDog ? (item == .hotDog ? .served : .wrongItem) : .unwanted
            #expect(ShotResult.judge(hit: 5, figure: 5, symbol: symbol, item: item, revealed: true) == wanted)
            #expect(ShotResult.judge(hit: 5, figure: 5, symbol: symbol, item: item, revealed: false) == .tooSoon)
        }
        #expect(ShotResult.judge(hit: 6, figure: 5, symbol: symbol, item: .hotDog, revealed: true) == .wrongFan)
        #expect(ShotResult.judge(hit: nil, figure: 5, symbol: symbol, item: .hotDog, revealed: true) == .miss)
    }
    #expect(ShotResult.allCases.filter(\.success) == [.served, .heldFire])
}

@Test
func aHotDogShotMustFallInsideTheRevealedResponseWindow() throws {
    for (offset, expected) in [(-1, ShotResult.tooSoon), (0, .served), (59, .served), (60, .missedRequest)] {
        var game = StadiumGame(parameters: p)
        var hand = StadiumScript.Hand(.wrong)
        drive(&game, hand: &hand, until: { has($0, isLocked) })
        let incident = try #require(game.incident)
        #expect(incident.symbol == .hotDog && incident.end - incident.start == 60)
        let release = incident.start + offset
        #expect(game.tick <= release)
        drive(&game, ticks: max(0, release - game.tick))
        let snapshot = game.step(.ended(game.fingerX, game.fingerY))
        #expect(snapshot.tick == release && snapshot.ride.lastResult?.result == expected)
        #expect(snapshot.ride.tally.served == (expected == .served ? 1 : 0))
        if offset == 60 {
            #expect(!has(snapshot, isFired) && snapshot.ride.lastResult?.shot == -1)
        } else {
            #expect(has(snapshot, isFired) && snapshot.ride.lastResult?.shot == release)
        }
    }
}

@Test
func aMissedRequestWhileTheFingerIsDownPopsTheBubble() throws {
    let held = try #require(StadiumScript.variants.first { $0.kind == .wrong })
    let snapshots = StadiumScript.recording(kind: .wrong, parameters: StadiumScript.parameters(held)).replay()
    let end = try #require(snapshots.first { has($0, isResult) })
    let inc = try #require(end.ride.incident)
    #expect(end.tick == inc.end && end.ride.lastResult?.result == .missedRequest && end.ride.lastResult?.shot == -1)
    #expect(end.ride.events.first.map { if case .popped = $0 { true } else { false } } == true && end.ride.bubbles.isEmpty)
    let right = try #require(StadiumScript.variants.first { $0.kind == .right })
    let q = StadiumScript.parameters(right)
    var game = StadiumGame(parameters: q)
    var hand = StadiumScript.Hand(.right)
    drive(&game, hand: &hand, until: { has($0, isGrabbed) })
    let b = try #require(game.heldBubble)
    let close = try #require(game.incident?.end)
    let rest = drive(&game, ticks: close - game.tick + 1)
    #expect(rest.last?.ride.events == [.popped(id: b.id), .result(.heldFire)] && game.bubbles.isEmpty)
}

@Test
func aTouchTakenAwayLetsGoOfTheLock() throws {
    let v = try #require(StadiumScript.variants.first { $0.kind == .right })
    let q = StadiumScript.parameters(v)
    var game = StadiumGame(parameters: q)
    var hand = StadiumScript.Hand(.right)
    drive(&game, hand: &hand, until: { has($0, isLocked) })
    let id = try #require(game.incident?.locked)
    let s = game.step(.cancelled(game.fingerX, game.fingerY))
    #expect(s.ride.events == [.released(id: id), .unlocked] && s.ride.incident?.locked == -1 && s.ride.incident?.isLive == true)
    let close = try #require(game.incident?.end)
    let rest = drive(&game, ticks: close - game.tick + 1)
    #expect(!rest.contains { has($0, isFired) } && rest.last?.ride.lastResult?.result == .heldFire)
}

@Test
func aHotDogIsCaughtAndOtherPicturesRewardHoldingFire() throws {
    let snapshots = StadiumScript.recording().replay()
    let shots = snapshots.filter { has($0, isFired) }
    #expect(shots.count == 2)
    for (shot, result) in zip(shots, [ShotResult.served, .unwanted]) {
        let fan = try #require(shot.ride.incident?.figure)
        #expect(shot.ride.lastResult?.result == result && shot.crowd.states[fan] == .catching)
    }
    let v = try #require(StadiumScript.variants.first { $0.kind == .right })
    let run = StadiumScript.recording(kind: .right, parameters: StadiumScript.parameters(v)).replay()
    let end = try #require(run.first { has($0, isResult) })
    let inc = try #require(end.ride.incident)
    #expect(!run.contains { has($0, isFired) } && !inc.symbol.requiresHotDog && end.ride.lastResult?.result == .heldFire && end.ride.lastResult?.result.success == true)
    #expect(run[inc.start].crowd.states[inc.figure] == .watching)
}

// Near-plane projection sends the ball nearly 54,000 points offscreen here.
// Squaring that distance in 16.16 overflowed Int64 before the far-distance guard.
@Test
func aBubbleHeldAsTheBallPassesBesideTheTurretDoesNotOverflow() throws {
    let p = try Fixture.load().parameters
    let at = FingerInput(phase: .began, x: Fixed(200.0), y: Fixed(600.0))
    var inputs = [StadiumInput](repeating: .none, count: 1790)
    inputs.append(StadiumInput(finger: at))
    inputs += [StadiumInput](repeating: StadiumInput(finger: FingerInput(phase: .moved, x: at.x, y: at.y)), count: 158)
    inputs.append(StadiumInput(finger: FingerInput(phase: .ended, x: at.x, y: at.y)))
    let snapshots = StadiumRecording(parameters: p, inputs: inputs).replay()
    #expect(snapshots.count == 1950)
    expectThoughtDecisions(snapshots)
    let o = PicturePoint(x: .zero, y: .zero)
    #expect(o.distance(to: PicturePoint(x: Fixed(3.0), y: Fixed(4.0))) == Fixed(5.0))
    #expect(o.distance(to: PicturePoint(x: Fixed(52351.5), y: Fixed(1131.75))) == Fixed(52351.5))
    #expect(o.distance(to: PicturePoint(x: Fixed(-40.0), y: -Fixed(60000.0))) == Fixed(60000.0))
    let far = PictureRect(x: Fixed(50000.0), y: Fixed(100.0), w: Fixed(40.0), h: Fixed(40.0))
    #expect(!HitBox.rectIntersectsCircle(far, x: Fixed(200.0), y: Fixed(120.0), diameter: Fixed(44.0), radiusOffset: -1, widthOffset: -1, heightOffset: 0))
}
