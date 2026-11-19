import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import StadiumGame

extension RideRig {
    /// Rounded segment endpoints and radii, in view points.
    struct Limb: Equatable {
        var from: CGPoint
        var to: CGPoint
        var fromRadius: Double
        var toRadius: Double
    }

    struct FanHands: Equatable {
        var behind: [Limb]
        var over: [Limb]
        var tip: CGPoint
        var pointing: CGPoint
        var unit: Double
        var pressed: Bool
    }

    struct PhoneHand: Equatable {
        enum State: Equatable {
            case resting
            case down(from: CGPoint, since: Int)
            case lifted(at: CGPoint, since: Int)
        }
        private(set) var state = State.resting
        private(set) var finger = CGPoint.zero

        static let reach = 5, hover = 18, settle = 24

        func tip(at tick: Int, rest: CGPoint) -> (point: CGPoint, pressed: Bool) {
            switch state {
            case .resting:
                return (rest, false)
            case .down(let from, let since):
                let k = Double(smoothstep(Double(tick - since) / Double(Self.reach)))
                return (RideRig.mix(from, finger, k), tick - since >= Self.reach)
            case .lifted(let at, let since):
                let k = Double(smoothstep(Double(tick - since - Self.hover) / Double(Self.settle)))
                return (RideRig.mix(at, rest, k), false)
            }
        }

        mutating func touch(_ phase: TouchPhase, at p: CGPoint, tick: Int, rest: CGPoint) {
            switch phase {
            case .began:
                state = .down(from: tip(at: tick, rest: rest).point, since: tick)
                finger = p
            case .moved:
                if case .down = state { finger = p }
            case .ended, .cancelled:
                if case .down = state { state = .lifted(at: finger, since: tick) }
            case .none:
                break
            }
        }
    }

    static func mix(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
        CGPoint(x: Double(a.x) + (Double(b.x) - Double(a.x)) * k, y: Double(a.y) + (Double(b.y) - Double(a.y)) * k)
    }

    static func handRest(screen: CGSize) -> CGPoint {
        CGPoint(x: Double(screen.width) * 0.78, y: Double(screen.height) + 15 + Double(screen.width) * 0.11 * 0.9)
    }

    // Overlap each limb with its neighbour and extend the forearms offscreen to avoid floating hands.
    static func fanHands(frame: PhoneFrame, offset: Double, viewSize: SIMD2<Float>, tip: CGPoint, pressed: Bool) -> FanHands {
        typealias V = SIMD2<Double>
        func cg(_ v: V) -> CGPoint { CGPoint(x: v.x, y: v.y) }
        func limb(_ a: V, _ b: V, _ ra: Double, _ rb: Double) -> Limb { Limb(from: cg(a), to: cg(b), fromRadius: ra, toRadius: rb) }
        let w = Double(frame.screen.width), h = Double(frame.screen.height)
        let o = V(Double(frame.centre.x) - w / 2, Double(frame.centre.y) - h / 2 + offset)
        let s = w * 0.11
        let foot = max(Double(viewSize.y), o.y + h) + 0.35 * h
        let t = o + V(Double(tip.x), Double(tip.y))
        let elbow = V(o.x + w * 1.3, foot)
        let along = t - elbow
        let d = along / max(1e-9, (along * along).sum().squareRoot())
        let n = V(d.y, -d.x)
        let k = t - d * (3.2 * s)
        let km = k - n * (0.78 * s) + d * (0.05 * s), kr = k - n * (1.5 * s) - d * (0.12 * s), kl = k - n * (2.15 * s) - d * (0.38 * s)
        let wrist = (k + kl) / 2 - d * (2.4 * s)
        let right = [
            limb(wrist - d * (0.3 * s), elbow, 1.0 * s, 1.45 * s),
            limb(wrist, (k + kl) / 2, 1.1 * s, 1.2 * s),
            limb(wrist + n * (0.95 * s) + d * (0.7 * s), k + n * (0.62 * s) - d * (0.85 * s), 0.55 * s, 0.42 * s),
            limb(kl, kl + d * (0.42 * s), 0.38 * s, 0.35 * s),
            limb(kr, kr + d * (0.55 * s), 0.45 * s, 0.42 * s),
            limb(km, km + d * (0.7 * s), 0.47 * s, 0.44 * s),
            limb(k, t, 0.5 * s, 0.42 * s),
        ]
        // Draw the supporting palm behind the phone, but its thumb above the bezel.
        let heel = V(o.x - 0.12 * w, o.y + 1.06 * h), knuckles = V(o.x + 0.12 * w, o.y + 0.78 * h)
        let elbowLeft = V(o.x - 0.45 * w, foot)
        let edge = o.x - 9
        let behind = [limb(heel, elbowLeft, 1.0 * s, 1.45 * s), limb(heel, knuckles, 1.15 * s, 1.25 * s)]
        let thumb = limb(V(edge - 0.1 * s, o.y + 0.86 * h), V(edge + 0.35 * s, o.y + 0.62 * h), 0.55 * s, 0.43 * s)
        return FanHands(behind: behind, over: [thumb] + right, tip: cg(t), pointing: cg(d), unit: s, pressed: pressed)
    }
}
