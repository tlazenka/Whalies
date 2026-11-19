import StadiumCore

public enum BodyPart: Int, Sendable, Codable {
    case head = 0
    case torso = 1
}

/// Requires a unit direction. Measure the miss vector directly: subtracting
/// large squared distances loses precision in 16.16 arithmetic.
public func raySphere(origin: Vec3, direction d: Vec3, centre: Vec3, radius: Fixed) -> Fixed? {
    let v = centre - origin
    let tca = v.dot(d)
    if tca <= .zero { return nil }
    let m = v - d.scaled(by: tca)
    let d2 = m.dot(m)
    let r2 = radius * radius
    if r2 < d2 { return nil }
    return tca - Fixed.sqrt(r2 - d2)
}

public struct Hit: Hashable, Sendable, Codable {
    public var figure: Int
    public var part: BodyPart
    public var distance: Fixed
    public init(figure: Int, part: BodyPart, distance: Fixed) { self.figure = figure; self.part = part; self.distance = distance }
}

/// Ties favor the lower figure index, then the head.
public func firstHit(origin: Vec3, direction d: Vec3, figures: [Figure], skip: Set<Int> = []) -> Hit? {
    var best: Hit? = nil
    for (i, f) in figures.enumerated() where !skip.contains(i) {
        for (part, centre, radius) in [(BodyPart.head, f.head, f.headR), (.torso, f.torso, f.torsoR)] {
            if let dist = raySphere(origin: origin, direction: d, centre: centre, radius: radius), best == nil || dist < best!.distance {
                best = Hit(figure: i, part: part, distance: dist)
            }
        }
    }
    return best
}
