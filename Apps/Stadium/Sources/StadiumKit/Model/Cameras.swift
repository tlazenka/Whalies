// Reflect core z into scene -z; a core heading of h turns becomes -h about scene +y.

import Foundation
#if canImport(simd)
import simd
#endif
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame

enum SceneMapping {
    static func scene(_ v: Vec3) -> SIMD3<Float> { SIMD3(Float(v.x.double), Float(v.y.double), -Float(v.z.double)) }
    static func scene(x: Double, y: Double, z: Double) -> SIMD3<Float> { SIMD3(Float(x), Float(y), -Float(z)) }
    static func stadium(_ p: SIMD3<Float>) -> (x: Double, y: Double, z: Double) { (Double(p.x), Double(p.y), -Double(p.z)) }
    #if canImport(simd)
    static func orientation(headingTurns: Double) -> simd_quatf {
        simd_quatf(angle: Float(-headingTurns * 2 * Double.pi), axis: SIMD3<Float>(0, 1, 0))
    }
    #endif
    static func direction(_ v: Vec3) -> SIMD3<Float> { scene(v) }
    static func forward(headingTurns h: Double) -> (x: Double, z: Double) { (sin(h * 2 * Double.pi), cos(h * 2 * Double.pi)) }
    static func right(headingTurns h: Double) -> (x: Double, z: Double) { (cos(h * 2 * Double.pi), -sin(h * 2 * Double.pi)) }
    static func heading(dx: Double, dz: Double) -> Double {
        let a = atan2(dx, dz) / (2 * Double.pi)
        return a < 0 ? a + 1 : a
    }

    static let mound = (x: 0.0, y: 0.25, z: 18.44)
}

struct PinholeCamera: Equatable {
    var position: SIMD3<Float>
    var target: SIMD3<Float>
    var fieldOfViewDegrees: Float

    private var basis: (forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>) {
        let fwd = simd_normalize(target - position)
        var r = simd_cross(fwd, SIMD3<Float>(0, 1, 0))
        if simd_length(r) < 0.0001 { r = SIMD3<Float>(1, 0, 0) }
        r = simd_normalize(r)
        return (fwd, r, simd_cross(r, fwd))
    }

    private var tanHalf: Float { tan(fieldOfViewDegrees * .pi / 360) }

    var forward: SIMD3<Float> { basis.forward }

    /// Screen coordinates start at the top left, with y increasing downward.
    func ray(through point: SIMD2<Float>, viewSize: SIMD2<Float>) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let b = basis
        guard viewSize.x > 0, viewSize.y > 0 else { return (position, b.forward) }
        let aspect = viewSize.x / viewSize.y
        let ndcX = 2 * point.x / viewSize.x - 1
        let ndcY = 1 - 2 * point.y / viewSize.y
        let direction = simd_normalize(b.forward + b.right * (ndcX * tanHalf * aspect) + b.up * (ndcY * tanHalf))
        return (position, direction)
    }

    func project(_ p: SIMD3<Float>, viewSize: SIMD2<Float>) -> SIMD2<Float>? {
        guard viewSize.x > 0, viewSize.y > 0 else { return nil }
        let b = basis
        let v = p - position
        let depth = simd_dot(v, b.forward)
        guard depth > 0.01 else { return nil }
        let aspect = viewSize.x / viewSize.y
        let ndcX = simd_dot(v, b.right) / (depth * tanHalf * aspect)
        let ndcY = simd_dot(v, b.up) / (depth * tanHalf)
        return SIMD2((ndcX + 1) / 2 * viewSize.x, (1 - ndcY) / 2 * viewSize.y)
    }
}

func smoothstep(_ k: Double) -> Float {
    let c = Float(min(1, max(0, k)))
    return c * c * (3 - 2 * c)
}

enum Cameras {

    static func muzzle(_ car: Car, parameters p: StadiumParameters) -> SIMD3<Float> {
        SceneMapping.scene(x: car.x.double, y: p.muzzleHeight.double, z: car.z.double)
    }

    static func degrees(tanHalf: Double) -> Float { Float(2 * atan(tanHalf) * 180 / Double.pi) }

    // Mirror the core camera so scene geometry stays aligned with its 2D bubble coordinates.
    static func turret(_ car: Car, parameters p: StadiumParameters, zoom: Fixed = .one, onHim: Fixed = .zero, jumbo: JumboAim? = nil) -> PinholeCamera {
        let t = TurretCamera(car: car, parameters: p, zoom: zoom, onHim: onHim, jumbo: jumbo)
        let tanHalf = jumbo == nil ? p.ride.view.tanHalfV.double * zoom.double : t.tanHalf.double
        return PinholeCamera(position: SceneMapping.scene(t.eye), target: SceneMapping.scene(t.target), fieldOfViewDegrees: degrees(tanHalf: tanHalf))
    }

    static func turret(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> PinholeCamera {
        let aim = s.ride.jumbo.zoom?.aim(ticks: p.ride.whaley.zoomTicks) ?? s.ride.interlude.on?.aim(ticks: p.ride.interlude.turnTicks)
        return turret(s.car, parameters: p, zoom: s.ride.zoom, onHim: s.ride.pitcher.fade, jumbo: aim)
    }

    static let eyesDown: Float = 25

    // Place the eye outside the head; the scene phone stays below the overlay phone.
    static func eyes(on f: Figure, parameters p: StadiumParameters) -> PinholeCamera {
        let bowed = RideRig.lookingDown(RideRig.pose(f, state: .seated))
        let position = bowed.head + bowed.forward * (Look.head + 0.03) + SIMD3(0, 0.02, 0)
        let down = eyesDown * .pi / 180
        let target = position + (bowed.forward * cos(down) + SIMD3(0, -sin(down), 0)) * 10
        return PinholeCamera(position: position, target: target, fieldOfViewDegrees: degrees(tanHalf: p.ride.view.tanHalfV.double))
    }

    static func view(_ s: StadiumSnapshot, parameters p: StadiumParameters, figures: [Figure]) -> PinholeCamera {
        guard let i = s.ride.interlude.on, figures.indices.contains(i.fan) else { return turret(s, parameters: p) }
        let il = p.ride.interlude
        let move = InterludeMove(fan: figures[i.fan], ride: rideView(s, parameters: p), muzzle: muzzle(s.car, parameters: p), parameters: p)
        switch i.phase {
        case .turningIn: return move.goingIn(i.k, turnTicks: il.turnTicks)
        case .browsing: return move.eyes
        case .catchWatched: return move.comingOut(il.holdTicks - i.left, ticks: il.holdTicks + il.turnTicks)
        case .turningBack: return move.comingOut(il.holdTicks + il.turnTicks - i.k, ticks: il.holdTicks + il.turnTicks)
        }
    }

    static func rideView(_ s: StadiumSnapshot, parameters p: StadiumParameters) -> PinholeCamera {
        turret(s.car, parameters: p, zoom: s.ride.zoom, onHim: s.ride.pitcher.fade, jumbo: nil)
    }

    // Hold the ride camera while its screen-space bubbles fade out and back in.
    static let inHold = 6, outHold = 8, lookUp = 24
    static let glance = 12
    // Offset the waypoint toward the kart to avoid a half-turn when entering or leaving the fan's eyes.
    static let frontDistance: Float = 4.5, frontUp: Float = 0.45, frontTurn: Float = 20 * .pi / 180, frontMost: Float = 75 * .pi / 180
    static let chinDrop: Float = 0.3, frontIn = 0.6, frontOut = 0.4
    // Lift the path above the direct line to clear the stands, in metres.
    static let bump: Float = 3

    static func wrap(_ a: Float) -> Float { a.remainder(dividingBy: 2 * .pi) }

    static func hermite(_ p0: SIMD3<Float>, _ v0: SIMD3<Float>, _ p1: SIMD3<Float>, _ v1: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let t2 = t * t, t3 = t2 * t
        let a = p0 * (2 * t3 - 3 * t2 + 1) + v0 * (t3 - 2 * t2 + t)
        return a + p1 * (3 * t2 - 2 * t3) + v1 * (t3 - t2)
    }

    /// Radians: yaw zero faces scene -z; positive yaw turns toward +x.
    struct Gaze: Equatable {
        var yaw: Float
        var pitch: Float
        init(yaw: Float, pitch: Float) { self.yaw = yaw; self.pitch = pitch }
        init(_ v: SIMD3<Float>) { self.init(yaw: atan2(v.x, -v.z), pitch: atan2(v.y, (v.x * v.x + v.z * v.z).squareRoot())) }
        var direction: SIMD3<Float> { SIMD3(cos(pitch) * sin(yaw), sin(pitch), -cos(pitch) * cos(yaw)) }

        func toward(_ o: Gaze, by w: Float) -> Gaze {
            Gaze(yaw: yaw + w * Cameras.wrap(o.yaw - yaw), pitch: pitch + w * (o.pitch - pitch))
        }
    }

    // Fix turn directions at the front waypoint so the camera cannot flip mid-transition.
    struct InterludeMove {
        let ride: PinholeCamera
        let eyes: PinholeCamera
        let front: SIMD3<Float>
        let chin: SIMD3<Float>
        let rideGaze: Gaze, eyesGaze: Gaze, frontGaze: Gaze, cannonGaze: Gaze
        let swingIn: Float, swingOut: Float
        // Scale waypoint tangents by each segment's duration to preserve velocity through the join.
        let throughIn: SIMD3<Float>, throughOut: SIMD3<Float>

        init(fan f: Figure, ride: PinholeCamera, muzzle: SIMD3<Float>, parameters p: StadiumParameters) {
            self.ride = ride
            eyes = Cameras.eyes(on: f, parameters: p)
            let head = SceneMapping.scene(f.head)
            chin = head - SIMD3(0, Cameras.chinDrop, 0)
            let ahead = Gaze(RideRig.facing(f)).yaw
            let kart = Cameras.wrap(Gaze(muzzle - head).yaw - ahead)
            let side: Float = kart >= 0 ? 1 : -1
            let off = min(Cameras.frontMost, max(-Cameras.frontMost, kart + side * Cameras.frontTurn))
            front = head + Gaze(yaw: ahead + off, pitch: 0).direction * Cameras.frontDistance + SIMD3(0, Cameras.frontUp, 0)
            rideGaze = Gaze(ride.forward)
            eyesGaze = Gaze(eyes.forward)
            frontGaze = Gaze(chin - front)
            cannonGaze = Gaze(muzzle - eyes.position)
            swingIn = Cameras.wrap(eyesGaze.yaw - frontGaze.yaw)
            swingOut = Cameras.wrap(frontGaze.yaw - cannonGaze.yaw)
            let rest = simd_length(eyes.position - front)
            throughIn = simd_normalize(eyes.position - front) * (rest / Float(1 - Cameras.frontIn))
            throughOut = simd_normalize(ride.position - front) * (rest / Float(Cameras.frontOut))
        }

        private func camera(_ position: SIMD3<Float>, _ look: Gaze, _ fov: Float) -> PinholeCamera {
            PinholeCamera(position: position, target: position + look.direction * 10, fieldOfViewDegrees: fov)
        }

        func goingIn(_ k: Int, turnTicks n: Int) -> PinholeCamera {
            let u = min(1, max(0, Double(k - Cameras.inHold) / Double(max(1, n - Cameras.inHold))))
            if u <= 0 { return ride }
            let position: SIMD3<Float>
            if u <= Cameras.frontIn {
                let w = Float(u / Cameras.frontIn), lift = sin(Float.pi * w)
                position = Cameras.hermite(ride.position, .zero, front, throughIn * Float(Cameras.frontIn), w) + SIMD3(0, Cameras.bump * lift * lift, 0)
            } else {
                let w = Float((u - Cameras.frontIn) / (1 - Cameras.frontIn))
                position = Cameras.hermite(front, throughIn * Float(1 - Cameras.frontIn), eyes.position, .zero, w)
            }
            let a = smoothstep(u / 0.25), m = smoothstep((u - 0.5) / 0.1), b = smoothstep((u - 0.55) / 0.42)
            let him = Gaze(chin - position)
            var look = rideGaze.toward(him, by: a).toward(frontGaze, by: m)
            look = Gaze(yaw: look.yaw + b * swingIn, pitch: look.pitch + b * (eyesGaze.pitch - frontGaze.pitch))
            return camera(position, look, ride.fieldOfViewDegrees + (eyes.fieldOfViewDegrees - ride.fieldOfViewDegrees) * a)
        }

        func comingOut(_ t: Int, ticks n: Int) -> PinholeCamera {
            if t <= Cameras.lookUp {
                let look = eyesGaze.toward(cannonGaze, by: smoothstep(Double(t) / Double(Cameras.glance)))
                return camera(eyes.position, look, eyes.fieldOfViewDegrees)
            }
            let v = min(1, Double(t - Cameras.lookUp) / Double(max(1, n - Cameras.outHold - Cameras.lookUp)))
            if v >= 1 { return ride }
            let position: SIMD3<Float>
            if v <= Cameras.frontOut {
                let w = Float(v / Cameras.frontOut)
                position = Cameras.hermite(eyes.position, .zero, front, throughOut * Float(Cameras.frontOut), w)
            } else {
                let w = Float((v - Cameras.frontOut) / (1 - Cameras.frontOut)), lift = sin(Float.pi * w)
                position = Cameras.hermite(front, throughOut * Float(1 - Cameras.frontOut), ride.position, .zero, w) + SIMD3(0, Cameras.bump * lift * lift, 0)
            }
            let d = smoothstep(v / Cameras.frontOut)
            var look = Gaze(yaw: cannonGaze.yaw + d * swingOut, pitch: cannonGaze.pitch + d * (frontGaze.pitch - cannonGaze.pitch))
            let n2 = smoothstep((v - Cameras.frontOut) / 0.1), e = smoothstep((v - 0.7) / 0.3)
            look = look.toward(Gaze(chin - position), by: n2).toward(rideGaze, by: e)
            return camera(position, look, eyes.fieldOfViewDegrees + (ride.fieldOfViewDegrees - eyes.fieldOfViewDegrees) * e)
        }
    }

    static func crewFocus(_ s: StadiumSnapshot) -> Double {
        guard let inc = s.ride.incident else { return 0 }
        return Double(smoothstep(Double(s.tick - inc.beep) / 90))
    }

    static func crew(_ s: StadiumSnapshot, figures: [Figure]) -> PinholeCamera? {
        guard let inc = s.ride.incident, figures.indices.contains(inc.figure) else { return nil }
        var camera = crew(on: figures[inc.figure], focus: crewFocus(s))
        // Leave room for the thought reel above the fan.
        camera.target += SIMD3(0, 0.27, 0)
        camera.fieldOfViewDegrees = 16
        return camera
    }

    // Keep the framing above and in front of the fan so the row behind cannot enter the shot.
    static func crew(on f: Figure, focus: Double) -> PinholeCamera {
        let c = KartParameters.fieldCentre
        let dx = c.x.double - f.x.double, dz = c.z.double - f.z.double
        let length = max(0.001, (dx * dx + dz * dz).squareRoot())
        let away = 10 - 4 * min(1, max(0, focus))
        let position = SceneMapping.scene(x: f.x.double + dx / length * away, y: f.headY.double + 0.2, z: f.z.double + dz / length * away)
        return PinholeCamera(position: position, target: SceneMapping.scene(f.head), fieldOfViewDegrees: 12)
    }

    static func crewFan(_ s: StadiumSnapshot, figures: [Figure], parameters p: StadiumParameters) -> PinholeCamera? {
        guard let i = s.ride.interlude.on, figures.indices.contains(i.fan) else { return nil }
        let focus = i.phase == .turningIn ? Double(smoothstep(Double(i.k) / Double(max(1, p.ride.interlude.turnTicks)))) : 1
        return crew(on: figures[i.fan], focus: focus)
    }

    static let pressBox = SceneMapping.scene(x: 0, y: 14, z: -30)
    static let ballPictureHeight: Float = 6
    static let pitcherPictureHeight: Float = 3.5

    static func fromPressBox(on target: SIMD3<Float>, pictureHeight: Float) -> PinholeCamera {
        let distance = max(1, simd_length(target - pressBox))
        return PinholeCamera(position: pressBox, target: target, fieldOfViewDegrees: degrees(tanHalf: Double(pictureHeight / 2 / distance)))
    }

    static func crewBall(_ s: StadiumSnapshot) -> PinholeCamera {
        fromPressBox(on: SceneMapping.scene(s.ride.pitcher.ball.pos), pictureHeight: ballPictureHeight)
    }

    static func crewPitcher(parameters p: StadiumParameters) -> PinholeCamera {
        let pz = p.ride.pitcher
        return fromPressBox(on: SceneMapping.scene(pz.point(pz.middle)), pictureHeight: pitcherPictureHeight)
    }

    static func crewInfield(_ cut: RideRig.InfieldCut, parameters p: StadiumParameters) -> PinholeCamera {
        if cut == .mound { return crewPitcher(parameters: p) }
        return fromPressBox(on: cut.target(parameters: p), pictureHeight: cut.pictureHeight)
    }

    /// Scene corners in viewer order: top-left, top-right, bottom-right, bottom-left.
    static func jumbotronCorners(parameters p: StadiumParameters) -> [SIMD3<Float>] {
        let c = p.jumbotron
        let toward = (x: -c.x.double, z: KartParameters.fieldCentre.z.double - c.z.double)
        let length = (toward.x * toward.x + toward.z * toward.z).squareRoot()
        let n = (x: toward.x / length, z: toward.z / length)
        // The viewer faces -n, so use that heading for screen-right.
        let h = SceneMapping.heading(dx: -n.x, dz: -n.z)
        let r = SceneMapping.right(headingTurns: h)
        let face = (x: c.x.double + n.x * 0.55, y: c.y.double, z: c.z.double + n.z * 0.55)
        let w = p.jumbotronWidth.double / 2, ht = p.jumbotronHeight.double / 2
        return [SceneMapping.scene(x: face.x - r.x * w, y: face.y + ht, z: face.z - r.z * w),
                SceneMapping.scene(x: face.x + r.x * w, y: face.y + ht, z: face.z + r.z * w),
                SceneMapping.scene(x: face.x + r.x * w, y: face.y - ht, z: face.z + r.z * w),
                SceneMapping.scene(x: face.x - r.x * w, y: face.y - ht, z: face.z - r.z * w)]
    }

    static func jumbotronHeading(parameters p: StadiumParameters) -> Double {
        SceneMapping.heading(dx: -p.jumbotron.x.double, dz: KartParameters.fieldCentre.z.double - p.jumbotron.z.double)
    }
}
