// Scripted hands sample state before each tick; fixtures verify their recorded inputs.

import StadiumCore
import WhaleKartCore
import CrowdCore

public enum StadiumScript {
    public static let rideTicks = 2400
    public static let variantTicks = 1300

    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case ride, right, wrong, early, cancel, none
    }

    /// Seeds are the first at or above the stadium seed that produce each expected result.
    public struct Variant: Hashable, Sendable {
        public var kind: Kind
        public var seed: Int64
        public var result: ShotResult
    }

    public static let variants = [Variant(kind: .right, seed: 20261102, result: .heldFire), Variant(kind: .wrong, seed: 20261101, result: .missedRequest),
                                  Variant(kind: .early, seed: 20261102, result: .heldFire), Variant(kind: .cancel, seed: 20261101, result: .missedRequest),
                                  Variant(kind: .none, seed: 20261101, result: .missedRequest)]

    public static let balkTicks = 3700

    public enum PitcherKind: String, Hashable, Sendable, CaseIterable {
        case plate
        case base
        case pickoff
        case wild
        case drop
        case hold
        /// Use the minimum flick toward the eye so the pitcher can pick up the settled ball.
        case own = "self"
        case cancel
    }

    public static let balkStory = (kind: PitcherKind.plate, seed: Int64(20261101))

    public struct BalkVariant: Hashable, Sendable {
        public var kind: PitcherKind
        public var outcome: ThrowOutcome
    }

    public static let balkVariants = [BalkVariant(kind: .base, outcome: .unoccupiedBase), BalkVariant(kind: .pickoff, outcome: .pickoff),
                                      BalkVariant(kind: .wild, outcome: .noBall), BalkVariant(kind: .drop, outcome: .dropped),
                                      BalkVariant(kind: .hold, outcome: .noBall), BalkVariant(kind: .own, outcome: .hisOwn),
                                      BalkVariant(kind: .cancel, outcome: .dropped)]

    /// Spawn above the ball to clear the wheels, then carry the bubble onto it.
    public struct PitcherHand: Sendable {
        enum Stage: Sendable { case wait, shot, press, carry, captured, done }

        public let kind: PitcherKind
        var stage = Stage.wait
        var at = 0
        var x = Fixed.zero
        var y = Fixed.zero
        var flick: (ux: Fixed, uy: Fixed, perTick: Fixed)?
        var stepIndex = 0

        public init(_ kind: PitcherKind) { self.kind = kind }

        func targetFielder(_ game: StadiumGame) -> Fielder? {
            switch kind {
            case .plate:
                return Fielder.all.first { $0.name == "catcher" }
            case .base:
                for base in [Base.third, .second] where !game.runners.contains(base) {
                    return Fielder.all.first { $0.who == .atBase && $0.base == base }
                }
                return nil
            case .pickoff:
                for base in [Base.first, .second, .third] where game.runners.contains(base) {
                    return Fielder.all.first { $0.who == .atBase && $0.base == base }
                }
                return nil
            default:
                return nil
            }
        }

        /// Invert the flick compass and solve the launch range to aim at a fielder.
        /// A nil plan drops the ball.
        func planFlick(_ game: StadiumGame, camera cam: TurretCamera) -> (ux: Fixed, uy: Fixed, perTick: Fixed)? {
            let pz = game.parameters.ride.pitcher
            let ball = game.ball.pos
            if let f = targetFielder(game) {
                let dx = f.x - ball.x, dz = f.z - ball.z
                let c = cam.compass
                let across = dx * c.rightX + dz * c.rightZ
                let away = dx * c.forwardX + dz * c.forwardZ
                let px = across, py = -(away / pz.depthGain)
                let d = Fixed.sqrt(px * px + py * py)
                let run = PicturePoint(x: ball.x, y: ball.z).distance(to: PicturePoint(x: f.x, y: f.z))
                var speed = Fixed.sqrt((run * (pz.gravity * 60)) / Trig.sin(Fixed(raw: pz.launch.raw << 1)))
                speed = min(speed, pz.maxSpeed)
                return (px / d, py / d, speed / pz.speedPerPoint)
            }
            if kind == .own { return (.zero, .one, pz.flickMin) }
            if kind == .wild { return (-Fixed(0.7071), -Fixed(0.7071), pz.maxSpeed / pz.speedPerPoint) }
            return nil
        }

        static let none = StadiumInput.none
        static func input(_ phase: TouchPhase, _ x: Fixed, _ y: Fixed) -> StadiumInput { StadiumInput(finger: FingerInput(phase: phase, x: x, y: y)) }

        public mutating func input(_ game: StadiumGame, at t: Int) -> StadiumInput {
            let pz = game.parameters.ride.pitcher
            let w = game.parameters.picture.width
            if stage == .done { return Self.none }
            let cam = game.camera
            switch stage {
            case .wait:
                guard let m = cam.project(pz.point(pz.middle)), Fixed(80.0) <= m.x, m.x <= w - Fixed(80.0), game.ball.state == .tossing,
                      let q = game.ballOnPicture(camera: cam) else { return Self.none }
                (x, y) = (q.x, q.y - Fixed(90.0))
                stage = .shot
                at = t + 2
                return Self.input(.began, x, y)
            case .shot:
                guard t == at else { return Self.none }
                stage = .press
                at = t + 12
                return Self.input(.ended, x, y)
            case .press:
                guard t == at else { return Self.none }
                guard let b = game.bubbles.last else {
                    stage = .done
                    return Self.none
                }
                (x, y) = (b.x, b.y)
                stage = .carry
                at = t + 400
                return Self.input(.began, x, y)
            case .carry:
                if game.ball.state == .captured {
                    stage = .captured
                    stepIndex = 0
                    at = t + (kind == .hold ? pz.holdLimit + 30 : 12)
                    return Self.none
                }
                if t >= at || game.ball.state != .tossing {
                    stage = .done
                    return Self.input(.ended, x, y)
                }
                guard let q = game.ballOnPicture(camera: cam) else { return Self.none }
                (x, y) = StadiumScript.toward(x, y, q.x, q.y, Fixed(30.0))
                return Self.input(.moved, x, y)
            case .captured:
                if game.ball.state != .captured {
                    stage = .done
                    return kind == .hold ? Self.input(.ended, x, y) : Self.none
                }
                if t < at { return Self.none }
                if kind == .cancel {
                    stage = .done
                    return Self.input(.cancelled, x, y)
                }
                if stepIndex == 0 { flick = planFlick(game, camera: cam) }
                guard let flick else {
                    stage = .done
                    return Self.input(.ended, x, y)
                }
                (x, y) = (x + flick.ux * flick.perTick, y + flick.uy * flick.perTick)
                stepIndex += 1
                if stepIndex == pz.flickTicks {
                    stage = .done
                    return Self.input(.ended, x, y)
                }
                return Self.input(.moved, x, y)
            case .done:
                return Self.none
            }
        }
    }

    public static let whaleyTicks = 2400
    public static let whaleyVariantTicks = 700

    public enum WhaleyKind: String, Hashable, Sendable, CaseIterable {
        case story
        /// Landing without carrying does not trigger the zoom needed to share the bubble.
        case land
        case lift
        case push
        case middle
        case release
        case flame
        case once
        case none

        var acts: [WhaleyHand.Act] {
            switch self {
            case .story: [.climb, .push, .middle, .release, .carry, .flame, .release]
            case .lift: [.lift, .lift, .lift, .release]
            case .push: [.push, .release]
            case .middle: [.middle, .release]
            case .release: [.release]
            case .flame: [.flame, .release]
            case .once: [.lift, .release]
            case .land, .none: []
            }
        }
    }

    public static let whaleyStory = (kind: WhaleyKind.story, seed: Int64(20261101))
    public static let whaleyVariants: [WhaleyKind] = [.land, .lift, .push, .middle, .release, .flame, .none]

    public struct WhaleyHand: Sendable {
        enum Stage: Sendable { case wait, up, shot, take, carry, act, between, done }
        enum Act: Sendable { case climb, lift, push, middle, release, carry, flame }
        enum Step: Sendable { case go, under, rise, drop, into }

        static let pushHold = 90
        static let middleHold = 60
        static let climbJumps = 5

        public let kind: WhaleyKind
        var stage = Stage.wait
        var at = 0
        var x = Fixed.zero
        var y = Fixed.zero
        var side = -1
        var acts: [Act]
        var step = Step.go
        var jumps = 0
        var room = -1
        var flameSide = 1
        var still = 0
        var lastX = Fixed.zero

        public init(_ kind: WhaleyKind) {
            self.kind = kind
            acts = kind.acts
        }

        public var isDone: Bool { stage == .done || kind == .none }

        static let none = StadiumInput.none
        static func input(_ phase: TouchPhase, _ x: Fixed, _ y: Fixed) -> StadiumInput { StadiumInput(finger: FingerInput(phase: phase, x: x, y: y)) }

        /// Offsets are measured from Whaley in level coordinates.
        func point(_ game: StadiumGame, camera cam: TurretCamera, dx: Fixed, dy: Fixed) -> PicturePoint? {
            let w = game.whaley
            return game.screenPoint(camera: cam, x: w.centreX + dx, y: w.centreY + dy)
        }

        /// up is measured from the visible screen bottom, after the native camera offset.
        func windowPoint(_ game: StadiumGame, camera cam: TurretCamera, dx: Fixed, up: Fixed) -> PicturePoint? {
            let w = game.whaley
            return game.screenPoint(camera: cam, x: w.centreX + dx, y: up - w.layer.y)
        }

        func onPicture(_ game: StadiumGame, _ q: PicturePoint?) -> Bool {
            let pic = game.parameters.picture
            guard let q else { return false }
            return .zero <= q.x && q.x <= pic.width && .zero <= q.y && q.y <= pic.height
        }

        mutating func tap(at t: Int, _ q: PicturePoint, then next: Stage) -> StadiumInput {
            (x, y) = (q.x, q.y)
            stage = next
            at = t + 2
            return Self.input(.began, x, y)
        }

        mutating func move(_ q: PicturePoint?, _ by: Fixed) -> StadiumInput {
            if let q { (x, y) = StadiumScript.toward(x, y, q.x, q.y, by) }
            return Self.input(.moved, x, y)
        }

        func jumped(_ game: StadiumGame) -> Bool {
            game.whaleyEvents.contains { e in
                if case .bubbleContact(_, _, _, let bounced) = e { return bounced }
                return false
            }
        }

        func near(_ q: PicturePoint?) -> Bool {
            guard let q else { return false }
            return PicturePoint(x: x, y: y).distance(to: q) <= Fixed(2.0)
        }

        public mutating func input(_ game: StadiumGame, at t: Int) -> StadiumInput {
            if stage == .done || kind == .none { return Self.none }
            let cam = game.camera
            let w = game.whaley
            let zt = game.parameters.ride.whaley.zoomTicks
            switch stage {
            case .wait:
                guard game.whaleyShown, !w.dead, !w.won, w.ready, t >= at, t >= 200, game.jumbo == nil else { return Self.none }
                if kind == .land {
                    let q = point(game, camera: cam, dx: -Fixed(36.0), dy: -Fixed(30.0))
                    guard onPicture(game, q), let q else { return Self.none }
                    return tap(at: t, q, then: .up)
                }
                room = w.centreX + w.layer.x > pixels(game.parameters.ride.whaley.screenWidth / 2) ? -1 : 1
                let q = windowPoint(game, camera: cam, dx: Fixed(100.0) * room, up: -Fixed(70.0))
                guard onPicture(game, q), let q else { return Self.none }
                return tap(at: t, q, then: .shot)
            case .up:
                guard t == at else { return Self.none }
                stage = .done
                return Self.input(.ended, x, y)
            case .shot:
                guard t == at else { return Self.none }
                stage = .take
                at = t + 14
                return Self.input(.ended, x, y)
            case .take:
                guard t >= at else { return Self.none }
                guard let b = game.bubbles.last, b.isFrozen else {
                    stage = .done
                    return Self.none
                }
                (x, y) = (b.x, b.y)
                stage = .carry
                return Self.input(.began, x, y)
            case .carry:
                guard game.heldBubble != nil else {
                    stage = .done
                    return Self.none
                }
                if let j = game.jumbo {
                    if j.k < zt { return Self.none }
                    stage = .act
                    step = .go
                    at = t
                    return Self.none
                }
                return move(windowPoint(game, camera: cam, dx: Fixed(100.0) * room, up: Fixed(10.0)), Fixed(12.0))
            case .act:
                return act(game, camera: cam, at: t)
            case .between:
                stage = .act
                return Self.none
            case .done:
                return Self.none
            }
        }

        mutating func act(_ game: StadiumGame, camera cam: TurretCamera, at t: Int) -> StadiumInput {
            let w = game.whaley
            let act = acts.first ?? .release
            switch act {
            case .release:
                if !acts.isEmpty { acts.removeFirst() }
                stage = acts.isEmpty ? .done : .between
                at = t + 60
                return Self.input(.ended, x, y)
            case .carry:
                if game.jumbo == nil && w.ready && !w.dead && t >= at {
                    acts.removeFirst()
                    stage = .wait
                }
                return Self.none
            default:
                break
            }
            guard game.heldBubble != nil, game.jumbo != nil else {
                stage = .done
                return Self.none
            }
            switch act {
            case .climb:
                if step == .go {
                    let q = point(game, camera: cam, dx: Fixed(40.0) * side, dy: -Fixed(120.0))
                    if near(q) { step = .under }
                    return move(q, Fixed(12.0))
                }
                if jumped(game) {
                    jumps += 1
                    side = -side
                    if jumps >= Self.climbJumps {
                        acts.removeFirst()
                        step = .go
                        jumps = 0
                        return Self.none
                    }
                }
                return move(point(game, camera: cam, dx: Fixed(40.0) * side, dy: -Fixed(70.0)), Fixed(12.0))
            case .lift:
                if step == .go {
                    let q = point(game, camera: cam, dx: Fixed(40.0) * side, dy: -Fixed(120.0))
                    if near(q) { step = .rise }
                    return move(q, Fixed(12.0))
                }
                if step == .rise {
                    if jumped(game) {
                        jumps += 1
                        step = .drop
                        at = t + 30
                    }
                    return move(point(game, camera: cam, dx: Fixed(40.0) * side, dy: -Fixed(60.0)), Fixed(3.0))
                }
                if t >= at && w.ready {
                    acts.removeFirst()
                    step = .go
                    if kind == .story { side = -side }
                }
                return move(point(game, camera: cam, dx: Fixed(40.0) * side, dy: -Fixed(140.0)), Fixed(12.0))
            case .push, .flame:
                var toward = act == .push ? -1 : flameSide
                if step == .go {
                    let q = point(game, camera: cam, dx: Fixed(120.0) * toward, dy: .zero)
                    if near(q) {
                        step = .into
                        at = t + (act == .push ? Self.pushHold : 0)
                        still = 0
                        lastX = w.x
                    }
                    return move(q, Fixed(12.0))
                }
                if (act == .push && t >= at) || (act == .flame && w.dead) {
                    acts.removeFirst()
                    step = .go
                    at = t + 30
                    return Self.none
                }
                if act == .flame {
                    // Switch sides after a second against a wall so the flame script can continue.
                    still = w.x == lastX && w.ready ? still + 1 : 0
                    lastX = w.x
                    if still >= 60 {
                        flameSide = -flameSide
                        still = 0
                        toward = flameSide
                    }
                }
                return move(point(game, camera: cam, dx: Fixed(70.0) * toward, dy: .zero), Fixed(12.0))
            case .middle:
                if step == .go {
                    let q = point(game, camera: cam, dx: -Fixed(120.0), dy: .zero)
                    if near(q) {
                        step = .into
                        at = t + Self.middleHold
                    }
                    return move(q, Fixed(12.0))
                }
                if t >= at {
                    acts.removeFirst()
                    step = .go
                    return Self.none
                }
                return move(point(game, camera: cam, dx: .zero, dy: .zero), Fixed(12.0))
            case .release, .carry:
                return Self.none
            }
        }
    }

    public struct RepeatRun: Hashable, Sendable {
        public var kind: String
        public var toggles: [Int: RepeatState]
        public var parks: [Int: Bool] = [:]
        public var ticks: Int
    }

    public static let repeatRuns = [RepeatRun(kind: "cannon", toggles: [0: .cannon], ticks: 6600),
                                    RepeatRun(kind: "pitcher", toggles: [0: .pitcher], ticks: 5400),
                                    RepeatRun(kind: "toggle", toggles: [0: .pitcher, 3600: .off], ticks: 4800),
                                    RepeatRun(kind: "whaley", toggles: [0: .whaley], ticks: 3000),
                                    RepeatRun(kind: "cannon-static", toggles: [0: .cannon], parks: [0: true], ticks: 1800),
                                    RepeatRun(kind: "whaley-static", toggles: [0: .whaley], parks: [0: true], ticks: 1200),
                                    RepeatRun(kind: "pitcher-static", toggles: [0: .pitcher], parks: [0: true], ticks: 1500),
                                    RepeatRun(kind: "static", toggles: [0: .cannon, 600: .pitcher, 1800: .off], parks: [0: true, 900: false, 1500: true],
                                              ticks: 2400)]

    public static func repeatInputs(toggles: [Int: RepeatState], parks: [Int: Bool] = [:], dones: Set<Int> = [], ticks: Int) -> [StadiumInput] {
        (0..<ticks).map { t in StadiumInput(finger: .none, repeat: toggles[t], parked: parks[t], done: dones.contains(t)) }
    }

    public static func pitcherInputs(kind: PitcherKind, parameters p: StadiumParameters = .stadium, ticks: Int = balkTicks) -> [StadiumInput] {
        var game = StadiumGame(parameters: p)
        var hand = PitcherHand(kind)
        var out: [StadiumInput] = []
        out.reserveCapacity(ticks)
        for t in 0..<ticks {
            let input = hand.input(game, at: t)
            out.append(input)
            game.step(input)
        }
        return out
    }

    public static func balkParameters(_ p: StadiumParameters = .stadium) -> StadiumParameters {
        var q = p
        q.seed = balkStory.seed
        return q
    }

    public static func toward(_ x: Fixed, _ y: Fixed, _ tx: Fixed, _ ty: Fixed, _ step: Fixed) -> (Fixed, Fixed) {
        let d = PicturePoint(x: x, y: y).distance(to: PicturePoint(x: tx, y: ty))
        if d <= step { return (tx, ty) }
        return (x + ((tx - x) * step) / d, y + ((ty - y) * step) / d)
    }

    public struct Hand: Sendable {
        enum Stage: Sendable { case start, shot, press, pumpOut, pumpIn, wait, dollShot, dollPress, carry, locked, done }

        public let kind: Kind
        var stage = Stage.start
        var at = 0
        var x = Fixed.zero
        var y = Fixed.zero
        var dolls = 0
        var pumps = 0
        var wheelIndex = -1

        public init(_ kind: Kind) { self.kind = kind }

        func wheels(_ game: StadiumGame) -> [PictureRect?] {
            BullpenCartOnPicture(camera: game.camera, car: game.car, bullpenCart: game.parameters.ride.bullpenCart).wheels
        }

        func lowest(_ game: StadiumGame) -> Int {
            let w = wheels(game)
            var best = -1
            for (k, r) in w.enumerated() {
                if let r, best < 0 || w[best]!.y + w[best]!.h < r.y + r.h { best = k }
            }
            return best
        }

        static let none = StadiumInput.none
        static func input(_ phase: TouchPhase, _ x: Fixed, _ y: Fixed) -> StadiumInput { StadiumInput(finger: FingerInput(phase: phase, x: x, y: y)) }

        mutating func pump(_ game: StadiumGame, at t: Int) -> StadiumInput {
            guard let rect = wheels(game)[wheelIndex] else {
                stage = .wait
                return Self.input(.ended, x, y)
            }
            let radius = Fixed(raw: game.parameters.ride.bubbles.image.raw >> 1)
            let bottom = rect.y + rect.h
            let out = (rect.midX, bottom + radius + Fixed(24.0))
            let inn = (rect.midX, bottom + radius - Fixed(12.0))
            let next = (game.beatPhase + game.tempo.raw / 3600) & 0xFFFF
            let nearBeat = next >= Fixed.one.raw - 3000 || next <= 3000
            let midBeat = abs(next - (Fixed.one.raw >> 1)) <= 3000
            if stage == .pumpOut {
                let wantIn = game.hops[wheelIndex] == 0 && ((nearBeat && pumps != 3) || (midBeat && pumps == 3))
                if t >= at && wantIn {
                    stage = .pumpIn
                    at = t + 10
                    pumps += 1
                    (x, y) = inn
                    return Self.input(.moved, inn.0, inn.1)
                }
                (x, y) = out
                return Self.input(.moved, out.0, out.1)
            }
            if t >= at {
                if pumps >= 5 {
                    stage = .wait
                    return Self.input(.ended, out.0, out.1)
                }
                stage = .pumpOut
                at = t + 8
                (x, y) = out
                return Self.input(.moved, out.0, out.1)
            }
            (x, y) = inn
            return Self.input(.moved, inn.0, inn.1)
        }

        /// Keep the spawn tap clear of the turret.
        func dollTap(_ game: StadiumGame, _ head: PicturePoint) -> (Fixed, Fixed) {
            let a = game.parameters.ride.alarm
            let top = game.camera.project(kartPoint(game.car, right: .zero, forward: .zero, up: a.clearHeight))
            var y = head.y + Fixed(100.0)
            if let top, top.y - Fixed(70.0) < y { y = head.y - Fixed(100.0) }
            return (head.x, y)
        }

        public mutating func input(_ game: StadiumGame, at t: Int) -> StadiumInput {
            if stage == .done { return Self.none }
            if kind == .ride && stage == .start && t <= 30 {
                guard t == 30 else { return Self.none }
                wheelIndex = lowest(game)
                let rect = wheels(game)[wheelIndex]!
                (x, y) = (rect.midX, rect.y + rect.h + Fixed(90.0))
                stage = .shot
                at = t + 3
                return Self.input(.began, x, y)
            }
            if stage == .shot {
                guard t == at else { return Self.none }
                stage = .press
                at = t + 12
                return Self.input(.ended, x, y)
            }
            if stage == .press {
                guard t == at else { return Self.none }
                guard let b = game.bubbles.last else {
                    stage = .wait
                    return Self.none
                }
                (x, y) = (b.x, b.y)
                stage = .pumpOut
                at = t + 8
                return Self.input(.began, x, y)
            }
            if stage == .pumpOut || stage == .pumpIn { return pump(game, at: t) }
            if kind == .none { return Self.none }
            let inc = game.incident
            if stage == .start || stage == .wait {
                let most = kind == .ride ? 2 : 1
                guard let inc, inc.isLive, inc.locked < 0, t >= inc.beep + 5, dolls < most else { return Self.none }
                guard let head = game.camera.point(game.figures[inc.figure].head) else { return Self.none }
                dolls += 1
                (x, y) = dollTap(game, head)
                stage = .dollShot
                at = t + 2
                return Self.input(.began, x, y)
            }
            guard let inc, inc.isLive else {
                if stage == .carry || stage == .locked {
                    stage = .wait
                    return Self.input(.ended, x, y)
                }
                stage = .wait
                return Self.none
            }
            let head = game.camera.point(game.figures[inc.figure].head)
            if stage == .dollShot {
                guard t == at else { return Self.none }
                stage = .dollPress
                at = t + 12
                return Self.input(.ended, x, y)
            }
            if stage == .dollPress {
                guard t == at else { return Self.none }
                guard let b = game.bubbles.last else {
                    stage = .wait
                    return Self.none
                }
                (x, y) = (b.x, b.y)
                stage = .carry
                at = t + 6
                return Self.input(.began, x, y)
            }
            if stage == .carry {
                if inc.locked >= 0 {
                    stage = .locked
                } else if let head, t >= at {
                    if kind == .early && PicturePoint(x: x, y: y).distance(to: head) <= Fixed(60.0) {
                        stage = .done
                        return Self.input(.ended, x, y)
                    }
                    (x, y) = StadiumScript.toward(x, y, head.x, head.y, Fixed(20.0))
                    return Self.input(.moved, x, y)
                } else {
                    return Self.none
                }
            }
            if stage == .locked {
                if kind == .cancel {
                    guard t >= inc.beep + 200 else { return Self.none }
                    stage = .done
                    return Self.input(.cancelled, x, y)
                }
                if fires(inc) && t >= inc.start + 20 {
                    stage = .wait
                    return Self.input(.ended, x, y)
                }
                return Self.none
            }
            return Self.none
        }

        func fires(_ inc: Incident) -> Bool {
            let wrong = kind == .wrong || (kind == .ride && dolls == 2)
            return wrong ? !inc.symbol.requiresHotDog : inc.symbol.requiresHotDog
        }
    }

    public static func inputs(kind: Kind = .ride, parameters p: StadiumParameters = .stadium, ticks: Int? = nil) -> [StadiumInput] {
        let n = ticks ?? (kind == .ride ? rideTicks : variantTicks)
        var game = StadiumGame(parameters: p)
        var hand = Hand(kind)
        var out: [StadiumInput] = []
        out.reserveCapacity(n)
        for t in 0..<n {
            let input = hand.input(game, at: t)
            out.append(input)
            game.step(input)
        }
        return out
    }

    public static func parameters(_ v: Variant, _ p: StadiumParameters = .stadium) -> StadiumParameters {
        var q = p
        q.seed = v.seed
        return q
    }

    public static func recording(kind: Kind = .ride, parameters p: StadiumParameters = .stadium, ticks: Int? = nil) -> StadiumRecording {
        StadiumRecording(parameters: p, inputs: inputs(kind: kind, parameters: p, ticks: ticks))
    }
}
