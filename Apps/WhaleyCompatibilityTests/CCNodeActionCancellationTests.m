#import <XCTest/XCTest.h>
#import "../../Sources/WhaleyObjectiveC/cocos2d.h"
#import "../../Sources/WhaleyObjectiveC/src/Projectile.h"

// Exercise the real SpriteKit compatibility classes on an Apple SDK. The C
// arena-geometry tests cannot detect missing Objective-C runtime selectors.
@interface CCNodeActionCancellationTests : XCTestCase
@end

@implementation CCNodeActionCancellationTests

- (void)onMain:(void (^)(void))body {
    if ([NSThread isMainThread]) {
        body();
    } else {
        dispatch_sync(dispatch_get_main_queue(), body);
    }
}

- (void)testProjectileInheritsCancellationAndCancelsTranslatedActions {
    [self onMain:^{
        Projectile *projectile = [Projectile new];
        XCTAssertTrue([projectile respondsToSelector:@selector(stopAllActions)]);
        CCFiniteTimeAction *wait = [CCDelayTime actionWithDuration:60];
        [projectile runAction:wait];
        [wait release];
        XCTAssertTrue([projectile hasActions]);
        XCTAssertNoThrow([projectile stopAllActions]);
        XCTAssertFalse([projectile hasActions]);
        [projectile release];
    }];
}

- (void)testCancelsAllNamedActionsWithoutMovingOrDetachingTheProjectile {
    [self onMain:^{
        SKNode *parent = [SKNode node];
        Projectile *projectile = [Projectile new];
        [parent addChild:projectile];
        projectile.position = CGPointMake(21, 34);
        projectile.scaleX = 0.75;
        projectile.scaleY = 0.9;
        [projectile runAction:[SKAction waitForDuration:60] withKey:@"move"];
        [projectile runAction:[SKAction waitForDuration:60] withKey:@"scale"];
        XCTAssertNotNil([projectile actionForKey:@"move"]);
        XCTAssertNotNil([projectile actionForKey:@"scale"]);
        [projectile stopAllActions];
        XCTAssertNil([projectile actionForKey:@"move"]);
        XCTAssertNil([projectile actionForKey:@"scale"]);
        XCTAssertFalse([projectile hasActions]);
        XCTAssertTrue(CGPointEqualToPoint(projectile.position, CGPointMake(21, 34)));
        XCTAssertEqualWithAccuracy(projectile.scaleX, 0.75, 0.00001);
        XCTAssertEqualWithAccuracy(projectile.scaleY, 0.9, 0.00001);
        XCTAssertEqual(projectile.parent, parent);
        [projectile release];
    }];
}

- (void)testCancellationIsLocalAndDoesNotCancelChildOrSiblingActions {
    [self onMain:^{
        SKNode *parent = [SKNode node];
        Projectile *projectile = [Projectile new];
        SKNode *child = [SKNode node];
        SKNode *sibling = [SKNode node];
        [parent addChild:projectile];
        [parent addChild:sibling];
        [projectile addChild:child];
        [child runAction:[SKAction waitForDuration:60] withKey:@"child"];
        [sibling runAction:[SKAction waitForDuration:60] withKey:@"sibling"];
        [projectile runAction:[SKAction waitForDuration:60] withKey:@"projectile"];
        [projectile stopAllActions];
        XCTAssertFalse([projectile hasActions]);
        XCTAssertNotNil([child actionForKey:@"child"]);
        XCTAssertNotNil([sibling actionForKey:@"sibling"]);
        XCTAssertEqual(child.parent, projectile);
        [child removeAllActions];
        [sibling removeAllActions];
        [projectile release];
    }];
}

- (void)testRepeatedCancellationAllowsSubsequentActions {
    [self onMain:^{
        Projectile *projectile = [Projectile new];
        XCTAssertNoThrow([projectile stopAllActions]);
        XCTAssertNoThrow([projectile stopAllActions]);
        [projectile runAction:[SKAction waitForDuration:60] withKey:@"afterCancel"];
        XCTAssertNotNil([projectile actionForKey:@"afterCancel"]);
        [projectile stopAllActions];
        XCTAssertFalse([projectile hasActions]);
        [projectile release];
    }];
}

- (void)testStopActionOnlyCancelsTheRequestedCocosAction {
    [self onMain:^{
        CCNode *node = [CCNode node];
        CCFiniteTimeAction *first = [CCDelayTime actionWithDuration:60];
        CCFiniteTimeAction *second = [CCDelayTime actionWithDuration:60];
        NSString *firstKey = [NSString stringWithFormat:@"whaley.cocos2d.action.%p", first];
        NSString *secondKey = [NSString stringWithFormat:@"whaley.cocos2d.action.%p", second];
        [node runAction:first];
        [node runAction:second];
        [node runAction:[SKAction waitForDuration:60] withKey:@"unrelated"];
        [node stopAction:first];
        XCTAssertNil([node actionForKey:firstKey]);
        XCTAssertNotNil([node actionForKey:secondKey]);
        XCTAssertNotNil([node actionForKey:@"unrelated"]);
        [node stopAction:first]; // Idempotent.
        [node stopAction:second];
        XCTAssertNotNil([node actionForKey:@"unrelated"]);
        [node stopAllActions];
        XCTAssertFalse(node.hasActions);
        [first release];
        [second release];
    }];
}


@end
