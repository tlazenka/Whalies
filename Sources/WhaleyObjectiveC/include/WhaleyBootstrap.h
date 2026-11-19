#if __has_include(<UIKit/UIKit.h>)
#import <SpriteKit/SpriteKit.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

void WhaleySrcSetResourceBundle(NSBundle *bundle);
NSBundle *WhaleySrcResourceBundle(void);
BOOL WhaleySrcUsesWhalelandArt(void);
NSURL *_Nullable WhaleySrcResourceURL(NSString *filename);
SKTexture *WhaleySrcTexture(NSString *filename);

SKScene *WhaleyCreateSrcMainMenuScene(void);
void WhaleySrcShowMainMenu(void);
void WhaleySrcStartLevel(NSInteger levelNumber, NSInteger mode);
BOOL WhaleySrcIsMainMenuVisible(void);
SKScene *WhaleyCreateSrcLevelScene(NSInteger levelNumber);
SKScene *WhaleyCreateSrcLevelOneScene(void);
SKScene *WhaleyCreateSrcLevelTwoScene(void);

// Embedded displays use the same scene, scheduler, collision rules and assets.
// A single native host owns the process-wide legacy director at a time.
SKScene *WhaleyCreateSrcEmbeddedLevelScene(NSInteger levelNumber, CGSize logicalSize);
SKScene *WhaleyCreateSrcEmbeddedLevelSceneWithSoundEffects(NSInteger levelNumber, CGSize logicalSize, BOOL soundEffectsEnabled);
// False for a stale/disposed host. Retries and level changes retain this policy.
BOOL WhaleySrcHostSoundEffectsEnabled(SKScene *host);
// Updates an owned host in place, stopping current effects when disabled.
// Re-enabling permits future playback; it does not replay muted sounds.
void WhaleySrcSetHostSoundEffectsEnabled(SKScene *host, BOOL enabled);
void WhaleySrcDisposeHost(SKScene *host);
void WhaleySrcSetHostSuspended(SKScene *host, BOOL suspended);
// Input dictionaries: id, x/y (screen-space center from bottom-left), diameter,
// remainingUses, fixed and held. The containing world draws these projectiles.
void WhaleySrcSetExternalProjectiles(NSArray<NSDictionary<NSString *, id> *> *projectiles);
NSDictionary<NSString *, id> *WhaleySrcHostState(void);
// Drains events observed at the real engine outcome sites; never advances time.
NSArray<NSDictionary<NSString *, id> *> *WhaleySrcDrainGameEvents(void);

void WhaleySrcSetCompatViewSize(CGSize size);
// Persist the preference and update the active level immediately. New levels
// read the same preference; overlays are off for a fresh installation.
BOOL WhaleySrcTileDebugOverlaysEnabled(void);
void WhaleySrcSetTileDebugOverlaysEnabled(BOOL enabled);
void WhaleySrcSetSuppressedFlames(NSArray<NSNumber *> *indices);
NSArray<NSValue *> *WhaleySrcFlamePositions(void);
NSDictionary<NSString *, id> *WhaleySrcSceneSnapshotElements(void);

void WhaleySrcReplayCurrentLevel(void);
void WhaleySrcAdvanceAfterWin(void);

BOOL WhaleySrcTouchBegan(UITouch *touch, UIEvent *_Nullable event);
void WhaleySrcTouchMoved(UITouch *touch, UIEvent *_Nullable event);
void WhaleySrcTouchEnded(UITouch *touch, UIEvent *_Nullable event);
void WhaleySrcTouchCancelled(UITouch *touch, UIEvent *_Nullable event);

// Acquires/releases the scrub's pause without losing an existing HUD pause.
// Repeated acquisition/release is safe, including after replacing the scene.
void WhaleySrcSetSceneScrubPaused(BOOL paused);
void WhaleySrcBeginTimeProjection(void);
BOOL WhaleySrcProjectTime(NSTimeInterval seconds);
void WhaleySrcRestoreLiveProjection(void);
CGPoint WhaleySrcPlayerPosition(void);
// Read-only visual center for 3D projections (legacy position remains unchanged).
CGPoint WhaleySrcPlayerCenter(void);
NSInteger WhaleySrcCurrentLevelNumber(void);
void WhaleySrcProjectPlayerPosition(CGPoint position);
NSTimeInterval WhaleySrcGameTime(void);
NSUInteger WhaleySrcPlayerHistorySampleCount(void);
NSTimeInterval WhaleySrcPlayerHistoryFirstTime(void);
NSTimeInterval WhaleySrcPlayerHistoryLastTime(void);

BOOL WhaleySrcHitBubble(CGPoint viewPoint);
BOOL WhaleySrcSceneScrubCanAcquire(CGPoint viewPoint);
BOOL WhaleySrcSceneScrubBegin(CGPoint viewPoint);
NSUInteger WhaleySrcSceneScrubAccessibleObjectCount(void);
NSString *WhaleySrcSceneScrubAccessibleObjectLabel(NSUInteger index);
CGRect WhaleySrcSceneScrubAccessibleObjectFrame(NSUInteger index);
CGRect WhaleySrcSceneScrubActiveObjectFrame(void);
BOOL WhaleySrcSceneScrubBeginAccessibleObject(NSUInteger index);

NSUInteger WhaleySrcAccessibleBubbleCount(void);
NSString *WhaleySrcAccessibleBubbleLabel(NSUInteger index);
CGRect WhaleySrcAccessibleBubbleFrame(NSUInteger index);
BOOL WhaleySrcAccessibleBubbleBegin(NSUInteger index);
BOOL WhaleySrcAccessibleBubbleMove(CGFloat deltaX, CGFloat deltaY);
void WhaleySrcAccessibleBubbleEnd(void);
void WhaleySrcSceneScrubApply(NSInteger category, NSInteger scalarSteps);
void WhaleySrcSceneScrubEnd(void);

NS_ASSUME_NONNULL_END

typedef NS_ENUM(NSInteger, WhaleyAdventureAction) {
    WhaleyAdventureActionShootLeft = 0,
    WhaleyAdventureActionShootRight = 1,
    WhaleyAdventureActionShootBelow = 2,
};
BOOL WhaleySrcAdventurePerformAction(WhaleyAdventureAction action);
BOOL WhaleySrcAdventurePlayerIsDead(void);

// Interactive 3D projection. Calls into the same original Obj-C gameplay.
// Must be called on the main thread while the SpriteKit-backed level is active.
void WhaleySrc3DSetEnabled(BOOL enabled);
BOOL WhaleySrc3DIsAirborne(void);
NSUInteger WhaleySrc3DJumpSequence(void);
CGPoint WhaleySrc3DPlayerBottom(void);
CGPoint WhaleySrc3DJumpStartBottom(void);
BOOL WhaleySrc3DBeginBubble(WhaleyAdventureAction action);
// Re-select only a live, ordinary bubble from the captured native scene.
// Failure consumes no shot and must not be retried as creation by the caller.
BOOL WhaleySrc3DBeginExistingBubble(NSString * _Nonnull sessionID,
                                   NSString * _Nonnull projectileID);
void WhaleySrc3DUpdateHeldBubble(NSTimeInterval duration);
void WhaleySrc3DEndHeldBubble(void);
CGPoint WhaleySrcAdventureViewPoint(CGPoint normalizedLevelPoint);
BOOL WhaleySrcAdventurePrepareCheckpoint(CGPoint normalizedLevelPoint);

CGSize WhaleySrcAdventureLevelSize(void);
#endif
