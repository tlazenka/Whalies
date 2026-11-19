#if canImport(UIKit)
import SwiftUI
import StadiumCore
import WhaleKartCore
import CrowdCore
import StadiumGame

public struct StadiumRootView: View {
    @State private var session = StadiumSession()
    @State private var readiness = StadiumSceneReadiness()
    @State private var sceneReady = false
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ZStack {
            StadiumSplash.blue.ignoresSafeArea()
            ZStack {
                RideView(session: session, readiness: readiness, onSceneReady: sceneDidBecomeReady)
                    .ignoresSafeArea()
                VStack(spacing: 6) {
                    TopBar(session: session)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
            }
            .allowsHitTesting(sceneReady)
            .accessibilityHidden(!sceneReady)
            StadiumSplash(isReady: sceneReady)
        }
        .onAppear {
            isVisible = true
            OrientationLock.apply()
            if sceneReady && scenePhase == .active { session.start() }
        }
        .onDisappear {
            isVisible = false
            session.releaseEverything()
            session.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding may omit touch-end events; cancel held input before stopping.
            if phase == .active {
                if isVisible && sceneReady { session.start() }
            } else {
                session.releaseEverything()
                session.stop()
            }
        }
    }

    private func sceneDidBecomeReady() {
        guard !sceneReady else { return }
        sceneReady = true
        // A queued frame callback can arrive after onDisappear but before the
        // UIKit host is dismantled. Retain readiness without restarting offscreen.
        if isVisible && scenePhase == .active { session.start() }
    }
}

struct RideView: View {
    let session: StadiumSession
    let readiness: StadiumSceneReadiness
    let onSceneReady: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RideSceneView(session: session, readiness: readiness, onSceneReady: onSceneReady)
                JumbotronOnItsScreen(session: session, size: size)
                BubblesOverlay(session: session)
                FingerTouches(session: session)
                InterludeOverlay(session: session, size: size)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

struct JumbotronOnItsScreen: View {
    let session: StadiumSession
    let size: CGSize

    var body: some View {
        let corners = ScreenCorners.project(Cameras.jumbotronCorners(parameters: session.parameters), camera: session.camera, viewSize: size)
        ScreenFace(corners: corners, size: CGSize(width: 480, height: 270)) {
            JumbotronFace(session: session)
        }
    }
}

struct JumbotronFace: View {
    let session: StadiumSession

    var body: some View {
        let shows = RideRig.jumbotron(session.snapshot, parameters: session.parameters)
        ZStack {
            // Keep hidden programs mounted to preserve their scene state between appearances.
            CrewPicture(session: session).opacity(shows.isCrew ? 1 : 0)
            #if canImport(SpriteKit)
            JumbotronWhaleyView(session: session, shown: shows.isWhaley).opacity(shows.isWhaley ? 1 : 0)
            #endif
            switch shows {
            case .crew, .whaley: EmptyView()
            case .ball, .pitcher, .fan: LivePicture(session: session)
            case .result, .board: InfieldPicture(session: session)
            }
            if let result = RideRig.resultOnJumbotron(session.snapshot, parameters: session.parameters) {
                ResultStrip(result: result.result, height: shows.isWhaley ? 48 : 57)
            }
            if let name = RideRig.balkName(session.snapshot, parameters: session.parameters) {
                VStack {
                    Text(name).font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Color.yellow)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.7), in: Capsule())
                    Spacer()
                }
                .padding(.top, 6)
            }
        }
    }
}

struct CrewPicture: View {
    let session: StadiumSession

    var body: some View {
        CrewShotView(session: session)
    }
}

struct ResultStrip: View {
    let result: ShotResult
    let height: CGFloat

    var body: some View {
        let mark = RideRig.ResultMark(result)
        let colour = mark == .check ? Color.green : Color.red
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                colour.opacity(0.85)
                Circle().fill(Color.white)
                    .frame(width: height * 0.8, height: height * 0.8)
                Image(systemName: mark.symbol)
                    .font(.system(size: height * 0.44, weight: .black))
                    .foregroundStyle(colour)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
        }
    }
}

struct CrewShotView: View {
    let session: StadiumSession

    var body: some View {
        let shot = RideRig.crewShot(session.snapshot, figures: session.game.figures, seats: session.parameters.stands.seats,
                                    garden: { session.game.isInGarden($0) }, flight: session.lastFlight)
        Canvas { context, size in
            guard let shot else { return }
            ShotDrawing.draw(shot, in: &context, size: size)
        }
    }
}

enum ShotDrawing {
    static func draw(_ shot: RideRig.CrewShot, in context: inout GraphicsContext, size: CGSize) {
        let sx = size.width / CGFloat(RideRig.crewSize.x), sy = size.height / CGFloat(RideRig.crewSize.y)
        func at(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: CGFloat(p.x) * sx, y: CGFloat(p.y) * sy) }
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(shot.backdrop.color))
        for piece in shot.pieces {
            if piece.radius > 0, let c = piece.points.first {
                let r = CGFloat(piece.radius)
                let rect = CGRect(x: at(c).x - r * sx, y: at(c).y - r * sy, width: 2 * r * sx, height: 2 * r * sy)
                if piece.part == .glow {
                    context.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [piece.paint.color.opacity(0.75), piece.paint.color.opacity(0)]),
                        center: at(c), startRadius: 0, endRadius: r * sx))
                } else {
                    context.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [piece.paint.lit(1.2).color, piece.paint.color, piece.paint.lit(0.75).color]),
                        center: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.3),
                        startRadius: 0, endRadius: r * sx * 1.9))
                    context.stroke(Path(ellipseIn: rect), with: .color(piece.paint.lit(0.45).color), lineWidth: 1.5 * sx)
                }
            } else if piece.points.count >= 3 {
                var face = Path()
                face.addLines(piece.points.map(at))
                face.closeSubpath()
                let flat = piece.part == .thoughtBubble || piece.part == .thoughtSymbol
                context.fill(face, with: .color(flat ? piece.paint.color : piece.paint.lit(piece.light).color))
                if !flat { context.stroke(face, with: .color(piece.paint.lit(0.45).color), lineWidth: 1.5 * sx) }
            }
        }
    }
}

struct LivePicture: View {
    let session: StadiumSession

    var body: some View {
        Canvas { context, size in
            guard let shot = RideRig.liveShot(session.snapshot, figures: session.game.figures, parameters: session.parameters,
                                              flight: session.lastFlight) else { return }
            ShotDrawing.draw(shot, in: &context, size: size)
        }
    }
}

extension Paint {
    var color: Color { Color(red: r, green: g, blue: b) }
}

struct InfieldPicture: View {
    let session: StadiumSession

    var body: some View {
        Canvas { context, size in
            ShotDrawing.draw(RideRig.infieldShot(session.snapshot, parameters: session.parameters), in: &context, size: size)
        }
    }
}

struct TopBar: View {
    let session: StadiumSession

    var body: some View {
        HStack(spacing: 10) {
            RideTempo(session: session)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            Menu {
                RideTallySection(session: session)
                DebugSection(session: session)
                Section {
                    Button("Play again", systemImage: "arrow.counterclockwise") { session.playAgain() }
                    Picker(selection: Binding(get: { session.audioOutput }, set: { session.audioOutput = $0 })) {
                        ForEach(AudioOutput.allCases) { Text($0.rawValue).tag($0) }
                    } label: {
                        Label("Sound", systemImage: "speaker.wave.2")
                    }
                    Button("Save run", systemImage: "square.and.arrow.down") {
                        _ = session.saveRecording()
                    }
                }
            } label: {
                MenuLabel(session: session)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
    }
}

struct RideTempo: View {
    let session: StadiumSession

    var body: some View {
        let s = session.snapshot
        let bpm = Int(s.ride.tempo.double.rounded())
        HStack(spacing: 6) {
            Circle().fill(Color.yellow.opacity(0.25 + 0.75 * RideRig.beatGlow(s))).frame(width: 9, height: 9)
            Text("\(bpm) bpm").font(.subheadline.weight(.bold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bpm) beats a minute")
    }
}

struct MenuLabel: View {
    let session: StadiumSession

    var body: some View {
        Image(systemName: "ellipsis.circle").font(.title3)
            .foregroundStyle(session.repeatState == .off ? Color.white : Color.yellow)
            .accessibilityLabel(session.repeatState == .off ? "Menu" : "Menu, debug: \(RideRig.debugTitle(session.repeatState))")
    }
}

// Read the cached tally instead of the snapshot to avoid redrawing the menu every tick.
struct RideTallySection: View {
    let session: StadiumSession

    var body: some View {
        Section("WhaleKart") {
            ForEach(session.menuTally) { line in
                Label(line.text, systemImage: line.symbol)
            }
        }
    }
}

struct DebugSection: View {
    let session: StadiumSession

    var body: some View {
        Section("Debug") {
            Picker(selection: Binding(get: { session.repeatState }, set: { session.setRepeat($0) })) {
                ForEach(RepeatState.allCases, id: \.self) { state in
                    Text(RideRig.debugTitle(state)).tag(state)
                }
            } label: {
                Label("Level", systemImage: "ladybug")
            }
            .pickerStyle(.inline)
            Toggle(isOn: Binding(get: { session.parked }, set: { session.setParked($0) })) {
                Label("Static", systemImage: "pause.circle")
            }
            .disabled(session.repeatState == .off)
        }
    }
}
#endif
