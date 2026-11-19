import Foundation

enum WhaleyMascot {
    struct Part: Equatable {
        var name: String
        var centre: SIMD3<Float>
        var radii: SIMD3<Float>
        var paint: Paint
    }

    struct MeshPart {
        var name: String
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var indices: [UInt32]
        var paint: Paint
    }

    static let grey = Paint(0.81, 0.81, 0.81)
    static let pale = Paint(0.96, 0.96, 0.96)
    static let red = Paint(1, 0.02, 0.03)
    static let black = Paint(0.02, 0.02, 0.02)
    static let hatRed = Paint(0.64, 0.075, 0.10)
    static let hatBlue = Paint(0.075, 0.13, 0.28)
    static let linen = Paint(0.91, 0.88, 0.77)
    private static let bodyRadii = SIMD3<Float>(0.36, 0.37, 0.32)

    // Shared local-space spray origin; keep the cap behind it to avoid intersecting the jet.
    static let blowhole = SIMD3<Float>(0, 0.32, -0.17)

    private static let eyeRadii = SIMD3<Float>(0.125, 0.18, 0.085)
    private static func eyeCentre(side: Float) -> SIMD3<Float> { SIMD3(side * 0.13, 0.13, -0.285) }
    private static func pupilCentre(side: Float) -> SIMD3<Float> { SIMD3(side * 0.12, 0.13, -0.362) }

    // Move pupils and highlights along the curved eye while keeping them inside its silhouette.
    static func gazeOffset(for part: Part, toward direction: SIMD3<Float>) -> SIMD3<Float> {
        guard part.name == "pupil" || part.name == "eye-glint",
              direction.x.isFinite, direction.y.isFinite, direction.z.isFinite else { return .zero }
        let lengthSquared = (direction * direction).sum()
        guard lengthSquared.isFinite, lengthSquared > 0.00000001 else { return .zero }
        let direction = direction / sqrt(lengthSquared)
        let yawLimit: Float = 40 * .pi / 180, pitchLimit: Float = 35 * .pi / 180
        let yaw = min(yawLimit, max(-yawLimit, atan2(direction.x, -direction.z)))
        let pitch = min(pitchLimit, max(-pitchLimit, atan2(direction.y, sqrt(direction.x * direction.x + direction.z * direction.z))))
        let x: Float = 0.035 * sin(yaw) / sin(yawLimit)
        let y: Float = 0.04 * sin(pitch) / sin(pitchLimit)
        let side: Float = part.centre.x < 0 ? -1 : 1
        let rest = pupilCentre(side: side) - eyeCentre(side: side)
        func front(x: Float, y: Float) -> Float {
            let u = x / eyeRadii.x, v = y / eyeRadii.y
            return -eyeRadii.z * sqrt(max(0, 1 - u * u - v * v))
        }
        let z = front(x: rest.x + x, y: rest.y + y) - front(x: rest.x, y: rest.y)
        return SIMD3(x, y, z)
    }

    // Local forward is -z, matching the turret.
    static var parts: [Part] {
        var parts = [Part(name: "body", centre: .zero, radii: bodyRadii, paint: grey),
                     Part(name: "blowhole", centre: blowhole, radii: SIMD3(0.046, 0.009, 0.032), paint: black),
                     Part(name: "hat-button", centre: hatPoint(SIMD3<Float>(0, hatRadii.y, 0)),
                          radii: SIMD3(0.026, 0.018, 0.026), paint: linen)]
        for side in [Float(-1), 1] {
            parts.append(Part(name: "fin", centre: SIMD3(side * 0.32, -0.09, 0.04), radii: SIMD3(0.14, 0.065, 0.15), paint: grey))
            parts.append(Part(name: "tail", centre: SIMD3(side * 0.13, -0.015, 0.36), radii: SIMD3(0.19, 0.07, 0.14), paint: grey))
            parts.append(Part(name: "eye", centre: eyeCentre(side: side), radii: eyeRadii, paint: pale))
            parts.append(Part(name: "pupil", centre: pupilCentre(side: side), radii: SIMD3(0.058, 0.11, 0.022), paint: black))
            parts.append(Part(name: "eye-glint", centre: SIMD3(side * 0.12 - 0.015, 0.18, -0.383), radii: SIMD3(0.017, 0.026, 0.008), paint: pale))
        }
        return parts
    }

    static var roundedUnitSphere: MeshPart { unitSphere }

    private static let unitSphere: MeshPart = {
        let slices = 32, bands = 24
        var points = [SIMD3<Float>(0, 1, 0)]
        for band in 1..<bands {
            let phi: Float = Float(band) / Float(bands) * .pi
            for slice in 0..<slices {
                let theta: Float = Float(slice) / Float(slices) * 2 * .pi
                points.append(SIMD3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)))
            }
        }
        let bottom = UInt32(points.count)
        points.append(SIMD3(0, -1, 0))
        func at(_ band: Int, _ slice: Int) -> UInt32 {
            UInt32(1 + (band - 1) * slices + slice % slices)
        }
        var indices: [UInt32] = []
        for slice in 0..<slices {
            indices += [0, at(1, slice + 1), at(1, slice)]
            for band in 1..<(bands - 1) {
                let a = at(band, slice), b = at(band, slice + 1)
                let c = at(band + 1, slice), d = at(band + 1, slice + 1)
                indices += [a, b, c, b, d, c]
            }
            indices += [at(bands - 1, slice), at(bands - 1, slice + 1), bottom]
        }
        return MeshPart(name: "WhaleyRoundedUnitSphere", positions: points,
                        normals: points.map(unit), indices: indices, paint: grey)
    }()

    // Project the original sprite's 32 red mouth pixels onto the body triangles. Image-right is local -x.
    // Relief and boundary walls keep the stepped outline attached to the curved face.
    static var mouth: MeshPart { mouthMesh }

    private static let mouthMesh: MeshPart = {
        let rows = [[10, 11], [10, 11], [6, 7, 10, 11],
                    [0, 2, 3, 5, 6, 7, 8, 9, 10], Array(0...9), [2, 3, 7, 8, 9]]
        let cell = SIMD2<Float>(0.035, 0.024)
        let imageLeftX: Float = 0.21, top: Float = -0.07, relief: Float = 0.002
        let sphere = roundedUnitSphere
        var faces: [[SIMD3<Float>]] = []
        for i in stride(from: 0, to: sphere.indices.count, by: 3) {
            let face = (0..<3).map { sphere.positions[Int(sphere.indices[i + $0])] * bodyRadii }
            if cross(face[1] - face[0], face[2] - face[0]).z < -0.000001 { faces.append(face) }
        }
        var result = MeshPart(name: "WhaleyGrin", positions: [], normals: [], indices: [], paint: red)
        func filled(_ row: Int, _ column: Int) -> Bool {
            rows.indices.contains(row) && rows[row].contains(column)
        }
        for row in rows.indices {
            for column in rows[row] {
                let x1 = imageLeftX - Float(column) * cell.x, x0 = x1 - cell.x
                let y1 = top - Float(row) * cell.y, y0 = y1 - cell.y
                let rectangle = [SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1)]
                for face in faces {
                    let polygon = clip(rectangle, to: face)
                    guard polygon.count >= 3 else { continue }
                    let normal = cross(face[1] - face[0], face[2] - face[0])
                    func surface(_ p: SIMD2<Float>) -> SIMD3<Float> {
                        let z = face[0].z - (normal.x * (p.x - face[0].x) + normal.y * (p.y - face[0].y)) / normal.z
                        return SIMD3(p.x, p.y, z)
                    }
                    let back = polygon.map(surface)
                    let front = back.map { $0 - SIMD3<Float>(0, 0, relief) }
                    let normals = back.map { unit($0 / (bodyRadii * bodyRadii)) }
                    for index in 1..<(front.count - 1) {
                        appendTriangle(front[0], front[index + 1], front[index],
                                       vertexNormals: [normals[0], normals[index + 1], normals[index]], to: &result)
                    }
                    // Only silhouette edges need walls; shared edges already meet at the same depth.
                    for index in polygon.indices {
                        let next = (index + 1) % polygon.count
                        let a = polygon[index], b = polygon[next]
                        func on(_ value: Float, _ other: Float, edge: Float) -> Bool {
                            abs(value - edge) < 0.000001 && abs(other - edge) < 0.000001
                        }
                        let boundary = (on(a.x, b.x, edge: x0) && !filled(row, column + 1))
                            || (on(a.x, b.x, edge: x1) && !filled(row, column - 1))
                            || (on(a.y, b.y, edge: y1) && !filled(row - 1, column))
                            || (on(a.y, b.y, edge: y0) && !filled(row + 1, column))
                        if boundary {
                            appendTriangle(front[index], front[next], back[index], to: &result)
                            appendTriangle(front[next], back[next], back[index], to: &result)
                        }
                    }
                }
            }
        }
        return result
    }()

    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        a.x * b.y - a.y * b.x
    }

    private static func unit(_ v: SIMD3<Float>) -> SIMD3<Float> {
        v / sqrt((v * v).sum())
    }

    private static func appendTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                                       vertexNormals: [SIMD3<Float>]? = nil, to mesh: inout MeshPart) {
        let n = cross(b - a, c - a), squared = (n * n).sum()
        guard squared.isFinite, squared > 1e-20 else { return }
        let normal = n / sqrt(squared), first = UInt32(mesh.positions.count)
        mesh.positions += [a, b, c]
        mesh.normals += vertexNormals ?? [normal, normal, normal]
        mesh.indices += [first, first + 1, first + 2]
    }

    // Sutherland–Hodgman clipping: the body front is clockwise in XY, the cell counterclockwise.
    private static func clip(_ polygon: [SIMD2<Float>], to face: [SIMD3<Float>]) -> [SIMD2<Float>] {
        let triangle = face.map { SIMD2($0.x, $0.y) }
        let sign: Float = cross(triangle[1] - triangle[0], triangle[2] - triangle[0]) < 0 ? -1 : 1
        var result = polygon
        for edge in triangle.indices {
            guard !result.isEmpty else { break }
            let a = triangle[edge], b = triangle[(edge + 1) % triangle.count]
            let input = result
            result = []
            var previous = input[input.count - 1]
            var before = sign * cross(b - a, previous - a)
            for current in input {
                let after = sign * cross(b - a, current - a)
                if (before >= -0.00000001) != (after >= -0.00000001) {
                    let t = min(1, max(0, before / (before - after)))
                    result.append(previous + (current - previous) * t)
                }
                if after >= -0.00000001 { result.append(current) }
                previous = current
                before = after
            }
        }
        return result
    }

    // Mihkli murumüts construction references (cloth wedges, linen binding and top button):
    // https://rahvaroivad.ee/regioonid/laane-eesti/mihkli/mihkli-mees
    // https://rahvaroivad.ee/regioonid/laane-eesti/tori/tori-mees
    private static let hatCentre = SIMD3<Float>(0, 0.27, 0.075)
    private static let hatRadii = SIMD3<Float>(0.24, 0.14, 0.20)
    private static let hatTilt: Float = 25 * .pi / 180

    private static func hatDirection(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let c: Float = cos(hatTilt), s: Float = sin(hatTilt)
        return SIMD3<Float>(v.x, v.y * c - v.z * s, v.y * s + v.z * c)
    }

    private static func hatPoint(_ p: SIMD3<Float>) -> SIMD3<Float> { hatCentre + hatDirection(p) }

    static var hatParts: [MeshPart] {
        let panels = 6, rings = 8, slices = 6
        let sector: Float = 2 * .pi / Float(panels)
        var result: [MeshPart] = []
        for panel in 0..<panels {
            let firstAngle: Float = -.pi / 2 - sector / 2 + Float(panel) * sector
            var points = [hatPoint(SIMD3<Float>(0, hatRadii.y, 0))]
            var normals = [hatDirection(SIMD3<Float>(0, 1, 0))]
            var indices: [UInt32] = []
            for ring in 1...rings {
                let phi: Float = Float(ring) / Float(rings) * .pi / 2
                for slice in 0...slices {
                    let theta: Float = firstAngle + Float(slice) / Float(slices) * sector
                    let p = SIMD3<Float>(hatRadii.x * sin(phi) * cos(theta),
                                         hatRadii.y * cos(phi),
                                         hatRadii.z * sin(phi) * sin(theta))
                    points.append(hatPoint(p))
                    normals.append(hatDirection(unit(p / (hatRadii * hatRadii))))
                }
            }
            for slice in 0..<slices { indices += [0, UInt32(slice + 2), UInt32(slice + 1)] }
            for ring in 0..<(rings - 1) {
                for slice in 0..<slices {
                    let a = UInt32(1 + ring * (slices + 1) + slice)
                    let b = a + 1, c = a + UInt32(slices + 1), d = c + 1
                    indices += [a, b, c, b, d, c]
                }
            }
            result.append(MeshPart(name: "hat-panel-\(panel)", positions: points, normals: normals,
                                   indices: indices, paint: panel.isMultiple(of: 2) ? hatRed : hatBlue))
        }

        let segments = panels * slices
        var points: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        for segment in 0...segments {
            let theta: Float = Float(segment) / Float(segments) * 2 * .pi
            let x: Float = hatRadii.x * 1.015 * cos(theta)
            let z: Float = hatRadii.z * 1.015 * sin(theta)
            let n = hatDirection(unit(SIMD3<Float>(cos(theta) / hatRadii.x, 0, sin(theta) / hatRadii.z)))
            points += [hatPoint(SIMD3<Float>(x, -0.014, z)), hatPoint(SIMD3<Float>(x, 0.006, z))]
            normals += [n, n]
            if segment < segments {
                let a = UInt32(segment * 2), b = a + 1, c = a + 2, d = a + 3
                indices += [a, b, c, b, d, c]
            }
        }
        result.append(MeshPart(name: "hat-rim", positions: points, normals: normals, indices: indices, paint: linen))
        return result
    }
}
