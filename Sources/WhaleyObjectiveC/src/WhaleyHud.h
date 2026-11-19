//
//  Created by Francis Lazenka on 9/8/10.
//

#if __has_include(<UIKit/UIKit.h>)

#import "cocos2d.h"
@class Whaley;
@interface WhaleyWinScreen : CCLayerColor
@property (nonatomic, assign) Whaley *gameLayer;
+ (instancetype)initAsColorLayer:(Whaley *)gameLayer;
- (void)winLevel:(id)sender;
- (void)advanceAfterWin;
@end
@interface WhaleyHud : CCLayerColor
@property (nonatomic, assign) Whaley *gameLayer;
+ (instancetype)initAsColorLayer:(Whaley *)gameLayer;
- (void)pauseGame:(id)sender;
- (void)handleTopBarTouch:(CGPoint)point;
- (void)resumeLevel:(id)sender;
- (void)replayLevel:(id)sender;
- (void)setWarning:(BOOL)value;
- (void)updateScore;
@end
#endif
