import Foundation
import CrowdCore

/// Shared billboard/Jumbotron polygons, in metres on a camera-facing plane.
enum ThoughtArtwork {
    enum Layer: Equatable { case bubble, symbol }

    struct Shape: Equatable {
        var layer: Layer
        var points: [SIMD2<Float>]
        var paint: Paint
    }

    // Quantize the reel to twelve positions per symbol to bound the world mesh cache.
    struct Key: Hashable {
        var symbol: ThoughtSymbol
        var next: ThoughtSymbol
        var step: Int

        init(_ frame: ThoughtFrame) {
            symbol = frame.symbol
            next = frame.isSpinning ? frame.nextSymbol : frame.symbol
            step = frame.isSpinning ? min(11, max(0, Int(frame.progress * 12))) : 0
        }
    }

    static let aboveHead: Float = 0.66
    static let ink = Paint(0.11, 0.18, 0.25)
    static let paper = Paint(1, 1, 1)
    static let well = Paint(0.9, 0.95, 0.98)

    private static func ellipse(_ centre: SIMD2<Float>, _ radius: SIMD2<Float>, _ paint: Paint,
                                layer: Layer = .symbol) -> Shape {
        Shape(layer: layer, points: (0..<32).map { n in
            let a = Float(n) * 2 * .pi / 32
            return centre + SIMD2(cos(a) * radius.x, sin(a) * radius.y)
        }, paint: paint)
    }

    private static func line(_ a: SIMD2<Float>, _ b: SIMD2<Float>, width: Float, paint: Paint) -> Shape {
        let d = b - a
        let length = (d.x * d.x + d.y * d.y).squareRoot()
        let side = SIMD2(-d.y, d.x) * (width / max(length, 0.001) / 2)
        return Shape(layer: .symbol, points: [a - side, b - side, b + side, a + side], paint: paint)
    }

    // Draw portable glyphs without relying on platform SF Symbol availability.
    static func glyph(_ symbol: ThoughtSymbol) -> [Shape] {
        switch symbol {
        case .hotDog:
            let bun = Paint(0.91, 0.65, 0.3), sausage = Paint(0.69, 0.19, 0.1), mustard = Paint(1, 0.86, 0.08)
            var shapes = [ellipse(.zero, SIMD2(0.98, 0.5), ink),
                          ellipse(.zero, SIMD2(0.91, 0.43), bun),
                          ellipse(SIMD2(0, 0.05), SIMD2(0.88, 0.23), sausage)]
            let stripe: [SIMD2<Float>] = [SIMD2(-0.65, 0.05), SIMD2(-0.4, 0.13), SIMD2(-0.15, -0.03),
                                         SIMD2(0.1, 0.13), SIMD2(0.35, -0.03), SIMD2(0.62, 0.08)]
            for n in 1..<stripe.count { shapes.append(line(stripe[n - 1], stripe[n], width: 0.09, paint: mustard)) }
            return shapes.map { shape in
                var rotated = shape
                let a: Float = 0.22
                rotated.points = shape.points.map { SIMD2($0.x * cos(a) - $0.y * sin(a), $0.x * sin(a) + $0.y * cos(a)) }
                return rotated
            }
        case .baseball:
            var shapes = [ellipse(.zero, SIMD2(repeating: 0.74), ink), ellipse(.zero, SIMD2(repeating: 0.65), paper)]
            let red = Paint(0.8, 0.18, 0.15)
            for side in [Float(-1), 1] {
                let seam: [SIMD2<Float>] = (0...6).map { n in
                    let y = Float(n) * 0.18 - 0.54
                    return SIMD2(side * (0.28 + 0.3 * y * y), y)
                }
                for n in 1..<seam.count { shapes.append(line(seam[n - 1], seam[n], width: 0.045, paint: red)) }
                for p in seam { shapes.append(line(p + SIMD2(-0.08, -0.04), p + SIMD2(0.08, 0.04), width: 0.04, paint: red)) }
            }
            return shapes
        case .music:
            return [ellipse(SIMD2(-0.39, -0.4), SIMD2(0.25, 0.17), ink),
                    ellipse(SIMD2(0.35, -0.25), SIMD2(0.25, 0.17), ink),
                    line(SIMD2(-0.19, -0.4), SIMD2(-0.19, 0.54), width: 0.13, paint: ink),
                    line(SIMD2(0.55, -0.25), SIMD2(0.55, 0.69), width: 0.13, paint: ink),
                    Shape(layer: .symbol, points: [SIMD2(-0.25, 0.35), SIMD2(0.61, 0.5), SIMD2(0.61, 0.75), SIMD2(-0.25, 0.6)], paint: ink)]
        case .star:
            let gold = Paint(1, 0.73, 0.06)
            var shapes: [Shape] = []
            // Convex wedges keep clipping and triangulation simple.
            for (radius, inner, paint) in [(Float(0.84), Float(0.37), ink), (Float(0.73), Float(0.32), gold)] {
                let inside: [SIMD2<Float>] = (0..<5).map { n in
                    let a = .pi / 2 + Float(n) * 2 * .pi / 5 + .pi / 5
                    return SIMD2(cos(a), sin(a)) * inner
                }
                shapes.append(Shape(layer: .symbol, points: inside, paint: paint))
                for n in 0..<5 {
                    let a = Float.pi / 2 + Float(n) * 2 * .pi / 5
                    shapes.append(Shape(layer: .symbol, points: [inside[(n + 4) % 5], SIMD2(cos(a), sin(a)) * radius, inside[n]], paint: paint))
                }
            }
            return shapes
        }
    }

    /// Clip adjacent symbols to one slot; positive y is up.
    static func shapes(for key: Key) -> [Shape] {
        var shapes = [ellipse(SIMD2(-0.3, -0.33), SIMD2(repeating: 0.11), ink, layer: .bubble),
                      ellipse(SIMD2(-0.3, -0.33), SIMD2(repeating: 0.08), paper, layer: .bubble),
                      ellipse(SIMD2(-0.4, -0.46), SIMD2(repeating: 0.055), ink, layer: .bubble),
                      ellipse(SIMD2(-0.4, -0.46), SIMD2(repeating: 0.035), paper, layer: .bubble),
                      ellipse(.zero, SIMD2(0.64, 0.36), ink, layer: .bubble),
                      ellipse(.zero, SIMD2(0.61, 0.33), paper, layer: .bubble),
                      Shape(layer: .bubble, points: [SIMD2(-0.41, -0.25), SIMD2(0.41, -0.25), SIMD2(0.41, 0.25), SIMD2(-0.41, 0.25)], paint: well)]
        let progress: Float = Float(key.step) / 12
        let travel: Float = 0.65
        let slots: [(ThoughtSymbol, Float)]
        if key.step == 0 {
            slots = [(key.symbol, .zero)]
        } else {
            slots = [
                (key.symbol, -progress * travel),
                (key.next, (1 - progress) * travel),
            ]
        }
        for (symbol, offset) in slots {
            for var shape in glyph(symbol) {
                shape.points = clip(shape.points.map { $0 * 0.34 + SIMD2(0, offset) })
                if shape.points.count >= 3 { shapes.append(shape) }
            }
        }
        return shapes
    }

    // Sutherland–Hodgman clipping against the slot bounds.
    private static func clip(_ source: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var points = source
        for (axis, boundary, greater) in [(0, Float(-0.4), true), (0, Float(0.4), false), (1, Float(-0.24), true), (1, Float(0.24), false)] {
            guard let last = points.last else { return [] }
            var previous = last
            var output: [SIMD2<Float>] = []
            func inside(_ p: SIMD2<Float>) -> Bool { greater ? p[axis] >= boundary : p[axis] <= boundary }
            for current in points {
                if inside(current) != inside(previous) {
                    let t = (boundary - previous[axis]) / (current[axis] - previous[axis])
                    output.append(previous + (current - previous) * t)
                }
                if inside(current) { output.append(current) }
                previous = current
            }
            points = output
        }
        return points
    }
}
