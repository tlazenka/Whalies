// Store inputs so the same run can be replayed through either rope model.

import StadiumCore

public struct Recording: Hashable, Sendable, Codable {
    public var parameters: KartParameters
    public var model: RopeModel
    public var inputs: [RopeInput]

    public init(parameters: KartParameters = .stadium, model: RopeModel, inputs: [RopeInput]) {
        self.parameters = parameters; self.model = model; self.inputs = inputs
    }

    public func replay(model override: RopeModel? = nil) -> [WorldSnapshot] {
        var world = WhaleKartWorld(parameters: parameters, model: override ?? model)
        return inputs.map { world.step($0) }
    }
}

public enum WhaleKartDigest {
    /// Keep field order aligned with mix in python/whaley_tools/stadium/kart.py.
    public static func digest(_ snapshots: [WorldSnapshot]) -> ReplayDigest {
        var d = ReplayDigest()
        for s in snapshots { mix(&d, s) }
        return d
    }

    public static func mix(_ d: inout ReplayDigest, _ s: WorldSnapshot) {
        let c = s.car
        d.mix(s.tick); d.mix(c.x); d.mix(c.z); d.mix(c.heading); d.mix(c.yawRate); d.mix(c.speed)
        d.mix(c.progress); d.mix(c.offset); d.mix(c.side); d.mix(c.offTrack)
        for can in s.cans {
            d.mix(can.position)
            d.mix((can.grounded ? 1 : 0) | (can.held ? 2 : 0) | (can.taut ? 4 : 0))
        }
        for e in s.events {
            switch e {
            case .clink(let can): d.mix(1); d.mix(can)
            }
        }
    }
}
