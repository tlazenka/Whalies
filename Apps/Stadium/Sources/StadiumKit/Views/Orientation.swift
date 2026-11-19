#if canImport(UIKit)
import SwiftUI
import UIKit

public final class StadiumAppDelegate: NSObject, UIApplicationDelegate {
    nonisolated(unsafe) static var orientations: UIInterfaceOrientationMask = .portrait

    public override init() { super.init() }

    public func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }
}

enum OrientationLock {
    @MainActor static func apply() {
        let mask: UIInterfaceOrientationMask = .portrait
        StadiumAppDelegate.orientations = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            #if targetEnvironment(macCatalyst)
            scene.sizeRestrictions?.minimumSize = CGSize(width: 420, height: 820)
            #else
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            #endif
        }
    }
}
#endif
