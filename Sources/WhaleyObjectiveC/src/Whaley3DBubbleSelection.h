#ifndef WHALEY_3D_BUBBLE_SELECTION_H
#define WHALEY_3D_BUBBLE_SELECTION_H
#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyScene.h"
#include <math.h>

/* Synchronous lookup on the game thread. The identity function is injected
 * only to reuse the existing snapshot identity, not to make a second ID map.
 * The returned projectile is borrowed from game.projectiles. Callers retain
 * its ID, not the projectile, and re-resolve it for subsequent growth updates. */
static inline Projectile *WhaleyFind3DGrowableBubble(
    Whaley *game, NSString *expectedSession, NSString *currentSession,
    NSString *projectileID, NSString *(^identity)(GameObject *)) {
    NSCAssert([NSThread isMainThread], @"Bubble selection requires the game thread");
    if (!WhaleyScene3DModeEnabled || !game || !game.player || game.isPaused ||
        game.player.isDead || game.player.hasWon || !expectedSession.length ||
        ![expectedSession isEqualToString:currentSession] || !projectileID.length ||
        !identity) return nil;
    for (Projectile *candidate in game.projectiles) {
        if (![identity(candidate) isEqualToString:projectileID]) continue;
        if (WhaleySceneIs3DFoundation(candidate) || candidate.parent != game ||
            !candidate.visible || !candidate.isFrozen || candidate.isBeingMoved ||
            candidate.bouncesLeft <= 0 || !isfinite(candidate.sizeMode) ||
            candidate.sizeMode <= 0 || !isfinite(candidate.scaledWidth) ||
            !isfinite(candidate.scaledHeight) || candidate.scaledWidth <= 0 ||
            candidate.scaledHeight <= 0) return nil;
        return candidate;
    }
    return nil;
}
#endif
#endif
