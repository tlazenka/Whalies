#if canImport(UIKit) && canImport(SpriteKit)
import SwiftUI
import WhaleyCore
import WhaleyHost
import StadiumCore
import StadiumGame

// Stadium supplies projection and input; the shared Whaley host owns rendering and outcomes.
struct JumbotronWhaleyView: View {
    let session: StadiumSession
    let shown: Bool

    var body: some View {
        let configuration = session.parameters.ride.whaley
        WhaleyEmbeddedGameView(
            configuration: WhaleyEmbeddedConfiguration(
                sessionID: session.whaleySessionID,
                width: Double(configuration.screenWidth),
                height: Double(configuration.screenHeight),
                soundEffectsEnabled: false
            ),
            isActive: shown && session.isRunning,
            bubbles: session.snapshot.ride.whaley.over.map {
                WhaleyEmbeddedBubble(id: String($0.id), x: $0.screenX.double, y: $0.screenY.double,
                                     diameter: $0.size.double, remainingUses: $0.uses, fixed: $0.fixed, held: $0.moved)
            },
            onFrame: { frame in session.receiveWhaley(frame.stadiumFrame) }
        )
        .allowsHitTesting(false)
    }
}

private extension WhaleyEmbeddedFrame {
    var stadiumFrame: JumbotronFrame {
        let state = WhaleyObservation(
            ready: true, number: level, gameTime: gameTime,
            x: Fixed(playerX), y: Fixed(playerY), width: Fixed(playerWidth), height: Fixed(playerHeight),
            layer: LevelSpot(Fixed(layerX), Fixed(layerY)), dead: dead, won: completed
        )
        let results: [WhaleyEvent] = events.compactMap { event in
            switch event {
            case .bubbleContact(let id, let remainingUses, let popped, let bounced):
                guard let id = Int(id) else { return nil }
                return .bubbleContact(id: id, remainingUses: remainingUses, popped: popped, bounced: bounced)
            case .coinCollected: return .coin
            case .died: return .died
            case .levelCompleted: return .goal
            }
        }
        return JumbotronFrame(sessionID: sessionID, sequence: sequence, observation: state, events: results)
    }
}
#endif
