import StadiumCore

public protocol CanRope: Sendable {
    init(parameters: KartParameters, car: Car)
    mutating func step(parameters: KartParameters, car: Car, input: RopeInput) -> RopeReport
}

public enum RopeModel: String, CaseIterable, Sendable, Codable {
    case rules = "a"
    case pbd = "b"

    public func makeRope(parameters: KartParameters, car: Car) -> any CanRope {
        switch self {
        case .rules: return RulesChainRope(parameters: parameters, car: car)
        case .pbd: return PBDRope(parameters: parameters, car: car)
        }
    }
}

func initialCans(parameters p: KartParameters, car: Car) -> [Vec3] {
    let f = Trig.forward(car.heading)
    var out: [Vec3] = []
    for s in 0..<p.hitches.count {
        let h = car.hitch(p, string: s)
        for k in 0..<p.cans {
            out.append(Vec3(h.x - f.x * (p.segment * (k + 1)), p.canRadius, h.z - f.z * (p.segment * (k + 1))))
        }
    }
    return out
}

/// Clamp the held can to its string's reach from the hitch.
public func reach(_ p: KartParameters, string s: Int, place k: Int, dx: Fixed, dz: Fixed) -> (dx: Fixed, dz: Fixed) {
    let hx = p.hitches[s]
    var ex = dx - hx, ez = dz
    let length = Fixed.sqrt(ex * ex + ez * ez)
    let limit = p.segment * (k + 1)
    if limit < length {
        ex = (ex * limit) / length
        ez = (ez * limit) / length
    }
    return (hx + ex, ez)
}
