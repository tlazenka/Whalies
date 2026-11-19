//
//  Created by Francis Lazenka on 9/8/10.
//

#import "cocos2d.h"
@class Whaley;
@class Collectible;
@class Player;
@class CCLabelBMFont;

@interface WhaleyWinScreen : CCLayerColor {
    CCLabelBMFont *_label3;
    CCLabelBMFont *_label4;
    CCLabelBMFont *_label5;
    CCLabelBMFont *_label6;
    CCLabelBMFont *_label7;
    CCLabelBMFont *_label8;
    CCLabelBMFont *_label9;
}

@property (nonatomic, retain)Whaley *gameLayer;
@property (nonatomic, retain)CCLabelBMFont *label1;
@property (nonatomic, retain)CCLabelBMFont *label2;

- (void)blink:(id)sender;
+ (WhaleyWinScreen *)initAsColorLayer:(Whaley *)gameLayer;

- (void)winLevel:(id)sender;
- (void)nextScene:(id)sender;

@end

@interface WhaleyHud : CCLayerColor {
}

@property (nonatomic, retain)Whaley *gameLayer;
@property (nonatomic, retain)CCLabelBMFont *label1;
@property (nonatomic, retain)CCLabelBMFont *warningLabel;
@property (nonatomic, retain)CCLabelBMFont *scoreLabel;
@property (nonatomic, retain)Collectible *collectibleIcon;
@property (nonatomic, retain)CCLabelBMFont *resumeLabel;
@property (nonatomic, retain)CCLabelBMFont *quitLabel;
@property (nonatomic, retain)Player *playerResumeIcon;
@property (nonatomic, retain)Player *playerQuitIcon;

+ (WhaleyHud *)initAsColorLayer:(Whaley *)gameLayer;

- (void)resumeLevel:(id)sender;

- (void)pauseGame:(id)sender;

- (void)updateScore;

- (void)replayLevel:(id)sender;

- (void)exitLevel:(id)sender;

- (void)setWarning:(BOOL)value;

@end
