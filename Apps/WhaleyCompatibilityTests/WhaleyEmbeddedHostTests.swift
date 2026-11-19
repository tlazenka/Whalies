import Foundation
import SpriteKit
import UIKit
import XCTest
import WhaleyCore
@testable import WhaleyHost
import WhaleyObjectiveC
import WhaleySpriteKit

/// Exercises the existing Objective-C scene and gameLoop: implementation. No
/// translated collision rules or second test simulation is used here.
@MainActor
final class WhaleyEmbeddedHostTests: XCTestCase {
    private func makeHost() -> SKScene {
        WhaleyRuntimeBridgeLinkage.ensureLinked()
        WhaleyResources.configure()
        return WhaleyCreateSrcEmbeddedLevelScene(1, CGSize(width: 320, height: 180))
    }

    private func game(in node: SKNode) throws -> SKNode {
        let gameClass = try XCTUnwrap(NSClassFromString("Whaley"))
        func find(_ node: SKNode) -> SKNode? {
            if node.isKind(of: gameClass) { return node }
            return node.children.lazy.compactMap(find).first
        }
        return try XCTUnwrap(find(node))
    }

    private func step(_ game: SKNode) throws {
        let selector = NSSelectorFromString("gameLoop:")
        XCTAssertTrue(game.responds(to: selector))
        let implementation = try XCTUnwrap(game.method(for: selector))
        typealias GameLoop = @convention(c) (AnyObject, Selector, Double) -> Void
        unsafeBitCast(implementation, to: GameLoop.self)(game, selector, 1.0 / 60.0)
    }

    private func prepareContact(_ game: SKNode) throws -> SKNode {
        let player = try XCTUnwrap(game.value(forKey: "player") as? SKNode)
        // Keep the real gameplay but remove unrelated level obstacles from this
        // fixture. One manual tick can then establish the external bubble result.
        game.setValue(nil, forKey: "meta")
        game.setValue(NSMutableArray(), forKey: "hazards")
        game.setValue(NSMutableArray(), forKey: "collectibles")
        game.setValue(NSMutableArray(), forKey: "projectiles")
        game.setValue(false, forKey: "hasInfiniteBubbles")
        game.setValue(false, forKey: "isPaused")
        (game.value(forKey: "goal") as? SKNode)?.position = CGPoint(x: 10_000, y: 10_000)
        player.position = CGPoint(x: 300, y: 300)
        player.setValue(3, forKey: "airMode") // FALLING, from the shared Player.h.
        player.setValue(false, forKey: "isDead")
        player.setValue(false, forKey: "hasWon")
        player.setValue(false, forKey: "isMovingLaterally")
        player.setValue(1, forKey: "yAdd")
        player.setValue(1, forKey: "jumpDiff")
        return player
    }

    private func input(game: SKNode, id: String, fixed: Bool, uses: Int) -> [String: Any] {
        // World (316, 291) expressed on this host's current logical screen.
        ["id": id, "x": 316 + game.position.x, "y": 291 + game.position.y,
         "diameter": 20.0, "remainingUses": uses, "fixed": fixed, "held": false]
    }

    func testEmbeddedViewportDoesNotChangeStandaloneViewport() throws {
        let host = makeHost()
        XCTAssertEqual(host.size, CGSize(width: 320, height: 180))
        XCTAssertEqual(host.scaleMode, .aspectFit)
        let state = WhaleySrcHostState()
        XCTAssertEqual((state["level"] as? NSNumber)?.intValue, 1)
        XCTAssertGreaterThan((state["playerWidth"] as? NSNumber)?.doubleValue ?? 0, 0)
        WhaleySrcDisposeHost(host)
        XCTAssertTrue(WhaleySrcHostState().isEmpty)

        let standalone = WhaleyCreateSrcLevelOneScene()
        defer { WhaleySrcDisposeHost(standalone) }
        XCTAssertEqual(standalone.size, CGSize(width: 320, height: 568))
    }

    func testEmbeddedAudioConfigurationDefaultsAndRoundTrips() throws {
        let legacy = Data(#"{"sessionID":"legacy","level":1,"width":320,"height":180}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(WhaleyEmbeddedConfiguration.self, from: legacy).soundEffectsEnabled)
        XCTAssertTrue(WhaleyEmbeddedConfiguration(sessionID: "audible").soundEffectsEnabled)
        let silent = WhaleyEmbeddedConfiguration(sessionID: "stadium", soundEffectsEnabled: false)
        XCTAssertEqual(try JSONDecoder().decode(WhaleyEmbeddedConfiguration.self,
                                               from: JSONEncoder().encode(silent)), silent)
    }

    func testAudioOnlyConfigurationChangesPreserveTheGameAndFrameSequence() throws {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let view = SrcWhaleySKView(frame: frame)
        let window = UIWindow(frame: frame)
        // The test drives display callbacks synchronously and makes no relay
        // requests. A window supplies the host's normal visibility precondition.
        view.cliRelayHelloSent = true
        view.lastCLIRelayAttempt = .infinity
        view.startNativeSession(configuration: .init(sessionID: "audio-toggle", soundEffectsEnabled: false))
        window.addSubview(view)
        view.isPaused = true
        view.displayLink?.invalidate()
        view.displayLink = nil
        defer { view.stopNativeSession(); view.removeFromSuperview() }

        let host = try XCTUnwrap(view.scene)
        let game = try game(in: host)
        let sound = try XCTUnwrap(game.value(forKey: "bounceSound") as? NSObject)
        XCTAssertFalse(WhaleySrcHostSoundEffectsEnabled(host))
        var frames: [WhaleyEmbeddedFrame] = []
        view.onEmbeddedFrame = { frames.append($0) }
        view.updateSemanticClock()
        XCTAssertEqual(frames.map(\.sequence), [1])

        _ = try prepareContact(game)
        WhaleySrcSetExternalProjectiles([input(game: game, id: "audio-contact", fixed: false, uses: 1)])
        try step(game)
        let pendingState = WhaleySrcHostState() as NSDictionary
        // The real collision is pending when the containing app turns sound on.
        view.startNativeSession(configuration: .init(sessionID: "audio-toggle", soundEffectsEnabled: true))
        XCTAssertTrue(view.scene === host)
        XCTAssertTrue(try self.game(in: host) === game)
        XCTAssertTrue((game.value(forKey: "bounceSound") as? NSObject) === sound)
        XCTAssertEqual(WhaleySrcHostState() as NSDictionary, pendingState)
        XCTAssertTrue(WhaleySrcHostSoundEffectsEnabled(host))
        XCTAssertEqual(sound.value(forKey: "playbackEnabled") as? Bool, true,
                       "A source originally created muted becomes eligible in the same session")
        XCTAssertEqual(sound.value(forKey: "isPlaying") as? Bool, false,
                       "Enabling audio must not replay the collision that happened while muted")
        view.updateSemanticClock()
        XCTAssertEqual(frames.map(\.sequence), [1, 2])
        XCTAssertEqual(frames.last?.events, [.bubbleContact(id: "audio-contact", remainingUses: 0, popped: true, bounced: true)])

        sound.setValue(0, forKey: "gain")
        sound.perform(NSSelectorFromString("play"))
        view.startNativeSession(configuration: .init(sessionID: "audio-toggle", soundEffectsEnabled: false))
        XCTAssertTrue(view.scene === host)
        XCTAssertEqual(sound.value(forKey: "playbackEnabled") as? Bool, false)
        XCTAssertEqual(sound.value(forKey: "isPlaying") as? Bool, false)
        sound.perform(NSSelectorFromString("play"))
        XCTAssertEqual(sound.value(forKey: "isPlaying") as? Bool, false)
        view.updateSemanticClock()
        XCTAssertEqual(frames.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(frames.last?.events, [])
        XCTAssertTrue(frames.allSatisfy { $0.sessionID == "audio-toggle" })

        view.setHostActive(false)
        view.startNativeSession(configuration: .init(sessionID: "audio-toggle", soundEffectsEnabled: true))
        XCTAssertTrue(host.isPaused && view.isPaused,
                      "An audio preference cannot resume an inactive host")
        XCTAssertEqual(sound.value(forKey: "isPlaying") as? Bool, false)
    }

    func testMutedEmbeddedHostKeepsItsLiveAudioPolicyAcrossRetriesAndStopsAtTeardown() throws {
        let view = SrcWhaleySKView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        defer { view.stopNativeSession() }
        view.startNativeSession(configuration: .init(sessionID: "silent"))
        let host = try XCTUnwrap(view.scene)
        view.startNativeSession(configuration: .init(sessionID: "silent", soundEffectsEnabled: false))
        XCTAssertTrue(view.scene === host)
        XCTAssertFalse(WhaleySrcHostSoundEffectsEnabled(host))

        func assertSilentSounds(in game: SKNode) throws {
            for key in ["bgSound", "bounceSound", "flameSound", "jumpSound", "collectibleSound", "goalSound"] {
                let source = try XCTUnwrap(game.value(forKey: key) as? NSObject)
                source.perform(NSSelectorFromString("play"))
                XCTAssertEqual(source.value(forKey: "isPlaying") as? Bool, false, key)
            }
        }
        try assertSilentSounds(in: game(in: host))
        WhaleySrcReplayCurrentLevel()
        XCTAssertFalse(WhaleySrcHostSoundEffectsEnabled(host))
        try assertSilentSounds(in: game(in: host))
        WhaleySrcAdvanceAfterWin()
        XCTAssertFalse(WhaleySrcHostSoundEffectsEnabled(host))
        try assertSilentSounds(in: game(in: host))
        let advancedLevel = WhaleySrcCurrentLevelNumber()
        XCTAssertGreaterThan(advancedLevel, 1)
        view.startNativeSession(configuration: .init(sessionID: "silent"))
        XCTAssertTrue(view.scene === host)
        XCTAssertEqual(WhaleySrcCurrentLevelNumber(), advancedLevel,
                       "The original requested level is not reapplied when sound changes")
        XCTAssertTrue(WhaleySrcHostSoundEffectsEnabled(host))

        view.stopNativeSession()
        XCTAssertFalse(WhaleySrcHostSoundEffectsEnabled(host))
        let standalone = WhaleyCreateSrcLevelOneScene()
        defer { WhaleySrcDisposeHost(standalone) }
        XCTAssertTrue(WhaleySrcHostSoundEffectsEnabled(standalone))
    }

    func testReplacingAudioPolicyInvalidatesOldSoundsAndStaleHostsCannotMuteTheReplacement() throws {
        let outgoing = SrcWhaleySKView(frame: .zero)
        let incoming = SrcWhaleySKView(frame: .zero)
        defer { outgoing.stopNativeSession(); incoming.stopNativeSession() }
        outgoing.startNativeSession(configuration: .init(sessionID: "audible"))
        let oldHost = try XCTUnwrap(outgoing.scene)
        let oldSound = try XCTUnwrap(try game(in: oldHost).value(forKey: "bgSound") as? NSObject)
        XCTAssertTrue(WhaleySrcHostSoundEffectsEnabled(oldHost))
        oldSound.perform(NSSelectorFromString("play"))

        incoming.startNativeSession(configuration: .init(sessionID: "silent", soundEffectsEnabled: false))
        XCTAssertEqual(oldSound.value(forKey: "isPlaying") as? Bool, false)
        WhaleySrcSetHostSoundEffectsEnabled(oldHost, true)
        XCTAssertFalse(WhaleySrcHostSoundEffectsEnabled(try XCTUnwrap(incoming.scene)))
        // A retained outgoing source cannot become audible after the next session
        // restores the default policy. Only newly created sources belong to it.
        incoming.startNativeSession(configuration: .init(sessionID: "audible-again"))
        let replacement = try XCTUnwrap(incoming.scene)
        outgoing.stopNativeSession()
        WhaleySrcDisposeHost(oldHost)
        WhaleySrcSetHostSoundEffectsEnabled(oldHost, false)
        XCTAssertTrue(WhaleySrcHostSoundEffectsEnabled(replacement))
        oldSound.setValue(true, forKey: "playbackEnabled")
        XCTAssertEqual(oldSound.value(forKey: "playbackEnabled") as? Bool, false,
                       "Permanent teardown cannot be undone by a later audio preference")
        oldSound.perform(NSSelectorFromString("play"))
        XCTAssertEqual(oldSound.value(forKey: "isPlaying") as? Bool, false)
    }

    func testVisibilitySuspensionPreservesHUDPauseAndDisposalClearsOwnership() throws {
        let host = makeHost()
        let game = try game(in: host)
        game.setValue(true, forKey: "isPaused")
        WhaleySrcSetHostSuspended(host, true)
        XCTAssertTrue(host.isPaused)
        WhaleySrcSetHostSuspended(host, false)
        XCTAssertFalse(host.isPaused)
        XCTAssertEqual(game.value(forKey: "isPaused") as? Bool, true)

        WhaleySrcDisposeHost(host)
        XCTAssertTrue(host.children.isEmpty)
        XCTAssertTrue(WhaleySrcDrainGameEvents().isEmpty)
        let replacement = makeHost()
        defer { WhaleySrcDisposeHost(replacement) }
        WhaleySrcSetHostSuspended(host, true) // A stale owner cannot pause the replacement.
        WhaleySrcDisposeHost(host)
        XCTAssertFalse(replacement.isPaused)
        XCTAssertEqual(WhaleySrcCurrentLevelNumber(), 1)
    }

    func testNewEmbeddedSessionStartsFreshWithoutChangingDeathRetrySemantics() throws {
        let host = makeHost()
        let game = try game(in: host)
        let level = try XCTUnwrap(game.value(forKey: "level") as? NSObject)
        level.setValue(0, forKey: "checkpointIndex")
        level.setValue(NSMutableArray(array: [0]), forKey: "collectiblesCaptured")
        WhaleySrcReplayCurrentLevel()
        let retryLevel = try XCTUnwrap(try self.game(in: host).value(forKey: "level") as? NSObject)
        XCTAssertEqual(retryLevel.value(forKey: "checkpointIndex") as? Int, 0)
        WhaleySrcDisposeHost(host)

        let replacement = makeHost()
        defer { WhaleySrcDisposeHost(replacement) }
        let freshLevel = try XCTUnwrap(try self.game(in: replacement).value(forKey: "level") as? NSObject)
        XCTAssertEqual(freshLevel.value(forKey: "checkpointIndex") as? Int, -1)
        XCTAssertEqual(try XCTUnwrap(freshLevel.value(forKey: "collectiblesCaptured") as? NSArray).count, 0)
    }

    func testExternalBubbleBouncesInTheRealEngineAndCannotBeResurrectedByStaleInput() throws {
        let host = makeHost()
        defer { WhaleySrcDisposeHost(host) }
        let game = try game(in: host)
        let player = try prepareContact(game)
        let bubble = input(game: game, id: "stadium-17", fixed: false, uses: 1)
        WhaleySrcSetExternalProjectiles([bubble])
        let projectiles = try XCTUnwrap(game.value(forKey: "projectiles") as? NSMutableArray)
        XCTAssertEqual(projectiles.count, 1)
        XCTAssertTrue(try XCTUnwrap(projectiles.firstObject as? SKNode).isHidden)

        try step(game)
        XCTAssertEqual(player.value(forKey: "airMode") as? Int, 1) // JUMPING_UP.
        XCTAssertEqual(projectiles.count, 0)
        let events = WhaleySrcDrainGameEvents()
        let contact = try XCTUnwrap(events.first { ($0["externalID"] as? String) == "stadium-17" })
        XCTAssertEqual(contact["bounced"] as? Bool, true)
        XCTAssertEqual(contact["popped"] as? Bool, true)
        XCTAssertEqual(contact["remainingUses"] as? Int, 0)
        XCTAssertEqual(events.filter { ($0["externalID"] as? String) == "stadium-17" }.count, 1)
        XCTAssertTrue(WhaleySrcDrainGameEvents().isEmpty)

        WhaleySrcSetExternalProjectiles([bubble])
        XCTAssertEqual(projectiles.count, 0)
    }

    func testCarriedFixedBubbleUsesTheSameBounceWithoutConsumption() throws {
        let host = makeHost()
        defer { WhaleySrcDisposeHost(host) }
        let game = try game(in: host)
        let player = try prepareContact(game)
        WhaleySrcSetExternalProjectiles([input(game: game, id: "carried", fixed: true, uses: 1)])
        try step(game)
        XCTAssertEqual(player.value(forKey: "airMode") as? Int, 1)
        let projectiles = try XCTUnwrap(game.value(forKey: "projectiles") as? NSMutableArray)
        XCTAssertEqual(projectiles.count, 1)
        let contact = try XCTUnwrap(WhaleySrcDrainGameEvents().first { ($0["externalID"] as? String) == "carried" })
        XCTAssertEqual(contact["remainingUses"] as? Int, 1)
        XCTAssertEqual(contact["popped"] as? Bool, false)
    }

    func testStoppingEmbeddedHostDeliversPendingOutcomeOnceAfterTeardown() async throws {
        let view = SrcWhaleySKView(frame: .zero)
        let replacement = SrcWhaleySKView(frame: .zero)
        defer { view.stopNativeSession(); replacement.stopNativeSession() }
        view.startNativeSession(configuration: .init(sessionID: "outgoing"))
        let game = try game(in: XCTUnwrap(view.scene))
        _ = try prepareContact(game)
        WhaleySrcSetExternalProjectiles([input(game: game, id: "last-bubble", fixed: false, uses: 1)])
        try step(game)
        let outgoingState = WhaleySrcHostState()

        let delivered = expectation(description: "Pending outcome delivered after teardown")
        delivered.assertForOverFulfill = true
        var frames: [WhaleyEmbeddedFrame] = []
        var stopReturned = false
        view.onEmbeddedFrame = { frame in
            XCTAssertTrue(stopReturned, "A stop inside a representable update must not call its client synchronously")
            XCTAssertNil(view.scene)
            XCTAssertTrue(WhaleySrcHostState().isEmpty)
            frames.append(frame)
            // The deadline measures delivery, not the successor's synchronous
            // level/resource startup. This MainActor callback finishes before
            // the awaiting test can resume and inspect the replacement below.
            delivered.fulfill()
            // A client can start another host without the old teardown removing it.
            replacement.startNativeSession(configuration: .init(sessionID: "from-callback"))
        }

        view.stopNativeSession()
        stopReturned = true
        XCTAssertTrue(frames.isEmpty)
        view.stopNativeSession() // An idempotent second stop cannot enqueue the event again.
        await fulfillment(of: [delivered], timeout: 1)

        XCTAssertEqual(frames.count, 1)
        let frame = try XCTUnwrap(frames.first)
        XCTAssertEqual(frame.sessionID, "outgoing")
        XCTAssertEqual(frame.sequence, 1)
        XCTAssertEqual(frame.level, 1)
        XCTAssertEqual(frame.playerX, try XCTUnwrap(outgoingState["playerX"] as? NSNumber).doubleValue)
        XCTAssertEqual(frame.gameTime, try XCTUnwrap(outgoingState["gameTime"] as? NSNumber).doubleValue)
        XCTAssertEqual(frame.events, [.bubbleContact(id: "last-bubble", remainingUses: 0, popped: true, bounced: true)])
        XCTAssertNotNil(replacement.scene)
        XCTAssertEqual(WhaleySrcCurrentLevelNumber(), 1)
        XCTAssertTrue(WhaleySrcDrainGameEvents().isEmpty)
    }

    func testReplacementKeepsOutgoingIdentityAndObsoleteStopCannotDrainItsEvents() async throws {
        let outgoing = SrcWhaleySKView(frame: .zero)
        let replacement = SrcWhaleySKView(frame: .zero)
        defer { outgoing.stopNativeSession(); replacement.stopNativeSession() }
        outgoing.startNativeSession(configuration: .init(sessionID: "old-session"))
        let oldGame = try game(in: XCTUnwrap(outgoing.scene))
        _ = try prepareContact(oldGame)
        WhaleySrcSetExternalProjectiles([input(game: oldGame, id: "old-bubble", fixed: false, uses: 1)])
        try step(oldGame)

        let oldDelivered = expectation(description: "Outgoing host outcome")
        let newDelivered = expectation(description: "Replacement host outcome")
        oldDelivered.assertForOverFulfill = true
        newDelivered.assertForOverFulfill = true
        var oldFrames: [WhaleyEmbeddedFrame] = []
        var newFrames: [WhaleyEmbeddedFrame] = []
        outgoing.onEmbeddedFrame = { oldFrames.append($0); oldDelivered.fulfill() }

        // Starting the successor stops the old view synchronously, but defers its callback.
        replacement.startNativeSession(configuration: .init(sessionID: "new-session"))
        replacement.onEmbeddedFrame = { newFrames.append($0); newDelivered.fulfill() }
        XCTAssertTrue(oldFrames.isEmpty)
        let newGame = try game(in: XCTUnwrap(replacement.scene))
        _ = try prepareContact(newGame)
        WhaleySrcSetExternalProjectiles([input(game: newGame, id: "new-bubble", fixed: false, uses: 1)])
        try step(newGame)

        outgoing.stopNativeSession() // Must not drain the successor's pending native outcome.
        XCTAssertNotNil(replacement.scene)
        replacement.stopNativeSession()
        XCTAssertTrue(newFrames.isEmpty)
        await fulfillment(of: [oldDelivered, newDelivered], timeout: 1)

        XCTAssertEqual(oldFrames.count, 1)
        XCTAssertEqual(newFrames.count, 1)
        let oldFrame = try XCTUnwrap(oldFrames.first)
        let newFrame = try XCTUnwrap(newFrames.first)
        XCTAssertEqual(oldFrame.sessionID, "old-session")
        XCTAssertEqual(newFrame.sessionID, "new-session")
        XCTAssertEqual(oldFrame.sequence, 1)
        XCTAssertEqual(newFrame.sequence, 1)
        XCTAssertEqual(oldFrame.events, [.bubbleContact(id: "old-bubble", remainingUses: 0, popped: true, bounced: true)])
        XCTAssertEqual(newFrame.events, [.bubbleContact(id: "new-bubble", remainingUses: 0, popped: true, bounced: true)])
        XCTAssertTrue(WhaleySrcHostState().isEmpty)
        XCTAssertTrue(WhaleySrcDrainGameEvents().isEmpty)
    }
}
