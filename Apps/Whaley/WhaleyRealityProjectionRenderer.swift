import RealityKit
import UIKit
import simd
import WhaleyCore

/// Applies captured state to stable presentation entities. No physics or
/// independent growth animation lives in the renderer.
@MainActor
final class WhaleyRealityProjectionRenderer {
    let root = Entity()
    let camera = PerspectiveCamera()
    private let radius: Float = 3.4
    private let bubbleShell: ModelEntity
    private var entities: [String: ModelEntity] = [:]
    private var appearances: [String: String] = [:]
    private var opticalSpots: [String: ModelEntity] = [:]
    private var session: String?
    private var pressTargets: [String: Whaley3DPressRouter.Target] = [:]

    /// Use entity identity, not just its name. A delayed event from a removed
    /// entity must not select a new entity that happens to have the same name.
    func pressTarget(for entity: Entity) -> Whaley3DPressRouter.Target {
        guard let registered = entities[entity.name], registered === entity,
              entity.parent === root else { return .unavailable }
        return pressTargets[entity.name] ?? .unavailable
    }

    private func pressTarget(for object: WhaleyProjection3D.Object,
                             session: String) -> Whaley3DPressRouter.Target {
        guard object.kind == .bubble else { return .body(session: session) }
        let prefix = "live:bubble:"
        guard object.id.hasPrefix(prefix) else { return .unavailable }
        return .bubble(session: session,
            projectileID: String(object.id.dropFirst(prefix.count)),
            canGrow: object.bubbleRole == .playerCreated)
    }

    init() {
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(red: 0.61, green: 0.87, blue: 1, alpha: 1))
        glass.roughness = .init(floatLiteral: 0.035)
        glass.metallic = .init(floatLiteral: 0.12)
        glass.clearcoat = .init(floatLiteral: 1)
        glass.clearcoatRoughness = .init(floatLiteral: 0.02)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.19))
        glass.faceCulling = .front
        bubbleShell = ModelEntity(mesh: .generateSphere(radius: radius), materials: [glass])
        camera.camera.fieldOfViewInDegrees = 78
        camera.transform.rotation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        bubbleShell.name = "Unbreakable Optical Bubble"
        root.addChild(bubbleShell)
    }

    func render(_ world: WhaleyProjection3D.World, trackingEye: WhaleyProjection3D.Point?) {
        if session != world.session {
            for model in entities.values { model.removeFromParent() }
            for model in opticalSpots.values { model.removeFromParent() }
            entities.removeAll()
            appearances.removeAll()
            pressTargets.removeAll()
            opticalSpots.removeAll()
            session = world.session
        }
        let optics = WhaleyBubbleOptics.camera(for: world, radius: Double(radius), trackingEye: trackingEye)
        bubbleShell.position = vector(optics.center)
        camera.position = vector(optics.eye)
        let desired = Set(world.renderObjects.map(\.id))
        for id in entities.keys.filter({ !desired.contains($0) }) {
            entities.removeValue(forKey: id)?.removeFromParent()
            appearances.removeValue(forKey: id)
            pressTargets.removeValue(forKey: id)
        }
        for object in world.renderObjects {
            let model: ModelEntity
            let appearance = object.kind.rawValue + ":" + (object.bubbleRole?.rawValue ?? "legacy")
            if let existing = entities[object.id] {
                model = existing
            } else {
                // Unit meshes let EVERY frame apply the authoritative dimensions,
                // not just the first frame in which an object becomes visible.
                let mesh: MeshResource
                switch object.kind {
                case .wall, .ground: mesh = .generateBox(size: SIMD3<Float>(repeating: 1))
                default: mesh = .generateSphere(radius: 0.5)
                }
                model = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: Self.color(for: object))])
                model.name = object.id
                // Input-only shapes follow the same unit mesh and entity scale.
                // All bodies participate so a nearer wall/player/coin can occlude
                // a bubble. The optical shell and signal spots do not intercept input.
                let shape: ShapeResource
                switch object.kind {
                case .wall, .ground: shape = .generateBox(size: SIMD3<Float>(repeating: 1))
                default: shape = .generateSphere(radius: 0.5)
                }
                var collision = CollisionComponent(shapes: [shape])
                collision.filter = CollisionFilter(group: [], mask: [])
                model.components.set(collision)
                model.components.set(InputTargetComponent())
                // No PhysicsBodyComponent: native Objective-C still owns gameplay.
                root.addChild(model)
                entities[object.id] = model
                appearances[object.id] = appearance
            }
            if appearances[object.id] != appearance {
                model.model?.materials = [UnlitMaterial(color: Self.color(for: object))]
                appearances[object.id] = appearance
            }
            model.position = vector(object.center)
            model.scale = vector(object.size)
            pressTargets[object.id] = pressTarget(for: object, session: world.session)
        }

        let samples = WhaleyBubbleOptics.signals(for: world, radius: Double(radius), trackingEye: trackingEye)
        let spotIDs = Set(samples.flatMap { [$0.id + ":through", $0.id + ":echo"] })
        for id in opticalSpots.keys.filter({ !spotIDs.contains($0) }) {
            opticalSpots.removeValue(forKey: id)?.removeFromParent()
        }
        for sample in samples {
            updateSpot(id: sample.id + ":through", kind: sample.kind,
                       point: sample.refractedSpot, intensity: sample.transmission,
                       reflected: false, time: world.gameTime)
            updateSpot(id: sample.id + ":echo", kind: sample.kind,
                       point: sample.reflectedSpot, intensity: sample.reflectance,
                       reflected: true, time: world.gameTime)
        }
    }

    private func updateSpot(id: String, kind: WhaleyBubbleOptics.Landmark,
        point: WhaleyProjection3D.Point, intensity: Double, reflected: Bool, time: Double) {
        let model: ModelEntity
        if let existing = opticalSpots[id] {
            model = existing
        } else {
            model = ModelEntity(mesh: .generateSphere(radius: reflected ? 0.095 : 0.13),
                materials: [UnlitMaterial(color: Self.signalColor(for: kind))])
            model.name = id
            root.addChild(model)
            opticalSpots[id] = model
        }
        model.position = vector(point)
        model.isEnabled = intensity > 0.0001
        let pulse: Double = kind == .flame ? 0.83 + 0.17 * sin(time * 4) : 1
        let strength = Float(min(1.5, max(0.09, sqrt(max(0, intensity)))) * pulse)
        model.scale = SIMD3<Float>(repeating: strength)
    }

    private func vector(_ point: WhaleyProjection3D.Point) -> SIMD3<Float> {
        SIMD3<Float>(Float(point.x), Float(point.y), Float(point.z))
    }

    private static func color(for object: WhaleyProjection3D.Object) -> UIColor {
        switch object.kind {
        case .player: .systemCyan
        case .wall: UIColor(white: 0.25, alpha: 1)
        case .ground: .brown
        case .bubble: object.bubbleRole == .foundation ? .white : .systemBlue
        case .coin: .systemYellow
        case .flame: .systemRed
        case .goal: .systemGreen
        }
    }

    private static func signalColor(for kind: WhaleyBubbleOptics.Landmark) -> UIColor {
        switch kind {
        case .flame: .systemRed
        case .coin: .systemYellow
        case .platform: .white
        case .wall: .systemPurple
        case .ground: .systemOrange
        case .bubble: .systemCyan
        case .goal: .systemGreen
        }
    }
}
