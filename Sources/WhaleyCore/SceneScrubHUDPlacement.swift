import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A placement captured at gesture acquisition. Neither the moving finger nor
/// the edited object's later position can change this value.
public struct SceneScrubHUDPlacement: Equatable, Sendable {
    public enum Side: Equatable, Sendable { case above, below }
    public let frame: CGRect
    public let anchor: CGPoint
    public let side: Side

    // Scalar equality avoids relying on imported geometry conformances.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.side == rhs.side &&
        lhs.frame.origin.x == rhs.frame.origin.x &&
        lhs.frame.origin.y == rhs.frame.origin.y &&
        lhs.frame.size.width == rhs.frame.size.width &&
        lhs.frame.size.height == rhs.frame.size.height &&
        lhs.anchor.x == rhs.anchor.x &&
        lhs.anchor.y == rhs.anchor.y
    }

    public init(
        originalTarget: CGRect,
        initialTouch: CGPoint,
        viewport: CGRect,
        size: CGSize = CGSize(width: 196, height: 44),
        clearance: CGFloat = 60,
        edgeInset: CGFloat = 8
    ) {
        let allowed = Self.allowedRect(viewport, inset: edgeInset)
        let width = min(max(0, size.width), allowed.size.width)
        let height = min(max(0, size.height), allowed.size.height)
        let target = originalTarget.isNull || originalTarget.isInfinite
            ? CGRect(origin: initialTouch, size: .zero) : originalTarget.standardized
        let gap = max(0, clearance)
        let top = min(target.minY, initialTouch.y) - gap - height
        let above = top >= allowed.minY
        side = above ? .above : .below
        anchor = CGPoint(x: target.midX, y: above ? target.minY : target.maxY)
        let requestedY = above ? top : max(target.maxY, initialTouch.y) + gap
        frame = Self.clamp(
            CGRect(x: target.midX - width / 2, y: requestedY, width: width, height: height),
            to: allowed
        )
    }

    /// Only an actual viewport/safe-area change may move the frozen frame.
    /// This method intentionally accepts no current pointer or target position.
    public func frame(in viewport: CGRect, edgeInset: CGFloat = 8) -> CGRect {
        Self.clamp(frame, to: Self.allowedRect(viewport, inset: edgeInset))
    }

    private static func allowedRect(_ rect: CGRect, inset: CGFloat) -> CGRect {
        guard !rect.isNull, !rect.isInfinite, rect.size.width > 0, rect.size.height > 0 else {
            return .zero
        }
        let dx = min(max(0, inset), rect.size.width / 2)
        let dy = min(max(0, inset), rect.size.height / 2)
        return rect.insetBy(dx: dx, dy: dy)
    }

    private static func clamp(_ rect: CGRect, to allowed: CGRect) -> CGRect {
        let width = min(max(0, rect.size.width), allowed.size.width)
        let height = min(max(0, rect.size.height), allowed.size.height)
        return CGRect(
            x: min(max(rect.minX, allowed.minX), allowed.maxX - width),
            y: min(max(rect.minY, allowed.minY), allowed.maxY - height),
            width: width, height: height
        )
    }
}
