//
//  Created by Francis Lazenka on 8/18/10.
//

// Original MainMenu.m interaction model, adapted to the SpriteKit compatibility layer.
// Artwork loads from WhaleyResources when available; procedural placeholders are used otherwise.
#if __has_include(<UIKit/UIKit.h>)
#import "MainMenu.h"
#import "WhaleyBootstrap.h"
#import "WhaleySceneLifecycle.h"
#import "Constants.h"
#import "GameState.h"
#import "Level.h"
#import "SimpleAudioEngine.h"
#import "WhaleyBitmapFont.h"
#import "WhaleyTitleGeometry.h"
#import "WhaleyArtworkPreview.h"
#import "WhaleyLevelArtwork.h"
#import <math.h>

static WhaleyBitmapLabel *MenuText(NSString *text, CGFloat size, CGPoint pos) {
    return [WhaleyBitmapLabel labelWithText:text fontFile:@"game_font.fnt"
                                      size:size position:pos];
}

static SKNode *MenuArtwork(NSString *file, CGSize size, UIColor *fallback) {
    NSURL *url = WhaleySrcResourceURL(file);
    if (url) {
        SKTexture *texture = WhaleySrcTexture(file);
        SKSpriteNode *image = [SKSpriteNode spriteNodeWithTexture:texture size:size];
        return image;
    }
    SKShapeNode *shape = [SKShapeNode shapeNodeWithRectOfSize:size cornerRadius:3];
    shape.fillColor = fallback;
    shape.strokeColor = [UIColor colorWithWhite:0.85 alpha:0.8];
    shape.lineWidth = 1;
    return shape;
}

@interface MainMenu () {
    NSMutableArray<SKNode *> *_cards;
    CGSize _cardSize;
    NSMutableArray<SKNode *> *_titleLetters;
    NSInteger _pressedLevel;
    WhaleyArtworkPreview *_zoomNode;
    SKNode *_puzzleBubble;
    CDSoundSource *_knockSound;
    BOOL _wonGame;
}
@end

@implementation MainMenu

+ (instancetype)initWithLevelsAchieved { return [self initWithLevelsAchieved:NO]; }

+ (instancetype)initWithLevelsAchieved:(BOOL)firstLaunch {
    MainMenu *menu = [[[self alloc] init] autorelease];
    [menu buildMenu:firstLaunch];
    return menu;
}

- (void)buildMenu:(BOOL)firstLaunch {
    // The host has removed the old level. Cancel even if an action still
    // retains that level: deallocation is not an audio-lifecycle boundary.
    WhaleyStopDetachedSchedules();
    CGSize size = [[CCDirector sharedDirector] winSize];
    _cards = [[NSMutableArray alloc] init];
    _titleLetters = [[NSMutableArray alloc] init];
    _knockSound = [[[SimpleAudioEngine sharedEngine] soundSourceForFile:@"knock.mp3"] retain];
    _knockSound.gain = 0.5f;
    // Match the original menu soundtrack: A or B according to game progress,
    // play once, and resume from the point where a level paused it.
    NSString *music = [GameState gameState].levelsAchieved > NumLevels ? MusicFile2 : MusicFile1;
    [[SimpleAudioEngine sharedEngine] playBackgroundMusic:music loop:NO];
    [[SimpleAudioEngine sharedEngine] resumeBackgroundMusic];
    _pressedLevel = -1;
    _wonGame = [GameState gameState].levelsAchieved > NumLevels;
    self.isTouchEnabled = YES;
    SKNode *background = MenuArtwork(@"Default-568h@2x.png", size,
                              [UIColor colorWithRed:0.07 green:0.11 blue:0.17 alpha:1]);
    background.position = CGPointMake(size.width / 2, size.height / 2);
    background.zPosition = -2;
    [self addChild:background];

    // Legacy MainMenu fixes the title's bottom-left at (24, height-lineHeight-20)
    // because of Zapfino's overhangs. Do not center, shrink, or estimate word gaps.
    // Keep separate logical glyph owners for persistent per-character chalking.
    NSString *title = _wonGame ? GameName2 : GameName1;
    NSString *fontFile = _wonGame ? @"title_font2.fnt" : @"title_font.fnt";
    const CGFloat fontSize = 32;
    CGFloat lineHeight = [WhaleyBitmapLabel lineHeightForFontFile:fontFile size:fontSize];
    CGFloat pen = 0;
    NSArray *faded = [GameState gameState].transparentGameTitleCharacters;
    (void)firstLaunch; // The reference fades glyphs on every menu construction.
    for (NSUInteger i = 0; i < title.length; ++i) {
        unichar code = [title characterAtIndex:i];
        NSString *character = [title substringWithRange:NSMakeRange(i, 1)];
        if (i > 0) pen += [WhaleyBitmapLabel kerningForFirst:[title characterAtIndex:i - 1]
            second:code fontFile:fontFile size:fontSize];
        CGFloat advance = [WhaleyBitmapLabel advanceForCharacter:code fontFile:fontFile size:fontSize];
        WhaleyTitlePoint center = WhaleyTitleLetterCenter(size.height, lineHeight, pen, advance);
        WhaleyBitmapLabel *letter = [WhaleyBitmapLabel labelWithText:character
            fontFile:fontFile size:fontSize position:CGPointMake(center.x, center.y)];
        letter.name = character;
        letter.zPosition = 10 + i; // Original glyph-index order, explicitly preserved.
        [self addChild:letter];
        [_titleLetters addObject:letter];
        CGFloat targetAlpha = (i < faded.count && faded[i] != [NSNull null])
            ? WhaleyTitleChalkAlpha() : 1;
        letter.alpha = 0;
        [letter runAction:[SKAction fadeAlphaTo:targetAlpha duration:WhaleyTitleFadeSeconds()]
                  withKey:@"title-opacity"];
        pen += advance;
    }

    // Match the original full PNG canvas, including its transparent margins.
    // Each card is scaled once and rotates around its bottom-left corner.
    const CGFloat iconScale = 0.2;
    const CGFloat xPadding = 20;
    const CGFloat yPadding = 15;
    CGSize frameSize = WhaleySrcResourceURL(@"frame.png")
        ? [WhaleySrcTexture(@"frame.png") size] : CGSizeMake(344, 514);
    CGPoint frameCenter = CGPointMake(frameSize.width / 2, frameSize.height / 2);
    _cardSize = CGSizeMake(frameSize.width * iconScale, frameSize.height * iconScale);
    CGFloat firstX = (size.width - (_cardSize.width + xPadding) * 3) / 2 + xPadding / 2;
    CGFloat titleBottom = size.height - lineHeight - 20;
    GameState *state = [GameState gameState];
    for (NSInteger i = 0; i < NumLevels; ++i) {
        NSInteger number = i + 1;
        CGFloat x = firstX + (i % 3) * (_cardSize.width + xPadding);
        CGFloat y = titleBottom - (i / 3 + 1) * (_cardSize.height + yPadding);
        SKNode *card = [SKNode node];
        card.position = CGPointMake(x, y);
        [card setScale:iconScale];
        Level *level = i < (NSInteger)state.levels.count ? state.levels[i] : nil;
        CGFloat degrees = level ? level.levelImageRotation : 0;
        card.zRotation = -degrees * (CGFloat)M_PI / 180;
        card.name = [NSString stringWithFormat:@"level-%ld", (long)number];

        // Explicit depths are required when SKView ignores sibling order.
        // Child insertion order alone did not guarantee the frame stayed on top.
        if (number <= state.levelsAchieved) {
            NSString *file = WhaleyLevelArtworkFilename(number, NO);
            // Legacy scales the level image to 200x300 inside the full frame.
            SKNode *painting = MenuArtwork(file, CGSizeMake(200, 300),
                [UIColor colorWithHue:0.56 saturation:0.36 brightness:0.5 alpha:1]);
            painting.position = frameCenter;
            painting.name = @"painting";
            painting.zPosition = 0;
            [card addChild:painting];
        }
        SKNode *frame = MenuArtwork(@"frame.png", frameSize,
                                   [UIColor colorWithWhite:0.15 alpha:0.12]);
        frame.position = frameCenter;
        frame.name = @"picture-frame";
        frame.zPosition = 10;
        [card addChild:frame];
        // CCLayerColor ccc4(0, 0, 0, 100), covering the exact frame rectangle.
        SKSpriteNode *highlight = [SKSpriteNode spriteNodeWithColor:UIColor.blackColor size:frameSize];
        highlight.position = frameCenter;
        highlight.alpha = 100.0 / 255.0;
        highlight.name = @"highlight";
        highlight.zPosition = 30;
        highlight.hidden = YES;
        [card addChild:highlight];
        [self addChild:card];
        [_cards addObject:card];
    }

    // Preserve the requested single reward/interpunct; no decorative duplicate.
    // Geometry is the original 128px bubble at 1/8 scale, opacity 150/255,
    // positioned from the title origin, not from neighboring painted bounds.
    CGFloat diameter = WhaleyTitleRewardDiameter();
    _puzzleBubble = [MenuArtwork(@"bubble01.png", CGSizeMake(diameter, diameter),
                                [UIColor colorWithRed:0.83 green:0.1 blue:0.58 alpha:1]) retain];
    _puzzleBubble.name = @"puzzle-bubble";
    WhaleyTitlePoint reward = WhaleyTitleRewardCenter(size.width, size.height, lineHeight);
    _puzzleBubble.position = CGPointMake(reward.x, reward.y);
    _puzzleBubble.alpha = WhaleyTitleRewardAlpha();
    _puzzleBubble.zPosition = 30;
    if ([_puzzleBubble isKindOfClass:[SKSpriteNode class]]) {
        SKSpriteNode *sprite = (SKSpriteNode *)_puzzleBubble;
        sprite.color = [UIColor colorWithRed:Magenta.r / 255.0 green:Magenta.g / 255.0
                                       blue:Magenta.b / 255.0 alpha:1];
        sprite.colorBlendFactor = 1;
    }
    [self addChild:_puzzleBubble];
    [self refreshPuzzleBubble];
}

- (void)refreshPuzzleBubble {
    _puzzleBubble.hidden = ![GameState gameState].hasExtraBounce;
}

- (NSInteger)levelAt:(CGPoint)point {
    for (NSInteger i = 0; i < (NSInteger)_cards.count; ++i) {
        SKNode *card = _cards[i];
        // Helpers.spriteRectangle in Whaley2010 tests the nominal, unrotated
        // canvas at the card's bottom-left, even while the painting swings.
        CGRect bounds = (CGRect){card.position, _cardSize};
        if (CGRectContainsPoint(bounds, point)) {
            NSInteger number = i + 1;
            return number <= [GameState gameState].levelsAchieved ? number : -1;
        }
    }
    return -1;
}

- (void)clearHighlights {
    for (SKNode *card in _cards) {
        [card childNodeWithName:@"highlight"].hidden = YES;
    }
}

- (void)schedulePreview {
    if (_pressedLevel <= 0 || [self actionForKey:@"zoom"]) return;
    NSInteger selected = _pressedLevel;
    [self runAction:[SKAction sequence:@[
        [SKAction waitForDuration:1],
        [SKAction runBlock:^{ [self showPreview:selected]; }]
    ]] withKey:@"zoom"];
}

- (void)showPreview:(NSInteger)level {
    if (_zoomNode.parent || _pressedLevel != level) return;
    CGSize size = [[CCDirector sharedDirector] winSize];
    // A dismissed preview stays owned until its fade/removal has completed.
    // Releasing it here cannot let an old completion alter this new preview.
    [_zoomNode release];
    _zoomNode = [[WhaleyArtworkPreview node] retain];
    _zoomNode.name = @"WhaleyArtworkPreview";
    _zoomNode.zPosition = 2000;
    NSString *image = WhaleyLevelArtworkFilename(level, YES);
    if (!WhaleySrcResourceURL(image)) image = WhaleyLevelArtworkFilename(level, NO);
    [_zoomNode addChild:MenuArtwork(image, size,
                              [UIColor colorWithRed:0.11 green:0.18 blue:0.24 alpha:1])];
    for (SKNode *child in _zoomNode.children) child.position = CGPointMake(size.width / 2, size.height / 2);
    if (!WhaleySrcResourceURL(image)) {
        [_zoomNode addChild:MenuText([NSString stringWithFormat:@"LEVEL %ld", (long)level], 27,
                                    CGPointMake(size.width / 2, size.height / 2))];
    }
    [_zoomNode presentInNode:self];
    _pressedLevel = -1;
    // Keep the selected painting dark beneath the original preview fade-in.
    // hidePreview clears it when the preview is dismissed.
}

- (void)hidePreview {
    _pressedLevel = -1;
    [self removeActionForKey:@"zoom"];
    [self clearHighlights];
    [_zoomNode dismiss];
}

- (void)tapTitleAt:(CGPoint)point {
    GameState *state = [GameState gameState];
    // Legacy MainMenu tests a 1x1 touch against EVERY fully opaque glyph's
    // painted rectangle. Zapfino overlap can chalk more than one character.
    // Neither advance cells nor nearest-center ranking reproduce that rule.
    for (NSUInteger i = 0; i < _titleLetters.count; ++i) {
        WhaleyBitmapLabel *letter = (WhaleyBitmapLabel *)_titleLetters[i];
        if (letter.alpha < 1 || [letter.name isEqualToString:@" "]) continue;
        CGRect painted = [letter calculateAccumulatedFrame];
        if (!WhaleyTitleGlyphHit(point.x, point.y, painted.origin.x, painted.origin.y,
                                 painted.size.width, painted.size.height)) continue;
        [letter removeActionForKey:@"title-opacity"];
        [letter runAction:[SKAction fadeAlphaTo:WhaleyTitleChalkAlpha()
                                     duration:WhaleyTitleFadeSeconds()]
                  withKey:@"title-opacity"];
        if (i < state.transparentGameTitleCharacters.count) {
            state.transparentGameTitleCharacters[i] = @1;
        }
        // Retain the current dust implementation; particle-system parity is
        // a separate rendering contract, not part of the glyph geometry fix.
        SKTexture *dustTexture = WhaleySrcTexture(@"dust.png");
        for (NSInteger j = 0; j < 16; ++j) {
            CGFloat angle = (CGFloat)j * 2 * M_PI / 16.0;
            CGFloat distance = 12 + (CGFloat)(j % 5) * 5;
            SKSpriteNode *dust = [SKSpriteNode spriteNodeWithTexture:dustTexture
                                                                size:CGSizeMake(5 + j % 4, 5 + j % 4)];
            dust.position = point;
            dust.alpha = 0.75;
            dust.zPosition = 100;
            [self addChild:dust];
            [dust runAction:[SKAction sequence:@[
                [SKAction group:@[
                    [SKAction moveByX:cos(angle) * distance
                                    y:sin(angle) * distance duration:0.32],
                    [SKAction fadeOutWithDuration:0.32],
                    [SKAction scaleTo:0.3 duration:0.32]
                ]],
                [SKAction removeFromParent]
            ]]];
        }
    }
}

- (void)rotateFramesAndEvaluatePuzzle {
    BOOL aligned = YES;
    GameState *state = [GameState gameState];
    for (NSUInteger i = 0; i < _cards.count; ++i) {
        SKNode *card = _cards[i];
        Level *level = i < state.levels.count ? state.levels[i] : nil;
        if (!level) continue;
        CGFloat degrees = level.levelImageRotation;
        CGFloat delta;
        if (fabs(degrees) > 0.5) {
            delta = -degrees; // Restore a rotated card to zero.
        } else {
            NSInteger draw = arc4random_uniform(2);
            NSInteger magnitude = (NSInteger)arc4random_uniform(3) + 1;
            delta = draw == 0 ? 0 : (arc4random_uniform(2) == 0 ? magnitude : -magnitude);
        }
        level.levelImageRotation = degrees + delta;
        [card removeActionForKey:@"frame-rotation"];
        // cocos2d's positive degrees are clockwise. Target the persisted angle
        // so interrupting a swing cannot leave the frame at a different angle.
        [card runAction:[SKAction rotateToAngle:-level.levelImageRotation * (CGFloat)M_PI / 180 duration:0.1]
                withKey:@"frame-rotation"];
        if (fabs(level.levelImageRotation) > 0.5) aligned = NO;
    }
    if (aligned && !_wonGame) {
        state.hasExtraBounce = YES;
        [self refreshPuzzleBubble];
    }
}

- (void)registerWithTouchDispatcher {
    [[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:self priority:0 swallowsTouches:YES];
}

- (BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
    [self removeActionForKey:@"zoom"];
    // Includes the fade-out interval: no press may reach a painting underneath.
    if (_zoomNode.parent) {
        [self hidePreview];
        return YES;
    }
    CGPoint point = [[CCDirector sharedDirector] convertToGL:[touch locationInView:touch.view]];
    _pressedLevel = [self levelAt:point];
    [self clearHighlights];
    if (_pressedLevel > 0) {
        [[_cards[_pressedLevel - 1] childNodeWithName:@"highlight"] setHidden:NO];
        [self schedulePreview];
        return YES;
    }
    WhaleyTitlePoint reward = {_puzzleBubble.position.x, _puzzleBubble.position.y};
    if (!_puzzleBubble.hidden && WhaleyTitleRewardHit(point.x, point.y, reward)) {
        [GameState gameState].hasExtraBounce = NO;
        [self refreshPuzzleBubble];
        // Original puzzle pop: no knock, rotation, chalk, or invented pop sound.
    } else {
        // Original menu cue is at touch-began, not on preview/release/start.
        [_knockSound play];
        [self rotateFramesAndEvaluatePuzzle];
        [self tapTitleAt:point];
    }
    [GameState saveGameStateToFile];
    return YES;
}

- (void)ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
    if (_pressedLevel <= 0 || _zoomNode.parent) return;
    CGPoint point = [[CCDirector sharedDirector] convertToGL:[touch locationInView:touch.view]];
    if ([self levelAt:point] == _pressedLevel) {
        [[_cards[_pressedLevel - 1] childNodeWithName:@"highlight"] setHidden:NO];
        [self schedulePreview];
    } else {
        // Retain the original selection so dragging back restores its highlight
        // and starts a fresh hold, just as Whaley2010's ccTouchMoved does.
        [self removeActionForKey:@"zoom"];
        [self clearHighlights];
    }
}

- (void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    [self removeActionForKey:@"zoom"];
    if (_zoomNode.parent) { _pressedLevel = -1; return; }
    CGPoint point = [[CCDirector sharedDirector] convertToGL:[touch locationInView:touch.view]];
    NSInteger level = [self levelAt:point];
    if (_pressedLevel > 0 && level == _pressedLevel) {
        _pressedLevel = -1;
        GameState *state = [GameState gameState];
        NSInteger mode = state.hasExtraBounce ? ExtraBounce : (_wonGame ? InfiniteBubble : NormalBubble);
        [_knockSound stop];
        WhaleySrcStartLevel(level, mode);
        return;
    }
    _pressedLevel = -1;
    [self clearHighlights];
}

- (void)ccTouchCancelled:(UITouch *)touch withEvent:(UIEvent *)event {
    _pressedLevel = -1;
    [self removeActionForKey:@"zoom"];
    [self clearHighlights];
}

- (void)dealloc {
    [_cards release];
    [_titleLetters release];
    [_zoomNode release];
    [_puzzleBubble release];
    [_knockSound stop];
    [_knockSound release];
    [super dealloc];
}
@end
#endif
