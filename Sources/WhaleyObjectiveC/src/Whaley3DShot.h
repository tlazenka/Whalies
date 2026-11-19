#ifndef WHALEY_3D_SHOT_H
#define WHALEY_3D_SHOT_H
#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyScene.h"
#import "Constants.h"
#import "../include/Whaley3DShotPlacement.h"
#include <limits.h>

/* Use the original scene's limits and layer order. This is a native spawn
 * operation, not an action interpreter or another simulation. */
FOUNDATION_EXPORT const NSInteger MAX_BUBBLES;
FOUNDATION_EXPORT const NSInteger BubbleZorder;

static inline Projectile *WhaleyCreate3DShot(Whaley *game, int side) {
    NSCAssert([NSThread isMainThread], @"3D shots require the game thread");
    if (!WhaleyScene3DModeEnabled || !game || !game.player || !game.level ||
        !game.projectiles || game.isPaused || game.player.isDead ||
        game.player.hasWon || game.bubbleFileName.length == 0 || side < -1 || side > 1) return nil;
    WhaleySceneApply3DEnvironment(game);
    CGSize map = game.tileMap.mapSize, tile = game.tileMap.tileSize;
    if (!isfinite(map.width) || !isfinite(map.height) || map.width < 3 ||
        map.height < 4 || map.width > INT_MAX || map.height > INT_MAX) return nil;
    WhaleyArenaLayout arena = WhaleyArenaMakeLayout((size_t)map.width,
        (size_t)map.height, tile.width, tile.height);
    if (!arena.valid) return nil;
    Projectile *shot = [Projectile initWithFile:game.bubbleFileName
        withIsFrozen:YES withSizeMode:SmallSize withIsBeingMoved:NO withBouncesLeft:1];
    if (!shot) return nil;
    CGPoint bottom = CGPointMake([Helpers spriteCenter:game.player].x, game.player.position.y);
    BOOL anchored = game.player.airMode != GROUNDED && WhaleyScene3DJumpSequence > 0;
    Whaley3DShotPlacement placement = Whaley3DPlanShot(arena, bottom.x, bottom.y,
        game.player.scaledWidth, anchored, WhaleyScene3DJumpAnchorBottom.x,
        WhaleyScene3DJumpAnchorBottom.y, shot.scaledWidth / 2, shot.scaledHeight / 2, side);
    if (!placement.valid) return nil;
    shot.sizeMode = SmallSize * placement.scale;
    shot.position = CGPointMake(placement.x, placement.y);
    shot.color = Purple;

    NSUInteger count = 0;
    for (Projectile *p in game.projectiles) if (!WhaleySceneIs3DFoundation(p)) ++count;
    if (count >= (NSUInteger)MAX_BUBBLES) {
        for (Projectile *old in [[game.projectiles copy] autorelease]) {
            if (WhaleySceneIs3DFoundation(old)) continue;
            [old stopAllActions];
            [game removeChild:old cleanup:YES];
            [game.projectiles removeObjectIdenticalTo:old];
            break;
        }
    }
    /* Immediate authoritative placement: no synthetic touches, callback-owned
     * flight action, or rendered-camera coordinates. The next real gameLoop:
     * decides whether contact launches Whaley and consumes this bubble. */
    [game addChild:shot z:BubbleZorder];
    [game.projectiles addObject:shot];
    game.level.bubblesUsed++;
    if (side != 0) game.player.flipX = side > 0;
    return shot;
}
#endif
#endif
