import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Observation
#if canImport(simd)
import simd
#endif
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame

@MainActor
@Observable
final class StadiumSession {
    private(set) var parameters: StadiumParameters
    private(set) var game: StadiumGame
    private(set) var snapshot: StadiumSnapshot
    private(set) var recording: StadiumRecording

    var tick: Int { snapshot.tick }
    private(set) var playID = 0

    // Preserve touch phases, coalescing adjacent moves; consume one phase per simulation tick.
    private var queue: [FingerInput] = []
    private(set) var fingerDown = false
    private(set) var finger: CGPoint?
    private var scripted = false
    private var assist: Assist?
    private var whaleyAssist: WhaleyAssist?
    private var pendingRepeat: RepeatState?
    private var pendingParked: Bool?
    private var pendingDone = false

    @ObservationIgnored private(set) var viewSize = SIMD2<Float>(390, 844)
    var map: RideRig.PictureMap { RideRig.PictureMap(picture: parameters.picture, viewSize: viewSize) }

    private(set) var lastFlight: (tick: Int, from: SIMD3<Float>, to: SIMD3<Float>, item: Item)?
    private(set) var lastPops: [(tick: Int, point: CGPoint, radius: Double)] = []
    private(set) var filmPhase = 0.0

    // Only the phone's snapshot feed reads this log, so appending moments need not redraw the ride.
    @ObservationIgnored private(set) var moments = MomentLog()
    private(set) var phone: PhoneFeed?
    @ObservationIgnored private var phoneStroke: (down: Int, last: CGPoint, travel: Double, tab: PhoneTab)?
    @ObservationIgnored private var phoneTab = PhoneTab.stats
    @ObservationIgnored private(set) var phoneHand = RideRig.PhoneHand()

    let audio = StadiumAudio()
    private var outputChosen: AudioOutput = .headphones
    var audioOutput: AudioOutput {
        get { outputChosen }
        set { outputChosen = newValue; audio.output = newValue }
    }
    private var timer: Timer?
    private(set) var isRunning = false
    private(set) var whaleySessionID = UUID().uuidString
    private var pendingWhaleyFrames: [JumbotronFrame] = []
    private var lastReceivedWhaleySequence = -1
    #if canImport(UIKit)
    let explorer = StadiumExplorerStore()
    #endif

    init() {
        let p = Self.play(.stadium)
        var fresh = StadiumGame(parameters: p)
        let first = fresh.step(.none)
        parameters = p
        game = fresh
        snapshot = first
        recording = StadiumRecording(parameters: p, inputs: [.none])
        refreshMenu()
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        // Keep simulation time advancing while menus track a finger.
        RunLoop.main.add(t, forMode: .common)
        timer = t
        isRunning = true
    }

    func stop() { timer?.invalidate(); timer = nil; isRunning = false; audio.silence() }

    // Generate randomness outside the core and record the seed for replay.
    static func play(_ base: StadiumParameters) -> StadiumParameters {
        var p = base
        p.seed = Int64.random(in: 1...Int64(Int32.max))
        return p
    }

    static func base(_ size: SIMD2<Float>) -> StadiumParameters {
        StadiumParameters.stadium.picture(width: Fixed(Double(size.x)), height: Fixed(Double(size.y)))
    }

    func reset(to p: StadiumParameters) {
        let running = timer != nil
        stop()
        var fresh = StadiumGame(parameters: p)
        let first = fresh.step(.none)
        parameters = p
        game = fresh
        snapshot = first
        recording = StadiumRecording(parameters: p, inputs: [.none])
        queue = []; fingerDown = false; finger = nil; scripted = false; assist = nil; whaleyAssist = nil; pendingRepeat = nil; pendingParked = nil
        pendingDone = false
        pendingWhaleyFrames = []; lastReceivedWhaleySequence = -1; whaleySessionID = UUID().uuidString
        lastFlight = nil; lastPops = []; filmPhase = 0
        moments = MomentLog(); phone = nil; phoneStroke = nil; phoneTab = .stats; phoneHand = RideRig.PhoneHand()
        refreshMenu()
        playID += 1
        if running { start() }
    }

    func playAgain() { reset(to: Self.play(Self.base(viewSize))) }

    // Publish menu changes separately to avoid invalidating the menu every simulation tick.
    private(set) var menuTally: [RideRig.MenuLine] = []
    private(set) var repeatState: RepeatState = .off
    private(set) var parked = false
    func setRepeat(_ state: RepeatState) { pendingRepeat = state; refreshMenu() }
    func setParked(_ on: Bool) { pendingParked = on; refreshMenu() }

    private func refreshMenu() {
        let tally = RideRig.menuTally(snapshot, parameters: parameters)
        if tally != menuTally { menuTally = tally }
        let state = pendingRepeat ?? snapshot.ride.repeat.state
        if state != repeatState { repeatState = state }
        let on = pendingParked ?? snapshot.ride.repeat.parked
        if on != parked { parked = on }
    }

    // Adopt the first layout only before play starts; later resizes preserve the recorded picture.
    func viewResized(_ size: SIMD2<Float>) {
        guard size.x > 0, size.y > 0, size != viewSize else { return }
        viewSize = size
        let picture = PictureParameters(width: Fixed(Double(size.x)), height: Fixed(Double(size.y)))
        if picture != parameters.picture && tick < 120 && recording.inputs.allSatisfy({
            $0.finger.phase == .none && $0.repeat == nil && $0.parked == nil && !$0.done
        }) {
            reset(to: Self.play(Self.base(size)))
        }
    }

    var camera: PinholeCamera { Cameras.view(snapshot, parameters: parameters, figures: game.figures) }

    var crew: PinholeCamera? { Cameras.crew(snapshot, figures: game.figures) }

    var crewLive: PinholeCamera? {
        switch snapshot.ride.pitcher.crew {
        case .ball: Cameras.crewBall(snapshot)
        case .pitcher: Cameras.crewPitcher(parameters: parameters)
        case .fan: Cameras.crewFan(snapshot, figures: game.figures, parameters: parameters)
        case .free: nil
        }
    }

    private func input(_ phase: TouchPhase, _ p: CGPoint) -> FingerInput {
        let q = map.picture(p)
        return FingerInput(phase: phase, x: q.x, y: q.y)
    }

    @discardableResult
    func fingerBegan(at p: CGPoint) -> Bool {
        guard !fingerDown, !scripted, assist == nil, whaleyAssist == nil, snapshot.ride.interlude.on == nil else { return false }
        fingerDown = true
        finger = p
        queue.append(input(.began, p))
        return true
    }

    func fingerMoved(to p: CGPoint) {
        guard fingerDown else { return }
        finger = p
        let move = input(.moved, p)
        if let last = queue.last, last.phase == .moved { queue[queue.count - 1] = move } else { queue.append(move) }
    }

    func fingerEnded(at p: CGPoint) {
        guard fingerDown else { return }
        fingerDown = false
        finger = nil
        queue.append(input(.ended, p))
    }

    // Cancellation must release a locked bubble without firing it.
    func fingerCancelled() {
        guard fingerDown else { return }
        let p = finger ?? .zero
        fingerDown = false
        finger = nil
        queue.append(input(.cancelled, p))
    }

    func releaseEverything() { fingerCancelled() }

    private func touch(_ phase: TouchPhase, _ x: Fixed, _ y: Fixed) -> FingerInput { FingerInput(phase: phase, x: x, y: y) }

    var acceptsStroke: Bool { !fingerDown && !scripted && assist == nil && whaleyAssist == nil && snapshot.ride.interlude.on == nil }

    private func stroke(_ inputs: [FingerInput]) {
        guard acceptsStroke, !inputs.isEmpty else { return }
        queue += inputs
        scripted = true
    }

    // Avoid pipes and other wheels so the assisted bubble bounces only the selected rear wheel.
    func accessibleBounce(left: Bool) {
        let on = BullpenCartOnPicture(camera: game.camera, car: game.car, bullpenCart: parameters.ride.bullpenCart)
        let k = left ? Wheel.rearLeft.rawValue : Wheel.rearRight.rawValue
        guard let wheel = on.wheels[k] else { return }
        let present = on.wheels.compactMap { $0 }
        let cx = present.map(\.midX.double).reduce(0, +) / Double(present.count)
        let cy = present.map(\.midY.double).reduce(0, +) / Double(present.count)
        let mx = wheel.midX.double, my = wheel.midY.double
        let away = atan2(my - cy, mx - cx)
        let small = parameters.ride.bubbles.small.double, reach = wheel.w.double / 2 + 8
        func gap(_ r: PictureRect, _ x: Double, _ y: Double) -> Double {
            let dx = max(r.x.double - x, 0, x - r.maxX.double), dy = max(r.y.double - y, 0, y - r.maxY.double)
            return (dx * dx + dy * dy).squareRoot()
        }
        var spot: (Double, Double)?
        for i in 0..<16 {
            let a = away + Double((i + 1) / 2) * Double.pi / 8 * (i % 2 == 0 ? 1 : -1)
            let x = mx + cos(a) * reach, y = my + sin(a) * reach
            let clearOfPipes = on.pipes.allSatisfy { q in
                guard let q else { return true }
                let dx = q.x.double - x, dy = q.y.double - y
                return (dx * dx + dy * dy).squareRoot() > small + 4
            }
            let clearOfWheels = on.wheels.enumerated().allSatisfy { j, r in
                guard j != k, let r else { return true }
                return gap(r, x, y) > small / 2 + 4
            }
            if clearOfPipes && clearOfWheels { spot = (x, y); break }
        }
        let (x, y) = spot ?? (mx + cos(away) * reach, my + sin(away) * reach)
        stroke([touch(.began, Fixed(x), Fixed(y)), .none, touch(.ended, Fixed(x), Fixed(y))])
    }

    // Limit the scripted lift to ten seconds; release it if another program takes the Jumbotron.
    func accessibleWhaley() {
        guard acceptsStroke, game.whaleyShown else { return }
        whaleyAssist = WhaleyAssist(hand: StadiumScript.WhaleyHand(.once), until: game.tick + 600)
    }

    private struct WhaleyAssist {
        var hand: StadiumScript.WhaleyHand
        var until: Int
        var x = Fixed.zero
        var y = Fixed.zero
        var down = false
    }

    private func whaleyAssistInput() -> FingerInput {
        guard var a = whaleyAssist else { return .none }
        guard game.tick < a.until, game.jumbo != nil || game.whaleyShown else {
            whaleyAssist = nil
            return a.down ? touch(.ended, a.x, a.y) : .none
        }
        let f = a.hand.input(game, at: game.tick).finger
        switch f.phase {
        case .began, .moved: (a.x, a.y, a.down) = (f.x, f.y, true)
        case .ended, .cancelled: a.down = false
        case .none: break
        }
        guard a.hand.isDone else {
            whaleyAssist = a
            return f
        }
        // The script may finish with its finger down after losing its bubble.
        whaleyAssist = nil
        return a.down && f.phase == .none ? touch(.ended, a.x, a.y) : f
    }

    func accessibleShot() {
        guard acceptsStroke, let inc = game.incident, inc.isLive,
              snapshot.tick >= inc.start, game.tick < inc.end else { return }
        assist = Assist()
    }

    private struct Assist {
        var step = 0
        var x = Fixed.zero
        var y = Fixed.zero
        var down = false
    }

    private func assistInput() -> FingerInput {
        guard var a = assist else { return .none }
        guard let inc = game.incident, inc.isLive, let head = game.camera.point(game.figures[inc.figure].head) else {
            assist = nil
            return a.down ? touch(.ended, a.x, a.y) : .none
        }
        // Gate assistance on the visible program; background baseball must not block a fan response.
        if !RideRig.jumbotron(snapshot, parameters: parameters).isCrew || game.tick < inc.start {
            return .none
        }
        var out = FingerInput.none
        switch a.step {
        case 0:
            let top = game.camera.project(kartPoint(game.car, right: .zero, forward: .zero, up: parameters.ride.alarm.clearHeight))
            a.x = head.x
            a.y = head.y + Fixed(100.0)
            if let top, top.y - Fixed(70.0) < a.y { a.y = head.y - Fixed(100.0) }
            out = touch(.began, a.x, a.y)
        case 2:
            out = touch(.ended, a.x, a.y)
        case 14:
            guard let b = game.bubbles.last else { assist = nil; return .none }
            a.x = b.x; a.y = b.y; a.down = true
            out = touch(.began, a.x, a.y)
        case 15...:
            if inc.locked < 0 {
                (a.x, a.y) = StadiumScript.toward(a.x, a.y, head.x, head.y, Fixed(20.0))
                out = touch(.moved, a.x, a.y)
            } else {
                assist = nil
                return touch(.ended, a.x, a.y)
            }
        default:
            break
        }
        a.step += 1
        if a.step > 200 {
            assist = nil
            return a.down ? touch(.ended, a.x, a.y) : out
        }
        assist = a
        return out
    }

    // Queue native events between ticks; session and sequence checks reject stale or duplicate callbacks.
    func receiveWhaley(_ frame: JumbotronFrame) {
        guard frame.sessionID == whaleySessionID, frame.sequence > lastReceivedWhaleySequence else { return }
        lastReceivedWhaleySequence = frame.sequence
        pendingWhaleyFrames.append(frame)
    }

    func advance() {
        let finger: FingerInput
        if !queue.isEmpty {
            finger = queue.removeFirst()
            if queue.isEmpty { scripted = false }
        } else if assist != nil {
            finger = assistInput()
        } else if whaleyAssist != nil {
            finger = whaleyAssistInput()
        } else {
            finger = .none
        }
        let input = StadiumInput(finger: finger, repeat: pendingRepeat, parked: pendingParked, done: pendingDone,
                                 whaleyFrames: pendingWhaleyFrames)
        pendingWhaleyFrames = []
        pendingRepeat = nil
        pendingParked = nil
        pendingDone = false
        let before = snapshot.ride.bubbles
        recording.inputs.append(input)
        snapshot = game.step(input)
        moments.observe(snapshot, parameters: parameters)
        for e in snapshot.ride.events {
            switch e {
            case .fired(let item, let figure, let part, _):
                let flight = RideRig.itemFlight(snapshot, parameters: parameters, figures: game.figures, figure: figure, part: part)
                lastFlight = (snapshot.tick, flight.from, flight.to, item)
            case .popped(let id):
                if let b = before.first(where: { $0.id == id }) {
                    lastPops.append((snapshot.tick, map.view(x: b.x, y: b.y), map.length(b.size(parameters.ride.bubbles)) / 2))
                }
            case .interlude(let begun, _, let number):
                if begun {
                    phone = moments.feed(number: number)
                    phoneTab = .stats
                    phoneHand = RideRig.PhoneHand()
                } else {
                    phoneTouch(.cancelled, at: phoneStroke?.last ?? .zero)
                    phone = nil
                    phoneHand = RideRig.PhoneHand()
                }
            default:
                break
            }
        }
        lastPops.removeAll { snapshot.tick - $0.tick > 12 }
        if let inc = RideRig.live(snapshot), inc.locked < 0, RideRig.reticle(snapshot) != nil {
            filmPhase += RideRig.filmRate(aim: inc.aim.double) / 60
        }
        refreshMenu()
        voices()
    }

    private func voices() {
        let c = camera
        let ear = (position: c.position, facing: c.forward)
        let live = RideRig.live(snapshot)
        let r = snapshot.ride
        var beeping: [(figure: Int, position: SIMD3<Float>)] = []
        if let inc = live, game.figures.indices.contains(inc.figure) {
            beeping = [(inc.figure, SceneMapping.scene(game.figures[inc.figure].head))]
        }
        let cheering = RideRig.showingResult(snapshot, parameters: parameters) && r.lastResult?.result.success == true
        audio.update(listener: ear.position, facing: ear.facing, crowd: cheering ? 1.0 : 0.15)
        audio.beeps(listener: ear.position, facing: ear.facing, beeping: beeping)
        audio.groove(tempo: r.tempo.double, beat: r.beat ? RideRig.beatIndex(snapshot) : nil)
        // Native contacts retire the shared bubble, but its host already plays the pop sound.
        let nativePops = Set(r.whaley.events.compactMap { event -> Int? in
            if case .bubbleContact(let id, _, true, _) = event { return id }
            return nil
        })
        for e in r.events {
            switch e {
            case .bubble: audio.cue(.bloop)
            case .grabbed: audio.cue(.swell)
            case .popped(let id): if !nativePops.contains(id) { audio.cue(.pop) }
            case .hop(_, _, let onBeat): audio.cue(onBeat ? .boingOnBeat : .boing)
            case .locked: audio.cue(.lock)
            case .fired(let item, _, _, _): audio.cue(item == .hotDog ? .hotDog : (item == .bun ? .bun : .mustard))
            case .result(let result): audio.cue(result.success ? .cheer : .groan)
            case .captured: audio.cue(.lock)
            case .thrown(let how, _, _): audio.cue(how == .thrown ? .hotDog : .pop)
            case .fielded: audio.cue(.bloop)
            case .balk: audio.cue(.cheer)
            default: break
            }
        }
    }

    private var phoneRound: Int { snapshot.ride.interlude.on?.number ?? snapshot.ride.interlude.count }

    // Phone touches produce moments without entering the ride's input queue.
    func phoneTouch(_ phase: TouchPhase, at p: CGPoint) {
        phoneHand.touch(phase, at: p, tick: tick, rest: RideRig.handRest(screen: RideRig.phoneFrame(viewSize: viewSize).screen))
        switch phase {
        case .began:
            guard phoneStroke == nil else { return }
            phoneStroke = (down: tick, last: p, travel: 0.0, tab: phoneTab)
        case .moved:
            guard var st = phoneStroke else { return }
            st.travel += hypot(Double(p.x - st.last.x), Double(p.y - st.last.y))
            st.last = p
            phoneStroke = st
        case .ended, .cancelled:
            guard var st = phoneStroke else { return }
            if phase == .ended { st.travel += hypot(Double(p.x - st.last.x), Double(p.y - st.last.y)) }
            phoneStroke = nil
            let held = Double(tick - st.down) / 60
            let gesture = st.travel >= 10 ? "swipe" : (held >= 0.5 ? "press" : "tap")
            moments.phone(.touch, tick: tick, round: phoneRound, title: "A \(gesture) on the phone", details: [
                "gesture": .text(gesture), "heldFor": .number((held * 10).rounded() / 10), "travel": .int(Int(st.travel.rounded())),
                "tab": .text(st.tab.rawValue),
            ])
        case .none:
            break
        }
    }

    // Record completed filters only; intermediate scrub steps stay in the explorer's analytics.
    func phoneRecorded(_ event: String, _ properties: [String: Any]) {
        let results = properties["resultsAfter"] as? Int ?? 0
        switch event {
        case "filter_finished":
            let filter = properties["description"] as? String ?? "a filter"
            moments.phone(.scrub, tick: tick, round: phoneRound, title: "Scrubbed \(filter)", details: [
                "filter": .text(filter), "path": .text(properties["path"] as? String ?? ""), "results": .int(results),
                "source": .text(properties["source"] as? String ?? "touch"),
            ])
        case "filter_suggestion_selected":
            let field = properties["fieldName"] as? String ?? "", value = properties["value"] as? String ?? ""
            moments.phone(.facet, tick: tick, round: phoneRound, title: "Faceted \(field) = \(value)", details: [
                "field": .text(field), "value": .text(value), "results": .int(results),
            ])
        case "filter_cleared":
            moments.phone(.cleared, tick: tick, round: phoneRound, title: "Filters cleared", details: [:])
        default:
            break
        }
    }

    func phoneDone() {
        guard let on = snapshot.ride.interlude.on, on.isBrowsing, !pendingDone else { return }
        pendingDone = true
        moments.phone(.done, tick: tick, round: on.number, title: "Finished exploring", details: [:])
    }

    func phoneTabbed(_ tab: PhoneTab) {
        guard tab != phoneTab else { return }
        phoneTab = tab
        moments.phone(.tab, tick: tick, round: phoneRound, title: "Opened \(tab.rawValue)", details: ["tab": .text(tab.rawValue)])
    }

    func saveRecording() -> URL? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = dir.appendingPathComponent("stadium-ride-\(Int(Date().timeIntervalSince1970)).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do { try encoder.encode(recording).write(to: url); return url } catch { return nil }
    }
}
