import StadiumCore

public enum DemoScript {
    public static let ticks = 3600

    public static func input(at t: Int) -> RopeInput {
        func ramp(_ a: Fixed, _ b: Fixed, _ t0: Int, _ t1: Int) -> Fixed {
            Fixed(raw: a.raw + floorDiv((b.raw - a.raw) * Int64(t - t0), Int64(t1 - t0)))
        }
        if 300 <= t && t < 330 { return RopeInput(held: 4, dx: ramp(Fixed(0.5), Fixed(2.5), 300, 330), dz: Fixed(-2.0)) }
        if 330 <= t && t < 600 { return RopeInput(held: 4, dx: Fixed(2.5), dz: Fixed(-2.0)) }
        if 600 <= t && t < 630 { return RopeInput(held: 4, dx: ramp(Fixed(2.5), Fixed(0.5), 600, 630), dz: Fixed(-2.0)) }
        if 900 <= t && t < 1080 { return RopeInput(held: 2, dx: Fixed(-6.0), dz: Fixed(-4.0)) }
        if 1300 <= t && t < 1330 { return RopeInput(held: 1, dx: Fixed(-1.5), dz: Fixed(-1.5)) }
        if t == 1330 { return RopeInput(held: 1, dx: Fixed(-1.5), dz: Fixed(-1.5), toss: true, tvx: Fixed(-2.0), tvz: Fixed(1.0)) }
        if 2000 <= t && t < 2020 { return RopeInput(held: 3, dx: Fixed(1.0), dz: Fixed(-1.0)) }
        if t == 2020 { return RopeInput(held: 3, dx: Fixed(1.0), dz: Fixed(-1.0), toss: true, tvx: Fixed(1.5), tvz: Fixed(-2.0)) }
        return .none
    }

    public static func recording(model: RopeModel, parameters: KartParameters = .stadium) -> Recording {
        Recording(parameters: parameters, model: model, inputs: (0..<ticks).map { input(at: $0) })
    }
}
