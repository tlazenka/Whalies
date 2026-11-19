#if __has_include(<UIKit/UIKit.h>)
#import <objc/message.h>
#import <objc/runtime.h>
#import "WhaleyRuntimeBridge.h"
#import "WhaleyDisplayClock.h"
#import "WhaleySceneLifecycle.h"
#import "cocos2d.h"
#import "WhaleyScene.h"
#import "SimpleAudioEngine.h"

typedef struct {
    id target;
    SEL selector;
} WhaleyObjCActionContext;
static void WhaleyInvokeAction(void *rawContext, void *rawNode) {
    WhaleyObjCActionContext *context = rawContext;
    id node = (id)rawNode;
    ((void (*)(id, SEL, id))objc_msgSend)(context->target, context->selector, node);
    [context->target release];
    free(context);
}

@class WhaleySchedulerDriver;
@interface WhaleyDisplayLinkTarget : NSObject
@property (nonatomic, assign) WhaleySchedulerDriver *driver;
- (void)tick:(CADisplayLink *)link;
@end

@interface WhaleySchedulerDriver : NSObject {
    NSHashTable *_layerReference;
    void *_scheduler;
    CADisplayLink *_displayLink;
    WhaleyDisplayLinkTarget *_displayTarget;
    NSMutableDictionary<NSString *, NSValue *> *_contexts;
    WhaleyDisplayClock _clock;
    uint64_t _tickSequence;
    BOOL _seenScene;
    BOOL _invalidated;
    BOOL _advancing;
    BOOL _foreground;
}
@property (nonatomic, readonly) CCLayer *layer;
@property (nonatomic, readonly) BOOL invalidated;
- (instancetype)initWithLayer:(CCLayer *)layer;
- (void)tick:(CADisplayLink *)link;
- (void)scheduleSelector:(SEL)selector interval:(ccTime)interval;
- (void)unscheduleSelector:(SEL)selector;
- (void)invalidate;
- (void)disposeScheduler;
- (BOOL)canInvoke;
- (void)invokeContext:(void *)context delta:(double)delta;
@end

// The layer owns its driver. Neither this registry nor CADisplayLink owns the
// layer; a removed level cannot survive solely because of its scheduler.
static char WhaleySchedulerAssociation;
static NSHashTable *WhaleySchedulerDrivers(void) {
    static NSHashTable *drivers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ drivers = [[NSHashTable weakObjectsHashTable] retain]; });
    return drivers;
}

static void WhaleyStopLayerSounds(CCLayer *layer) {
    if (![layer isKindOfClass:[Whaley class]]) return;
    Whaley *game = (Whaley *)layer;
    [game.bgSound stop];
    [game.bounceSound stop];
    [game.flameSound stop];
    [game.jumpSound stop];
    [game.collectibleSound stop];
    [game.goalSound stop];
}

typedef struct {
    WhaleySchedulerDriver *driver; // owned by the layer, not retained by C context
    SEL selector;
    uint64_t scheduleID;
    uint64_t lastTickSequence;
} WhaleyScheduleContext;

static void WhaleyInvokeScheduledSelector(void *rawContext, double dt) {
    WhaleyScheduleContext *context = rawContext;
    [context->driver invokeContext:context delta:dt];
}

@implementation WhaleyDisplayLinkTarget
- (void)tick:(CADisplayLink *)link {
    // A callback may replace the level and release its associated driver.
    WhaleySchedulerDriver *driver = [self.driver retain];
    @try { [driver tick:link]; }
    @finally { [driver release]; }
}
@end

@implementation WhaleySchedulerDriver
- (instancetype)initWithLayer:(CCLayer *)layer {
    if ((self = [super init])) {
        _layerReference = [[NSHashTable weakObjectsHashTable] retain];
        [_layerReference addObject:layer];
        _scheduler = WhaleySchedulerCreate();
        _contexts = [[NSMutableDictionary alloc] init];
        _foreground = UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
        _displayTarget = [WhaleyDisplayLinkTarget new];
        _displayTarget.driver = self;
        _displayLink = [[CADisplayLink displayLinkWithTarget:_displayTarget selector:@selector(tick:)] retain];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(suspend:)
            name:UIApplicationWillResignActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume:)
            name:UIApplicationDidBecomeActiveNotification object:nil];
        [WhaleySchedulerDrivers() addObject:self];
    }
    return self;
}
- (CCLayer *)layer { return _layerReference.anyObject; }
- (BOOL)invalidated { return _invalidated; }
- (void)suspend:(NSNotification *)notification {
    _foreground = NO;
    WhaleyDisplayClockSuspend(&_clock);
    WhaleyStopLayerSounds(self.layer);
}
- (void)resume:(NSNotification *)notification {
    _foreground = YES;
    WhaleyDisplayClockSuspend(&_clock); // Never catch up background time.
}
- (BOOL)canInvoke {
    CCLayer *layer = self.layer;
    SKScene *scene = layer.scene;
    if (_invalidated || !_foreground || !layer || !scene) return NO;
    if (scene.view && (scene.view.scene != scene || scene.view.paused)) return NO;
    for (SKNode *node = layer; node; node = node.parent) {
        if (node.paused) return NO;
    }
    return YES;
}
- (void)tick:(CADisplayLink *)link {
    if (_invalidated) return;
    CCLayer *layer = [self.layer retain];
    @try {
        if (!layer || (_seenScene && !layer.scene)) {
            [self invalidate];
            return;
        }
        if (layer.scene) _seenScene = YES;
        double delta = WhaleyDisplayClockAdvance(&_clock, link.timestamp, [self canInvoke]);
        if (delta <= 0) return;
        ++_tickSequence;
        _advancing = YES;
        @try { WhaleySchedulerAdvance(_scheduler, delta); }
        @finally {
            _advancing = NO;
            // A callback may have requested teardown. The Swift scheduler box
            // must remain alive until its current advance has returned.
            if (_invalidated) [self disposeScheduler];
        }
    } @finally { [layer release]; }
}
- (void)invokeContext:(void *)rawContext delta:(double)delta {
    WhaleyScheduleContext *context = rawContext;
    if (![self canInvoke]) return;
    // A stalled frame can contain several elapsed beats. Keep the scheduler's
    // phase but never emit a burst of overdue anvil strikes on one frame.
    if (context->selector == @selector(playBg:)) {
        if (context->lastTickSequence == _tickSequence) return;
        context->lastTickSequence = _tickSequence;
    }
    CCLayer *layer = [self.layer retain];
    SEL selector = context->selector;
    @try {
        ((void (*)(id, SEL, ccTime))objc_msgSend)(layer, selector, (ccTime)delta);
    } @finally { [layer release]; }
    // Do not touch context here: the callback may have unscheduled itself.
}
- (void)scheduleSelector:(SEL)selector interval:(ccTime)interval {
    NSParameterAssert(interval > 0);
    if (_invalidated) return;
    NSString *key = NSStringFromSelector(selector);
    [self unscheduleSelector:selector];
    WhaleyScheduleContext *context = calloc(1, sizeof(*context));
    context->driver = self;
    context->selector = selector;
    context->scheduleID = WhaleySchedulerSchedule(_scheduler, interval, context, WhaleyInvokeScheduledSelector);
    _contexts[key] = [NSValue valueWithPointer:context];
    [CCCompatTrace record:@"schedule.lower" detail:[NSString stringWithFormat:@"%@ @ %.6g", key, interval]];
}
- (void)unscheduleSelector:(SEL)selector {
    NSString *key = NSStringFromSelector(selector);
    WhaleyScheduleContext *context = [_contexts[key] pointerValue];
    if (!context) return;
    WhaleySchedulerCancel(_scheduler, context->scheduleID);
    [_contexts removeObjectForKey:key];
    free(context);
    [CCCompatTrace record:@"unschedule.lower" detail:key];
}
- (void)disposeScheduler {
    if (!_scheduler) return;
    // Unregister callbacks before releasing their contexts.
    WhaleyReleaseScheduler(_scheduler);
    _scheduler = NULL;
    for (NSValue *value in _contexts.allValues) free(value.pointerValue);
    [_contexts removeAllObjects];
}
- (void)invalidate {
    if (_invalidated) return;
    _invalidated = YES;
    _displayTarget.driver = nil;
    [_displayLink invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    WhaleyDisplayClockSuspend(&_clock);
    WhaleyStopLayerSounds(self.layer);
    [WhaleySchedulerDrivers() removeObject:self];
    if (!_advancing) [self disposeScheduler];
}
- (void)dealloc {
    // The association can be released during layer teardown; don't access it.
    [_layerReference removeAllObjects];
    [self invalidate];
    [_displayLink release];
    [_displayTarget release];
    [_layerReference release];
    [_contexts release];
    [super dealloc];
}
@end

void WhaleyStopSceneSchedules(SKNode *root) {
    NSCAssert(NSThread.isMainThread, @"Scene teardown belongs to the main thread");
    if (!root) return;
    WhaleySchedulerDriver *driver = objc_getAssociatedObject(root, &WhaleySchedulerAssociation);
    [driver invalidate];
    if ([root isKindOfClass:[CCLayer class]]) WhaleyStopLayerSounds((CCLayer *)root);
    for (SKNode *child in root.children) WhaleyStopSceneSchedules(child);
}

void WhaleyStopDetachedSchedules(void) {
    NSCAssert(NSThread.isMainThread, @"Scene teardown belongs to the main thread");
    for (WhaleySchedulerDriver *driver in WhaleySchedulerDrivers().allObjects) {
        if (!driver.layer.scene) [driver invalidate];
    }
}

@implementation CCLayer (SrcScheduling)
- (void)schedule:(SEL)selector {
    [self schedule:selector interval:1.0 / 60.0];
}
- (void)schedule:(SEL)selector interval:(ccTime)interval {
    WhaleySchedulerDriver *driver = objc_getAssociatedObject(self, &WhaleySchedulerAssociation);
    if (!driver || driver.invalidated) {
        driver = [[[WhaleySchedulerDriver alloc] initWithLayer:self] autorelease];
        objc_setAssociatedObject(self, &WhaleySchedulerAssociation, driver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [driver scheduleSelector:selector interval:interval];
}
- (void)unschedule:(SEL)selector {
    WhaleySchedulerDriver *driver = objc_getAssociatedObject(self, &WhaleySchedulerAssociation);
    [driver unscheduleSelector:selector];
}
- (void)registerWithTouchDispatcher {
}
@end

@implementation CCSprite (SrcAppearance)
- (GLubyte)opacity {
    // Fade actions run on the logical wrapper. Keep writes and readback there.
    return (GLubyte)lrint(MAX(0, MIN(1, self.alpha)) * 255.0);
}
- (void)setOpacity:(GLubyte)o {
    self.alpha = (CGFloat)o / 255.0;
}
- (ccColor3B)color {
    // The actual drawable's tint is authoritative, not a second cached value.
    CGFloat r = 1, g = 1, b = 1, a = 1;
    if (![self.spriteKitNode.color getRed:&r green:&g blue:&b alpha:&a]) return ccWHITE;
    return ccc3((uint8_t)lrint(MAX(0, MIN(1, r)) * 255),
                (uint8_t)lrint(MAX(0, MIN(1, g)) * 255),
                (uint8_t)lrint(MAX(0, MIN(1, b)) * 255));
}
- (void)setColor:(ccColor3B)c {
    self.spriteKitNode.color = [UIColor colorWithRed:c.r / 255.0 green:c.g / 255.0 blue:c.b / 255.0 alpha:1];
    self.spriteKitNode.colorBlendFactor = 1;
}
@end
@implementation CCFadeTo
+ (instancetype)actionWithDuration:(ccTime)d opacity:(GLubyte)o {
    CCFadeTo *a = [self new];
    a.gameAction = WhaleyGameActionFade(d, (double)o / 255.0);
    return [a autorelease];
}
@end
@implementation CCCallFuncN
+ (instancetype)actionWithTarget:(id)target selector:(SEL)selector {
    CCCallFuncN *action = [self new];
    WhaleyObjCActionContext *context = calloc(1, sizeof(*context));
    context->target = [target retain];
    context->selector = selector;
    uint64_t callbackID = WhaleyRegisterActionCallback(context, WhaleyInvokeAction);
    action.gameAction = WhaleyGameActionCallback(callbackID);
    [CCCompatTrace record:@"CCCallFuncN.lower" detail:NSStringFromSelector(selector)];
    return [action autorelease];
}
@end
@implementation CCDirector (SrcInput)
- (CCTouchDispatcher *)touchDispatcher {
    static CCTouchDispatcher *d;
    if (!d) {
        d = [CCTouchDispatcher new];
    }
    return d;
}
- (CGPoint)convertToGL:(CGPoint)p {
    CGSize logical = self.winSize;
    CGSize view = self.compatViewSize;
    if (view.width <= 0 || view.height <= 0) {
        view = UIScreen.mainScreen.bounds.size;
    }
    // The iOS SKScenes use AspectFit to preserve both walls and the whole menu.
    // Match SpriteKit's letterboxing when converting UIKit touches to scene space.
    CGFloat scale = MIN(view.width / logical.width, view.height / logical.height);
    CGFloat ox = (view.width - logical.width * scale) / 2.0;
    CGFloat oy = (view.height - logical.height * scale) / 2.0;
    return CGPointMake((p.x - ox) / scale, logical.height - ((p.y - oy) / scale));
}
@end
#endif
