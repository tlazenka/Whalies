#if canImport(UIKit) && canImport(SpriteKit)
import SwiftUI
import UIKit
import WhaleyCore

/// Presents the canonical native Whaley scene inside a containing application's
/// surface. Its host can project this view into 3D without a second game renderer.
/// Stadium retains control of its gestures and submits external projectile poses;
/// the native game alone produces collisions, deaths, coins and level completions.
@MainActor
public struct WhaleyEmbeddedGameView: UIViewRepresentable {
    public let configuration: WhaleyEmbeddedConfiguration
    public let isActive: Bool
    public let bubbles: [WhaleyEmbeddedBubble]
    public let onFrame: @MainActor (WhaleyEmbeddedFrame) -> Void

    public init(configuration: WhaleyEmbeddedConfiguration, isActive: Bool,
                bubbles: [WhaleyEmbeddedBubble],
                onFrame: @escaping @MainActor (WhaleyEmbeddedFrame) -> Void) {
        self.configuration = configuration
        self.isActive = isActive
        self.bubbles = bubbles
        self.onFrame = onFrame
    }

    public func makeUIView(context: Context) -> SrcWhaleySKView {
        let view = SrcWhaleySKView(frame: .zero)
        configure(view)
        return view
    }

    public func updateUIView(_ uiView: SrcWhaleySKView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: SrcWhaleySKView) {
        view.setHostActive(isActive)
        view.startNativeSession(configuration: configuration)
        view.embeddedBubbles = bubbles
        view.onEmbeddedFrame = onFrame
    }

    public static func dismantleUIView(_ uiView: SrcWhaleySKView, coordinator: ()) {
        uiView.stopNativeSession()
    }
}
#endif
