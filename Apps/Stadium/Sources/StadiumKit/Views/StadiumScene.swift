#if canImport(UIKit)
import SwiftUI
import RealityKit
import Combine
import simd
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame

struct SceneMoments {
    var flight: (tick: Int, from: SIMD3<Float>, to: SIMD3<Float>, item: Item)? = nil
}

@MainActor
final class StadiumEntities {
    // Retain rest geometry so pose updates cannot accumulate transforms across frames.
    @MainActor
    private struct MascotModel {
        struct EyePart {
            var entity: ModelEntity
            var part: WhaleyMascot.Part
        }

        struct FinJoint {
            var entity: Entity
            var side: Float
        }

        var entity = ModelEntity()
        var scale: Float = 1
        var eyes: [EyePart] = []
        var fins: [FinJoint] = []
        var tail: Entity? = nil

        func apply(_ pose: WhaleyMotion.Pose) {
            entity.position = pose.position
            entity.orientation = simd_quatf(angle: pose.yaw, axis: SIMD3<Float>(0, 1, 0))
                               * simd_quatf(angle: pose.pitch, axis: SIMD3<Float>(1, 0, 0))
            for eye in eyes {
                let offset = WhaleyMascot.gazeOffset(for: eye.part, toward: pose.gaze)
                eye.entity.position = (eye.part.centre + offset) * scale
            }
            for fin in fins {
                fin.entity.orientation = simd_quatf(angle: fin.side * pose.finAngle, axis: SIMD3<Float>(0, 0, 1))
            }
            tail?.orientation = simd_quatf(angle: pose.tailAngle, axis: SIMD3<Float>(1, 0, 0))
        }
    }

    let root = Entity()
    let camera = PerspectiveCamera()
    private(set) var built = false
    private var heads: [ModelEntity] = []
    private var torsos: [ModelEntity] = []
    private var hands: [ModelEntity] = []
    private var facing: [SIMD3<Float>] = []
    private var turns: [simd_quatf] = []
    private var drawn: [Int] = []                 // Cache poses to skip unchanged fans.
    private var doll = ModelEntity()
    private var dollHead = ModelEntity()
    private var dollGlow = false
    private var thought = ModelEntity()
    private var thoughtKey: ThoughtArtwork.Key?
    private var thoughtModels: [ThoughtArtwork.Key: ModelComponent] = [:]
    private var phone = ModelEntity()
    private var phoning = -1
    private var body = ModelEntity()
    private var wheels: [ModelEntity] = []
    private var turret = ModelEntity()
    private var barrel = ModelEntity()
    private var driverFlame = ModelEntity()
    private var whaley = MascotModel()
    private var waterDrops: [ModelEntity] = []
    private var bullpenCartOpacity = 1.0
    private var hotDogs: [ModelEntity] = []
    private var items: [Item: ModelEntity] = [:]
    private var baseball = ModelEntity()
    private var runners: [ModelEntity] = []

    static func colour(_ p: Paint) -> SimpleMaterial.Color { .init(red: CGFloat(p.r), green: CGFloat(p.g), blue: CGFloat(p.b), alpha: 1) }
    static let skin = StadiumEntities.colour(Look.skin)
    static let tierColors: [SimpleMaterial.Color] = Look.tiers.map { StadiumEntities.colour($0) }
    static let gardenSeat = StadiumEntities.colour(Look.gardenSeat)
    static let primer = SimpleMaterial.Color(red: 0.42, green: 0.43, blue: 0.4, alpha: 1)

    private static func box(_ w: Float, _ h: Float, _ d: Float, _ color: SimpleMaterial.Color, metal: Bool = false) -> ModelEntity {
        ModelEntity(mesh: .generateBox(width: w, height: h, depth: d), materials: [SimpleMaterial(color: color, isMetallic: metal)])
    }

    private static func ball(_ r: Float, _ color: SimpleMaterial.Color) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: r), materials: [SimpleMaterial(color: color, isMetallic: false)])
    }

    private static func tree(_ t: RideRig.Tree) -> ModelEntity {
        let trunk = ModelEntity(mesh: .generateCylinder(height: t.height, radius: t.trunkRadius), materials: [SimpleMaterial(color: bark, isMetallic: false)])
        trunk.position = t.foot + SIMD3(0, t.height / 2, 0)
        let green = leaves[t.green % leaves.count]
        for ball in t.crown {
            let lump = Self.ball(ball.radius, green)
            lump.position = ball.centre - trunk.position
            trunk.addChild(lump)
        }
        return trunk
    }
    static let bark = SimpleMaterial.Color(red: 0.36, green: 0.24, blue: 0.14, alpha: 1)
    static let leaves: [SimpleMaterial.Color] = [.init(red: 0.13, green: 0.4, blue: 0.17, alpha: 1),
                                                 .init(red: 0.18, green: 0.5, blue: 0.22, alpha: 1),
                                                 .init(red: 0.24, green: 0.58, blue: 0.27, alpha: 1)]

    private static func lay(_ e: ModelEntity, from a: (Double, Double), to b: (Double, Double), y: Float, extra: Float = 0) {
        let pa = SceneMapping.scene(x: a.0, y: Double(y), z: a.1), pb = SceneMapping.scene(x: b.0, y: Double(y), z: b.1)
        let d = pb - pa
        let length = simd_length(d)
        guard length > 0.001 else { e.isEnabled = false; return }
        e.position = (pa + pb) / 2
        e.orientation = simd_quatf(from: SIMD3(0, 0, 1), to: d / length)
        e.scale = SIMD3(1, 1, length + extra)
    }

    private static func whale(scale: Float = 1, bodyPaint: Paint = WhaleyMascot.grey) -> MascotModel {
        let model = ModelEntity()
        model.name = "Whaley"
        var eyes: [MascotModel.EyePart] = []
        var fins: [MascotModel.FinJoint] = []
        // Put tail and fin hinges inside the body so articulation cannot detach them.
        let tail = Entity()
        let tailRoot = SIMD3<Float>(0, -0.015, 0.28)
        tail.name = "Tail hinge"
        tail.position = tailRoot * scale
        model.addChild(tail)
        let geometry = WhaleyMascot.roundedUnitSphere
        var sphereDescriptor = MeshDescriptor(name: geometry.name)
        sphereDescriptor.positions = MeshBuffers.Positions(geometry.positions)
        sphereDescriptor.normals = MeshBuffers.Normals(geometry.normals)
        sphereDescriptor.primitives = .triangles(geometry.indices)
        sphereDescriptor.materials = .allFaces(0)
        let sphere = (try? MeshResource.generate(from: [sphereDescriptor])) ?? .generateSphere(radius: 1)
        for part in WhaleyMascot.parts {
            let paint = part.paint == WhaleyMascot.grey ? bodyPaint : part.paint
            let entity = ModelEntity(mesh: sphere, materials: [SimpleMaterial(color: colour(paint), isMetallic: false)])
            entity.name = part.name
            entity.scale = part.radii * scale
            entity.position = part.centre * scale
            if part.name == "fin" {
                let side: Float = part.centre.x < 0 ? -1 : 1
                let root = SIMD3<Float>(side * 0.24, part.centre.y, part.centre.z)
                let hinge = Entity()
                hinge.name = side < 0 ? "Left fin hinge" : "Right fin hinge"
                hinge.position = root * scale
                entity.position = (part.centre - root) * scale
                hinge.addChild(entity)
                model.addChild(hinge)
                fins.append(MascotModel.FinJoint(entity: hinge, side: side))
            } else if part.name == "tail" {
                entity.position = (part.centre - tailRoot) * scale
                tail.addChild(entity)
            } else {
                model.addChild(entity)
            }
            if part.name == "pupil" || part.name == "eye-glint" {
                eyes.append(MascotModel.EyePart(entity: entity, part: part))
            }
        }
        var descriptors: [MeshDescriptor] = []
        var materials: [any RealityKit.Material] = []
        for part in WhaleyMascot.hatParts {
            var descriptor = MeshDescriptor(name: part.name)
            descriptor.positions = MeshBuffers.Positions(part.positions.map { $0 * scale })
            descriptor.normals = MeshBuffers.Normals(part.normals)
            descriptor.primitives = .triangles(part.indices)
            descriptor.materials = .allFaces(UInt32(materials.count))
            descriptors.append(descriptor)
            materials.append(SimpleMaterial(color: colour(part.paint), isMetallic: false))
        }
        if let mesh = try? MeshResource.generate(from: descriptors) {
            let hat = ModelEntity(mesh: mesh, materials: materials)
            hat.name = "Murumuts"
            model.addChild(hat)
        }
        let grin = WhaleyMascot.mouth
        var mouthDescriptor = MeshDescriptor(name: grin.name)
        mouthDescriptor.positions = MeshBuffers.Positions(grin.positions.map { $0 * scale })
        mouthDescriptor.normals = MeshBuffers.Normals(grin.normals)
        mouthDescriptor.primitives = .triangles(grin.indices)
        mouthDescriptor.materials = .allFaces(0)
        if let mesh = try? MeshResource.generate(from: [mouthDescriptor]) {
            let mouth = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: colour(grin.paint), isMetallic: false)])
            mouth.name = "Original stepped grin"
            model.addChild(mouth)
        }
        return MascotModel(entity: model, scale: scale, eyes: eyes, fins: fins, tail: tail)
    }

    // Unlit colours keep the flame's bright core readable from either side.
    private static func flame() -> ModelEntity {
        var descriptors: [MeshDescriptor] = []
        var materials: [any RealityKit.Material] = []
        for part in FlameMascot.parts {
            var descriptor = MeshDescriptor(name: part.name)
            descriptor.positions = MeshBuffers.Positions(part.positions)
            descriptor.normals = MeshBuffers.Normals(part.normals)
            descriptor.primitives = .triangles(part.indices)
            descriptor.materials = .allFaces(UInt32(materials.count))
            descriptors.append(descriptor)
            materials.append(UnlitMaterial(color: colour(part.paint)))
        }
        let mesh = (try? MeshResource.generate(from: descriptors)) ?? .generateSphere(radius: FlameMascot.radius)
        let model = ModelEntity(mesh: mesh, materials: materials)
        model.name = "Original flame driver"
        return model
    }

    // Quantized reel keys bound the mesh cache; reuse entities between ticks.
    private func thoughtModel(for key: ThoughtArtwork.Key) -> ModelComponent? {
        if let cached = thoughtModels[key] { return cached }
        var descriptors: [MeshDescriptor] = []
        var materials: [any RealityKit.Material] = []
        for (layer, shape) in ThoughtArtwork.shapes(for: key).enumerated() {
            guard shape.points.count >= 3 else { continue }
            let centre = shape.points.reduce(SIMD2<Float>.zero, +) / Float(shape.points.count)
            let z = Float(layer) * 0.005
            let points = [centre] + shape.points
            var triangles: [UInt32] = []
            for n in shape.points.indices {
                let a = shape.points[n] - centre, b = shape.points[(n + 1) % shape.points.count] - centre
                let area = a.x * b.y - a.y * b.x
                guard abs(area) > 0.00000001 else { continue }
                let first = UInt32(n + 1), second = UInt32((n + 1) % shape.points.count + 1)
                triangles += area > 0 ? [0, first, second] : [0, second, first]
            }
            guard !triangles.isEmpty else { continue }
            var descriptor = MeshDescriptor(name: "thought-\(layer)")
            descriptor.positions = MeshBuffers.Positions(points.map { SIMD3($0.x, $0.y, z) })
            descriptor.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 0, 1), count: points.count))
            descriptor.primitives = .triangles(triangles)
            descriptor.materials = .allFaces(UInt32(materials.count))
            descriptors.append(descriptor)
            materials.append(UnlitMaterial(color: Self.colour(shape.paint)))
        }
        guard let mesh = try? MeshResource.generate(from: descriptors) else { return nil }
        let model = ModelComponent(mesh: mesh, materials: materials)
        thoughtModels[key] = model
        return model
    }

    private func road(_ points: [GroundPoint], half: Double, y: Float, edge: SimpleMaterial.Color) {
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            let road = Self.box(Float(half * 2), 0.03, 1, .darkGray)
            Self.lay(road, from: (a.x.double, a.z.double), to: (b.x.double, b.z.double), y: y, extra: 0.4)
            root.addChild(road)
            let ex = b.x.double - a.x.double, ez = b.z.double - a.z.double
            let l = (ex * ex + ez * ez).squareRoot()
            let nx = ez / l, nz = -ex / l                      // Travel-right normal.
            for side in [-1.0, 1.0] {
                let line = Self.box(0.12, 0.035, 1, edge)
                Self.lay(line, from: (a.x.double + nx * side * half, a.z.double + nz * side * half),
                         to: (b.x.double + nx * side * half, b.z.double + nz * side * half), y: y + 0.005, extra: 0.4)
                root.addChild(line)
            }
        }
    }

    private static func person(body: SIMD3<Float>, shirt: SimpleMaterial.Color, cap: SimpleMaterial.Color, legs: Float = 0) -> ModelEntity {
        let torso = box(body.x, body.y, body.z, shirt)
        if legs > 0 {
            let pair = box(body.x * 0.8, legs, body.z * 0.8, .lightGray)
            pair.position = SIMD3(0, -(body.y + legs) / 2, 0)
            torso.addChild(pair)
        }
        let head = ball(0.13, skin)
        head.position = SIMD3(0, body.y / 2 + 0.17, 0)
        let brim = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 0.14), materials: [SimpleMaterial(color: cap, isMetallic: false)])
        brim.position = SIMD3(0, 0.1, 0)
        head.addChild(brim)
        torso.addChild(head)
        return torso
    }

    static let ride: Float = 0.25

    private static func bullpenCart(_ h: BullpenCartParameters) -> ModelEntity {
        let w = Float(h.wheelSide.double) * 2 + 0.1, centre = Float(h.wheelHeight.double) + ride
        let length = Float((h.wheelBack + h.wheelFront).double) + 1.9
        let chassis = box(w, 0.5, length, primer)
        let cabin = box(w * 0.86, 0.48, length * 0.45, .init(red: 0.45, green: 0.12, blue: 0.12, alpha: 1))
        cabin.position = SIMD3(0, 0.49, 0.15)
        chassis.addChild(cabin)
        let glass = box(w * 0.88, 0.3, length * 0.4, .init(red: 0.2, green: 0.25, blue: 0.3, alpha: 1))
        glass.position = SIMD3(0, 0.52, 0.15)
        chassis.addChild(glass)
        let door = box(0.03, 0.42, 1.0, .systemTeal)
        door.position = SIMD3(w / 2 + 0.01, 0.02, 0.1)
        chassis.addChild(door)
        for z in [-length / 2 - 0.05, length / 2 + 0.05] {
            let bumper = box(w * 1.02, 0.12, 0.12, .lightGray, metal: true)
            bumper.position = SIMD3(0, -0.12, z)
            chassis.addChild(bumper)
        }
        for x in [-Float(h.pipeSide.double), Float(h.pipeSide.double)] {
            let pipe = ModelEntity(mesh: .generateCylinder(height: 0.4, radius: 0.06), materials: [SimpleMaterial(color: .darkGray, isMetallic: true)])
            pipe.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            pipe.position = SIMD3(x, Float(h.pipeHeight.double) - centre, Float(h.pipeBack.double) - 0.2)
            chassis.addChild(pipe)
        }
        let ring = ModelEntity(mesh: .generateCylinder(height: 0.3, radius: 0.4), materials: [SimpleMaterial(color: .darkGray, isMetallic: true)])
        ring.position = SIMD3(0, 0.88, 0)
        chassis.addChild(ring)
        return chassis
    }

    func build(game: StadiumGame) {
        guard !built else { return }
        built = true
        let p = game.parameters
        let c = KartParameters.fieldCentre
        let field = Self.box(300, 0.02, 300, .init(red: 0.22, green: 0.5, blue: 0.2, alpha: 1))
        field.position = SceneMapping.scene(x: c.x.double, y: -0.02, z: c.z.double)
        root.addChild(field)
        let dirt = Self.box(30, 0.02, 30, .init(red: 0.6, green: 0.42, blue: 0.28, alpha: 1))
        dirt.position = SceneMapping.scene(x: 0, y: -0.005, z: 19.4)
        dirt.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3(0, 1, 0))
        root.addChild(dirt)
        let grass = Self.box(18, 0.02, 18, .init(red: 0.25, green: 0.55, blue: 0.22, alpha: 1))
        grass.position = SceneMapping.scene(x: 0, y: 0.0, z: 19.4)
        grass.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3(0, 1, 0))
        root.addChild(grass)
        let mound = ModelEntity(mesh: .generateCylinder(height: 0.25, radius: 2.7), materials: [SimpleMaterial(color: .init(red: 0.6, green: 0.42, blue: 0.28, alpha: 1), isMetallic: false)])
        mound.position = SceneMapping.scene(x: SceneMapping.mound.x, y: 0.12, z: SceneMapping.mound.z)
        root.addChild(mound)
        for (x, z) in [(19.4, 19.4), (0.0, 38.8), (-19.4, 19.4)] {
            let base = Self.box(0.4, 0.08, 0.4, .white)
            base.position = SceneMapping.scene(x: x, y: 0.04, z: z)
            root.addChild(base)
        }
        let plate = Self.box(0.43, 0.03, 0.43, .white)
        plate.position = SceneMapping.scene(x: 0, y: 0.015, z: 0)
        root.addChild(plate)
        for side in [-1.0, 1.0] {
            let line = Self.box(0.1, 0.02, 1, .white)
            Self.lay(line, from: (0, 0), to: (side * 64, 64), y: 0.01)
            root.addChild(line)
        }
        let ring = game.kartParameters
        road(ring.trackPoints, half: ring.roadHalf.double, y: 0, edge: .white)
        let st = p.stands, iso = p.ride.garden
        for (r, row) in st.rows.enumerated() {
            let radius = row.radius.double, base = row.base.double
            let length = Float(2 * Double.pi * radius / Double(st.seats)) + 0.15
            for k in 0..<st.seats {
                let a = st.bearing(seat: k).double * 2 * Double.pi
                let inGarden = iso.contains(figure: k, seatsARow: st.seats)
                let platform = Self.box(length, Float(max(0.05, base)), 4.0, inGarden ? Self.gardenSeat : Self.tierColors[r % Self.tierColors.count])
                platform.position = SceneMapping.scene(x: c.x.double + radius * sin(a), y: base / 2, z: c.z.double + radius * cos(a))
                platform.orientation = SceneMapping.orientation(headingTurns: st.bearing(seat: k).double)
                root.addChild(platform)
            }
        }
        if let back = st.rows.last {
            let radius = back.radius.double + RideRig.wallBehind
            let length = Float(2 * Double.pi * radius / Double(st.seats)) + 0.2
            for k in 0..<st.seats {
                let a = st.bearing(seat: k).double * 2 * Double.pi
                let wall = Self.box(length, Float(RideRig.wallHeight), Float(RideRig.wallThickness), Self.colour(Look.wall))
                wall.position = SceneMapping.scene(x: c.x.double + radius * sin(a), y: RideRig.wallHeight / 2, z: c.z.double + radius * cos(a))
                wall.orientation = SceneMapping.orientation(headingTurns: st.bearing(seat: k).double)
                root.addChild(wall)
            }
        }
        for t in RideRig.gardenTrees(parameters: p) { root.addChild(Self.tree(t)) }
        for (i, f) in game.figures.enumerated() {
            let torso = Self.box(Look.torso.x, Look.torso.y, Look.torso.z, Self.colour(Look.shirt(i)))
            torso.position = SceneMapping.scene(f.torso)
            let head = Self.ball(Look.head, Self.skin)
            head.position = SceneMapping.scene(f.head)
            let hand = Self.ball(Look.hand, Self.skin)
            hand.isEnabled = false
            let toward = simd_normalize(SIMD3<Float>(Float(c.x.double - f.x.double), 0, -Float(c.z.double - f.z.double)))
            facing.append(toward)
            torso.orientation = SceneMapping.orientation(headingTurns: SceneMapping.heading(dx: c.x.double - f.x.double, dz: c.z.double - f.z.double))
            turns.append(torso.orientation)
            for e in [torso, head, hand] { root.addChild(e) }
            torsos.append(torso); heads.append(head); hands.append(hand)
        }
        drawn = Array(repeating: -1, count: game.figures.count)
        doll = Self.box(Look.dollBody.x, Look.dollBody.y, Look.dollBody.z, Self.colour(Look.doll))
        dollHead = Self.ball(Look.dollHead / 1.4, Self.colour(Look.doll))
        dollHead.position = SIMD3(0, 0.2, 0)
        doll.addChild(dollHead)
        doll.isEnabled = false
        root.addChild(doll)
        phone = Self.box(Look.phoneBox.x, Look.phoneBox.y, Look.phoneBox.z, Self.colour(Look.phone))
        phone.isEnabled = false
        root.addChild(phone)
        thought.name = "Fan thought reel"
        thought.isEnabled = false
        root.addChild(thought)
        let jumbotron = Self.box(Float(p.jumbotronWidth.double) + 1, Float(p.jumbotronHeight.double) + 1, 1.0, .init(white: 0.08, alpha: 1), metal: true)
        jumbotron.position = SceneMapping.scene(p.jumbotron)
        let facingJumbotron = SceneMapping.orientation(headingTurns: Cameras.jumbotronHeading(parameters: p))
        jumbotron.orientation = facingJumbotron
        root.addChild(jumbotron)
        for side in [Float(-9), Float(9)] {
            let post = Self.box(0.8, 17, 0.8, .init(white: 0.25, alpha: 1), metal: true)
            post.position = SceneMapping.scene(x: p.jumbotron.x.double, y: 8.5, z: p.jumbotron.z.double) + facingJumbotron.act(SIMD3(side, 0, 0))
            root.addChild(post)
        }
        let h = p.ride.bullpenCart
        body = Self.bullpenCart(h)
        root.addChild(body)
        for _ in Wheel.allCases {
            let wheel = ModelEntity(mesh: .generateCylinder(height: 0.26, radius: Float(h.wheelRadius.double)),
                                    materials: [SimpleMaterial(color: .init(white: 0.08, alpha: 1), isMetallic: false)])
            let hub = ModelEntity(mesh: .generateCylinder(height: 0.28, radius: Float(h.wheelRadius.double) * 0.45),
                                  materials: [SimpleMaterial(color: .lightGray, isMetallic: true)])
            wheel.addChild(hub)
            wheels.append(wheel)
            root.addChild(wheel)
        }
        turret = Self.box(0.6, 0.4, 0.7, .darkGray, metal: true)
        root.addChild(turret)
        barrel = Self.box(0.2, 0.2, 1.0, .systemYellow, metal: true)
        barrel.position = SIMD3(0, 0.1, -0.55)
        turret.addChild(barrel)
        driverFlame = Self.flame()
        root.addChild(driverFlame)
        whaley = Self.whale()
        root.addChild(whaley.entity)
        let sphere = MeshResource.generateSphere(radius: 1)
        let water = UnlitMaterial(color: .init(red: 0.08, green: 0.55, blue: 1, alpha: 1))
        for _ in 0..<WaterArtwork.dropCount {
            let drop = ModelEntity(mesh: sphere, materials: [water])
            drop.isEnabled = false
            root.addChild(drop)
            waterDrops.append(drop)
        }
        let hotDogMaterials = CannonArtwork.hotDogParts.map {
            SimpleMaterial(color: Self.colour($0.paint), isMetallic: false)
        }
        for index in 0..<CannonArtwork.projectileCount {
            let hotDog = ModelEntity()
            hotDog.name = "Cannon hot dog \(index)"
            for (partIndex, part) in CannonArtwork.hotDogParts.enumerated() {
                let piece = ModelEntity(mesh: sphere, materials: [hotDogMaterials[partIndex]])
                piece.position = part.center
                piece.scale = part.radii
                hotDog.addChild(piece)
            }
            hotDog.isEnabled = false
            root.addChild(hotDog)
            hotDogs.append(hotDog)
        }
        items[.bun] = Self.box(0.2, 0.12, 0.4, .init(red: 0.85, green: 0.65, blue: 0.35, alpha: 1))
        items[.mustard] = Self.ball(0.11, .systemYellow)
        for e in items.values { e.isEnabled = false; root.addChild(e) }
        let catcher = Self.person(body: SIMD3(0.55, 0.5, 0.5), shirt: .systemRed, cap: .systemRed)
        catcher.position = SceneMapping.scene(x: 0.12, y: 0.45, z: -0.6)
        let batter = Self.person(body: SIMD3(0.42, 0.72, 0.3), shirt: .white, cap: .systemRed, legs: 0.8)
        batter.position = SceneMapping.scene(x: -0.72, y: 1.2, z: 0.05)
        batter.orientation = SceneMapping.orientation(headingTurns: 0.25)
        let pitcher = Self.person(body: SIMD3(0.45, 0.8, 0.3), shirt: .systemTeal, cap: .black, legs: 0.85)
        pitcher.position = SceneMapping.scene(x: SceneMapping.mound.x, y: 1.5, z: SceneMapping.mound.z)
        pitcher.orientation = SceneMapping.orientation(headingTurns: 0.5)
        for e in [catcher, batter, pitcher] { root.addChild(e) }
        for f in Fielder.all where f.who != .atPlate {
            let fielder = Self.person(body: SIMD3(0.45, 0.72, 0.3), shirt: .systemTeal, cap: .black, legs: 0.85)
            fielder.position = SceneMapping.scene(x: f.x.double, y: 1.3, z: f.z.double)
            fielder.orientation = SceneMapping.orientation(headingTurns: 0.5)
            root.addChild(fielder)
        }
        for spot in Fielder.runnerSpots {
            let runner = Self.person(body: SIMD3(0.42, 0.72, 0.3), shirt: .white, cap: .systemRed, legs: 0.8)
            runner.position = SceneMapping.scene(x: spot.x.double, y: 1.3, z: spot.z.double)
            runner.isEnabled = false
            root.addChild(runner)
            runners.append(runner)
        }
        baseball = Self.ball(0.12, .white)
        root.addChild(baseball)
        // Match PinholeCamera's vertical field of view.
        camera.camera.fieldOfViewOrientation = .vertical
        camera.camera.fieldOfViewInDegrees = 60
        root.addChild(camera)
        let light = DirectionalLight()
        light.light.intensity = 4000
        light.look(at: SceneMapping.scene(x: 0, y: 0, z: 45), from: SceneMapping.scene(x: 40, y: 90, z: -30), relativeTo: nil)
        root.addChild(light)
    }

    func mirror(game: StadiumGame, snapshot s: StadiumSnapshot, moments: SceneMoments, spray: WaterSpray?) {
        let p = game.parameters
        mirrorFans(game: game, snapshot: s)
        let c = s.car, h = p.ride.bullpenCart, n = p.ride.hop.ticks
        let heading = SceneMapping.orientation(headingTurns: c.heading.double)
        let lifts = s.ride.hops.map { RideRig.hopLift($0, ticks: n) }
        let rock = RideRig.rock(s, parameters: p)
        body.position = SceneMapping.scene(x: c.x.double, y: h.wheelHeight.double + Double(Self.ride), z: c.z.double) + SIMD3(0, lifts.reduce(0, +) / 4, 0)
        body.orientation = heading * simd_quatf(angle: rock.roll, axis: SIMD3(0, 0, -1)) * simd_quatf(angle: rock.pitch, axis: SIMD3(1, 0, 0))
        for (k, wheel) in Wheel.allCases.enumerated() where k < wheels.count && k < lifts.count {
            let rear = wheel == .rearLeft || wheel == .rearRight
            let centre = kartPoint(c, right: wheel.isLeft ? -h.wheelSide : h.wheelSide, forward: rear ? -h.wheelBack : h.wheelFront, up: h.wheelHeight)
            wheels[k].position = SceneMapping.scene(centre) + SIMD3(0, lifts[k], 0)
            wheels[k].orientation = heading * simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        }
        let roof = lifts.reduce(0, +) / 4
        turret.position = SceneMapping.scene(x: c.x.double, y: p.muzzleHeight.double - 0.15, z: c.z.double) + SIMD3(0, roof, 0)
        turret.orientation = SceneMapping.orientation(headingTurns: s.turret.double)
        barrel.orientation = simd_quatf(angle: RideRig.barrelPitch(s, parameters: p, figures: game.figures), axis: SIMD3(1, 0, 0))
        let f = SceneMapping.forward(headingTurns: c.heading.double), r = SceneMapping.right(headingTurns: c.heading.double)
        let driverPosition = SceneMapping.scene(x: c.x.double + f.x * 0.2 - r.x * 0.35, y: 1.15, z: c.z.double + f.z * 0.2 - r.z * 0.35) + SIMD3(0, roof, 0)
        driverFlame.position = driverPosition
        driverFlame.orientation = heading * simd_quatf(angle: FlameMascot.roll(at: s.tick), axis: SIMD3<Float>(0, 0, -1))
        let g = SceneMapping.forward(headingTurns: s.turret.double)
        let whaleyPosition = SceneMapping.scene(x: c.x.double - g.x * 0.6, y: p.muzzleHeight.double + 0.3, z: c.z.double - g.z * 0.6) + SIMD3(0, roof, 0)
        let aim = RideRig.whaleyAimTarget(s, parameters: p, figures: game.figures, flight: moments.flight)
        whaley.apply(WhaleyMotion.pose(origin: whaleyPosition, headingTurns: c.heading.double,
                                      target: aim, spray: spray, tick: s.tick, beatPhase: s.ride.beatPhase))
        let opacity = RideRig.bullpenCartOpacity(s)
        if abs(opacity - bullpenCartOpacity) > 0.002 {
            bullpenCartOpacity = opacity
            for part in [body, turret, driverFlame, whaley.entity] + wheels {
                part.components.set(OpacityComponent(opacity: Float(opacity)))
            }
        }
        baseball.position = SceneMapping.scene(s.ride.pitcher.ball.pos)
        for (k, runner) in runners.enumerated() {
            runner.isEnabled = Base(rawValue: k).map { s.ride.pitcher.runners.contains($0) } ?? false
        }
        for hotDog in hotDogs { hotDog.isEnabled = false }
        if let flight = moments.flight, flight.item == .hotDog {
            for pose in CannonArtwork.poses(for: flight, at: s.tick) where hotDogs.indices.contains(pose.index) {
                let hotDog = hotDogs[pose.index]
                hotDog.position = pose.center
                hotDog.orientation = simd_quatf(simd_float3x3(columns: (pose.side, pose.up, pose.forward)))
                hotDog.isEnabled = true
            }
        }
        for (item, e) in items {
            if let shot = moments.flight, shot.item == item, shot.tick <= s.tick, s.tick - shot.tick < 20 {
                let k = Float(s.tick - shot.tick) / 20
                e.isEnabled = true
                e.position = shot.from + (shot.to - shot.from) * k + SIMD3(0, 2.5 * k * (1 - k), 0)
                e.look(at: shot.to, from: e.position, relativeTo: nil)
            } else {
                e.isEnabled = false
            }
        }
    }

    private func mirrorFans(game: StadiumGame, snapshot s: StadiumSnapshot) {
        let figures = game.figures
        let onPhone = s.ride.interlude.on.map { RideRig.onHisPhone(s, figure: $0.fan) ? $0.fan : -1 } ?? -1
        if phoning >= 0 && phoning != onPhone { drawn[phoning] = -1 }
        phoning = onPhone
        phone.isEnabled = false
        for (i, f) in figures.enumerated() where i < s.crowd.states.count {
            let state = s.crowd.states[i]
            let key = state.rawValue * 1000 + (i == onPhone ? 7 : 0)
            if key == drawn[i] && i != onPhone { continue }
            drawn[i] = key
            let posed = RideRig.pose(f, state: state)
            let pose = i == onPhone ? RideRig.lookingDown(posed) : posed
            heads[i].position = pose.head
            torsos[i].orientation = turns[i]
            torsos[i].position = pose.torso
            hands[i].isEnabled = pose.hand != nil
            if let hand = pose.hand { hands[i].position = hand }
            if i == onPhone {
                let held = RideRig.phoneInHand(pose)
                phone.isEnabled = true
                phone.position = held.phone
                phone.orientation = simd_quatf(angle: -RideRig.phoneTilt, axis: pose.side) * simd_quatf(from: SIMD3(0, 0, -1), to: pose.forward)
                if pose.hand == nil {
                    hands[i].isEnabled = true
                    hands[i].position = held.hand
                }
            }
        }
        thought.isEnabled = false
        if let inc = RideRig.crewDoll(s), figures.indices.contains(inc.figure), let frame = inc.thought(at: s.tick) {
            let key = ThoughtArtwork.Key(frame)
            if thoughtKey != key {
                thought.model = thoughtModel(for: key)
                thoughtKey = key
            }
            thought.isEnabled = thought.model != nil
            thought.position = heads[inc.figure].position + SIMD3(0, ThoughtArtwork.aboveHead, 0)
        }
        guard let inc = RideRig.crewDoll(s), let pose = RideRig.dollFanPose(s, inc, figures: figures),
              s.crowd.states[inc.figure] != .catching else { doll.isEnabled = false; return }
        let d = RideRig.dollPose(pose, tick: s.tick, lit: s.ride.lit)
        doll.isEnabled = true
        doll.position = d.body
        doll.orientation = simd_quatf(from: SIMD3(0, 0, -1), to: pose.forward)
        dollHead.position = SIMD3(d.bob, 0.2 + abs(d.bob), 0)
        dollHead.scale = SIMD3(repeating: 1.4)
        if d.lit != dollGlow {
            dollGlow = d.lit
            dollHead.model?.materials = [SimpleMaterial(color: Self.colour(d.lit ? Look.dollLit : Look.doll), isMetallic: false)]
        }
    }

    func place(_ pinhole: PinholeCamera) {
        camera.camera.fieldOfViewInDegrees = pinhole.fieldOfViewDegrees
        camera.look(at: pinhole.target, from: pinhole.position, relativeTo: nil)
        if thought.isEnabled {
            let toward = simd_normalize(pinhole.position - thought.position)
            let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), toward))
            let up = simd_cross(toward, right)
            thought.orientation = simd_quatf(simd_float3x3(columns: (right, up, toward)))
        }
    }

    func mirrorWater(_ spray: WaterSpray?, tick: Int, camera pinhole: PinholeCamera) {
        for drop in waterDrops { drop.isEnabled = false }
        guard let spray else { return }
        let origin = whaley.entity.convert(position: WhaleyMascot.blowhole + SIMD3<Float>(0, 0.012, 0), to: nil)
        for pose in WaterArtwork.drops(spray: spray, tick: tick, origin: origin, camera: pinhole) {
            let drop = waterDrops[pose.slot]
            drop.position = pose.position
            drop.scale = pose.radii
            drop.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: pose.direction)
            drop.isEnabled = true
        }
    }
}

// Read observation here so the UIKit scene and SwiftUI overlays receive the same snapshot.
struct RideSceneView: View {
    let session: StadiumSession
    let readiness: StadiumSceneReadiness
    let onSceneReady: () -> Void

    var body: some View {
        StadiumSceneHost(game: session.game, snapshot: session.snapshot, camera: session.camera,
                         moments: SceneMoments(flight: session.lastFlight), readiness: readiness, onSceneReady: onSceneReady)
    }
}

// Use the normal non-AR renderer. The launch cover is a separate SwiftUI shape,
// and no WaterLens postprocess callback is installed.
private struct StadiumSceneHost: UIViewRepresentable {
    let game: StadiumGame
    let snapshot: StadiumSnapshot
    let camera: PinholeCamera
    let moments: SceneMoments
    let readiness: StadiumSceneReadiness
    let onSceneReady: () -> Void

    @MainActor
    final class Coordinator {
        let entities = StadiumEntities()
        private let readiness: StadiumSceneReadiness
        private var token: UUID?
        private var frames: Cancellable?
        private var sawFrame = false
        var onSceneReady: () -> Void

        init(readiness: StadiumSceneReadiness, onSceneReady: @escaping () -> Void) {
            self.readiness = readiness
            self.onSceneReady = onSceneReady
        }

        func awaitSceneFrames(in view: ARView) {
            cancelReadiness()
            let token = readiness.begin()
            self.token = token
            frames = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self, weak view] _ in
                Task { @MainActor [weak self, weak view] in
                    guard let self, let view, self.token == token else { return }
                    guard self.entities.built, view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else {
                        self.sawFrame = false
                        return
                    }
                    // These are real RealityKit frame updates after population and
                    // layout, not a timed launch delay. They do not certify that
                    // the GPU has presented a particular pixel on the display.
                    guard self.sawFrame else { self.sawFrame = true; return }
                    let current = self.readiness.finish(token)
                    self.cancelReadiness()
                    if current { self.onSceneReady() }
                }
            }
        }

        func cancelReadiness() {
            if let token { readiness.cancel(token) }
            token = nil
            frames?.cancel()
            frames = nil
            sawFrame = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(readiness: readiness, onSceneReady: onSceneReady) }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.black)
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableCameraGrain])
        // The overlay owns input and accessibility.
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        let anchor = AnchorEntity(world: .zero)
        context.coordinator.entities.build(game: game)
        anchor.addChild(context.coordinator.entities.root)
        view.scene.addAnchor(anchor)
        refresh(view, coordinator: context.coordinator)
        context.coordinator.awaitSceneFrames(in: view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.onSceneReady = onSceneReady
        refresh(view, coordinator: context.coordinator)
    }

    private func refresh(_ view: ARView, coordinator: Coordinator) {
        // Activities and cannon fire hide the spray while its core clock continues, preventing a restart on return.
        let firing = moments.flight.map { CannonArtwork.activeAge(for: $0, at: snapshot.tick) != nil } ?? false
        let available = snapshot.ride.interlude.on == nil && snapshot.ride.jumbo.zoom == nil
                     && RideRig.crewDoll(snapshot) == nil && !firing
        let spray = available ? snapshot.ride.waterSpray : nil
        // Update the mascot pose before converting its blowhole into the jet's world-space origin.
        coordinator.entities.mirror(game: game, snapshot: snapshot, moments: moments, spray: spray)
        coordinator.entities.place(camera)
        coordinator.entities.mirrorWater(spray, tick: snapshot.tick, camera: camera)
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.cancelReadiness()
        view.scene.anchors.removeAll()
    }
}
#endif
