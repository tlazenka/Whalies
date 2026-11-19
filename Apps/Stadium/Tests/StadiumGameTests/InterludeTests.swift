import Foundation
import Testing
import StadiumCore
import WhaleKartCore
import CrowdCore
@testable import StadiumGame

private func replay(_ p: StadiumParameters, _ inputs: [StadiumInput]) -> [(snapshot: StadiumSnapshot, camera: TurretCamera)] {
    var game = StadiumGame(parameters: p)
    var out: [(StadiumSnapshot, TurretCamera)] = []
    out.reserveCapacity(inputs.count)
    for input in inputs {
        let s = game.step(input)
        out.append((s, game.camera))
    }
    return out
}

private func interludeEvents(_ s: StadiumSnapshot) -> [(begun: Bool, fan: Int, number: Int)] {
    var out: [(begun: Bool, fan: Int, number: Int)] = []
    for e in s.ride.events {
        if case .interlude(let begun, let fan, let number) = e { out.append((begun: begun, fan: fan, number: number)) }
    }
    return out
}

@Test
func theInterludeComesAfterARound() throws {
    let p = StadiumParameters.stadium
    let replayed = replay(p, StadiumScript.repeatInputs(toggles: [:], dones: [4415], ticks: 4700))
    let snapshots = replayed.map(\.snapshot)
    let rows = snapshots.flatMap { s in interludeEvents(s).map { [s.tick, $0.begun ? 1 : 0, $0.fan, $0.number] } }
    #expect(rows == [[3906, 1, 153, 1], [4565, 0, 153, 1]])
    #expect(snapshots[3906].ride.repeat.unwrapped >= p.ride.interlude.at && snapshots[3905].ride.interlude.on == nil)
    #expect(snapshots[3467].ride.events.contains(.lap(1)), "after a round")
    func phase(_ t: Int) -> [Int]? { snapshots[t].ride.interlude.on.map { [$0.phase.rawValue, $0.k, $0.left, $0.shot] } }
    #expect(phase(3906) == [1, 1, 0, -1] && phase(3994) == [1, 89, 0, -1])
    #expect(phase(3995) == [2, 90, 0, -1] && phase(4414) == [2, 90, 0, -1])
    #expect(phase(4415) == [3, 90, 60, 4415] && phase(4475) == [4, 90, 0, 4415] && phase(4564) == [4, 1, 0, 4415])
    #expect(phase(4565) == nil)
    let browsing = (3995..<4415).compactMap { snapshots[$0].ride.interlude.on }
    #expect(browsing.count == 420 && browsing.allSatisfy(\.isBrowsing))
    #expect(browsing.allSatisfy { $0.left == 0 && $0.shot == -1 }, "the phone waits for the recorded Done input")
    let sprays = snapshots.filter { $0.ride.waterSpray?.startTick == $0.tick }
    let nextRound = try #require(snapshots.first { $0.ride.interlude.round == 2 })
    let firstSprayTick = nextRound.tick + WaterSpray.leadTicks
    #expect(nextRound.ride.events.contains(.interlude(begun: false, fan: 153, number: 1)),
            "the round changes when the phone visit fully ends, not when it begins")
    #expect(snapshots.prefix(firstSprayTick).allSatisfy { $0.ride.waterSpray == nil },
            "the opening lap, phone visit and following lead-in all stay dry")
    #expect(sprays.map { [$0.tick, $0.ride.waterSpray!.round] } == [[firstSprayTick, 2]],
            "the first spray follows completion of round one by the normal lead-in")
    #expect(snapshots[4415].ride.events.contains(.fired(item: .hotDog, figure: 153, part: 0, distance: Fixed(raw: 7_030_683))))
    #expect((3906...4565).allSatisfy { snapshots[$0].car == snapshots[3906].car } && snapshots[4699].car != snapshots[4565].car)
    #expect((3907...4565).allSatisfy { snapshots[$0].ride.bullpenCart == .none } && snapshots[3906].ride.bullpenCart != .none && snapshots[4566].ride.bullpenCart != .none)
    #expect((3906..<4565).allSatisfy { snapshots[$0].ride.pitcher.crew == .fan } && snapshots[4565].ride.pitcher.crew == .free)
    #expect(!(3906...4565).contains { t in snapshots[t].ride.events.contains { if case .beep = $0 { true } else { false } } })
    #expect(snapshots[4565].ride.nextAlarm == 4925)
    let cam = replayed[4000].camera
    let head = p.stands.figures()[153].head
    let q = try #require(cam.project(head))
    #expect(abs(q.x.double - 195.07) < 0.1 && abs(q.y.double - 251.58) < 0.1, "the head at (\(q.x.double), \(q.y.double))")
    let radius = try #require(cam.rect(centre: head, radius: p.stands.figures()[153].headR)).w.double / 2
    #expect(abs(radius - 40.0) < 0.1, "the head's radius \(radius)")
    #expect(snapshots[4565].ride.interlude.next == p.ride.interlude.at + StadiumGame(parameters: p).track.total)
}

@Test
func theInterludesLevelRepeatsIt() throws {
    let p = StadiumParameters.stadium
    #expect(RepeatState.interlude.rawValue == 4 && p.ride.repeat.stretch(.interlude) == nil && p.ride.repeat.spot(.interlude) == Fixed(40.0))
    #expect(CrewSubject.fan.rawValue == 3 && StadiumDigest.code(.interlude(begun: true, fan: 153, number: 2)) == [24, 1, 153, 2])
    let snapshots = replay(p, StadiumScript.repeatInputs(toggles: [0: .interlude], parks: [0: true], dones: [509, 1288], ticks: 1700)).map(\.snapshot)
    let rows = snapshots.flatMap { s in interludeEvents(s).map { [s.tick, $0.begun ? 1 : 0, $0.number] } }
    #expect(rows == [[0, 1, 1], [659, 0, 1], [779, 1, 2], [1438, 0, 2], [1558, 1, 3]])
    #expect(snapshots.allSatisfy { $0.ride.repeat.isHeld && $0.ride.repeat.parkedAt == Fixed(40.0) })
    #expect(!snapshots.contains { s in s.ride.events.contains { if case .beep = $0 { true } else { false } } })
}

@Test
func thePhoneWaitsForDoneAndIgnoresDoneOutsideBrowsing() throws {
    let p = StadiumParameters.stadium
    let snapshots = replay(p, StadiumScript.repeatInputs(toggles: [0: .interlude], parks: [0: true], dones: [400, 450, 675], ticks: 1600)).map(\.snapshot)
    func phase(_ t: Int) -> [Int]? { snapshots[t].ride.interlude.on.map { [$0.phase.rawValue, $0.k, $0.left, $0.shot] } }
    #expect(phase(399) == [2, 90, 0, -1] && phase(400) == [3, 90, 60, 400] && phase(450) == [3, 90, 10, 400])
    #expect(snapshots[400].ride.events.contains(.fired(item: .hotDog, figure: 153, part: 0, distance: Fixed(raw: 6_865_510))))
    let rows = snapshots.flatMap { s in interludeEvents(s).map { [s.tick, $0.begun ? 1 : 0, $0.number] } }
    #expect(rows == [[0, 1, 1], [550, 0, 1], [670, 1, 2]])
    #expect(phase(675) == [1, 6, 0, -1] && phase(759) == [2, 90, 0, -1] && phase(1599) == [2, 90, 0, -1],
            "Done during the entrance is ignored, and the next visit stays open beyond the former time limit")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(String(decoding: try encoder.encode(StadiumInput(done: true)), as: UTF8.self) == #"{"done":true}"#)
    #expect(String(decoding: try encoder.encode(StadiumInput.none), as: UTF8.self) == "{}")
    #expect(try JSONDecoder().decode(StadiumInput.self, from: Data(#"{"done":true}"#.utf8)) == StadiumInput(done: true))
}
