// UIKit delivers the initial touch point immediately, before a gesture recognizer would resolve.

#if canImport(UIKit)
import SwiftUI
import UIKit
import StadiumCore
import WhaleKartCore
import StadiumGame

struct FingerTouches: UIViewRepresentable {
    let session: StadiumSession

    func makeCoordinator() -> FingerTouchModel { FingerTouchModel(session: session) }

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.model = context.coordinator
        view.isAccessibilityElement = true
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        context.coordinator.resized(view.bounds.size)
        view.refreshAccessibility()
    }

    final class TouchView: UIView {
        var model: FingerTouchModel?
        private func id(_ t: UITouch) -> Int { ObjectIdentifier(t).hashValue }

        override func layoutSubviews() {
            super.layoutSubviews()
            model?.resized(bounds.size)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { model?.began(id(t), at: t.location(in: self)) }
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { model?.moved(id(t), to: t.location(in: self)) }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { model?.ended(id(t), at: t.location(in: self)) }
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { model?.cancelled(id(t)) }
        }

        // Replacing actions every tick would reset VoiceOver's open actions menu.
        private var accessibilityKey: String?
        private var announcedReveal: Int?

        // Announce the settled symbol only, leaving the actions menu unchanged while the reel spins.
        func refreshAccessibility() {
            guard let session = model?.session else { return }
            let live = RideRig.live(session.snapshot)
            let shown = live ?? RideRig.crewDoll(session.snapshot)
            let spinning = shown.map { session.snapshot.tick < $0.start } ?? false
            let whaley = session.snapshot.ride.whaley.shown
            let interlude = session.snapshot.ride.interlude.on?.number
            if shown == nil || spinning { announcedReveal = nil }
            let key = "\(shown?.beep ?? -1) \(live != nil) \(spinning) \(shown?.result?.rawValue ?? -1) \(whaley) \(interlude ?? 0)"
            if key == accessibilityKey { return }
            accessibilityKey = key
            if interlude != nil {
                accessibilityLabel = "The interlude: the ride waits while a fan looks at the game's stats on his phone; its Done goes back to the ride"
                accessibilityCustomActions = []
                return
            }
            if let shown {
                let words: String
                if let result = shown.result {
                    words = result.headline.lowercased()
                } else if spinning {
                    words = "Thought bubble spinning. Wait for the final symbol"
                } else {
                    words = shown.symbol == .hotDog
                        ? "Hot dog. Fire a hot dog at this fan"
                        : "\(shown.symbol.label). Hold fire"
                }
                let jumbotron = whaley ? ". Whaley on the Jumbotron" : ""
                accessibilityLabel = "The Bullpen Cart round the ring\(jumbotron). Fan \(shown.figure)\(shown.garden ? " in the garden section" : ""). \(words)"
                if !spinning, live != nil, announcedReveal != shown.beep, UIAccessibility.isVoiceOverRunning {
                    announcedReveal = shown.beep
                    UIAccessibility.post(notification: .announcement, argument: words)
                }
            } else if whaley {
                accessibilityLabel = "The Bullpen Cart round the ring. Whaley on the Jumbotron"
            } else {
                accessibilityLabel = "The Bullpen Cart round the ring"
            }
            var actions: [UIAccessibilityCustomAction] = []
            func action(_ name: String, _ run: @escaping () -> Void) {
                actions.append(UIAccessibilityCustomAction(name: name) { _ in run(); return true })
            }
            if live != nil && !spinning { action("Fire a hot dog at this fan") { session.accessibleShot() } }
            if whaley { action("Carry a bubble onto the Jumbotron and lift Whaley") { session.accessibleWhaley() } }
            action("Bounce the left wheel, steering right") { session.accessibleBounce(left: true) }
            action("Bounce the right wheel, steering left") { session.accessibleBounce(left: false) }
            accessibilityCustomActions = actions
        }
    }
}

struct BubblesOverlay: View {
    let session: StadiumSession

    private static let film = Gradient(colors: [.pink, .orange, .yellow, .green, .cyan, .blue, .purple, .pink])

    var body: some View {
        let s = session.snapshot
        let map = session.map
        let marks = RideRig.bubbles(s, parameters: session.parameters, map: map)
        let pops = session.lastPops
        let tick = s.tick
        let glow = RideRig.filmGlow(phase: session.filmPhase)
        let locked = RideRig.live(s)?.locked ?? -1
        // Hide bubbles while the camera leaves the ride's picture, where their coordinates are defined.
        let shown = 1 - RideRig.interludeShare(s, parameters: session.parameters)
        Canvas { context, _ in
            for m in marks {
                let r = CGFloat(m.radius)
                let rect = CGRect(x: m.centre.x - r, y: m.centre.y - r, width: r * 2, height: r * 2)
                let colour = m.tint == .red ? Color(red: 1, green: 0.32, blue: 0.36) : Color(red: 0.72, green: 0.48, blue: 1)
                context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(m.held ? 0.22 : 0.18)))
                if let aim = m.aim {
                    let level = m.locked ? 1 : 0.35 + 0.65 * glow
                    let width = m.locked ? 6 : 2 + 4 * CGFloat(glow) * CGFloat(0.4 + 0.6 * aim)
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: width / 2, dy: width / 2)),
                                   with: .conicGradient(Self.film, center: m.centre, angle: .degrees(Double(tick) * (m.locked ? 0 : 2))),
                                   style: StrokeStyle(lineWidth: width))
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.06 + 0.12 * level * aim)))
                    if m.locked {
                        var cross = Path()
                        cross.move(to: CGPoint(x: m.centre.x - r * 0.35, y: m.centre.y)); cross.addLine(to: CGPoint(x: m.centre.x + r * 0.35, y: m.centre.y))
                        cross.move(to: CGPoint(x: m.centre.x, y: m.centre.y - r * 0.35)); cross.addLine(to: CGPoint(x: m.centre.x, y: m.centre.y + r * 0.35))
                        context.stroke(cross, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
                    }
                } else {
                    context.stroke(Path(ellipseIn: rect), with: .color(colour.opacity(m.frozen ? 0.95 : 0.6)), lineWidth: m.held ? 3 : 2)
                }
                let shine = CGRect(x: m.centre.x - r * 0.55, y: m.centre.y - r * 0.62, width: r * 0.42, height: r * 0.28)
                context.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.55)))
            }
            for pop in pops {
                let age = CGFloat(tick - pop.tick) / 12
                let r = CGFloat(pop.radius) * (1 + 0.7 * age)
                let rect = CGRect(x: pop.point.x - r, y: pop.point.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(Double(max(0, 0.8 - age)))), lineWidth: 2)
            }
        }
        .opacity(shown)
        .sensoryFeedback(.impact(weight: .medium), trigger: locked) { old, new in old < 0 && new >= 0 }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
