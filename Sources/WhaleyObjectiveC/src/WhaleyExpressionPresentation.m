#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyExpressionPresentation.h"
#if defined(WHALEY_SPRITEKIT_COMPAT)
#import "WhaleyExpressionPolicy.h"
#import "WhaleyJumpTrail.h"
#import "WhaleyFlamePresentation.h"
#import "WhaleyBootstrap.h"
#import <objc/runtime.h>

static char WhaleyExpressionBubbleIdentifierKey;

typedef struct {
    const WhaleyTrailSurface *surfaces;
    size_t count;
} WhaleyTrailSurfaceContext;

static bool WhaleyFindTrailSurface(void *context, double x, double fromBottom,
                                  double toBottom, WhaleyTrailSurface *surface) {
    const WhaleyTrailSurfaceContext *cached = context;
    for (size_t i = 0; i < cached->count; i++) {
        WhaleyTrailSurface candidate = cached->surfaces[i];
        if (x >= candidate.left && x < candidate.right &&
            fromBottom >= candidate.y - 1e-9 && toBottom <= candidate.y + 1e-9) {
            *surface = candidate; // The cache is ordered from highest to lowest.
            return true;
        }
    }
    return false;
}

@interface WhaleyExpressionPresentation ()
- (void)enable:(Player *)player;
- (void)advanceTrail:(Whaley *)game seconds:(ccTime)seconds;
- (void)prepareTrailSurfaces:(Whaley *)game;
@end

@implementation WhaleyExpressionPresentation {
    NSArray<SKTexture *> *_frames;
    SKTexture *_originalTexture;
    NSMutableData *_events;
    NSMutableData *_targets;
    WhaleyExpressionState _state;
    uint64_t _nextBubbleIdentifier;
    double _animationElapsed;
    BOOL _enabled;
    WhaleyJumpTrail _trail;
    WhaleyFlamePresentation *_flames;
    SKNode *_trailLayer;
    NSMutableArray<SKSpriteNode *> *_trailNodes;
    NSMutableData *_trailSurfaces;
    CCTMXTiledMap *_trailMap;
}

- (instancetype)initWithPlayer:(Player *)player {
    if (!(self = [super init])) return nil;
    NSString *filename = [GameState gameState].levelsAchieved > NumLevels
        ? @"whaley-win-expressions.png" : @"whaley-expressions.png";
    NSURL *url = WhaleySrcResourceURL(filename);
    UIImage *image = url ? [UIImage imageWithContentsOfFile:url.path] : nil;
    if (!image.CGImage || CGImageGetWidth(image.CGImage) != 864 ||
        CGImageGetHeight(image.CGImage) != 32 * WhaleyExpressionRows) {
        [self release];
        return nil;
    }
    SKTexture *atlas = [SKTexture textureWithImage:image];
    atlas.filteringMode = SKTextureFilteringNearest;
    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:27 * WhaleyExpressionRows];
    for (NSInteger row = 0; row < WhaleyExpressionRows; row++) {
        for (NSInteger column = 0; column < 27; column++) {
            CGRect crop = CGRectMake(column / 27.0, 1 - (row + 1.0) / WhaleyExpressionRows,
                                     1 / 27.0, 1.0 / WhaleyExpressionRows);
            SKTexture *texture = [SKTexture textureWithRect:crop inTexture:atlas];
            texture.filteringMode = SKTextureFilteringNearest;
            [frames addObject:texture];
        }
    }
    _frames = [frames copy];
    _events = [NSMutableData new];
    _targets = [NSMutableData new];
    _nextBubbleIdentifier = 1;
    _trailNodes = [NSMutableArray new];
    _trailSurfaces = [NSMutableData new];
    _flames = [WhaleyFlamePresentation new];
    if (!WhaleyScene3DModeEnabled) [self enable:player];
    return self;
}

- (void)enable:(Player *)player {
    [_originalTexture release];
    _originalTexture = [player.spriteKitNode.texture retain];
    [player stopAction:player.moveAction];
    WhaleyExpressionReset(&_state);
    WhaleyTrailReset(&_trail);
    CGPoint center = [Helpers spriteCenter:player];
    _state.previous = (WhaleyExpressionPoint){center.x, center.y};
    _state.hasPrevious = true;
    _animationElapsed = 0;
    _enabled = YES;
}

- (void)collectCoin {
    if (!_enabled) return;
    WhaleyExpressionEvent event = {WhaleyExpressionCollect, 0, 0};
    [_events appendBytes:&event length:sizeof(event)];
}

- (void)contactBubble:(Projectile *)projectile player:(Player *)player jumped:(BOOL)jumped {
    if (!_enabled) return;
    NSNumber *identifier = objc_getAssociatedObject(projectile, &WhaleyExpressionBubbleIdentifierKey);
    if (!identifier) {
        identifier = @(_nextBubbleIdentifier++);
        objc_setAssociatedObject(projectile, &WhaleyExpressionBubbleIdentifierKey, identifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGPoint center = [Helpers spriteCenter:player];
    double horizontal = center.x - projectile.position.x;
    int direction = horizontal < 0 ? -1 : horizontal > 0 ? 1 : player.flipX ? -1 : 1;
    WhaleyExpressionEvent event = {jumped ? WhaleyExpressionJump : WhaleyExpressionBounce,
        identifier.unsignedLongLongValue, direction};
    [_events appendBytes:&event length:sizeof(event)];
}

- (void)advance:(Whaley *)game seconds:(ccTime)seconds {
    [_flames advance:game seconds:seconds];
    Player *player = game.player;
    BOOL enabled = !WhaleyScene3DModeEnabled;
    if (!enabled) {
        WhaleyTrailStop(&_trail);
        _trailLayer.hidden = YES;
        if (_enabled) {
            player.spriteKitNode.texture = _originalTexture;
            [player runAction:player.moveAction];
            _enabled = NO;
            [_events setLength:0];
        }
        return;
    }
    if (!_enabled) [self enable:player];
    [self advanceTrail:game seconds:seconds];
    CGPoint center = [Helpers spriteCenter:player];
    if (game.isPaused) {
        _state.previous = (WhaleyExpressionPoint){center.x, center.y};
        return;
    }
    if (isfinite(seconds) && seconds > 0) {
        _animationElapsed = fmod(_animationElapsed + fmin(seconds, 0.25), 0.75);
    }
    [_targets setLength:0];
    [game.hazards enumerateObjectsUsingBlock:^(Hazard *hazard, NSUInteger index, BOOL *stop) {
        WhaleyExpressionTarget target = {WhaleyExpressionHazard, index,
            {hazard.position.x, hazard.position.y}, hazard.visible && hazard.isActive};
        [self->_targets appendBytes:&target length:sizeof(target)];
    }];
    for (Collectible *coin in game.collectibles) {
        if (!coin.visible) continue;
        WhaleyExpressionTarget target = {WhaleyExpressionCoin, (uint64_t)coin.tag,
            {coin.position.x, coin.position.y}, true};
        [_targets appendBytes:&target length:sizeof(target)];
    }
    int status = player.isDead ? WhaleyExpressionDead : player.hasWon ? WhaleyExpressionWon : WhaleyExpressionPlaying;
    WhaleyExpressionFrame frame = WhaleyExpressionStep(&_state,
        (WhaleyExpressionPoint){center.x, center.y}, player.flipX, player.airMode == GROUNDED,
        status, _targets.bytes, _targets.length / sizeof(WhaleyExpressionTarget),
        _events.bytes, _events.length / sizeof(WhaleyExpressionEvent));
    [_events setLength:0];
    // Keep the wrapper's logical size, anchors, flips and tint authoritative.
    NSUInteger animation = (NSUInteger)(_animationElapsed / 0.25 + 1e-9) % 3;
    player.spriteKitNode.texture = _frames[frame.row * 27 + animation * 9 + frame.column];
}

- (void)prepareTrailSurfaces:(Whaley *)game {
    if (_trailMap == game.tileMap) return;
    [_trailMap release];
    _trailMap = [game.tileMap retain];
    [_trailSurfaces setLength:0];
    WhaleyTrailReset(&_trail);
    CGSize size = _trailMap.mapSize;
    CGSize tile = _trailMap.tileSize;
    if (!game.meta || !isfinite(size.width) || !isfinite(size.height) ||
        !isfinite(tile.width) || !isfinite(tile.height) || size.width <= 0 ||
        size.height <= 0 || tile.width <= 0 || tile.height <= 0) return;
    NSInteger width = (NSInteger)size.width;
    NSInteger height = (NSInteger)size.height;
    NSMutableData *metadata = [NSMutableData dataWithLength:(NSUInteger)width * (NSUInteger)height];
    uint8_t *cells = metadata.mutableBytes;
    // Read each metadata cell once, never once per droplet per frame.
    for (NSInteger row = 0; row < height; row++) {
        for (NSInteger column = 0; column < width; column++) {
            NSInteger gid = [game.meta tileGIDAt:CGPointMake(column, row)];
            NSDictionary *properties = gid ? [_trailMap propertiesForGID:gid] : nil;
            cells[row * width + column] = ([properties[@"IsWall"] isEqualToString:@"True"] ? 1 : 0) |
                ([properties[@"IsGround"] isEqualToString:@"True"] ? 2 : 0);
        }
    }
    // A ground marker's bottom edge and an exposed wall's top edge are supports.
    // Merge adjacent supports at each height so patches stop at real ledges/gaps.
    for (NSInteger y = height; y >= 0; y--) {
        NSInteger start = -1;
        for (NSInteger x = 0; x <= width; x++) {
            BOOL exposed = NO;
            if (x < width) {
                uint8_t above = y < height ? cells[(height - 1 - y) * width + x] : 0;
                uint8_t below = y > 0 ? cells[(height - y) * width + x] : 0;
                exposed = !(above & 1) && ((above & 2) || (below & 1));
            }
            if (exposed && start < 0) start = x;
            if (!exposed && start >= 0) {
                CGPoint left = [game convertPoint:CGPointMake(start * tile.width, y * tile.height)
                                         fromNode:_trailMap];
                CGPoint right = [game convertPoint:CGPointMake(x * tile.width, y * tile.height)
                                          fromNode:_trailMap];
                WhaleyTrailSurface surface = {left.x, right.x, left.y};
                [_trailSurfaces appendBytes:&surface length:sizeof(surface)];
                start = -1;
            }
        }
    }
}

- (void)advanceTrail:(Whaley *)game seconds:(ccTime)seconds {
    Player *player = game.player;
    CGPoint center = [game convertPoint:[Helpers spriteCenter:player] fromNode:player.parent];
    BOOL jumped = NO;
    const WhaleyExpressionEvent *events = _events.bytes;
    for (NSUInteger i = 0; i < _events.length / sizeof(WhaleyExpressionEvent); i++) {
        if (events[i].kind == WhaleyExpressionJump) jumped = YES;
    }
    [self prepareTrailSurfaces:game];
    WhaleyTrailSurfaceContext surfaces = {_trailSurfaces.bytes,
        _trailSurfaces.length / sizeof(WhaleyTrailSurface)};
    WhaleyTrailAdvanceWithSurfaces(&_trail, (WhaleyTrailPoint){center.x, center.y}, seconds,
        player.airMode != GROUNDED, !player.isDead && !player.hasWon, jumped,
        game.isPaused, UIAccessibilityIsReduceMotionEnabled(), WhaleyFindTrailSurface, &surfaces);
    WhaleyTrailMark marks[WhaleyTrailMarkCapacity];
    NSUInteger count = WhaleyTrailMarks(&_trail, marks);
    if (count && !_trailLayer) {
        _trailLayer = [SKNode new];
        _trailLayer.name = @"WhaleyJumpTrail";
        _trailLayer.zPosition = -1;
        [game addChild:(CCNode *)(id)_trailLayer];
    }
    _trailLayer.hidden = count == 0;
    while (_trailNodes.count < count) {
        SKSpriteNode *node = [SKSpriteNode spriteNodeWithColor:UIColor.whiteColor size:CGSizeZero];
        [_trailLayer addChild:node];
        [_trailNodes addObject:node];
    }
    for (NSUInteger i = 0; i < _trailNodes.count; i++) {
        SKSpriteNode *node = _trailNodes[i];
        node.hidden = i >= count;
        if (i >= count) continue;
        WhaleyTrailMark mark = marks[i];
        node.position = CGPointMake(mark.center.x, mark.center.y);
        node.size = CGSizeMake(mark.width, mark.height);
        node.color = [UIColor colorWithRed:mark.red / 255.0 green:mark.green / 255.0
                                      blue:mark.blue / 255.0 alpha:1];
        node.alpha = mark.alpha;
    }
}

- (void)dealloc {
    [_flames release];
    [_trailLayer removeFromParent];
    [_trailLayer release];
    [_trailNodes release];
    [_trailSurfaces release];
    [_trailMap release];
    [_frames release];
    [_originalTexture release];
    [_events release];
    [_targets release];
    [super dealloc];
}
@end
#endif
#endif
