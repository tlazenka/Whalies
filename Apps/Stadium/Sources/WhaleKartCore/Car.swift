import StadiumCore

public struct Car: Hashable, Sendable, Codable {
    public var x: Fixed
    public var z: Fixed
    /// Turns: zero faces +z; positive turns rotate toward +x.
    public var heading: Fixed
    /// Turns per second.
    public var yawRate: Fixed = .zero
    public var speed: Fixed = .zero
    public var progress: Fixed
    public var offset: Fixed
    public var side: Fixed
    public var segment: Int
    public var offTrack: Bool = false

    public init(parameters p: KartParameters, track: Track) {
        x = track.points[0].x
        z = track.points[0].z
        heading = Trig.bearing(dx: track.segment[0].x, dz: track.segment[0].z)
        let at = track.locate(x: x, z: z)
        progress = at.progress; offset = at.offset; side = at.side; segment = at.segment
    }

    public var position: Vec3 { Vec3(x, .zero, z) }

    public func hitch(_ p: KartParameters, string s: Int) -> Vec3 {
        let f = Trig.forward(heading), r = Trig.right(heading)
        let h = p.hitches[s]
        return Vec3(x - f.x * p.hitchOffset + r.x * h, p.canRadius, z - f.z * p.hitchOffset + r.z * h)
    }

    /// Car-relative coordinates: dx points right; dz points forward from the rear.
    public func localToWorld(_ p: KartParameters, dx: Fixed, dz: Fixed) -> Vec3 {
        let f = Trig.forward(heading), r = Trig.right(heading)
        let along = dz - p.hitchOffset
        return Vec3(x + r.x * dx + f.x * along, p.canRadius, z + r.z * dx + f.z * along)
    }

    public func localVelocityToWorld(vx: Fixed, vz: Fixed) -> Vec3 {
        let f = Trig.forward(heading), r = Trig.right(heading)
        return Vec3(r.x * vx + f.x * vz, .zero, r.z * vx + f.z * vz)
    }

    public func worldToLocal(_ p: KartParameters, x wx: Fixed, z wz: Fixed) -> (dx: Fixed, dz: Fixed) {
        let f = Trig.forward(heading), r = Trig.right(heading)
        let ex = wx - x, ez = wz - z
        return (r.x * ex + r.z * ez, f.x * ex + f.z * ez + p.hitchOffset)
    }

    public mutating func step(parameters p: KartParameters, track: Track) {
        let r = Trig.right(heading)
        let aim = track.point(atProgress: progress + p.lookahead)
        let dx = aim.x - x, dz = aim.z - z
        let side = dx * r.x + dz * r.z
        let d2 = dx * dx + dz * dz
        yawRate = Fixed.zero < d2 ? (((p.steerGain * speed) * side) / d2).clamped(-p.yawMax, p.yawMax) : .zero
        heading = Fixed(raw: Trig.normalize(heading.raw + (yawRate * p.dt).raw))
        speed += (p.cruiseSpeed - speed).clamped(-(p.decel * p.dt), p.accel * p.dt)
        let f = Trig.forward(heading)
        x += (f.x * speed) * p.dt
        z += (f.z * speed) * p.dt
        let at = track.locate(x: x, z: z)
        progress = at.progress; offset = at.offset; self.side = at.side; segment = at.segment
        offTrack = p.roadHalf < offset
    }

    @discardableResult
    public mutating func step(parameters p: KartParameters, track: Track, steer: Fixed, railHalf: Fixed) -> Bool {
        var turn = (steer.clamped(-.one, .one) * p.yawMax) * p.dt
        heading = Fixed(raw: Trig.normalize(heading.raw + turn.raw))
        speed += (p.cruiseSpeed - speed).clamped(-(p.decel * p.dt), p.accel * p.dt)
        let f = Trig.forward(heading)
        x += (f.x * speed) * p.dt
        z += (f.z * speed) * p.dt
        var at = track.locate(x: x, z: z)
        var railed = false
        if railHalf < at.offset {
            // Limit rail correction to full steering speed so the following camera stays smooth.
            let c = track.point(atProgress: at.progress)
            let nx = (x - c.x) / at.offset, nz = (z - c.z) / at.offset
            x = c.x + nx * railHalf
            z = c.z + nz * railHalf
            let e = track.direction(atProgress: at.progress)
            var d = Trig.normalize(Trig.bearing(dx: e.x, dz: e.z).raw - heading.raw)
            if d > Trig.turn / 2 { d -= Trig.turn }
            if d > Trig.quarter { d -= Trig.turn / 2 } else if d < -Trig.quarter { d += Trig.turn / 2 }
            let most = (p.yawMax * p.dt).raw
            d = min(max(d, -most), most)
            heading = Fixed(raw: Trig.normalize(heading.raw + d))
            turn += Fixed(raw: d)
            at = track.locate(x: x, z: z)
            railed = true
        }
        yawRate = turn / p.dt
        progress = at.progress; offset = at.offset; self.side = at.side; segment = at.segment
        offTrack = p.roadHalf < offset
        return railed
    }
}
