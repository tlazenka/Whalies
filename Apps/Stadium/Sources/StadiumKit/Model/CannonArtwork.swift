import Foundation
#if canImport(simd)
import simd
#endif
import StadiumGame

enum CannonArtwork {
    typealias Flight = (tick: Int, from: SIMD3<Float>, to: SIMD3<Float>, item: Item)

    struct Part {
        var center: SIMD3<Float>
        var radii: SIMD3<Float>
        var paint: Paint
    }

    struct Pose {
        var index: Int
        var center: SIMD3<Float>
        // Right-handed axes; the model's local +Z follows its flight.
        var side: SIMD3<Float>
        var up: SIMD3<Float>
        var forward: SIMD3<Float>

        func point(_ local: SIMD3<Float>) -> SIMD3<Float> {
            center + side * local.x + up * local.y + forward * local.z
        }
    }

    static let rankCount = 4
    static let dogsPerRank = 7
    static let projectileCount = rankCount * dogsPerRank
    static let flightTicks = 30
    static let rankDelay = 6
    static let durationTicks = flightTicks + (rankCount - 1) * rankDelay
    static let spreadRadius: Float = 0.65
    static let bun = Paint(0.9, 0.66, 0.32)
    static let hotDogParts: [Part] = [
        Part(center: SIMD3(-0.085, -0.035, 0), radii: SIMD3(0.08, 0.095, 0.235), paint: bun),
        Part(center: SIMD3(0.085, -0.035, 0), radii: SIMD3(0.08, 0.095, 0.235), paint: bun),
        Part(center: SIMD3(0, 0.035, 0), radii: SIMD3(0.07, 0.07, 0.25), paint: Look.hotDog),
    ]

    private static func finite(_ p: SIMD3<Float>) -> Bool {
        p.x.isFinite && p.y.isFinite && p.z.isFinite
    }

    private static func axes(_ forward: SIMD3<Float>) -> (side: SIMD3<Float>, up: SIMD3<Float>) {
        let reference = abs(forward.y) < 0.95 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let side = simd_normalize(simd_cross(reference, forward))
        return (side, simd_cross(forward, side))
    }

    // Keep projectile visibility and the mascot's target hold on the same lifetime.
    static func activeAge(for flight: Flight, at tick: Int) -> Int? {
        let (age, overflow) = tick.subtractingReportingOverflow(flight.tick)
        guard !overflow, age >= 0, age < (flight.item == .hotDog ? durationTicks : 20),
              finite(flight.from), finite(flight.to) else { return nil }
        let distance = simd_length(flight.to - flight.from)
        return distance.isFinite && distance > 0.001 ? age : nil
    }

    static func poses(for flight: Flight, at tick: Int) -> [Pose] {
        guard let age = activeAge(for: flight, at: tick) else { return [] }
        let hotDog = flight.item == .hotDog
        let delta = flight.to - flight.from
        let distance = simd_length(delta)
        let forward = delta / distance
        let frame = axes(forward)
        var result: [Pose] = []
        result.reserveCapacity(hotDog ? projectileCount : 1)
        for rank in 0..<(hotDog ? rankCount : 1) {
            let elapsed = age - rank * rankDelay
            let travelTicks = hotDog ? flightTicks : 20
            guard elapsed >= 0, elapsed < travelTicks else { continue }
            let k = Float(elapsed) / Float(travelTicks)
            let arc = SIMD3<Float>(0, 2.5 * k * (1 - k), 0)
            for lane in 0..<(hotDog ? dogsPerRank : 1) {
                let angle = Float(lane - 1) * .pi / 3 + Float(rank) * .pi / 6
                let radial = lane == 0 ? SIMD3<Float>.zero :
                    (frame.side * cos(angle) + frame.up * sin(angle)) * spreadRadius
                let center = flight.from + delta * k + arc + radial * sin(.pi * k)
                let tangent = delta + SIMD3<Float>(0, 2.5 * (1 - 2 * k), 0) + radial * (.pi * cos(.pi * k))
                let length = simd_length(tangent)
                let heading = length > 0.001 ? tangent / length : forward
                // Preserve the launch bank while following the curved trajectory.
                let across = frame.side - heading * simd_dot(frame.side, heading)
                let acrossLength = simd_length(across)
                let side = acrossLength.isFinite && acrossLength > 0.001 ? across / acrossLength : axes(heading).side
                result.append(Pose(index: rank * dogsPerRank + lane, center: center,
                                   side: side, up: simd_cross(heading, side), forward: heading))
            }
        }
        return result
    }

    static func pieces(for flight: Flight?, at tick: Int, through camera: PinholeCamera) -> [RideRig.CrewShot.Piece] {
        guard let flight else { return [] }
        let parts: [Part]
        switch flight.item {
        case .hotDog: parts = hotDogParts
        case .bun: parts = [Part(center: .zero, radii: SIMD3(0.1, 0.06, 0.2), paint: bun)]
        case .mustard: parts = [Part(center: .zero, radii: SIMD3(repeating: 0.11), paint: Paint(1, 0.8, 0))]
        }
        return poses(for: flight, at: tick).flatMap { pose in
            parts.compactMap { silhouette($0, pose: pose, camera: camera) }
        }
    }

    private static func silhouette(_ part: Part, pose: Pose, camera: PinholeCamera) -> RideRig.CrewShot.Piece? {
        let center = pose.point(part.center)
        let eye = camera.position - center
        let localEye = SIMD3(simd_dot(eye, pose.side), simd_dot(eye, pose.up), simd_dot(eye, pose.forward)) / part.radii
        let squared = simd_dot(localEye, localEye)
        guard squared.isFinite, squared > 1.0001 else { return nil }
        let magnitude = squared.squareRoot()
        let normal = localEye / magnitude
        let frame = axes(normal)
        // In unit-sphere space, perspective tangency is the circle u·eye = 1.
        let circleCenter = localEye / squared
        let radius = (1 - 1 / squared).squareRoot()
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(16)
        for i in 0..<16 {
            let angle = Float(i) * 2 * .pi / 16
            let unit = circleCenter + (frame.side * cos(angle) + frame.up * sin(angle)) * radius
            let world = pose.point(part.center + unit * part.radii)
            guard let point = camera.project(world, viewSize: RideRig.crewSize),
                  point.x.isFinite, point.y.isFinite else { return nil }
            points.append(point)
        }
        let distance = simd_length(eye)
        return RideRig.CrewShot.Piece(part: .hotDog, points: points, radius: 0, paint: part.paint,
                                     light: 1, depth: distance - distance / magnitude)
    }
}
