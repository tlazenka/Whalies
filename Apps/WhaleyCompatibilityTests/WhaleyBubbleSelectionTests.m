#import <XCTest/XCTest.h>
#import "../../Sources/WhaleyObjectiveC/src/Whaley3DShot.h"
#import "../../Sources/WhaleyObjectiveC/src/Whaley3DBubbleSelection.h"

@interface WhaleyArenaBounceTests : XCTestCase
- (void)withArena:(void (^)(Whaley *game))body;
@end
@interface Whaley (BubbleSelectionTestAccess)
- (void)gameLoop:(ccTime)dt;
@end

@implementation WhaleyArenaBounceTests (BubbleSelection)
- (Projectile *)selectionShot:(Whaley *)game {
    game.bubbleFileName = @"infinite_bubble.png";
    game.player.position = CGPointMake(300, 300);
    game.player.airMode = FALLING;
    game.player.yAdd = SlowYspd;
    WhaleyScene3DJumpSequence = 0;
    return WhaleyCreate3DShot(game, 0);
}

- (void)testExistingShotLookupDoesNotCreateMoveOrChargeForAShot {
    [self withArena:^(Whaley *game) {
        Projectile *shot = [self selectionShot:game];
        XCTAssertNotNil(shot);
        if (!shot) return;
        NSUInteger count = game.projectiles.count;
        NSInteger score = game.level.bubblesUsed;
        CGPoint center = shot.position;
        shot.sizeMode *= 1.5;
        CGFloat scale = shot.sizeMode;
        Projectile *selected = WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot",
            ^NSString *(GameObject *object) { return object == shot ? @"shot" : @"other"; });
        XCTAssertEqual(selected, shot);
        XCTAssertEqualWithAccuracy(selected.sizeMode, scale, 0.00001);
        XCTAssertTrue(CGPointEqualToPoint(selected.position, center));
        XCTAssertEqual(game.projectiles.count, count);
        XCTAssertEqual(game.level.bubblesUsed, score);
    }];
}

- (void)testMissingOrOldSceneSelectionDoesNotFallBackToNewShot {
    [self withArena:^(Whaley *game) {
        Projectile *shot = [self selectionShot:game];
        NSString *(^identity)(GameObject *) = ^NSString *(GameObject *object) {
            return object == shot ? @"shot" : @"other";
        };
        NSUInteger count = game.projectiles.count;
        NSInteger used = game.level.bubblesUsed;
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"old", @"new", @"shot", identity));
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"missing", identity));
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"", @"s", @"shot", identity));
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"", identity));
        XCTAssertEqual(game.projectiles.count, count);
        XCTAssertEqual(game.level.bubblesUsed, used);
    }];
}

- (void)testFoundationCannotBeSelectedEvenWithMatchingID {
    [self withArena:^(Whaley *game) {
        Projectile *foundation = game.projectiles.firstObject;
        XCTAssertTrue(WhaleySceneIs3DFoundation(foundation));
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"foundation",
            ^NSString *(GameObject *object) { return object == foundation ? @"foundation" : @"other"; }));
        XCTAssertEqual(foundation.bouncesLeft, (NSInteger)-1);
    }];
}

- (void)testIneligibleGameAndShotStatesRejectSelection {
    [self withArena:^(Whaley *game) {
        Projectile *shot = [self selectionShot:game];
        if (!shot) { XCTFail(@"Expected real shot"); return; }
        NSString *(^identity)(GameObject *) = ^NSString *(GameObject *object) {
            return object == shot ? @"shot" : @"other";
        };
        game.isPaused = YES;
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity));
        game.isPaused = NO; game.player.isDead = YES;
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity));
        game.player.isDead = NO; game.player.hasWon = YES;
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity));
        game.player.hasWon = NO; shot.visible = NO;
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity));
        shot.visible = YES; shot.isFrozen = NO;
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity));
        shot.isFrozen = YES; shot.isBeingMoved = YES;
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity));
        shot.isBeingMoved = NO; shot.bouncesLeft = 0;
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity));
        shot.bouncesLeft = 1;
        WhaleyScene3DModeEnabled = NO;
        XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity));
        WhaleyScene3DModeEnabled = YES;
    }];
}

- (void)testRealBounceMakesPreviouslySelectedIDUnavailable {
    [self withArena:^(Whaley *game) {
        Projectile *shot = [[self selectionShot:game] retain];
        @try {
            XCTAssertNotNil(shot);
            if (!shot) return;
            NSString *(^identity)(GameObject *) = ^NSString *(GameObject *object) {
                return object == shot ? @"shot" : @"other";
            };
            XCTAssertEqual(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity), shot);
            [game gameLoop:1.0 / 60.0];
            XCTAssertNil(shot.parent);
            NSUInteger count = game.projectiles.count;
            NSInteger used = game.level.bubblesUsed;
            XCTAssertNil(WhaleyFind3DGrowableBubble(game, @"s", @"s", @"shot", identity));
            XCTAssertEqual(game.projectiles.count, count);
            XCTAssertEqual(game.level.bubblesUsed, used);
        } @finally { [shot release]; }
    }];
}
@end
