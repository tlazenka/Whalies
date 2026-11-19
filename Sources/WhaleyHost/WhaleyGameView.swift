#if canImport(UIKit) && canImport(SpriteKit)
import SpriteKit
import SwiftUI
import UIKit
import WhaleyCore
import WhaleyObjectiveC
import WhaleySpriteKit

@MainActor
public struct SrcWhaleyView: UIViewRepresentable {
    var designerEnabled = false
    var emptyScrubFeedbackEnabled: @MainActor () -> Bool
    var onMainMenuVisibilityChanged: (@MainActor (Bool) -> Void)?
    var designerProjection: ((CGPoint, SrcWhaleySKView) -> Void)? = nil

    public init(designerEnabled: Bool = false,
                emptyScrubFeedbackEnabled: @escaping @MainActor () -> Bool = { false },
                onMainMenuVisibilityChanged: (@MainActor (Bool) -> Void)? = nil,
                designerProjection: ((CGPoint, SrcWhaleySKView) -> Void)? = nil) {
        self.designerEnabled = designerEnabled
        self.emptyScrubFeedbackEnabled = emptyScrubFeedbackEnabled
        self.onMainMenuVisibilityChanged = onMainMenuVisibilityChanged
        self.designerProjection = designerProjection
    }

    public func makeUIView(context: Context) -> SrcWhaleySKView {
        let view = SrcWhaleySKView(frame: .zero)
        view.startNativeSession()
        view.designerEnabled = designerEnabled
        view.emptyScrubFeedbackEnabled = emptyScrubFeedbackEnabled
        view.onMainMenuVisibilityChanged = onMainMenuVisibilityChanged
        view.designerProjection = designerProjection
        return view
    }

    public func updateUIView(_ uiView: SrcWhaleySKView, context: Context) {
        uiView.designerEnabled = designerEnabled
        uiView.emptyScrubFeedbackEnabled = emptyScrubFeedbackEnabled
        uiView.onMainMenuVisibilityChanged = onMainMenuVisibilityChanged
        uiView.designerProjection = designerProjection
    }

    public static func dismantleUIView(_ uiView: SrcWhaleySKView, coordinator: ()) {
        uiView.stopNativeSession()
    }
}

@MainActor
public final class SrcWhaleySKView: SKView {
    private static weak var activeHost: SrcWhaleySKView?
    private var ownsNativeSession = false
    private var hostActive = true
    private var embeddedConfiguration: WhaleyEmbeddedConfiguration?
    private var embeddedSequence = 0
    var embeddedBubbles: [WhaleyEmbeddedBubble] = []
    var onEmbeddedFrame: (@MainActor (WhaleyEmbeddedFrame) -> Void)?
    var emptyScrubFeedbackEnabled: @MainActor () -> Bool = { false }
    var onMainMenuVisibilityChanged: (@MainActor (Bool) -> Void)?
    private var lastReportedMainMenuVisibility: Bool?

    /// The legacy director has one authoritative native session. Replacing its
    /// host stops the previous session first, including recorder and observers.
    func startNativeSession(configuration: WhaleyEmbeddedConfiguration? = nil) {
        if ownsNativeSession && configuration == embeddedConfiguration { return }
        if let configuration { precondition(configuration.isValid, "Invalid embedded Whaley configuration") }
        if ownsNativeSession, Self.activeHost === self, let previous = embeddedConfiguration,
           let configuration, let scene,
           configuration.sessionID == previous.sessionID, configuration.level == previous.level,
           configuration.width == previous.width, configuration.height == previous.height {
            // Sound is a live host preference. Changing it must not replace the
            // game, lose pending outcomes or restart the frame sequence under
            // the same containing-game session identity.
            WhaleySrcSetHostSoundEffectsEnabled(scene, configuration.soundEffectsEnabled)
            embeddedConfiguration = configuration
            return
        }
        Self.activeHost?.stopNativeSession()
        Self.activeHost = self
        ownsNativeSession = true
        embeddedConfiguration = configuration
        embeddedSequence = 0
        backgroundColor = .black
        ignoresSiblingOrder = true
        preferredFramesPerSecond = 60
        WhaleyRuntimeBridgeLinkage.ensureLinked()
        WhaleyResources.configure()
        let nativeScene: SKScene
        if let configuration {
            nativeScene = WhaleyCreateSrcEmbeddedLevelSceneWithSoundEffects(configuration.level,
                CGSize(width: configuration.width, height: configuration.height), configuration.soundEffectsEnabled)
            // Stadium supplies the 3D gestures and draws the external bubbles.
            isUserInteractionEnabled = false
        } else {
            nativeScene = WhaleyCreateSrcMainMenuScene()
            isUserInteractionEnabled = true
        }
        presentScene(nativeScene)
        updateHostSuspension()
    }

    func setHostActive(_ active: Bool) {
        hostActive = active
        updateHostSuspension()
    }

    private func updateHostSuspension() {
        guard ownsNativeSession, let scene else { return }
        let suspended = !hostActive || window == nil
        WhaleySrcSetHostSuspended(scene, suspended)
        isPaused = suspended
        if suspended {
            cancelCLIRelayRequests()
            endDesignerInteractions()
            displayLink?.invalidate()
            displayLink = nil
        } else {
            startDisplayLink()
        }
    }

    func stopNativeSession() {
        cancelCLIRelayRequests()
        endDesignerInteractions()
        designerEnabled = false
        designerProjection = nil
        onMainMenuVisibilityChanged = nil
        lastReportedMainMenuVisibility = nil
        displayLink?.invalidate()
        displayLink = nil
        guard ownsNativeSession else { return }
        ownsNativeSession = false
        let terminalCallback = onEmbeddedFrame
        var terminalFrame: WhaleyEmbeddedFrame?
        if Self.activeHost === self {
            let state = WhaleySrcHostState()
            let events = consumeGameEvents()
            if terminalCallback != nil && !events.isEmpty {
                terminalFrame = makeEmbeddedFrame(state: state, events: events)
            }
            WhaleyRunRecorder.shared.finishCurrent()
            if let scene { WhaleySrcDisposeHost(scene) }
            Self.activeHost = nil
        }
        presentScene(nil)
        onEmbeddedFrame = nil
        embeddedBubbles = []
        if let terminalFrame, let terminalCallback {
            // Stop can run inside a representable update or another host's start.
            // Retain the outgoing identity, but defer client work until teardown
            // and the caller's synchronous replacement have both returned.
            Task { @MainActor in terminalCallback(terminalFrame) }
        }
    }

    var designerEnabled = false {
        didSet {
            guard designerEnabled != oldValue else { return }
            if !designerEnabled { endDesignerInteractions() }
            updateDesignerControls()
        }
    }
    var designerProjection: ((CGPoint, SrcWhaleySKView) -> Void)?
    let gameClock = AdjustableClockLabel()
    // The HUD is a native SpriteKit node, not a UIKit overlay.
    // Track HUD-owned touches so they never reach the legacy gameplay dispatcher.
    private weak var positionedHUD: SKNode?
    private var hudOwnedTouches: Set<ObjectIdentifier> = []
    var clockLongPress: UILongPressGestureRecognizer!
    var clockScrub: SceneTimeScrubSession?
    var clockOriginX: CGFloat = 0
    var displayLink: CADisplayLink?
    let sceneScrubStatus = UILabel()
    let sceneScrubCallout = WhaleyScrubCalloutView()
    private var objectScrubHUDPlacement: SceneScrubHUDPlacement?
    var objectLongPress: UILongPressGestureRecognizer!
    var objectScrub: SceneObjectScrubSession?
    var objectScrubOrigin: CGPoint = .zero
    var lastCLIRelayPublish: CFTimeInterval = 0
    var lastCLIRelayAttempt: CFTimeInterval = 0
    var cliRelayAvailable: Bool?
    var cliRelayHelloSent = false
    private var cliRelayHelloTask: URLSessionDataTask?
    private var cliRelayHelloID: UUID?
    private var cliRelayPublishTask: URLSessionDataTask?
    private var cliRelayPublishID: UUID?
    private static let cliRelaySession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    var cliRelayStateURL: URL? {
        URL(string: ProcessInfo.processInfo.environment["WHALEY_RELAY_URL"] ?? "http://127.0.0.1:8092/state")
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        installSemanticClock()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        installSemanticClock()
    }

    func installSemanticClock() {
        gameClock.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        gameClock.textColor = .white
        gameClock.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        gameClock.layer.cornerRadius = 6
        gameClock.layer.masksToBounds = true
        gameClock.textAlignment = .center
        gameClock.numberOfLines = 4
        gameClock.text = "00:00.00"
        gameClock.isAccessibilityElement = false
        gameClock.isUserInteractionEnabled = true
        addSubview(gameClock)

        clockLongPress = UILongPressGestureRecognizer(target: self, action: #selector(scrubClock(_:)))
        clockLongPress.minimumPressDuration = 0.35
        clockLongPress.cancelsTouchesInView = true
        clockLongPress.allowableMovement = 10_000
        clockLongPress.delegate = self
        gameClock.addGestureRecognizer(clockLongPress)

        installObjectSceneScrub()
        updateDesignerControls()
        startDisplayLink()
    }

    private func updateDesignerControls() {
        let hasLevel = WhaleySrcCurrentLevelNumber() > 0
        if !hasLevel { endDesignerInteractions() }
        gameClock.isHidden = !designerEnabled || !hasLevel
        let canScrub = designerEnabled && hasLevel
        if clockLongPress.isEnabled != canScrub {
            clockLongPress.isEnabled = canScrub
        }
        // A disabled recognizer must not delay ordinary gameplay touches.
        if objectLongPress.isEnabled != canScrub {
            objectLongPress.isEnabled = canScrub
        }
    }

    private func endObjectScrub() {
        let acquired = objectScrub != nil
        objectScrub = nil
        objectScrubHUDPlacement = nil
        sceneScrubCallout.isHidden = true
        sceneScrubStatus.isHidden = true
        if acquired { WhaleySrcSceneScrubEnd() }
    }

    private func endClockScrub() {
        guard clockScrub != nil else { return }
        clockScrub = nil
        WhaleySrcRestoreLiveProjection()
        WhaleySrcSetSceneScrubPaused(false)
        gameClock.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        gameClock.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        gameClock.text = SceneGameTime.seconds(WhaleySrcGameTime()).clockText
        setNeedsLayout()
    }

    private func endDesignerInteractions() {
        // Clear acquired sessions before disabling recognizers: UIKit may also
        // deliver a cancellation, which must not release the pause twice.
        endObjectScrub()
        endClockScrub()
    }

    func installObjectSceneScrub() {
        sceneScrubStatus.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        sceneScrubStatus.textColor = .white
        sceneScrubStatus.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        sceneScrubStatus.layer.cornerRadius = 6
        sceneScrubStatus.layer.masksToBounds = true
        sceneScrubStatus.textAlignment = .center
        sceneScrubStatus.isHidden = true
        sceneScrubStatus.isUserInteractionEnabled = false
        addSubview(sceneScrubStatus)

        sceneScrubCallout.isHidden = true
        sceneScrubCallout.isUserInteractionEnabled = false
        addSubview(sceneScrubCallout)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(scrubObject(_:)))
        press.minimumPressDuration = 0.35
        press.allowableMovement = 10_000
        press.cancelsTouchesInView = true
        press.delaysTouchesBegan = true
        press.delegate = self
        addGestureRecognizer(press)
        objectLongPress = press
    }

    @objc func scrubObject(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            guard designerEnabled, clockScrub == nil else { return }
            guard WhaleySrcSceneScrubBegin(location) else {
                if emptyScrubFeedbackEnabled() {
                showTransientScrubCallout(text: "No object here to scrub", anchor: location, touch: location)
                }
                return
            }
            objectScrubOrigin = location
            let target = WhaleySrcSceneScrubActiveObjectFrame()
            objectScrubHUDPlacement = SceneScrubHUDPlacement(
                originalTarget: target.isNull || target.isEmpty
                    ? CGRect(origin: location, size: .zero) : target,
                initialTouch: location,
                viewport: bounds.inset(by: safeAreaInsets)
            )
            objectScrub = SceneObjectScrubSession()
            showObjectScrubCallout()
        case .changed:
            guard designerEnabled, var scrub = objectScrub else { return }
            scrub.update(
                horizontal: Double(location.x - objectScrubOrigin.x),
                vertical: Double(location.y - objectScrubOrigin.y)
            )
            objectScrub = scrub
            WhaleySrcSceneScrubApply(scrub.category.rawValue, scrub.scalarSteps)
            // Only the value changes; the HUD and tail stay at the acquisition point.
            showObjectScrubCallout()
        case .ended, .cancelled, .failed:
            endObjectScrub()
        default:
            break
        }
    }

    func showObjectScrubCallout() {
        guard let scrub = objectScrub, let placement = objectScrubHUDPlacement else { return }
        sceneScrubCallout.text = "\(scrub.category.title)   \(scrub.scalarSteps >= 0 ? "+" : "")\(scrub.scalarSteps)"
        sceneScrubCallout.update(placement: placement, in: bounds.inset(by: safeAreaInsets))
        sceneScrubCallout.isHidden = false
        bringSubviewToFront(sceneScrubCallout)
    }

    func showTransientScrubCallout(text: String, anchor: CGPoint, touch: CGPoint) {
        let viewport = bounds.inset(by: safeAreaInsets)
        let placement = SceneScrubHUDPlacement(
            originalTarget: CGRect(origin: anchor, size: .zero),
            initialTouch: touch, viewport: viewport
        )
        sceneScrubCallout.text = text
        sceneScrubCallout.update(placement: placement, in: viewport)
        sceneScrubCallout.isHidden = false
        bringSubviewToFront(sceneScrubCallout)
    }

    func showObjectScrubStatus() {
        guard let scrub = objectScrub else { return }
        sceneScrubStatus.text = "  \(scrub.category.title)   \(scrub.scalarSteps >= 0 ? "+" : "")\(scrub.scalarSteps)  "
        sceneScrubStatus.sizeToFit()
        sceneScrubStatus.frame.size.height = 30
        sceneScrubStatus.center = CGPoint(x: bounds.midX, y: safeAreaInsets.top + 58)
        sceneScrubStatus.isHidden = false
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateHostSuspension()
        if window != nil {
            startDisplayLink()
            sendCLIRelayHelloIfNeeded()
        } else {
            endDesignerInteractions()
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    func startDisplayLink() {
        guard ownsNativeSession, hostActive, window != nil, displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(updateSemanticClock))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func spriteKitHUD() -> SKNode? {
        scene?.childNode(withName: "//WhaleyHUD")
    }

    private func isSpriteKitHUDTouch(_ touch: UITouch) -> Bool {
        guard let scene, let hud = spriteKitHUD(), !hud.isHidden,
              hud.isUserInteractionEnabled else { return false }

        // Convert through the actual SpriteKit scene transform. This handles
        // aspect-fill cropping, device rotation and the HUD's rendered position.
        let scenePoint = scene.convertPoint(fromView: touch.location(in: self))
        let localPoint = hud.convert(scenePoint, from: scene)
        return CGRect(x: -scene.size.width / 2, y: -16,
                      width: scene.size.width, height: 32).contains(localPoint)
    }

    @discardableResult
    private func layoutSpriteKitHUD() -> CGFloat? {
        guard let scene, let hud = spriteKitHUD(), let parent = hud.parent,
              !bounds.isEmpty else {
            positionedHUD = nil
            return nil
        }

        // Project the actual safe-area edge. The previous +4 view-point inset
        // and sceneHeight-2 clamp left gameplay visible above the black band.
        let topInView = CGPoint(x: bounds.midX, y: safeAreaInsets.top)
        let sceneTop = scene.convertPoint(fromView: topInView)
        guard let center = WhaleyHUDLayout.center(sceneSize: scene.size,
                                                   projectedTop: sceneTop) else { return nil }
        hud.position = parent.convert(center, from: scene)
        positionedHUD = hud
        let bottomInScene = CGPoint(x: center.x, y: center.y - WhaleyHUDLayout.barHeight / 2)
        return scene.convertPoint(toView: bottomInScene).y
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if ownsNativeSession && Self.activeHost === self {
            WhaleySrcSetCompatViewSize(bounds.size)
        }
        let hudBottom = layoutSpriteKitHUD()
        let clockWidth: CGFloat = clockScrub == nil ? 84 : 190
        let clockHeight: CGFloat = clockScrub == nil ? 30 : 76
        gameClock.frame = CGRect(
            x: bounds.width - clockWidth - 10,
            y: max(safeAreaInsets.top + 8, (hudBottom ?? safeAreaInsets.top) + 8),
            width: clockWidth,
            height: clockHeight
        )
        if objectScrub != nil, !sceneScrubCallout.isHidden {
            showObjectScrubCallout()
        }
        if !sceneScrubStatus.isHidden { showObjectScrubStatus() }
    }

    func sendCLIRelayHelloIfNeeded() {
        guard ownsNativeSession, Self.activeHost === self, hostActive, window != nil,
              !cliRelayHelloSent, let stateURL = cliRelayStateURL else { return }
        cliRelayHelloSent = true
        let helloURL = stateURL.deletingLastPathComponent().appendingPathComponent("hello")
        print("Whaley relay endpoint: \(stateURL.absoluteString)")
        var request = URLRequest(url: helloURL)
        request.setValue("mobile", forHTTPHeaderField: "X-Whaley-Client")
        request.setValue("ios-\(ProcessInfo.processInfo.processIdentifier)", forHTTPHeaderField: "X-Whaley-Client-ID")
        let helloID = UUID()
        cliRelayHelloID = helloID
        let task = Self.cliRelaySession
            .dataTask(with: request) { [weak self] _, response, error in
                let reachable =
                    error == nil && (response as? HTTPURLResponse).map { 200..<300 ~= $0.statusCode } == true
                let errorDescription = error?.localizedDescription
                    ?? (response as? HTTPURLResponse).map { "HTTP \($0.statusCode)" }
                Task { @MainActor [weak self] in
                    guard let self, self.cliRelayHelloID == helloID else { return }
                    self.cliRelayHelloTask = nil
                    self.cliRelayHelloID = nil
                    // Once publication starts, its response is authoritative:
                    // a delayed hello must not replace a newer POST result.
                    guard self.lastCLIRelayPublish == 0 else { return }
                    self.recordCLIRelayResult(url: helloURL, reachable: reachable, errorDescription: errorDescription)
                }
            }
        cliRelayHelloTask = task
        task.resume()
    }

    @MainActor
    func recordCLIRelayResult(url: URL, reachable: Bool, errorDescription: String?) {
        guard cliRelayAvailable != reachable else { return }
        cliRelayAvailable = reachable
        if reachable {
            print("Whaley relay connected: \(url.absoluteString)")
        } else {
            let detail = errorDescription.map { " — \($0)" } ?? ""
            print("Whaley relay unavailable: \(url.absoluteString)\(detail)")
        }
    }

    func publishCLIPositionIfNeeded() {
        let now = CACurrentMediaTime()
        let interval: CFTimeInterval = cliRelayAvailable == false ? 2.0 : 0.1
        // Drop intermediate frames while a request is pending. Queueing them
        // would eventually publish old positions as if they were current.
        guard cliRelayPublishTask == nil, now - lastCLIRelayAttempt >= interval else { return }
        lastCLIRelayAttempt = now
        sendCLIRelayHelloIfNeeded()
        guard let captured = WhaleyLiveSceneCapture.current(),
              let url = cliRelayStateURL,
              let payload = try? JSONEncoder().encode(captured.snapshot) else { return }
        lastCLIRelayPublish = now
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("mobile", forHTTPHeaderField: "X-Whaley-Client")
        request.setValue("ios-\(ProcessInfo.processInfo.processIdentifier)", forHTTPHeaderField: "X-Whaley-Client-ID")
        // The CLI receives the exact same schema and stable entity IDs as
        // the RealityKit renderer. Older consumers ignore liveEntities.
        request.httpBody = payload
        let publicationID = UUID()
        cliRelayPublishID = publicationID
        let task = Self.cliRelaySession
            .dataTask(with: request) { [weak self] _, response, error in
                let reachable =
                    error == nil && (response as? HTTPURLResponse).map { 200..<300 ~= $0.statusCode } == true
                let errorDescription = error?.localizedDescription
                    ?? (response as? HTTPURLResponse).map { "HTTP \($0.statusCode)" }
                Task { @MainActor [weak self] in
                    guard let self, self.cliRelayPublishID == publicationID else { return }
                    self.cliRelayPublishTask = nil
                    self.cliRelayPublishID = nil
                    self.recordCLIRelayResult(url: url, reachable: reachable, errorDescription: errorDescription)
                }
            }
        cliRelayPublishTask = task
        task.resume()
    }

    private func cancelCLIRelayRequests() {
        cliRelayHelloID = nil
        cliRelayHelloTask?.cancel()
        cliRelayHelloTask = nil
        cliRelayHelloSent = false
        cliRelayPublishID = nil
        cliRelayPublishTask?.cancel()
        cliRelayPublishTask = nil
        lastCLIRelayPublish = 0
    }

    @objc func updateSemanticClock() {
        guard ownsNativeSession, Self.activeHost === self, hostActive, window != nil else { return }
        let mainMenuVisible = WhaleySrcIsMainMenuVisible()
        if mainMenuVisible != lastReportedMainMenuVisibility {
            lastReportedMainMenuVisibility = mainMenuVisible
            onMainMenuVisibilityChanged?(mainMenuVisible)
        }
        if embeddedConfiguration != nil {
            WhaleySrcSetExternalProjectiles(embeddedBubbles.filter(\.isValid).map { bubble in
                ["id": bubble.id, "x": bubble.x, "y": bubble.y,
                 "diameter": bubble.diameter, "remainingUses": bubble.remainingUses,
                 "fixed": bubble.fixed, "held": bubble.held] as [String: Any]
            })
        }
        updateDesignerControls()
        // The host SKScene persists across level/menu transitions; reposition
        // newly installed native HUD nodes after the next gameplay transition.
        if spriteKitHUD() !== positionedHUD {
            setNeedsLayout()
        }
        if designerEnabled { designerProjection?(.zero, self) }
        let adventureTime = WhaleySrcGameTime()
        let state = WhaleySrcHostState()
        // A completed/dead scene can be replaced between display callbacks.
        // Drain its events under their original session before starting the new run.
        let events = consumeGameEvents()
        let completed = (state["completed"] as? NSNumber)?.boolValue ?? false
        if WhaleySrcCurrentLevelNumber() > 0 {
            WhaleyRunRecorder.shared.sample(
                level: WhaleySrcCurrentLevelNumber(),
                time: adventureTime,
                position: WhaleySrcPlayerPosition(),
                dead: WhaleySrcAdventurePlayerIsDead(),
                completed: completed,
                engineSession: state["session"] as? String,
                finishWhenDead: false
            )
            publishCLIPositionIfNeeded()
        } else {
            WhaleyRunRecorder.shared.finishCurrent()
        }
        // Consume the engine's confirmed event batch before closing a dead run.
        // Otherwise a final collision/coin in the batch could be dropped.
        if WhaleySrcAdventurePlayerIsDead() { WhaleyRunRecorder.shared.completeRun() }
        publishEmbeddedFrame(state: state, events: events)
        guard clockScrub == nil else { return }
        let live = SceneGameTime.seconds(WhaleySrcGameTime())
        gameClock.text = live.clockText
        gameClock.accessibilityValue = live.clockText
    }

    private func consumeGameEvents() -> [WhaleyEmbeddedEvent] {
        var outcomes: [WhaleyEmbeddedEvent] = []
        for event in WhaleySrcDrainGameEvents() {
            let kind = event["kind"] as? String
            let level = (event["level"] as? NSNumber)?.intValue ?? WhaleySrcCurrentLevelNumber()
            let engineSession = event["session"] as? String
            WhaleyRunRecorder.shared.prepareForEvent(level: level, engineSession: engineSession)
            let time = (event["time"] as? NSNumber)?.doubleValue ?? WhaleySrcGameTime()
            let point = CGPoint(x: (event["x"] as? NSNumber)?.doubleValue ?? 0,
                                y: (event["y"] as? NSNumber)?.doubleValue ?? 0)
            let objectID = event["objectID"] as? String
            switch kind {
            case "bubbleContact":
                let bounced = (event["bounced"] as? NSNumber)?.boolValue ?? false
                WhaleyRunRecorder.shared.gameplay(.bubbleCollision, time: time, position: point, objectID: objectID)
                if bounced {
                    WhaleyRunRecorder.shared.gameplay(.bubbleBounce, time: time, position: point, objectID: objectID)
                }
                if let id = event["externalID"] as? String {
                    outcomes.append(.bubbleContact(id: id,
                        remainingUses: (event["remainingUses"] as? NSNumber)?.intValue ?? 0,
                        popped: (event["popped"] as? NSNumber)?.boolValue ?? false, bounced: bounced))
                }
            case "coinCollected":
                WhaleyRunRecorder.shared.gameplay(.coinCollected, time: time, position: point, objectID: objectID)
                outcomes.append(.coinCollected)
            case "died":
                let playerPoint = CGPoint(x: (event["playerX"] as? NSNumber)?.doubleValue ?? 0,
                                          y: (event["playerY"] as? NSNumber)?.doubleValue ?? 0)
                WhaleyRunRecorder.shared.sample(level: level, time: time, position: playerPoint,
                    dead: true, engineSession: engineSession)
                outcomes.append(.died)
            case "levelCompleted":
                WhaleyRunRecorder.shared.gameplay(.levelCompleted, time: time, position: point, objectID: objectID)
                WhaleyRunRecorder.shared.completeRun()
                outcomes.append(.levelCompleted)
            default:
                break
            }
        }
        return outcomes
    }

    private func publishEmbeddedFrame(state: [String: Any], events: [WhaleyEmbeddedEvent]) {
        guard let onEmbeddedFrame, let frame = makeEmbeddedFrame(state: state, events: events) else { return }
        onEmbeddedFrame(frame)
    }

    private func makeEmbeddedFrame(state: [String: Any], events: [WhaleyEmbeddedEvent]) -> WhaleyEmbeddedFrame? {
        guard let configuration = embeddedConfiguration,
              let level = (state["level"] as? NSNumber)?.intValue else { return nil }
        func value(_ key: String) -> Double { (state[key] as? NSNumber)?.doubleValue ?? 0 }
        embeddedSequence += 1
        return .init(sessionID: configuration.sessionID, sequence: embeddedSequence,
            level: level, gameTime: value("gameTime"), layerX: value("layerX"), layerY: value("layerY"),
            playerX: value("playerX"), playerY: value("playerY"),
            playerWidth: value("playerWidth"), playerHeight: value("playerHeight"),
            dead: (state["dead"] as? NSNumber)?.boolValue ?? false,
            completed: (state["completed"] as? NSNumber)?.boolValue ?? false, events: events)
    }

    func updateTemporalDiagnostics(_ preview: SceneGameTime, projected: Bool) {
        let count = WhaleySrcPlayerHistorySampleCount()
        guard count > 0 else {
            gameClock.text = "\(preview.clockText)\nWhaley: no history\nprojection: unavailable"
            return
        }
        let first = SceneGameTime.seconds(WhaleySrcPlayerHistoryFirstTime()).clockText
        let last = SceneGameTime.seconds(WhaleySrcPlayerHistoryLastTime()).clockText
        gameClock.text =
            "\(preview.clockText)\nWhaley: \(count) samples\n\(first) … \(last)\n\(projected ? "projected" : "projection failed")"
    }

    @objc func scrubClock(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            guard designerEnabled, objectScrub == nil,
                  WhaleySrcCurrentLevelNumber() > 0 else { return }
            let live = SceneGameTime.seconds(WhaleySrcGameTime())
            clockScrub = SceneTimeScrubSession(liveTime: live)
            clockOriginX = location.x
            gameClock.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
            gameClock.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
            WhaleySrcBeginTimeProjection()
            WhaleySrcSetSceneScrubPaused(true)
            updateTemporalDiagnostics(live, projected: WhaleySrcProjectTime(live.seconds))
            setNeedsLayout()
        case .changed:
            guard designerEnabled, var scrub = clockScrub else { return }
            scrub.update(horizontal: Double(location.x - clockOriginX))
            clockScrub = scrub
            let projected = WhaleySrcProjectTime(scrub.previewTime.seconds)
            updateTemporalDiagnostics(scrub.previewTime, projected: projected)
        case .ended, .cancelled, .failed:
            endClockScrub()
        default:
            break
        }
    }
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Classify BEFORE forwarding to SpriteKit: QUIT can replace the entire
        // game scene synchronously inside WhaleyHud.touchesBegan.
        let newlyOwned = Set(touches.filter(isSpriteKitHUDTouch).map(ObjectIdentifier.init))
        hudOwnedTouches.formUnion(newlyOwned)

        // Required for SpriteKit's native userInteractionEnabled nodes.
        super.touchesBegan(touches, with: event)

        for touch in touches where !newlyOwned.contains(ObjectIdentifier(touch)) {
            if WhaleySrcCurrentLevelNumber() > 0 {
                WhaleyRunRecorder.shared.input(
                    .began, time: WhaleySrcGameTime(), point: touch.location(in: self))
            }
            _ = WhaleySrcTouchBegan(touch, event)
        }
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches where !hudOwnedTouches.contains(ObjectIdentifier(touch)) {
            if WhaleySrcCurrentLevelNumber() > 0 {
                WhaleyRunRecorder.shared.input(
                    .moved, time: WhaleySrcGameTime(), point: touch.location(in: self))
            }
            WhaleySrcTouchMoved(touch, event)
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        for touch in touches {
            if hudOwnedTouches.remove(ObjectIdentifier(touch)) != nil { continue }
            if WhaleySrcCurrentLevelNumber() > 0 {
                WhaleyRunRecorder.shared.input(
                    .ended, time: WhaleySrcGameTime(), point: touch.location(in: self))
            }
            WhaleySrcTouchEnded(touch, event)
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        for touch in touches {
            if hudOwnedTouches.remove(ObjectIdentifier(touch)) != nil { continue }
            if WhaleySrcCurrentLevelNumber() > 0 {
                WhaleyRunRecorder.shared.input(
                    .cancelled, time: WhaleySrcGameTime(), point: touch.location(in: self))
            }
            WhaleySrcTouchCancelled(touch, event)
        }
    }
}

extension SrcWhaleySKView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === clockLongPress {
            return designerEnabled && objectScrub == nil && WhaleySrcCurrentLevelNumber() > 0
        }
        guard gestureRecognizer === objectLongPress else { return true }
        guard designerEnabled, clockScrub == nil else { return false }
        if touch.view === gameClock { return false }
        // Long-press scene scrubbing must not delay or steal a pause HUD tap.
        if isSpriteKitHUDTouch(touch) { return false }
        // A held painting in the main menu must reach the original menu's
        // one-second full-screen preview instead of activating object scrubbing.
        guard WhaleySrcCurrentLevelNumber() > 0 else { return false }
        if WhaleySrcHitBubble(touch.location(in: self)) { return false }
        return WhaleySrcSceneScrubCanAcquire(touch.location(in: self))
    }
}

final class WhaleyScrubCalloutView: UIView {
    let label = UILabel()
    let bubbleLayer = CAShapeLayer()
    let tailLayer = CAShapeLayer()
    var text: String {
        get { label.text ?? "" }
        set { label.text = newValue }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(tailLayer)
        layer.addSublayer(bubbleLayer)
        label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
        bubbleLayer.fillColor = UIColor.black.withAlphaComponent(0.78).cgColor
        tailLayer.fillColor = UIColor.black.withAlphaComponent(0.78).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(placement: SceneScrubHUDPlacement, in viewport: CGRect) {
        let rect = placement.frame(in: viewport)
        frame = rect.insetBy(dx: -10, dy: -10)
        let bubbleFrame = rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        bubbleLayer.path = UIBezierPath(roundedRect: bubbleFrame, cornerRadius: 12).cgPath
        label.frame = bubbleFrame.insetBy(dx: 10, dy: 4)
        let anchor = CGPoint(x: placement.anchor.x - frame.minX,
                             y: placement.anchor.y - frame.minY)
        let x = min(max(anchor.x, bubbleFrame.minX + 18), bubbleFrame.maxX - 18)
        let y = placement.side == .above ? bubbleFrame.maxY - 1 : bubbleFrame.minY + 1
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: x - 9, y: y))
        tail.addLine(to: CGPoint(x: x + 9, y: y))
        tail.addLine(to: anchor)
        tail.close()
        tailLayer.path = tail.cgPath
    }
}

final class AdjustableClockLabel: UILabel {}

#endif
