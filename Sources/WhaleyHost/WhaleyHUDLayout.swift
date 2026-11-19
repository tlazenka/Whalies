import Foundation

/// Place the original 32-point HUD at the visible scene edge, without an inset
/// that would expose gameplay between the black bar and the top of the scene.
/// Project UIKit's safe-area top into scene coordinates before calling this.
public enum WhaleyHUDLayout {
    public static let barHeight: CGFloat = 32

    public static func center(sceneSize: CGSize, projectedTop: CGPoint) -> CGPoint? {
        guard sceneSize.width.isFinite, sceneSize.height.isFinite,
              sceneSize.width >= barHeight, sceneSize.height >= barHeight,
              projectedTop.x.isFinite, projectedTop.y.isFinite else { return nil }
        let half = barHeight / 2
        let x = min(max(projectedTop.x, half), sceneSize.width - half)
        let top = min(max(projectedTop.y, barHeight), sceneSize.height)
        return CGPoint(x: x, y: top - half)
    }
}
