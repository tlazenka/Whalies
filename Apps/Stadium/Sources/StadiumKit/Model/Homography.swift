import Foundation
#if canImport(simd)
import simd
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif

/// Row-major 3x3 projective matrix; the last row supplies the homogeneous denominator.
struct Homography: Equatable {
    var m: [Double]

    /// Heckbert square-to-quad map; corners are top-left, top-right, bottom-right, bottom-left.
    init?(width w: Double, height h: Double, to q: [CGPoint]) {
        guard q.count == 4, w > 0, h > 0 else { return nil }
        let x0 = Double(q[0].x), y0 = Double(q[0].y), x1 = Double(q[1].x), y1 = Double(q[1].y)
        let x2 = Double(q[2].x), y2 = Double(q[2].y), x3 = Double(q[3].x), y3 = Double(q[3].y)
        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
        var g = 0.0, k = 0.0
        if abs(dx3) > 1e-9 || abs(dy3) > 1e-9 {
            let den = dx1 * dy2 - dx2 * dy1
            guard abs(den) > 1e-12 else { return nil }
            g = (dx3 * dy2 - dx2 * dy3) / den
            k = (dx1 * dy3 - dx3 * dy1) / den
        }
        let a = x1 - x0 + g * x1, b = x3 - x0 + k * x3, c = x0
        let d = y1 - y0 + g * y1, e = y3 - y0 + k * y3, f = y0
        m = [a / w, b / h, c, d / w, e / h, f, g / w, k / h, 1]
    }

    func apply(_ p: CGPoint) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        let d = m[6] * x + m[7] * y + m[8]
        return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / d, y: (m[3] * x + m[4] * y + m[5]) / d)
    }

    #if canImport(QuartzCore)
    // Core Animation uses row vectors, with the projective denominator in the w column.
    var transform: CATransform3D {
        var t = CATransform3DIdentity
        t.m11 = CGFloat(m[0]); t.m21 = CGFloat(m[1]); t.m41 = CGFloat(m[2])
        t.m12 = CGFloat(m[3]); t.m22 = CGFloat(m[4]); t.m42 = CGFloat(m[5])
        t.m14 = CGFloat(m[6]); t.m24 = CGFloat(m[7]); t.m44 = CGFloat(m[8])
        return t
    }
    #endif
}

enum ScreenCorners {
    /// Corners must be clockwise on screen. Reject backfaces, edge-on screens and hidden corners.
    static func project(_ corners: [SIMD3<Float>], camera: PinholeCamera, viewSize: CGSize) -> [CGPoint]? {
        let size = SIMD2(Float(viewSize.width), Float(viewSize.height))
        var points: [CGPoint] = []
        for c in corners {
            guard let q = camera.project(c, viewSize: size) else { return nil }
            points.append(CGPoint(x: CGFloat(q.x), y: CGFloat(q.y)))
        }
        guard points.count == 4 else { return nil }
        var area: CGFloat = 0
        for i in 0..<4 {
            let a = points[i], b = points[(i + 1) % 4]
            area += a.x * b.y - b.x * a.y
        }
        return area > 4 ? points : nil
    }
}
