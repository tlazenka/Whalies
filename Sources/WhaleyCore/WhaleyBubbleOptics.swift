import Foundation

/// Optical interpretation of a live WhaleyProjection3D.World. No physics, level
/// edits, input routing or independent game state lives here.
public enum WhaleyBubbleOptics {
    public struct RaySample: Sendable, Equatable {
        public let id: String
        public let kind: Landmark
        public let refractedSpot: WhaleyProjection3D.Point
        public let reflectedSpot: WhaleyProjection3D.Point
        public let reflectance: Double
        public let transmission: Double
    }

    public enum Landmark: String, Sendable, Equatable {
        case flame, coin, platform, wall, ground, bubble, goal
    }

    public struct Camera: Sendable, Equatable {
        public let eye: WhaleyProjection3D.Point
        public let center: WhaleyProjection3D.Point
        public let radius: Double
        /// Fixed optical axis: up in Whaley's original 2D XY plane.
        public let direction: WhaleyProjection3D.Point
    }

    public static func camera(
        for world: WhaleyProjection3D.World,
        radius: Double = 3.4,
        trackingEye: WhaleyProjection3D.Point? = nil
    ) -> Camera {
        // When the camera is anchored at a jump origin, move the entire optical
        // sphere with it; the eye must always stay inside the spherical shell.
        let center = trackingEye.map { WhaleyProjection3D.Point(x: $0.x, y: $0.y + radius * 0.80, z: $0.z) }
            ?? world.player.center
        return Camera(
            eye: .init(x: center.x, y: center.y - radius * 0.80, z: center.z),
            center: center, radius: radius,
            direction: .init(x: 0, y: 1, z: 0)
        )
    }

    /// Stable source IDs preserve cues as moving entities cross tile boundaries.
    /// Platform is a *projection classification*: the exposed top of a wall tile.
    /// It does not add a new kind to the original Obj-C simulation.
    public static func signals(
        for world: WhaleyProjection3D.World,
        radius: Double = 3.4,
        interiorIndex: Double = 1.33,
        maximum: Int = 64,
        trackingEye: WhaleyProjection3D.Point? = nil
    ) -> [RaySample] {
        guard radius > 0, interiorIndex > 1, maximum > 0 else { return [] }
        let camera = camera(for: world, radius: radius, trackingEye: trackingEye)
        let center = vector(camera.center), eye = vector(camera.eye)
        let walls = Set(world.objects.filter { $0.kind == .wall }.map {
            Tile(x: Int(floor($0.center.x)), y: Int(floor($0.center.y)))
        })
        let sources = world.objects.sorted {
            let a = lengthSquared(vector($0.center) - eye)
            let b = lengthSquared(vector($1.center) - eye)
            return a == b ? $0.id < $1.id : a < b
        }
        return sources.prefix(maximum).compactMap { object -> RaySample? in
            let toward = vector(object.center) - eye
            guard lengthSquared(toward) > 1e-12 else { return nil }
            let incident = normalized(toward)
            guard let first = sphereExit(origin: eye, direction: incident, center: center, radius: radius)
            else { return nil }
            let normal = normalized(first - center)
            let cosine = min(1, max(0, dot(incident, normal)))
            let eta = interiorIndex // bubble interior to surrounding air (n = 1)
            let transmittedSquare = 1 - eta * eta * (1 - cosine * cosine)
            let reflectance: Double
            if transmittedSquare <= 0 {
                reflectance = 1 // total internal reflection
            } else {
                let transmittedCosine = sqrt(transmittedSquare)
                let perpendicular = (interiorIndex * cosine - transmittedCosine) /
                                    (interiorIndex * cosine + transmittedCosine)
                let parallel = (cosine - interiorIndex * transmittedCosine) /
                               (cosine + interiorIndex * transmittedCosine)
                reflectance = min(1, max(0, (perpendicular * perpendicular +
                                              parallel * parallel) / 2))
            }
            // Snell's law supplies the transmitted direction when it exists.
            // The first prototype displaces its color cue on the shell along
            // the tangential refractive deflection (not an image-space ray trace).
            let transmittedDirection: SIMD3<Double>
            if transmittedSquare > 0 {
                transmittedDirection = normalized(
                    eta * (incident - normal * cosine) +
                    normal * sqrt(transmittedSquare)
                )
            } else {
                transmittedDirection = incident
            }
            let reflectedDirection = normalized(incident - normal * (2 * dot(incident, normal)))
            let second = sphereExit(origin: first + reflectedDirection * 1e-4,
                                    direction: reflectedDirection, center: center, radius: radius) ?? first
            let kind: Landmark
            switch object.kind {
            case .flame: kind = .flame
            case .coin: kind = .coin
            case .bubble: kind = .bubble
            case .goal: kind = .goal
            case .ground: kind = .ground
            case .wall:
                let tile = Tile(x: Int(floor(object.center.x)), y: Int(floor(object.center.y)))
                kind = walls.contains(Tile(x: tile.x, y: tile.y + 1)) ? .wall : .platform
            case .player: return nil
            }
            // Inset slightly so both spots remain visible on the inside surface.
            let refractiveOffset = (transmittedDirection - incident) * (radius * 0.22)
            let primary = center + normalized(first - center + refractiveOffset) * (radius - 0.035)
            let secondary = second - normalized(second - center) * 0.055
            return RaySample(
                id: object.id, kind: kind,
                refractedSpot: point(primary),
                reflectedSpot: point(secondary),
                reflectance: reflectance,
                transmission: 1 - reflectance
            )
        }
    }

    private struct Tile: Hashable { var x: Int; var y: Int }

    private static func vector(_ p: WhaleyProjection3D.Point) -> SIMD3<Double> {
        .init(p.x, p.y, p.z)
    }
    private static func point(_ v: SIMD3<Double>) -> WhaleyProjection3D.Point {
        .init(x: v.x, y: v.y, z: v.z)
    }
    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
    private static func lengthSquared(_ v: SIMD3<Double>) -> Double { dot(v, v) }
    private static func normalized(_ v: SIMD3<Double>) -> SIMD3<Double> {
        v / sqrt(lengthSquared(v))
    }
    private static func sphereExit(
        origin: SIMD3<Double>, direction: SIMD3<Double>,
        center: SIMD3<Double>, radius: Double
    ) -> SIMD3<Double>? {
        let offset = origin - center
        let b = dot(offset, direction)
        let discriminant = b * b - (dot(offset, offset) - radius * radius)
        guard discriminant >= 0 else { return nil }
        let distance = -b + sqrt(discriminant)
        guard distance > 0 else { return nil }
        return origin + direction * distance
    }
}
