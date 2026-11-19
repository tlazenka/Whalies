import Foundation
import StadiumGame

// Fixed emission slots allow entity reuse; positions depend only on the simulation tick.
enum WaterArtwork {
    struct Drop: Equatable {
        var slot: Int
        var position: SIMD3<Float>
        /// The droplet's long +y axis follows the arc tangent.
        var direction: SIMD3<Float>
        var radii: SIMD3<Float>
    }

    private static let emissionTicks = 2
    static let dropCount = (WaterSpray.sprayTicks + emissionTicks - 1) / emissionTicks

    // The first drop reaches the camera when the core's lens effect begins.
    static func drops(spray: WaterSpray, tick: Int, origin: SIMD3<Float>, camera: PinholeCamera) -> [Drop] {
        let age = tick - spray.startTick
        let flightTicks = WaterSpray.impactDelayTicks
        guard age >= 0, age < WaterSpray.sprayTicks + flightTicks,
              finite(origin), finite(camera.position), finite(camera.target) else { return [] }

        let forward = unit(camera.target - camera.position, fallback: SIMD3<Float>(0, 0, -1))
        let right = unit(cross(forward, SIMD3<Float>(0, 1, 0)), fallback: SIMD3<Float>(1, 0, 0))
        let up = cross(right, forward)
        var result: [Drop] = []
        result.reserveCapacity(dropCount)
        for slot in 0..<dropCount {
            let emitted = slot * emissionTicks
            let flying = age - emitted
            guard emitted < WaterSpray.sprayTicks, flying >= 0, flying <= flightTicks else { continue }
            let t: Float = Float(flying) / Float(max(1, flightTicks))
            let remaining: Float = 1 - t
            // Fixed angular spacing adds spray width without consuming randomness.
            let angle: Float = Float(slot) * 2.3999632
            let side: Float = sin(angle), vertical: Float = cos(angle)
            let start = origin + SIMD3<Float>(side * 0.012, 0, vertical * 0.008)
            let lift: Float = 1 + Float(slot % 3) * 0.1
            let control = start + SIMD3<Float>(0, lift, 0) + right * (side * 0.12)
            let end = camera.position + forward * 0.12 + right * (side * 0.035) + up * (vertical * 0.025)
            let position = start * (remaining * remaining) + control * (2 * remaining * t) + end * (t * t)
            let tangent = (control - start) * remaining + (end - control) * t
            let direction = unit(tangent, fallback: -forward)
            let width: Float = 0.025 + Float(slot % 3) * 0.004
            let length: Float = 0.075 + Float(slot % 3) * 0.012
            let taper: Float = 1 - 0.7 * t * t
            guard finite(position) else { continue }
            result.append(Drop(slot: slot, position: position, direction: direction,
                               radii: SIMD3<Float>(width, length, width) * taper))
        }
        return result
    }

    private static func finite(_ v: SIMD3<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }

    private static func unit(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let squared: Float = v.x * v.x + v.y * v.y + v.z * v.z
        guard squared.isFinite, squared > 0.00000001 else { return fallback }
        return v / sqrt(squared)
    }

    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}
