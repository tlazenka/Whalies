#import <XCTest/XCTest.h>
#import "../../Sources/WhaleyObjectiveC/src/Whaley3DShot.h"

// Reuse the existing unscheduled, resource-isolated arena fixture. These
// category methods are discovered on the same XCTestCase; no duplicate fixture.
@interface WhaleyArenaBounceTests : XCTestCase
- (void)withArena:(void (^)(Whaley *game))body;
@end
@interface Whaley (WorldPlacementTestAccess)
- (void)gameLoop:(ccTime)dt;
@end

@implementation WhaleyArenaBounceTests (WorldPlacement)
- (void)prepareWorldPlacement:(Whaley *)game {
    game.bubbleFileName = @"infinite_bubble.png";
    game.player.position = CGPointMake(300, 300);
    game.player.airMode = FALLING;
    game.player.yAdd = SlowYspd;
    WhaleyScene3DJumpSequence = 0;
    WhaleyScene3DJumpAnchorBottom = CGPointZero;
}

- (void)testDirectCenterShotLaunchesAndPopsThroughTheActualGameLoop {
    [self withArena:^(Whaley *game) {
        [self prepareWorldPlacement:game];
        // Presentation transforms must not feed back into native placement.
        game.position = CGPointMake(-500, -900);
        game.scaleX = 0.4;
        game.scaleY = 1.6;
        NSUInteger foundations = game.projectiles.count;
        NSInteger used = game.level.bubblesUsed;
        Projectile *shot = [WhaleyCreate3DShot(game, 0) retain];
        @try {
            XCTAssertNotNil(shot);
            if (!shot) return;
            XCTAssertEqualWithAccuracy(shot.position.x, 316, 0.0001);
            XCTAssertEqualWithAccuracy(shot.position.y + shot.scaledHeight / 2, 302, 0.0001);
            XCTAssertEqual(game.level.bubblesUsed, used + 1);
            XCTAssertEqual(game.projectiles.count, foundations + 1);
            XCTAssertEqual(shot.parent, game);
            [game gameLoop:1.0 / 60.0];
            XCTAssertEqual(game.player.airMode, JUMPING_UP);
            XCTAssertFalse(game.player.isMovingLaterally);
            XCTAssertEqual(WhaleyScene3DJumpSequence, (NSUInteger)1);
            XCTAssertNil(shot.parent);
            XCTAssertEqual(game.projectiles.count, foundations);
        } @finally { [shot release]; }
    }];
}

- (void)testDirectSideShotsRetainLegacyAngledLaunchDirection {
    for (int side = -1; side <= 1; side += 2) {
        [self withArena:^(Whaley *game) {
            [self prepareWorldPlacement:game];
            Projectile *shot = WhaleyCreate3DShot(game, side);
            XCTAssertNotNil(shot);
            if (!shot) return;
            [game gameLoop:1.0 / 60.0];
            XCTAssertEqual(game.player.airMode, JUMPING_UP);
            XCTAssertTrue(game.player.isMovingLaterally);
            CGFloat center = [Helpers spriteCenter:game.player].x;
            if (side < 0) XCTAssertGreaterThan(game.player.desiredPos.x, center);
            else XCTAssertLessThan(game.player.desiredPos.x, center);
        }];
    }
}

- (void)testAirbornePlacementUsesJumpOriginUntilANewBounce {
    [self withArena:^(Whaley *game) {
        [self prepareWorldPlacement:game];
        game.player.airMode = JUMPING_UP;
        WhaleyScene3DJumpSequence = 9;
        WhaleyScene3DJumpAnchorBottom = CGPointMake(220, 180);
        Projectile *first = WhaleyCreate3DShot(game, 0);
        XCTAssertNotNil(first);
        game.player.position = CGPointMake(450, 600);
        Projectile *second = WhaleyCreate3DShot(game, 0);
        XCTAssertNotNil(second);
        XCTAssertEqualWithAccuracy(first.position.x, 220, 0.0001);
        XCTAssertTrue(CGPointEqualToPoint(first.position, second.position));
        WhaleyScene3DJumpSequence = 10;
        WhaleyScene3DJumpAnchorBottom = CGPointMake(300, 350);
        Projectile *third = WhaleyCreate3DShot(game, 0);
        XCTAssertNotNil(third);
        XCTAssertEqualWithAccuracy(third.position.x, 300, 0.0001);
        XCTAssertGreaterThan(third.position.y, second.position.y);
    }];
}

- (void)testCapacityEvictsAnOrdinaryShotButNeverTheFoundation {
    [self withArena:^(Whaley *game) {
        [self prepareWorldPlacement:game];
        NSArray *foundations = [[game.projectiles copy] autorelease];
        Projectile *first = [WhaleyCreate3DShot(game, 0) retain];
        @try {
            for (NSInteger i = 0; i < MAX_BUBBLES; i++) {
                XCTAssertNotNil(WhaleyCreate3DShot(game, 0));
            }
            XCTAssertNil(first.parent);
            XCTAssertEqual(game.projectiles.count, foundations.count + (NSUInteger)MAX_BUBBLES);
            for (Projectile *foundation in foundations) {
                XCTAssertEqual(foundation.parent, game);
                XCTAssertNotEqual([game.projectiles indexOfObjectIdenticalTo:foundation], NSNotFound);
                XCTAssertEqual(foundation.bouncesLeft, (NSInteger)-1);
            }
        } @finally { [first release]; }
    }];
}

- (void)testRejectedWorldShotsDoNotChangeScoreOrProjectileCount {
    [self withArena:^(Whaley *game) {
        [self prepareWorldPlacement:game];
        NSUInteger count = game.projectiles.count;
        NSInteger used = game.level.bubblesUsed;
        XCTAssertNil(WhaleyCreate3DShot(game, 2));
        game.isPaused = YES;
        XCTAssertNil(WhaleyCreate3DShot(game, 0));
        game.isPaused = NO;
        game.player.isDead = YES;
        XCTAssertNil(WhaleyCreate3DShot(game, 0));
        game.player.isDead = NO;
        game.player.hasWon = YES;
        XCTAssertNil(WhaleyCreate3DShot(game, 0));
        game.player.hasWon = NO;
        WhaleyScene3DModeEnabled = NO;
        XCTAssertNil(WhaleyCreate3DShot(game, 0));
        WhaleyScene3DModeEnabled = YES;
        XCTAssertEqual(game.projectiles.count, count);
        XCTAssertEqual(game.level.bubblesUsed, used);
    }];
}

- (void)testLowShotFitsBelowTheLaunchPointWithoutMovingItsCenterOnGrowth {
    [self withArena:^(Whaley *game) {
        [self prepareWorldPlacement:game];
        game.player.position = CGPointMake(300, 35);
        Projectile *shot = WhaleyCreate3DShot(game, 0);
        XCTAssertNotNil(shot);
        if (!shot) return;
        XCTAssertLessThan(shot.sizeMode, SmallSize);
        XCTAssertGreaterThanOrEqual(shot.position.y - shot.scaledHeight / 2, 32 - 0.0001);
        CGPoint center = shot.position;
        shot.sizeMode *= 2;
        XCTAssertTrue(CGPointEqualToPoint(center, shot.position));
    }];
}
@end
