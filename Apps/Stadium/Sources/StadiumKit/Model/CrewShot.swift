import Foundation
#if canImport(simd)
import simd
#endif
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame

/// Shared scene/Jumbotron RGB channels in 0...1.
struct Paint: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    func lit(_ k: Double) -> Paint { Paint(min(1, r * k), min(1, g * k), min(1, b * k)) }
}

enum Look {
    static let skin = Paint(0.9, 0.75, 0.6)
    static let shirts: [Paint] = [Paint(0.19, 0.69, 0.78), Paint(1, 0.584, 0), Paint(1, 1, 1), Paint(0, 0.478, 1),
                                  Paint(1, 0.176, 0.333), Paint(1, 0.8, 0), Paint(0.204, 0.78, 0.349), Paint(0.686, 0.322, 0.871)]
    static func shirt(_ figure: Int) -> Paint { shirts[(figure * 5 + figure / 7) % shirts.count] }
    static let tiers: [Paint] = [Paint(0.15, 0.35, 0.55), Paint(0.2, 0.42, 0.62), Paint(0.25, 0.5, 0.7)]
    static let gardenSeat = Paint(0.95, 0.55, 0.1)
    static let wall = Paint(0.35, 0.35, 0.35)
    static let doll = Paint(1, 1, 1)
    static let dollLit = Paint(1, 0.231, 0.188)
    static let hotDog = Paint(0.75, 0.25, 0.15)
    static let phone = Paint(0.1, 0.1, 0.12)

    // Dimensions are metres; torso axes are width, height, depth.
    static let torso = SIMD3<Float>(0.5, 0.9, 0.35)
    static let head: Float = 0.25
    static let hand: Float = 0.08
    static let dollBody = SIMD3<Float>(0.12, 0.18, 0.09)
    static let dollHead: Float = 0.12 * 1.4
    static let item: Float = 0.13
    static let phoneBox = SIMD3<Float>(0.08, 0.16, 0.012)

    // Camera-side fill keeps shirt colours legible when the scene sun hits them edge-on.
    static func light(_ normal: SIMD3<Float>, toward eye: SIMD3<Float>) -> Double {
        0.78 + 0.22 * Double(max(0, simd_dot(normal, simd_normalize(eye))))
    }
}

extension RideRig {

    struct FanPose: Equatable {
        var head: SIMD3<Float>
        var torso: SIMD3<Float>
        var hand: SIMD3<Float>?
        var forward: SIMD3<Float>
        var side: SIMD3<Float>

        var torsoAxes: (x: SIMD3<Float>, y: SIMD3<Float>, z: SIMD3<Float>) {
            (side, SIMD3(0, 1, 0), -forward)
        }
    }

    static func facing(_ f: Figure) -> SIMD3<Float> {
        let c = KartParameters.fieldCentre
        return simd_normalize(SIMD3<Float>(Float(c.x.double - f.x.double), 0, -Float(c.z.double - f.z.double)))
    }

    /// Rodrigues rotation about a unit axis, matching the scene's right-handed quaternion.
    static func turn(_ v: SIMD3<Float>, about k: SIMD3<Float>, by a: Float) -> SIMD3<Float> {
        v * cos(a) + simd_cross(k, v) * sin(a) + k * simd_dot(k, v) * (1 - cos(a))
    }

    // Keep thought poses still so the symbol alone cues the requested action.
    static func pose(_ f: Figure, state: CrowdState) -> FanPose {
        let fwd = facing(f), side = simd_cross(fwd, SIMD3<Float>(0, 1, 0))
        let rest = SceneMapping.scene(f.head)
        let drop: Float = state == .struck ? -0.25 : 0
        let head = rest + SIMD3(0, drop, 0)
        let torso = SceneMapping.scene(f.torso) + SIMD3(0, drop / 2, 0)
        let hand = state == .catching ? rest + fwd * 0.2 + side * -0.25 + SIMD3(0, 0.35, 0) : nil
        return FanPose(head: head, torso: torso, hand: hand, forward: fwd, side: side)
    }

    struct DollPose: Equatable {
        var body: SIMD3<Float>
        var head: SIMD3<Float>
        var bob: Float
        var lit: Bool
    }

    static func dollPose(_ p: FanPose, tick: Int, lit: Bool) -> DollPose {
        let bob = Float(0.05 * sin(Double(tick) * 0.9))
        let body = p.torso + p.forward * 0.38 + p.side * -0.2 + SIMD3(0, 0.08, 0)
        return DollPose(body: body, head: body + p.side * bob + SIMD3(0, 0.2 + abs(bob), 0), bob: bob, lit: lit)
    }

    static func onHisPhone(_ s: StadiumSnapshot, figure i: Int) -> Bool {
        guard let on = s.ride.interlude.on, on.fan == i, i < s.crowd.states.count else { return false }
        return s.crowd.states[i] != .catching
    }

    static func lookingDown(_ p: FanPose) -> FanPose {
        var q = p
        q.head = p.head + p.forward * 0.05 + SIMD3(0, -0.05, 0)
        return q
    }

    static func phoneInHand(_ p: FanPose) -> (phone: SIMD3<Float>, hand: SIMD3<Float>) {
        let phone = p.torso + p.forward * 0.32 + SIMD3(0, 0.16, 0)
        return (phone, phone + p.side * 0.06 + SIMD3(0, -0.05, 0))
    }

    static let phoneTilt: Float = 0.6

    static func dollFanPose(_ s: StadiumSnapshot, _ inc: Incident, figures: [Figure]) -> FanPose? {
        guard figures.indices.contains(inc.figure), inc.figure < s.crowd.states.count else { return nil }
        return pose(figures[inc.figure], state: s.crowd.states[inc.figure])
    }

    /// Projected pieces in painter's order, farthest first.
    struct CrewShot: Equatable {
        enum Part: Equatable { case torso, head, hand, doll, glow, dollHead, thoughtBubble, thoughtSymbol, hotDog, ball, player, playerHead, cap, legs, phone }

        struct Piece: Equatable {
            var part: Part
            var points: [SIMD2<Float>]
            var radius: Float
            var paint: Paint
            var light: Double
            var depth: Float
        }

        var backdrop: Paint
        var pieces: [Piece]

        func parts(_ part: Part) -> [Piece] { pieces.filter { $0.part == part } }
    }

    static let crewSize = SIMD2<Float>(480, 270)

    static func crewShot(_ s: StadiumSnapshot, figures: [Figure], seats: Int, garden: (Int) -> Bool,
                         flight: (tick: Int, from: SIMD3<Float>, to: SIMD3<Float>, item: Item)?) -> CrewShot? {
        guard let inc = crewDoll(s), let p = dollFanPose(s, inc, figures: figures),
              let cam = Cameras.crew(s, figures: figures) else { return nil }
        let size = crewSize
        let tanHalf = Float(tan(Double(cam.fieldOfViewDegrees) * Double.pi / 360))
        var pieces: [CrewShot.Piece] = []

        func box(_ part: CrewShot.Part, at c: SIMD3<Float>, axes a: (x: SIMD3<Float>, y: SIMD3<Float>, z: SIMD3<Float>),
                 half h: SIMD3<Float>, paint: Paint, bias: Float = 0) {
            let x = a.x * h.x, y = a.y * h.y, z = a.z * h.z
            for (out, u, v) in [(x, y, z), (-x, y, z), (y, x, z), (-y, x, z), (z, x, y), (-z, x, y)] {
                let mid = c + out, n = simd_normalize(out)
                guard simd_dot(n, cam.position - mid) > 0 else { continue }
                let onPicture = [mid + u + v, mid - u + v, mid - u - v, mid + u - v].compactMap { cam.project($0, viewSize: size) }
                guard onPicture.count == 4 else { continue }
                pieces.append(CrewShot.Piece(part: part, points: onPicture, radius: 0, paint: paint,
                                             light: Look.light(n, toward: cam.position - mid), depth: simd_length(mid - cam.position) - bias))
            }
        }
        // Sort discs by their near surface, unless a layer supplies its own depth.
        func ball(_ part: CrewShot.Part, at c: SIMD3<Float>, radius r: Float, paint: Paint, depth: Float? = nil) {
            let ahead = simd_dot(c - cam.position, cam.forward)
            guard ahead > 0.05, let q = cam.project(c, viewSize: size) else { return }
            pieces.append(CrewShot.Piece(part: part, points: [q], radius: r * size.y / 2 / (ahead * tanHalf), paint: paint, light: 1,
                                         depth: depth ?? simd_length(c - cam.position) - r))
        }

        let up = SIMD3<Float>(0, 1, 0), level = (x: p.side, y: up, z: -p.forward)
        box(.torso, at: p.torso, axes: p.torsoAxes, half: Look.torso / 2, paint: Look.shirt(inc.figure))
        ball(.head, at: p.head, radius: Look.head, paint: Look.skin)
        if let hand = p.hand { ball(.hand, at: hand, radius: Look.hand, paint: Look.skin) }
        if s.crowd.states[inc.figure] != .catching {
            let d = dollPose(p, tick: s.tick, lit: s.ride.lit)
            box(.doll, at: d.body, axes: level, half: Look.dollBody / 2, paint: Look.doll)
            // Place the glow behind the head in painter's order.
            let headDepth = simd_length(d.head - cam.position) - Look.dollHead
            if d.lit { ball(.glow, at: d.head, radius: Look.dollHead * 1.9, paint: Look.dollLit, depth: headDepth + 0.001) }
            ball(.dollHead, at: d.head, radius: Look.dollHead, paint: d.lit ? Look.dollLit : Look.doll, depth: headDepth)
        }
        if let thought = inc.thought(at: s.tick) {
            let centre = p.head + SIMD3(0, ThoughtArtwork.aboveHead, 0)
            let toward = simd_normalize(cam.position - centre)
            let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), toward))
            let up = simd_cross(toward, right)
            let shapes = ThoughtArtwork.shapes(for: ThoughtArtwork.Key(thought))
            for (layer, shape) in shapes.enumerated() {
                let corners = shape.points.compactMap { cam.project(centre + right * $0.x + up * $0.y, viewSize: size) }
                guard corners.count == shape.points.count else { continue }
                pieces.append(CrewShot.Piece(part: shape.layer == .bubble ? .thoughtBubble : .thoughtSymbol,
                                             points: corners, radius: 0, paint: shape.paint, light: 1,
                                             depth: simd_length(centre - cam.position) - Float(layer) * 0.0001))
            }
        }
        pieces.append(contentsOf: CannonArtwork.pieces(for: flight, at: s.tick, through: cam))

        let row = inc.figure / max(1, seats)
        let behind = row + 1 < Look.tiers.count ? (garden(inc.figure) ? Look.gardenSeat : Look.tiers[row + 1]) : Look.wall
        return CrewShot(backdrop: behind.lit(0.8), pieces: pieces.sorted { $0.depth > $1.depth })
    }
}
