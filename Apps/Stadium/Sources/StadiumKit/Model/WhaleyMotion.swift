import Foundation
import StadiumGame

// Derive poses from simulation state so skipped frames, pauses and replay cannot accumulate drift.
enum WhaleyMotion {
    struct Pose: Equatable {
        var position: SIMD3<Float>
        /// Right-handed rotation about world +y, then local +x.
        var yaw: Float
        var pitch: Float
        /// Unit gaze direction in mascot coordinates; forward is -z.
        var gaze: SIMD3<Float>
        /// Opposite fin rotations about local ±z keep their roots inside the body.
        var finAngle: Float = 0
        /// Tail rotation about local +x at its root.
        var tailAngle: Float = 0

        func worldPoint(_ local: SIMD3<Float>) -> SIMD3<Float> {
            position + WhaleyMotion.rotate(local, yaw: yaw, pitch: pitch)
        }
    }

    private static let forward = SIMD3<Float>(0, 0, -1)
    private static let fullTurn: Float = 2 * .pi
    private static let bodyYawRemainder: Float = 12 * .pi / 180
    private static let bodyPitchLimit: Float = 25 * .pi / 180
    private static let eyeYawLimit: Float = 40 * .pi / 180
    private static let eyePitchLimit: Float = 35 * .pi / 180
    private static let idleHop: Float = 0.05
    private static let idleFinAngle: Float = 6 * .pi / 180
    private static let idleTailAngle: Float = 4 * .pi / 180
    private static let idleBlendTicks: Float = 6

    static func pose(origin: SIMD3<Float>, headingTurns: Double, target: SIMD3<Float>?,
                     spray: WaterSpray?, tick: Int, beatPhase: Int64 = 0) -> Pose {
        let rest = finite(origin) ? origin : .zero
        let heading = headingTurns.isFinite ? headingTurns.truncatingRemainder(dividingBy: 1) : 0
        let roadYaw = Float(-heading * 2 * Double.pi)
        var position = rest
        var spin: Float = 0
        var idleWeight: Float = 1
        if let progress = spray?.sprayProgress(at: tick) {
            let t = Float(progress)
            let rise = sin(Float.pi * t)
            position.y += 0.9 * rise * rise
            spin = fullTurn * t * t * (3 - 2 * t)
            // Blend idle motion at both endpoints with zero endpoint velocity.
            let age = t * Float(WaterSpray.sprayTicks)
            let out = eased(age / idleBlendTicks)
            let back = eased((age - Float(WaterSpray.sprayTicks) + idleBlendTicks) / idleBlendTicks)
            idleWeight = 1 - out + back
        }
        // Mask before Float conversion to preserve fractional beats in long recordings.
        let beat = Float(beatPhase & 0xFFFF) / 65536
        let bounce = sin(Float.pi * beat)
        let stroke = sin(fullTurn * beat) * idleWeight
        position.y += idleHop * bounce * bounce * idleWeight
        let finAngle = idleFinAngle * stroke
        let tailAngle = -idleTailAngle * stroke

        var yaw = roadYaw
        var pitch: Float = 0
        let toward = target.flatMap { finite($0) ? unit($0 - position) : nil }
        if let toward {
            let horizontal = sqrt(toward.x * toward.x + toward.z * toward.z)
            // Vertical targets provide no new heading.
            if horizontal > 0.0001 {
                let targetYaw = atan2(-toward.x, -toward.z)
                let change = atan2(sin(targetYaw - roadYaw), cos(targetYaw - roadYaw))
                // A periodic eye share avoids a jump when the target crosses the ±π heading boundary.
                let eyeShare = sin(change) * bodyYawRemainder
                yaw += change - eyeShare
            }
            pitch = clamped(atan2(toward.y, horizontal) * 0.65, limit: bodyPitchLimit)
        }
        yaw += spin

        let gaze: SIMD3<Float>
        if let toward {
            let local = inverseRotate(toward, yaw: yaw, pitch: pitch)
            let eyeYaw = clamped(atan2(-local.x, -local.z), limit: eyeYawLimit)
            let horizontal = sqrt(local.x * local.x + local.z * local.z)
            let eyePitch = clamped(atan2(local.y, horizontal), limit: eyePitchLimit)
            gaze = rotate(forward, yaw: eyeYaw, pitch: eyePitch)
        } else {
            gaze = forward
        }
        return Pose(position: position, yaw: yaw, pitch: pitch, gaze: gaze,
                    finAngle: finAngle, tailAngle: tailAngle)
    }

    private static func eased(_ value: Float) -> Float {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    // Ry(yaw) * Rx(pitch), matching the entity's quaternion composition.
    private static func rotate(_ v: SIMD3<Float>, yaw: Float, pitch: Float) -> SIMD3<Float> {
        let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        let pitched = SIMD3<Float>(v.x, cp * v.y - sp * v.z, sp * v.y + cp * v.z)
        return SIMD3<Float>(cy * pitched.x + sy * pitched.z, pitched.y,
                            -sy * pitched.x + cy * pitched.z)
    }

    private static func inverseRotate(_ v: SIMD3<Float>, yaw: Float, pitch: Float) -> SIMD3<Float> {
        let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        let unturned = SIMD3<Float>(cy * v.x - sy * v.z, v.y, sy * v.x + cy * v.z)
        return SIMD3<Float>(unturned.x, cp * unturned.y + sp * unturned.z,
                            -sp * unturned.y + cp * unturned.z)
    }

    private static func finite(_ v: SIMD3<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }

    private static func unit(_ v: SIMD3<Float>) -> SIMD3<Float>? {
        guard finite(v) else { return nil }
        // Scale before squaring to avoid overflow for large finite targets.
        let magnitude = max(abs(v.x), abs(v.y), abs(v.z))
        guard magnitude > 0.000001 else { return nil }
        let scaled = v / magnitude
        return scaled / sqrt((scaled * scaled).sum())
    }

    private static func clamped(_ value: Float, limit: Float) -> Float {
        min(limit, max(-limit, value))
    }
}
