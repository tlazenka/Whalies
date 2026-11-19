#if canImport(UIKit)
import Foundation
import SwiftUI

/// Plain identity state, deliberately separate from SwiftUI's observed rendering
/// state. Replacing a scene host invalidates callbacks queued by its predecessor.
@MainActor
final class StadiumSceneReadiness {
    private var current: UUID?

    func begin() -> UUID {
        let token = UUID()
        current = token
        return token
    }

    func finish(_ token: UUID) -> Bool {
        guard current == token else { return false }
        current = nil
        return true
    }

    func cancel(_ token: UUID) {
        if current == token { current = nil }
    }
}

/// The launch storyboard uses the same fixed sRGB #0072CE. No scene textures,
/// Metal pipeline, render callback or image readback participates in this cover.
struct StadiumSplash: View {
    static let blue = Color(.sRGB, red: 0, green: 114.0 / 255.0, blue: 206.0 / 255.0, opacity: 1)

    let isReady: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var finished = false

    var body: some View {
        Group {
            if !finished {
                EvaporatingPools(progress: progress)
                    .fill(Self.blue)
                    .ignoresSafeArea()
                    .accessibilityLabel("Loading WhaleKart")
                    .accessibilityHidden(isReady)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isReady, initial: true) { _, ready in
            if ready { reveal() }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced && isReady { removeImmediately() }
        }
    }

    private func reveal() {
        guard !finished else { return }
        if reduceMotion {
            removeImmediately()
        } else {
            // Only the decorative evaporation has a duration. Loading has no
            // guessed delay, and input is already available beneath these pools.
            withAnimation(.easeInOut(duration: 1.15), completionCriteria: .logicallyComplete) {
                progress = 1
            } completion: {
                finished = true
            }
        }
    }

    private func removeImmediately() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            progress = 1
            finished = true
        }
    }
}

private struct EvaporatingPools: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0, progress < 1 else { return Path() }
        guard progress > 0 else { return Path(rect) }
        let columns = rect.width > rect.height ? 8 : 5
        let rows = rect.width > rect.height ? 5 : 8
        let width = rect.width / CGFloat(columns)
        let height = rect.height / CGFloat(rows)
        var pools = Path()
        for row in 0..<rows {
            for column in 0..<columns {
                // Stable variation avoids random changes during body updates.
                let seed = (row * 17 + column * 31) % 23
                let variation = CGFloat(seed) / 22
                let delay = variation * 0.28
                let local = min(1, max(0, (progress - delay) / (1 - delay)))
                let remaining = (1 - local) * (1 - local)
                guard remaining > 0 else { continue }
                let x = rect.minX + (CGFloat(column) + 0.5 + (variation - 0.5) * 0.2) * width
                let y = rect.minY + (CGFloat(row) + 0.5 + (CGFloat(seed % 5) / 4 - 0.5) * 0.2) * height
                // Overlapping ovals initially cover every cell, then separate
                // into differently sized patches and shrink to nothing.
                let rx = width * (1 + variation * 0.18) * remaining
                let ry = height * (1.12 - variation * 0.12) * remaining
                pools.addEllipse(in: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
            }
        }
        return pools
    }
}
#endif
