// Progress is arc length from point zero; side is signed right of the travel direction.

import StadiumCore

public struct Track: Hashable, Sendable {
    public let points: [GroundPoint]
    public let roadHalf: Fixed
    public let segment: [GroundPoint]      // (ex, ez) per segment
    public let segmentLength: [Fixed]
    public let cumulative: [Fixed]         // cumulative[i] is the length to point i; the final entry closes the loop.
    public var total: Fixed { cumulative[points.count] }

    public struct Location: Hashable, Sendable {
        public var progress: Fixed
        public var offset: Fixed
        public var side: Fixed
        public var segment: Int
    }

    public init(points: [GroundPoint], roadHalf: Fixed) {
        self.points = points
        self.roadHalf = roadHalf
        var seg: [GroundPoint] = []
        var lengths: [Fixed] = []
        var cum: [Fixed] = [.zero]
        let n = points.count
        for i in 0..<n {
            let a = points[i], b = points[(i + 1) % n]
            let e = GroundPoint(b.x - a.x, b.z - a.z)
            seg.append(e)
            let length = Fixed.sqrt(e.x * e.x + e.z * e.z)
            lengths.append(length)
            cum.append(cum[cum.count - 1] + length)
        }
        segment = seg
        segmentLength = lengths
        cumulative = cum
    }

    public init(parameters p: KartParameters) {
        self.init(points: p.trackPoints, roadHalf: p.roadHalf)
    }

    public func locate(x: Fixed, z: Fixed) -> Location {
        var bestD2 = Fixed.zero
        var bestIndex = -1
        var bestT = Fixed.zero
        let n = points.count
        for i in 0..<n {
            let a = points[i]
            let e = segment[i]
            let px = x - a.x, pz = z - a.z
            let len2 = e.x * e.x + e.z * e.z
            let dot = px * e.x + pz * e.z
            let t = (dot / len2).clamped(.zero, .one)
            let cx = a.x + e.x * t, cz = a.z + e.z * t
            let dx = x - cx, dz = z - cz
            let d2 = dx * dx + dz * dz
            if bestIndex < 0 || d2 < bestD2 {
                bestD2 = d2; bestIndex = i; bestT = t
            }
        }
        let a = points[bestIndex], e = segment[bestIndex]
        let cx = a.x + e.x * bestT, cz = a.z + e.z * bestT
        let side = ((x - cx) * e.z - (z - cz) * e.x) / segmentLength[bestIndex]
        return Location(progress: cumulative[bestIndex] + segmentLength[bestIndex] * bestT,
                        offset: Fixed.sqrt(bestD2), side: side, segment: bestIndex)
    }

    public func point(atProgress s: Fixed) -> GroundPoint {
        let d = Fixed(raw: floorMod(s.raw, total.raw))
        var i = 0
        while i < points.count - 1 && cumulative[i + 1] <= d { i += 1 }
        let length = segmentLength[i]
        let t = Fixed.zero < length ? ((d - cumulative[i]) / length).clamped(.zero, .one) : .zero
        let a = points[i], e = segment[i]
        return GroundPoint(a.x + e.x * t, a.z + e.z * t)
    }

    public func direction(atProgress s: Fixed) -> GroundPoint {
        let d = Fixed(raw: floorMod(s.raw, total.raw))
        var i = 0
        while i < points.count - 1 && cumulative[i + 1] <= d { i += 1 }
        let length = segmentLength[i]
        let e = segment[i]
        return Fixed.zero < length ? GroundPoint(e.x / length, e.z / length) : GroundPoint(.zero, .one)
    }
}
