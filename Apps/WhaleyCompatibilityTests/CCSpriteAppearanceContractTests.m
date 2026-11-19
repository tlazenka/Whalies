#import <XCTest/XCTest.h>
#import "../../Sources/WhaleyObjectiveC/cocos2d.h"

@interface CCSpriteAppearanceContractTests : XCTestCase
@end

@implementation CCSpriteAppearanceContractTests

- (void)testOpacityReadWriteAndActionOwnership {
    CCSprite *sprite = [[CCSprite spriteWithFile:@"bubble01.png"] retain];
    XCTAssertNotNil(sprite.spriteKitNode);
    sprite.opacity = 100;
    XCTAssertEqual(sprite.opacity, 100);
    XCTAssertEqualWithAccuracy(sprite.alpha, 100.0 / 255.0, 0.001);
    XCTAssertEqualWithAccuracy(sprite.spriteKitNode.alpha, 1.0, 0.001);
    [sprite runAction:[SKAction fadeAlphaTo:0.75 duration:60] withKey:@"nativeFade"];
    XCTAssertNotNil([sprite actionForKey:@"nativeFade"]);
    CCFiniteTimeAction *fade = [CCFadeTo actionWithDuration:60 opacity:210];
    [sprite runAction:fade];
    NSString *key = [NSString stringWithFormat:@"whaley.cocos2d.action.%p", fade];
    XCTAssertNotNil([sprite actionForKey:key]);
    [sprite stopAction:fade];
    XCTAssertNil([sprite actionForKey:key]);
    XCTAssertNotNil([sprite actionForKey:@"nativeFade"]);
    [sprite stopAllActions];
    [sprite release];
}

- (void)testColorReadbackFollowsDrawableTint {
    CCSprite *sprite = [[CCSprite spriteWithFile:@"bubble01.png"] retain];
    sprite.color = ccRED;
    ccColor3B red = sprite.color;
    XCTAssertEqual(red.r, 255);
    XCTAssertEqual(red.g, 0);
    XCTAssertEqual(red.b, 0);
    sprite.color = ccc3(102, 130, 255);
    ccColor3B value = sprite.color;
    XCTAssertEqualWithAccuracy(value.r, 102, 1);
    XCTAssertEqualWithAccuracy(value.g, 130, 1);
    XCTAssertEqualWithAccuracy(value.b, 255, 1);
    [sprite release];
}

@end
