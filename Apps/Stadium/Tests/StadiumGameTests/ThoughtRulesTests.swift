import Foundation
import Testing
import StadiumCore
import CrowdCore
@testable import StadiumGame

// Reuse the existing snapshots; recording determinism is tested separately.
func expectThoughtDecisions(_ snapshots: [StadiumSnapshot]) {
    var results: [AlarmResult] = []
    for snapshot in snapshots where snapshot.ride.events.contains(where: isResult) {
        guard let result = snapshot.ride.lastResult, let incident = snapshot.ride.incident else {
            Issue.record("A decision must publish its incident and result")
            continue
        }
        results.append(result)
        #expect(result.endTick == snapshot.tick && incident.ended == snapshot.tick)
        #expect(result.symbol == incident.symbol && result.result == incident.result)
        switch result.result {
        case .served:
            #expect(result.symbol == .hotDog && result.item == .hotDog)
            #expect(result.shot >= incident.start && result.shot < incident.end)
        case .heldFire:
            #expect(!result.symbol.requiresHotDog && result.shot == -1 && snapshot.tick == incident.end)
        case .missedRequest:
            #expect(result.symbol.requiresHotDog && result.shot == -1 && snapshot.tick == incident.end)
        case .tooSoon:
            #expect(result.shot >= incident.beep && result.shot < incident.start && !result.result.success)
        case .unwanted:
            #expect(!result.symbol.requiresHotDog && !result.result.success)
        case .wrongItem:
            #expect(result.symbol.requiresHotDog && result.item != .hotDog && !result.result.success)
        case .wrongFan, .miss:
            #expect(!result.result.success)
        }
    }
    #expect(Set(results.map(\.beep)).count == results.count, "a request is decided only once")
    if let tally = snapshots.last?.ride.tally {
        #expect(tally.served == results.filter { $0.result == .served }.count)
        #expect(tally.tooSoon == results.filter { $0.result == .tooSoon }.count)
        #expect(tally.heldFire == results.filter { $0.result == .heldFire }.count)
        #expect(tally.wrong == results.filter { !$0.result.success }.count)
    }
}

@Test
func aRecordingRejectsRetiredOrUnknownRulesExplicitly() throws {
    let recording = StadiumRecording(parameters: .stadium, inputs: [.none])
    let data = try JSONEncoder().encode(recording)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in [nil, 1, 2, 3, 4, 5, StadiumRecording.currentVersion + 1] as [Int?] {
        if let version { object["version"] = version } else { object.removeValue(forKey: "version") }
        let changed = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try JSONDecoder().decode(StadiumRecording.self, from: changed)
            Issue.record("A recording with different rules must not silently replay")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("different gameplay rules"))
        }
    }
}

@Test(arguments: [0, 1, 20261101, -1] as [Int64])
func halfOfThoughtOutcomesRequestHotDogs(seed: Int64) {
    var rng = Rng(seed: seed)
    let count = 10_000
    var totals: [ThoughtSymbol: Int] = [:]
    for variation in 0..<count {
        let symbol = ThoughtSymbol.draw(using: &rng, variation: variation)
        totals[symbol, default: 0] += 1
    }
    // Allow sampling variation while rejecting a uniform four-symbol draw.
    #expect((4_700...5_300).contains(totals[.hotDog, default: 0]))
    for symbol in [ThoughtSymbol.baseball, .music, .star] {
        #expect((1_300...2_000).contains(totals[symbol, default: 0]))
    }
}

@Test
func weightedThoughtDrawPreservesTheRecordedOutcomeStream() {
    var rng = Rng(seed: 20261101)
    let symbols = (0..<12).map { ThoughtSymbol.draw(using: &rng, variation: $0) }
    #expect(symbols == [.baseball, .hotDog, .hotDog, .hotDog, .music, .hotDog,
                        .baseball, .music, .star, .hotDog, .music, .star])
    #expect(rng.state == 7_681_369_315_931_781_609)
}

@Test
func weightedReelShowsHotDogsInHalfItsSlotsAndLandsOnEveryPicture() throws {
    var hotDogPredecessors: Set<ThoughtSymbol> = []
    for figure in 0..<3 {
        for symbol in ThoughtSymbol.allCases {
            let thought = FanThought(figure: figure, start: 300, end: 390, spinTicks: 300, symbol: symbol)
            // Sample only the initial constant-speed slots.
            let slots = try stride(from: 3, through: 33, by: 6).map { tick in
                let frame = try #require(thought.frame(at: tick))
                #expect(frame.isSpinning && frame.progress == 0)
                return frame.symbol
            }
            #expect(slots.filter(\.requiresHotDog).count == 3)
            #expect(slots.filter { $0 == .baseball }.count == 1)
            #expect(slots.filter { $0 == .music }.count == 1)
            #expect(slots.filter { $0 == .star }.count == 1)

            let lastSlot = try #require(thought.frame(at: 276))
            let lastFrame = try #require(thought.frame(at: 299))
            let settled = try #require(thought.frame(at: 300))
            #expect(lastSlot.nextSymbol == symbol && lastSlot.progress == 0)
            #expect(lastFrame.symbol == lastSlot.symbol && lastFrame.nextSymbol == symbol)
            #expect(lastFrame.progress == 23.0 / 24.0)
            #expect(settled.symbol == symbol && settled.nextSymbol == symbol && !settled.isSpinning)
            if symbol == .hotDog { hotDogPredecessors.insert(lastSlot.symbol) }
        }
    }
    #expect(hotDogPredecessors == Set([.baseball, .music, .star]), "all three hot-dog stops land correctly")
}

@Test
func aThoughtKeepsItsPictureThroughTheCameraResultHold() throws {
    for symbol in ThoughtSymbol.allCases {
        let incident = Incident(beep: 100, figure: 7, garden: false, symbol: symbol, start: 400, end: 460)
        #expect(incident.thought(at: 99) == nil)
        #expect(incident.thought(at: 399)?.isSpinning == true)
        #expect(incident.thought(at: 400)?.symbol == symbol && incident.thought(at: 400)?.isSpinning == false)
        #expect(incident.crewEnd == 490)
        #expect(incident.thought(at: 489)?.symbol == symbol && incident.thought(at: 490) == nil)
    }
}
