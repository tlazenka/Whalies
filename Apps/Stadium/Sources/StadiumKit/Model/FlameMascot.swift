import Foundation

// A single coloured surface keeps the bright centre visible without nested opaque shells.
enum FlameMascot {
    struct MeshPart {
        var name: String
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var indices: [UInt32]
        var paint: Paint
    }

    static let radius: Float = 0.30
    static let palette = [Paint(1, 0.2, 0), Paint(1, 0.6, 0), Paint(1, 1, 0.2), Paint(1, 1, 1)]

    // Match the legacy sprite's 30 degrees per half-second on the 60 Hz simulation clock.
    static func roll(at tick: Int) -> Float {
        let remainder = tick % 360
        let phase = remainder < 0 ? remainder + 360 : remainder
        return Float(phase) * (2 * .pi / 360)
    }

    // Sample band boundaries from the original 24x24 sprite's positive quadrant.
    private static func band(at point: SIMD3<Float>) -> Int {
        let x = min(11, Int(abs(point.x / radius) * 12))
        let y = min(11, Int(abs(point.y / radius) * 12))
        if x < 2 && y < 2 { return 3 }
        let yellow = [6, 6, 6, 3, 3, 3, 0, 0, 0, 0, 0, 0]
        if x < yellow[y] { return 2 }
        let orange = [9, 9, 9, 7, 6, 6, 4, 3, 3, 0, 0, 0]
        return x < orange[y] ? 1 : 0
    }

    static var parts: [MeshPart] {
        let rings = 12, slices = 24
        func point(ring: Float, slice: Float) -> SIMD3<Float> {
            let latitude: Float = ring / Float(rings) * .pi
            let longitude: Float = slice / Float(slices) * 2 * .pi
            return SIMD3<Float>(sin(latitude) * cos(longitude),
                                sin(latitude) * sin(longitude), -cos(latitude)) * radius
        }

        // Share pole and seam positions to avoid degenerate faces and a floating-point crack at 2π.
        var vertices = [SIMD3<Float>(0, 0, -radius)]
        for ring in 1..<rings {
            for slice in 0..<slices { vertices.append(point(ring: Float(ring), slice: Float(slice))) }
        }
        let back = vertices.count
        vertices.append(SIMD3<Float>(0, 0, radius))
        func vertex(_ ring: Int, _ slice: Int) -> Int {
            if ring == 0 { return 0 }
            if ring == rings { return back }
            return 1 + (ring - 1) * slices + slice % slices
        }

        var parts = palette.enumerated().map {
            MeshPart(name: "flame-band-\($0.offset)", positions: [], normals: [], indices: [], paint: $0.element)
        }
        func triangle(_ a: Int, _ b: Int, _ c: Int, band: Int) {
            let u = vertices[b] - vertices[a], v = vertices[c] - vertices[a]
            let cross = SIMD3<Float>(u.y * v.z - u.z * v.y,
                                     u.z * v.x - u.x * v.z,
                                     u.x * v.y - u.y * v.x)
            let normal = cross / sqrt((cross * cross).sum())
            // Separate render vertices preserve flat normals at each edge.
            for original in [a, b, c] {
                let index = UInt32(parts[band].positions.count)
                parts[band].positions.append(vertices[original])
                parts[band].normals.append(normal)
                parts[band].indices.append(index)
            }
        }

        for ring in 0..<rings {
            for slice in 0..<slices {
                let colour = band(at: point(ring: Float(ring) + 0.5, slice: Float(slice) + 0.5))
                let a = vertex(ring, slice), b = vertex(ring, slice + 1)
                let c = vertex(ring + 1, slice), d = vertex(ring + 1, slice + 1)
                if ring == 0 {
                    triangle(a, d, c, band: colour)
                } else if ring == rings - 1 {
                    triangle(a, b, c, band: colour)
                } else {
                    triangle(a, b, c, band: colour)
                    triangle(b, d, c, band: colour)
                }
            }
        }
        return parts
    }
}
