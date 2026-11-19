import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(simd)
import simd
#endif
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame

enum RideRig {

    /// Scale by height and centre horizontally, preserving the core's logical picture after a resize.
    struct PictureMap: Equatable {
        var scale: Double
        var offsetX: Double

        init(picture: PictureParameters, viewSize: SIMD2<Float>) {
            let h = picture.height.double
            scale = viewSize.y > 0 && h > 0 ? Double(viewSize.y) / h : 1
            offsetX = Double(viewSize.x) / 2 - picture.width.double / 2 * scale
        }

        func view(x: Fixed, y: Fixed) -> CGPoint { CGPoint(x: offsetX + x.double * scale, y: y.double * scale) }
        func picture(_ p: CGPoint) -> (x: Fixed, y: Fixed) { (Fixed((Double(p.x) - offsetX) / scale), Fixed(Double(p.y) / scale)) }
        func length(_ v: Fixed) -> Double { v.double * scale }
    }

    struct BubbleMark: Equatable, Identifiable {
        var id: Int
        var centre: CGPoint
        var radius: Double
        var tint: Bubble.Tint
        var held: Bool
        var frozen: Bool
        var aim: Double?
        var locked: Bool
    }

    static func live(_ s: StadiumSnapshot) -> Incident? { s.ride.incident.flatMap { $0.isLive ? $0 : nil } }

    static func reticle(_ s: StadiumSnapshot) -> Int? {
        guard let inc = live(s) else { return nil }
        if inc.locked >= 0 { return inc.locked }
        return s.ride.bubbles.first { $0.isFrozen && $0.isBeingMoved }?.id
    }

    // Aim at the fan's depth before locking to avoid a parallax jump when the reticle locks.
    static func whaleyAimTarget(_ s: StadiumSnapshot, parameters p: StadiumParameters, figures: [Figure],
                                flight: CannonArtwork.Flight? = nil) -> SIMD3<Float>? {
        // A fired shot owns the gaze until its last projectile arrives, even after the reticle resolves.
        if let flight, CannonArtwork.activeAge(for: flight, at: s.tick) != nil { return flight.to }
        guard s.ride.interlude.on == nil, s.ride.jumbo.zoom == nil,
              let inc = live(s), let id = reticle(s),
              let bubble = s.ride.bubbles.first(where: { $0.id == id }),
              figures.indices.contains(inc.figure),
              p.picture.width > .zero, p.picture.height > .zero,
              p.ride.view.tanHalfV > .zero, s.ride.zoom > .zero else { return nil }

        func finite(_ v: SIMD3<Float>) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }
        let head = SceneMapping.scene(figures[inc.figure].head)
        guard finite(head) else { return nil }
        if inc.locked == id { return head }

        // Use the firing ray in logical picture coordinates so aim and shots agree.
        guard p.ride.view.tanHalfV * s.ride.zoom > .zero else { return nil }
        let camera = TurretCamera(car: s.car, parameters: p, zoom: s.ride.zoom, onHim: s.ride.pitcher.fade)
        guard camera.focal > .zero else { return nil }
        let eye = SceneMapping.scene(camera.eye)
        let ray = SceneMapping.direction(camera.ray(x: bubble.x, y: bubble.y))
        let forward = SceneMapping.direction(camera.basis.forward)
        guard finite(eye), finite(ray), finite(forward) else { return nil }
        let along = simd_dot(ray, forward)
        guard along.isFinite, along > 0.0001 else { return nil }
        let depth = simd_dot(head - eye, forward)
        // A fan behind the camera has no usable depth plane; keep a forward fallback.
        let distance: Float = depth.isFinite && depth > 0.01 ? depth / along : 60
        let target = eye + ray * distance
        return distance.isFinite && distance > 0 && finite(target) ? target : nil
    }

    // Shared bubbles remain in the overlay while the Jumbotron game interacts with them.
    static func bubbles(_ s: StadiumSnapshot, parameters p: StadiumParameters, map: PictureMap) -> [BubbleMark] {
        let reticle = reticle(s), inc = live(s)
        return s.ride.bubbles.map { b in
            let isReticle = b.id == reticle
            return BubbleMark(id: b.id, centre: map.view(x: b.x, y: b.y), radius: map.length(b.size(p.ride.bubbles)) / 2, tint: b.tint,
                              held: b.isBeingMoved, frozen: b.isFrozen, aim: isReticle ? inc.map { $0.aim.double } : nil,
                              locked: isReticle && inc?.locked == b.id)
        }
    }

    static func filmRate(aim: Double) -> Double { 2 + 6 * min(1, max(0, aim)) }

    static func filmGlow(phase: Double) -> Double { 0.5 + 0.5 * cos(2 * Double.pi * phase) }

    static func caughtTick(_ inc: Incident) -> Int? { inc.caughtTick }

    static func itemFlight(_ s: StadiumSnapshot, parameters p: StadiumParameters, figures: [Figure], figure: Int, part: Int) -> (from: SIMD3<Float>, to: SIMD3<Float>) {
        let from = Cameras.muzzle(s.car, parameters: p)
        if figures.indices.contains(figure) {
            let f = figures[figure]
            return (from, SceneMapping.scene(part == 0 ? f.head : f.torso))
        }
        let cam = Cameras.turret(s, parameters: p)
        return (from, cam.position + cam.forward * 60)
    }

    static func barrelPitch(_ s: StadiumSnapshot, parameters p: StadiumParameters, figures: [Figure]) -> Float {
        let from = Cameras.muzzle(s.car, parameters: p)
        var to = SceneMapping.scene(p.jumbotron)
        if let inc = live(s), inc.locked >= 0, figures.indices.contains(inc.figure) { to = SceneMapping.scene(figures[inc.figure].head) }
        let d = to - from
        return atan2(d.y, (d.x * d.x + d.z * d.z).squareRoot())
    }

    static func hopLift(_ left: Int, ticks: Int) -> Float {
        guard left > 0, ticks > 0 else { return 0 }
        return Float(sin(Double.pi * Double(ticks - left) / Double(ticks))) * 0.35
    }

    static func rock(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> (roll: Float, pitch: Float) {
        let n = p.ride.hop.ticks
        let lift = s.ride.hops.map { hopLift($0, ticks: n) }
        guard lift.count == 4 else { return (0, 0) }
        let left = lift[0] + lift[2], right = lift[1] + lift[3], front = lift[2] + lift[3], rear = lift[0] + lift[1]
        return ((left - right) * 0.18, (front - rear) * 0.1)
    }

    // Fade the cart so the pitcher remains visible through it.
    static let bullpenCartDimmed = 0.4

    static func bullpenCartOpacity(_ s: StadiumSnapshot) -> Double {
        1 - (1 - bullpenCartDimmed) * min(1, max(0, s.ride.pitcher.fade.double))
    }

    static func beatGlow(_ s: StadiumSnapshot) -> Double {
        let frac = Double(s.ride.beatPhase & 0xFFFF) / 65536
        return max(0, 1 - frac * 4)
    }

    static func beatIndex(_ s: StadiumSnapshot) -> Int64 { s.ride.beatPhase >> 16 }

    static func showingResult(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> Bool {
        s.ride.lastResult != nil && s.tick - s.ride.lastResultTick < p.ride.alarm.resultShown
    }

    static func resultOnJumbotron(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> AlarmResult? {
        if case .crew(result: let r?) = jumbotron(s, parameters: p) { return r }
        return showingResult(s, parameters: p) ? s.ride.lastResult : nil
    }

    enum ResultMark: Equatable {
        case check, cross

        init(_ result: ShotResult) { self = result.success ? .check : .cross }

        var symbol: String { self == .check ? "checkmark" : "xmark" }
    }

    static func balkName(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> String? {
        guard !jumbotron(s, parameters: p).isCrew,
              let st = s.ride.lastThrow, st.outcome.isBalk, s.tick - s.ride.lastThrowTick < p.ride.alarm.resultShown else { return nil }
        return st.outcome.headline
    }

    static let catchShown = Incident.crewCatch

    static func crewEnd(_ inc: Incident) -> Int { inc.crewEnd }

    static func crewDoll(_ s: StadiumSnapshot) -> Incident? {
        guard let inc = s.ride.incident else { return nil }
        return inc.onJumbotron(at: s.tick) ? inc : nil
    }

    enum JumbotronShows: Equatable {
        case crew(result: AlarmResult?)
        case ball
        case pitcher
        case fan
        case whaley(result: AlarmResult?)
        case result(AlarmResult)
        case board

        var isCrew: Bool { if case .crew = self { true } else { false } }
        var isWhaley: Bool { if case .whaley = self { true } else { false } }
    }

    static func jumbotron(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> JumbotronShows {
        if let inc = crewDoll(s),
           StadiumGame.showsFan(crew: s.ride.pitcher.crew, dollOnJumbotron: true, zoomed: s.ride.jumbo.zoom != nil) {
            return .crew(result: inc.isLive ? nil : s.ride.lastResult)
        }
        switch s.ride.pitcher.crew {
        case .ball: return .ball
        case .pitcher: return .pitcher
        case .fan: return .fan
        case .free: break
        }
        if s.ride.whaley.shown { return .whaley(result: showingResult(s, parameters: p) ? s.ride.lastResult : nil) }
        if showingResult(s, parameters: p), let last = s.ride.lastResult { return .result(last) }
        return .board
    }

    // Fade screen-space bubbles only while the interlude camera holds the ride's view.
    static func interludeShare(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> Double {
        guard let i = s.ride.interlude.on else { return 0 }
        switch i.phase {
        case .turningIn: return Double(smoothstep(Double(i.k) / Double(Cameras.inHold)))
        case .turningBack: return Double(smoothstep(Double(i.k) / Double(Cameras.outHold)))
        case .browsing, .catchWatched: return 1
        }
    }

    static let phoneRise = 10, phoneDrop = 8

    /// Phone offset from 0 (raised) to 1 (hidden); touches are enabled while browsing.
    static func phoneDown(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> Double? {
        guard let i = s.ride.interlude.on else { return nil }
        let il = p.ride.interlude
        switch i.phase {
        case .turningIn: return 1 - Double(smoothstep(Double(i.k - (il.turnTicks - phoneRise)) / Double(phoneRise)))
        case .browsing: return 0
        case .catchWatched: return Double(smoothstep(Double(il.holdTicks - i.left) / Double(phoneDrop)))
        case .turningBack: return 1
        }
    }

    struct PhoneFrame: Equatable {
        var centre: CGPoint
        var screen: CGSize
        var top: Double
    }

    static func phoneFrame(viewSize: SIMD2<Float>) -> PhoneFrame {
        let w = Double(viewSize.x), h = Double(viewSize.y)
        let foot = h - 40, ceiling = max(h * 0.25, 120)
        let width = max(140, min(300, w - 110, (foot - ceiling - 30) * 320 / 568))
        let height = width * 568 / 320
        let y = min(foot - 15 - height / 2, max(ceiling + 15 + height / 2, h * 0.6))
        let top = y - height / 2 - 15
        return PhoneFrame(centre: CGPoint(x: w / 2, y: y), screen: CGSize(width: width, height: height),
                          top: top)
    }

    static func debugTitle(_ state: RepeatState) -> String {
        switch state {
        case .off: "Normal"
        case .cannon: "Hot dog cannon"
        case .whaley: "Whaley 2D"
        case .pitcher: "Balk"
        case .interlude: "Interlude"
        }
    }

    struct MenuLine: Equatable, Identifiable {
        var text: String
        var symbol: String
        var id: String { symbol }
    }

    static func menuTally(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> [MenuLine] {
        let r = s.ride, t = r.tally
        var lines: [MenuLine] = []
        if live(s) != nil { lines.append(MenuLine(text: "A fan is choosing", symbol: "exclamationmark.circle")) }
        let streak = r.streak > 1 ? " \u{00D7}\(min(r.streak, p.ride.beat.streakCap))" : ""
        lines.append(MenuLine(text: "Points \(t.points)\(streak)", symbol: "music.note"))
        if t.balks > 0 { lines.append(MenuLine(text: "Balks \(t.balks)", symbol: "baseball")) }
        lines.append(MenuLine(text: "Called right \(t.served + t.heldFire)", symbol: "checkmark.circle.fill"))
        lines.append(MenuLine(text: "Called wrong \(t.wrong)", symbol: "xmark.circle"))
        return lines
    }
}
