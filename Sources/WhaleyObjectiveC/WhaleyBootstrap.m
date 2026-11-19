#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyBootstrap.h"
static NSBundle *WhaleyConfiguredResourceBundle;
void WhaleySrcSetResourceBundle(NSBundle *bundle) {
    @synchronized([NSBundle class]) {
        if (WhaleyConfiguredResourceBundle != bundle) {
            [WhaleyConfiguredResourceBundle release];
            WhaleyConfiguredResourceBundle = [bundle retain];
        }
    }
}
NSBundle *WhaleySrcResourceBundle(void) {
    @synchronized([NSBundle class]) {
        return WhaleyConfiguredResourceBundle ?: NSBundle.mainBundle;
    }
}
BOOL WhaleySrcUsesWhalelandArt(void) {
    NSString *style = NSProcessInfo.processInfo.environment[@"WHALEY_ART_STYLE"] ?: @"whaleland";
    return [style isEqualToString:@"whaleland"];
}
NSURL *WhaleySrcResourceURL(NSString *filename) {
    if (WhaleySrcUsesWhalelandArt() &&
        [@[@"flame01.png", @"flame02.png", @"spout.png",
           @"tileset.png", @"tileset2.png", @"tileset3.png"]
            containsObject:filename]) {
        NSURL *alternate = WhaleySrcResourceURL([@"whaleland-" stringByAppendingString:filename]);
        if (alternate) return alternate;
    }
    NSString *base = filename.stringByDeletingPathExtension;
    NSString *ext = filename.pathExtension;
    NSBundle *bundle = WhaleySrcResourceBundle();
    NSURL *url = [bundle URLForResource:base withExtension:ext.length ? ext : nil];
    if (!url) {
        url = [bundle URLForResource:base withExtension:ext.length ? ext : nil subdirectory:@"Resources"];
    }
    return url;
}
SKTexture *WhaleySrcTexture(NSString *filename) {
    NSURL *url = WhaleySrcResourceURL(filename);
    UIImage *image = url ? [UIImage imageWithContentsOfFile:url.path] : nil;
    SKTexture *texture = image ? [SKTexture textureWithImage:image] : [SKTexture textureWithImageNamed:filename];
    NSString *name = filename.lastPathComponent;
    NSString *stylePrefix = @"whaleland-";
    if ([name hasPrefix:stylePrefix]) name = [name substringFromIndex:stylePrefix.length];
    if ([@[@"player.png", @"player-win.png", @"spout.png", @"flame01.png", @"flame02.png",
           @"coin.png", @"goal01.png", @"tileset.png", @"tileset2.png", @"tileset3.png",
           @"whaley-expressions.png", @"whaley-win-expressions.png"] containsObject:name]) {
        texture.filteringMode = SKTextureFilteringNearest;
    }
    return texture;
}

#import "cocos2d.h"
#import "src/Constants.h"
#import "src/GameState.h"
#import "src/Helpers.h"
#import "src/Level.h"
#import "src/MainMenu.h"
#import "src/WhaleyScene.h"
#import "src/WhaleySnapshotCapture.h"
#import "src/Whaley3DShot.h"
#import "src/Whaley3DBubbleSelection.h"
#include <limits.h>
#import "include/WhaleyArenaRules.h"
#import "src/WhaleyHud.h"
#import "src/WhaleyHostHooks.h"
#import "src/SimpleAudioEngine.h"
#import "WhaleySceneLifecycle.h"
#import <objc/runtime.h>

static Whaley *WhaleyCurrentGame = nil;
static MainMenu *WhaleyCurrentMenu = nil;
static SKScene *WhaleyCurrentHost = nil;
static BOOL WhaleyEmbeddedHost = NO;
static NSMutableDictionary<NSString *, Projectile *> *WhaleyExternalProjectiles;
static NSMutableSet<NSString *> *WhaleyConsumedExternalProjectiles;
static NSMutableArray<NSMutableDictionary<NSString *, id> *> *WhaleyObservedEvents;
static char WhaleyExternalProjectileKey;
static NSArray<NSNumber *> *WhaleySuppressedFlameIndices = nil;
static NSString *const WhaleyTileDebugOverlaysKey = @"whaley.debug.tileOverlaysEnabled";
// Retain only while an editing interaction owns the pause. The scene itself
// remains the authority for its current pause state.
static Whaley *WhaleyScrubPauseOwner = nil;
static BOOL WhaleyWasPausedBeforeScrub = NO;
// A stable ID, not an unretained pointer into the scene's projectile array.
static NSString *Whaley3DHeldIdentity = nil;
// Press-start baseline; the projectile remains the only owner of its live size.
static CGFloat Whaley3DHeldInitialScale = 0;
static void Whaley3DClearHeldBubble(void) {
    [Whaley3DHeldIdentity release];
    Whaley3DHeldIdentity = nil;
    Whaley3DHeldInitialScale = 0;
}

void WhaleySrcSetSuppressedFlames(NSArray<NSNumber *> *indices) {
    WhaleySuppressedFlameIndices = [indices copy];
    Whaley *game = WhaleyCurrentGame;
    if (!game) {
        return;
    }
    NSUInteger index = 0;
    for (Hazard *hazard in game.hazards) {
        BOOL suppressed = [WhaleySuppressedFlameIndices containsObject:@(index++)];
        hazard.visible = !suppressed;
        if (suppressed) {
            hazard.isActive = NO;
        }
    }
}

NSArray<NSValue *> *WhaleySrcFlamePositions(void) {
    NSMutableArray<NSValue *> *positions = [NSMutableArray array];
    for (Hazard *hazard in WhaleyCurrentGame.hazards) {
        [positions addObject:[NSValue valueWithCGPoint:hazard.position]];
    }
    return positions;
}

// Bind identity to the original gameplay object, not its tile position,
// array index, or pointer address. IDs cannot be reused when objects are freed
// or when a level is replayed; no extra gameplay ownership is introduced.
static char WhaleySnapshotIdentityKey;
static NSUInteger WhaleyNextSnapshotIdentity = 1;

static NSString *WhaleySnapshotIdentity(GameObject *object) {
    NSNumber *identifier = objc_getAssociatedObject(object, &WhaleySnapshotIdentityKey);
    if (!identifier) {
        identifier = @(WhaleyNextSnapshotIdentity++);
        objc_setAssociatedObject(object, &WhaleySnapshotIdentityKey,
                                 identifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return identifier.stringValue;
}

static char WhaleySnapshotSessionKey;
static NSString *WhaleySnapshotSessionIdentity(Whaley *game) {
    NSString *identifier = objc_getAssociatedObject(game, &WhaleySnapshotSessionKey);
    if (!identifier) {
        identifier = NSUUID.UUID.UUIDString;
        objc_setAssociatedObject(game, &WhaleySnapshotSessionKey,
                                 identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return identifier;
}

BOOL WhaleyHostOwnsProjectile(Projectile *projectile) {
    return objc_getAssociatedObject(projectile, &WhaleyExternalProjectileKey) != nil;
}

BOOL WhaleyHostProjectileIsFixed(Projectile *projectile) {
    NSDictionary *metadata = objc_getAssociatedObject(projectile, &WhaleyExternalProjectileKey);
    return [metadata[@"fixed"] boolValue];
}

static NSMutableDictionary *WhaleyObservedEvent(Whaley *game, NSString *kind, GameObject *object) {
    if (game != WhaleyCurrentGame) return nil;
    if (!WhaleyObservedEvents) WhaleyObservedEvents = [NSMutableArray new];
    CGPoint point = object ? object.position : game.player.position;
    NSMutableDictionary *event = [@{
        @"kind": kind, @"level": @(game.level.num),
        @"session": WhaleySnapshotSessionIdentity(game),
        @"time": @(WhaleySrcGameTime()), @"x": @(point.x), @"y": @(point.y),
        @"playerX": @(game.player.position.x), @"playerY": @(game.player.position.y)
    } mutableCopy];
    if (object) event[@"objectID"] = WhaleySnapshotIdentity(object);
    [WhaleyObservedEvents addObject:event];
    [event release];
    return event;
}

void WhaleyObserveProjectileContact(Whaley *game, Projectile *projectile, BOOL bounced) {
    NSMutableDictionary *event = WhaleyObservedEvent(game, @"bubbleContact", projectile);
    if (!event) return;
    NSDictionary *metadata = objc_getAssociatedObject(projectile, &WhaleyExternalProjectileKey);
    event[@"bounced"] = @(bounced);
    event[@"remainingUses"] = @(MAX(0, projectile.bouncesLeft));
    event[@"popped"] = @NO;
    if (metadata) event[@"externalID"] = metadata[@"id"];
}

void WhaleyObserveProjectileRemoval(Whaley *game, Projectile *projectile) {
    if (game != WhaleyCurrentGame) return;
    NSDictionary *metadata = objc_getAssociatedObject(projectile, &WhaleyExternalProjectileKey);
    if (!metadata) return;
    NSString *identifier = metadata[@"id"];
    if (!WhaleyConsumedExternalProjectiles) WhaleyConsumedExternalProjectiles = [NSMutableSet new];
    [WhaleyConsumedExternalProjectiles addObject:identifier];
    // Contact and exhaustion in one engine tick form one delivered outcome.
    NSMutableDictionary *event = nil;
    for (NSMutableDictionary *candidate in WhaleyObservedEvents.reverseObjectEnumerator) {
        if ([candidate[@"kind"] isEqual:@"bubbleContact"] &&
            [candidate[@"externalID"] isEqual:identifier] &&
            [candidate[@"session"] isEqual:WhaleySnapshotSessionIdentity(game)] &&
            [candidate[@"time"] doubleValue] == WhaleySrcGameTime()) {
            event = candidate;
            break;
        }
    }
    if (!event) {
        WhaleyObserveProjectileContact(game, projectile, NO);
        event = WhaleyObservedEvents.lastObject;
    }
    event[@"popped"] = @YES;
    event[@"remainingUses"] = @0;
    [WhaleyExternalProjectiles removeObjectForKey:identifier];
}

void WhaleyObserveCoin(Whaley *game, Collectible *coin) {
    WhaleyObservedEvent(game, @"coinCollected", coin);
}
void WhaleyObserveDeath(Whaley *game) { WhaleyObservedEvent(game, @"died", nil); }
void WhaleyObserveGoal(Whaley *game) { WhaleyObservedEvent(game, @"levelCompleted", game.goal); }

NSArray<NSDictionary<NSString *, id> *> *WhaleySrcDrainGameEvents(void) {
    NSCAssert([NSThread isMainThread], @"Game observation requires the main thread");
    NSArray *result = [[WhaleyObservedEvents copy] autorelease] ?: @[];
    [WhaleyObservedEvents removeAllObjects];
    return result;
}

NSDictionary<NSString *, id> *WhaleySrcHostState(void) {
    NSCAssert([NSThread isMainThread], @"Game observation requires the main thread");
    Whaley *game = WhaleyCurrentGame;
    if (!game) return @{};
    return @{@"session": WhaleySnapshotSessionIdentity(game),
        @"level": @(game.level.num), @"gameTime": @(WhaleySrcGameTime()),
        @"layerX": @(game.position.x), @"layerY": @(game.position.y),
        @"playerX": @(game.player.position.x), @"playerY": @(game.player.position.y),
        @"playerWidth": @(game.player.scaledWidth), @"playerHeight": @(game.player.scaledHeight),
        @"dead": @(game.player.isDead), @"completed": @(game.player.hasWon)};
}

void WhaleySrcSetExternalProjectiles(NSArray<NSDictionary<NSString *, id> *> *inputs) {
    NSCAssert([NSThread isMainThread], @"External projectiles require the main thread");
    Whaley *game = WhaleyCurrentGame;
    if (!WhaleyEmbeddedHost || !game || game.player.hasWon) return;
    if (!WhaleyExternalProjectiles) WhaleyExternalProjectiles = [NSMutableDictionary new];
    NSMutableSet *present = [NSMutableSet set];
    for (NSDictionary *input in inputs) {
        NSString *identifier = input[@"id"];
        if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) continue;
        BOOL numeric = YES;
        for (NSString *key in @[@"x", @"y", @"diameter", @"remainingUses"]) {
            if (![input[key] isKindOfClass:NSNumber.class]) { numeric = NO; break; }
        }
        if (!numeric) continue;
        double x = [input[@"x"] doubleValue], y = [input[@"y"] doubleValue];
        double diameter = [input[@"diameter"] doubleValue];
        NSInteger uses = [input[@"remainingUses"] integerValue];
        BOOL fixed = [input[@"fixed"] boolValue];
        if (!isfinite(x) || !isfinite(y) || !isfinite(diameter) || diameter <= 0 || uses < 0) continue;
        [present addObject:identifier];
        if (!fixed && uses == 0) {
            // Consumption by the containing world withdraws the proxy without
            // fabricating another native collision or reward.
            Projectile *old = WhaleyExternalProjectiles[identifier];
            if (old) {
                [game.projectiles removeObjectIdenticalTo:old];
                [old removeFromParent];
                [WhaleyExternalProjectiles removeObjectForKey:identifier];
            }
            continue;
        }
        // A stale view update cannot resurrect a bubble consumed by the engine.
        if ([WhaleyConsumedExternalProjectiles containsObject:identifier]) continue;
        Projectile *projectile = WhaleyExternalProjectiles[identifier];
        if (!projectile || [game.projectiles indexOfObjectIdenticalTo:projectile] == NSNotFound) {
            projectile = [Projectile initDefaults];
            if (!projectile) continue;
            projectile.bouncesLeft = uses;
            projectile.visible = NO;
            [game addChild:projectile];
            [game.projectiles addObject:projectile];
            WhaleyExternalProjectiles[identifier] = projectile;
        } else {
            // The native engine owns consumption until the caller acknowledges it.
            projectile.bouncesLeft = MIN(projectile.bouncesLeft, uses);
        }
        objc_setAssociatedObject(projectile, &WhaleyExternalProjectileKey,
            @{@"id": identifier, @"fixed": @(fixed)}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        projectile.position = [game convertPoint:CGPointMake(x, y) fromNode:WhaleyCurrentHost];
        projectile.scaleX = diameter / MAX(projectile.contentSize.width, 1);
        projectile.scaleY = diameter / MAX(projectile.contentSize.height, 1);
        projectile.isFrozen = YES;
        projectile.isBeingMoved = [input[@"held"] boolValue];
    }
    for (NSString *identifier in [[WhaleyExternalProjectiles.allKeys copy] autorelease]) {
        if (![present containsObject:identifier]) {
            Projectile *projectile = WhaleyExternalProjectiles[identifier];
            [game.projectiles removeObjectIdenticalTo:projectile];
            [projectile removeFromParent];
            [WhaleyExternalProjectiles removeObjectForKey:identifier];
        }
    }
    [WhaleyConsumedExternalProjectiles intersectSet:present];
}

NSDictionary<NSString *, id> *WhaleySrcSceneSnapshotElements(void) {
    NSCAssert([NSThread isMainThread], @"Snapshot capture requires the game thread");
    Whaley *game = WhaleyCurrentGame;
    if (!game || !game.tileMap || !game.meta) {
        return @{@"elements" : @[]};
    }
    WhaleySceneApply3DEnvironment(game);
    CGSize tile = game.tileMap.tileSize;
    CGSize map = game.tileMap.mapSize;
    if (!isfinite(map.width) || !isfinite(map.height) || map.width < 1 || map.height < 1 ||
        map.width > INT_MAX || map.height > INT_MAX) return @{@"elements": @[]};
    NSDictionary *playerGeometry = WhaleySnapshotGeometryDictionary(game.player, tile, YES);
    if (!playerGeometry) return @{@"elements": @[]};
    NSInteger width = (NSInteger)map.width, height = (NSInteger)map.height;
    CGPoint player = WhaleySrcPlayerPosition();
    double px = player.x / tile.width, py = player.y / tile.height;
    if (!isfinite(px) || !isfinite(py) || fabs(px) > INT_MAX / 2 || fabs(py) > INT_MAX / 2)
        return @{@"elements": @[]};
    NSInteger cx = (NSInteger)floor(px), cy = (NSInteger)floor(py);
    NSMutableArray *elements = [NSMutableArray array];
    NSMutableArray *liveEntities = [NSMutableArray array];
    NSInteger minX = MAX(0, cx - 18), maxX = MIN(width - 1, cx + 18);
    NSInteger minY = MAX(0, cy - 18), maxY = MIN(height - 1, cy + 18);
    for (NSInteger y = minY; y <= maxY; ++y) {
        for (NSInteger x = minX; x <= maxX; ++x) {
            NSInteger gid = [game.meta tileGIDAt:CGPointMake(x, height - 1 - y)];
            if (!gid && !WhaleyScene3DModeEnabled) {
                continue;
            }
            NSDictionary *properties = gid ? [game.tileMap propertiesForGID:gid] : nil;
            NSString *kind = [properties[@"IsWall"] isEqualToString:@"True"] ? @"wall" : ([properties[@"IsGround"] isEqualToString:@"True"] ? @"ground" : nil);
            if (WhaleyScene3DModeEnabled) {
                // Match the continuous collision perimeter, including authored gaps.
                kind = WhaleyArenaIsPerimeter(x, y, width, height)
                    ? (y == 0 ? @"ground" : @"wall") : nil;
            }
            if (kind) {
                [elements addObject:@{@"kind" : kind,
                                      @"x" : @(x),
                                      @"y" : @(y)}];
            }
        }
    }
    void (^addObjects)(NSArray *, NSString *) = ^(NSArray *objects, NSString *kind) {
        for (GameObject *object in objects) {
            if (!object.visible || !object.parent) {
                continue;
            }
            NSDictionary *entity = WhaleySnapshotLiveEntity(object, kind,
                WhaleySnapshotIdentity(object), tile, WhaleyScene3DModeEnabled);
            if (!entity) continue;
            // Circular objects already store their center. Adding half the size
            // would move the displayed bubble whenever it grows.
            double ex = [entity[@"x"] doubleValue], ey = [entity[@"y"] doubleValue];
            if (fabs(ex) > INT_MAX / 2 || fabs(ey) > INT_MAX / 2) continue;
            NSInteger x = (NSInteger)floor(ex), y = (NSInteger)floor(ey);
            if (labs(x - cx) <= 18 && labs(y - cy) <= 18) {
                [elements addObject:@{@"kind": kind, @"x": @(x), @"y": @(y)}];
                [liveEntities addObject:entity];
            }
        }
    };
    addObjects(game.projectiles, @"bubble");
    addObjects(game.collectibles, @"coin");
    addObjects(game.hazards, @"flame");
    if (game.goal && !WhaleyScene3DModeEnabled) {
        addObjects(@[ game.goal ], @"goal");
    }
    return @{@"elements" : elements,
             @"liveEntities" : liveEntities,
             @"playerGeometry" : playerGeometry,
             @"session" : WhaleySnapshotSessionIdentity(game),
             @"tileWidth" : @(tile.width),
             @"tileHeight" : @(tile.height)};
}

static CGPoint WhaleyLivePlayerBeforeTimeProjection;
static BOOL WhaleyHasLivePlayerBeforeTimeProjection = NO;

static Whaley *WhaleyFindGameLayer(SKNode *node) {
    if ([node isKindOfClass:[Whaley class]]) {
        return (Whaley *)node;
    }
    for (SKNode *child in node.children) {
        Whaley *found = WhaleyFindGameLayer(child);
        if (found) {
            return found;
        }
    }
    return nil;
}

static SKShapeNode *WhaleyDebugRect(CGRect rect, UIColor *color) {
    SKShapeNode *shape = [SKShapeNode shapeNodeWithRect:rect];
    shape.strokeColor = color;
    shape.lineWidth = 1.5;
    shape.fillColor = UIColor.clearColor;
    shape.zPosition = 20001;
    return shape;
}

static SKShapeNode *WhaleyDebugCircle(CGRect semanticCircle, UIColor *color) {
    CGFloat radius = semanticCircle.size.width / 2.0;
    CGRect circleBounds = CGRectMake(semanticCircle.origin.x - radius,
                                     semanticCircle.origin.y - radius,
                                     radius * 2.0, radius * 2.0);
    SKShapeNode *shape = [SKShapeNode shapeNodeWithEllipseInRect:circleBounds];
    shape.strokeColor = color;
    shape.lineWidth = 1.5;
    shape.fillColor = UIColor.clearColor;
    shape.zPosition = 20001;
    return shape;
}

static void WhaleyInstallMechanicsStatus(SKScene *host, CCScene *srcScene) {
#if DEBUG
    Whaley *game = WhaleyFindGameLayer(srcScene);
    if (!game) {
        return;
    }

    NSUInteger startingCoins = game.collectibles.count;
    NSUInteger hazardCount = game.hazards.count;

    SKLabelNode *status = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Bold"];
    status.name = @"WhaleyMechanicsStatus";
    status.fontSize = 9;
    status.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    status.verticalAlignmentMode = SKLabelVerticalAlignmentModeTop;
    status.position = CGPointMake(6, host.size.height - 20);
    status.zPosition = 30001;
    [host addChild:status];

    __block NSInteger previousCoins = -1;
    __block NSInteger previousActiveHazards = -1;
    __block BOOL previousDead = NO;
    __block BOOL previousWon = NO;
    [status runAction:[SKAction repeatActionForever:[SKAction sequence:@[
                                    [SKAction runBlock:^{
                                        NSInteger remaining = (NSInteger)game.collectibles.count;
                                        NSInteger collected = (NSInteger)startingCoins - remaining;
                                        NSInteger active = 0;
                                        for (Hazard *hazard in game.hazards) {
                                            if (hazard.isActive) {
                                                ++active;
                                            }
                                        }
                                        BOOL dead = game.player.isDead;
                                        BOOL won = game.player.hasWon;
                                        status.text = [NSString stringWithFormat:@"COINS %ld/%lu  HAZARDS %ld/%lu  GOAL %@",
                                                                                 (long)collected, (unsigned long)startingCoins,
                                                                                 (long)active, (unsigned long)hazardCount,
                                                                                 won ? @"WON" : @"READY"];

                                        if (collected != previousCoins) {
                                            [CCCompatTrace record:@"mechanic.coins" detail:[NSString stringWithFormat:@"%ld/%lu", (long)collected, (unsigned long)startingCoins]];
                                            previousCoins = collected;
                                        }
                                        if (active != previousActiveHazards) {
                                            [CCCompatTrace record:@"mechanic.hazards" detail:[NSString stringWithFormat:@"active=%ld/%lu", (long)active, (unsigned long)hazardCount]];
                                            previousActiveHazards = active;
                                        }
                                        if (dead && !previousDead) {
                                            [CCCompatTrace record:@"mechanic.hazardHit" detail:@"player.isDead = YES"];
                                        }
                                        if (won && !previousWon) {
                                            [CCCompatTrace record:@"mechanic.goal" detail:@"player.hasWon = YES"];

                                        }
                                        previousDead = dead;
                                        previousWon = won;
                                    }],
                                    [SKAction waitForDuration:1.0 / 15.0]
                                ]]]];
#endif
}

BOOL WhaleySrcTileDebugOverlaysEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:WhaleyTileDebugOverlaysKey];
}

static void WhaleyRemoveCollisionOverlay(SKScene *host) {
    for (NSString *name in @[@"//WhaleyCollisionOverlay", @"//WhaleyGeometry", @"//WhaleyCollisionLegend"]) {
        SKNode *node = [host childNodeWithName:name];
        // Stop the geometry refresh, including its captured game, before
        // removing the node. Hidden overlays must do no rendering work.
        [node removeAllActions];
        [node removeFromParent];
    }
}

static void WhaleyInstallCollisionOverlay(SKScene *host, SKNode *srcScene) {
    WhaleyRemoveCollisionOverlay(host);
    if (!WhaleySrcTileDebugOverlaysEnabled()) return;
    Whaley *game = WhaleyFindGameLayer(srcScene);
    if (!game || !game.tileMap || !game.meta) {
        [CCCompatTrace record:@"DebugOverlay.install" detail:@"missing Whaley/tileMap/meta"];
        return;
    }

    SKNode *sceneOverlay = [SKNode node];
    sceneOverlay.name = @"WhaleyCollisionOverlay";
    sceneOverlay.zPosition = 20000;
    [game addChild:sceneOverlay];

    NSUInteger occupied = 0, walls = 0, grounds = 0, other = 0;
    NSInteger width = (NSInteger)game.tileMap.mapSize.width;
    NSInteger height = (NSInteger)game.tileMap.mapSize.height;
    CGSize tileSize = game.tileMap.tileSize;
    for (NSInteger row = 0; row < height; ++row) {
        for (NSInteger col = 0; col < width; ++col) {
            NSInteger gid = [game.meta tileGIDAt:CGPointMake(col, row)];
            if (!gid) {
                continue;
            }
            ++occupied;
            NSDictionary *properties = [game.tileMap propertiesForGID:gid];
            BOOL wall = [[properties objectForKey:@"IsWall"] isEqualToString:@"True"];
            BOOL ground = [[properties objectForKey:@"IsGround"] isEqualToString:@"True"];
            UIColor *color;
            if (wall) {
                color = UIColor.systemRedColor;
                ++walls;
            } else if (ground) {
                color = UIColor.systemGreenColor;
                ++grounds;
            } else {
                color = UIColor.systemYellowColor;
                ++other;
            }
            CGRect rect = CGRectMake(col * tileSize.width,
                                     (height - 1 - row) * tileSize.height,
                                     tileSize.width, tileSize.height);
            SKShapeNode *cell = [SKShapeNode shapeNodeWithRect:rect];
            cell.strokeColor = color;
            cell.fillColor = [color colorWithAlphaComponent:0.18];
            cell.lineWidth = 0.5;
            [sceneOverlay addChild:cell];
        }
    }

    SKNode *geometry = [SKNode node];
    geometry.name = @"WhaleyGeometry";
    geometry.zPosition = 20002;
    [game addChild:geometry];
    [geometry runAction:[SKAction repeatActionForever:[SKAction sequence:@[
                                      // SpriteKit supplies the action's node. Do
                                      // not capture the node or game in its own
                                      // repeating action (a retain cycle).
                                      [SKAction customActionWithDuration:1.0 / 30.0 actionBlock:^(SKNode *geometry, CGFloat elapsedTime) {
                                          (void)elapsedTime;
                                          Whaley *game = [geometry.parent isKindOfClass:[Whaley class]]
                                              ? (Whaley *)geometry.parent : nil;
                                          [geometry removeAllChildren];
                                          if (game.player) {
                                              [geometry addChild:WhaleyDebugRect([Helpers spriteRectangle:game.player], UIColor.systemCyanColor)];
                                          }
                                          for (Projectile *bubble in game.projectiles) {
                                              if (bubble.parent) {
                                                  [geometry addChild:WhaleyDebugCircle([Helpers spriteRectangle:bubble], UIColor.systemBlueColor)];
                                              }
                                          }
                                          for (Collectible *coin in game.collectibles) {
                                              if (coin.parent) {
                                                  [geometry addChild:WhaleyDebugCircle([Helpers spriteRectangle:coin], UIColor.systemOrangeColor)];
                                              }
                                          }
                                          for (Hazard *hazard in game.hazards) {
                                              if (hazard.parent && hazard.visible) {
                                                  [geometry addChild:WhaleyDebugCircle([Helpers spriteRectangle:hazard], UIColor.systemPurpleColor)];
                                              }
                                          }
                                      }],
                                      [SKAction waitForDuration:1.0 / 30.0]
                                  ]]]];

    SKLabelNode *legend = [SKLabelNode labelNodeWithFontNamed:@"Menlo-Bold"];
    legend.name = @"WhaleyCollisionLegend";
    legend.text = [NSString stringWithFormat:@"META %lu  wall %lu  ground %lu  other %lu",
                                             (unsigned long)occupied, (unsigned long)walls,
                                             (unsigned long)grounds, (unsigned long)other];
    legend.fontSize = 9;
    legend.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    legend.verticalAlignmentMode = SKLabelVerticalAlignmentModeTop;
    legend.position = CGPointMake(6, host.size.height - 6);
    legend.zPosition = 30000;
    [host addChild:legend];

    [CCCompatTrace record:@"DebugOverlay.install"
                   detail:[NSString stringWithFormat:@"Meta occupied=%lu walls=%lu ground=%lu other=%lu",
                                                     (unsigned long)occupied, (unsigned long)walls,
                                                     (unsigned long)grounds, (unsigned long)other]];
}

void WhaleySrcSetTileDebugOverlaysEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:WhaleyTileDebugOverlaysKey];
    if (WhaleyCurrentHost) {
        WhaleyInstallCollisionOverlay(WhaleyCurrentHost, WhaleyCurrentHost);
    }
}

static void WhaleyFinishSceneInteractions(void) {
    WhaleySrcAccessibleBubbleEnd();
    WhaleySrcSceneScrubEnd();
    if (WhaleyHasLivePlayerBeforeTimeProjection) WhaleySrcRestoreLiveProjection();
    WhaleySrcSetSceneScrubPaused(NO);
}

// Recreate the historical CCTransitionTurnOffTiles without replacing the
// authoritative game scene. Each tile independently vanishes to reveal play.
static void WhaleyRevealLevelTiles(SKScene *host) {
    const CGFloat step = 32;
    NSInteger columns = (NSInteger)ceil(host.size.width / step);
    NSInteger rows = (NSInteger)ceil(host.size.height / step);
    for (NSInteger row = 0; row < rows; ++row) {
        for (NSInteger col = 0; col < columns; ++col) {
            SKShapeNode *tile = [SKShapeNode shapeNodeWithRect:
                CGRectMake(col * step, row * step, step + 0.5, step + 0.5)];
            tile.fillColor = UIColor.blackColor;
            tile.strokeColor = UIColor.clearColor;
            tile.lineWidth = 0;
            tile.zPosition = 60000;
            [host addChild:tile];
            NSTimeInterval delay = ((row * 7 + col * 13) % 43) * 0.012;
            [tile runAction:[SKAction sequence:@[
                [SKAction waitForDuration:delay],
                // Each tile is either fully present or fully removed.
                [SKAction removeFromParent]
            ]]];
        }
    }
}

static void WhaleyInstallSrcSceneInHost(SKScene *host, Level *level) {
    WhaleyFinishSceneInteractions();
    WhaleyRemoveCollisionOverlay(host);
    Whaley3DClearHeldBubble();
    WhaleyStopSceneSchedules(host);
    [WhaleyExternalProjectiles removeAllObjects];
    CCScene *srcScene = [Whaley scene:level withGameMode:level.gameMode];
    WhaleyCurrentGame = WhaleyFindGameLayer(srcScene);
    WhaleySrcSetSuppressedFlames(WhaleySuppressedFlameIndices);
    WhaleyHasLivePlayerBeforeTimeProjection = NO;
    [host removeAllChildren];
    [host addChild:srcScene];
    WhaleyCurrentHost = host;
    WhaleyCurrentMenu = nil;
    [[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:WhaleyCurrentGame priority:0 swallowsTouches:YES];
    WhaleyInstallCollisionOverlay(host, srcScene);
    WhaleyInstallMechanicsStatus(host, srcScene);
    WhaleyRevealLevelTiles(host);
}

static void WhaleyInstallMenuInHost(SKScene *host) {
    WhaleyFinishSceneInteractions();
    WhaleyRemoveCollisionOverlay(host);
    Whaley3DClearHeldBubble();
    WhaleyCurrentGame = nil;
    WhaleyHasLivePlayerBeforeTimeProjection = NO;
    WhaleySrcTrajectoryReset();
    [host removeAllChildren];
    MainMenu *menu = [MainMenu initWithLevelsAchieved];
    WhaleyCurrentMenu = menu;
    WhaleyCurrentHost = host;
    [host addChild:menu];
    [[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:menu priority:0 swallowsTouches:YES];
}

SKScene *WhaleyCreateSrcMainMenuScene(void) {
    [[SimpleAudioEngine sharedEngine] beginSoundEffectsSessionEnabled:YES];
    WhaleyEmbeddedHost = NO;
    [WhaleyExternalProjectiles removeAllObjects];
    [WhaleyConsumedExternalProjectiles removeAllObjects];
    [WhaleyObservedEvents removeAllObjects];
    CGSize logicalSize = CGSizeMake(320, 568);
    [[CCDirector sharedDirector] setCompatWinSize:logicalSize];
    SKScene *host = [SKScene sceneWithSize:logicalSize];
    host.scaleMode = SKSceneScaleModeAspectFit;
    host.anchorPoint = CGPointZero;
    host.backgroundColor = UIColor.blackColor;
    WhaleyInstallMenuInHost(host);
    return host;
}

BOOL WhaleySrcIsMainMenuVisible(void) { return WhaleyCurrentMenu != nil; }

void WhaleySrcShowMainMenu(void) {
    if (!WhaleyCurrentHost) return;
    if (WhaleyCurrentGame && WhaleyCurrentGame.level) {
        Level *level = WhaleyCurrentGame.level;
        [level.collectiblesCaptured removeAllObjects];
        level.checkpointIndex = -1;
        level.totalTime = 0;
        level.bubblesUsed = 0;
        [GameState saveGameStateToFile];
    }
    WhaleyInstallMenuInHost(WhaleyCurrentHost);
}

static Level *WhaleyPersistentLevel(NSInteger number) {
    GameState *state = [GameState gameState];
    if (number >= 1 && number <= (NSInteger)state.levels.count) {
        return [state.levels objectAtIndex:number - 1];
    }
    return [Level levelWithNum:number withGameMode:NormalBubble];
}

static void WhaleyResetLevelForFreshRun(Level *level) {
    level.checkpointIndex = -1;
    [level.collectiblesCaptured removeAllObjects];
    level.bubblesUsed = 0;
    level.totalTime = 0;
    level.totalCollectibles = 0;
}

void WhaleySrcStartLevel(NSInteger levelNumber, NSInteger mode) {
    if (!WhaleyCurrentHost || levelNumber < 1 || levelNumber > NumLevels) return;
    if (levelNumber > [GameState gameState].levelsAchieved) return;
    Level *level = WhaleyPersistentLevel(levelNumber);
    WhaleyResetLevelForFreshRun(level);
    level.gameMode = mode;
    [GameState saveGameStateToFile];
    WhaleyInstallSrcSceneInHost(WhaleyCurrentHost, level);
}

void WhaleySrcReplayCurrentLevel(void) {
    Whaley *game = WhaleyCurrentGame;
    SKScene *host = (SKScene *)game.parent.parent;
    if (!game || !host || !game.level) {
        return;
    }
    [GameState saveGameStateToFile];
    WhaleyInstallSrcSceneInHost(host, game.level);
}

void WhaleySrcAdvanceAfterWin(void) {
    Whaley *game = WhaleyCurrentGame;
    SKScene *host = (SKScene *)game.parent.parent;
    if (!game || !host || !game.level) {
        return;
    }
    GameState *state = [GameState gameState];
    NSInteger completed = game.level.num;
    WhaleyResetLevelForFreshRun(game.level);
    NSInteger next = completed + 1;
    if (completed >= NumLevels) {
        state.levelsAchieved = MAX(state.levelsAchieved, NumLevels + 1);
        next = 1;
        for (Level *level in state.levels) {
            WhaleyResetLevelForFreshRun(level);
        }
    } else {
        state.levelsAchieved = MAX(state.levelsAchieved, next);
    }
    if (completed >= NumLevels && !WhaleyEmbeddedHost) {
        [GameState saveGameStateToFile];
        WhaleyInstallMenuInHost(host);
        return;
    }
    Level *nextLevel = WhaleyPersistentLevel(next);
    WhaleyResetLevelForFreshRun(nextLevel);
    [GameState saveGameStateToFile];
    WhaleyInstallSrcSceneInHost(host, nextLevel);
}

static SKScene *WhaleyCreateLevelHost(NSInteger levelNumber, CGSize logicalSize, BOOL embedded, BOOL soundEffectsEnabled) {
    NSCAssert([NSThread isMainThread], @"Game creation requires the main thread");
    NSCAssert(levelNumber >= 1 && levelNumber <= 6, @"Original Whaley level must be 1...6");
    NSCAssert(isfinite(logicalSize.width) && isfinite(logicalSize.height) &&
              logicalSize.width >= 32 && logicalSize.height >= 32, @"Invalid Whaley viewport");
    // Set the policy before the original scene creates or plays any sound.
    [[SimpleAudioEngine sharedEngine] beginSoundEffectsSessionEnabled:soundEffectsEnabled];
    [CCCompatTrace setEnabled:YES];
    WhaleyFinishSceneInteractions();
    Whaley3DClearHeldBubble();
    WhaleyEmbeddedHost = embedded;
    WhaleyScene3DModeEnabled = NO;
    [WhaleyExternalProjectiles removeAllObjects];
    [WhaleyConsumedExternalProjectiles removeAllObjects];
    [WhaleyObservedEvents removeAllObjects];
    [[CCDirector sharedDirector] setCompatWinSize:logicalSize];

    Level *level = WhaleyPersistentLevel(levelNumber);
    if (embedded) {
        // A new containing-game session starts a fresh attempt. Death retries
        // still use WhaleySrcReplayCurrentLevel and retain that attempt's coins.
        WhaleyResetLevelForFreshRun(level);
        level.gameMode = NormalBubble;
    }
    CCScene *srcScene = [Whaley scene:level withGameMode:NormalBubble];
    WhaleyCurrentGame = WhaleyFindGameLayer(srcScene);
    WhaleySrcSetSuppressedFlames(WhaleySuppressedFlameIndices);
    WhaleyHasLivePlayerBeforeTimeProjection = NO;

    SKScene *host = [SKScene sceneWithSize:logicalSize];
    host.scaleMode = SKSceneScaleModeAspectFit;
    host.anchorPoint = CGPointZero;
    host.backgroundColor = UIColor.blackColor;
    [host addChild:srcScene];
    WhaleyCurrentHost = host;
    WhaleyCurrentMenu = nil;
    [[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:WhaleyCurrentGame priority:0 swallowsTouches:YES];
    WhaleyInstallCollisionOverlay(host, srcScene);
    WhaleyInstallMechanicsStatus(host, srcScene);
    WhaleyRevealLevelTiles(host);

    [CCCompatTrace record:@"bootstrap.original"
                   detail:[NSString stringWithFormat:@"WhaleyScene.m original level %ld", (long)levelNumber]];
    return host;
}

SKScene *WhaleyCreateSrcLevelScene(NSInteger levelNumber) {
    return WhaleyCreateLevelHost(levelNumber, CGSizeMake(320, 568), NO, YES);
}

SKScene *WhaleyCreateSrcEmbeddedLevelScene(NSInteger levelNumber, CGSize logicalSize) {
    return WhaleyCreateSrcEmbeddedLevelSceneWithSoundEffects(levelNumber, logicalSize, YES);
}

SKScene *WhaleyCreateSrcEmbeddedLevelSceneWithSoundEffects(NSInteger levelNumber, CGSize logicalSize, BOOL soundEffectsEnabled) {
    return WhaleyCreateLevelHost(levelNumber, logicalSize, YES, soundEffectsEnabled);
}

BOOL WhaleySrcHostSoundEffectsEnabled(SKScene *host) {
    return host == WhaleyCurrentHost && [SimpleAudioEngine sharedEngine].soundEffectsEnabled;
}

void WhaleySrcSetHostSoundEffectsEnabled(SKScene *host, BOOL enabled) {
    NSCAssert([NSThread isMainThread], @"Host audio changes require the main thread");
    if (!host || host != WhaleyCurrentHost) return;
    [SimpleAudioEngine sharedEngine].soundEffectsEnabled = enabled;
}

void WhaleySrcSetHostSuspended(SKScene *host, BOOL suspended) {
    NSCAssert([NSThread isMainThread], @"Host suspension requires the main thread");
    if (host != WhaleyCurrentHost) return;
    if (suspended && !host.paused) {
        [WhaleyCurrentGame.bgSound stop];
        [WhaleyCurrentGame.bounceSound stop];
        [WhaleyCurrentGame.flameSound stop];
        [WhaleyCurrentGame.jumpSound stop];
        [WhaleyCurrentGame.collectibleSound stop];
        [WhaleyCurrentGame.goalSound stop];
        [WhaleyCurrentMenu.knockSound stop];
        [[SimpleAudioEngine sharedEngine] pauseBackgroundMusic];
    } else if (!suspended && host.paused && WhaleyCurrentMenu) {
        [[SimpleAudioEngine sharedEngine] resumeBackgroundMusic];
    }
    // Pause an ancestor, leaving the HUD's game.isPaused/game.paused state intact.
    host.paused = suspended;
}

void WhaleySrcDisposeHost(SKScene *host) {
    NSCAssert([NSThread isMainThread], @"Host disposal requires the main thread");
    if (host != WhaleyCurrentHost) return;
    WhaleyFinishSceneInteractions();
    Whaley3DClearHeldBubble();
    WhaleyStopSceneSchedules(host);
    [[SimpleAudioEngine sharedEngine] endSoundEffectsSession];
    [[SimpleAudioEngine sharedEngine] pauseBackgroundMusic];
    [host removeAllActions];
    [host removeAllChildren];
    WhaleyCurrentGame = nil;
    WhaleyCurrentMenu = nil;
    WhaleyCurrentHost = nil;
    WhaleyEmbeddedHost = NO;
    [WhaleyExternalProjectiles removeAllObjects];
    [WhaleyConsumedExternalProjectiles removeAllObjects];
    [WhaleyObservedEvents removeAllObjects];
}

SKScene *WhaleyCreateSrcLevelOneScene(void) {
    return WhaleyCreateSrcLevelScene(1);
}

SKScene *WhaleyCreateSrcLevelTwoScene(void) {
    return WhaleyCreateSrcLevelScene(2);
}

void WhaleySrcSetCompatViewSize(CGSize size) {
    [[CCDirector sharedDirector] setCompatViewSize:size];
}

BOOL WhaleySrcTouchBegan(UITouch *touch, UIEvent *event) {
    if (WhaleyCurrentGame.winScreen.visible) return YES;
    return [[[CCDirector sharedDirector] touchDispatcher] dispatchTouchBegan:touch withEvent:event];
}
void WhaleySrcTouchMoved(UITouch *touch, UIEvent *event) {
    [[[CCDirector sharedDirector] touchDispatcher] dispatchTouchMoved:touch withEvent:event];
}
void WhaleySrcTouchEnded(UITouch *touch, UIEvent *event) {
    if (WhaleyCurrentGame.winScreen.visible) {
        [WhaleyCurrentGame.winScreen advanceAfterWin];
        return;
    }
    [[[CCDirector sharedDirector] touchDispatcher] dispatchTouchEnded:touch withEvent:event];
}
void WhaleySrcTouchCancelled(UITouch *touch, UIEvent *event) {
    [[[CCDirector sharedDirector] touchDispatcher] dispatchTouchCancelled:touch withEvent:event];
}

void WhaleySrcSetSceneScrubPaused(BOOL paused) {
    Whaley *game = WhaleyCurrentGame;
    if (paused) {
        if (!game || WhaleyScrubPauseOwner == game) return;
        // A previous scene must never leave a pause claim on its replacement.
        [WhaleyScrubPauseOwner release];
        WhaleyScrubPauseOwner = [game retain];
        WhaleyWasPausedBeforeScrub = game.isPaused;
        game.isPaused = YES;
    } else {
        Whaley *owner = WhaleyScrubPauseOwner;
        WhaleyScrubPauseOwner = nil;
        if (owner && owner == game) owner.isPaused = WhaleyWasPausedBeforeScrub;
        [owner release];
    }
}

void WhaleySrcBeginTimeProjection(void) {
    Whaley *game = WhaleyCurrentGame;
    WhaleyHasLivePlayerBeforeTimeProjection = NO;
    if (!game || !game.player) {
        return;
    }
    WhaleyLivePlayerBeforeTimeProjection = game.player.position;
    WhaleyHasLivePlayerBeforeTimeProjection = YES;
}

BOOL WhaleySrcProjectTime(NSTimeInterval seconds) {
    Whaley *game = WhaleyCurrentGame;
    if (!game || !WhaleyHasLivePlayerBeforeTimeProjection) {
        return NO;
    }
    NSInteger interval = (NSInteger)floor(MAX(0.0, seconds) / 2.0);
    NSInteger projectedPhase = (interval % 2 == 0) ? 180 : 0;
    for (Hazard *hazard in game.hazards) {
        BOOL active = hazard.phase == -1 || hazard.phase == projectedPhase;
        hazard.isActive = active;
        hazard.opacity = active ? FLAME_OPAQUE : FLAME_DIMMED;
        hazard.color = active ? ccWHITE : ccBLACK;
    }
    return WhaleySrcTrajectoryProjectPlayer(game.player, seconds);
}

void WhaleySrcRestoreLiveProjection(void) {
    Whaley *game = WhaleyCurrentGame;
    if (!game || !WhaleyHasLivePlayerBeforeTimeProjection) {
        return;
    }
    if (WhaleyHasLivePlayerBeforeTimeProjection && game.player) {
        game.player.position = WhaleyLivePlayerBeforeTimeProjection;
        WhaleyHasLivePlayerBeforeTimeProjection = NO;
    }
    NSInteger livePhase = [[game valueForKey:@"_phase"] integerValue];
    for (Hazard *hazard in game.hazards) {
        BOOL active = hazard.phase == -1 || hazard.phase == livePhase;
        hazard.isActive = active;
        hazard.opacity = active ? FLAME_OPAQUE : FLAME_DIMMED;
        hazard.color = active ? ccWHITE : ccBLACK;
    }
}

#pragma mark - Live Scene Shift acquisition

typedef NS_ENUM(NSInteger, WhaleySceneScrubTargetKind) {
    WhaleySceneScrubTargetNone = 0,
    WhaleySceneScrubTargetObject = 1,
    WhaleySceneScrubTargetTile = 2,
};

static WhaleySceneScrubTargetKind WhaleySceneScrubKind = WhaleySceneScrubTargetNone;
static GameObject *WhaleySceneScrubObject = nil;
static SKNode *WhaleySceneScrubGhost = nil;

static void WhaleySceneScrubShowGhost(GameObject *object) {
    [WhaleySceneScrubGhost removeFromParent];
    [WhaleySceneScrubGhost release];
    WhaleySceneScrubGhost = nil;
    if (!object || !object.parent) return;

    CGRect originalFrame = [object boundingBox];
    SKTexture *texture = object.spriteKitNode.texture;
    if (!texture || CGRectIsEmpty(originalFrame)) return;
    SKSpriteNode *ghost = [SKSpriteNode spriteNodeWithTexture:texture
                                                size:originalFrame.size];
    ghost.position = CGPointMake(CGRectGetMidX(originalFrame), CGRectGetMidY(originalFrame));
    ghost.alpha = 0.24;
    ghost.color = UIColor.systemTealColor;
    ghost.colorBlendFactor = 0.25;
    ghost.zPosition = object.zPosition + 0.5;
    [object.parent addChild:ghost];
    WhaleySceneScrubGhost = [ghost retain];
}
static CGPoint WhaleySceneScrubOriginPosition;
static CGFloat WhaleySceneScrubOriginScaleX = 1.0;
static CGFloat WhaleySceneScrubOriginScaleY = 1.0;
static NSInteger WhaleySceneScrubImageIndex = 0;
static CGPoint WhaleySceneScrubTileCoordinate;
static SKShapeNode *WhaleySceneScrubTileOverlay = nil;
static NSMutableArray<NSNumber *> *WhaleySceneScrubTileRowSnapshot = nil;
static NSInteger WhaleySceneScrubTileInitialRun = 1;
static NSInteger WhaleySceneScrubTileAnchorGID = 0;

static NSArray *WhaleySceneScrubCandidates(Whaley *game) {
    if (!game) {
        return @[];
    }
    NSMutableArray *objects = [NSMutableArray array];
    if (game.player) {
        [objects addObject:game.player];
    }
    if (game.goal) {
        [objects addObject:game.goal];
    }
    [objects addObjectsFromArray:game.hazards ?: @[]];
    [objects addObjectsFromArray:game.collectibles ?: @[]];
    return objects;
}

static CGPoint WhaleySceneScrubScenePoint(CGPoint viewPoint) {
    Whaley *game = WhaleyCurrentGame;
    SKScene *host = game.scene;
    return host ? [host convertPointFromView:viewPoint] : CGPointZero;
}

static GameObject *WhaleySceneScrubHitObject(CGPoint scenePoint) {
    Whaley *game = WhaleyCurrentGame;
    if (!game || !game.scene) {
        return nil;
    }
    NSArray *objects = WhaleySceneScrubCandidates(game);
    for (GameObject *object in [objects reverseObjectEnumerator]) {
        if (!object.visible || !object.parent) {
            continue;
        }
        CGPoint parentPoint = [object.parent convertPoint:scenePoint fromNode:game.scene];
        if (CGRectContainsPoint([object boundingBox], parentPoint)) {
            return object;
        }
    }
    return nil;
}

static BOOL WhaleySceneScrubHitTile(CGPoint scenePoint, CGPoint *tileCoordinate) {
    Whaley *game = WhaleyCurrentGame;
    if (!game || !game.meta || !game.tileMap) {
        return NO;
    }
    CGPoint local = [game.meta convertPoint:scenePoint fromNode:game.scene];
    CGSize tile = game.tileMap.tileSize;
    NSInteger width = (NSInteger)game.tileMap.mapSize.width;
    NSInteger height = (NSInteger)game.tileMap.mapSize.height;
    if (tile.width <= 0 || tile.height <= 0 || local.x < 0 || local.y < 0) {
        return NO;
    }
    NSInteger column = (NSInteger)floor(local.x / tile.width);
    NSInteger bottomRow = (NSInteger)floor(local.y / tile.height);
    NSInteger row = height - 1 - bottomRow;  // TMX is top-left row order
    if (column < 0 || column >= width || row < 0 || row >= height) {
        return NO;
    }
    if ([game.meta tileGIDAt:CGPointMake(column, row)] == 0) {
        return NO;
    }
    if (tileCoordinate) {
        *tileCoordinate = CGPointMake(column, row);
    }
    return YES;
}

static void WhaleySceneScrubShowTileOverlayRun(CGPoint coordinate, NSInteger cells) {
    [WhaleySceneScrubTileOverlay removeFromParent];
    WhaleySceneScrubTileOverlay = nil;
    Whaley *game = WhaleyCurrentGame;
    if (!game || !game.meta || !game.scene) {
        return;
    }
    CGSize tile = game.tileMap.tileSize;
    NSInteger height = (NSInteger)game.tileMap.mapSize.height;
    CGPoint localOrigin = CGPointMake(coordinate.x * tile.width,
                                      (height - 1 - coordinate.y) * tile.height);
    CGPoint hostOrigin = [game.scene convertPoint:localOrigin fromNode:game.meta];
    CGPoint hostFar = [game.scene convertPoint:CGPointMake(localOrigin.x + tile.width * MAX(1, cells),
                                                           localOrigin.y + tile.height)
                                      fromNode:game.meta];
    CGRect rect = CGRectMake(MIN(hostOrigin.x, hostFar.x), MIN(hostOrigin.y, hostFar.y),
                             fabs(hostFar.x - hostOrigin.x), fabs(hostFar.y - hostOrigin.y));
    SKShapeNode *shape = [SKShapeNode shapeNodeWithRect:rect];
    shape.strokeColor = UIColor.systemYellowColor;
    shape.fillColor = [UIColor.systemYellowColor colorWithAlphaComponent:0.18];
    shape.lineWidth = 3;
    shape.zPosition = 40000;
    [game.scene addChild:shape];
    WhaleySceneScrubTileOverlay = shape;
}

BOOL WhaleySrcHitBubble(CGPoint viewPoint) {
    Whaley *game = WhaleyCurrentGame;
    if (!game || !game.scene) {
        return NO;
    }
    CGPoint scenePoint = WhaleySceneScrubScenePoint(viewPoint);
    for (Projectile *bubble in [game.projectiles reverseObjectEnumerator]) {
        if (!bubble.visible || !bubble.parent) {
            continue;
        }
        CGPoint parentPoint = [bubble.parent convertPoint:scenePoint fromNode:game.scene];
        CGRect hit = CGRectInset([bubble boundingBox], -TouchBubbleFudgeOffset, -TouchBubbleFudgeOffset);
        if (CGRectContainsPoint(hit, parentPoint)) {
            return YES;
        }
    }
    return NO;
}

static GameObject *WhaleySceneScrubAccessibleObject(NSUInteger index) {
    NSArray *objects = WhaleySceneScrubCandidates(WhaleyCurrentGame);
    return index < objects.count ? objects[index] : nil;
}

NSUInteger WhaleySrcSceneScrubAccessibleObjectCount(void) {
    return WhaleySceneScrubCandidates(WhaleyCurrentGame).count;
}

NSString *WhaleySrcSceneScrubAccessibleObjectLabel(NSUInteger index) {
    GameObject *object = WhaleySceneScrubAccessibleObject(index);
    if (!object) {
        return @"Game object";
    }
    Whaley *game = WhaleyCurrentGame;
    if (object == game.player) {
        return @"Whaley";
    }
    if (object == game.goal) {
        return @"Goal bubble";
    }
    if ([object isKindOfClass:[Hazard class]]) {
        NSUInteger ordinal = [game.hazards indexOfObjectIdenticalTo:object];
        return [NSString stringWithFormat:@"Hazard %lu", (unsigned long)(ordinal == NSNotFound ? index + 1 : ordinal + 1)];
    }
    if ([object isKindOfClass:[Collectible class]]) {
        NSUInteger ordinal = [game.collectibles indexOfObjectIdenticalTo:object];
        return [NSString stringWithFormat:@"Collectible %lu", (unsigned long)(ordinal == NSNotFound ? index + 1 : ordinal + 1)];
    }
    return [NSString stringWithFormat:@"Game object %lu", (unsigned long)(index + 1)];
}

CGRect WhaleySrcSceneScrubAccessibleObjectFrame(NSUInteger index) {
    GameObject *object = WhaleySceneScrubAccessibleObject(index);
    Whaley *game = WhaleyCurrentGame;
    if (!object || !object.visible || !object.parent || !game.scene) {
        return CGRectZero;
    }
    CGRect box = [object boundingBox];
    CGPoint corners[4] = {
        CGPointMake(CGRectGetMinX(box), CGRectGetMinY(box)),
        CGPointMake(CGRectGetMaxX(box), CGRectGetMinY(box)),
        CGPointMake(CGRectGetMinX(box), CGRectGetMaxY(box)),
        CGPointMake(CGRectGetMaxX(box), CGRectGetMaxY(box))};
    CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX, maxX = -CGFLOAT_MAX, maxY = -CGFLOAT_MAX;
    for (NSInteger i = 0; i < 4; i++) {
        CGPoint scenePoint = [game.scene convertPoint:corners[i] fromNode:object.parent];
        CGPoint viewPoint = [game.scene convertPointToView:scenePoint];
        minX = MIN(minX, viewPoint.x);
        minY = MIN(minY, viewPoint.y);
        maxX = MAX(maxX, viewPoint.x);
        maxY = MAX(maxY, viewPoint.y);
    }
    return CGRectMake(minX, minY, MAX(1, maxX - minX), MAX(1, maxY - minY));
}

CGRect WhaleySrcSceneScrubActiveObjectFrame(void) {
    Whaley *game = WhaleyCurrentGame;
    GameObject *object = WhaleySceneScrubObject;
    if (!object || !object.visible || !object.parent || !game.scene) {
        return CGRectZero;
    }
    CGRect box = [object boundingBox];
    CGPoint corners[4] = {
        CGPointMake(CGRectGetMinX(box), CGRectGetMinY(box)),
        CGPointMake(CGRectGetMaxX(box), CGRectGetMinY(box)),
        CGPointMake(CGRectGetMinX(box), CGRectGetMaxY(box)),
        CGPointMake(CGRectGetMaxX(box), CGRectGetMaxY(box))};
    CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX, maxX = -CGFLOAT_MAX, maxY = -CGFLOAT_MAX;
    for (NSInteger i = 0; i < 4; i++) {
        CGPoint scenePoint = [game.scene convertPoint:corners[i] fromNode:object.parent];
        CGPoint viewPoint = [game.scene convertPointToView:scenePoint];
        minX = MIN(minX, viewPoint.x);
        minY = MIN(minY, viewPoint.y);
        maxX = MAX(maxX, viewPoint.x);
        maxY = MAX(maxY, viewPoint.y);
    }
    return CGRectMake(minX, minY, MAX(1, maxX - minX), MAX(1, maxY - minY));
}

BOOL WhaleySrcSceneScrubBeginAccessibleObject(NSUInteger index) {
    GameObject *object = WhaleySceneScrubAccessibleObject(index);
    if (!object || !object.visible || !object.parent) {
        return NO;
    }
    WhaleySceneScrubKind = WhaleySceneScrubTargetObject;
    WhaleySceneScrubObject = object;
    WhaleySceneScrubShowGhost(object);
    WhaleySceneScrubOriginPosition = object.position;
    WhaleySceneScrubOriginScaleX = object.scaleX;
    WhaleySceneScrubOriginScaleY = object.scaleY;
    WhaleySceneScrubImageIndex = 0;
    WhaleySrcSetSceneScrubPaused(YES);
    return YES;
}

static Projectile *WhaleyAccessibleBubble = nil;
static CGPoint WhaleyAccessibleBubbleOrigin = {0, 0};

static NSArray *WhaleyAccessibleBubbles(void) {
    Whaley *game = WhaleyCurrentGame;
    if (!game) {
        return @[];
    }
    NSMutableArray *result = [NSMutableArray array];
    for (Projectile *bubble in game.projectiles) {
        if (WhaleySceneIs3DFoundation(bubble)) continue;
        BOOL accessibilityOwnsBubble = (bubble == WhaleyAccessibleBubble);
        if (bubble.isFrozen && bubble.visible && bubble.parent && (!bubble.isBeingMoved || accessibilityOwnsBubble)) {
            [result addObject:bubble];
        }
    }
    return result;
}

static Projectile *WhaleyAccessibleBubbleAtIndex(NSUInteger index) {
    NSArray *bubbles = WhaleyAccessibleBubbles();
    return index < bubbles.count ? bubbles[index] : nil;
}

NSUInteger WhaleySrcAccessibleBubbleCount(void) {
    return WhaleyAccessibleBubbles().count;
}

NSString *WhaleySrcAccessibleBubbleLabel(NSUInteger index) {
    return [NSString stringWithFormat:@"Bubble %lu", (unsigned long)(index + 1)];
}

CGRect WhaleySrcAccessibleBubbleFrame(NSUInteger index) {
    Projectile *bubble = WhaleyAccessibleBubbleAtIndex(index);
    Whaley *game = WhaleyCurrentGame;
    if (!bubble || !game.scene) {
        return CGRectZero;
    }
    CGRect box = [bubble boundingBox];
    CGPoint corners[4] = {
        CGPointMake(CGRectGetMinX(box), CGRectGetMinY(box)),
        CGPointMake(CGRectGetMaxX(box), CGRectGetMinY(box)),
        CGPointMake(CGRectGetMinX(box), CGRectGetMaxY(box)),
        CGPointMake(CGRectGetMaxX(box), CGRectGetMaxY(box))};
    CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX, maxX = -CGFLOAT_MAX, maxY = -CGFLOAT_MAX;
    for (NSInteger i = 0; i < 4; i++) {
        CGPoint scenePoint = [game.scene convertPoint:corners[i] fromNode:bubble.parent];
        CGPoint viewPoint = [game.scene convertPointToView:scenePoint];
        minX = MIN(minX, viewPoint.x);
        minY = MIN(minY, viewPoint.y);
        maxX = MAX(maxX, viewPoint.x);
        maxY = MAX(maxY, viewPoint.y);
    }
    return CGRectMake(minX, minY, MAX(1, maxX - minX), MAX(1, maxY - minY));
}

BOOL WhaleySrcAccessibleBubbleBegin(NSUInteger index) {
    Projectile *bubble = WhaleyAccessibleBubbleAtIndex(index);
    Whaley *game = WhaleyCurrentGame;
    if (!bubble || !game) {
        return NO;
    }
    WhaleySrcSceneScrubEnd();
    WhaleyAccessibleBubble = bubble;
    WhaleyAccessibleBubbleOrigin = bubble.position;
    if (bubble.bouncesLeft < 0) {
        bubble.bouncesLeft = 2;
    }
    bubble.isBeingMoved = YES;
    bubble.relativeOffset = CGPointZero;
    bubble.scaleX = NormalSize;
    bubble.scaleY = NormalSize;
    WhaleySrcSetSceneScrubPaused(YES);
    return YES;
}

BOOL WhaleySrcAccessibleBubbleMove(CGFloat deltaX, CGFloat deltaY) {
    Projectile *bubble = WhaleyAccessibleBubble;
    Whaley *game = WhaleyCurrentGame;
    if (!bubble || !bubble.parent || !game) {
        return NO;
    }
    bubble.position = CGPointMake(WhaleyAccessibleBubbleOrigin.x + deltaX,
                                  WhaleyAccessibleBubbleOrigin.y + deltaY);
    return YES;
}

void WhaleySrcAccessibleBubbleEnd(void) {
    Projectile *bubble = WhaleyAccessibleBubble;
    if (bubble) {
        CGFloat delta = NormalSize - SmallSize;
        bubble.position = CGPointMake(bubble.position.x + bubble.relativeOffset.x * delta,
                                      bubble.position.y + bubble.relativeOffset.y * delta);
        bubble.isBeingMoved = NO;
        bubble.scaleX = SmallSize;
        bubble.scaleY = SmallSize;
    }
    WhaleyAccessibleBubble = nil;
    if (bubble) WhaleySrcSetSceneScrubPaused(NO);
}

BOOL WhaleySrcSceneScrubCanAcquire(CGPoint viewPoint) {
    CGPoint scenePoint = WhaleySceneScrubScenePoint(viewPoint);
    if (WhaleySceneScrubHitObject(scenePoint)) {
        return YES;
    }
    return WhaleySceneScrubHitTile(scenePoint, NULL);
}

BOOL WhaleySrcSceneScrubBegin(CGPoint viewPoint) {
    CGPoint scenePoint = WhaleySceneScrubScenePoint(viewPoint);
    GameObject *object = WhaleySceneScrubHitObject(scenePoint);
    if (object) {
        WhaleySceneScrubKind = WhaleySceneScrubTargetObject;
        WhaleySceneScrubObject = object;
        WhaleySceneScrubShowGhost(object);
        WhaleySceneScrubOriginPosition = object.position;
        WhaleySceneScrubOriginScaleX = object.scaleX;
        WhaleySceneScrubOriginScaleY = object.scaleY;
        WhaleySceneScrubImageIndex = 0;
        WhaleySrcSetSceneScrubPaused(YES);
        return YES;
    }
    CGPoint tile;
    if (WhaleySceneScrubHitTile(scenePoint, &tile)) {
        WhaleySceneScrubKind = WhaleySceneScrubTargetTile;
        WhaleySceneScrubTileCoordinate = tile;
        NSInteger width = (NSInteger)WhaleyCurrentGame.tileMap.mapSize.width;
        [WhaleySceneScrubTileRowSnapshot release];
        WhaleySceneScrubTileRowSnapshot = [[NSMutableArray alloc] initWithCapacity:width];
        for (NSInteger column = 0; column < width; column++) {
            [WhaleySceneScrubTileRowSnapshot addObject:@([WhaleyCurrentGame.meta tileGIDAt:CGPointMake(column, tile.y)])];
        }
        WhaleySceneScrubTileAnchorGID = [WhaleyCurrentGame.meta tileGIDAt:tile];
        WhaleySceneScrubTileInitialRun = 1;
        for (NSInteger column = (NSInteger)tile.x + 1; column < width; column++) {
            if ([WhaleyCurrentGame.meta tileGIDAt:CGPointMake(column, tile.y)] == 0) {
                break;
            }
            WhaleySceneScrubTileInitialRun++;
        }
        WhaleySrcSetSceneScrubPaused(YES);
        WhaleySceneScrubShowTileOverlayRun(tile, WhaleySceneScrubTileInitialRun);
        return YES;
    }
    return NO;
}
static void WhaleySceneScrubApplyImage(GameObject *object, NSInteger steps) {
    NSInteger index = MAX(0, WhaleySceneScrubImageIndex + steps);
    SKSpriteNode *presentation = object.spriteKitNode;
    if (!presentation) {
        return;
    }
    NSString *name = nil;
    if ([object isKindOfClass:[Collectible class]]) {
        index = index % 8;
        name = [NSString stringWithFormat:@"coin%ld.png", (long)index + 1];
    } else if ([object isKindOfClass:[Player class]]) {
        index = index % 3;
        name = [NSString stringWithFormat:@"player%ld.png", (long)index + 1];
    } else if ([object isKindOfClass:[Hazard class]]) {
        index = index % 2;
        name = index == 0 ? @"flame01.png" : @"flame02.png";
        presentation.texture = WhaleySrcTexture(name);
        return;
    } else {
        return;
    }
    CCSpriteFrame *frame = [[CCSpriteFrameCache sharedSpriteFrameCache] spriteFrameByName:name];
    if (!frame || frame.atlasFile.length == 0) {
        return;
    }
    CGRect r = frame.frameRect;
    CGSize a = frame.atlasSize;
    SKTexture *atlas = WhaleySrcTexture(frame.atlasFile);
    CGRect normalized = CGRectMake(r.origin.x / a.width, 1.0 - (r.origin.y + r.size.height) / a.height, r.size.width / a.width, r.size.height / a.height);
    presentation.texture = [SKTexture textureWithRect:normalized inTexture:atlas];
    presentation.texture.filteringMode = atlas.filteringMode;
}

void WhaleySrcSceneScrubApply(NSInteger category, NSInteger scalarSteps) {
    if (WhaleySceneScrubKind == WhaleySceneScrubTargetObject) {
        GameObject *object = WhaleySceneScrubObject;
        if (!object) {
            return;
        }
        switch (category) {
            case 0:
                object.position = CGPointMake(WhaleySceneScrubOriginPosition.x + scalarSteps * 32.0,
                                              WhaleySceneScrubOriginPosition.y);
                break;
            case 1: {
                CGFloat width = MAX(32.0, object.contentSize.width * WhaleySceneScrubOriginScaleX + scalarSteps * 32.0);
                CGFloat factor = object.contentSize.width > 0 ? width / object.contentSize.width : WhaleySceneScrubOriginScaleX;
                object.scaleX = factor;
                object.scaleY = factor;
                break;
            }
            case 2:
                WhaleySceneScrubApplyImage(object, scalarSteps);
                break;
            default:
                break;
        }
        return;
    }

    if (WhaleySceneScrubKind == WhaleySceneScrubTargetTile) {
        NSInteger width = (NSInteger)WhaleyCurrentGame.tileMap.mapSize.width;
        NSInteger row = (NSInteger)WhaleySceneScrubTileCoordinate.y;
        if (category == 0) {
            NSInteger column = MAX(0, MIN(width - 1, (NSInteger)WhaleySceneScrubTileCoordinate.x + scalarSteps));
            WhaleySceneScrubShowTileOverlayRun(CGPointMake(column, row), WhaleySceneScrubTileInitialRun);
        } else if (category == 1 && WhaleySceneScrubTileRowSnapshot) {
            for (NSInteger column = 0; column < width; column++) {
                [WhaleyCurrentGame.meta setTileGID:WhaleySceneScrubTileRowSnapshot[column].integerValue at:CGPointMake(column, row)];
            }
            NSInteger anchor = (NSInteger)WhaleySceneScrubTileCoordinate.x;
            NSInteger cells = MAX(1, MIN(width - anchor, WhaleySceneScrubTileInitialRun + scalarSteps));
            NSInteger affected = MAX(WhaleySceneScrubTileInitialRun, cells);
            for (NSInteger offset = 0; offset < affected && anchor + offset < width; offset++) {
                NSInteger gid = offset < cells ? WhaleySceneScrubTileAnchorGID : 0;
                [WhaleyCurrentGame.meta setTileGID:gid at:CGPointMake(anchor + offset, row)];
            }
            WhaleySceneScrubShowTileOverlayRun(WhaleySceneScrubTileCoordinate, cells);
        }
    }
}

void WhaleySrcSceneScrubEnd(void) {
    BOOL acquired = WhaleySceneScrubKind != WhaleySceneScrubTargetNone;
    BOOL editedTiles = WhaleySceneScrubKind == WhaleySceneScrubTargetTile;
    [WhaleySceneScrubGhost removeFromParent];
    [WhaleySceneScrubGhost release];
    WhaleySceneScrubGhost = nil;
    [WhaleySceneScrubTileOverlay removeFromParent];
    WhaleySceneScrubTileOverlay = nil;
    WhaleySceneScrubObject = nil;
    [WhaleySceneScrubTileRowSnapshot release];
    WhaleySceneScrubTileRowSnapshot = nil;
    WhaleySceneScrubKind = WhaleySceneScrubTargetNone;
    if (acquired) WhaleySrcSetSceneScrubPaused(NO);
    if (editedTiles && WhaleyCurrentHost && WhaleySrcTileDebugOverlaysEnabled()) {
        WhaleyInstallCollisionOverlay(WhaleyCurrentHost, WhaleyCurrentHost);
    }
}

CGPoint WhaleySrcPlayerPosition(void) {
    return WhaleyCurrentGame.player ? WhaleyCurrentGame.player.position : CGPointZero;
}

CGPoint WhaleySrcPlayerCenter(void) {
    return WhaleyCurrentGame.player ?
        [Helpers spriteCenter:WhaleyCurrentGame.player] : CGPointZero;
}

NSInteger WhaleySrcCurrentLevelNumber(void) {
    return WhaleyCurrentGame.level ? WhaleyCurrentGame.level.num : 0;
}

void WhaleySrcProjectPlayerPosition(CGPoint position) {
    if (WhaleyCurrentGame.player) {
        WhaleyCurrentGame.player.position = position;
    }
}

NSTimeInterval WhaleySrcGameTime(void) { return WhaleySrcSemanticTime(); }
NSUInteger WhaleySrcPlayerHistorySampleCount(void) { return WhaleySrcTrajectorySampleCount(); }
NSTimeInterval WhaleySrcPlayerHistoryFirstTime(void) { return WhaleySrcTrajectoryFirstTime(); }
NSTimeInterval WhaleySrcPlayerHistoryLastTime(void) { return WhaleySrcTrajectoryLastTime(); }

@interface WhaleyAdventureSyntheticTouch : NSObject
@property (nonatomic) CGPoint point;
@property (nonatomic, assign) UIView *hostView;
@end
@implementation WhaleyAdventureSyntheticTouch
- (CGPoint)locationInView:(UIView *)view {
    return self.point;
}
- (UIView *)view {
    return self.hostView;
}
@end

BOOL WhaleySrcAdventurePerformAction(WhaleyAdventureAction action) {
    Whaley *game = WhaleyCurrentGame;
    CCDirector *director = [CCDirector sharedDirector];
    CGSize viewport = director.compatViewSize;
    if (!game || viewport.width <= 0 || viewport.height <= 0 || game.player.isDead || game.player.hasWon) {
        return NO;
    }

    CGPoint center = [Helpers spriteCenter:game.player];
    CGFloat dx = game.tileMap.tileSize.width * 0.45;
    CGFloat dy = game.tileMap.tileSize.height * 0.80;
    CGPoint sceneTarget = center;
    switch (action) {
        case WhaleyAdventureActionShootLeft:
            sceneTarget = CGPointMake(center.x - dx, center.y - dy);
            break;
        case WhaleyAdventureActionShootRight:
            sceneTarget = CGPointMake(center.x + dx, center.y - dy);
            break;
        case WhaleyAdventureActionShootBelow:
            sceneTarget = CGPointMake(center.x, center.y - dy);
            break;
    }

    CGSize logical = director.winSize;
    CGFloat scale = MAX(viewport.width / logical.width, viewport.height / logical.height);
    CGFloat ox = (viewport.width - logical.width * scale) / 2.0;
    CGFloat oy = (viewport.height - logical.height * scale) / 2.0;
    CGPoint uiPoint = CGPointMake(sceneTarget.x * scale + ox,
                                  (logical.height - sceneTarget.y) * scale + oy);
    WhaleyAdventureSyntheticTouch *touch = [WhaleyAdventureSyntheticTouch new];
    touch.point = uiPoint;
    touch.hostView = nil;
    BOOL accepted = [game ccTouchBegan:(UITouch *)touch withEvent:nil];
    if (accepted) {
        [game ccTouchEnded:(UITouch *)touch withEvent:nil];
    }
    [touch release];
    return accepted;
}

void WhaleySrc3DSetEnabled(BOOL enabled) {
    NSCAssert([NSThread isMainThread], @"3D gameplay requires the main thread");
    Whaley3DClearHeldBubble();
    WhaleyScene3DModeEnabled = enabled;
    WhaleyScene3DPlaceAtAnchor = NO;
    WhaleySceneApply3DEnvironment(WhaleyCurrentGame);
}

BOOL WhaleySrc3DIsAirborne(void) {
    Whaley *game = WhaleyCurrentGame;
    return game && !game.player.isDead && game.player.airMode != GROUNDED;
}

NSUInteger WhaleySrc3DJumpSequence(void) {
    return WhaleyScene3DJumpSequence;
}

CGPoint WhaleySrc3DPlayerBottom(void) {
    Whaley *game = WhaleyCurrentGame;
    if (!game || !game.player) return CGPointZero;
    return CGPointMake([Helpers spriteCenter:game.player].x, game.player.position.y);
}

CGPoint WhaleySrc3DJumpStartBottom(void) {
    return WhaleyScene3DJumpSequence == 0
        ? WhaleySrc3DPlayerBottom()
        : WhaleyScene3DJumpAnchorBottom;
}

BOOL WhaleySrc3DBeginBubble(WhaleyAdventureAction action) {
    NSCAssert([NSThread isMainThread], @"3D gameplay requires the main thread");
    Whaley3DClearHeldBubble();
    int side;
    switch (action) {
        case WhaleyAdventureActionShootLeft: side = -1; break;
        case WhaleyAdventureActionShootRight: side = 1; break;
        case WhaleyAdventureActionShootBelow: side = 0; break;
        default: return NO;
    }
    Projectile *projectile = WhaleyCreate3DShot(WhaleyCurrentGame, side);
    if (!projectile) return NO;
    Whaley3DHeldIdentity = [WhaleySnapshotIdentity(projectile) copy];
    Whaley3DHeldInitialScale = projectile.sizeMode;
    return YES;
}

BOOL WhaleySrc3DBeginExistingBubble(NSString *sessionID, NSString *projectileID) {
    NSCAssert([NSThread isMainThread], @"3D gameplay requires the main thread");
    Whaley3DClearHeldBubble();
    Whaley *game = WhaleyCurrentGame;
    NSString *currentSession = game ? WhaleySnapshotSessionIdentity(game) : nil;
    Projectile *projectile = WhaleyFind3DGrowableBubble(game, sessionID, currentSession,
        projectileID, ^NSString *(GameObject *object) { return WhaleySnapshotIdentity(object); });
    if (!projectile) return NO;
    // Re-selection neither creates nor repositions a shot, resets its bounce
    // allowance, nor charges the shot score. Growth resumes from its live size.
    Whaley3DHeldIdentity = [projectileID copy];
    Whaley3DHeldInitialScale = projectile.sizeMode;
    return YES;
}

void WhaleySrc3DUpdateHeldBubble(NSTimeInterval duration) {
    NSCAssert([NSThread isMainThread], @"3D gameplay requires the main thread");
    Whaley *game = WhaleyCurrentGame;
    if (!WhaleyScene3DModeEnabled || !game || !Whaley3DHeldIdentity ||
        game.player.isDead || game.player.hasWon) {
        Whaley3DClearHeldBubble();
        return;
    }
    Projectile *projectile = nil;
    for (Projectile *candidate in game.projectiles) {
        if ([WhaleySnapshotIdentity(candidate) isEqualToString:Whaley3DHeldIdentity]) {
            projectile = candidate;
            break;
        }
    }
    if (!projectile || WhaleySceneIs3DFoundation(projectile)) {
        Whaley3DClearHeldBubble();
        return;
    }
    // Resolve the live object on the game thread. A popped object is never dereferenced.
    if (game.isPaused || !isfinite(duration) || duration <= 0.2 || !projectile.isFrozen) return;
    CGFloat size = MIN(NormalSize * 2.4,
                       Whaley3DHeldInitialScale + (duration - 0.2) * NormalSize * 1.5);
    projectile.sizeMode = MAX(projectile.sizeMode, size);
}

void WhaleySrc3DEndHeldBubble(void) {
    NSCAssert([NSThread isMainThread], @"3D gameplay requires the main thread");
    Whaley3DClearHeldBubble();
}

BOOL WhaleySrcAdventurePlayerIsDead(void) {
    return WhaleyCurrentGame ? WhaleyCurrentGame.player.isDead : NO;
}

CGPoint WhaleySrcAdventureViewPoint(CGPoint normalizedLevelPoint) {
    Whaley *game = WhaleyCurrentGame;
    if (!game || !game.scene || !game.meta || !game.tileMap) {
        return CGPointMake(NAN, NAN);
    }
    CGSize tile = game.tileMap.tileSize;
    CGSize map = game.tileMap.mapSize;
    CGFloat width = tile.width * map.width;
    CGFloat height = tile.height * map.height;
    CGPoint local = CGPointMake(normalizedLevelPoint.x * width,
                                (1.0 - normalizedLevelPoint.y) * height);
    CGPoint scenePoint = [game.scene convertPoint:local fromNode:game.meta];
    return [game.scene convertPointToView:scenePoint];
}

BOOL WhaleySrcAdventurePrepareCheckpoint(CGPoint normalizedLevelPoint) {
    Whaley *game = WhaleyCurrentGame;
    if (!game || !game.level || !game.tileMap) {
        return NO;
    }

    WhaleySrcReplayCurrentLevel();
    game = WhaleyCurrentGame;
    if (!game || !game.player || !game.tileMap) {
        return NO;
    }

    CGSize tile = game.tileMap.tileSize;
    CGSize map = game.tileMap.mapSize;
    CGFloat width = tile.width * map.width;
    CGFloat height = tile.height * map.height;
    if (width <= 0 || height <= 0) {
        return NO;
    }

    CGPoint position = CGPointMake(normalizedLevelPoint.x * width,
                                   (1.0 - normalizedLevelPoint.y) * height);
    game.player.position = position;
    game.player.desiredPos = position;
    game.player.isDead = NO;
    game.player.hasWon = NO;
    game.player.isMovingLaterally = NO;
    game.player.xAdd = 0;
    game.player.yAdd = 0;
    return YES;
}

CGSize WhaleySrcAdventureLevelSize(void) {
    Whaley *game = WhaleyCurrentGame;
    if (!game || !game.tileMap) {
        return CGSizeZero;
    }
    CGSize tile = game.tileMap.tileSize;
    CGSize map = game.tileMap.mapSize;
    return CGSizeMake(tile.width * map.width, tile.height * map.height);
}
#endif
