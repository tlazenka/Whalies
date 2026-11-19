// Fixed-point Verlet integration with iterative distance constraints; matches python/whaley_tools/stadium/kart.py.

import StadiumCore

public struct PBDRope: CanRope {
    public var pos: [Vec3]
    public var prev: [Vec3]
    public var taut: [Bool]
    public var tension: [Fixed]
    public var grounded: [Bool]
    public var held: Int = -1

    public init(parameters p: KartParameters, car: Car) {
        let n = p.canCount
        pos = initialCans(parameters: p, car: car)
        prev = pos
        taut = Array(repeating: false, count: n)
        tension = Array(repeating: .zero, count: n)
        grounded = Array(repeating: true, count: n)
    }

    public mutating func step(parameters p: KartParameters, car: Car, input: RopeInput) -> RopeReport {
        let n = p.canCount, per = p.cans
        var events: [WorldEvent] = []
        let hitches = (0..<p.hitches.count).map { car.hitch(p, string: $0) }
        let dt = p.dt
        let dt2 = dt * dt
        held = input.held >= 0 && input.held < n ? input.held : -1
        if held >= 0 {
            let i = held
            let at = reach(p, string: i / per, place: i % per, dx: input.dx, dz: input.dz)
            pos[i] = car.localToWorld(p, dx: at.dx, dz: at.dz)
            if input.toss {
                let tv = car.localVelocityToWorld(vx: input.tvx, vz: input.tvz)
                prev[i] = pos[i] - Vec3(tv.x * dt, p.tossUp * dt, tv.z * dt)
                held = -1
            } else {
                prev[i] = pos[i]
            }
        }
        let gdt2 = p.gravity * dt2
        for i in 0..<n where i != held {
            var vel = pos[i] - prev[i]
            if grounded[i] {
                vel = Vec3(vel.x * p.groundFriction, vel.y, vel.z * p.groundFriction)
            }
            vel = vel.scaled(by: p.damping)
            prev[i] = pos[i]
            pos[i] = Vec3(pos[i].x + vel.x, pos[i].y + vel.y - gdt2, pos[i].z + vel.z)
        }
        for it in 0..<p.iterations {
            let last = it == p.iterations - 1
            for i in 0..<n {
                let k = i % per
                let anchor = k == 0 ? hitches[i / per] : pos[i - 1]
                let d = pos[i] - anchor
                let length = d.length
                if last {
                    taut[i] = p.segment - p.tautEps <= length
                    tension[i] = p.segment < length ? length - p.segment : .zero
                }
                if length <= p.segment { continue }
                let corr = d.scaledTo(length: length, target: length - p.segment)
                if k == 0 {
                    if held != i { pos[i] = pos[i] - corr }
                } else if held == i {
                    pos[i - 1] = pos[i - 1] + corr
                } else if held == i - 1 {
                    pos[i] = pos[i] - corr
                } else {
                    let h = corr.half
                    pos[i - 1] = pos[i - 1] + h
                    pos[i] = pos[i] - h
                }
            }
            for i in 0..<n where pos[i].y < p.canRadius {
                pos[i] = Vec3(pos[i].x, p.canRadius, pos[i].z)
            }
        }
        for i in 0..<n {
            let was = grounded[i]
            grounded[i] = pos[i].y <= p.canRadius + p.tautEps
            if grounded[i] && !was { events.append(.clink(can: i)) }
        }
        let strain = (0..<n).map { i in Fixed.zero < tension[i] ? tension[i] / p.segment : Fixed.zero }
        let cans = (0..<n).map { i in CanState(position: pos[i], grounded: grounded[i], held: i == held, taut: taut[i]) }
        return RopeReport(cans: cans, strain: strain, events: events)
    }
}
