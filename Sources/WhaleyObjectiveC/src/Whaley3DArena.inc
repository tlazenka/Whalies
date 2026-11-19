/* Included only by WhaleyScene.m. Keep the shared 2010 source's integration
 * explicit: no method swizzling, no second simulation and no TMX mutation. */
#import <objc/runtime.h>
#import "../include/WhaleyArenaRules.h"
#include <limits.h>

static char WhaleyArenaStateKey;
static char WhaleyFoundationKey;

@interface WhaleyArenaSession : NSObject
@property(nonatomic, retain) NSArray *suspendedProjectiles;
@property(nonatomic, retain) NSArray *projectileVisibility;
@property(nonatomic) BOOL tileMapWasVisible;
@property(nonatomic) BOOL goalWasVisible;
@property(nonatomic) CGPoint entryPosition;
@end
@implementation WhaleyArenaSession
- (void)dealloc {
    self.suspendedProjectiles = nil;
    self.projectileVisibility = nil;
    [super dealloc];
}
@end

BOOL WhaleySceneIs3DFoundation(Projectile *p) {
    return p && [objc_getAssociatedObject(p, &WhaleyFoundationKey) boolValue];
}

static BOOL Whaley3DIsFoundation(Projectile *p) {
    return WhaleySceneIs3DFoundation(p);
}

static NSUInteger Whaley3DShotCount(Whaley *game) {
    NSUInteger count = 0;
    for (Projectile *p in game.projectiles) {
        if (!Whaley3DIsFoundation(p)) ++count;
    }
    return count;
}

static WhaleyArenaLayout Whaley3DLayout(Whaley *game) {
    CGSize map = game.tileMap.mapSize;
    // Check floating-point dimensions before conversion to an unsigned integer.
    if (!isfinite(map.width) || !isfinite(map.height) || map.width < 3 ||
        map.height < 4 || map.width > INT_MAX || map.height > INT_MAX) {
        return (WhaleyArenaLayout){0};
    }
    return WhaleyArenaMakeLayout((size_t)map.width, (size_t)map.height,
        game.tileMap.tileSize.width, game.tileMap.tileSize.height);
}

/* Called synchronously on mode changes and before gameplay updates. The scene
 * owns this session through its associated object; the session does not retain
 * the scene, so it cannot introduce a scene/session ownership cycle. */
void WhaleySceneApply3DEnvironment(Whaley *game) {
    if (!game || !game.player || !game.projectiles) return;
    NSCAssert([NSThread isMainThread], @"Arena changes require the game thread");
    WhaleyArenaSession *session = objc_getAssociatedObject(game, &WhaleyArenaStateKey);
    if (WhaleyScene3DModeEnabled && !session) {
        WhaleyArenaLayout a = Whaley3DLayout(game);
        if (!a.valid) return;
        session = [[[WhaleyArenaSession alloc] init] autorelease];
        session.suspendedProjectiles = [[game.projectiles copy] autorelease];
        NSMutableArray *visibility = [NSMutableArray array];
        for (Projectile *p in session.suspendedProjectiles) {
            [visibility addObject:@(p.visible)];
            /* Stop, rather than replay, callbacks belonging to suspended 2D shots. */
            [p stopAllActions];
            p.isBeingMoved = NO;
            p.isFrozen = YES;
            p.visible = NO;
        }
        session.projectileVisibility = visibility;
        session.tileMapWasVisible = game.tileMap.visible;
        session.goalWasVisible = game.goal.visible;
        session.entryPosition = game.player.position;
        objc_setAssociatedObject(game, &WhaleyArenaStateKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [game.projectiles removeAllObjects];
        game.tileMap.visible = NO;
        game.goal.visible = NO;

        for (size_t i = 0; i < a.bubbleCount; i++) {
            Projectile *bubble = [Projectile initWithFile:@"infinite_bubble.png"
                withIsFrozen:YES withSizeMode:SmallSize withIsBeingMoved:NO withBouncesLeft:-1];
            objc_setAssociatedObject(bubble, &WhaleyFoundationKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            bubble.sizeMode = (2 * a.bubbleRadius) / MAX(1, bubble.contentSize.width);
            bubble.position = ccp(WhaleyArenaBubbleX(a, i), a.bottom + a.bubbleRadius);
            [game addChild:bubble z:4];
            [game.projectiles addObject:bubble];
        }
        /* Preserve entry height when possible, but stay within the perimeter
         * and above the bubble row. No relocation to an unrelated checkpoint. */
        CGPoint p = game.player.position;
        CGFloat maxX = MAX(a.left, a.right - game.player.scaledWidth);
        CGFloat maxY = MAX(a.bottom, a.top - game.player.scaledHeight);
        CGFloat minY = MIN(maxY, a.bottom + 2 * a.bubbleRadius + 1);
        p.x = MAX(a.left, MIN(maxX, p.x));
        p.y = MAX(minY, MIN(maxY, p.y));
        game.player.position = p;
        game.player.airMode = FALLING;
        game.player.yAdd = SlowYspd;
        WhaleyScene3DPlaceAtAnchor = NO;
        WhaleyScene3DJumpSequence = 0;
        WhaleyScene3DJumpAnchorBottom = CGPointMake([Helpers spriteCenter:game.player].x, p.y);
    } else if (!WhaleyScene3DModeEnabled && session) {
        /* Teardown bypasses removeProjectile's permanent-foundation guard. */
        for (Projectile *p in [[game.projectiles copy] autorelease]) {
            [game removeChild:p cleanup:YES];
        }
        [game.projectiles removeAllObjects];
        NSUInteger i = 0;
        for (Projectile *p in session.suspendedProjectiles) {
            p.visible = [session.projectileVisibility[i++] boolValue];
            [game.projectiles addObject:p];
        }
        game.tileMap.visible = session.tileMapWasVisible;
        game.goal.visible = session.goalWasVisible;
        /* Returning to an interior-platform level must not embed Whaley in a wall. */
        if (!game.player.isDead && !game.player.hasWon) {
            game.player.position = session.entryPosition;
            game.player.desiredPos = [Helpers spriteCenter:game.player];
            game.player.isMovingLaterally = NO;
            game.player.airMode = FALLING;
            game.player.yAdd = SlowYspd;
            game.player.groundYpos = game.player.position.y;
        }
        WhaleyScene3DPlaceAtAnchor = NO;
        WhaleyScene3DJumpSequence = 0;
        WhaleyScene3DJumpAnchorBottom = CGPointZero;
        objc_setAssociatedObject(game, &WhaleyArenaStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
