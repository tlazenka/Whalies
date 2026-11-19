import StadiumCore

public struct CameraBasis: Hashable, Sendable, Codable {
    public var forward: Vec3
    public var right: Vec3
    public var up: Vec3
}

public struct Camera: Hashable, Sendable, Codable {
    public var eye: Vec3
    /// Tangents of the horizontal and vertical half-fields of view.
    public var tanHalfH: Fixed
    public var tanHalfV: Fixed
    public var range: Fixed

    public init(eye: Vec3, tanHalfH: Fixed, tanHalfV: Fixed, range: Fixed) {
        self.eye = eye; self.tanHalfH = tanHalfH; self.tanHalfV = tanHalfV; self.range = range
    }

    public func basis(lookingAt target: Vec3) -> CameraBasis {
        let d = target - eye
        let length = Fixed.sqrt(d.dot(d))
        let f = Vec3(d.x / length, d.y / length, d.z / length)
        let rl = Fixed.sqrt(f.z * f.z + f.x * f.x)
        let r = Vec3(f.z / rl, .zero, (-f.x) / rl)
        let u = Vec3(f.y * r.z - f.z * r.y, f.z * r.x - f.x * r.z, f.x * r.y - f.y * r.x)
        return CameraBasis(forward: f, right: r, up: u)
    }

    public func frames(_ point: Vec3, basis b: CameraBasis) -> Bool {
        let v = point - eye
        let fc = v.dot(b.forward)
        if fc <= .zero || range < fc { return false }
        return v.dot(b.right).magnitude <= fc * tanHalfH && v.dot(b.up).magnitude <= fc * tanHalfV
    }
}
