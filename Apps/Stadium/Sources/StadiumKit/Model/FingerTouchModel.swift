import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import StadiumGame

@MainActor
final class FingerTouchModel {
    unowned let session: StadiumSession
    private(set) var touch: Int?

    init(session: StadiumSession) { self.session = session }

    // Defer reset until after layout to avoid mutating session state during a view update.
    func resized(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let s = SIMD2(Float(size.width), Float(size.height))
        guard s != session.viewSize else { return }
        DispatchQueue.main.async { [session] in session.viewResized(s) }
    }

    func began(_ id: Int, at p: CGPoint) {
        guard touch == nil, session.fingerBegan(at: p) else { return }
        touch = id
    }

    func moved(_ id: Int, to p: CGPoint) {
        guard id == touch else { return }
        session.fingerMoved(to: p)
    }

    func ended(_ id: Int, at p: CGPoint) {
        guard id == touch else { return }
        touch = nil
        session.fingerEnded(at: p)
    }

    func cancelled(_ id: Int) {
        guard id == touch else { return }
        touch = nil
        session.fingerCancelled()
    }
}
