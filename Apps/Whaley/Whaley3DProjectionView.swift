import WhaleyHost
import RealityKit
import SwiftUI
import UIKit
import WhaleyCore
import WhaleyObjectiveC

/// First-person optical projection of the authoritative original 2D world.
/// The infinite camera bubble has no collision body or gameplay authority.
@MainActor
struct Whaley3DProjectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var pressIsDown = false
    @State private var world: WhaleyProjection3D.World?
    @State private var cameraEye: WhaleyProjection3D.Point?
    @State private var hold = Whaley3DHoldSession()
    @State private var captureLoopID: UUID?
    @State private var bounceSequence: UInt64 = 0
    @State private var renderer = WhaleyRealityProjectionRenderer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if let world {
                    GeometryReader { geometry in
                        RealityView { content in
                            content.camera = .virtual
                            content.add(renderer.root)
                            content.add(renderer.camera)
                            renderer.render(world, trackingEye: cameraEye)
                        } update: { _ in
                            renderer.render(world, trackingEye: cameraEye)
                        }
                        .background(.black)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .targetedToAnyEntity()
                                .exclusively(before: DragGesture(minimumDistance: 0))
                                .updating($pressIsDown) { _, isDown, _ in isDown = true }
                                .onChanged { value in
                                    switch value {
                                    case .first(let targeted):
                                        beginHold(at: targeted.gestureValue.startLocation,
                                            viewport: geometry.size,
                                            target: renderer.pressTarget(for: targeted.entity))
                                    case .second(let emptySpace):
                                        beginHold(at: emptySpace.startLocation,
                                            viewport: geometry.size, target: .empty)
                                    }
                                }
                                .onEnded { _ in releaseHold() }
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Inside Whaley's permanent optical bubble, looking upward")
                    .accessibilityHint("Press a blue bubble to grow it. Elsewhere, tap center for a vertical bubble or either side for angled ascent. White foundation bubbles cannot be edited.")
                    HStack {
                        Text("Level \(world.level)")
                        Spacer()
                        Text(world.gameTime.formatted(.number.precision(.fractionLength(1))) + "s")
                        Spacer()
                        Text("Bounces \(bounceSequence)")
                            .accessibilityLabel("Confirmed bounces: \(bounceSequence)")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("No active level", systemImage: "circle.dotted.circle",
                        description: Text("Start a level in Whaley 2D to see its live optical bubble."))
                }
                Text("Whaley: cyan · permanent bottom bubbles: white · player-created bubbles: blue. Red light signals flames; gold signals coins.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Press a blue bubble: grow that bubble. Elsewhere: center shoots vertically, sides shoot at an angle. White foundation bubbles are fixed. New bubbles shot mid-jump return to the jump anchor. Player-created bubbles pop on one bounce; bottom bubbles keep bouncing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Body positions and bubble sizes come from the shared Objective-C game. The camera remains at the jump origin while Whaley moves.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Inside the Bubble")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        releaseHold()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { WhaleySrc3DSetEnabled(true) }
        .onChange(of: pressIsDown) { _, isDown in
            // onEnded is not delivered for every system cancellation. The
            // gesture-state reset releases the native hold in those cases too.
            if !isDown { releaseHold() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { interruptHold() }
        }
        .onDisappear {
            captureLoopID = nil
            releaseHold()
            WhaleySrc3DSetEnabled(false)
        }
        .task { @MainActor in
            guard !Task.isCancelled else { return }
            let loopID = UUID()
            captureLoopID = loopID
            defer {
                // A cancelled loop may resume after the sheet has reappeared.
                // Its cleanup must not cancel the replacement loop's new press.
                if captureLoopID == loopID {
                    interruptHold()
                    captureLoopID = nil
                }
            }
            var rig = Whaley3DJumpCamera()
            var previousSession: String?
            var lastTick = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled && captureLoopID == loopID {
                let now = ProcessInfo.processInfo.systemUptime
                if let frame = Self.capture() {
                    if previousSession != frame.world.session {
                        rig.reset()
                        previousSession = frame.world.session
                    }
                    // Validate native scene identity BEFORE applying any growth.
                    // This also preserves a new press begun after a retry but
                    // before the renderer has received its first new-scene frame.
                    updateHold(using: frame)
                    let eye = rig.update(playerBottom: frame.playerBottom,
                        airborne: frame.airborne, jumpSequence: frame.jumpSequence,
                        jumpStartBottom: frame.jumpStartBottom, deltaSeconds: now - lastTick)
                    cameraEye = eye
                    world = frame.world
                    bounceSequence = frame.jumpSequence
                } else {
                    interruptHold()
                    world = nil
                    bounceSequence = 0
                    cameraEye = nil
                    rig.reset()
                    previousSession = nil
                }
                lastTick = now
                do { try await Task.sleep(for: .milliseconds(33)) }
                catch { break }
            }
        }
    }

    private func beginHold(at location: CGPoint, viewport: CGSize,
                           target: Whaley3DPressRouter.Target) {
        guard hold.acceptsNewPress else { return }
        // Do not bind a press to the possibly stale frame displayed by SwiftUI.
        let frame = Self.capture()
        guard hold.begin(session: frame?.world.session ?? "",
                         simulationTime: frame?.world.gameTime ?? .nan) else { return }
        guard scenePhase == .active, let frame, !frame.dead,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0,
              location.x.isFinite, location.y.isFinite,
              location.x >= 0, location.x <= viewport.width,
              location.y >= 0, location.y <= viewport.height else {
            interruptHold()
            return
        }
        // A stale entity or rejected native selection must NOT fall back to a
        // shot: that would spend another bubble while the player tries to grow one.
        let intent = Whaley3DPressRouter.intent(for: target,
            currentSession: frame.world.session,
            horizontalFraction: Double(location.x / viewport.width))
        switch intent {
        case .ignore:
            interruptHold()
        case let .grow(session, projectileID):
            if !WhaleySrc3DBeginExistingBubble(session, projectileID) { interruptHold() }
        case let .shoot(direction):
            let action: WhaleyAdventureAction
            switch direction {
            case .left: action = .shootLeft
            case .below: action = .shootBelow
            case .right: action = .shootRight
            }
            if !WhaleySrc3DBeginBubble(action) { interruptHold() }
        }
    }

    private func updateHold(using frame: Frame) {
        let wasHolding = hold.isHolding
        if let duration = hold.elapsed(session: frame.world.session,
                                       simulationTime: frame.world.gameTime,
                                       canContinue: !frame.dead) {
            // The bridge still owns the actual projectile, limits and collisions.
            WhaleySrc3DUpdateHeldBubble(duration)
        } else if wasHolding {
            WhaleySrc3DEndHeldBubble()
        }
    }

    private func interruptHold() {
        WhaleySrc3DEndHeldBubble()
        hold.cancel()
    }

    private func releaseHold() {
        WhaleySrc3DEndHeldBubble()
        hold.release()
    }

    private struct Frame {
        let world: WhaleyProjection3D.World
        let playerBottom: WhaleyProjection3D.Point
        let jumpStartBottom: WhaleyProjection3D.Point
        let airborne: Bool
        let jumpSequence: UInt64
        let dead: Bool
    }

    private static func capture() -> Frame? {
        guard let current = WhaleyLiveSceneCapture.current() else { return nil }
        let world = WhaleyProjection3D.project(current.snapshot, precisePlayer: current.precisePlayer)
        let z = world.player.center.z
        func convert(_ pixel: CGPoint) -> WhaleyProjection3D.Point {
            .init(x: Double(pixel.x) / current.tileWidth,
                  y: Double(pixel.y) / current.tileHeight, z: z)
        }
        return Frame(world: world,
            playerBottom: convert(WhaleySrc3DPlayerBottom()),
            jumpStartBottom: convert(WhaleySrc3DJumpStartBottom()),
            airborne: WhaleySrc3DIsAirborne(), jumpSequence: UInt64(WhaleySrc3DJumpSequence()),
            dead: current.snapshot.dead)
    }
}
