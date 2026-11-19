//
//  Created by Francis Lazenka on 8/18/10.
//

#if __has_include(<UIKit/UIKit.h>)

#import "cocos2d.h"
@class CCLabelBMFont;
@class CCSprite;
@class Whaley;
@class ParticleDust;
@class CDSoundSource;


@interface MainMenu : CCLayer {
}

@property (nonatomic, retain)CCLabelBMFont *label1;
@property (nonatomic, retain)NSMutableDictionary *levelImages;
@property (nonatomic, retain)CCSprite *bubble;
@property (nonatomic, retain)CCSprite *extraBounceBubble;
@property (nonatomic, retain)CCSprite *zoomedLevelImage;
@property (nonatomic, retain)CCSprite *credits;
@property (nonatomic, retain)UITouch *zoomTouch;
@property (nonatomic, readwrite)BOOL wonGame;
@property (nonatomic, readwrite)BOOL zoomLevelImage;
@property (nonatomic, readwrite)NSInteger currentTouchedLevelIndex;
@property (nonatomic, readwrite)BOOL zoomIsScheduled;
@property (nonatomic, retain)CDSoundSource *knockSound;

+ (id)initWithLevelsAchieved;

+ (id)initWithLevelsAchieved:(BOOL)firstLaunch;

- (void)setOpacity:(GLubyte)opacity;

- (void)runFadeIn:(ccTime)duration;

@end

#endif
