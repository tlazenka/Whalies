import SwiftUI
import StadiumKit

@main
struct StadiumApp: App {
    @UIApplicationDelegateAdaptor(StadiumAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            StadiumRootView()
        }
    }
}
