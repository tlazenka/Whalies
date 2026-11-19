#import <XCTest/XCTest.h>
#import "../../Sources/WhaleyObjectiveC/include/WhaleyBootstrap.h"
#import "../../Sources/WhaleyObjectiveC/src/WhaleyScene.h"
#import "../../Sources/WhaleyObjectiveC/src/Constants.h"

// Call the REAL shared game loop, not a second test implementation of physics.
@interface Whaley (BounceTestAccess)
- (void)gameLoop:(ccTime)dt;
@end

@interface WhaleyArenaBounceTests : XCTestCase
@end

@implementation WhaleyArenaBounceTests

- (void)withArena:(void (^)(Whaley *game))body {
    void (^run)(void) = ^{
        @autoreleasepool {
            BOOL oldMode = WhaleyScene3DModeEnabled;
            BOOL oldPlacement = WhaleyScene3DPlaceAtAnchor;
            NSUInteger oldSequence = WhaleyScene3DJumpSequence;
            CGPoint oldAnchor = WhaleyScene3DJumpAnchorBottom;
            NSBundle *oldBundle = [WhaleySrcResourceBundle() retain];
            Whaley *game = nil;
            // A deterministic local texture: no app asset, account, saved level,
            // scheduled display link or wall-clock animation is required.
            NSURL *bundleURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString stringWithFormat:@"WhaleyBounce-%@.bundle", NSUUID.UUID.UUIDString]];
            @try {
                NSError *error = nil;
                XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:bundleURL
                    withIntermediateDirectories:YES attributes:nil error:&error]);
                XCTAssertNil(error);
                NSDictionary *info = @{@"CFBundleIdentifier": @"com.muttniks.bounce-fixture",
                                       @"CFBundlePackageType": @"BNDL"};
                XCTAssertTrue([info writeToURL:[bundleURL URLByAppendingPathComponent:@"Info.plist"] atomically:YES]);
                UIGraphicsImageRenderer *imageRenderer = [[UIGraphicsImageRenderer alloc]
                    initWithSize:CGSizeMake(32, 32)];
                UIImage *image = [imageRenderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                    CGContextSetFillColorWithColor(context.CGContext, UIColor.blueColor.CGColor);
                    CGContextFillEllipseInRect(context.CGContext, CGRectMake(0, 0, 32, 32));
                }];
                [imageRenderer release];
                XCTAssertTrue([UIImagePNGRepresentation(image)
                    writeToURL:[bundleURL URLByAppendingPathComponent:@"infinite_bubble.png"] atomically:YES]);
                NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
                XCTAssertNotNil(bundle);
                if (!bundle) return;
                WhaleySrcSetResourceBundle(bundle);

                // Use inherited init to construct an unscheduled fixture, then
                // let the production arena installer create its real foundations.
                game = [[Whaley alloc] init];
                game.tileMap = [[[CCTMXTiledMap alloc] init] autorelease];
                game.tileMap.mapSize = CGSizeMake(20, 30);
                game.tileMap.tileSize = CGSizeMake(32, 32);
                game.meta = [[[CCTMXLayer alloc] init] autorelease];
                game.level = [Level levelWithNum:1 withGameMode:NormalBubble];
                game.projectiles = [NSMutableArray array];
                game.collectibles = [NSMutableArray array];
                game.hazards = [NSMutableArray array];
                game.player = [[[Player alloc] init] autorelease];
                game.player.contentSize = CGSizeMake(32, 32);
                game.player.anchorPoint = CGPointZero;
                game.player.position = CGPointMake(300, 100);
                game.player.airMode = FALLING;
                game.player.jumpDiff = 1;
                game.player.yAdd = SlowYspd;
                game.player.xAdd = NormXspd;
                [game addChild:game.player];
                WhaleyScene3DModeEnabled = YES;
                WhaleySceneApply3DEnvironment(game);
                XCTAssertGreaterThan(game.projectiles.count, (NSUInteger)0);
                for (Projectile *p in game.projectiles) {
                    XCTAssertTrue(WhaleySceneIs3DFoundation(p));
                    XCTAssertGreaterThan(p.scaledWidth, 0);
                }
                body(game);
            } @finally {
                WhaleyScene3DModeEnabled = NO;
                WhaleySceneApply3DEnvironment(game);
                [game release];
                WhaleySrcSetResourceBundle(oldBundle);
                [oldBundle release];
                [NSFileManager.defaultManager removeItemAtURL:bundleURL error:NULL];
                WhaleyScene3DModeEnabled = oldMode;
                WhaleyScene3DPlaceAtAnchor = oldPlacement;
                WhaleyScene3DJumpSequence = oldSequence;
                WhaleyScene3DJumpAnchorBottom = oldAnchor;
                WhaleySrcTrajectoryReset();
            }
        }
    };
    if (NSThread.isMainThread) run();
    else dispatch_sync(dispatch_get_main_queue(), run);
}

- (void)testBottomFoundationsProduceRepeatedRealJumpsWithoutInput {
    [self withArena:^(Whaley *game) {
        NSArray *foundations = [[game.projectiles copy] autorelease];
        CGFloat low = CGFLOAT_MAX, high = -CGFLOAT_MAX;
        BOOL sawAscent = NO, sawDescent = NO;
        // Fifteen simulated seconds. No touches and no synthetic bounce animation.
        for (NSUInteger tick = 0; tick < 900; tick++) {
            NSUInteger previous = WhaleyScene3DJumpSequence;
            [game gameLoop:1.0 / 60.0];
            XCTAssertLessThanOrEqual(WhaleyScene3DJumpSequence - previous, (NSUInteger)1);
            sawAscent |= game.player.airMode == JUMPING_UP;
            sawDescent |= game.player.airMode == JUMPING_DOWN;
            low = MIN(low, game.player.position.y);
            high = MAX(high, game.player.position.y);
        }
        XCTAssertGreaterThanOrEqual(WhaleyScene3DJumpSequence, (NSUInteger)3);
        XCTAssertTrue(sawAscent);
        XCTAssertTrue(sawDescent);
        XCTAssertGreaterThan(high - low, 40);
        XCTAssertEqual(game.projectiles.count, foundations.count);
        for (Projectile *p in foundations) {
            XCTAssertNotEqual([game.projectiles indexOfObjectIdenticalTo:p], NSNotFound);
            XCTAssertEqual(p.bouncesLeft, (NSInteger)-1);
            XCTAssertEqual(p.parent, game);
        }
    }];
}

- (void)testOrdinaryBubbleLaunchesOnceAndPopsWhileFoundationsRemain {
    [self withArena:^(Whaley *game) {
        NSUInteger foundationCount = game.projectiles.count;
        game.player.position = CGPointMake(300, 300);
        game.player.airMode = FALLING;
        game.player.yAdd = SlowYspd;
        Projectile *shot = [[[Projectile alloc] init] autorelease];
        shot.contentSize = CGSizeMake(20, 20);
        shot.sizeMode = 1;
        shot.isFrozen = YES;
        shot.bouncesLeft = 1;
        shot.position = CGPointMake(316, 291);
        [game addChild:shot];
        [game.projectiles addObject:shot];
        NSUInteger before = WhaleyScene3DJumpSequence;
        [game gameLoop:1.0 / 60.0];
        XCTAssertEqual(game.player.airMode, JUMPING_UP);
        XCTAssertEqual(WhaleyScene3DJumpSequence, before + 1);
        XCTAssertEqual([game.projectiles indexOfObjectIdenticalTo:shot], NSNotFound);
        XCTAssertNil(shot.parent);
        XCTAssertEqual(game.projectiles.count, foundationCount);
        [game gameLoop:1.0 / 60.0];
        XCTAssertEqual(WhaleyScene3DJumpSequence, before + 1);
    }];
}
@end
