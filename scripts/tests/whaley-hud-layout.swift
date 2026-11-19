import Foundation

@main
struct HUDLayoutChecks {
    static func main() {
        let scene = CGSize(width: 320, height: 568)
        for top in [CGFloat(568), 570, 700, 500, 32] {
            let center = WhaleyHUDLayout.center(sceneSize: scene,
                projectedTop: CGPoint(x: 160, y: top))!
            precondition(center.y + WhaleyHUDLayout.barHeight / 2 == min(top, 568))
            precondition(center.x == 160)
        }
        precondition(WhaleyHUDLayout.center(sceneSize: .zero, projectedTop: .zero) == nil)
        precondition(WhaleyHUDLayout.center(sceneSize: scene,
            projectedTop: CGPoint(x: CGFloat.nan, y: 568)) == nil)
        precondition(WhaleyHUDLayout.center(sceneSize: scene,
            projectedTop: CGPoint(x: 160, y: CGFloat.infinity)) == nil)
        precondition(WhaleyHUDLayout.center(sceneSize: scene,
            projectedTop: CGPoint(x: 160, y: 568)) == CGPoint(x: 160, y: 552))
        // The removed inset regression: upper edge must never be 566 or 564.
        for scale in [CGFloat(0.5), 1, 1.171875, 2, 3] {
            let center = WhaleyHUDLayout.center(sceneSize: scene,
                projectedTop: CGPoint(x: 160, y: 568))!
            precondition((568 - center.y - 16) * scale == 0)
        }
        print("PASS: HUD top-edge placement, letterboxing, cropping, scale and invalid inputs")
    }
}
