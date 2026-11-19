//
//  Created by Francis Lazenka on 9/8/10.
//

#import "WhaleyHud.h"
#import "WhaleyScene.h"
#import "SimpleAudioEngine.h"
#import "Score.h"
#import "MainMenu.h"

@implementation WhaleyWinScreen

@synthesize gameLayer = _gameLayer;

@synthesize label1 = _label1;
@synthesize label2 = _label2;

const NSInteger yPadding = 10;

- (void)blink:(id)sender {
	CCLabelBMFont *sprite = (CCLabelBMFont *)sender;
	sprite.visible = (!(sprite.visible));
}

+ (WhaleyWinScreen *)initAsColorLayer:(Whaley *)gameLayer {
	CGSize s = [[CCDirector sharedDirector] winSize];
	WhaleyWinScreen *result = [WhaleyWinScreen layerWithColor:ccc4(0, 0, 0, 255)
														width:s.width
													   height:s.height];
	result.gameLayer = gameLayer;
	
	result.ignoreAnchorPointForPosition = NO;
	result.isTouchEnabled = NO;
	result.position = ccp(s.width / 2, s.height / 2);
	
	result.label1 = [CCLabelBMFont labelWithString:
					 [NSString stringWithFormat:@"%@", result.gameLayer.level.name]
														 fntFile:@"game_font.fnt"];
	//result.label1.anchorPoint = ccp(0.5, 1);
	[result addChild:result.label1];
	
	result.label2 = [CCLabelBMFont labelWithString:
					 [NSString stringWithFormat:@"PUSH SCREEN"]
														 fntFile:@"game_font.fnt"];
	//result.label2.anchorPoint = ccp(0.5, 0);
	
	result.label2.visible = NO;
	[result addChild:result.label2];
	
	result.visible = NO;
	
	return result;
}

- (void)winLevel:(id)sender {
	[self.gameLayer pauseSchedulerAndActions];
	
	Score *score = (Score *)[self.gameLayer.level.scores objectForKey:[NSString stringWithFormat:@"%d", self.gameLayer.level.gameMode]];
	
	CGSize s = [[CCDirector sharedDirector] winSize];
	_label3 = [CCLabelBMFont labelWithString:
			   [NSString stringWithFormat:@"      x %d", self.gameLayer.level.totalCollectibles] fntFile:@"game_font.fnt"];
	_label4 = [CCLabelBMFont labelWithString:
			   [NSString stringWithFormat:@"      x %d", self.gameLayer.level.bubblesUsed] fntFile:@"game_font.fnt"];
	_label5 = [CCLabelBMFont labelWithString:
			   [NSString stringWithFormat:@"   TIME %d", (NSInteger)self.gameLayer.level.totalTime] fntFile:@"game_font.fnt"];
	_label6 = [CCLabelBMFont labelWithString:
			   [NSString stringWithFormat:@"  SCORE "] fntFile:@"game_font.fnt"];
	_label9 = [CCLabelBMFont labelWithString:
			   [NSString stringWithFormat:@"%d", [self.gameLayer calculateScore]] fntFile:@"game_font.fnt"];
	
	score.highScore = MAX([self.gameLayer calculateScore], score.highScore);
	
	_label7 = [CCLabelBMFont labelWithString:
			   [NSString stringWithFormat:@"     HI "] fntFile:@"game_font.fnt"];
	
	_label8 = [CCLabelBMFont labelWithString:
			   [NSString stringWithFormat:@"%d", score.highScore] fntFile:@"game_font.fnt"];
	
	_label3.anchorPoint = ccp(0, 0.5);
	_label4.anchorPoint = ccp(0, 0.5);
	_label5.anchorPoint = ccp(0, 0.5);
	_label6.anchorPoint = ccp(0, 0.5);
	_label7.anchorPoint = ccp(0, 0.5);
	_label8.anchorPoint = ccp(0, 0.5);
	_label9.anchorPoint = ccp(0, 0.5);
	
	_label3.position = ccp(16 * 4, (s.height / 2) + (_label3.contentSize.height * 3));
	_label4.position = ccp(_label3.position.x, _label3.position.y - _label3.contentSize.height);
	_label5.position = ccp(_label3.position.x, _label4.position.y - _label4.contentSize.height);
	_label6.position = ccp(_label3.position.x, _label5.position.y - (_label5.contentSize.height * 2));
	_label7.position = ccp(_label3.position.x, _label6.position.y - _label6.contentSize.height);
	_label8.position = ccp(_label7.position.x + _label7.contentSize.width, _label7.position.y);
	_label9.position = ccp(_label6.position.x + _label6.contentSize.width, _label6.position.y);
	
	self.label1.position = ccp(s.width / 2, _label3.position.y + (_label3.contentSize.height * 2));
	self.label2.position = ccp(s.width / 2, -(self.label2.contentSize.height / 2));
	
	[self addChild:_label3];
	[self addChild:_label4];
	[self addChild:_label5];
	[self addChild:_label6];
	[self addChild:_label7];
	[self addChild:_label8];
	[self addChild:_label9];
	
	CCSpriteBatchNode *collectibleSpriteSheet = [CCSpriteBatchNode batchNodeWithFile:@"coin.png"];
	[self addChild:collectibleSpriteSheet];
	
	Collectible *collectible = [Collectible initWithFile:@"coin1.png"];
	[collectibleSpriteSheet addChild:collectible];
	collectible.scale = 0.5;
	collectible.anchorPoint = ccp(0, 0.5);
	collectible.position = ccp(_label3.position.x + (16 * 4), _label3.position.y);
	
	NSString *bubbleFileName = ([GameState gameState].levelsAchieved >= NumLevels) ? (@"infinite_bubble.png") : (@"bubble01.png");
	CCSprite *bubble = [CCSprite spriteWithFile:bubbleFileName];
	
	BOOL hasExtraBounce = self.gameLayer.level.gameMode == ExtraBounce;
	
	if ([GameState gameState].levelsAchieved <= NumLevels) {
		bubble.color = (hasExtraBounce) ? (Magenta) : (Purple);
	}
	bubble.scale = 0.125;
	bubble.anchorPoint = ccp(0, 0.5);
	bubble.position = ccp(_label4.position.x + (16 * 4), _label4.position.y);
	[self addChild:bubble];
	
	//BOOL wonGame = NO;
	
	if ((self.gameLayer.level.num == NumLevels) && ([GameState gameState].levelsAchieved == NumLevels))  {
		
		[[GameState gameState].transparentGameTitleCharacters replaceObjectAtIndex:1 withObject:[NSNull null]];
		[[GameState gameState].transparentGameTitleCharacters replaceObjectAtIndex:3 withObject:[NSNull null]];
		
		[[SimpleAudioEngine sharedEngine] playBackgroundMusic:MusicFile2 loop:NO];
		
		[GameState gameState].hasExtraBounce = NO;
		
		//wonGame = YES;
	}
	
	if ((self.gameLayer.level.num + 1) > [GameState gameState].levelsAchieved) {
		[GameState gameState].levelsAchieved = self.gameLayer.level.num + 1;
	}
	score.bestBubblesUsed = MIN(score.bestBubblesUsed, self.gameLayer.level.bubblesUsed);
	score.bestCollectiblesCaptured = MAX(score.bestCollectiblesCaptured, self.gameLayer.level.totalCollectibles);
	score.bestTime = MIN(score.bestTime, self.gameLayer.level.totalTime);
	
	self.gameLayer.level.bubblesUsed = 0;
	self.gameLayer.level.checkpointIndex = -1;
	self.gameLayer.level.totalTime = 0;
	[self.gameLayer.level.collectiblesCaptured removeAllObjects];
	
	[GameState saveGameStateToFile];
	
	self.visible = YES;
	
	//if (!(wonGame)) {
		//self.isTouchEnabled = NO;
	self.isTouchEnabled = YES;
	self.label2.visible = NO;
	id action = [CCCallFuncN actionWithTarget:self selector:@selector(nextScene:)];
	[self runAction:[CCSequence actions:[CCDelayTime actionWithDuration:3.0f], action, nil]];
	/*}
	else {
		self.isTouchEnabled = YES;
		self.label2.visible = YES;
		[self.label2 runAction:[CCSequence actions:
								//[CCDelayTime actionWithDuration:1.5f],
								[CCMoveTo actionWithDuration:4.0f
													position:ccp(s.width / 2,
																 _label7.position.y - (_label7.contentSize.height * 2))],
								nil]];
		//id action = [CCCallFuncN actionWithTarget:self selector:@selector(blink:)];
		//[self.label2 runAction:[CCRepeatForever actionWithAction:[CCSequence actions:
		//[CCDelayTime actionWithDuration:0.5f], action, nil]]];
	}*/
	
	[_label8 runAction:[CCRepeatForever actionWithAction:[CCSequence actions:
														  [CCDelayTime actionWithDuration:0.5f],
														  [CCCallFuncN actionWithTarget:self selector:@selector(blink:)], nil]]];

	[_label9 runAction:[CCRepeatForever actionWithAction:[CCSequence actions:
														  [CCDelayTime actionWithDuration:0.5f],
														  [CCCallFuncN actionWithTarget:self selector:@selector(blink:)], nil]]];	
}

- (void)registerWithTouchDispatcher {
	[[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:self priority:0 swallowsTouches:YES];
}

- (BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
	[self unschedule:@selector(nextScene:)];
	return YES;
}

- (void)ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
}

- (void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
	[self nextScene:nil];
}

- (void)nextScene:(id)sender {
	self.isTouchEnabled = NO;
	CCScene *nextScene;
	
	if ((self.gameLayer.level.num < NumLevels)
		/*&& (([GameState gameState].levelsAchieved) == (self.gameLayer.level.num + 1))*/) {
		//gameState levels have different indexing scheme than self.gameLayer.level.num
		Level *nextLevel = [[GameState gameState].levels objectAtIndex:(self.gameLayer.level.num)];
		nextScene = [Whaley scene:nextLevel withGameMode:self.gameLayer.level.gameMode];
	}
	else {
		nextScene = [MainMenu initWithLevelsAchieved];
	}
	
	[[CCDirector sharedDirector] replaceScene:[CCTransitionTurnOffTiles
											   transitionWithDuration:0.5f
											   scene:nextScene]];
	[self.gameLayer releaseRetained];
}

- (void)dealloc {
	self.gameLayer = nil;
	self.label1 = nil;
	self.label2 = nil;
	[super dealloc];
}

@end

@implementation WhaleyHud

@synthesize gameLayer = _gameLayer;
@synthesize label1 = _label1;
@synthesize scoreLabel = _scoreLabel;
@synthesize collectibleIcon = _collectibleIcon;
@synthesize resumeLabel = _resumeLabel;
@synthesize quitLabel = _quitLabel;
@synthesize playerQuitIcon = _playerQuitIcon;
@synthesize playerResumeIcon = _playerResumeIcon;
@synthesize warningLabel = _warningLabel;

+ (WhaleyHud *)initAsColorLayer:(Whaley *)gameLayer {
	CGSize s = [[CCDirector sharedDirector] winSize];
	WhaleyHud *result = [WhaleyHud layerWithColor:ccc4(0, 0, 0, 255)
											width:s.width
										   height:32];
	result.gameLayer = gameLayer;
	
	result.ignoreAnchorPointForPosition = NO;
	result.isTouchEnabled = YES;
	result.position = ccp(s.width / 2, s.height - (result.contentSize.height / 2));
	
	result.label1 = [CCLabelBMFont labelWithString:
					 [NSString stringWithFormat:@"%@", result.gameLayer.level.name]
														 fntFile:@"game_font.fnt"];
	
	result.label1.position = ccp(result.contentSize.width / 2, result.contentSize.height / 2);
	
	CCSpriteBatchNode *collectibleSpriteSheet = [CCSpriteBatchNode batchNodeWithFile:@"coin.png"];
	[result addChild:collectibleSpriteSheet];
	
	Collectible *collectible = [Collectible initWithFile:@"coin1.png"];
	[collectibleSpriteSheet addChild:collectible];
	
	result.collectibleIcon = collectible;
	result.collectibleIcon.scale = 0.5;
	result.collectibleIcon.anchorPoint = ccp(0, 0.5);
	result.collectibleIcon.position = ccp(0, result.contentSize.height / 2);
	
	result.scoreLabel = [CCLabelBMFont labelWithString:
						 [NSString stringWithFormat:@"x%d", 0]
															 fntFile:@"game_font.fnt"];
	result.scoreLabel.anchorPoint = ccp(0, 0.5);
	result.scoreLabel.position = ccp(result.collectibleIcon.contentSize.width * result.collectibleIcon.scale, result.contentSize.height / 2);
	
	if ([result.gameLayer.level.collectiblesCaptured count] > 0) {
		result.label1.visible = NO;
		result.scoreLabel.visible = YES;
		result.collectibleIcon.visible = YES;
	}
	else {
		result.label1.visible = YES;
		result.scoreLabel.visible = NO;
		result.collectibleIcon.visible = NO;
	}
	
	[result addChild:result.label1];
	[result addChild:result.scoreLabel];
	
	NSString *playerImage = ([GameState gameState].levelsAchieved > NumLevels) ? (@"player-win") : (@"player");
	
	CCSpriteBatchNode *playerSpriteSheet = [CCSpriteBatchNode batchNodeWithFile:[NSString stringWithFormat:@"%@.png", playerImage]];
	[result addChild:playerSpriteSheet];
	
	result.playerQuitIcon = [Player initDefaults:[NSString stringWithFormat:@"%@1.png", playerImage]];
	result.playerQuitIcon.scale = 0.5;
	result.playerQuitIcon.anchorPoint = ccp(0, 0.5);
	result.playerQuitIcon.position = ccp(4, result.contentSize.height / 2);
	result.playerQuitIcon.color = ccRED;
	result.playerQuitIcon.flipY = YES;
	[playerSpriteSheet addChild:result.playerQuitIcon];	
	
	result.resumeLabel = [CCLabelBMFont labelWithString:@"CONTINUE"
															  fntFile:@"game_font.fnt"];
	result.quitLabel = [CCLabelBMFont labelWithString:@"QUIT"
															fntFile:@"game_font.fnt"];
	
	result.resumeLabel.anchorPoint = ccp(1, 0.5);
	result.quitLabel.anchorPoint = ccp(0, 0.5);
	
	result.resumeLabel.position = ccp(result.contentSize.width, result.contentSize.height / 2);
	result.quitLabel.position = ccp(result.playerQuitIcon.scaledWidth + result.playerQuitIcon.position.x + 4, result.contentSize.height / 2);
	
	[result addChild:result.resumeLabel];
	[result addChild:result.quitLabel];
	
	result.playerResumeIcon = [Player initDefaults:[NSString stringWithFormat:@"%@1.png", playerImage]];
	result.playerResumeIcon.scale = 0.5;
	result.playerResumeIcon.anchorPoint = ccp(1, 0.5);
	result.playerResumeIcon.position = ccp(result.resumeLabel.position.x - result.resumeLabel.contentSize.width - 4, result.contentSize.height / 2);
	[playerSpriteSheet addChild:result.playerResumeIcon];	
	
	result.playerResumeIcon.visible = result.playerQuitIcon.visible = result.resumeLabel.visible = result.quitLabel.visible = NO;
	
	result.warningLabel = [CCLabelBMFont labelWithString:@"!"
															   fntFile:@"game_font.fnt"];
	result.warningLabel.visible = NO;
	
	result.warningLabel.anchorPoint = ccp(0.5, 0.5);
	result.warningLabel.position = ccp(result.contentSize.width / 2, result.contentSize.height / 2);
	[result addChild:result.warningLabel];
	
	return result;
}

- (void)setWarning:(BOOL)value {
	if (self.warningLabel.visible != value) {
		self.warningLabel.visible = value;
		if ((value == YES) && (self.label1.visible)) {
			self.label1.visible = NO;
		}
		else if (!(self.scoreLabel.visible)) {
			self.label1.visible = YES;
		}
	}
}

- (void)updateScore {
	self.label1.visible = NO;
	self.scoreLabel.visible = YES;
	self.collectibleIcon.visible = YES;
	[self.scoreLabel setString:[NSString stringWithFormat:@"x%d", self.gameLayer.level.totalCollectibles]];
}

- (void)resumeLevel:(id)sender {
	self.gameLayer.player.color = ccWHITE;
	self.playerResumeIcon.visible = self.playerQuitIcon.visible = self.resumeLabel.visible = self.quitLabel.visible = NO;
	
	if ([self.gameLayer.level.collectiblesCaptured count] > 0) {
		self.label1.visible = NO;
		self.scoreLabel.visible = YES;
		self.collectibleIcon.visible = YES;
	}
	else {
		self.label1.visible = YES;
		self.scoreLabel.visible = NO;
		self.collectibleIcon.visible = NO;
	}
	
	if ((!(self.gameLayer.player.isDead))
		&& (!(self.gameLayer.player.hasWon))) {
		self.isTouchEnabled = YES;
		self.gameLayer.isPaused = NO;
	}
	[[CCDirector sharedDirector] resume];
	[self.gameLayer resumeSchedulerAndActions];
	[self.gameLayer onEnter];
}

- (void)replayLevel:(id)sender {
	[self resumeLevel:self];
	[[CCDirector sharedDirector] replaceScene:[CCTransitionTurnOffTiles
											   transitionWithDuration:0.5f
											   scene:[Whaley scene:self.gameLayer.level withGameMode:self.gameLayer.level.gameMode]]];
	[self.gameLayer releaseRetained];
}

- (void)exitLevel:(id)sender {
	[self.gameLayer.level.collectiblesCaptured removeAllObjects];
	self.gameLayer.level.checkpointIndex = -1;
	self.gameLayer.level.totalTime = 0;
	self.gameLayer.level.bubblesUsed = 0;
	[GameState saveGameStateToFile];
	
	[[CCDirector sharedDirector] resume];
	[[CCDirector sharedDirector] replaceScene:[CCTransitionTurnOffTiles
											   transitionWithDuration:0.5f
											   scene:[MainMenu initWithLevelsAchieved]]];
	[self.gameLayer releaseRetained];
}

- (void)pauseGame:(id)sender {
	self.gameLayer.player.color = ccGRAY;
	if (!(self.gameLayer.isPaused)) {
		if (!(self.gameLayer.player.isDead)) {
			[[SimpleAudioEngine sharedEngine] playEffect:@"pause01.wav"];
		}
		
		[self.gameLayer pauseSchedulerAndActions];
		[self.gameLayer onExit];
		[[CCDirector sharedDirector] pause];
		self.gameLayer.isPaused = YES;
		self.isTouchEnabled = YES;
		
		self.playerResumeIcon.visible = self.playerQuitIcon.visible = self.resumeLabel.visible = self.quitLabel.visible = YES;
		self.label1.visible = NO;
		self.scoreLabel.visible = NO;
		self.warningLabel.visible = NO;
		self.collectibleIcon.visible = NO;
	}
}

- (void)registerWithTouchDispatcher {
	// The game layer also registers at priority 0 and swallows touches.
	// Keep the HUD ahead of it after resumeLevel: re-registers gameplay.
	[[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:self priority:-1 swallowsTouches:YES];
}

- (BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
	// Only capture touches in the HUD's 32-point top bar. Gameplay touches
	// outside it must continue to reach the Whaley layer.
	CGPoint point = [touch locationInView:[touch view]];
	point = [[CCDirector sharedDirector] convertToGL:point];
	point = [self convertToNodeSpace:point];
	if (!CGRectContainsPoint(CGRectMake(0, 0, self.contentSize.width,
	                                    self.contentSize.height), point)) {
		return NO;
	}
	if (!self.gameLayer.isPaused) {
		[self pauseGame:self];
		return YES;
	}

	CGPoint touchLocation = [touch locationInView:[touch view]];
	touchLocation = [[CCDirector sharedDirector] convertToGL:touchLocation];
	touchLocation = [self convertToNodeSpace:touchLocation];
	
	CGRect touchRect = CGRectMake(touchLocation.x,
								  touchLocation.y,
								  1,
								  1);
	CGRect quitRect = CGRectMake(0, 0, self.quitLabel.contentSize.width + self.quitLabel.position.x, self.contentSize.height);
	
	if (CGRectIntersectsRect(touchRect, quitRect)) {
		[self exitLevel:self];
		self.gameLayer.player.color = ccRED;
		self.gameLayer.player.flipY = YES;
		return NO;
	}
	
	if ((!(self.gameLayer.player.isDead))
		&& (!(self.gameLayer.player.hasWon))) {
		[self resumeLevel:self];
	}
	return YES;
}

- (void)ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
}

- (void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
	// The top-bar action is handled in ccTouchBegan:. Re-pausing here
	// would undo Continue on the same touch sequence.
}

- (void)dealloc {
	self.gameLayer = nil;
	self.label1 = nil;
	self.scoreLabel = nil;
	self.collectibleIcon = nil;
	self.resumeLabel = nil;
	self.quitLabel = nil;
	self.warningLabel = nil;
	self.playerQuitIcon = nil;
	self.playerResumeIcon = nil;	
	[super dealloc];
}

@end
