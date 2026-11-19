#ifndef WHALEY_SNAPSHOT_CAPTURE_H
#define WHALEY_SNAPSHOT_CAPTURE_H
#import "WhaleyScene.h"
#import "../include/WhaleySnapshotGeometry.h"

/* Shared by the live producer and native tests. No node ownership, game
 * mutation, animation, or inferred gameplay outcome is introduced here. */
static inline NSDictionary *WhaleySnapshotGeometryDictionary(GameObject *object,
                                                             CGSize tile,
                                                             BOOL bottomLeftOrigin) {
    if (!object) return nil;
    WhaleySnapshotGeometry g = WhaleyMakeSnapshotGeometry(object.position.x,
        object.position.y, object.scaledWidth, object.scaledHeight,
        tile.width, tile.height, bottomLeftOrigin);
    if (!g.valid) return nil;
    return @{@"x": @(g.x), @"y": @(g.y),
        @"dimensions": @{@"width": @(g.width), @"height": @(g.height)}};
}

static inline NSDictionary *WhaleySnapshotLiveEntity(GameObject *object,
    NSString *kind, NSString *identifier, CGSize tile, BOOL mode3D) {
    NSDictionary *geometry = WhaleySnapshotGeometryDictionary(object, tile, NO);
    if (!geometry || !kind.length || !identifier.length) return nil;
    NSMutableDictionary *entity = [[geometry mutableCopy] autorelease];
    entity[@"id"] = identifier;
    entity[@"kind"] = kind;
    if (mode3D && [kind isEqualToString:@"bubble"] &&
        [object isKindOfClass:[Projectile class]]) {
        // Pre-existing 2D projectiles are suspended on arena entry, so every
        // active non-foundation projectile in 3D came from player input.
        entity[@"bubbleRole"] = WhaleySceneIs3DFoundation((Projectile *)object)
            ? @"foundation" : @"playerCreated";
    }
    return entity;
}
#endif
