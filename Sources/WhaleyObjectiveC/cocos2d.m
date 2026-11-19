#if __has_include(<UIKit/UIKit.h>)
#import "cocos2d.h"
#import <objc/message.h>
#import <zlib.h>
#import <math.h>
#import "WhaleyBootstrap.h"
#import "WhaleyRuntimeBridge.h"
#import "WhaleySpriteFrameTarget.h"
#import "src/WhaleySpriteFrameGeometry.h"

@implementation CCCompatTrace
static BOOL _traceEnabled = NO;
static NSMutableArray<NSString *> *_trace;
static const NSUInteger CCCompatTraceCapacity = 4096;

+ (void)setEnabled:(BOOL)enabled {
    @synchronized(self) {
        _traceEnabled = enabled;
        if (enabled && !_trace) {
            _trace = [[NSMutableArray alloc] init];
        }
    }
}

+ (void)record:(NSString *)operation detail:(NSString *)detail {
    @synchronized(self) {
        if (!_traceEnabled) {
            return;
        }
        if (!_trace) {
            _trace = [[NSMutableArray alloc] init];
        }
        NSString *entry = [NSString stringWithFormat:@"%@ %@", operation ?: @"", detail ?: @""];
        if (_trace.count >= CCCompatTraceCapacity) {
            [_trace removeObjectAtIndex:0];
        }
        [_trace addObject:entry];
    }
}

+ (NSArray<NSString *> *)drain {
    @synchronized(self) {
        NSArray *result = _trace ? [[_trace copy] autorelease] : @[];
        [_trace removeAllObjects];
        return result;
    }
}
@end

@implementation CCNode {
    CGSize _contentSize;
    CGPoint _anchorPoint;
    BOOL _visible;
    NSInteger _tag;
    BOOL _ignoreAnchorPointForPosition;
}
- (instancetype)init {
    if ((self = [super init])) {
        self.xScale = 1;
        self.yScale = 1;
        _anchorPoint = CGPointMake(.5, .5);
        _visible = YES;
    }
    return self;
}
- (CGSize)contentSize {
    return _contentSize;
}
- (void)setContentSize:(CGSize)v {
    _contentSize = v;
}
- (CGFloat)scaleX {
    return self.xScale;
}
- (void)setScaleX:(CGFloat)v {
    self.xScale = v;
}
- (CGFloat)scaleY {
    return self.yScale;
}
- (void)setScaleY:(CGFloat)v {
    self.yScale = v;
}
- (BOOL)visible {
    return _visible;
}
- (void)setVisible:(BOOL)v {
    _visible = v;
    self.hidden = !v;
}
- (NSInteger)tag {
    return _tag;
}
- (void)setTag:(NSInteger)v {
    _tag = v;
    self.name = [NSString stringWithFormat:@"tag:%ld", (long)v];
}
- (BOOL)ignoreAnchorPointForPosition {
    return _ignoreAnchorPointForPosition;
}
- (void)setIgnoreAnchorPointForPosition:(BOOL)v {
    _ignoreAnchorPointForPosition = v;
}
- (CGPoint)anchorPoint {
    return _anchorPoint;
}
- (void)setAnchorPoint:(CGPoint)v {
    _anchorPoint = v;
}
- (void)setPosition:(CGPoint)p {
    [super setPosition:p];
    [CCCompatTrace record:@"CCNode.setPosition" detail:NSStringFromCGPoint(p)];
}
- (void)addChild:(CCNode *)child z:(NSInteger)z {
    child.zPosition = z;
    [super addChild:child];
}
- (void)addChild:(CCNode *)child z:(NSInteger)z tag:(NSInteger)tag {
    child.tag = tag;
    [self addChild:child z:z];
}
- (void)removeChild:(CCNode *)child cleanup:(BOOL)cleanup {
    [child removeFromParent];
}
- (CCAction *)runAction:(CCAction *)action {
    void *raw = WhaleyRenderGameAction(action.gameAction, (__bridge void *)self);
    SKAction *rendered = (__bridge SKAction *)raw;
    // Preserve per-action identity for stopAction:, without cancelling siblings.
    NSString *key = [NSString stringWithFormat:@"whaley.cocos2d.action.%p", action];
    [super runAction:rendered withKey:key];
    WhaleyReleaseRenderedObject(raw);
    [CCCompatTrace record:@"CCNode.runAction" detail:NSStringFromClass(action.class)];
    return action;
}
- (void)stopAction:(CCAction *)action {
    if (!action) return;
    [self removeActionForKey:[NSString stringWithFormat:@"whaley.cocos2d.action.%p", action]];
}
- (void)stopAllActions {
    // runAction: installs the translated action on this SKNode, not its sprite child.
    // Cancel in place: do not detach children, reset transforms, or unschedule selectors.
    [super removeAllActions];
}
- (CGPoint)convertToNodeSpace:(CGPoint)point {
    return [self convertPoint:point fromNode:self.scene];
}
@end
@implementation CCLayer {
    BOOL _isTouchEnabled;
}
- (BOOL)isTouchEnabled {
    return _isTouchEnabled;
}
- (void)setIsTouchEnabled:(BOOL)v {
    _isTouchEnabled = v;
    if (v) {
        [self registerWithTouchDispatcher];
    }
}
@end
@implementation CCScene
@end

@interface CCSprite () <WhaleySpriteFrameTarget>
- (void)setDisplayFrame:(CCSpriteFrame *)frame;
- (void)setTextureRect:(CGRect)rect rotated:(BOOL)rotated untrimmedSize:(CGSize)size;
- (void)cc_updatePresentationTransform;
@end

@implementation CCSprite {
    SKSpriteNode *_spriteKitNode;
    SKTexture *_sourceTexture;
    NSString *_atlasFile;
    CGSize _atlasSize;
    CGRect _textureRect;
    CGPoint _frameOffset;
    BOOL _rectRotated;
    BOOL _flipX, _flipY;
    CCSpriteBatchNode *_batchNode;
}
- (instancetype)init {
    if ((self = [super init])) {
        // Retained separately from the children collection: removing children
        // must not leave a dangling MRC pointer to the drawable.
        _spriteKitNode = [[SKSpriteNode alloc] init];
        _spriteKitNode.size = CGSizeZero;
        [self addChild:(CCNode *)(id)_spriteKitNode];
    }
    return self;
}
- (void)dealloc {
    [_spriteKitNode release];
    [_sourceTexture release];
    [_atlasFile release];
    [super dealloc];
}
+ (instancetype)spriteWithFile:(NSString *)file {
    CCSprite *n = [self new];
    n->_sourceTexture = [WhaleySrcTexture(file) retain];
    n->_atlasFile = [file copy];
    n->_atlasSize = n->_sourceTexture.size;
    n.textureRect = (CGRect){CGPointZero, n->_atlasSize};
    [CCCompatTrace record:@"CCSprite.file" detail:[NSString stringWithFormat:@"%@ %.0fx%.0f", file, n.contentSize.width, n.contentSize.height]];
    return [n autorelease];
}
+ (instancetype)spriteWithSpriteFrameName:(NSString *)name {
    CCSpriteFrame *frame = [[CCSpriteFrameCache sharedSpriteFrameCache] spriteFrameByName:name];
    if (!frame) {
        [CCCompatTrace record:@"CCSprite.frame.missing" detail:name];
        return nil;
    }
    CCSprite *n = [self new];
    [n setDisplayFrame:frame];
    return [n autorelease];
}
- (SKSpriteNode *)spriteKitNode { return _spriteKitNode; }
- (CGRect)textureRect { return _textureRect; }

- (BOOL)whaleyApplySpriteFrameNamed:(NSString *)name {
    CCSpriteFrame *frame = [[CCSpriteFrameCache sharedSpriteFrameCache] spriteFrameByName:name];
    if (!frame) {
        [CCCompatTrace record:@"CCSprite.frame.missing" detail:name];
        return NO;
    }
    [self setDisplayFrame:frame];
    return YES;
}

- (void)setDisplayFrame:(CCSpriteFrame *)frame {
    NSParameterAssert(frame);
    CGSize logical = CGSizeEqualToSize(frame.originalSize, CGSizeZero)
        ? frame.frameRect.size : frame.originalSize;
    BOOL hasAtlas = frame.atlasFile.length > 0;
    WhaleyFrameRect region;
    WhaleyFrameRect r = {frame.frameRect.origin.x, frame.frameRect.origin.y,
                        frame.frameRect.size.width, frame.frameRect.size.height};
    // Validate before changing any state. Missing-sheet semantic frames retain
    // their previous transparent-placeholder behavior, never a stale texture.
    BOOL valid = isfinite(logical.width) && isfinite(logical.height) &&
        logical.width >= 0 && logical.height >= 0 &&
        isfinite(frame.frameOffset.x) && isfinite(frame.frameOffset.y) &&
        (!hasAtlas || WhaleyFrameRegion(r, frame.rotated,
                                       frame.atlasSize.width, frame.atlasSize.height, &region));
    if (!valid) {
        [NSException raise:NSInvalidArgumentException format:@"Invalid sprite frame %@", frame.frameName];
        return;
    }
    BOOL sameAtlas = [_atlasFile isEqualToString:frame.atlasFile] &&
        CGSizeEqualToSize(_atlasSize, frame.atlasSize);
    // Custom actions are called every render frame. Reapply only on a real
    // descriptor change; a manual textureRect/contentSize edit breaks equality.
    if (sameAtlas && CGRectEqualToRect(_textureRect, frame.frameRect) &&
        CGSizeEqualToSize(self.contentSize, logical) &&
        CGPointEqualToPoint(_frameOffset, frame.frameOffset) &&
        _rectRotated == frame.rotated) return;
    if (!sameAtlas) {
        SKTexture *source = hasAtlas ? [WhaleySrcTexture(frame.atlasFile) retain] : nil;
        [_sourceTexture release];
        _sourceTexture = source;
        [_atlasFile release];
        _atlasFile = [frame.atlasFile copy];
        _atlasSize = frame.atlasSize;
    }
    _frameOffset = frame.frameOffset;
    [self setTextureRect:frame.frameRect rotated:frame.rotated untrimmedSize:logical];
    [CCCompatTrace record:@"CCSprite.frame"
        detail:[NSString stringWithFormat:@"%@ %@ crop %@ logical %@ offset %@ rotated=%d",
            frame.frameName, frame.atlasFile, NSStringFromCGRect(frame.frameRect),
            NSStringFromCGSize(logical), NSStringFromCGPoint(frame.frameOffset), frame.rotated]];
}

- (void)setTextureRect:(CGRect)rect {
    // cocos2d's simple setter resets logical size and rotation, but retains
    // the last display frame's unflipped offset. It always crops the atlas,
    // NEVER the previously cropped texture.
    [self setTextureRect:rect rotated:NO untrimmedSize:rect.size];
}
- (void)setTextureRect:(CGRect)rect rotated:(BOOL)rotated untrimmedSize:(CGSize)size {
    WhaleyFrameRect region = {0};
    WhaleyFrameRect r = {rect.origin.x, rect.origin.y, rect.size.width, rect.size.height};
    BOOL finite = isfinite(r.x) && isfinite(r.y) && isfinite(r.width) && isfinite(r.height) &&
        r.x >= 0 && r.y >= 0 && r.width >= 0 && r.height >= 0 &&
        isfinite(size.width) && isfinite(size.height) && size.width >= 0 && size.height >= 0;
    if (!finite || (_sourceTexture && !WhaleyFrameRegion(r, rotated,
                                      _atlasSize.width, _atlasSize.height, &region))) {
        [NSException raise:NSInvalidArgumentException format:@"Invalid sprite texture rect %@", NSStringFromCGRect(rect)];
        return;
    }
    SKTexture *texture = nil;
    if (_sourceTexture && rect.size.width > 0 && rect.size.height > 0) {
        texture = [SKTexture textureWithRect:CGRectMake(region.x, region.y, region.width, region.height)
                                  inTexture:_sourceTexture];
        texture.filteringMode = _sourceTexture.filteringMode;
    }
    _textureRect = rect;
    _rectRotated = rotated;
    [super setContentSize:size];
    _spriteKitNode.texture = texture;
    [self cc_updatePresentationTransform];
}
- (void)cc_updatePresentationTransform {
    CGPoint anchor = self.anchorPoint;
    CGSize logical = self.contentSize;
    WhaleyFramePlacement p = WhaleyPlaceFrame(_textureRect.size.width, _textureRect.size.height,
        logical.width, logical.height, _frameOffset.x, _frameOffset.y,
        anchor.x, anchor.y, _flipX, _flipY, _rectRotated);
    _spriteKitNode.anchorPoint = CGPointMake(0.5, 0.5);
    // A missing texture with nonzero size would otherwise draw a white quad.
    _spriteKitNode.size = _spriteKitNode.texture ? CGSizeMake(p.width, p.height) : CGSizeZero;
    _spriteKitNode.position = CGPointMake(p.centerX, p.centerY);
    _spriteKitNode.zRotation = p.quarterTurn ? (CGFloat)M_PI_2 : 0;
    _spriteKitNode.xScale = p.scaleX;
    _spriteKitNode.yScale = p.scaleY;
}
- (void)setAnchorPoint:(CGPoint)v {
    [super setAnchorPoint:v];
    [self cc_updatePresentationTransform];
}
- (void)setContentSize:(CGSize)v {
    [super setContentSize:v];
    [self cc_updatePresentationTransform];
}
- (BOOL)flipX { return _flipX; }
- (void)setFlipX:(BOOL)v {
    _flipX = v;
    [self cc_updatePresentationTransform];
}
- (BOOL)flipY { return _flipY; }
- (void)setFlipY:(BOOL)v {
    _flipY = v;
    [self cc_updatePresentationTransform];
}
- (CCSpriteBatchNode *)batchNode { return _batchNode; }
- (void)setBatchNode:(CCSpriteBatchNode *)v { _batchNode = v; }
- (CGRect)boundingBox {
    return CGRectMake(self.position.x - self.contentSize.width * self.scaleX * self.anchorPoint.x, self.position.y - self.contentSize.height * self.scaleY * self.anchorPoint.y, self.contentSize.width * self.scaleX, self.contentSize.height * self.scaleY);
}
@end
@implementation CCSpriteBatchNode
+ (instancetype)batchNodeWithFile:(NSString *)file {
    return [self new];
}
- (void)addChild:(CCNode *)child z:(NSInteger)z {
    if ([child isKindOfClass:[CCSprite class]]) {
        ((CCSprite *)child).batchNode = self;
    }
    [super addChild:child z:z];
}
- (void)addChild:(CCNode *)child z:(NSInteger)z tag:(NSInteger)tag {
    if ([child isKindOfClass:[CCSprite class]]) {
        ((CCSprite *)child).batchNode = self;
    }
    [super addChild:child z:z tag:tag];
}
@end

@implementation CCAction
- (void)dealloc {
    if (_gameAction) {
        WhaleyReleaseGameAction(_gameAction);
    }
}
@end
@implementation CCFiniteTimeAction
@end
@implementation CCMoveTo
+ (instancetype)actionWithDuration:(ccTime)d position:(CGPoint)p {
    CCMoveTo *a = [self new];
    a.gameAction = WhaleyGameActionMoveTo(p.x, p.y, d);
    [CCCompatTrace record:@"CCMoveTo.lower" detail:NSStringFromCGPoint(p)];
    return a;
}
@end
@implementation CCScaleTo
+ (instancetype)actionWithDuration:(ccTime)d scale:(CGFloat)s {
    CCScaleTo *a = [self new];
    a.gameAction = WhaleyGameActionScaleTo(s, d);
    [CCCompatTrace record:@"CCScaleTo.lower" detail:[NSString stringWithFormat:@"%g", s]];
    return a;
}
@end
@implementation CCRotateBy
+ (instancetype)actionWithDuration:(ccTime)d angle:(CGFloat)angle {
    CCRotateBy *a = [self new];
    a.gameAction = WhaleyGameActionRotateBy(angle, d);
    [CCCompatTrace record:@"CCRotateBy.lower" detail:[NSString stringWithFormat:@"%g", angle]];
    return a;
}
@end
@implementation CCDelayTime
+ (instancetype)actionWithDuration:(ccTime)d {
    CCDelayTime *a = [self new];
    a.gameAction = WhaleyGameActionWait(d);
    [CCCompatTrace record:@"CCDelayTime.lower" detail:[NSString stringWithFormat:@"%g", d]];
    return a;
}
@end
@implementation CCSequence
+ (instancetype)actions:(CCFiniteTimeAction *)first, ... {
    NSMutableArray<CCFiniteTimeAction *> *actions = [NSMutableArray array];
    va_list ap;
    va_start(ap, first);
    for (CCFiniteTimeAction *a = first; a; a = va_arg(ap, CCFiniteTimeAction *)) {
        [actions addObject:a];
    }
    va_end(ap);
    void **raw = calloc(actions.count, sizeof(void *));
    for (NSUInteger i = 0; i < actions.count; i++) {
        raw[i] = actions[i].gameAction;
    }
    CCSequence *r = [self new];
    r.gameAction = WhaleyGameActionSequence(raw, actions.count);
    free(raw);
    [CCCompatTrace record:@"CCSequence.lower" detail:[NSString stringWithFormat:@"%lu", (unsigned long)actions.count]];
    return r;
}
@end
@implementation CCRepeatForever
+ (instancetype)actionWithAction:(CCFiniteTimeAction *)action {
    CCRepeatForever *r = [self new];
    r.gameAction = WhaleyGameActionRepeatForever(action.gameAction);
    [CCCompatTrace record:@"CCRepeatForever.lower" detail:NSStringFromClass(action.class)];
    return r;
}
@end

@implementation CCSpriteFrame
@end

@implementation CCSpriteFrameCache {
    NSMutableDictionary *_frames;
}
+ (instancetype)sharedSpriteFrameCache {
    static CCSpriteFrameCache *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [self new];
    });
    return c;
}
- (instancetype)init {
    if ((self = [super init])) {
        _frames = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (void)dealloc {
    [_frames release];
    [super dealloc];
}
- (void)addSpriteFramesWithFile:(NSString *)file {
    NSString *base = file.stringByDeletingPathExtension;
    NSURL *url = WhaleySrcResourceURL(file);
    NSDictionary *plist = url ? [NSDictionary dictionaryWithContentsOfURL:url] : nil;
    NSDictionary *entries = plist[@"frames"];
    NSDictionary *texture = plist[@"texture"];
    NSString *atlas = [base stringByAppendingPathExtension:@"png"];
    if (!plist) {
        NSInteger count = [base isEqualToString:@"spout"] ? 4 : ([base isEqualToString:@"player-win"] ? 3 : 0);
        for (NSInteger i = 1; i <= count; i++) {
            NSString *name = [NSString stringWithFormat:@"%@%ld.png", base, (long)i];
            CCSpriteFrame *f = [CCSpriteFrame new];
            f.frameName = name;
            f.atlasFile = @"";
            f.frameRect = CGRectZero;
            f.atlasSize = CGSizeZero;
            f.originalSize = CGSizeZero;
            f.frameOffset = CGPointZero;
            f.rotated = NO;
            _frames[name] = f;
            WhaleyRegisterMissingSpriteFrame(name.UTF8String);
            [f release];
        }
        [CCCompatTrace record:@"CCSpriteFrameCache.missingSheet" detail:[NSString stringWithFormat:@"%@ (%ld semantic frames)", file, (long)count]];
        return;
    }
    CGSize atlasSize = CGSizeMake([texture[@"width"] doubleValue], [texture[@"height"] doubleValue]);
    for (NSString *name in entries) {
        NSDictionary *d = entries[name];
        CCSpriteFrame *f = [CCSpriteFrame new];
        f.frameName = name;
        f.atlasFile = atlas;
        f.frameRect = CGRectMake([d[@"x"] doubleValue], [d[@"y"] doubleValue], [d[@"width"] doubleValue], [d[@"height"] doubleValue]);
        f.atlasSize = atlasSize;
        f.frameOffset = CGPointMake([d[@"offsetX"] doubleValue], [d[@"offsetY"] doubleValue]);
        CGFloat originalWidth = d[@"originalWidth"] ? [d[@"originalWidth"] doubleValue] : f.frameRect.size.width;
        CGFloat originalHeight = d[@"originalHeight"] ? [d[@"originalHeight"] doubleValue] : f.frameRect.size.height;
        f.originalSize = CGSizeMake(originalWidth, originalHeight);
        f.rotated = [d[@"rotated"] boolValue];
        _frames[name] = f;
        WhaleyRegisterSpriteFrame(name.UTF8String, atlas.UTF8String, f.frameRect.origin.x, f.frameRect.origin.y, f.frameRect.size.width, f.frameRect.size.height, atlasSize.width, atlasSize.height);
        [f release];
    }
    [CCCompatTrace record:@"CCSpriteFrameCache.add" detail:[NSString stringWithFormat:@"%@ -> %@ (%lu frames)", file, atlas, (unsigned long)entries.count]];
}
- (CCSpriteFrame *)spriteFrameByName:(NSString *)name {
    return _frames[name];
}
- (void)removeUnusedSpriteFrames {
}
@end

@implementation CCAnimation
+ (instancetype)animationWithSpriteFrames:(NSArray<CCSpriteFrame *> *)frames delay:(ccTime)delay {
    CCAnimation *a = [self new];
    a.frames = frames;
    a.delay = delay;
    return [a autorelease];
}
- (void)dealloc {
    [_frames release];
    [super dealloc];
}
@end

@implementation CCAnimate
+ (instancetype)actionWithAnimation:(CCAnimation *)animation {
    NSUInteger count = animation.frames.count;
    const char **names = calloc(count, sizeof(char *));
    for (NSUInteger i = 0; i < count; i++) {
        names[i] = animation.frames[i].frameName.UTF8String;
    }
    CCAnimate *a = [self new];
    a.gameAction = WhaleyGameActionAnimate(names, count, animation.delay);
    free(names);
    [CCCompatTrace record:@"CCAnimate.lower" detail:[NSString stringWithFormat:@"%lu frames", (unsigned long)count]];
    return [a autorelease];
}
@end

@implementation CCTMXObjectGroup
- (NSDictionary *)objectNamed:(NSString *)name {
    for (NSDictionary *o in self.objects) {
        if ([o[@"name"] isEqual:name]) {
            return o;
        }
    }
    return nil;
}
@end

static NSData *CCGunzip(NSData *compressed) {
    if (compressed.length == 0) {
        return [NSData data];
    }
    z_stream stream = {0};
    stream.next_in = (Bytef *)compressed.bytes;
    stream.avail_in = (uInt)compressed.length;
    if (inflateInit2(&stream, 15 + 32) != Z_OK) {
        return nil;
    }
    NSMutableData *result = [NSMutableData dataWithLength:MAX((NSUInteger)4096, compressed.length * 3)];
    int status;
    do {
        if (stream.total_out >= result.length) {
            [result increaseLengthBy:MAX((NSUInteger)4096, compressed.length)];
        }
        stream.next_out = (Bytef *)result.mutableBytes + stream.total_out;
        stream.avail_out = (uInt)(result.length - stream.total_out);
        status = inflate(&stream, Z_NO_FLUSH);
    } while (status == Z_OK);
    inflateEnd(&stream);
    if (status != Z_STREAM_END) {
        return nil;
    }
    result.length = stream.total_out;
    return result;
}

@class CCTMXTiledMap;
@interface CCTMXParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, assign) CCTMXTiledMap *map;
@property (nonatomic) NSInteger firstGID;
@property (nonatomic) NSInteger currentTileGID;
@property (nonatomic, copy) NSString *currentLayer;
@property (nonatomic, strong) NSMutableString *layerData;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *groups;
@property (nonatomic, copy) NSString *currentGroup;
@property (nonatomic, strong) NSMutableDictionary *currentObject;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableDictionary *> *gidProperties;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *decodedLayers;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *visualTilesets;
@property (nonatomic, strong) NSMutableDictionary *currentTileset;
@end

@interface CCTMXLayer ()
@property (nonatomic, copy, readwrite) NSString *layerName;
@property (nonatomic, assign) void *tileMapBox;
@property (nonatomic) CGSize compatTileSize;
@property (nonatomic, strong) SKTexture *visualAtlas;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SKSpriteNode *> *visibleTiles;
@property (nonatomic) NSInteger firstVisualGID;
@property (nonatomic) CGFloat visualMargin;
@property (nonatomic) CGFloat visualSpacing;
@property (nonatomic) CGSize visualPixelSize;
@property (nonatomic, strong) NSData *sourceGIDs;
- (void)buildVisualTiles:(NSDictionary *)spec;
- (void)updateVisualTileAt:(CGPoint)coordinate;
@end

@interface CCTMXTiledMap ()
@property (nonatomic, assign) void *tileMapBox;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CCTMXLayer *> *compatLayers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CCTMXObjectGroup *> *compatGroups;
@property (nonatomic, strong) NSDictionary<NSNumber *, NSDictionary *> *compatGIDProperties;
@end

@implementation CCTMXParser
- (instancetype)init {
    if ((self = [super init])) {
        self.groups = [NSMutableDictionary dictionary];
        self.gidProperties = [NSMutableDictionary dictionary];
        self.decodedLayers = [NSMutableArray array];
        self.visualTilesets = [NSMutableArray array];
        _currentTileGID = -1;
    }
    return self;
}
- (void)dealloc {
    [_currentLayer release];
    [_layerData release];
    [_groups release];
    [_currentGroup release];
    [_currentObject release];
    [_gidProperties release];
    [_decodedLayers release];
    [_visualTilesets release];
    [_currentTileset release];
    [super dealloc];
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *, NSString *> *)a {
    if ([element isEqual:@"map"]) {
        self.map.mapSize = CGSizeMake(a[@"width"].doubleValue, a[@"height"].doubleValue);
        self.map.tileSize = CGSizeMake(a[@"tilewidth"].doubleValue, a[@"tileheight"].doubleValue);
    } else if ([element isEqual:@"tileset"]) {
        self.firstGID = a[@"firstgid"].integerValue;
        self.currentTileset = [[@{
            @"firstgid": @(self.firstGID),
            @"margin": @([a[@"margin"] doubleValue]),
            @"spacing": @([a[@"spacing"] doubleValue])
        } mutableCopy] autorelease];
    } else if ([element isEqual:@"image"] && self.currentTileset) {
        self.currentTileset[@"source"] = a[@"source"] ?: @"";
        [self.visualTilesets addObject:[[self.currentTileset copy] autorelease]];
    } else if ([element isEqual:@"tile"]) {
        self.currentTileGID = self.firstGID + a[@"id"].integerValue;
        self.gidProperties[@(self.currentTileGID)] = [NSMutableDictionary dictionary];
    } else if ([element isEqual:@"layer"]) {
        self.currentLayer = a[@"name"];
    } else if ([element isEqual:@"data"] && self.currentLayer) {
        self.layerData = [NSMutableString string];
    } else if ([element isEqual:@"objectgroup"]) {
        self.currentGroup = a[@"name"];
        self.groups[self.currentGroup] = [NSMutableArray array];
    } else if ([element isEqual:@"object"] && self.currentGroup) {
        self.currentObject = [NSMutableDictionary dictionary];
        for (NSString *key in @[ @"name", @"x", @"y", @"width", @"height" ]) {
            if (a[key]) {
                self.currentObject[key] = a[key];
            }
        }
    } else if ([element isEqual:@"property"]) {
        NSString *name = a[@"name"], *value = a[@"value"] ?: @"";
        if (self.currentObject) {
            self.currentObject[name] = value;
        } else if (self.currentTileGID >= 0) {
            self.gidProperties[@(self.currentTileGID)][name] = value;
        }
    }
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (self.layerData) {
        [self.layerData appendString:string];
    }
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)qName {
    if ([element isEqual:@"data"] && self.layerData) {
        NSString *compact = [[self.layerData componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
        NSData *encoded = [[NSData alloc] initWithBase64EncodedString:compact options:0];
        NSData *raw = CCGunzip(encoded);
        NSUInteger expected = (NSUInteger)(self.map.mapSize.width * self.map.mapSize.height);
        NSMutableData *gids = [NSMutableData dataWithLength:expected * sizeof(uint32_t)];
        if (raw.length >= gids.length) {
            const uint8_t *bytes = raw.bytes;
            uint32_t *out = gids.mutableBytes;
            for (NSUInteger i = 0; i < expected; i++) {
                out[i] = (uint32_t)bytes[i * 4] | ((uint32_t)bytes[i * 4 + 1] << 8) | ((uint32_t)bytes[i * 4 + 2] << 16) | ((uint32_t)bytes[i * 4 + 3] << 24);
            }
            [self.decodedLayers addObject:@{@"name" : self.currentLayer, @"gids" : gids}];
        }
        self.layerData = nil;
    } else if ([element isEqual:@"layer"]) {
        self.currentLayer = nil;
    } else if ([element isEqual:@"tile"]) {
        self.currentTileGID = -1;
    } else if ([element isEqual:@"tileset"]) {
        self.currentTileset = nil;
    } else if ([element isEqual:@"object"] && self.currentObject) {
        CGFloat h = [self.currentObject[@"height"] doubleValue];
        CGFloat rawY = [self.currentObject[@"y"] doubleValue];
        self.currentObject[@"y"] = @(self.map.mapSize.height * self.map.tileSize.height - rawY - h);
        [self.groups[self.currentGroup] addObject:self.currentObject];
        self.currentObject = nil;
    } else if ([element isEqual:@"objectgroup"]) {
        self.currentGroup = nil;
    }
}
@end

@implementation CCTMXLayer
- (void)dealloc {
    [_visibleTiles release];
    [_visualAtlas release];
    [_sourceGIDs release];
    [_layerName release];
    [super dealloc];
}

// The original compatibility parser retained collision GIDs but painted no
// visible tiles. Render the Background layer from its real TMX tileset atlas.
// The Meta layer remains authoritative for collision and is never displayed.
- (void)buildVisualTiles:(NSDictionary *)spec {
    NSString *filename = spec[@"source"];
    NSURL *url = filename.length ? WhaleySrcResourceURL(filename) : nil;
    UIImage *image = url ? [UIImage imageWithContentsOfFile:url.path] : nil;
    if (!image || !image.CGImage || !self.parent) {
        NSLog(@"Whaley visible tiles missing image: %@", filename);
        return;
    }
    // Use actual PNG pixel dimensions. SKTexture.size can report a scaled
    // point size depending on the image's scale, breaking TMX atlas UVs.
    self.visualPixelSize = CGSizeMake(CGImageGetWidth(image.CGImage),
                                      CGImageGetHeight(image.CGImage));
    self.visualAtlas = [SKTexture textureWithImage:image];
    self.visualAtlas.filteringMode = SKTextureFilteringNearest;
    self.firstVisualGID = [spec[@"firstgid"] integerValue];
    self.visualMargin = [spec[@"margin"] doubleValue];
    self.visualSpacing = [spec[@"spacing"] doubleValue];
    self.visibleTiles = [NSMutableDictionary dictionary];
    CCTMXTiledMap *map = (CCTMXTiledMap *)self.parent;
    for (NSInteger row = 0; row < (NSInteger)map.mapSize.height; ++row) {
        for (NSInteger col = 0; col < (NSInteger)map.mapSize.width; ++col) {
            [self updateVisualTileAt:CGPointMake(col, row)];
        }
    }
    // Opt-in, bounded trace: resource resolution, atlas dimensions and
    // drawable count at the first relevant rendering boundary. Source data
    // counts alone never prove that pixels were rendered.
    NSArray<NSNumber *> *keys = [[self.visibleTiles allKeys]
        sortedArrayUsingSelector:@selector(compare:)];
    SKSpriteNode *first = keys.count ? self.visibleTiles[keys.firstObject] : nil;
    [CCCompatTrace record:@"CCTMXLayer.visual.summary"
        detail:[NSString stringWithFormat:
            @"layer=%@ atlas=%@ pixels=%.0fx%.0f tile=%.0fx%.0f drawables=%lu firstPoint=%@",
            self.layerName, filename, self.visualPixelSize.width,
            self.visualPixelSize.height, map.tileSize.width, map.tileSize.height,
            (unsigned long)self.visibleTiles.count,
            first ? NSStringFromCGPoint(first.position) : @"none"]];
}
- (void)updateVisualTileAt:(CGPoint)coord {
    if (!self.visualAtlas || !self.parent || !self.tileMapBox) return;
    CCTMXTiledMap *map = (CCTMXTiledMap *)self.parent;
    NSInteger cols = (NSInteger)map.mapSize.width;
    NSNumber *key = @((NSInteger)coord.y * cols + (NSInteger)coord.x);
    SKSpriteNode *old = self.visibleTiles[key];
    [old removeFromParent];
    [self.visibleTiles removeObjectForKey:key];

    uint32_t encoded = WhaleyTileMapGID(self.tileMapBox, self.layerName.UTF8String,
                                       (int)coord.x, (int)coord.y);
    NSUInteger offset = (NSUInteger)((NSInteger)coord.y * cols + (NSInteger)coord.x);
    if (self.sourceGIDs && self.sourceGIDs.length >= (offset + 1) * sizeof(uint32_t)) {
        encoded = ((const uint32_t *)self.sourceGIDs.bytes)[offset];
    }
    NSInteger gid = encoded & 0x1FFFFFFF; // TMX's three flip flags
    if (gid < self.firstVisualGID) return;
    CGSize tile = map.tileSize;
    CGSize sheet = self.visualPixelSize;
    NSInteger columns = MAX(1, (NSInteger)floor((sheet.width - 2 * self.visualMargin +
                                            self.visualSpacing) / (tile.width + self.visualSpacing)));
    NSInteger index = gid - self.firstVisualGID;
    CGFloat x = self.visualMargin + (index % columns) * (tile.width + self.visualSpacing);
    CGFloat y = self.visualMargin + (index / columns) * (tile.height + self.visualSpacing);
    if (x < 0 || y < 0 || x + tile.width > sheet.width || y + tile.height > sheet.height) return;
    CGRect region = CGRectMake(x / sheet.width,
                               1.0 - (y + tile.height) / sheet.height,
                               tile.width / sheet.width, tile.height / sheet.height);
    SKTexture *texture = [SKTexture textureWithRect:region inTexture:self.visualAtlas];
    texture.filteringMode = self.visualAtlas.filteringMode;
    SKSpriteNode *sprite = [SKSpriteNode spriteNodeWithTexture:texture size:tile];
    sprite.position = CGPointMake((coord.x + 0.5) * tile.width,
                                  (map.mapSize.height - coord.y - 0.5) * tile.height);
    if (encoded & 0x80000000u) sprite.xScale = -1;
    if (encoded & 0x40000000u) sprite.yScale = -1;
    if (encoded & 0x20000000u) sprite.zRotation = (CGFloat)M_PI_2;
    [self addChild:sprite];
    self.visibleTiles[key] = sprite;
}
- (NSInteger)tileGIDAt:(CGPoint)tileCoord {
    if (!self.tileMapBox) {
        return 0;
    }
    NSInteger gid = (NSInteger)WhaleyTileMapGID(self.tileMapBox, self.layerName.UTF8String, (int)tileCoord.x, (int)tileCoord.y);
    [CCCompatTrace record:@"CCTMXLayer.tileGIDAt" detail:[NSString stringWithFormat:@"%@ (%ld,%ld) -> %ld", self.layerName, (long)tileCoord.x, (long)tileCoord.y, (long)gid]];
    return gid;
}
- (void)setTileGID:(NSInteger)gid at:(CGPoint)tileCoord {
    if (!self.tileMapBox) {
        return;
    }
    WhaleyTileMapSetGID(self.tileMapBox, self.layerName.UTF8String, (int)tileCoord.x, (int)tileCoord.y, (uint32_t)MAX(0, gid));
    // Subsequent edits must read the modified authoritative map, not the
    // initial snapshot from the TMX document.
    self.sourceGIDs = nil;
    [self updateVisualTileAt:tileCoord];
}
- (CCSprite *)tileAt:(CGPoint)tileCoord {
    if ([self tileGIDAt:tileCoord] == 0) {
        return nil;
    }
    CCSprite *tile = [CCSprite new];
    tile.contentSize = self.compatTileSize;
    tile.anchorPoint = CGPointZero;
    tile.position = CGPointMake(tileCoord.x * self.compatTileSize.width,
                                (self.parent ? ((CCTMXTiledMap *)self.parent).mapSize.height - 1 - tileCoord.y : 0) * self.compatTileSize.height);
    return [tile autorelease];
}
@end

@implementation CCTMXTiledMap
+ (instancetype)tiledMapWithTMXFile:(NSString *)file {
    CCTMXTiledMap *map = [self new];
    NSString *base = file.stringByDeletingPathExtension;
    NSString *ext = file.pathExtension.length ? file.pathExtension : @"tmx";
    NSURL *url = WhaleySrcResourceURL(file);
    if (!url && [base hasPrefix:@"level"]) {
        url = WhaleySrcResourceURL([@"original-" stringByAppendingString:file]);
    }
    NSAssert(url != nil, @"TMX resource %@ not found", file);
    CCTMXParser *delegate = [CCTMXParser new];
    delegate.map = map;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithContentsOfURL:url];
    parser.delegate = delegate;
    BOOL ok = [parser parse];
    NSAssert(ok, @"Unable to parse %@: %@", file, parser.parserError);
    map.tileMapBox = WhaleyTileMapCreate((int)map.mapSize.width, (int)map.mapSize.height, map.tileSize.width, map.tileSize.height);
    map.compatLayers = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in delegate.decodedLayers) {
        NSString *name = entry[@"name"];
        NSData *data = entry[@"gids"];
        WhaleyTileMapSetLayer(map.tileMapBox, name.UTF8String, data.bytes, data.length / sizeof(uint32_t));
        CCTMXLayer *layer = [CCTMXLayer new];
        layer.layerName = name;
        layer.tileMapBox = map.tileMapBox;
        layer.compatTileSize = map.tileSize;
        [map addChild:layer];
        map.compatLayers[name] = layer;
        [layer release];
    }
    map.compatGroups = [NSMutableDictionary dictionary];
    [delegate.groups enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSMutableArray *objects, BOOL *stop) {
        CCTMXObjectGroup *group = [CCTMXObjectGroup new];
        group.objects = objects;
        map.compatGroups[name] = group;
        [group release];
    }];
    map.compatGIDProperties = delegate.gidProperties;
    // The Background layer, not the Meta collision layer, determines visible
    // tiles. Retain its decoded GIDs so painting doesn't depend on the
    // independently bridged collision/analytics tile map.
    NSDictionary *visualSpec = delegate.visualTilesets.firstObject;
    CCTMXLayer *background = map.compatLayers[@"Background"];
    for (NSDictionary *entry in delegate.decodedLayers) {
        if ([entry[@"name"] isEqualToString:@"Background"]) {
            background.sourceGIDs = entry[@"gids"];
            break;
        }
    }
    if (visualSpec && background) {
        [background buildVisualTiles:visualSpec];
        [CCCompatTrace record:@"CCTMXTiledMap.visualTiles"
            detail:[NSString stringWithFormat:@"%@: %lu sprites", file,
                (unsigned long)background.visibleTiles.count]];
    }
    [CCCompatTrace record:@"CCTMXTiledMap.load" detail:[NSString stringWithFormat:@"%@ %gx%g", file, map.mapSize.width, map.mapSize.height]];
    [parser release];
    [delegate release];
    return [map autorelease];
}
- (void)dealloc {
    if (_tileMapBox) {
        WhaleyReleaseTileMap(_tileMapBox);
    }
    [_compatLayers release];
    [_compatGroups release];
    [_compatGIDProperties release];
    [super dealloc];
}
- (CCTMXLayer *)layerNamed:(NSString *)name {
    return self.compatLayers[name];
}
- (CCTMXObjectGroup *)objectGroupNamed:(NSString *)name {
    return self.compatGroups[name];
}
- (NSDictionary *)propertiesForGID:(NSInteger)gid {
    return self.compatGIDProperties[@(gid)];
}
@end
@implementation CCDirector {
    CGSize _compatWinSize;
    CGSize _compatViewSize;
}
+ (instancetype)sharedDirector {
    static CCDirector *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [self new];
        d->_compatWinSize = CGSizeMake(320, 568);
    });
    return d;
}
- (CGSize)winSize {
    return _compatWinSize;
}
- (void)setCompatWinSize:(CGSize)size {
    _compatWinSize = size;
}
- (void)setCompatViewSize:(CGSize)size {
    _compatViewSize = size;
}
- (CGSize)compatViewSize {
    return _compatViewSize;
}
@end

@implementation CCLayerColor
+ (instancetype)layerWithColor:(ccColor4B)c width:(CGFloat)w height:(CGFloat)h {
    CCLayerColor *l = [[[self alloc] init] autorelease];
    l.contentSize = CGSizeMake(w, h);
    SKShapeNode *fill = [SKShapeNode shapeNodeWithRect:CGRectMake(0, 0, w, h)];
    fill.fillColor = [UIColor colorWithRed:c.r / 255.0
                                    green:c.g / 255.0
                                     blue:c.b / 255.0
                                    alpha:c.a / 255.0];
    fill.strokeColor = UIColor.clearColor;
    fill.lineWidth = 0;
    [l addChild:fill];
    return l;
}
@end
@implementation CCTouchDispatcher {
    id _targetedDelegate;
    BOOL _swallowsTouches;
}
- (void)addTargetedDelegate:(id)delegate priority:(NSInteger)priority swallowsTouches:(BOOL)swallowsTouches {
    _targetedDelegate = delegate;
    _swallowsTouches = swallowsTouches;
    [CCCompatTrace record:@"touch.delegate" detail:NSStringFromClass([delegate class])];
}
- (BOOL)dispatchTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
    if ([_targetedDelegate respondsToSelector:@selector(ccTouchBegan:withEvent:)]) {
        return ((BOOL (*)(id, SEL, UITouch *, UIEvent *))objc_msgSend)(_targetedDelegate, @selector(ccTouchBegan:withEvent:), touch, event);
    }
    return NO;
}
- (void)dispatchTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
    if ([_targetedDelegate respondsToSelector:@selector(ccTouchMoved:withEvent:)]) {
        ((void (*)(id, SEL, UITouch *, UIEvent *))objc_msgSend)(_targetedDelegate, @selector(ccTouchMoved:withEvent:), touch, event);
    }
}
- (void)dispatchTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    if ([_targetedDelegate respondsToSelector:@selector(ccTouchEnded:withEvent:)]) {
        ((void (*)(id, SEL, UITouch *, UIEvent *))objc_msgSend)(_targetedDelegate, @selector(ccTouchEnded:withEvent:), touch, event);
    }
}
- (void)dispatchTouchCancelled:(UITouch *)touch withEvent:(UIEvent *)event {
    if ([_targetedDelegate respondsToSelector:@selector(ccTouchCancelled:withEvent:)]) {
        ((void (*)(id, SEL, UITouch *, UIEvent *))objc_msgSend)(_targetedDelegate, @selector(ccTouchCancelled:withEvent:), touch, event);
    } else {
        [self dispatchTouchEnded:touch withEvent:event];
    }
}
@end
#endif