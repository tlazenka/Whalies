//
//  Created by Francis Lazenka on 9/8/10.
//

// Restore the original Whaley HUD and completion flow using SpriteKit-backed CCLayer nodes.
// All scene HUD labels use the original game_font.fnt bitmap atlas.
#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyHud.h"
#import "WhaleyBootstrap.h"
#import "WhaleySceneLifecycle.h"
#import "WhaleyScene.h"
#import "GameState.h"
#import "Constants.h"
#import "Level.h"
#import "Score.h"
#import "Player.h"
#import "SimpleAudioEngine.h"
#import "WhaleyBitmapFont.h"

static WhaleyBitmapLabel *WhaleyText(NSString *text, CGFloat size, CGPoint position) {
    return [WhaleyBitmapLabel labelWithText:text fontFile:@"game_font.fnt"
                                      size:size position:position];
}

static WhaleyBitmapLabel *WhaleyLeftText(NSString *text, CGFloat x, CGFloat y) {
    // CCLabelBMFont in the original uses anchor (0, 0.5) for result rows.
    // Our bitmap label uses a centered anchor and the real glyph advances.
    WhaleyBitmapLabel *label = WhaleyText(text, 16, CGPointZero);
    label.position = CGPointMake(x + label.advanceWidth / 2, y);
    label.zPosition = 2;
    return label;
}

static SKShapeNode *WhaleyPanel(CGRect frame, CGFloat alpha) {
    SKShapeNode *panel = [SKShapeNode shapeNodeWithRect:frame];
    panel.fillColor = [UIColor colorWithWhite:0 alpha:alpha];
    panel.strokeColor = UIColor.clearColor;
    panel.lineWidth = 0;
    return panel;
}

@interface WhaleyWinScreen () {
    BOOL _transitioning;
}
@end

@implementation WhaleyWinScreen

+ (instancetype)initAsColorLayer:(Whaley *)gameLayer {
    CGSize size = [[CCDirector sharedDirector] winSize];
    WhaleyWinScreen *screen = [self layerWithColor:ccc4(0, 0, 0, 255) width:size.width height:size.height];
    screen.gameLayer = gameLayer;
    screen.zPosition = 10000;
    screen.visible = NO;
    screen.position = CGPointZero;
    return screen;
}

- (void)winLevel:(id)sender {
    if (self.visible || !self.gameLayer) return;
    Whaley *game = self.gameLayer;
    Level *level = game.level;
    GameState *state = [GameState gameState];
    NSInteger previousLevelsAchieved = state.levelsAchieved;
    NSInteger finalScore = [game calculateScore];
    NSInteger coins = level.totalCollectibles;
    NSInteger bubbles = level.bubblesUsed;
    NSInteger time = (NSInteger)level.totalTime;

    Score *score = level.scores[[NSString stringWithFormat:@"%ld", (long)level.gameMode]];
    if (score) {
        score.highScore = MAX(score.highScore, finalScore);
        score.bestCollectiblesCaptured = MAX(score.bestCollectiblesCaptured, coins);
        score.bestBubblesUsed = MIN(score.bestBubblesUsed, bubbles);
        score.bestTime = MIN(score.bestTime, level.totalTime);
    }
    state.levelsAchieved = MAX(state.levelsAchieved, level.num + 1);
    [GameState saveGameStateToFile];

    game.isPaused = YES;
    game.paused = YES;
    game.hud.userInteractionEnabled = NO; // Full-screen interstitial owns taps.
    game.hud.hidden = YES;
    [self removeAllChildren];
    CGSize size = [[CCDirector sharedDirector] winSize];
    SKShapeNode *shade = [SKShapeNode shapeNodeWithRect:
        CGRectMake(0, 0, size.width, size.height)];
    shade.fillColor = UIColor.blackColor;
    shade.strokeColor = UIColor.clearColor;
    shade.zPosition = -10;
    [self addChild:shade];

    // Legacy WhaleyWinScreen.m uses 16-point bitmap rows. The name is two
    // rows above the coin count; labels are all anchored at logical x=64.
    CGFloat coinY = size.height / 2 + 3 * 16;
    CGFloat bubbleY = coinY - 16;
    CGFloat timeY = bubbleY - 16;
    CGFloat scoreY = timeY - 2 * 16;
    CGFloat highY = scoreY - 16;
    WhaleyBitmapLabel *title = WhaleyText(level.name ?: @"", 16,
        CGPointMake(size.width / 2, coinY + 2 * 16));
    title.zPosition = 2;
    [self addChild:title];
    [self addChild:WhaleyLeftText([NSString stringWithFormat:@"      x %ld", (long)coins], 64, coinY)];
    [self addChild:WhaleyLeftText([NSString stringWithFormat:@"      x %ld", (long)bubbles], 64, bubbleY)];
    [self addChild:WhaleyLeftText([NSString stringWithFormat:@"   TIME %ld", (long)time], 64, timeY)];

    WhaleyBitmapLabel *scoreLabel = WhaleyLeftText(@"  SCORE ", 64, scoreY);
    WhaleyBitmapLabel *scoreValue = WhaleyLeftText(
        [NSString stringWithFormat:@"%ld", (long)finalScore],
        64 + scoreLabel.advanceWidth, scoreY);
    [self addChild:scoreLabel];
    [self addChild:scoreValue];
    // The original toggles numeric visibility at hard 0.5-second intervals.
    SKAction *blink = [SKAction repeatActionForever:[SKAction sequence:@[
        [SKAction waitForDuration:0.5], [SKAction hide],
        [SKAction waitForDuration:0.5], [SKAction unhide]
    ]]];
    [scoreValue runAction:blink];

    WhaleyBitmapLabel *highLabel = WhaleyLeftText(@"     HI ", 64, highY);
    WhaleyBitmapLabel *highValue = WhaleyLeftText(
        [NSString stringWithFormat:@"%ld", (long)(score ? score.highScore : finalScore)],
        64 + highLabel.advanceWidth, highY);
    [self addChild:highLabel];
    [self addChild:highValue];
    [highValue runAction:blink];

    CCSprite *coin = [CCSprite spriteWithSpriteFrameName:@"coin1.png"];
    coin.scaleX = coin.scaleY = 0.5;
    coin.anchorPoint = CGPointMake(0, 0.5);
    coin.position = CGPointMake(128, coinY);
    coin.zPosition = 1;
    [self addChild:coin];

    // Capture pre-completion progress: cocos2d chooses result bubble art
    // before it unlocks the next painting.
    NSString *bubbleFile = (previousLevelsAchieved >= NumLevels)
        ? @"infinite_bubble.png" : @"bubble01.png";
    CCSprite *bubble = [CCSprite spriteWithFile:bubbleFile];
    bubble.scaleX = bubble.scaleY = 0.125;
    bubble.anchorPoint = CGPointMake(0, 0.5);
    bubble.position = CGPointMake(128, bubbleY);
    if (previousLevelsAchieved <= NumLevels) {
        bubble.color = (level.gameMode == ExtraBounce) ? Magenta : Purple;
    }
    bubble.zPosition = 1;
    [self addChild:bubble];
    _transitioning = NO;
    self.visible = YES;
    // Original WhaleyWinScreen automatically advanced after three seconds.
    [self runAction:[SKAction sequence:@[
        [SKAction waitForDuration:3],
        [SKAction runBlock:^{ [self advanceAfterWin]; }]
    ]] withKey:@"original-interstitial-advance"];
}

- (void)advanceAfterWin {
    if (!self.visible || _transitioning) return;
    _transitioning = YES;
    [self removeActionForKey:@"original-interstitial-advance"];
    WhaleyStopSceneSchedules(self.gameLayer);
    WhaleySrcAdvanceAfterWin();
}

@end

@interface WhaleyHud () {
    WhaleyBitmapLabel *_primaryLabel;
    WhaleyBitmapLabel *_leftLabel;
    WhaleyBitmapLabel *_rightLabel;
    SKShapeNode *_bar;
    WhaleyBitmapLabel *_warningLabel;
    WhaleyBitmapLabel *_coinCount;
    CCSprite *_coinIcon;
    CCSprite *_quitIcon;
    CCSprite *_continueIcon;
    CDSoundSource *_pauseSound;
    BOOL _warning;
    BOOL _quitting;
}
@end

@implementation WhaleyHud

+ (instancetype)initAsColorLayer:(Whaley *)gameLayer {
    CGSize s = [[CCDirector sharedDirector] winSize];
    WhaleyHud *hud = [self layerWithColor:ccc4(0, 0, 0, 0) width:s.width height:32];
    hud.gameLayer = gameLayer;
    hud->_pauseSound = [[[SimpleAudioEngine sharedEngine] soundSourceForFile:@"pause01.wav"] retain];
    // The logical scene's upper edge is y = s.height. Center the 32pt
    // content row there and overdraw above it to avoid exposing the level.
    hud.position = CGPointMake(s.width / 2, s.height - 16);
    // Keep the interactive HUD above DEBUG geometry/status nodes. It is
    // explicitly hidden when the level-completion interstitial takes over.
    hud.zPosition = 50000;
    // SpriteKit owns top-bar touch delivery. The HUD is a sibling of the
    // gameplay layer so it continues to receive events while gameplay is paused.
    hud.name = @"WhaleyHUD";
    hud.userInteractionEnabled = YES;
    // The reference HUD is a 32-point opaque band, not a 64-point patch.
    hud->_bar = [WhaleyPanel(CGRectMake(-s.width / 2, -16, s.width, 32), 1.0) retain];
    hud->_bar.zPosition = -10;
    [hud addChild:hud->_bar];
    hud->_primaryLabel = [WhaleyText(gameLayer.level.name ?: @"LEVEL", 16, CGPointZero) retain];
    hud->_leftLabel = [WhaleyText(@"QUIT", 16, CGPointZero) retain];
    hud->_rightLabel = [WhaleyText(@"CONTINUE", 16, CGPointZero) retain];
    hud->_warningLabel = [WhaleyText(@"!", 16, CGPointZero) retain];
    hud->_coinCount = [WhaleyText(@"x0", 16, CGPointZero) retain];

    // Use actual original sprite frames, matching the 2010 quit/continue
    // presentation; the quit icon is tinted red and vertically flipped.
    hud->_coinIcon = [[CCSprite spriteWithSpriteFrameName:@"coin1.png"] retain];
    hud->_coinIcon.scaleX = hud->_coinIcon.scaleY = 0.5;
    hud->_coinIcon.anchorPoint = CGPointMake(0, 0.5);
    hud->_coinIcon.position = CGPointMake(-s.width / 2, 0);
    NSString *playerFrame = ([GameState gameState].levelsAchieved > NumLevels)
        ? @"player-win1.png" : @"player1.png";
    hud->_quitIcon = [[CCSprite spriteWithSpriteFrameName:playerFrame] retain];
    hud->_quitIcon.scaleX = hud->_quitIcon.scaleY = 0.5;
    hud->_quitIcon.anchorPoint = CGPointMake(0, 0.5);
    hud->_quitIcon.color = ccRED;
    hud->_quitIcon.flipY = YES;
    hud->_quitIcon.position = CGPointMake(-s.width / 2 + 4, 0);
    hud->_continueIcon = [[CCSprite spriteWithSpriteFrameName:playerFrame] retain];
    hud->_continueIcon.scaleX = hud->_continueIcon.scaleY = 0.5;
    hud->_continueIcon.anchorPoint = CGPointMake(1, 0.5);
    // Cocos2d: quit starts after left+4 icon plus its scaled width+4.
    // Continue is right-anchored, with an icon to its left.
    CGFloat right = s.width / 2;
    CGFloat quitStart = hud->_quitIcon.position.x
        + hud->_quitIcon.contentSize.width * hud->_quitIcon.scaleX + 4;
    hud->_leftLabel.position = CGPointMake(quitStart + hud->_leftLabel.advanceWidth / 2, 0);
    CGFloat continueStart = right - hud->_rightLabel.advanceWidth;
    hud->_rightLabel.position = CGPointMake(continueStart + hud->_rightLabel.advanceWidth / 2, 0);
    hud->_continueIcon.position = CGPointMake(continueStart - 4, 0);

    // Explicit sibling order: SKView.ignoresSiblingOrder is enabled.
    for (SKNode *node in @[hud->_coinIcon, hud->_quitIcon, hud->_continueIcon]) {
        node.zPosition = 1;
        [hud addChild:node];
    }
    for (SKNode *node in @[hud->_primaryLabel, hud->_leftLabel, hud->_rightLabel,
                           hud->_warningLabel, hud->_coinCount]) {
        node.zPosition = 2;
        [hud addChild:node];
    }
    [hud syncLabels];
    return hud;
}

// SKView forwards touch events to this interactive SpriteKit node.
// Convert inside SpriteKit, using the HUD's local coordinates rather than
// UIKit safe areas, estimated scaling, or the legacy Cocos touch dispatcher.
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.gameLayer || _quitting || self.gameLayer.player.isDead ||
        self.gameLayer.player.hasWon) {
        return;
    }
    CGSize logicalSize = [[CCDirector sharedDirector] winSize];
    CGRect localBar = CGRectMake(-logicalSize.width / 2, -16, logicalSize.width, 32);
    for (UITouch *touch in touches) {
        CGPoint local = [touch locationInNode:self];
        if (!CGRectContainsPoint(localBar, local)) {
            continue;
        }
        // Existing QUIT / CONTINUE state transitions remain authoritative.
        [CCCompatTrace record:@"hud.spritekit.touch"
                       detail:[NSString stringWithFormat:@"x=%.1f paused=%@",
                                                          local.x, self.gameLayer.isPaused ? @"YES" : @"NO"]];
        [self handleTopBarTouch:CGPointMake(local.x + logicalSize.width / 2, local.y)];
        return;
    }
}

- (void)syncLabels {
    BOOL paused = self.gameLayer.isPaused;
    BOOL hasCoins = self.gameLayer.level.totalCollectibles > 0;
    _primaryLabel.hidden = paused || _warning || hasCoins;
    _warningLabel.hidden = paused || !_warning;
    _coinIcon.hidden = paused || !hasCoins || _warning;
    _coinCount.hidden = paused || !hasCoins || _warning;
    _coinCount.text = [NSString stringWithFormat:@"x%ld",
                       (long)self.gameLayer.level.totalCollectibles];
    // Anchor the entire coin readout to the left edge, even as digits grow.
    // WhaleyBitmapLabel centers glyph runs on its node, so offset by half
    // the *actual* atlas advance width after every text update.
    CGFloat leftEdge = _coinIcon.position.x
        + _coinIcon.contentSize.width * _coinIcon.scaleX;
    _coinCount.position = CGPointMake(leftEdge + _coinCount.advanceWidth / 2, 0);
    _leftLabel.hidden = _rightLabel.hidden = !paused;
    _quitIcon.hidden = _continueIcon.hidden = !paused;
}

- (void)pauseGame:(id)sender {
    if (!self.gameLayer || self.gameLayer.isPaused || self.gameLayer.player.isDead ||
        self.gameLayer.player.hasWon) return;
    // Match Legacy/WhaleyHud.m: play once on the accepted pause transition.
    // Continue, Quit, and the touch-ended event do not play this cue.
    [_pauseSound play];
    self.gameLayer.isPaused = YES;
    self.gameLayer.paused = YES;
    [self syncLabels];
}

- (void)resumeLevel:(id)sender {
    if (!self.gameLayer || self.gameLayer.player.isDead || self.gameLayer.player.hasWon) return;
    self.gameLayer.paused = NO;
    self.gameLayer.isPaused = NO;
    [self syncLabels];
}

- (void)handleTopBarTouch:(CGPoint)point {
    if (!self.gameLayer.isPaused) {
        [self pauseGame:self];
    } else if (point.x < _leftLabel.position.x + _leftLabel.advanceWidth / 2
                           + [[CCDirector sharedDirector] winSize].width / 2) {
        // The original quit hit region ends at the QUIT label's right edge.
        [self exitLevel];
    } else {
        [self resumeLevel:self];
    }
}

- (void)exitLevel {
    if (_quitting) return;
    _quitting = YES;
    self.userInteractionEnabled = NO;
    // Stop the old callbacks and currently playing effects immediately, not
    // after the pose/transition and not only when the old layer deallocates.
    WhaleyStopSceneSchedules(self.gameLayer);
    [_pauseSound stop];
    // Historically Whaley briefly turns into the red, inverted "dead"
    // sprite before the tile transition completes.
    self.gameLayer.player.color = ccRED;
    self.gameLayer.player.flipY = YES;
    [self runAction:[SKAction sequence:@[
        [SKAction waitForDuration:0.35],
        [SKAction runBlock:^{ WhaleySrcShowMainMenu(); }]
    ]] withKey:@"quit-after-death-pose"];
}

- (void)replayLevel:(id)sender {
    WhaleyStopSceneSchedules(self.gameLayer);
    [_pauseSound stop];
    WhaleySrcReplayCurrentLevel();
}

- (void)setWarning:(BOOL)value {
    _warning = value;
    [self syncLabels];
}
- (void)updateScore {
    [self syncLabels];
}
- (void)dealloc {
    [_pauseSound stop];
    [_pauseSound release];
    [_bar release];
    [_primaryLabel release];
    [_leftLabel release];
    [_rightLabel release];
    [_warningLabel release];
    [_coinCount release];
    [_coinIcon release];
    [_quitIcon release];
    [_continueIcon release];
    [super dealloc];
}
@end
#endif
