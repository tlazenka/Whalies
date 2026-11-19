#if canImport(UIKit)
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import StadiumCore
import StadiumGame
import JSONViewKit

struct InterludeOverlay: View {
    let session: StadiumSession
    let size: CGSize

    var body: some View {
        let s = session.snapshot
        let viewSize = SIMD2(Float(size.width), Float(size.height))
        let frame = RideRig.phoneFrame(viewSize: viewSize)
        let down = RideRig.phoneDown(s, parameters: session.parameters) ?? 1
        let acceptsInput = down == 0 && s.ride.interlude.on?.isBrowsing == true
        let offset = down * (Double(size.height) - frame.top + 40)
        let touch = session.phoneHand.tip(at: s.tick, rest: RideRig.handRest(screen: frame.screen))
        let hands = RideRig.fanHands(frame: frame, offset: offset, viewSize: viewSize, tip: touch.point, pressed: touch.pressed)
        ZStack {
            if let number = session.phone?.number {
                if down < 1 { FanHandsView(limbs: hands.behind) }
                FanPhone(session: session, screen: frame.screen)
                    .position(frame.centre)
                    .offset(y: CGFloat(offset))
                    .allowsHitTesting(acceptsInput)
                    .accessibilityHidden(!acceptsInput)
                    .id(number)
                if down < 1 { FanHandsView(limbs: hands.over, finger: hands) }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct FanPhone: View {
    let session: StadiumSession
    let screen: CGSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(Color(white: 0.06))
                .frame(width: screen.width + 18, height: screen.height + 30)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
            PhoneScreenHost(session: session) { phase, point in session.phoneTouch(phase, at: point) }
                .frame(width: screen.width, height: screen.height)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .frame(width: screen.width + 18, height: screen.height + 30)
    }
}

// Composite limbs before applying opacity so overlaps do not darken the transparent hands.
struct FanHandsView: View {
    let limbs: [RideRig.Limb]
    var finger: RideRig.FanHands? = nil

    static let skin = Color(red: 0.9, green: 0.75, blue: 0.6)
    static let rim = Color(red: 0.42, green: 0.3, blue: 0.22)

    var body: some View {
        Canvas { context, _ in
            context.opacity = 0.36
            context.drawLayer { layer in
                for limb in limbs {
                    for piece in Self.pieces(limb, grow: 1.6) { layer.fill(piece, with: .color(Self.rim)) }
                }
                for limb in limbs {
                    for piece in Self.pieces(limb, grow: 0) { layer.fill(piece, with: .color(Self.skin)) }
                }
                if let f = finger { layer.fill(Self.nail(f), with: .color(.white.opacity(0.7))) }
            }
            if let f = finger, f.pressed {
                context.opacity = 0.85
                let r = f.unit * 0.55
                let ring = Path(ellipseIn: CGRect(x: Double(f.tip.x) - r, y: Double(f.tip.y) - r, width: 2 * r, height: 2 * r))
                context.stroke(ring, with: .color(.white), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func pieces(_ l: RideRig.Limb, grow g: Double) -> [Path] {
        let ax = Double(l.from.x), ay = Double(l.from.y), bx = Double(l.to.x), by = Double(l.to.y)
        let ra = l.fromRadius + g, rb = l.toRadius + g
        let length = max(1e-9, hypot(bx - ax, by - ay))
        let nx = -(by - ay) / length, ny = (bx - ax) / length
        var band = Path()
        band.addLines([CGPoint(x: ax + nx * ra, y: ay + ny * ra), CGPoint(x: bx + nx * rb, y: by + ny * rb),
                       CGPoint(x: bx - nx * rb, y: by - ny * rb), CGPoint(x: ax - nx * ra, y: ay - ny * ra)])
        band.closeSubpath()
        return [Path(ellipseIn: CGRect(x: ax - ra, y: ay - ra, width: 2 * ra, height: 2 * ra)),
                Path(ellipseIn: CGRect(x: bx - rb, y: by - rb, width: 2 * rb, height: 2 * rb)), band]
    }

    static func nail(_ f: RideRig.FanHands) -> Path {
        let along = f.unit * 0.3, across = f.unit * 0.25
        let cx = Double(f.tip.x) - Double(f.pointing.x) * f.unit * 0.36, cy = Double(f.tip.y) - Double(f.pointing.y) * f.unit * 0.36
        let angle = atan2(Double(f.pointing.y), Double(f.pointing.x))
        return Path(ellipseIn: CGRect(x: -along, y: -across, width: 2 * along, height: 2 * across))
            .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: cx, y: cy)))
    }
}

// A separate host lets the touch observer see the explorer's UIKit descendants.
struct PhoneScreenHost: UIViewControllerRepresentable {
    let session: StadiumSession
    let onTouch: (TouchPhase, CGPoint) -> Void

    func makeCoordinator() -> TouchWatcher {
        let watcher = TouchWatcher(target: nil, action: nil)
        watcher.cancelsTouchesInView = false
        watcher.delaysTouchesBegan = false
        watcher.delaysTouchesEnded = false
        watcher.delegate = watcher
        return watcher
    }

    func makeUIViewController(context: Context) -> UIHostingController<PhoneScreen> {
        let host = UIHostingController(rootView: PhoneScreen(session: session))
        // Use the simulated phone's full screen, independent of the device window's safe area.
        host.safeAreaRegions = []
        host.view.backgroundColor = .systemBackground
        context.coordinator.report = onTouch
        host.view.addGestureRecognizer(context.coordinator)
        return host
    }

    func updateUIViewController(_ host: UIHostingController<PhoneScreen>, context: Context) {
        context.coordinator.report = onTouch
    }
}

// Observe without recognizing, cancelling or delaying touches, leaving explorer gestures intact.
final class TouchWatcher: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var report: ((TouchPhase, CGPoint) -> Void)?
    private weak var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard tracked == nil, let t = touches.first else { return }
        tracked = t
        report?(.began, t.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let t = tracked, touches.contains(t) else { return }
        report?(.moved, t.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if let t = tracked, touches.contains(t) {
            tracked = nil
            report?(.ended, t.location(in: view))
        }
        failOnceLifted(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if let t = tracked, touches.contains(t) {
            tracked = nil
            report?(.cancelled, t.location(in: view))
        }
        failOnceLifted(event)
    }

    // Failing after all fingers lift lets UIKit reset this passive recognizer for the next touch.
    private func failOnceLifted(_ event: UIEvent) {
        let down = event.allTouches?.contains { $0.phase != .ended && $0.phase != .cancelled } ?? false
        if !down { state = .failed }
    }

    override func reset() {
        super.reset()
        // UIKit may reset without delivering an end; report cancellation for the tracked touch.
        if let t = tracked {
            tracked = nil
            report?(.cancelled, t.location(in: view))
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

struct PhoneScreen: View {
    let session: StadiumSession
    @State private var tab = PhoneTab.stats

    var body: some View {
        let feed = session.phone
        TabView(selection: $tab) {
            NavigationStack {
                Group {
                    if let feed {
                        JSONNodeView(root: feed.root, analytics: session.explorer.analytics, title: "Every moment", copiesCommand: false,
                                     remembersFacet: false, preferences: session.explorer.preferences,
                                      onEvent: { event, properties in session.phoneRecorded(event, properties) })
                    } else {
                        ProgressView()
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { session.phoneDone() }
                    }
                }
            }
            .tabItem { Label(PhoneTab.stats.rawValue, systemImage: "list.bullet.rectangle") }
            .tag(PhoneTab.stats)

            NavigationStack {
                WrappedView(analytics: session.explorer.analytics, supplemental: feed?.cards ?? [],
                            title: "Round \(feed?.number ?? 1) wrapped",
                            emptyMessage: "Browse the game's moments and use facets or scrub to build your browsing history.")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { session.phoneDone() }
                        }
                    }
            }
            .tabItem { Label(PhoneTab.wrapped.rawValue, systemImage: "gift") }
            .tag(PhoneTab.wrapped)
        }
        .environment(\.horizontalSizeClass, .compact)
        .onChange(of: tab) { _, now in session.phoneTabbed(now) }
        .task { await session.explorer.prepare() }
    }
}
#endif
