import Foundation
#if canImport(simd)
import simd
#endif
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame

extension Look {
    static let teal = Paint(0.19, 0.69, 0.78)
    static let white = Paint(1, 1, 1)
    static let red = Paint(1, 0.231, 0.188)
    static let black = Paint(0.08, 0.08, 0.08)
    static let legs = Paint(0.75, 0.75, 0.75)
    static let field = Paint(0.24, 0.52, 0.24)
    static let dirt = Paint(0.62, 0.47, 0.33)

    // Enlarge the ball and its glow so they remain visible on the Jumbotron.
    static let baseball: Float = 0.2
    static let ballGlow: Float = 0.5
    static let dirtReach: Float = 5
}

extension RideRig {

    private struct Shot {
        let cam: PinholeCamera
        let size = RideRig.crewSize
        let tanHalf: Float
        var pieces: [CrewShot.Piece] = []

        init(_ cam: PinholeCamera) {
            self.cam = cam
            tanHalf = Float(tan(Double(cam.fieldOfViewDegrees) * Double.pi / 360))
        }

        static let level = (x: SIMD3<Float>(1, 0, 0), y: SIMD3<Float>(0, 1, 0), z: SIMD3<Float>(0, 0, 1))

        mutating func box(_ part: CrewShot.Part, at c: SIMD3<Float>, axes a: (x: SIMD3<Float>, y: SIMD3<Float>, z: SIMD3<Float>) = Shot.level,
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

        mutating func ball(_ part: CrewShot.Part, at c: SIMD3<Float>, radius r: Float, paint: Paint, depth: Float? = nil) {
            let ahead = simd_dot(c - cam.position, cam.forward)
            guard ahead > 0.05, let q = cam.project(c, viewSize: size) else { return }
            pieces.append(CrewShot.Piece(part: part, points: [q], radius: r * size.y / 2 / (ahead * tanHalf), paint: paint, light: 1,
                                         depth: depth ?? simd_length(c - cam.position) - r))
        }

        mutating func player(x: Double, y: Double, z: Double, body: SIMD3<Float>, shirt: Paint, cap: Paint, legs: Float, across: Bool = false) {
            let c = SceneMapping.scene(x: x, y: y, z: z)
            let half = across ? SIMD3<Float>(body.z / 2, body.y / 2, body.x / 2) : body / 2
            box(.player, at: c, half: half, paint: shirt)
            if legs > 0 {
                box(.legs, at: c + SIMD3(0, -(body.y + legs) / 2, 0), half: SIMD3(half.x * 0.8, legs / 2, half.z * 0.8), paint: Look.legs)
            }
            let head = c + SIMD3(0, body.y / 2 + 0.17, 0)
            ball(.playerHead, at: head, radius: 0.13, paint: Look.skin)
            box(.cap, at: head + SIMD3(0, 0.1, 0), half: SIMD3(0.14, 0.025, 0.14), paint: cap, bias: 0.05)
        }

        mutating func fan(_ p: FanPose, figure: Int) {
            box(.torso, at: p.torso, axes: p.torsoAxes, half: Look.torso / 2, paint: Look.shirt(figure))
            ball(.head, at: p.head, radius: Look.head, paint: Look.skin)
            if let hand = p.hand { ball(.hand, at: hand, radius: Look.hand, paint: Look.skin) }
        }

        var sorted: [CrewShot.Piece] { pieces.sorted { $0.depth > $1.depth } }
    }

    private static func field(_ s: StadiumSnapshot, parameters p: StadiumParameters, through cam: PinholeCamera) -> Shot {
        var shot = Shot(cam)
        shot.player(x: SceneMapping.mound.x, y: 1.5, z: SceneMapping.mound.z, body: SIMD3(0.45, 0.8, 0.3), shirt: Look.teal, cap: Look.black, legs: 0.85)
        shot.player(x: 0.12, y: 0.45, z: -0.6, body: SIMD3(0.55, 0.5, 0.5), shirt: Look.red, cap: Look.red, legs: 0)
        shot.player(x: -0.72, y: 1.2, z: 0.05, body: SIMD3(0.42, 0.72, 0.3), shirt: Look.white, cap: Look.red, legs: 0.8, across: true)
        for f in Fielder.all where f.who != .atPlate {
            shot.player(x: f.x.double, y: 1.3, z: f.z.double, body: SIMD3(0.45, 0.72, 0.3), shirt: Look.teal, cap: Look.black, legs: 0.85)
        }
        for (k, spot) in Fielder.runnerSpots.enumerated() where Base(rawValue: k).map({ s.ride.pitcher.runners.contains($0) }) == true {
            shot.player(x: spot.x.double, y: 1.3, z: spot.z.double, body: SIMD3(0.42, 0.72, 0.3), shirt: Look.white, cap: Look.red, legs: 0.8)
        }
        let ball = SceneMapping.scene(s.ride.pitcher.ball.pos)
        let depth = simd_length(ball - cam.position) - Look.baseball
        shot.ball(.glow, at: ball, radius: Look.ballGlow, paint: Look.white, depth: depth + 0.001)
        shot.ball(.ball, at: ball, radius: Look.baseball, paint: Look.white, depth: depth)
        return shot
    }

    static func standsRow(_ point: Vec3, parameters p: StadiumParameters) -> Int? {
        let centre = p.stands.centre
        let dx = point.x.double - centre.x.double, dz = point.z.double - centre.z.double
        let radius = (dx * dx + dz * dz).squareRoot()
        guard radius >= p.ride.pitcher.wallRadius.double else { return nil }
        var row = 0
        for (k, r) in p.stands.rows.enumerated() where radius >= r.radius.double { row = k }
        return row
    }

    static func ballShot(_ s: StadiumSnapshot, figures: [Figure], parameters p: StadiumParameters) -> CrewShot {
        let cam = Cameras.crewBall(s)
        var shot = field(s, parameters: p, through: cam)
        let pos = s.ride.pitcher.ball.pos
        let ball = SceneMapping.scene(pos)
        var backdrop = Look.field
        if let row = standsRow(pos, parameters: p) {
            backdrop = Look.tiers[min(row, Look.tiers.count - 1)].lit(0.8)
            for (k, f) in figures.enumerated() where k < s.crowd.states.count && simd_length(SceneMapping.scene(f.torso) - ball) < 4 {
                shot.fan(pose(f, state: s.crowd.states[k]), figure: k)
            }
        } else {
            let mound = SceneMapping.scene(x: SceneMapping.mound.x, y: 0, z: SceneMapping.mound.z), plate = SIMD3<Float>(0, 0, 0)
            let flat = SIMD3<Float>(ball.x, 0, ball.z)
            if simd_length(flat - mound) < Look.dirtReach || simd_length(flat - plate) < Look.dirtReach { backdrop = Look.dirt }
        }
        return CrewShot(backdrop: backdrop, pieces: shot.sorted)
    }

    static func pitcherShot(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> CrewShot {
        let shot = field(s, parameters: p, through: Cameras.crewPitcher(parameters: p))
        return CrewShot(backdrop: Look.dirt, pieces: shot.sorted)
    }

    enum InfieldCut: Int, CaseIterable, Equatable {
        case mound, plate, first, second, third

        func target(parameters p: StadiumParameters) -> SIMD3<Float> {
            switch self {
            case .mound:
                let pz = p.ride.pitcher
                return SceneMapping.scene(pz.point(pz.middle))
            case .plate: return SceneMapping.scene(x: -0.3, y: 0.85, z: -0.3)
            case .first: return SceneMapping.scene(x: 18.45, y: 1.0, z: 19.7)
            case .second: return SceneMapping.scene(x: 0, y: 1.0, z: 35.0)
            case .third: return SceneMapping.scene(x: -18.4, y: 1.0, z: 18.3)
            }
        }

        var pictureHeight: Float {
            switch self {
            case .mound, .plate: 3.5
            case .first, .third: 4.5
            case .second: 8
            }
        }
    }

    static let infieldCutTicks = 240

    // Use the simulation tick so replay selects the same broadcast cutaways.
    static func infieldCut(at tick: Int) -> InfieldCut {
        InfieldCut.allCases[(max(0, tick) / infieldCutTicks) % InfieldCut.allCases.count]
    }

    static func infieldShot(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> CrewShot {
        let shot = field(s, parameters: p, through: Cameras.crewInfield(infieldCut(at: s.tick), parameters: p))
        return CrewShot(backdrop: Look.dirt, pieces: shot.sorted)
    }

    static func fanShot(_ s: StadiumSnapshot, figures: [Figure], parameters p: StadiumParameters,
                        flight: (tick: Int, from: SIMD3<Float>, to: SIMD3<Float>, item: Item)?) -> CrewShot? {
        guard let i = s.ride.interlude.on, figures.indices.contains(i.fan), i.fan < s.crowd.states.count,
              let cam = Cameras.crewFan(s, figures: figures, parameters: p) else { return nil }
        let state = s.crowd.states[i.fan]
        let phoneUp = onHisPhone(s, figure: i.fan)
        let posed = Self.pose(figures[i.fan], state: state)
        let fanPose = phoneUp ? lookingDown(posed) : posed
        var shot = Shot(cam)
        shot.fan(fanPose, figure: i.fan)
        let seats = p.stands.seats
        let inGarden = p.ride.garden.contains(figure: i.fan, seatsARow: seats)
        if phoneUp {
            let held = phoneInHand(fanPose)
            let tilted = (x: fanPose.side, y: turn(SIMD3<Float>(0, 1, 0), about: fanPose.side, by: -phoneTilt),
                          z: turn(-fanPose.forward, about: fanPose.side, by: -phoneTilt))
            shot.box(.phone, at: held.phone, axes: tilted, half: Look.phoneBox / 2, paint: Look.phone)
            if fanPose.hand == nil { shot.ball(.hand, at: held.hand, radius: Look.hand, paint: Look.skin) }
        }
        shot.pieces.append(contentsOf: CannonArtwork.pieces(for: flight, at: s.tick, through: cam))
        let row = i.fan / max(1, seats)
        let behind = row + 1 < Look.tiers.count ? (inGarden ? Look.gardenSeat : Look.tiers[row + 1]) : Look.wall
        return CrewShot(backdrop: behind.lit(0.8), pieces: shot.sorted)
    }

    static func liveShot(_ s: StadiumSnapshot, figures: [Figure], parameters p: StadiumParameters,
                         flight: (tick: Int, from: SIMD3<Float>, to: SIMD3<Float>, item: Item)? = nil) -> CrewShot? {
        switch s.ride.pitcher.crew {
        case .ball: ballShot(s, figures: figures, parameters: p)
        case .pitcher: pitcherShot(s, parameters: p)
        case .fan: fanShot(s, figures: figures, parameters: p, flight: flight)
        case .free: nil
        }
    }
}
