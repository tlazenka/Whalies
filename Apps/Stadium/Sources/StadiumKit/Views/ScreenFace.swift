#if canImport(UIKit)
import SwiftUI
#if canImport(QuartzCore)
import QuartzCore
#endif

// Project a persistent SwiftUI view over the scene; scene geometry cannot occlude it.
// Hide invalid projections with opacity to preserve the embedded view's state.
struct ScreenFace<Content: View>: View {
    let corners: [CGPoint]?
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        let h = corners.flatMap { Homography(width: Double(size.width), height: Double(size.height), to: $0) }
        content()
            .frame(width: size.width, height: size.height)
            #if canImport(QuartzCore)
            .projectionEffect(ProjectionTransform(h?.transform ?? CATransform3DIdentity))
            #endif
            .opacity(h == nil ? 0 : 1)
            // A maximum-only frame can inherit the content width and shift the level's layout.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}
#endif
