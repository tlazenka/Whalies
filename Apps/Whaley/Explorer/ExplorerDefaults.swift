import Foundation
import ScopedUserDefaults

@Defaults
struct WhaleyDebugDefaults {
    /// Enables feedback on long presses that do not acquire a scene object.
    /// Off by default, including for existing installations.
    @DefaultKey("whaley.debug.showEmptySceneScrubFeedback")
    @Registered(false) var showEmptySceneScrubFeedback: Bool
    @DefaultKey("whaley.debug.invincibilityEnabled")
    @Registered(false) var invincibilityEnabled: Bool
}
