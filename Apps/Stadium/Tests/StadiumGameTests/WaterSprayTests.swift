import Foundation
import Testing
@testable import StadiumGame

@Test
func waterJetAndWetLensHaveOneSharedTickTimeline() {
    let water = WaterSpray(round: 2, startTick: 100)
    #expect(water.sprayProgress(at: 99) == nil)
    #expect(water.sprayProgress(at: 100) == 0)
    #expect(water.sprayProgress(at: 144) == 44.0 / 45.0)
    #expect(water.sprayProgress(at: 145) == nil)
    #expect(water.impactTick == 118 && water.endTick == 298)
    #expect(water.lensStrength(at: 117) == 0)
    #expect(water.lensStrength(at: 118) == 1)
    #expect(water.lensStrength(at: 208) == 0.25)
    #expect(water.lensStrength(at: 297) > 0 && water.lensStrength(at: 298) == 0)
    #expect(!water.isActive(at: 99) && water.isActive(at: 100))
    #expect(water.isActive(at: 297) && !water.isActive(at: 298))
}

@Test
func aBlockedSprayWaitsAndOnlyStartsOncePerRound() throws {
    var schedule = WaterSpraySchedule()
    for tick in [0, 89, 90, 400, 10_000] {
        schedule.advance(at: tick, round: 1, canBegin: true)
        #expect(schedule.latest == nil, "elapsed time never makes the opening round eligible")
    }

    schedule.advance(at: 10_001, round: 2, canBegin: true)
    schedule.advance(at: 10_090, round: 2, canBegin: true)
    #expect(schedule.latest == nil, "the lead-in starts when the first round ends")
    schedule.advance(at: 10_091, round: 2, canBegin: false)
    schedule.advance(at: 10_169, round: 2, canBegin: false)
    #expect(schedule.latest == nil, "phone, Whaley and fan presentations defer the spray")
    schedule.advance(at: 10_170, round: 2, canBegin: true)
    let first = try #require(schedule.latest)
    #expect(first == WaterSpray(round: 2, startTick: 10_170))

    // Re-rendering a paused tick must not restart the spray.
    for _ in 0..<10 { schedule.advance(at: 10_170, round: 2, canBegin: true) }
    schedule.advance(at: 10_500, round: 2, canBegin: true)
    #expect(schedule.latest == first && first.lensStrength(at: 10_500) == 0)

    schedule.advance(at: 10_501, round: 3, canBegin: true)
    schedule.advance(at: 10_590, round: 3, canBegin: true)
    #expect(schedule.latest == first, "each new round receives its own lead-in")
    schedule.advance(at: 10_591, round: 3, canBegin: true)
    #expect(schedule.latest == WaterSpray(round: 3, startTick: 10_591))
}

@Test
func aParkedOpeningRoundDoesNotBecomeEligibleWithTime() {
    var game = StadiumGame(parameters: .stadium)
    let inputs = StadiumScript.repeatInputs(toggles: [0: .cannon], parks: [0: true], ticks: 1000)
    let snapshots = inputs.map { game.step($0) }
    #expect(snapshots.allSatisfy { $0.ride.repeat.isHeld && $0.ride.interlude.round == 1 })
    #expect(snapshots.allSatisfy { $0.ride.waterSpray == nil },
            "parking cannot manufacture completion of the first round")
}

@Test
func aSprayReplaysResetsAndConsumesNoGameplayRandomness() throws {
    var game = StadiumGame(parameters: .stadium)
    let initialRandomState = game.rng.state
    let inputs = StadiumScript.repeatInputs(toggles: [:], dones: [4415], ticks: 5000)
    var snapshots: [StadiumSnapshot] = []
    for input in inputs {
        let randomBefore = game.rng.state, tallyBefore = game.tally
        let snapshot = game.step(input)
        snapshots.append(snapshot)
        if snapshot.tick == 399 {
            #expect(game.rng.state == initialRandomState && game.tally.points == 0)
            #expect(game.waterSpray == nil, "the former opening spray is absent")
        }
        if snapshot.ride.waterSpray?.startTick == snapshot.tick {
            #expect(game.rng.state == randomBefore && game.tally == tallyBefore)
            #expect(snapshot.ride.events.isEmpty, "the spray introduces no scoring or input event")
        }
    }
    let starts = snapshots.compactMap { snapshot -> WaterSpray? in
        guard let water = snapshot.ride.waterSpray, water.startTick == snapshot.tick else { return nil }
        return water
    }
    let firstCompletion = try #require(snapshots.first { $0.ride.interlude.round == 2 })
    #expect(starts == [WaterSpray(round: 2, startTick: firstCompletion.tick + WaterSpray.leadTicks)])
    #expect(game.waterSpray == starts.first && game.waterSpray?.isActive(at: 4999) == false)

    let recording = StadiumRecording(parameters: .stadium, inputs: inputs)
    let data = try JSONEncoder().encode(recording)
    let replay = try JSONDecoder().decode(StadiumRecording.self, from: data).replay()
    #expect(replay.last == snapshots.last)
    #expect(StadiumDigest.digest(replay).hex == game.digest.hex)

    var fresh = StadiumGame(parameters: .stadium)
    #expect(fresh.waterSpray == nil)
    let reset = (0...WaterSpray.leadTicks).map { _ in fresh.step(.none) }
    #expect(reset.allSatisfy { $0.ride.waterSpray == nil }, "a new run starts with a dry opening round")
}
