#ifndef WHALEY_SCENE_LIFECYCLE_H
#define WHALEY_SCENE_LIFECYCLE_H
#if __has_include(<UIKit/UIKit.h>)
#import <SpriteKit/SpriteKit.h>

/// Call before replacing a game subtree. Stops its callbacks and sound sources
/// without waiting for deallocation (actions may still retain the old level).
FOUNDATION_EXPORT void WhaleyStopSceneSchedules(SKNode *root);

/// Covers transitions that have already removed a subtree, including direct
/// main-menu installation. Safe to call repeatedly on the main thread.
FOUNDATION_EXPORT void WhaleyStopDetachedSchedules(void);
#endif
#endif
