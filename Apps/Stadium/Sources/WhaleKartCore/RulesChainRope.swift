import StadiumCore

public struct RulesChainRope: CanRope {
    public var pos: [Vec3]
    public var air: [Int]
    public var airvel: [Vec3]
    public var taut: [Bool]
    public var held: Int = -1

    public init(parameters p: KartParameters, car: Car) {
        let n = p.canCount
        pos = initialCans(parameters: p, car: car)
        air = Array(repeating: 0, count: n)
        airvel = Array(repeating: .zero, count: n)
        taut = Array(repeating: false, count: n)
    }

    public mutating func step(parameters p: KartParameters, car: Car, input: RopeInput) -> RopeReport {
        let n = p.canCount, per = p.cans
        var events: [WorldEvent] = []
        let hitches = (0..<p.hitches.count).map { car.hitch(p, string: $0) }
        held = input.held >= 0 && input.held < n ? input.held : -1
        if held >= 0 {
            let i = held
            let at = reach(p, string: i / per, place: i % per, dx: input.dx, dz: input.dz)
            pos[i] = car.localToWorld(p, dx: at.dx, dz: at.dz)
            air[i] = 0
            if input.toss {
                air[i] = p.airborneTicks
                airvel[i] = car.localVelocityToWorld(vx: input.tvx, vz: input.tvz)
                held = -1
            }
        }
        // Use a triangular height arc to match the rules model, rather than ballistic gravity.
        for i in 0..<n where air[i] != 0 {
            let v = airvel[i]
            let half = p.airborneTicks >> 1
            let steps = air[i] <= half ? air[i] : p.airborneTicks - air[i]
            let arc = (p.tossUp * p.dt) * steps
            pos[i] = Vec3(pos[i].x + v.x * p.dt, p.canRadius + arc, pos[i].z + v.z * p.dt)
            air[i] -= 1
            if air[i] == 0 {
                pos[i] = Vec3(pos[i].x, p.canRadius, pos[i].z)
                events.append(.clink(can: i))
            }
        }
        // Propagate the held constraint backward, then forward, so a taut string stays straight.
        for s in 0..<p.hitches.count {
            let hitch = hitches[s]
            forwardPass(p, string: s, hitch: hitch)
            if held >= 0 && held / per == s {
                let top = held % per
                if top > 0 {
                    backwardPass(p, string: s, top: top)
                    forwardPass(p, string: s, hitch: hitch)
                }
                let d = pos[held] - hitch
                let dist = d.length
                let total = p.segment * (top + 1)
                if total < dist {
                    for k in 0..<top {
                        pos[s * per + k] = hitch + d.scaledTo(length: Fixed.one * (top + 1), target: Fixed.one * (k + 1))
                    }
                }
            }
        }
        var strain = Array(repeating: Fixed.zero, count: n)
        for i in 0..<n {
            if air[i] == 0 { pos[i] = Vec3(pos[i].x, p.canRadius, pos[i].z) }
            let anchor = i % per == 0 ? hitches[i / per] : pos[i - 1]
            let length = (pos[i] - anchor).length
            strain[i] = p.segment < length ? (length - p.segment) / p.segment : .zero
        }
        let cans = (0..<n).map { i in CanState(position: pos[i], grounded: air[i] == 0, held: i == held, taut: taut[i]) }
        return RopeReport(cans: cans, strain: strain, events: events)
    }

    private mutating func forwardPass(_ p: KartParameters, string s: Int, hitch: Vec3) {
        let per = p.cans
        for k in 0..<per {
            let i = s * per + k
            let anchor = k == 0 ? hitch : pos[i - 1]
            let d = pos[i] - anchor
            let length = d.length
            taut[i] = p.segment - p.tautEps <= length
            if p.segment < length && i != held {
                pos[i] = anchor + d.scaledTo(length: length, target: p.segment)
            }
        }
    }

    private mutating func backwardPass(_ p: KartParameters, string s: Int, top: Int) {
        let per = p.cans
        var k = top - 1
        while k >= 0 {
            let i = s * per + k
            let next = pos[i + 1]
            let d = pos[i] - next
            let length = d.length
            if p.segment < length {
                pos[i] = next + d.scaledTo(length: length, target: p.segment)
            }
            k -= 1
        }
    }
}
