// Stadium owns its simulation; Whaley outcomes arrive as recorded native observations.
import StadiumCore
import WhaleKartCore
import CrowdCore

/// Optional toggles change state only on the tick they are present.
public struct StadiumInput: Hashable, Sendable, Codable {
    public var finger: FingerInput
    public var `repeat`: RepeatState?
    public var parked: Bool?
    public var done: Bool
    public var whaleyFrames: [JumbotronFrame]

    public init(finger: FingerInput = .none, repeat: RepeatState? = nil, parked: Bool? = nil, done: Bool = false, whaleyFrames: [JumbotronFrame] = []) {
        self.finger = finger; self.repeat = `repeat`; self.parked = parked; self.done = done; self.whaleyFrames = whaleyFrames
    }

    public static let none = StadiumInput()
    public static func began(_ x: Fixed, _ y: Fixed) -> StadiumInput { StadiumInput(finger: FingerInput(phase: .began, x: x, y: y)) }
    public static func moved(_ x: Fixed, _ y: Fixed) -> StadiumInput { StadiumInput(finger: FingerInput(phase: .moved, x: x, y: y)) }
    public static func ended(_ x: Fixed, _ y: Fixed) -> StadiumInput { StadiumInput(finger: FingerInput(phase: .ended, x: x, y: y)) }
    public static func cancelled(_ x: Fixed, _ y: Fixed) -> StadiumInput { StadiumInput(finger: FingerInput(phase: .cancelled, x: x, y: y)) }

    private enum CodingKeys: String, CodingKey { case finger, `repeat`, parked, done, whaleyFrames }

    /// Omitted fields mean no input or no change, matching the sparse replay format.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        finger = try c.decodeIfPresent(FingerInput.self, forKey: .finger) ?? .none
        `repeat` = try c.decodeIfPresent(RepeatState.self, forKey: .repeat)
        parked = try c.decodeIfPresent(Bool.self, forKey: .parked)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        whaleyFrames = try c.decodeIfPresent([JumbotronFrame].self, forKey: .whaleyFrames) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if finger.phase != .none { try c.encode(finger, forKey: .finger) }
        if let state = `repeat` { try c.encode(state, forKey: .repeat) }
        if let on = parked { try c.encode(on, forKey: .parked) }
        if done { try c.encode(true, forKey: .done) }
        if !whaleyFrames.isEmpty { try c.encode(whaleyFrames, forKey: .whaleyFrames) }
    }
}

public struct StadiumSnapshot: Hashable, Sendable {
    public var tick: Int
    public var car: Car
    public var crowd: CrowdSnapshot
    /// Yaw in turns in stadium coordinates, toward the Jumbotron.
    public var turret: Fixed
    public var ride: RideSnapshot
}

public struct StadiumGame: Sendable {
    public let parameters: StadiumParameters
    public let kartParameters: KartParameters
    public let track: Track
    public let figures: [Figure]
    public private(set) var car: Car
    public private(set) var crowd: Crowd
    public private(set) var rng: Rng
    public private(set) var tick = 0
    public private(set) var bubbles: [Bubble] = []
    public private(set) var nextBubbleID = 1
    public private(set) var touchSustained = false
    public private(set) var currentX = Fixed(raw: -(1 << 16))
    public private(set) var currentY = Fixed(raw: -(1 << 16))
    public private(set) var fingerX = Fixed.zero
    public private(set) var fingerY = Fixed.zero
    /// Unlike the bubble hold, this stays true after movement so an interlude waits for finger lift.
    public private(set) var fingerDown = false
    public private(set) var bullpenCart = BullpenCartOnPicture.none
    /// Previous-tick contacts prevent the same overlap from starting another bounce.
    public private(set) var touching: Set<Touching> = []
    public private(set) var hops = [0, 0, 0, 0]
    public private(set) var level = Fixed.zero
    public private(set) var tempo: Fixed
    public private(set) var beatPhase: Int64 = 0
    public private(set) var streak = 0
    public private(set) var lastBeat: Int64 = -1
    public private(set) var nextAlarm: Int
    public private(set) var incident: Incident?
    public private(set) var thoughts: [FanThought] = []
    public private(set) var called: Set<Int> = []
    public private(set) var tally = RideTally()
    public private(set) var lastResult: AlarmResult?
    public private(set) var lastResultTick = -1
    public private(set) var lap = 0
    public private(set) var lastProgress: Fixed
    public private(set) var turret = Fixed.zero
    /// 1 is the base view; larger values widen it.
    public private(set) var zoom = Fixed.one
    public private(set) var inView = false
    public private(set) var fade = Fixed.zero
    public private(set) var crew = CrewSubject.free
    public private(set) var engaged = false
    public private(set) var pitcherRng: Rng
    public private(set) var runners: [Base]
    public private(set) var tossStart = 0
    public private(set) var ball: Ball
    public private(set) var throwInPlay: Throw?
    public private(set) var attentionFrom = -1
    public private(set) var attentionUntil = -1
    public private(set) var balks: [BalkCall] = []
    public private(set) var lastThrow: ThrowStatus?
    public private(set) var lastThrowTick = -1
    public private(set) var repeatState = RepeatState.off
    public private(set) var repeatLo = Fixed.zero
    public private(set) var repeatHi = Fixed.zero
    public private(set) var direction = 1
    public private(set) var turning = Fixed.zero
    public private(set) var unwrapped: Fixed
    public private(set) var repeatEver = false
    public private(set) var parked = false
    public private(set) var parkedAt: Fixed?
    public private(set) var parkedEver = false
    public private(set) var whaley = WhaleyObservation()
    private var whaleySessionID: String?
    private var whaleySequence = -1
    public private(set) var inQuadrant = false
    public private(set) var whaleyShown = false
    public private(set) var whaleyEngaged = false
    public private(set) var whaleyOver: [WhaleyOver] = []
    public private(set) var whaleyEvents: [WhaleyEvent] = []
    public let screen: ScreenGeometry
    public private(set) var jumbo: JumboZoom?
    public private(set) var jumboOn = false
    public private(set) var jumboEver = false
    public private(set) var interlude: Interlude?
    public private(set) var interludePending = false
    public private(set) var interludeNext: Fixed
    public private(set) var interludeGapUntil = 0
    public private(set) var interludeCount = 0
    public private(set) var interludeEver = false
    private var waterSpraySchedule = WaterSpraySchedule()
    public var waterSpray: WaterSpray? { waterSpraySchedule.latest }
    private var doneAsked = false
    private var caught: Set<Int> = []
    private var events: [RideEvent] = []
    public private(set) var digest = ReplayDigest()

    public struct Touching: Hashable, Sendable {
        public var bubble: Int
        public var wheel: Int
    }

    public init(parameters: StadiumParameters) {
        self.parameters = parameters
        kartParameters = parameters.kart
        track = Track(parameters: kartParameters)
        car = Car(parameters: kartParameters, track: track)
        figures = parameters.stands.figures()
        crowd = Crowd(count: figures.count, parameters: parameters.crowd)
        rng = Rng(seed: parameters.seed)
        tempo = parameters.ride.beat.slowBPM
        let a = parameters.ride.alarm
        nextAlarm = Int(rng.between(Int64(a.firstLo), Int64(a.firstHi)))
        lastProgress = car.progress
        pitcherRng = Rng(seed: parameters.seed + 1_000_000)
        runners = Fielder.runnerSets[Int(pitcherRng.below(Int64(Fielder.runnerSets.count)))]
        ball = Ball(state: .tossing, pos: .init(.zero, .zero, .zero), since: 0)
        unwrapped = car.progress
        interludeNext = parameters.ride.interlude.at
        screen = ScreenGeometry(parameters: parameters)
        ball.pos = tossPoint(at: 0)
    }

    /// Changing modes while driving backward first turns the kart forward.
    private mutating func setRepeat(_ state: RepeatState) {
        guard state != repeatState else { return }
        repeatState = state
        repeatEver = true
        events.append(.repeat(state))
        if direction < 0 { startTurnaround() }
        interludePending = false
        if state == .off {
            interludeNext = interludePoint(after: unwrapped)
            return
        }
        if state == .interlude {
            interludeGapUntil = tick
            return
        }
        placeStretch()
    }

    /// Choose the stretch containing the kart, or its next instance ahead.
    private mutating func placeStretch() {
        guard let stretch = parameters.ride.repeat.stretch(repeatState) else { return }
        let total = track.total
        var k = floorDiv((unwrapped - stretch.lo).raw, total.raw)
        if unwrapped > stretch.hi + total * Int(k) { k += 1 }
        repeatLo = stretch.lo + total * Int(k)
        repeatHi = stretch.hi + total * Int(k)
    }

    private mutating func setParked(_ on: Bool) {
        guard on != parked else { return }
        parked = on
        parkedEver = true
        events.append(.parked(on))
    }

    private mutating func settleHold() {
        let spot = parked ? parameters.ride.repeat.spot(repeatState) : nil
        guard spot != parkedAt else { return }
        parkedAt = spot
        guard let spot else { return }
        placeCar(at: spot)
        direction = 1
        turning = .zero
        placeStretch()
    }

    /// Repositioning is not driving and must not count a lap.
    private mutating func placeCar(at s: Fixed) {
        let at = track.point(atProgress: s), along = track.direction(atProgress: s)
        car.x = at.x
        car.z = at.z
        car.heading = Trig.bearing(dx: along.x, dz: along.z)
        car.yawRate = .zero
        car.speed = .zero
        let l = track.locate(x: car.x, z: car.z)
        car.progress = l.progress; car.offset = l.offset; car.side = l.side; car.segment = l.segment
        car.offTrack = car.offset > kartParameters.roadHalf
        lastProgress = car.progress
        unwrapped = track.total * lap + car.progress
    }

    private mutating func startTurnaround() {
        direction = -direction
        turning = Fixed(raw: Trig.turn / 2)
        events.append(.turnaround(direction: direction))
    }

    /// Turnarounds override bounce steering and always turn toward the field.
    private mutating func drive(steer: Int) -> Bool {
        let r = parameters.ride
        if turning > .zero {
            let rp = r.repeat
            var kp = kartParameters
            kp.yawMax = rp.turnYaw
            kp.cruiseSpeed = rp.turnSpeed
            let railed = car.step(parameters: kp, track: track, steer: Fixed(raw: Int64(direction) << 16), railHalf: r.railHalf)
            turning = max(.zero, turning - rp.turnYaw * kartParameters.dt)
            return railed
        }
        return car.step(parameters: kartParameters, track: track, steer: Fixed(raw: Int64(steer) << 16) * r.steer, railHalf: r.railHalf)
    }

    public var muzzle: Vec3 { Vec3(car.x, parameters.muzzleHeight, car.z) }

    public var camera: TurretCamera { TurretCamera(car: car, parameters: parameters, zoom: zoom, onHim: fade, jumbo: jumboAim ?? interludeAim) }

    public var jumboAim: JumboAim? { jumbo?.aim(ticks: parameters.ride.whaley.zoomTicks) }

    /// Measure visibility without zoom or fade to avoid feedback that repeatedly hides the pitcher.
    public var baseCamera: TurretCamera { TurretCamera(car: car, parameters: parameters) }

    /// A fan lock overrides pitcher zoom; fit the required subjects inside their screen margins.
    private mutating func zoomToward() {
        let v = parameters.ride.view, pz = parameters.ride.pitcher
        let w = parameters.picture.width, h = parameters.picture.height
        var target = Fixed.one
        let base = TurretCamera(car: car, parameters: parameters, zoom: .one, onHim: fade)
        if let inc = incident, inc.isLocked {
            let sx = base.halfWidth - w * v.zoomMarginX
            let sy = base.halfHeight - h * v.zoomMarginY
            for point in [figures[inc.figure].head, parameters.jumbotron] {
                guard let q = base.project(point) else { continue }
                target = max(target, (q.x - base.halfWidth).magnitude / sx, (q.y - base.halfHeight).magnitude / sy)
            }
            target = min(target, v.zoomMax)
        } else if fade > .zero {
            let sx = base.halfWidth - w * v.zoomMarginX
            let sy = base.halfHeight - h * v.zoomMarginY
            let kx = base.halfWidth - w * pz.gardenMargin
            let ky = base.halfHeight - h * pz.gardenMargin
            var need = Fixed.zero
            if let q = base.project(parameters.jumbotron) {
                need = max(need, (q.x - base.halfWidth).magnitude / sx, (q.y - base.halfHeight).magnitude / sy)
            } else {
                need = .one
            }
            for (i, f) in figures.enumerated() where isInGarden(i) {
                guard let q = base.project(f.head), .zero <= q.x, q.x <= w, .zero <= q.y, q.y <= h else { continue }
                need = max(need, (q.x - base.halfWidth).magnitude / kx, (q.y - base.halfHeight).magnitude / ky)
            }
            let fit = need.clamped(pz.zoomIn, .one)
            target = .one + (fit - .one) * fade
        }
        let diff = target - zoom
        if diff.magnitude <= v.zoomSnap {
            zoom = target
        } else {
            zoom = zoom + diff * v.zoomEase
        }
    }

    private mutating func fadeToward() {
        let pz = parameters.ride.pitcher
        inView = pitcherInView(camera: baseCamera)
        let target: Fixed = inView ? .one : .zero
        let diff = target - fade
        if diff.magnitude <= pz.fadeSnap {
            fade = target
        } else {
            fade = fade + diff * pz.fadeEase
        }
    }

    public func isInGarden(_ i: Int) -> Bool { parameters.ride.garden.contains(figure: i, seatsARow: parameters.stands.seats) }

    public func phase(of i: Int, at t: Int) -> ThoughtPhase? {
        for (k, s) in thoughts.enumerated() where s.figure == i && !called.contains(k) {
            if let ph = s.phase(at: t) { return ph }
        }
        return nil
    }

    private mutating func cancel(_ i: Int, at t: Int, for duration: Int) {
        for (k, s) in thoughts.enumerated() where s.figure == i && !called.contains(k) && s.isCalledOff(at: t, for: duration) {
            called.insert(k)
        }
    }

    func index(of id: Int) -> Int? { bubbles.firstIndex { $0.id == id } }

    private mutating func remove(_ id: Int) {
        if let i = index(of: id) { bubbles.remove(at: i) }
    }

    public var heldBubble: Bubble? { bubbles.first { $0.isFrozen && $0.isBeingMoved } }

    /// Keep the grabbed point under the finger while enlarging the bubble.
    @discardableResult
    private mutating func checkTouched(x: Fixed, y: Fixed) -> Bool {
        let rb = parameters.ride.bubbles
        for id in bubbles.filter({ $0.isFrozen }).map({ $0.id }) {
            guard let i = index(of: id), !bubbles[i].isBeingMoved else { continue }
            let b = bubbles[i]
            if HitBox.rectIntersectsCircle(PictureRect(x: x, y: y, w: .one, h: .one), x: b.x, y: b.y, diameter: b.size(rb), radiusOffset: rb.touchFudge,
                                           widthOffset: 0, heightOffset: 0) {
                bubbles[i].isBeingMoved = true
                bubbles[i].offsetX = (x - b.x) / rb.smallScale
                bubbles[i].offsetY = (y - b.y) / rb.smallScale
                bubbles[i].tracks.append([.move(toX: x - bubbles[i].offsetX, toY: y - bubbles[i].offsetY, fromX: nil, fromY: nil, step: 0)])
                bubbles[i].tracks.append([.scale(to: rb.normalScale, from: nil, step: 0), .callback(.enlargeOrRemove)])
                events.append(.grabbed(id: id))
                return true
            }
        }
        return false
    }

    private mutating func touchBegan(x: Fixed, y: Fixed) {
        let rb = parameters.ride.bubbles
        touchSustained = true
        currentX = x
        currentY = y
        if checkTouched(x: x, y: y) { return }
        var best: (d2: Fixed, pipe: Int, at: PicturePoint)?
        for (k, q) in bullpenCart.pipes.enumerated() {
            guard let q else { continue }
            let dx = x - q.x, dy = y - q.y
            let d2 = dx * dx + dy * dy
            if best == nil || d2 < best!.d2 { best = (d2, k, q) }
        }
        guard let (d2, k, q) = best else { return }
        if bubbles.count >= rb.maxBubbles { bubbles.removeFirst() }
        var b = Bubble(id: nextBubbleID, x: q.x, y: q.y, scale: .zero, isFrozen: false, isBeingMoved: false, usesLeft: rb.uses)
        nextBubbleID += 1
        let small = rb.small
        let to: PicturePoint
        if d2 < small * small {
            b.tracks = [[.scale(to: rb.smallScale, from: nil, step: 0)]]
            b.isFrozen = true
            to = q
        } else {
            b.tracks = [[.scale(to: rb.smallScale, from: nil, step: 0), .move(toX: x, toY: y, fromX: nil, fromY: nil, step: 0), .callback(.moveDone)]]
            to = PicturePoint(x: x, y: y)
        }
        bubbles.append(b)
        events.append(.bubble(id: b.id, pipe: k, x: to.x, y: to.y))
    }

    private mutating func touchMoved(x: Fixed, y: Fixed) {
        touchSustained = false
        for i in bubbles.indices where bubbles[i].isFrozen && bubbles[i].isBeingMoved {
            bubbles[i].x = x - bubbles[i].offsetX
            bubbles[i].y = y - bubbles[i].offsetY
            return
        }
        checkTouched(x: x, y: y)
    }

    private mutating func touchEnded(x: Fixed, y: Fixed) {
        let rb = parameters.ride.bubbles
        touchSustained = false
        for i in bubbles.indices where bubbles[i].isFrozen && bubbles[i].isBeingMoved {
            let grow = rb.normalScale - rb.smallScale
            bubbles[i].tracks.append([.move(toX: bubbles[i].x + bubbles[i].offsetX * grow, toY: bubbles[i].y + bubbles[i].offsetY * grow,
                                            fromX: nil, fromY: nil, step: 0)])
            bubbles[i].isBeingMoved = false
            bubbles[i].tracks.append([.scale(to: rb.smallScale, from: nil, step: 0)])
            events.append(.released(id: bubbles[i].id))
        }
    }

    /// Truncate the interpolated fraction toward zero to match replay fixtures.
    static func interpolate(from: Fixed, to: Fixed, step: Int, total: Int) -> Fixed {
        let scaled = (to.raw - from.raw) * Int64(step)
        let q = abs(scaled) / Int64(total)
        return Fixed(raw: from.raw + (scaled >= 0 ? q : -q))
    }

    /// Run callbacks after a completed action in the same tick; defer the next timed action.
    /// Return true when a callback removes the bubble.
    private mutating func advanceActions(of index: Int) -> Bool {
        let total = parameters.ride.bubbles.actionTicks
        var removed = false
        var t = 0
        while t < bubbles[index].tracks.count {
            var track = bubbles[index].tracks[t]
            var progressed = false
            while let head = track.first, !removed {
                switch head {
                case .callback(let callback):
                    track.removeFirst()
                    switch callback {
                    case .moveDone:
                        bubbles[index].isFrozen = true
                    case .enlargeOrRemove:
                        if !bubbles[index].isBeingMoved {
                            removed = true
                            events.append(.popped(id: bubbles[index].id))
                        }
                    }
                    continue
                case .scale(let to, let from, let step):
                    if progressed { break }
                    let start = from ?? bubbles[index].scale
                    let next = step + 1
                    bubbles[index].scale = Self.interpolate(from: start, to: to, step: next, total: total)
                    progressed = true
                    if next >= total {
                        bubbles[index].scale = to
                        track.removeFirst()
                        continue
                    }
                    track[0] = .scale(to: to, from: start, step: next)
                case .move(let toX, let toY, let fromX, let fromY, let step):
                    if progressed { break }
                    let startX = fromX ?? bubbles[index].x
                    let startY = fromY ?? bubbles[index].y
                    let next = step + 1
                    bubbles[index].x = Self.interpolate(from: startX, to: toX, step: next, total: total)
                    bubbles[index].y = Self.interpolate(from: startY, to: toY, step: next, total: total)
                    progressed = true
                    if next >= total {
                        bubbles[index].x = toX
                        bubbles[index].y = toY
                        track.removeFirst()
                        continue
                    }
                    track[0] = .move(toX: toX, toY: toY, fromX: startX, fromY: startY, step: next)
                }
                break
            }
            if removed { return true }
            if track.isEmpty {
                bubbles[index].tracks.remove(at: t)
            } else {
                bubbles[index].tracks[t] = track
                t += 1
            }
        }
        return false
    }

    private mutating func contacts() -> [(wheel: Int, bubble: Int)] {
        let rb = parameters.ride.bubbles
        let frozen = bubbles.filter { $0.isFrozen }.map { $0.id }
        var now: Set<Touching> = []
        var started: [(wheel: Int, bubble: Int)] = []
        for id in frozen {
            guard let i = index(of: id) else { continue }
            let b = bubbles[i]
            for (k, rect) in bullpenCart.wheels.enumerated() {
                guard let rect, HitBox.rectIntersectsCircle(rect, x: b.x, y: b.y, diameter: b.size(rb), radiusOffset: -1, widthOffset: -1,
                                                              heightOffset: 0) else { continue }
                let close = Fixed(raw: rect.w.raw / 16)
                if (rect.midX - b.x).magnitude <= close && (rect.midY - b.y).magnitude <= close {
                    remove(id)
                    events.append(.popped(id: id))
                    break
                }
                let pair = Touching(bubble: id, wheel: k)
                now.insert(pair)
                if !touching.contains(pair) && hops[k] == 0 {
                    hops[k] = parameters.ride.hop.ticks
                    started.append((k, id))
                    if !b.isBeingMoved { bubbles[i].usesLeft -= 1 }
                }
            }
        }
        var foundMoving = false
        for id in frozen {
            guard let i = index(of: id) else { continue }
            if bubbles[i].isBeingMoved { foundMoving = true }
            if bubbles[i].usesLeft <= 0 {
                remove(id)
                events.append(.popped(id: id))
            }
        }
        let live = Set(bubbles.map(\.id))
        touching = now.filter { live.contains($0.bubble) }
        if touchSustained && !foundMoving { checkTouched(x: currentX, y: currentY) }
        return started
    }

    /// Whaley zoom and phone visits defer hidden fan reveals; baseball coverage yields to the fan.
    private mutating func deferThoughtForCamera(at tick: Int) {
        guard var inc = incident, inc.isLive, tick >= inc.start - 1,
              !Self.showsFan(crew: crewSubject(at: tick), dollOnJumbotron: true, zoomed: jumbo != nil) else { return }
        inc.start = tick + 1
        inc.end = inc.start + parameters.ride.alarm.leniency
        incident = inc
        thoughts = [FanThought(figure: inc.figure, start: inc.start,
                               end: inc.start + parameters.ride.alarm.fit,
                               spinTicks: max(0, inc.start - inc.beep), symbol: inc.symbol)]
    }


    @discardableResult
    private mutating func alarm(at t: Int, camera cam: TurretCamera) -> Bool {
        let a = parameters.ride.alarm
        let w = parameters.picture.width, h = parameters.picture.height
        let x0 = w * a.bandLeft, x1 = w * a.bandRight, y0 = h * a.bandTop
        var y1 = h * a.bandBottom
        if let top = cam.project(kartPoint(car, right: .zero, forward: .zero, up: a.clearHeight)) {
            y1 = min(y1, top.y - a.clearMargin)
        }
        // Pitcher views need enough reach to select fans across the field.
        let reach = inView ? parameters.ride.pitcher.dollReach : a.maxDepth
        var gardenSeats: [Int] = [], rest: [Int] = []
        for (i, f) in figures.enumerated() {
            guard let q = cam.project(f.head), q.depth <= reach, x0 <= q.x, q.x <= x1, y0 <= q.y, q.y <= y1 else { continue }
            if isInGarden(i) { gardenSeats.append(i) } else { rest.append(i) }
        }
        if gardenSeats.isEmpty && rest.isEmpty { return false }
        let pool: [Int]
        if !gardenSeats.isEmpty && !rest.isEmpty {
            pool = rng.below(Int64(parameters.ride.garden.oneIn)) == 0 ? gardenSeats : rest
        } else {
            pool = gardenSeats.isEmpty ? rest : gardenSeats
        }
        let figure = pool[Int(rng.below(Int64(pool.count)))]
        let symbol = ThoughtSymbol.draw(using: &rng, variation: figure + t)
        let start = t + a.lead
        let garden = isInGarden(figure)
        incident = Incident(beep: t, figure: figure, garden: garden, symbol: symbol, start: start, end: start + a.leniency)
        thoughts = [FanThought(figure: figure, start: start, end: start + a.fit, spinTicks: a.lead, symbol: symbol)]
        called = []
        tally.alarms += 1
        if garden { tally.garden += 1 }
        events.append(.beep(figure: figure, garden: garden))
        return true
    }

    private mutating func finish(at t: Int, result: ShotResult) {
        guard var inc = incident else { return }
        let a = parameters.ride.alarm
        inc.ended = t
        inc.result = result
        incident = inc
        switch result {
        case .served: tally.served += 1
        case .tooSoon: tally.tooSoon += 1; tally.wrong += 1
        case .heldFire: tally.heldFire += 1
        default: tally.wrong += 1
        }
        lastResult = AlarmResult(beep: inc.beep, figure: inc.figure, garden: inc.garden, symbol: inc.symbol, item: inc.item, result: result,
                                 endTick: t, shot: inc.shot)
        lastResultTick = t
        nextAlarm = t + Int(rng.between(Int64(a.gapLo), Int64(a.gapHi)))
        events.append(.result(result))
    }

    private mutating func letGoOfReticle() {
        guard let inc = incident else { return }
        if let i = index(of: inc.locked) {
            bubbles[i].isBeingMoved = false
            bubbles[i].tracks.append([.scale(to: parameters.ride.bubbles.smallScale, from: nil, step: 0)])
            events.append(.released(id: bubbles[i].id))
        }
        incident?.locked = -1
    }

    /// Cast from the rendered eye and expand each target by the item radius.
    private mutating func fire(at t: Int, camera cam: TurretCamera) {
        guard let inc = incident, t < inc.end, let i = index(of: inc.locked) else { return }
        let b = bubbles[i]
        let grow = parameters.ride.alarm.itemRadius
        let grown = figures.map { fg -> Figure in
            var g = fg
            g.headR = fg.headR + grow
            g.torsoR = fg.torsoR + grow
            return g
        }
        let hit = firstHit(origin: cam.eye, direction: cam.ray(x: b.x, y: b.y), figures: grown)
        incident?.shot = t
        if let hit {
            events.append(.fired(item: inc.item, figure: hit.figure, part: hit.part.rawValue, distance: hit.distance))
            if inc.item == .hotDog { caught.insert(hit.figure) }
        } else {
            events.append(.fired(item: inc.item, figure: -1, part: -1, distance: .zero))
        }
        finish(at: t, result: ShotResult.judge(hit: hit?.figure, figure: inc.figure, symbol: inc.symbol, item: inc.item, revealed: t >= inc.start && t < inc.end))
    }

    /// Locked reticles follow the fan; cancellation drops a captured ball without throwing it.
    private mutating func fingerPhase(_ finger: FingerInput, at t: Int, camera cam: TurretCamera) {
        let (phase, x, y) = (finger.phase, finger.x, finger.y)
        if phase != .none {
            fingerX = x
            fingerY = y
        }
        if phase == .began {
            fingerDown = true
        } else if phase == .ended || phase == .cancelled {
            fingerDown = false
        }
        if ball.state == .captured && (phase == .ended || phase == .cancelled) {
            var how = ReleaseKind.dropped, speed = Fixed.zero, way = Fixed.zero
            if phase == .ended { (how, speed, way) = flick(camera: cam, x: x, y: y) }
            touchEnded(x: x, y: y)
            releaseBall(at: t, how: how, speed: speed, way: way)
            return
        }
        if let inc = incident, inc.isLocked, phase != .none {
            switch phase {
            case .moved:
                return
            case .ended:
                fire(at: t, camera: cam)
                letGoOfReticle()
                touchSustained = false
                return
            default:
                letGoOfReticle()
                touchSustained = false
                events.append(.unlocked)
                if phase != .began { return }
            }
        }
        switch phase {
        case .none: break
        case .began: touchBegan(x: x, y: y)
        case .moved: touchMoved(x: x, y: y)
        case .ended, .cancelled: touchEnded(x: x, y: y)
        }
    }

    private mutating func watch(at t: Int, camera cam: TurretCamera) {
        guard var inc = incident else { return }
        let a = parameters.ride.alarm
        let head = cam.point(figures[inc.figure].head)
        defer { incident = inc }
        if inc.locked >= 0 {
            if let i = index(of: inc.locked), let head {
                bubbles[i].x = head.x
                bubbles[i].y = head.y
                inc.aim = .one
            } else {
                if index(of: inc.locked) != nil {
                    remove(inc.locked)
                    events.append(.popped(id: inc.locked))
                }
                inc.locked = -1
                inc.aim = .zero
                events.append(.unlocked)
            }
            return
        }
        guard let b = heldBubble, !(ball.state == .captured && ball.bubble == b.id), let head, let i = index(of: b.id) else {
            inc.aim = .zero
            return
        }
        let d = PicturePoint(x: b.x, y: b.y).distance(to: head)
        let radius = Fixed(raw: b.size(parameters.ride.bubbles).raw >> 1)
        inc.aim = .zero < radius && d < radius ? (.one - d / radius).clamped(.zero, .one) : .zero
        if d <= a.lockRadius {
            inc.locked = b.id
            inc.lockTick = t
            inc.item = .hotDog
            inc.aim = .one
            bubbles[i].x = head.x
            bubbles[i].y = head.y
            events.append(.locked(id: b.id))
        }
    }

    private var fielderFigures: [(who: Catcher, base: Base?, figure: Figure)] {
        let pz = parameters.ride.pitcher
        return Fielder.all.map { ($0.who, $0.base, $0.figure(pz)) }
    }

    public func tossPoint(at t: Int) -> Vec3 {
        let pz = parameters.ride.pitcher
        let k = floorMod(Int64(t - tossStart), Int64(pz.tossAir + pz.tossHeld))
        var g = pz.glove
        if k < Int64(pz.tossAir) {
            let tau = Fixed(raw: k << 16) / Fixed(raw: Int64(pz.tossAir) << 16)
            let rise = Fixed(raw: pz.tossHeight.raw << 2) * tau * (.one - tau)
            g = Vec3(g.x, g.y + rise, g.z)
        }
        return pz.point(g)
    }

    public func ballOnPicture(camera cam: TurretCamera) -> PicturePoint? { cam.point(ball.pos) }

    public func pitcherInView(camera cam: TurretCamera) -> Bool {
        let pz = parameters.ride.pitcher
        guard let m = cam.project(pz.point(pz.middle)) else { return false }
        return .zero <= m.x && m.x <= parameters.picture.width && .zero <= m.y && m.y <= parameters.picture.height
    }

    private func crewSubject(at t: Int) -> CrewSubject {
        if interlude != nil { return .fan }
        if attentionFrom <= t && t < attentionUntil { return .pitcher }
        if ball.state == .captured || ball.state == .flying || ball.state == .settled { return .ball }
        if let lt = lastThrow, !lt.outcome.isBalk, t < lastThrowTick + parameters.ride.pitcher.crewAfterCall { return .ball }
        return .free
    }

    private mutating func pitcherWatch(at t: Int, camera cam: TurretCamera) {
        let pz = parameters.ride.pitcher
        let th = throwInPlay
        switch ball.state {
        case .tossing:
            ball.pos = tossPoint(at: t)
            guard let b = heldBubble, let i = index(of: b.id) else { return }
            if let inc = incident, inc.isLive, inc.locked == b.id { return }
            guard let q = ballOnPicture(camera: cam), PicturePoint(x: b.x, y: b.y).distance(to: q) <= pz.captureRadius else { return }
            ball.state = .captured
            ball.bubble = b.id
            ball.since = t
            ball.depth = (ball.pos - cam.eye).dot(cam.basis.forward)
            bubbles[i].x = q.x
            bubbles[i].y = q.y
            throwInPlay = Throw(captured: t, finger: PicturePoint(x: fingerX, y: fingerY))
            engaged = true
            events.append(.captured(id: b.id))
        case .captured:
            guard let i = index(of: ball.bubble), var th else {
                releaseBall(at: t, how: .dropped, speed: .zero, way: .zero)
                return
            }
            // Apply finger travel in the camera-facing plane through the ball, then reproject.
            let dx = fingerX - th.finger.x, dy = fingerY - th.finger.y
            th.finger = PicturePoint(x: fingerX, y: fingerY)
            if dx != .zero || dy != .zero {
                let scale = (ball.pos - cam.eye).dot(cam.basis.forward) / cam.focal
                ball.pos = ball.pos + (cam.basis.right.scaled(by: dx * scale) + cam.basis.up.scaled(by: -dy * scale))
            }
            if let q = cam.point(ball.pos) {
                bubbles[i].x = q.x
                bubbles[i].y = q.y
            }
            th.trail.append(PicturePoint(x: fingerX, y: fingerY))
            if th.trail.count > pz.flickTicks + 1 { th.trail.removeFirst() }
            throwInPlay = th
            if t - th.captured >= pz.holdLimit {
                bubbles[i].isBeingMoved = false
                bubbles[i].tracks.append([.scale(to: parameters.ride.bubbles.smallScale, from: nil, step: 0)])
                touchSustained = false
                events.append(.released(id: bubbles[i].id))
                releaseBall(at: t, how: .held, speed: .zero, way: .zero)
            }
        case .flying:
            fly(at: t)
        case .settled, .dead:
            if let th, th.call >= 0, t == th.call { callThrow(at: t) }
            if let th, th.call >= 0, t >= th.call + pz.reset, ball.state != .tossing { newBall(at: t) }
        }
    }

    private mutating func newBall(at t: Int) {
        runners = Fielder.runnerSets[Int(pitcherRng.below(Int64(Fielder.runnerSets.count)))]
        tossStart = t
        ball = Ball(state: .tossing, pos: .init(.zero, .zero, .zero), since: t)
        ball.pos = tossPoint(at: t)
        throwInPlay = nil
        events.append(.newBall(runners: runners))
    }

    /// Map upward screen motion away from the camera on the field; speed comes from points per tick.
    private func flick(camera cam: TurretCamera, x: Fixed, y: Fixed) -> (how: ReleaseKind, speed: Fixed, way: Fixed) {
        let pz = parameters.ride.pitcher
        let trail = throwInPlay?.trail ?? []
        let ref = trail.first ?? PicturePoint(x: x, y: y)
        let n = max(1, min(trail.count, pz.flickTicks))
        let dx = x - ref.x, dy = y - ref.y
        let travel = Fixed.sqrt(dx * dx + dy * dy)
        let perTick = travel / Fixed(raw: Int64(n) << 16)
        if perTick < pz.flickMin { return (.dropped, .zero, .zero) }
        let speed = min(perTick * pz.speedPerPoint, pz.maxSpeed)
        let c = cam.compass
        let away = -dy * pz.depthGain
        let gx = dx * c.rightX + away * c.forwardX
        let gz = dx * c.rightZ + away * c.forwardZ
        return (.thrown, speed, Trig.bearing(dx: gx, dz: gz))
    }

    private mutating func releaseBall(at t: Int, how: ReleaseKind, speed: Fixed, way: Fixed) {
        let pz = parameters.ride.pitcher
        var vel = Vec3(.zero, .zero, .zero)
        if how == .thrown {
            let run = speed * Trig.cos(pz.launch)
            vel = Vec3(run * Trig.sin(way), speed * Trig.sin(pz.launch), run * Trig.cos(way))
        }
        ball.state = .flying
        ball.vel = vel
        ball.since = t
        ball.rolling = false
        ball.bubble = -1
        throwInPlay?.released = t
        throwInPlay?.how = how
        throwInPlay?.speed = speed
        throwInPlay?.way = way
        events.append(.thrown(how: how, speed: speed, way: way))
    }

    private mutating func fly(at t: Int) {
        let pz = parameters.ride.pitcher
        let dt = Fixed(1.0 / 60.0)
        var pos = ball.pos, vel = ball.vel
        pos = pos + vel.scaled(by: dt)
        vel = Vec3(vel.x, vel.y - pz.gravity, vel.z)
        let centre = parameters.stands.centre
        let rx = pos.x - centre.x, rz = pos.z - centre.z
        let radius = Fixed.sqrt(rx * rx + rz * rz)
        let inStands = radius >= pz.wallRadius
        var floor = pz.ballRadius
        if inStands {
            floor = pz.wallHeight + ((radius - pz.wallRadius) * pz.standsRise) / (pz.standsBack - pz.wallRadius)
            if pos.y < floor && vel.y <= .zero && radius < pz.standsBack && pos.y + (-vel.y) * dt >= pz.wallHeight {
                pos = Vec3(pos.x, floor, pos.z)
                vel = Vec3(.zero, .zero, .zero)
                ball.rolling = true
            } else if pos.y < pz.wallHeight || radius >= pz.standsBack {
                let ux = rx / radius, uz = rz / radius
                let out = vel.x * ux + vel.z * uz
                if out > .zero {
                    vel = Vec3(vel.x - (out + out * pz.restitution) * ux, vel.y, vel.z - (out + out * pz.restitution) * uz)
                    let at = pos.y < pz.wallHeight ? pz.wallRadius : pz.standsBack
                    pos = Vec3(centre.x + ux * at, pos.y, centre.z + uz * at)
                }
            }
        }
        if !inStands && pos.y <= floor {
            pos = Vec3(pos.x, floor, pos.z)
            if vel.y < .zero {
                let up = -(vel.y * pz.restitution)
                vel = Vec3(vel.x * pz.bounceKeep, up, vel.z * pz.bounceKeep)
                if up < .one {
                    vel = Vec3(vel.x, .zero, vel.z)
                    ball.rolling = true
                }
            }
        }
        if ball.rolling {
            vel = Vec3(vel.x * pz.rollKeep, .zero, vel.z * pz.rollKeep)
            pos = Vec3(pos.x, floor, pos.z)
        }
        ball.pos = pos
        ball.vel = vel
        var who = Catcher.nobody, by = -1
        var base: Base?
        if !inStands {
            for (k, f) in fielderFigures.enumerated() where withinSteps(f.figure, pos, steps: pz.fieldRange, height: pz.fieldHeight) {
                (who, by, base) = (f.who, k, f.base)
                break
            }
            if who == .nobody && t - ball.since >= pz.ownAfter && vel.y <= .zero
                && withinSteps(pz.figure, pos, steps: pz.fieldRange, height: pz.fieldHeight) {
                who = .pitcherHimself
            }
        } else {
            for (k, f) in figures.enumerated() where nearFigure(f, pos, reach: pz.fanReach, ballRadius: pz.ballRadius) {
                (who, by) = (.fan, k)
                caught.insert(k)
                break
            }
        }
        if who != .nobody {
            endThrow(at: t, who: who, by: by, base: base)
            return
        }
        let run = vel.x * vel.x + vel.z * vel.z
        if (ball.rolling && run < pz.settleSpeed * pz.settleSpeed) || t - ball.since >= pz.flightMax {
            if !inStands && withinSteps(pz.figure, pos, steps: pz.pickUp, height: pz.fieldHeight) { who = .pitcherHimself }
            endThrow(at: t, who: who, by: -1, base: nil)
        }
    }

    /// A drop or hold-limit balk remains that outcome regardless of who later catches the ball.
    private mutating func endThrow(at t: Int, who: Catcher, by: Int, base: Base?) {
        let pz = parameters.ride.pitcher
        guard var th = throwInPlay else { return }
        let outcome: ThrowOutcome
        switch th.how {
        case .thrown?: outcome = ThrowOutcome.judge(who: who, base: base, runners: runners)
        case .dropped?: outcome = .dropped
        default: outcome = .noBall
        }
        ball.state = .settled
        ball.since = t
        th.ended = t
        th.who = who
        th.by = by
        th.base = base
        th.outcome = outcome
        th.call = t + pz.callDelay
        throwInPlay = th
        events.append(.fielded(who: who, by: by, base: base, outcome: outcome))
    }

    private mutating func callThrow(at t: Int) {
        let pz = parameters.ride.pitcher
        guard let th = throwInPlay, let k = th.outcome else { return }
        var points = 0
        if k.isBalk {
            points = pz.points[k.rawValue]
            let until = t + pz.hold[k.rawValue]
            if t < attentionUntil {
                attentionUntil = max(attentionUntil, until)
            } else {
                attentionFrom = t
                attentionUntil = until
            }
            tally.balks += 1
            tally.balkPoints += points
            tally.points += points
            balks.append(BalkCall(type: k, released: th.released, call: t, points: points, until: attentionUntil))
            events.append(.balk(k, points: points, until: attentionUntil))
        }
        lastThrow = ThrowStatus(captured: th.captured, released: th.released, how: th.how, who: th.who, by: th.by, base: th.base, outcome: k,
                                points: points, call: t)
        lastThrowTick = t
        ball.state = .dead
        if k == .hisOwn { newBall(at: t) }
    }

    /// Return metres right and up from the screen center, plus camera depth.
    /// The plane hit may lie outside the screen; reject rays away from it or within one metre.
    public func planeCast(camera cam: TurretCamera, x: Fixed, y: Fixed) -> (u: Fixed, v: Fixed, depth: Fixed)? {
        let s = screen
        let d = cam.ray(x: x, y: y)
        let denom = d.dot(s.normal)
        guard denom < .zero else { return nil }
        let t = (s.face - cam.eye).dot(s.normal) / denom
        guard t > .one else { return nil }
        let hit = cam.eye + d.scaled(by: t)
        let rel = hit - s.face
        return (rel.dot(s.right), rel.y, (hit - cam.eye).dot(cam.basis.forward))
    }

    public func screenCast(camera cam: TurretCamera, x: Fixed, y: Fixed) -> (u: Fixed, v: Fixed, depth: Fixed)? {
        guard let c = planeCast(camera: cam, x: x, y: y) else { return nil }
        let s = screen
        guard c.u.magnitude <= s.halfWidth, c.v.magnitude <= s.halfHeight else { return nil }
        return c
    }

    /// Native screen coordinates use points from the bottom-left corner.
    public func screenSpot(u: Fixed, v: Fixed) -> (x: Fixed, y: Fixed) {
        let s = screen
        return ((u + s.halfWidth) * s.pixelsPerMetre, (v + s.halfHeight) * s.pixelsPerMetre)
    }

    public func screenWorld(x lx: Fixed, y ly: Fixed) -> Vec3 {
        let s = screen
        let u = (lx + whaley.layer.x) * s.metresPerPixel - s.halfWidth
        let v = (ly + whaley.layer.y) * s.metresPerPixel - s.halfHeight
        return s.face + s.right.scaled(by: u) + Vec3(.zero, v, .zero)
    }

    public func screenPoint(camera cam: TurretCamera, x lx: Fixed, y ly: Fixed) -> PicturePoint? { cam.point(screenWorld(x: lx, y: ly)) }

    /// Fan presentation outranks baseball coverage; explicit Whaley zoom and phone visits keep control.
    public static func showsFan(crew: CrewSubject, dollOnJumbotron: Bool, zoomed: Bool) -> Bool {
        dollOnJumbotron && !zoomed && crew != .fan
    }

    public static func showsGame(inQuadrant: Bool, crew: CrewSubject, dollOnJumbotron: Bool, zoomed: Bool) -> Bool {
        inQuadrant && crew == .free && !showsFan(crew: crew, dollOnJumbotron: dollOnJumbotron, zoomed: zoomed)
    }

    public var kartInQuadrant: Bool {
        let q = parameters.ride.whaley.quadrant
        let c = KartParameters.fieldCentre
        let b = Trig.bearing(dx: car.x - c.x, dz: car.z - c.z)
        return q[0] <= b && b <= q[1]
    }

    /// Enter zoom only when a held bubble crosses onto the screen; reverse the same transition on exit.
    private mutating func jumboPhase(camera cam: TurretCamera) {
        var held = heldBubble
        if let h = held, ball.state == .captured && ball.bubble == h.id { held = nil }
        guard var j = jumbo else {
            var on = false
            if let b = held, whaleyShown, !whaley.dead, screenCast(camera: cam, x: b.x, y: b.y) != nil { on = true }
            if on && !jumboOn, let b = held { zoomIn(b, camera: cam) }
            jumboOn = on
            return
        }
        if !j.out {
            if held == nil || held!.id != j.bubble || whaley.dead || !whaleyShown {
                j.out = true
                events.append(.zoom(inward: false, bubble: j.bubble))
            } else {
                j.k = min(j.k + 1, parameters.ride.whaley.zoomTicks)
                jumbo = j
                return
            }
        }
        j.k -= 1
        jumbo = j.k <= 0 ? nil : j
    }

    /// Keep the entry point under the held bubble while fitting the screen within the viewport.
    private mutating func zoomIn(_ b: Bubble, camera cam: TurretCamera) {
        let w = parameters.ride.whaley, s = screen, pic = parameters.picture
        guard let cast = screenCast(camera: cam, x: b.x, y: b.y) else { return }
        let d = s.face - cam.eye
        let yaw = Trig.bearing(dx: d.x, dz: d.z)
        let pitch = Trig.elevation(dy: d.y, horizontal: Fixed.sqrt(d.x * d.x + d.z * d.z))
        let at = TurretCamera(car: car, parameters: parameters, zoom: zoom, onHim: fade, jumbo: JumboAim(share: .one, yaw: yaw, pitch: pitch, zoom: .one))
        func off(_ du: Fixed, _ dv: Fixed) -> (x: Fixed, y: Fixed)? {
            guard let q = at.project(s.face + s.right.scaled(by: du) + Vec3(.zero, dv, .zero)) else { return nil }
            return (q.x - at.halfWidth, q.y - at.halfHeight)
        }
        var xs: [Fixed] = [], ys: [Fixed] = []
        for su in [-1, 1] {
            for sv in [-1, 1] {
                guard let c = off(s.halfWidth * su, s.halfHeight * sv) else { return }
                xs.append(c.x)
                ys.append(c.y)
            }
        }
        let into = (xs.max()! - xs.min()!) / w.zoomWidth
        guard let e = off(cast.u, cast.v) else { return }
        var cx = b.x - e.x / into
        var cy = b.y - e.y / into
        var lo = w.zoomSide - xs.min()! / into, hi = pic.width - w.zoomSide - xs.max()! / into
        cx = lo <= hi ? cx.clamped(lo, hi) : Fixed(raw: (lo.raw + hi.raw) >> 1)
        lo = w.zoomTop - ys.min()! / into
        hi = pic.height - w.zoomBottom - ys.max()! / into
        cy = lo <= hi ? cy.clamped(lo, hi) : Fixed(raw: (lo.raw + hi.raw) >> 1)
        let focal = at.halfHeight / (parameters.ride.view.tanHalfV * into)
        jumbo = JumboZoom(bubble: b.id, k: 1, out: false,
                          yaw: Fixed(raw: Trig.normalize(yaw.raw - Trig.elevation(dy: cx - at.halfWidth, horizontal: focal).raw)),
                          pitch: pitch + Trig.elevation(dy: cy - at.halfHeight, horizontal: focal), zoom: into)
        jumboEver = true
        car.speed = .zero
        car.yawRate = .zero
        bullpenCart = .none
        events.append(.zoom(inward: true, bubble: b.id))
    }

    public var interludeAim: JumboAim? { interlude?.aim(ticks: parameters.ride.interlude.turnTicks) }

    /// Skip the opening position; schedule the first interlude after a full lap.
    private func interludePoint(after u: Fixed) -> Fixed {
        let at = parameters.ride.interlude.at, total = track.total
        if u < at { return at }
        return at + total * Int(floorDiv((u - at).raw, total.raw) + 1)
    }

    private func interludeQuiet(at t: Int) -> Bool {
        !fingerDown && heldBubble == nil && bubbles.allSatisfy { $0.isFrozen } && !(incident?.isLive ?? false) && jumbo == nil
            && ball.state == .tossing && !(attentionFrom <= t && t < attentionUntil) && turning == .zero
    }

    /// Prefer a non-garden fan, then the closest head to the selection band center.
    private func interludeFan(camera cam: TurretCamera) -> Int? {
        let a = parameters.ride.alarm
        let w = parameters.picture.width, h = parameters.picture.height
        let x0 = w * a.bandLeft, x1 = w * a.bandRight, y0 = h * a.bandTop
        var y1 = h * a.bandBottom
        if let top = cam.project(kartPoint(car, right: .zero, forward: .zero, up: a.clearHeight)) {
            y1 = min(y1, top.y - a.clearMargin)
        }
        let reach = inView ? parameters.ride.pitcher.dollReach : a.maxDepth
        let mx = Fixed(raw: (x0.raw + x1.raw) >> 1), my = Fixed(raw: (y0.raw + y1.raw) >> 1)
        var best: (garden: Int, d2: Fixed, figure: Int)?
        for (i, f) in figures.enumerated() {
            guard let q = cam.project(f.head), q.depth <= reach, x0 <= q.x, q.x <= x1, y0 <= q.y, q.y <= y1 else { continue }
            let dx = q.x - mx, dy = q.y - my
            let key = (isInGarden(i) ? 1 : 0, dx * dx + dy * dy)
            if let b = best, !(key.0 < b.garden || (key.0 == b.garden && key.1 < b.d2)) { continue }
            best = (key.0, key.1, i)
        }
        return best?.figure
    }

    private mutating func interludePhase(at t: Int, camera cam: TurretCamera) {
        let il = parameters.ride.interlude
        guard var i = interlude else {
            switch repeatState {
            case .off: interludePending = interludePending || (direction > 0 && unwrapped >= interludeNext)
            case .interlude: interludePending = t >= interludeGapUntil
            default: interludePending = false
            }
            if interludePending {
                interludeEver = true
                if interludeQuiet(at: t) { interludeBegin(at: t, camera: cam) }
            }
            return
        }
        switch i.phase {
        case .turningIn:
            i.k += 1
            if i.k >= il.turnTicks {
                i.phase = .browsing
            }
            interlude = i
        case .browsing:
            // Only recorded input can end exploration; elapsed ticks do not.
            if doneAsked {
                interludeShot(at: t, camera: cam)
                interlude?.phase = .catchWatched
                interlude?.left = il.holdTicks
            }
        case .catchWatched:
            i.left -= 1
            if i.left <= 0 { i.phase = .turningBack }
            interlude = i
        case .turningBack:
            i.k -= 1
            interlude = i
            if i.k <= 0 { interludeEnd(at: t) }
        }
    }

    private mutating func interludeBegin(at t: Int, camera cam: TurretCamera) {
        let il = parameters.ride.interlude
        interludePending = false
        guard let fan = interludeFan(camera: cam) else {
            interludeNext = interludePoint(after: unwrapped)
            interludeGapUntil = t + il.gapTicks
            return
        }
        let f = figures[fan]
        let d = f.head - cam.eye
        let ground = Fixed.sqrt(d.x * d.x + d.z * d.z)
        let depth = Fixed.sqrt(ground * ground + d.y * d.y)
        let yaw = Trig.bearing(dx: d.x, dz: d.z)
        let pitch = Trig.elevation(dy: d.y, horizontal: ground)
        let hh = Fixed(raw: parameters.picture.height.raw >> 1)
        let tanV = parameters.ride.view.tanHalfV
        let into = ((hh * f.headR) / ((il.headRadius * depth) * tanV)).clamped(Fixed(0.02), .one)
        let focal = hh / (tanV * into)
        let y = parameters.picture.height * il.headAt
        interludeCount += 1
        interlude = Interlude(fan: fan, number: interludeCount, phase: .turningIn, k: 1, left: 0, shot: -1, yaw: yaw,
                              pitch: pitch + Trig.elevation(dy: y - hh, horizontal: focal), zoom: into)
        car.speed = .zero
        car.yawRate = .zero
        events.append(.interlude(begun: true, fan: fan, number: interludeCount))
    }

    private mutating func interludeShot(at t: Int, camera cam: TurretCamera) {
        guard let i = interlude else { return }
        let grow = parameters.ride.alarm.itemRadius
        let grown = figures.map { fg -> Figure in
            var g = fg
            g.headR = fg.headR + grow
            g.torsoR = fg.torsoR + grow
            return g
        }
        var hit: Hit?
        if let q = cam.project(figures[i.fan].head) {
            hit = firstHit(origin: cam.eye, direction: cam.ray(x: q.x, y: q.y), figures: grown)
        }
        interlude?.shot = t
        if let hit {
            events.append(.fired(item: .hotDog, figure: hit.figure, part: hit.part.rawValue, distance: hit.distance))
            caught.insert(hit.figure)
        } else {
            events.append(.fired(item: .hotDog, figure: -1, part: -1, distance: .zero))
        }
    }

    private mutating func interludeEnd(at t: Int) {
        guard let i = interlude else { return }
        interlude = nil
        interludeNext = interludePoint(after: unwrapped)
        interludeGapUntil = t + parameters.ride.interlude.gapTicks
        nextAlarm = max(nextAlarm, t + parameters.ride.alarm.gapLo)
        events.append(.interlude(begun: false, fan: i.fan, number: i.number))
    }

    /// Consume each native batch once, even if the displayed program changed before this tick.
    private mutating func consumeWhaley(_ frames: [JumbotronFrame]) {
        whaleyEvents = []
        for frame in frames {
            if let id = whaleySessionID, id != frame.sessionID { continue }
            guard frame.sequence > whaleySequence else { continue }
            whaleySessionID = frame.sessionID
            whaleySequence = frame.sequence
            whaley = frame.observation
            for event in frame.events {
                switch event {
                case .bubbleContact(let id, let uses, let popped, _):
                    // Ignore late contacts for bubbles already removed by Stadium.
                    guard let i = index(of: id) else { continue }
                    whaleyEngaged = true
                    bubbles[i].usesLeft = max(0, uses)
                    if popped {
                        remove(id)
                        events.append(.popped(id: id))
                    }
                case .coin where whaleyEngaged:
                    tally.coins += 1
                    tally.points += parameters.ride.whaley.coinPoints
                case .goal where whaleyEngaged:
                    tally.goals += 1
                    tally.points += parameters.ride.whaley.goalPoints
                default:
                    break
                }
                whaleyEvents.append(event)
            }
        }
    }

    private mutating func projectJumbotronBubbles(at t: Int, camera cam: TurretCamera) {
        inQuadrant = kartInQuadrant
        whaleyShown = Self.showsGame(inQuadrant: inQuadrant, crew: crew, dollOnJumbotron: incident?.onJumbotron(at: t) ?? false,
                                     zoomed: jumbo != nil)
        whaleyOver = []
        guard whaleyShown, let j = jumbo, j.isIn(ticks: parameters.ride.whaley.zoomTicks) else { return }
        let screen = self.screen
        let rules = parameters.ride.bubbles
        let configuration = parameters.ride.whaley
        for bubble in bubbles {
            if !bubble.isFrozen || (ball.state == .captured && ball.bubble == bubble.id) { continue }
            guard let cast = planeCast(camera: cam, x: bubble.x, y: bubble.y) else { continue }
            let diameter = bubble.size(rules) * cast.depth * screen.pixelsPerMetre / cam.focal
            let position = screenSpot(u: cast.u, v: cast.v)
            let radius = Fixed(raw: diameter.raw / 2)
            // This only checks screen overlap; the native engine resolves collisions.
            guard position.x + radius >= .zero, position.y + radius >= .zero,
                  position.x - radius <= pixels(configuration.screenWidth),
                  position.y - radius <= pixels(configuration.screenHeight) else { continue }
            whaleyOver.append(WhaleyOver(id: bubble.id, screenX: position.x, screenY: position.y,
                                         size: diameter, moved: bubble.isBeingMoved,
                                         uses: bubble.usesLeft, fixed: bubble.id == j.bubble))
        }
    }

    @discardableResult
    public mutating func step(_ input: StadiumInput) -> StadiumSnapshot {
        let t = tick
        events = []
        caught = []
        consumeWhaley(input.whaleyFrames)
        let p = parameters, r = p.ride
        // Apply parking before projecting touch input because it can reposition the kart.
        if let state = input.repeat { setRepeat(state) }
        if let on = input.parked { setParked(on) }
        doneAsked = input.done
        settleHold()
        deferThoughtForCamera(at: t)
        let cam = camera
        bullpenCart = BullpenCartOnPicture(camera: cam, car: car, bullpenCart: r.bullpenCart)
        if jumbo != nil || interlude != nil { bullpenCart = .none }
        // The phone owns touches during an interlude.
        if interlude == nil { fingerPhase(input.finger, at: t, camera: cam) }
        var i = 0
        while i < bubbles.count {
            if advanceActions(of: i) { bubbles.remove(at: i) } else { i += 1 }
        }
        jumboPhase(camera: cam)
        let beat = r.beat
        tempo = beat.slowBPM + (beat.fastBPM - beat.slowBPM) * level
        let before = beatPhase
        beatPhase += tempo.raw / 3600
        let beatFell = (beatPhase >> 16) != (before >> 16)
        // Score at most once per beat, even when several wheels start bouncing together.
        let started = contacts()
        if !started.isEmpty {
            let frac = beatPhase & 0xFFFF, whole = beatPhase >> 16
            let index: Int64 = frac <= beat.window.raw ? whole : (Fixed.one.raw - beat.window.raw <= frac ? whole + 1 : -1)
            let on = index >= 0
            tally.bounces += 1
            if !on {
                streak = 0
            } else if index != lastBeat {
                streak = index == lastBeat + 1 ? streak + 1 : 1
                lastBeat = index
                tally.onBeat += 1
                tally.points += beat.basePoints * min(streak, beat.streakCap)
                tally.bestStreak = max(tally.bestStreak, streak)
            }
            for s in started { events.append(.hop(wheel: Wheel(rawValue: s.wheel)!, bubble: s.bubble, onBeat: on)) }
        }
        var s = 0
        for k in 0..<4 where hops[k] > 0 { s += Wheel(rawValue: k)!.steer }
        let steer = min(max(s, -1), 1)
        let bouncing = hops.contains { $0 > 0 }
        // Bounces still score while parked or in a camera visit, but cannot drive the kart.
        let railed = parkedAt != nil || jumbo != nil || interlude != nil ? false : drive(steer: steer)
        level = bouncing ? min(.one, level + r.hop.rise) : max(.zero, level - r.hop.fall)
        hops = hops.map { max(0, $0 - 1) }
        let total = track.total
        if Fixed(raw: total.raw / 2) < lastProgress - car.progress {
            lap += 1
            events.append(.lap(lap))
        } else if Fixed(raw: total.raw / 2) < car.progress - lastProgress {
            lap -= 1
            events.append(.lap(lap))
        }
        lastProgress = car.progress
        tally.laps = lap
        unwrapped = total * lap + car.progress
        if repeatState != .off && repeatState != .interlude && turning == .zero && parkedAt == nil && jumbo == nil && interlude == nil {
            if (direction > 0 && unwrapped >= repeatHi) || (direction < 0 && unwrapped <= repeatLo) { startTurnaround() }
        }
        // Rebuild the camera after driving before choosing or tracking world-space targets.
        fadeToward()
        zoomToward()
        let cam2 = camera
        turret = cam2.turret
        interludePhase(at: t, camera: cam2)
        if !(incident?.isLive ?? false) && t >= nextAlarm && interlude == nil && !interludePending { alarm(at: t, camera: cam2) }
        if incident?.isLive == true { watch(at: t, camera: cam2) }
        pitcherWatch(at: t, camera: cam2)
        deferThoughtForCamera(at: t)
        let subject = crewSubject(at: t)
        if subject != crew {
            crew = subject
            events.append(.crew(subject))
        }
        for k in caught.sorted() { cancel(k, at: t, for: p.crowd.catchTicks) }
        let thoughts = self.thoughts, off = called
        let crowdSnapshot = crowd.step(struck: [], caught: caught) { k in
            for (n, s) in thoughts.enumerated() where s.figure == k && !off.contains(n) {
                if let ph = s.phase(at: t) { return ph }
            }
            return nil
        }
        if let inc = incident, inc.isLive, t == inc.end {
            if inc.locked >= 0 {
                remove(inc.locked)
                events.append(.popped(id: inc.locked))
                incident?.locked = -1
            } else if let b = heldBubble, !(ball.state == .captured && ball.bubble == b.id), jumbo?.bubble != b.id {
                remove(b.id)
                events.append(.popped(id: b.id))
            }
            let result: ShotResult = inc.symbol.requiresHotDog ? .missedRequest : .heldFire
            finish(at: t, result: result)
        }
        // Resolve the response deadline before selecting the board program for this frame.
        projectJumbotronBubbles(at: t, camera: cam2)
        var lit = false
        if let inc = incident, inc.isLive { lit = ((t - inc.beep) / r.alarm.flashTicks) % 2 == 0 }
        let pitcher = PitcherSnapshot(inView: inView, fade: fade, crew: crew, engaged: engaged, tossStart: tossStart, ball: ball, runners: runners,
                                      throwInPlay: throwInPlay, attentionFrom: attentionFrom, attentionUntil: attentionUntil)
        let repeatNow = RepeatSnapshot(state: repeatState, lo: repeatLo, hi: repeatHi, direction: direction, turning: turning, unwrapped: unwrapped,
                                       ever: repeatEver, parked: parked, parkedAt: parkedAt, parkedEver: parkedEver)
        let interludeNow = InterludeSnapshot(pending: interludePending, count: interludeCount, on: interlude, next: interludeNext,
                                             gapUntil: interludeGapUntil, ever: interludeEver)
        // Keep the lens dry during phone, Whaley, and fan views, and clear it before the next fan reveal.
        let canSpray = interlude == nil && !interludePending && jumbo == nil
            && !(incident?.onJumbotron(at: t) ?? false) && t + WaterSpray.totalTicks <= nextAlarm
        waterSpraySchedule.advance(at: t, round: interludeNow.round, canBegin: canSpray)
        let ride = RideSnapshot(bubbles: bubbles, bullpenCart: bullpenCart, zoom: zoom, steer: steer, railed: railed, hops: hops, level: level, tempo: tempo,
                                beatPhase: beatPhase, beat: beatFell, streak: streak, lastBeat: lastBeat, lap: lap, nextAlarm: nextAlarm,
                                incident: incident, lit: lit, tally: tally, lastResult: lastResult, lastResultTick: lastResultTick, events: events,
                                pitcher: pitcher, lastThrow: lastThrow, lastThrowTick: lastThrowTick, repeat: repeatNow, whaley: whaleySnapshot,
                                jumbo: JumboSnapshot(zoom: jumbo, on: jumboOn, ever: jumboEver),
                                interlude: interludeNow, waterSpray: waterSpray)
        let snapshot = StadiumSnapshot(tick: t, car: car, crowd: crowdSnapshot, turret: turret, ride: ride)
        StadiumDigest.mix(&digest, snapshot)
        tick += 1
        return snapshot
    }

    public var whaleySnapshot: WhaleySnapshot {
        WhaleySnapshot(inQuadrant: inQuadrant, shown: whaleyShown, engaged: whaleyEngaged, over: whaleyOver, events: whaleyEvents, observation: whaley)
    }
}

public enum StadiumDigest {
    /// Field order is part of the replay digest contract.
    public static func digest(_ snapshots: [StadiumSnapshot]) -> ReplayDigest {
        var d = ReplayDigest()
        for s in snapshots { mix(&d, s) }
        return d
    }

    /// Event code 9 is reserved for the removed facet selection input.
    public static func code(_ e: RideEvent) -> [Int64] {
        switch e {
        case .bubble(let id, let pipe, let x, let y): [1, Int64(id), Int64(pipe), x.raw, y.raw]
        case .grabbed(let id): [2, Int64(id)]
        case .released(let id): [3, Int64(id)]
        case .popped(let id): [4, Int64(id)]
        case .hop(let wheel, let bubble, let onBeat): [5, Int64(wheel.rawValue), Int64(bubble), onBeat ? 1 : 0]
        case .beep(let figure, let garden): [6, Int64(figure), garden ? 1 : 0]
        case .locked(let id): [7, Int64(id)]
        case .unlocked: [8]
        case .fired(let item, let figure, let part, let distance): [10, Int64(item.rawValue), Int64(figure), Int64(part), distance.raw]
        case .result(let result): [11, Int64(result.rawValue)]
        case .lap(let n): [12, Int64(n)]
        case .captured(let id): [13, Int64(id)]
        case .thrown(let how, let speed, let way): [14, Int64(how.rawValue), speed.raw, way.raw]
        case .fielded(let who, let by, let base, let outcome): [15, Int64(who.rawValue), Int64(by), base.map { Int64($0.rawValue) } ?? -1, Int64(outcome.rawValue)]
        case .balk(let type, let points, let until): [16, Int64(type.rawValue), Int64(points), Int64(until)]
        case .newBall(let runners): [17, Int64(runners.count)] + runners.map { Int64($0.rawValue) }
        case .repeat(let state): [19, Int64(state.rawValue)]
        case .turnaround(let direction): [20, Int64(direction)]
        case .crew(let subject): [21, Int64(subject.rawValue)]
        case .parked(let on): [22, on ? 1 : 0]
        case .zoom(let inward, let bubble): [23, inward ? 1 : 0, Int64(bubble)]
        case .interlude(let begun, let fan, let number): [24, begun ? 1 : 0, Int64(fan), Int64(number)]
        }
    }

    public static func mix(_ d: inout ReplayDigest, _ s: StadiumSnapshot) {
        let c = s.car
        d.mix(s.tick); d.mix(c.x); d.mix(c.z); d.mix(c.heading); d.mix(c.yawRate); d.mix(c.speed)
        d.mix(c.progress); d.mix(c.offset); d.mix(c.side); d.mix(c.offTrack)
        CrowdDigest.mix(&d, s.crowd)
        let r = s.ride
        d.mix(s.turret); d.mix(r.zoom); d.mix(r.steer); d.mix(r.railed); d.mix(r.lap)
        for h in r.hops { d.mix(h) }
        d.mix(r.level); d.mix(r.tempo); d.mix(r.beatPhase); d.mix(r.beat); d.mix(r.streak); d.mix(r.lastBeat); d.mix(r.bubbles.count)
        for b in r.bubbles {
            d.mix(b.id); d.mix(b.x); d.mix(b.y); d.mix(b.scale); d.mix(b.isFrozen); d.mix(b.isBeingMoved); d.mix(b.usesLeft)
        }
        d.mix(r.nextAlarm)
        if let inc = r.incident {
            d.mix(inc.beep); d.mix(inc.figure); d.mix(inc.garden); d.mix(inc.symbol.rawValue); d.mix(inc.start); d.mix(inc.end)
            d.mix(inc.aim); d.mix(inc.locked); d.mix(inc.lockTick)
            d.mix(inc.item.rawValue); d.mix(inc.shot); d.mix(inc.ended); d.mix(inc.result.map { $0.rawValue } ?? -1); d.mix(r.lit)
        }
        let ty = r.tally
        d.mix(ty.laps); d.mix(ty.alarms); d.mix(ty.served); d.mix(ty.tooSoon); d.mix(ty.wrong); d.mix(ty.heldFire); d.mix(ty.garden)
        d.mix(ty.bounces); d.mix(ty.onBeat); d.mix(ty.points); d.mix(ty.bestStreak)
        d.mix(r.events.count)
        for e in r.events { for v in code(e) { d.mix(v) } }
        // Mix optional subsystems only after first use, preserving digests for runs that never enter them.
        let pz = r.pitcher
        if pz.engaged {
            let b = pz.ball
            d.mix(pz.inView); d.mix(pz.fade); d.mix(pz.crew.rawValue); d.mix(pz.tossStart); d.mix(b.state.rawValue); d.mix(b.pos); d.mix(b.vel)
            d.mix(b.bubble); d.mix(b.depth); d.mix(b.since); d.mix(b.rolling)
            d.mix(pz.runners.count)
            for base in pz.runners { d.mix(base.rawValue) }
            if let th = pz.throwInPlay {
                d.mix(th.captured); d.mix(th.released); d.mix(th.how.map { $0.rawValue } ?? -1); d.mix(th.speed); d.mix(th.way); d.mix(th.ended)
                d.mix(th.who.rawValue); d.mix(th.by); d.mix(th.base.map { $0.rawValue } ?? -1); d.mix(th.outcome.map { $0.rawValue } ?? -1); d.mix(th.call)
            } else {
                d.mix(-1)
            }
            d.mix(pz.attentionFrom); d.mix(pz.attentionUntil); d.mix(ty.balks); d.mix(ty.balkPoints)
        }
        let rp = r.repeat
        if rp.ever {
            d.mix(rp.state.rawValue); d.mix(rp.direction); d.mix(rp.turning); d.mix(rp.lo); d.mix(rp.hi)
        }
        if rp.parkedEver {
            d.mix(rp.parked); d.mix(rp.parkedAt ?? Fixed(raw: -1))
        }
        let jb = r.jumbo
        if jb.ever {
            d.mix(jb.on)
            if let j = jb.zoom {
                d.mix(1); d.mix(j.bubble); d.mix(j.k); d.mix(j.out); d.mix(j.yaw); d.mix(j.pitch); d.mix(j.zoom)
            } else {
                d.mix(0)
            }
        }
        let il = r.interlude
        if il.ever {
            d.mix(il.pending); d.mix(il.next); d.mix(il.gapUntil); d.mix(il.count)
            if let i = il.on {
                d.mix(1); d.mix(i.fan); d.mix(i.number); d.mix(i.phase.rawValue); d.mix(i.k); d.mix(i.left); d.mix(i.shot)
                d.mix(i.yaw); d.mix(i.pitch); d.mix(i.zoom)
            } else {
                d.mix(0)
            }
        }
        // Water timing is replay state even though it emits no event and consumes no RNG draw.
        if let water = r.waterSpray {
            d.mix(water.round); d.mix(water.startTick)
        }
        let wh = r.whaley
        if wh.engaged {
            d.mix(wh.inQuadrant); d.mix(wh.shown); d.mix(wh.over.count)
            for o in wh.over {
                d.mix(o.id); d.mix(o.screenX); d.mix(o.screenY); d.mix(o.size); d.mix(o.moved); d.mix(o.uses); d.mix(o.fixed)
            }
            d.mix(wh.events.count)
            for e in wh.events { for v in e.integers { d.mix(v) } }
            let state = wh.observation
            d.mix(state.number); d.mix(state.ready); d.mix(Fixed(state.gameTime)); d.mix(state.x); d.mix(state.y)
            d.mix(state.width); d.mix(state.height); d.mix(state.layer.x); d.mix(state.layer.y)
            d.mix(state.dead); d.mix(state.won)
            d.mix(ty.coins); d.mix(ty.goals)
        }
    }
}
