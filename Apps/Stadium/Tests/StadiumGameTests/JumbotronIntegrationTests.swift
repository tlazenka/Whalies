import Foundation
import Testing
import StadiumCore
@testable import StadiumGame

private func observedFrame(_ sequence: Int, events: [WhaleyEvent] = []) -> JumbotronFrame {
    JumbotronFrame(sessionID: "native-game", sequence: sequence,
                   observation: WhaleyObservation(ready: true, number: 1, gameTime: Double(sequence) / 60,
                                                 x: Fixed(100), y: Fixed(200), width: Fixed(32), height: Fixed(32),
                                                 layer: LevelSpot(Fixed(-30), Fixed(-120))),
                   events: events)
}

@Test
func fanPriorityRetainsExplicitWhaleyAndPhoneActivities() {
    let cases: [(crew: CrewSubject, fan: Bool, zoomed: Bool, showsFan: Bool, showsGame: Bool)] = [
        (.free, false, false, false, true),
        (.free, true, false, true, false),
        (.ball, true, false, true, false),
        (.pitcher, true, false, true, false),
        (.fan, true, false, false, false),
        (.free, true, true, false, true),
        (.ball, true, true, false, false),
        (.fan, true, true, false, false),
    ]
    for c in cases {
        #expect(StadiumGame.showsFan(crew: c.crew, dollOnJumbotron: c.fan, zoomed: c.zoomed) == c.showsFan)
        #expect(StadiumGame.showsGame(inQuadrant: true, crew: c.crew, dollOnJumbotron: c.fan, zoomed: c.zoomed) == c.showsGame)
    }
}

@Test
func stadiumConsumesNativeOutcomesOnceAndRecordsTheirOrder() throws {
    var game = StadiumGame(parameters: .stadium)
    var inputs = [StadiumInput.began(Fixed(100), Fixed(300)), .ended(Fixed(100), Fixed(300))]
    for input in inputs { game.step(input) }
    let bubble = try #require(game.bubbles.first)
    let contact = observedFrame(1, events: [.bubbleContact(id: bubble.id, remainingUses: 1, popped: false, bounced: true), .coin])
    let goal = observedFrame(2, events: [.goal])
    let nativeInput = StadiumInput(whaleyFrames: [contact, contact, goal])
    inputs.append(nativeInput)
    let accepted = game.step(nativeInput)
    #expect(accepted.ride.whaley.events == [contact.events[0], .coin, .goal])
    #expect(accepted.ride.whaley.engaged)
    #expect(accepted.ride.tally.coins == 1 && accepted.ride.tally.goals == 1)
    #expect(accepted.ride.tally.points == 275)
    #expect(game.bubbles.first?.usesLeft == 1)

    let repeated = StadiumInput(whaleyFrames: [goal])
    inputs.append(repeated)
    let afterDuplicate = game.step(repeated)
    #expect(afterDuplicate.ride.whaley.events.isEmpty)
    #expect(afterDuplicate.ride.tally.points == 275)

    let recording = StadiumRecording(parameters: .stadium, inputs: inputs)
    let data = try JSONEncoder().encode(recording)
    let decoded = try JSONDecoder().decode(StadiumRecording.self, from: data)
    let replay = decoded.replay()
    #expect(replay.last == afterDuplicate)
    #expect(replay[2].ride.whaley.events == accepted.ride.whaley.events)
}

@Test
func nativeBubbleRemovalCannotResurrectOrAwardAStaleContact() throws {
    var game = StadiumGame(parameters: .stadium)
    game.step(.began(Fixed(100), Fixed(300)))
    game.step(.ended(Fixed(100), Fixed(300)))
    let id = try #require(game.bubbles.first?.id)
    let popped = observedFrame(1, events: [.bubbleContact(id: id, remainingUses: 0, popped: true, bounced: true)])
    let result = game.step(StadiumInput(whaleyFrames: [popped]))
    #expect(game.bubbles.allSatisfy { $0.id != id })
    #expect(result.ride.events.filter { $0 == .popped(id: id) }.count == 1)
    #expect(result.ride.whaley.events == popped.events)
    let stale = observedFrame(2, events: [.bubbleContact(id: id, remainingUses: 2, popped: true, bounced: true)])
    let next = game.step(StadiumInput(whaleyFrames: [stale]))
    #expect(game.bubbles.allSatisfy { $0.id != id })
    #expect(!next.ride.events.contains(.popped(id: id)))
    #expect(next.ride.whaley.events.isEmpty, "a removed bubble cannot trigger bounce audio or advance the assisted hand")
    #expect(next.ride.whaley.observation == stale.observation)

    // Mix a rejected contact with valid events to test partial acceptance.
    let mixed = observedFrame(3, events: [.coin, stale.events[0], .goal])
    let accepted = game.step(StadiumInput(whaleyFrames: [mixed]))
    #expect(accepted.ride.whaley.events == [.coin, .goal])
    #expect(accepted.ride.whaley.observation == mixed.observation)
    #expect(accepted.ride.tally.coins == 1 && accepted.ride.tally.goals == 1)
    #expect(accepted.ride.tally.points == 275)
}

@Test
func unengagedNativeGameDoesNotScoreAndForeignSessionsAreIgnored() {
    var game = StadiumGame(parameters: .stadium)
    game.step(StadiumInput(whaleyFrames: [observedFrame(1, events: [.coin, .goal])]))
    #expect(game.whaley.ready && !game.whaleyEngaged)
    #expect(game.whaley.number == 1)
    let foreign = JumbotronFrame(sessionID: "another-host", sequence: 100,
                                observation: WhaleyObservation(ready: true, number: 6), events: [.coin])
    let result = game.step(StadiumInput(whaleyFrames: [foreign]))
    #expect(game.whaley.number == 1 && result.ride.whaley.events.isEmpty)
    #expect(result.ride.tally.coins == 0 && result.ride.tally.goals == 0)
}

@Test
func screenConversionUsesTheObservedNativeCameraAndNoLevelTables() throws {
    var game = StadiumGame(parameters: .stadium)
    game.step(StadiumInput(whaleyFrames: [observedFrame(1)]))
    let world = game.screenWorld(x: Fixed(100), y: Fixed(200))
    let picture = try #require(game.camera.point(world))
    let cast = try #require(game.planeCast(camera: game.camera, x: picture.x, y: picture.y))
    let local = game.screenSpot(u: cast.u, v: cast.v)
    #expect(abs(local.x.double - 70) < 1)
    #expect(abs(local.y.double - 80) < 1)
}
