// Expected arithmetic values come from python/whaley_tools/stadium/math.py.

import Testing
@testable import StadiumCore

@Test
func fixedPointMatchesThePython() {
    #expect(Fixed(1.0).raw == 65536)
    #expect((Fixed(1) / Fixed(3)).raw == 21845)
    #expect((Fixed(-1) / Fixed(3)).raw == -21845)
    #expect((Fixed(-1.5) * Fixed(0.1)).raw == -9831)
    #expect(Fixed.sqrt(Fixed(2.0)).raw == 92681)
    let squares: [Int64] = [0, 1, 2, 15, 16, 17, 1_000_000_000_000, 1 << 62]
    #expect(squares.map { Fixed.isqrt($0) } == [0, 1, 1, 3, 4, 4, 1_000_000, 2_147_483_648])
    let divisions: [(Int64, Int64)] = [(7, 2), (-7, 2), (7, -2), (-7, -2)]
    #expect(divisions.map { floorDiv($0.0, $0.1) } == [3, -4, -4, 3])
    let modulos: [(Int64, Int64)] = [(7, 5), (-7, 5), (-65536, 65536), (-1, 65536)]
    #expect(modulos.map { floorMod($0.0, $0.1) } == [2, 3, 0, 65535])
}

@Test
func theSineTableInterpolatesLikeThePython() {
    let raws: [Int64] = [0, 1, 63, 64, 65, Trig.turn / 8, Trig.quarter, Trig.turn / 2, 3 * Trig.quarter, -Trig.turn / 8, Trig.turn + 5, 12345, -12345]
    #expect(raws.map { Trig.sin(Fixed(raw: $0)).raw } == [0, 6, 395, 402, 408, 46341, 65536, 0, -65536, -46341, 31, 60683, -60684])
    #expect([0, Trig.quarter, Trig.turn / 2, 12345].map { Trig.cos(Fixed(raw: $0)).raw } == [65536, 0, -65536, 24748])
}

@Test
func directionsMatchThePython() {
    let h = Fixed(raw: 12345)
    #expect(Trig.forward(h) == Vec3(Fixed(raw: 60683), .zero, Fixed(raw: 24748)))
    #expect(Trig.right(h) == Vec3(Fixed(raw: 24748), .zero, Fixed(raw: -60683)))
    #expect(Trig.forward(.zero) == Vec3(.zero, .zero, .one))
    #expect(Trig.right(.zero) == Vec3(.one, .zero, .zero))
    let p = Fixed(raw: -2345)
    #expect(Trig.direction(yaw: h, pitch: p) == Vec3(Fixed(raw: 59155), Fixed(raw: -14611), Fixed(raw: 24124)))
    #expect(Trig.up(yaw: h, pitch: p) == Vec3(Fixed(raw: 13530), Fixed(raw: 63886), Fixed(raw: 5518)))
}

@Test
func theDigestMatchesThePython() {
    var d = ReplayDigest()
    for v in [1, -2, 3, Int64(1) << 62, -(Int64(1) << 62)] { d.mix(v) }
    #expect(d.hex == "dc0b47a8afed18fe")
}

@Test
func theClockReadsLikeWhaleys() {
    #expect(TextFormat.clock(0) == "00:00.00")
    #expect(TextFormat.clock(60) == "00:01.00")
    #expect(TextFormat.clock(90) == "00:01.50")
    #expect(TextFormat.clock(3000) == "00:50.00")
    #expect(TextFormat.clock(60 * 61) == "01:01.00")
}

@Test
func theBearingMatchesThePython() {
    let cases: [(Double, Double)] = [(0, 1), (1, 0), (0, -1), (-1, 0), (1, 1), (3, -4), (-20, 50), (-0.5, -0.25), (12.25, 0.001)]
    #expect(cases.map { Trig.bearing(dx: Fixed($0.0), dz: Fixed($0.1)).raw } == [0, 16384, 32768, 49152, 8192, 26056, 61567, 44316, 16384])
    let pitches: [(Double, Double)] = [(2.2, 50), (-1, 10), (0, 5), (3, 0)]
    #expect(pitches.map { Trig.elevation(dy: Fixed($0.0), horizontal: Fixed($0.1)).raw } == [459, -1040, 0, 16384])
    #expect(Trig.bearing(dx: .zero, dz: .zero) == .zero)
    var worst: Int64 = 0
    for k in stride(from: Int64(0), to: Trig.turn, by: 97) {
        let f = Trig.forward(Fixed(raw: k))
        let b = Trig.bearing(dx: f.x * Fixed(40.0), dz: f.z * Fixed(40.0)).raw
        worst = max(worst, min(abs(b - k), Trig.turn - abs(b - k)))
    }
    #expect(worst <= 2)
}
