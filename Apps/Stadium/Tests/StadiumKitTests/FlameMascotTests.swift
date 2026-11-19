import Foundation
import Testing
@testable import StadiumKit

private func flameCross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

@Test
func theOriginalFlamePaletteIsVisibleOnBothSidesOfOneRoundSurface() {
    let parts = FlameMascot.parts
    #expect(parts.map(\.paint) == [Paint(1, 0.2, 0), Paint(1, 0.6, 0), Paint(1, 1, 0.2), Paint(1, 1, 1)])
    for part in parts {
        #expect(!part.indices.isEmpty)
        #expect(part.positions.count == part.normals.count)
        #expect(part.positions.contains { $0.z < -0.01 })
        #expect(part.positions.contains { $0.z > 0.01 }, "The rear camera can see every colour too")
        for (position, normal) in zip(part.positions, part.normals) {
            #expect(position.x.isFinite && position.y.isFinite && position.z.isFinite)
            #expect(abs(sqrt((position * position).sum()) - 0.30) < 0.00001,
                    "Every colour lies on the same orb, rather than a hidden inner shell")
            #expect(abs((normal * normal).sum() - 1) < 0.00001)
            #expect((position * normal).sum() > 0)
        }
    }
    let white = parts[3].positions
    #expect(white.allSatisfy { abs($0.z) > FlameMascot.radius * 0.95 },
            "White is a small front/rear core, not a stripe around the orb")
}

@Test
func theFlameMeshHasOutwardFacesAndNoOpenOrOverlappingEdges() {
    struct Point: Hashable {
        let x: Int, y: Int, z: Int
        init(_ value: SIMD3<Float>) {
            x = Int((value.x * 1_000_000).rounded())
            y = Int((value.y * 1_000_000).rounded())
            z = Int((value.z * 1_000_000).rounded())
        }
    }
    // Weld by position to test topology across flat-normal and material boundaries.
    struct Edge: Hashable {
        let first: Point, second: Point
    }
    var directed: [Edge: Int] = [:]
    for part in FlameMascot.parts {
        #expect(part.indices.count.isMultiple(of: 3))
        for triangle in stride(from: 0, to: part.indices.count, by: 3) {
            let ids = part.indices[triangle..<(triangle + 3)].map(Int.init)
            #expect(ids.allSatisfy { part.positions.indices.contains($0) })
            guard ids.allSatisfy({ part.positions.indices.contains($0) }) else { continue }
            let a = part.positions[ids[0]], b = part.positions[ids[1]], c = part.positions[ids[2]]
            #expect((flameCross(b - a, c - a) * (a + b + c)).sum() > 0,
                    "Every nondegenerate triangle faces outwards")
            for (first, second) in [(a, b), (b, c), (c, a)] {
                directed[Edge(first: Point(first), second: Point(second)), default: 0] += 1
            }
        }
    }
    #expect(!directed.isEmpty)
    for (edge, count) in directed {
        #expect(count == 1)
        #expect(directed[Edge(first: edge.second, second: edge.first)] == 1,
                "Every boundary joins exactly one neighbouring face")
    }
}

@Test
func theFlameUsesBroadFlatFacetsInsteadOfSmoothVertexNormals() {
    let parts = FlameMascot.parts
    let triangles = parts.reduce(0) { $0 + $1.indices.count / 3 }
    #expect(triangles > 100 && triangles < 600, "The driver uses a small, visibly faceted mesh")
    for part in parts {
        for triangle in stride(from: 0, to: part.indices.count, by: 3) {
            let ids = part.indices[triangle..<(triangle + 3)].map(Int.init)
            let a = part.positions[ids[0]], b = part.positions[ids[1]], c = part.positions[ids[2]]
            let normal = part.normals[ids[0]]
            #expect(part.normals[ids[1]] == normal && part.normals[ids[2]] == normal)
            #expect(abs((normal * (b - a)).sum()) < 0.000001)
            #expect(abs((normal * (c - a)).sum()) < 0.000001)
            let difference = normal - a / FlameMascot.radius
            #expect((difference * difference).sum() > 0.001,
                    "A face normal must not be interpolated from the sphere's radial normals")
        }
    }
}

@Test
func theFlameRollUsesTheLegacyRateAndDoesNotAccumulateAcrossRedraws() {
    #expect(FlameMascot.roll(at: 0) == 0)
    #expect(abs(FlameMascot.roll(at: 30) - .pi / 6) < 0.00001)
    #expect(abs(FlameMascot.roll(at: 180) - .pi) < 0.00001)
    #expect(FlameMascot.roll(at: 360) == 0)
    for tick in [0, 17, 60, 359, 720, 1_000_000] {
        let angle = FlameMascot.roll(at: tick)
        #expect(angle == FlameMascot.roll(at: tick))
        #expect(angle == FlameMascot.roll(at: tick + 360))
        #expect(angle.isFinite && angle >= 0 && angle < 2 * .pi)
    }
}
