//
//  Created by Francis Lazenka on 8/18/10.
//

#import "MainMenu.h"
#import "GameState.h"
#import "ParticleDust.h"
#import "CocosDenshion.h"
#import "SimpleAudioEngine.h"
#import "WhaleyLevelArtwork.h"

@implementation MainMenu

@synthesize label1 = _label1;
@synthesize levelImages = _levelImages;
@synthesize bubble = _bubble;
@synthesize extraBounceBubble = _extraBounceBubble;
@synthesize zoomedLevelImage = _zoomedLevelImage;
@synthesize zoomTouch = _zoomTouch;

@synthesize wonGame = _wonGame;
@synthesize zoomLevelImage = _zoomLevelImage;
@synthesize credits = _credits;

@synthesize currentTouchedLevelIndex = _currentTouchedLevelIndex;

@synthesize zoomIsScheduled = _zoomIsScheduled;
@synthesize knockSound = _knockSound;

const NSInteger CharacterTransparency = 100;

//http://pocketworx.com/?p=147
- (void)createExplosionX:(CGFloat)x y:(CGFloat)y {
	CCParticleSystemQuad *emitter = [ParticleDust node];
	emitter.position = ccp(x, y);
	[self addChild:emitter z:10];
	emitter.autoRemoveOnFinish = YES;
}	

- (void)scheduleZoom {
    if (!(self.zoomIsScheduled)) {
        [self schedule:@selector(zoomLevelImage:) interval:1.0f];
        self.zoomIsScheduled = YES;
    }
}

- (void)unscheduleZoom {
    //if (self.zoomIsScheduled) {
        [self unschedule:@selector(zoomLevelImage:)];
        self.zoomIsScheduled = NO;
    //}
}

- (void)clearHighlightOverlays {
    for (id theKey in self.levelImages) {
        CCNode *layer = [[self.levelImages objectForKey:theKey] getChildByTag:HighlightOverlayTag];
        if ([layer isKindOfClass:[CCLayerColor class]]) {
            layer.visible = NO;
        }
    }
}

-(NSInteger)validLevelImageForTouch:(CGPoint)touchLocation {
    for (id theKey in self.levelImages) {
        NSInteger levelNum = [(NSString *)theKey intValue];
        if ((levelNum <= [GameState gameState].levelsAchieved)
            && (CGRectContainsPoint([Helpers spriteRectangle:(CCNode *)[self.levelImages objectForKey:theKey]], touchLocation))) {
            return levelNum;
        }
    }
    return -1;
}

- (void)zoomLevelImage:(ccTime)dt {
    [self unscheduleZoom];
	self.zoomLevelImage = NO;
    
    if (self.zoomTouch) {
        CGSize size = [[CCDirector sharedDirector] winSize];
        CGPoint touchLocation = [self.zoomTouch locationInView:[self.zoomTouch view]];
        touchLocation = [[CCDirector sharedDirector] convertToGL:touchLocation];
        touchLocation = [self convertToNodeSpace:touchLocation];
        
        NSInteger levelIndex = [self validLevelImageForTouch:touchLocation];
        
        if ((levelIndex != -1) && (levelIndex == self.currentTouchedLevelIndex)) {
            NSString *foregroundFileName = WhaleyLevelArtworkFilename(levelIndex, [Helpers isiPhone5]);
            self.zoomedLevelImage = [CCSprite spriteWithFile:foregroundFileName];
            self.zoomLevelImage = YES;
            // Keep the complete original painting inside the logical surface,
            // independently of its source resolution or the device's scale.
            self.zoomedLevelImage.scaleX = size.width / self.zoomedLevelImage.contentSize.width;
            self.zoomedLevelImage.scaleY = size.height / self.zoomedLevelImage.contentSize.height;
            self.zoomedLevelImage.position = ccp(size.width / 2, size.height / 2);
            [self.zoomedLevelImage runAction:[CCFadeIn actionWithDuration:0.1f]];
            self.zoomedLevelImage.opacity = 0;
            [self addChild:self.zoomedLevelImage];
            self.currentTouchedLevelIndex = -1;
        }
    }
}

- (void)registerWithTouchDispatcher {
	[[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:self priority:0 swallowsTouches:YES];
}

- (void)setCurrentOverlay {
    CCNode *layer = [[self.levelImages
                      objectForKey:
                      [NSString stringWithFormat:@"%d", self.currentTouchedLevelIndex]] getChildByTag:HighlightOverlayTag];
    if ([layer isKindOfClass:[CCLayerColor class]]) {
        layer.visible = YES;
    }
}

- (BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
    [self unscheduleZoom];
	if (!(_zoomLevelImage)) {
		CGPoint touchLocation = [touch locationInView:[touch view]];
		touchLocation = [[CCDirector sharedDirector] convertToGL:touchLocation];
		touchLocation = [self convertToNodeSpace:touchLocation];
		
		CGRect touchRect = CGRectMake(touchLocation.x,
									  touchLocation.y,
									  1,
									  1);
        
        self.zoomTouch = nil;

        self.currentTouchedLevelIndex = [self validLevelImageForTouch:touchLocation];
        if (self.currentTouchedLevelIndex != -1) {
            [self setCurrentOverlay];
            [self scheduleZoom];
            self.zoomTouch = touch;
        }
		
		if (self.currentTouchedLevelIndex == -1) {
			
			BOOL poppedBubble = NO;
			
			if ((self.extraBounceBubble.visible)
                && ([Helpers rectIntersectsCircle:touchRect
									forCircle:[Helpers spriteRectangle:self.extraBounceBubble]
							 withRadiusOffset:20
						  withRectWidthOffset:0
						 withRectHeightOffset:0])) {
				//[self removeChild:self.extraBounceBubble cleanup:NO];
				self.extraBounceBubble.visible = NO;
				[GameState gameState].hasExtraBounce = NO;
				[GameState saveGameStateToFile];
				poppedBubble = YES;
			}
			
			if (!(poppedBubble)) {
                
                //if (!(self.knockSound.isPlaying)) {
                    [self.knockSound play];
                //}
				
				/*if (touchLocation.y < self.label1.position.y)*/ {
					for (id theKey in self.levelImages) {
						CCNode *levelImage = (CCNode *)[self.levelImages objectForKey:theKey];
						CGFloat angle = 0;
						if (levelImage.rotation != 0) {
							angle = -(levelImage.rotation);
						}
						else {
							angle = [Helpers getRandomLevelImageAngle];
						}
						
						((Level *)[[GameState gameState].levels objectAtIndex:levelImage.tag]).levelImageRotation =
						(levelImage.rotation + angle);
						
						[levelImage runAction:[CCRotateBy actionWithDuration:0.1f angle:angle]];
					}
				}
				
				for(NSInteger i = 0; i < [self.label1.children count]; i++) {
					CCSprite *child = (CCSprite *)[self.label1 getChildByTag:i];
					
					CGPoint childPosition = ccp(child.position.x - (child.contentSize.width / 2),
												child.position.y - (child.contentSize.height / 2));
					
					CGPoint labelPosition = ccp(self.label1.position.x,
												self.label1.position.y);		
					
					childPosition = ccp(childPosition.x + labelPosition.x,
										childPosition.y + labelPosition.y);
					
					CGRect childRect = CGRectMake(childPosition.x,
												  childPosition.y,
												  child.contentSize.width,
												  child.contentSize.height);
					
					if ((CGRectIntersectsRect(touchRect, childRect))
						&& (child.opacity == 255)) {
						[[GameState gameState].transparentGameTitleCharacters replaceObjectAtIndex:child.tag withObject:[NSNumber numberWithInt:1]];
						//child.opacity = 0;
						[child runAction:[CCFadeTo actionWithDuration:0.1f opacity:CharacterTransparency]];
						[self createExplosionX:touchLocation.x
											 y:touchLocation.y];
					}
				}
				
				BOOL allAtZero = YES;
				for (id theKey in self.levelImages) {
					CCNode *levelImage = (CCNode *)[self.levelImages objectForKey:theKey];
					if (ABS(((Level *)[[GameState gameState].levels objectAtIndex:levelImage.tag]).levelImageRotation) > 0.5f) {
						allAtZero = NO;
						break;
					}
				}
				
				if ((allAtZero)
					&& (!(_wonGame))) {
					[GameState gameState].hasExtraBounce = YES;
					self.extraBounceBubble.visible = YES;
				}
                /*
                if ((CGRectIntersectsRect(touchRect, self.credits.boundingBox))
                    && (self.credits.opacity == 255)) {
                    [GameState gameState].transparentCredits = YES;
                    [self.credits runAction:[CCFadeTo actionWithDuration:0.1f opacity:CharacterTransparency]];
                    [self createExplosionX:touchLocation.x
                                         y:touchLocation.y];
                }
                 */
			}
		}
		[GameState saveGameStateToFile];
	}
	else {
		_zoomLevelImage = NO;
		[self.zoomedLevelImage runAction:[CCFadeOut actionWithDuration:0.1f]];
        [self clearHighlightOverlays];
		return NO;
	}
	
	return YES;
}

- (void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
	[self unscheduleZoom];
	if (!(_zoomLevelImage)) {
		
		CGPoint touchLocation = [touch locationInView:[touch view]];
		touchLocation = [[CCDirector sharedDirector] convertToGL:touchLocation];
		touchLocation = [self convertToNodeSpace:touchLocation];
		
        BOOL startingLevel = NO;
        
        NSInteger levelNum = [self validLevelImageForTouch:touchLocation];
        if ((levelNum != -1) && (self.currentTouchedLevelIndex == levelNum)) {
            Level *level = [[GameState gameState].levels objectAtIndex:(levelNum - 1)];
            
            NSInteger gameMode = NormalBubble;
            
            startingLevel = YES;
            
            if ([GameState gameState].hasExtraBounce) {
                gameMode = ExtraBounce;
            }
            else if (_wonGame) {
                gameMode = InfiniteBubble;
            }
            
            [[CCDirector sharedDirector] replaceScene:[CCTransitionTurnOffTiles
                                                       transitionWithDuration:0.5f
                                                       scene:[Whaley scene:level withGameMode:gameMode]]];
        }
        
        self.currentTouchedLevelIndex = -1;
        
        if (!(startingLevel)) {
            [self clearHighlightOverlays];
        }
	}
}

- (void)ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
    if ((!(self.zoomLevelImage)) && (self.currentTouchedLevelIndex != -1)) {
        CGPoint touchLocation = [touch locationInView:[touch view]];
		touchLocation = [[CCDirector sharedDirector] convertToGL:touchLocation];
		touchLocation = [self convertToNodeSpace:touchLocation];

        if (self.currentTouchedLevelIndex != [self validLevelImageForTouch:touchLocation]) {
            [self unscheduleZoom];
            self.zoomTouch = nil;
            [self clearHighlightOverlays];
        }
        else {
            [self setCurrentOverlay];
            self.zoomTouch = touch;
            [self scheduleZoom];
        }
    }
}

//http://www.cocos2d-iphone.org/forum/topic/5088
- (void)setOpacity:(GLubyte)opacity {
	for (CCNode *node in [self children]) {
		if([node conformsToProtocol:@protocol(CCRGBAProtocol)]) {
			[(id<CCRGBAProtocol>)node setOpacity:opacity];
		}
	}
}

- (void)runFadeIn:(ccTime)duration {
	for (CCNode *node in [self children]) {
		[node runAction:[CCFadeIn actionWithDuration:duration]];
	}
}

+ (id)initWithLevelsAchieved {
    return [MainMenu initWithLevelsAchieved:NO];
}

+ (id)initWithLevelsAchieved:(BOOL)firstLaunch {
	MainMenu *result = [MainMenu node];
    
    result.knockSound = [[SimpleAudioEngine sharedEngine] soundSourceForFile:@"knock.mp3"];
    result.knockSound.gain = 0.5f;

    result.zoomIsScheduled = NO;
    
    result.currentTouchedLevelIndex = -1;
    
	result.zoomLevelImage = NO;
	
	result.wonGame = [GameState gameState].levelsAchieved > NumLevels;
	
	[[SimpleAudioEngine sharedEngine] resumeBackgroundMusic];
	
	result.isTouchEnabled = YES;
	
	NSString *backgroundFileName = nil;
	if ([Helpers isiPhone5]) {
		backgroundFileName = @"Default-568h@2x.png";
	}
	else {
		backgroundFileName = @"Default.png";		
	}
	
	CCSprite *back = [CCSprite spriteWithFile:backgroundFileName];
	back.anchorPoint = ccp(0, 0);
	back.position = ccp(0, 0);
	[result addChild:back];
	
	CGFloat yPadding = 20;
	CGSize size = [[CCDirector sharedDirector] winSize];
	
	if (result.wonGame) {
		result.label1 = [CCLabelBMFont labelWithString:GameName2 fntFile:@"title_font2.fnt"];
	}
	else {
		result.label1 = [CCLabelBMFont labelWithString:GameName1 fntFile:@"title_font.fnt"];
	}

	//hard coded because of ligatures
	result.label1.anchorPoint = ccp(0, 0);
	result.label1.position = ccp(24, (size.height - result.label1.contentSize.height) - yPadding);
	
	result.label1.opacity = 0;
	[result addChild:result.label1];
	
	NSMutableArray *transparentCharacters = [GameState gameState].transparentGameTitleCharacters;
	
	for (NSInteger i = 0; i < [[result.label1 children] count]; i++) {
		CCSprite *child = (CCSprite *)[result.label1 getChildByTag:i];
		if ([[transparentCharacters objectAtIndex:child.tag]isKindOfClass:[NSNull class]]) {
			[child runAction:[CCFadeIn actionWithDuration:0.1f]];
		}
		else {
			[child runAction:[CCFadeTo actionWithDuration:0.1f opacity:CharacterTransparency]];
		}
	}
    /*
    result.credits = [CCSprite spriteWithFile:@"credits.png"];
	result.credits.anchorPoint = ccp(0, 0);
    result.credits.position = ccp(0, 35);
    result.credits.opacity = 0;
	[result addChild:result.credits];
    NSInteger transparency = ([GameState gameState].transparentCredits) ? (CharacterTransparency) : (255);
    CGFloat duration = (firstLaunch) ? (0.5f) : (0);
    [result.credits runAction:[CCSequence actions:
                               [CCDelayTime actionWithDuration:duration],
                               [CCFadeTo actionWithDuration:0.1f
                                                    opacity:transparency],
                               nil]];
	*/
	result.levelImages = [[NSMutableDictionary new] autorelease];
	
	CGFloat iconScale = 0.2f;
	CGFloat yOffset = result.label1.position.y;
	CGFloat xOffset = 0;
	
	yPadding = 15;
	CGFloat xPadding = 20;
    CGFloat contentXdiv = 320 / 1.6;
	CGFloat contentYdiv = 480 / 1.6;
    
	for(NSInteger i = 1; i <= NumLevels; ++i) {
		CCNode *levelImage = [CCNode node];
		
		CCSprite *frame = [CCSprite spriteWithFile:[NSString stringWithFormat:@"frame.png"]];
		frame.anchorPoint = ccp(0, 0);
		frame.position = ccp(0, 0);
		levelImage.contentSize = frame.contentSize;
		levelImage.rotation = ((Level *)[[GameState gameState].levels objectAtIndex:(i - 1)]).levelImageRotation;
		levelImage.tag = i - 1;
		
		if (i <= [GameState gameState].levelsAchieved) {
			CCSprite *levelIcon = [CCSprite spriteWithFile:WhaleyLevelArtworkFilename(i, NO)];
			levelIcon.scaleX = (contentXdiv / levelIcon.contentSize.width);
			levelIcon.scaleY = (contentYdiv / levelIcon.contentSize.height);
			levelIcon.position = ccp((frame.contentSize.width / 2) * frame.scaleX,
									 (frame.contentSize.height / 2)  * frame.scaleY);
			
			[levelImage addChild:levelIcon];
		}
		[levelImage addChild:frame];
		levelImage.scaleX = levelImage.scaleY = iconScale;
		
		if ((i == 1) || (i == 4)) {
			yOffset -= ((levelImage.contentSize.height * levelImage.scaleY) + yPadding);
			xOffset = ((size.width - (((levelImage.contentSize.width * levelImage.scaleX) + xPadding) * 3)) / 2) + (xPadding / 2);
		}
		
		levelImage.position = ccp(xOffset, yOffset);
		
		xOffset += ((levelImage.contentSize.width * levelImage.scaleX) + xPadding);
		
		[result.levelImages setObject:levelImage forKey:[NSString stringWithFormat:@"%d", i]];
		[result addChild:levelImage];
        
        CCLayerColor *layer = [CCLayerColor layerWithColor:ccc4(0, 0, 0, 100) width:levelImage.contentSize.width height:levelImage.contentSize.height];
        layer.tag = HighlightOverlayTag;
        layer.visible = NO;
        [levelImage addChild:layer];
	}
	
	if (result.wonGame) {
		result.bubble = [CCSprite spriteWithFile:@"bubble01.png"];
		result.bubble.anchorPoint = ccp(0.5, 0.5);
		result.bubble.scaleX = 0.0625;
		result.bubble.scaleY = 0.0625;
		//result.bubble.opacity = 200;
		result.bubble.position = ccp(result.label1.position.x + result.label1.contentSize.width + 14,
									 result.label1.position.y + 52);
		[result addChild:result.bubble];
	}
	result.extraBounceBubble = [CCSprite spriteWithFile:@"bubble01.png"];
	result.extraBounceBubble.color = Magenta;
	result.extraBounceBubble.anchorPoint = ccp(0.5, 0.5);
	result.extraBounceBubble.scaleX = 0.125;
	result.extraBounceBubble.scaleY = 0.125;
	result.extraBounceBubble.opacity = 150;
	result.extraBounceBubble.visible = NO;
	result.extraBounceBubble.position = ccp(result.contentSize.width / 2 - 19,
											result.label1.position.y + 65);
	[result addChild:result.extraBounceBubble];
	
	if ([GameState gameState].hasExtraBounce) {
		result.extraBounceBubble.visible = YES;
	}
	
	return result;
}

- (void)dealloc {
	self.label1 = nil;
    self.credits = nil;
    [self.knockSound stop];
	self.knockSound = nil;
	[self.levelImages removeAllObjects];
	self.levelImages = nil;
	self.bubble = nil;
	self.extraBounceBubble = nil;
	self.zoomedLevelImage = nil;
	self.zoomTouch = nil;
	[super dealloc];
}

@end
