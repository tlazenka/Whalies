// Step the rope before the kart; rope forces never feed back into the kart.

import StadiumCore

public struct WorldSnapshot: Hashable, Sendable, Codable {
    public var tick: Int
    public var car: Car
    public var cans: [CanState]
    public var strain: [Fixed]
    public var events: [WorldEvent]

    public var heldIndex: Int { cans.firstIndex { $0.held } ?? -1 }
}

public struct WhaleKartWorld: Sendable {
    public let parameters: KartParameters
    public let model: RopeModel
    public let track: Track
    public private(set) var car: Car
    public private(set) var rope: any CanRope
    public private(set) var tick: Int = 0
    public private(set) var offTrackTicks: Int = 0

    public init(parameters: KartParameters = .stadium, model: RopeModel) {
        self.parameters = parameters
        self.model = model
        let t = Track(parameters: parameters)
        let c = Car(parameters: parameters, track: t)
        track = t
        car = c
        rope = model.makeRope(parameters: parameters, car: c)
    }

    @discardableResult
    public mutating func step(_ input: RopeInput) -> WorldSnapshot {
        let report = rope.step(parameters: parameters, car: car, input: input)
        car.step(parameters: parameters, track: track)
        if car.offTrack { offTrackTicks += 1 }
        let snapshot = WorldSnapshot(tick: tick, car: car, cans: report.cans, strain: report.strain, events: report.events)
        tick += 1
        return snapshot
    }
}
