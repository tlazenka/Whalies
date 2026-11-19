//
//  Created by Francis Lazenka on 7/25/10.
//

#if __has_include(<UIKit/UIKit.h>)

#import "Collectible.h"
#import "GameObject.h"
#import "GameState.h"
#import "Hazard.h"
#import "Helpers.h"
#import "Level.h"
#import "Player.h"
#import "Projectile.h"
#import "cocos2d.h"

@class CDSoundSource;
@class WhaleyHud;
@class WhaleyWinScreen;
@class WhaleyExpressionPresentation;

// Opt-in mode shared by the original Obj-C simulation and the SwiftUI 3D lens.
// The 2D SpriteKit and cocos2d behavior remains unchanged when disabled.
FOUNDATION_EXPORT BOOL WhaleyScene3DModeEnabled;
FOUNDATION_EXPORT BOOL WhaleyScene3DPlaceAtAnchor;
FOUNDATION_EXPORT CGPoint WhaleyScene3DJumpAnchorBottom;
FOUNDATION_EXPORT NSUInteger WhaleyScene3DJumpSequence;
FOUNDATION_EXPORT const NSInteger FLAME_DIMMED;
FOUNDATION_EXPORT const NSInteger FLAME_OPAQUE;
FOUNDATION_EXPORT const NSInteger TouchBubbleFudgeOffset;

FOUNDATION_EXPORT void WhaleySrcTrajectoryReset(void);
FOUNDATION_EXPORT NSUInteger WhaleySrcTrajectorySampleCount(void);
FOUNDATION_EXPORT NSTimeInterval WhaleySrcTrajectoryFirstTime(void);
FOUNDATION_EXPORT NSTimeInterval WhaleySrcTrajectoryLastTime(void);
FOUNDATION_EXPORT NSTimeInterval WhaleySrcSemanticTime(void);
FOUNDATION_EXPORT BOOL WhaleySrcTrajectoryProjectPlayer(Player *player, NSTimeInterval seconds);

@interface Whaley : CCLayer {
    NSInteger _numBubbles;
    CGFloat _ceilingFactor;
    BOOL _waterLevel;
    BOOL _touchSustained;
    NSInteger _phase;
    BOOL _hasInfiniteBubbles;
    NSInteger _defaultBounces;
    CGPoint _currentLocation;
    BOOL _allowMiddleBounce;
#if defined(WHALEY_SPRITEKIT_COMPAT)
    WhaleyExpressionPresentation *_expressionPresentation;
#endif
}

@property (nonatomic, retain) CCTMXTiledMap *tileMap;
@property (nonatomic, retain) CCTMXLayer *background;
@property (nonatomic, retain) CCTMXLayer *meta;
@property (nonatomic, retain) Player *player;
@property (nonatomic, retain) NSMutableArray *hazards;
@property (nonatomic, retain) NSMutableArray *projectiles;
@property (nonatomic, retain) NSMutableArray *collectibles;
@property (nonatomic, retain) WhaleyHud *hud;
@property (nonatomic, retain) WhaleyWinScreen *winScreen;
@property (nonatomic, readwrite) BOOL isPaused;
@property (nonatomic, retain) GameObject *goal;
@property (nonatomic, retain) Level *level;

@property (nonatomic, retain) NSString *tmxFile;

@property (nonatomic, retain) CDSoundSource *bounceSound;
@property (nonatomic, retain) CDSoundSource *flameSound;
@property (nonatomic, retain) CDSoundSource *jumpSound;
@property (nonatomic, retain) CDSoundSource *collectibleSound;
@property (nonatomic, retain) CDSoundSource *goalSound;
@property (nonatomic, retain) CDSoundSource *bgSound;

@property (nonatomic, retain) CCSpriteBatchNode *spoutSpriteSheet;
@property (nonatomic, retain) CCSprite *spout;
@property (nonatomic, retain) NSString *bubbleFileName;

- (BOOL)playerIsRestingOnGroundTile;

- (void)releaseRetained;

+ (id)scene:(Level *)level withGameMode:(NSInteger)gameMode;

- (id)initWithLevel:(Level *)level withGameMode:(NSInteger)gameMode;

// The compatibility scheduler coalesces overdue audio beats by this selector.
- (void)playBg:(ccTime)dt;
- (void)switchPhase:(ccTime)dt;
#if defined(WHALEY_SPRITEKIT_COMPAT)
- (void)updateExpression:(ccTime)dt;
#endif

- (NSInteger)calculateScore;

@end

// Shared engine hooks; no independent renderer-owned gameplay state.
FOUNDATION_EXPORT void WhaleySceneApply3DEnvironment(Whaley *game);
FOUNDATION_EXPORT BOOL WhaleySceneIs3DFoundation(Projectile *projectile);
#endif
