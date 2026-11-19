import Foundation
import Testing
@testable import StadiumKit

private func roundedCross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

private func roundedCross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    a.x * b.y - a.y * b.x
}

private func roundedTriangles(_ mesh: WhaleyMascot.MeshPart) -> [[SIMD3<Float>]] {
    stride(from: 0, to: mesh.indices.count, by: 3).map { i in
        (0..<3).map { mesh.positions[Int(mesh.indices[i + $0])] }
    }
}

private func validateRoundedMesh(_ mesh: WhaleyMascot.MeshPart) throws {
    try #require(!mesh.positions.isEmpty && !mesh.indices.isEmpty)
    try #require(mesh.positions.count == mesh.normals.count && mesh.indices.count.isMultiple(of: 3))
    try #require(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
    for i in stride(from: 0, to: mesh.indices.count, by: 3) {
        let indices = (0..<3).map { Int(mesh.indices[i + $0]) }
        let a = mesh.positions[indices[0]], b = mesh.positions[indices[1]], c = mesh.positions[indices[2]]
        let cross = roundedCross(b - a, c - a)
        let length = sqrt((cross * cross).sum())
        #expect(length.isFinite && length > 0)
        let expected = cross / length
        for index in indices {
            let n = mesh.normals[index]
            #expect(n.x.isFinite && n.y.isFinite && n.z.isFinite)
            #expect(abs((n * n).sum() - 1) < 0.0001)
            #expect((n * expected).sum() > 0,
                    "Vertex normals face the same way as the triangle's outward winding")
        }
    }
}

private func containsProjection(_ point: SIMD2<Float>, _ triangle: [SIMD3<Float>]) -> Bool {
    let p = triangle.map { SIMD2($0.x, $0.y) }
    let area = roundedCross(p[1] - p[0], p[2] - p[0])
    guard abs(area) > 0.000000001 else { return false }
    let distances = (0..<3).map { roundedCross(p[($0 + 1) % 3] - p[$0], point - p[$0]) }
    return distances.allSatisfy { $0 >= -0.00000001 } || distances.allSatisfy { $0 <= 0.00000001 }
}

@Test
func whaleyUsesABoundedSmoothMeshForItsRoundedParts() throws {
    let sphere = WhaleyMascot.roundedUnitSphere
    try validateRoundedMesh(sphere)
    #expect(sphere.indices.count / 3 <= 1600)
    #expect(sphere.positions.count < sphere.indices.count / 2,
            "Neighbouring triangles share smooth vertex normals")
    for (index, p) in sphere.positions.enumerated() {
        #expect(abs((p * p).sum() - 1) < 0.00001)
        let difference = sphere.normals[index] - p
        #expect((difference * difference).sum() < 0.0000001,
                "Radial normals keep lighting smooth when the mesh becomes an ellipsoid")
    }
    for triangle in roundedTriangles(sphere) {
        let normal = roundedCross(triangle[1] - triangle[0], triangle[2] - triangle[0])
        let centre = (triangle[0] + triangle[1] + triangle[2]) / 3
        #expect((normal * centre).sum() > 0)
        #expect(sqrt((centre * centre).sum()) > 0.99,
                "The body mesh closely follows the round surface, including between vertices")
    }
    let poleNormals = sphere.positions.enumerated().filter { $0.element.y > 0.9999 }.map { sphere.normals[$0.offset] }
    #expect(poleNormals.allSatisfy { abs($0.x) < 0.00001 && $0.y > 0.9999 && abs($0.z) < 0.00001 })
    #expect(!WhaleyMascot.parts.contains { $0.name == "smile" },
            "The original stepped grin remains one mesh, without rounded smile pieces")
}

@Test
func whaleysRoundedCapPreservesItsPanelsAndBlowholeClearance() throws {
    let hat = WhaleyMascot.hatParts
    try #require(hat.count == 7)
    #expect(hat.reduce(0) { $0 + $1.indices.count / 3 } <= 700)
    for (index, part) in hat.enumerated() {
        try validateRoundedMesh(part)
        #expect(part.positions.count < part.indices.count,
                "The cloth and binding reuse smooth vertices around the cap")
        #expect(part.positions.allSatisfy { $0.z > WhaleyMascot.blowhole.z + 0.032 },
                "The rounded cap stays behind the full blowhole opening")
        if index < 6 {
            #expect(part.paint == (index.isMultiple(of: 2) ? WhaleyMascot.hatRed : WhaleyMascot.hatBlue))
        } else {
            #expect(part.paint == WhaleyMascot.linen)
        }
    }
    for panel in 0..<6 {
        let a = hat[panel], b = hat[(panel + 1) % 6]
        var shared = 0
        for index in a.positions.indices {
            if let other = b.positions.firstIndex(where: {
                let difference = $0 - a.positions[index]
                return (difference * difference).sum() < 0.0000000001
            }) {
                shared += 1
                let difference = a.normals[index] - b.normals[other]
                #expect((difference * difference).sum() < 0.0000001,
                        "Separate cloth colours meet with continuous smooth lighting")
            }
        }
        #expect(shared >= 8, "Adjacent cap panels share the full seam, including the crown")
    }
}

@Test
func whaleysGrinPreservesTheOriginalMaskAndLowImageLeftCorner() throws {
    let mouth = WhaleyMascot.mouth
    try validateRoundedMesh(mouth)
    #expect(mouth.paint == WhaleyMascot.red)
    let front = roundedTriangles(mouth).filter { roundedCross($0[1] - $0[0], $0[2] - $0[0]).z < -0.000000001 }
    try #require(!front.isEmpty)
    let mask = [[10, 11], [10, 11], [6, 7, 10, 11],
                [0, 2, 3, 5, 6, 7, 8, 9, 10], Array(0...9), [2, 3, 7, 8, 9]]
    var covered = 0
    for row in 0..<6 {
        for column in 0..<12 {
            // Viewed from the mascot's -z side, screen-right is local -x.
            let centre = SIMD2<Float>(0.21 - (Float(column) + 0.5) * 0.035,
                                      -0.07 - (Float(row) + 0.5) * 0.024)
            let visible = front.contains { containsProjection(centre, $0) }
            #expect(visible == mask[row].contains(column), "Original mouth cell \(column),\(row)")
            if visible { covered += 1 }
        }
    }
    #expect(covered == 32)
    let projectedArea = front.reduce(Float(0)) { total, triangle in
        total + abs(roundedCross(triangle[1] - triangle[0], triangle[2] - triangle[0]).z) / 2
    }
    #expect(abs(projectedArea - 32 * 0.035 * 0.024) < 0.000005,
            "Body-mesh clipping neither fills the grin's notches nor leaves gaps")
    let imageLeftTop = try #require(mouth.positions.filter { $0.x > 0.17 }.map(\.y).max())
    let imageRightTop = try #require(mouth.positions.filter { $0.x < -0.17 }.map(\.y).max())
    #expect(imageLeftTop < imageRightTop - 0.06,
            "The image-left edge stays low; the opposite snout corner carries the tall upturn")
    #expect(mouth.positions.allSatisfy { $0.y <= -0.06999 }, "The grin stays below the eye whites")
}

@Test
func whaleysSteppedGrinFollowsTheRoundedFaceWithSmoothLighting() throws {
    let body = try #require(WhaleyMascot.parts.first { $0.name == "body" })
    let faces = roundedTriangles(WhaleyMascot.roundedUnitSphere).map { triangle in
        triangle.map { $0 * body.radii + body.centre }
    }.filter { roundedCross($0[1] - $0[0], $0[2] - $0[0]).z < -0.000001 }
    func depth(at point: SIMD3<Float>) -> Float? {
        faces.filter { containsProjection(SIMD2(point.x, point.y), $0) }.map { triangle in
            let n = roundedCross(triangle[1] - triangle[0], triangle[2] - triangle[0])
            return triangle[0].z - (n.x * (point.x - triangle[0].x) + n.y * (point.y - triangle[0].y)) / n.z
        }.min()
    }
    let mouth = WhaleyMascot.mouth
    for p in mouth.positions {
        let bodyDepth = try #require(depth(at: p))
        #expect(bodyDepth - p.z >= -0.00001 && bodyDepth - p.z <= 0.00201,
                "Every mouth edge reaches the face or its shallow red relief")
    }
    for i in stride(from: 0, to: mouth.indices.count, by: 3) {
        let indices = (0..<3).map { Int(mouth.indices[i + $0]) }
        let triangle = indices.map { mouth.positions[$0] }
        let normal = roundedCross(triangle[1] - triangle[0], triangle[2] - triangle[0])
        guard normal.z < -0.000000001 else { continue }
        let centre = (triangle[0] + triangle[1] + triangle[2]) / 3
        let bodyDepth = try #require(depth(at: centre))
        #expect(abs(bodyDepth - centre.z - 0.002) < 0.00001,
                "Front triangles follow the actual rounded mesh without floating or crossing it")
        for index in indices {
            let back = mouth.positions[index] + SIMD3<Float>(0, 0, 0.002)
            let direction = (back - body.centre) / (body.radii * body.radii)
            let expected = direction / sqrt((direction * direction).sum())
            let difference = mouth.normals[index] - expected
            #expect((difference * difference).sum() < 0.0000001,
                    "The stepped silhouette has smoothly rounded front lighting")
        }
    }
}

private func roundedEyeHull(_ points: [SIMD3<Float>]) -> [SIMD2<Float>] {
    let sorted = points.map { SIMD2($0.x, $0.y) }.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
    var unique: [SIMD2<Float>] = []
    for p in sorted where unique.last != p { unique.append(p) }
    func half(_ sequence: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var hull: [SIMD2<Float>] = []
        for p in sequence {
            while hull.count > 1 && roundedCross(hull[hull.count - 1] - hull[hull.count - 2], p - hull[hull.count - 1]) <= 0.0000001 {
                hull.removeLast()
            }
            hull.append(p)
        }
        return hull
    }
    return Array(half(unique).dropLast()) + Array(half(Array(unique.reversed())).dropLast())
}

@Test
func movingPupilsRemainInsideTheActualRoundedEyeSilhouette() throws {
    let sphere = WhaleyMascot.roundedUnitSphere
    let hull = roundedEyeHull(sphere.positions)
    try #require(hull.count >= 32)
    let parts = WhaleyMascot.parts
    var clearance = Float.greatestFiniteMagnitude
    for side in [Float(-1), 1] {
        let eye = try #require(parts.first { $0.name == "eye" && $0.centre.x * side > 0 })
        let pupil = try #require(parts.first { $0.name == "pupil" && $0.centre.x * side > 0 })
        for yawDegrees in [Float(-40), 0, 40] {
            for pitchDegrees in [Float(-35), 0, 35] {
                let yaw = yawDegrees * .pi / 180, pitch = pitchDegrees * .pi / 180
                let gaze = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
                let offset = WhaleyMascot.gazeOffset(for: pupil, toward: gaze)
                for vertex in sphere.positions {
                    let p = (pupil.centre + offset + vertex * pupil.radii - eye.centre) / eye.radii
                    for edge in hull.indices {
                        let a = hull[edge], b = hull[(edge + 1) % hull.count]
                        let vector = b - a
                        let distance = roundedCross(vector, SIMD2(p.x, p.y) - a) / sqrt((vector * vector).sum())
                        clearance = min(clearance, distance)
                    }
                }
            }
        }
    }
    #expect(clearance > 0.03,
            "Pupils retain a margin inside the actual rounded whites at maximum gaze")
}
