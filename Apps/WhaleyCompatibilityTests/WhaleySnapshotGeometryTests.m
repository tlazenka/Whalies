#import <XCTest/XCTest.h>
#import "../../Sources/WhaleyObjectiveC/src/WhaleySnapshotCapture.h"

@interface WhaleySnapshotGeometryTests : XCTestCase
@end
@implementation WhaleySnapshotGeometryTests
- (void)onMain:(void (^)(void))body {
    if (NSThread.isMainThread) body();
    else dispatch_sync(dispatch_get_main_queue(), body);
}
- (void)testRealProjectileGrowthPublishesScaledSizeWithoutCenterDrift {
    [self onMain:^{
        Projectile *p = [Projectile new];
        p.contentSize = CGSizeMake(32, 32);
        p.position = CGPointMake(64, 96);
        p.sizeMode = 0.5;
        NSDictionary *small = WhaleySnapshotLiveEntity(p, @"bubble", @"same-bubble", CGSizeMake(32, 16), YES);
        p.sizeMode = 2;
        NSDictionary *large = WhaleySnapshotLiveEntity(p, @"bubble", @"same-bubble", CGSizeMake(32, 16), YES);
        XCTAssertEqualObjects(small[@"id"], large[@"id"]);
        XCTAssertEqualObjects(small[@"x"], large[@"x"]);
        XCTAssertEqualObjects(small[@"y"], large[@"y"]);
        XCTAssertEqualWithAccuracy([large[@"x"] doubleValue], p.position.x / 32, 1e-8);
        XCTAssertEqualWithAccuracy([large[@"dimensions"][@"width"] doubleValue], p.scaledWidth / 32, 1e-8);
        XCTAssertEqualWithAccuracy([large[@"dimensions"][@"height"] doubleValue], p.scaledHeight / 16, 1e-8);
        XCTAssertEqualObjects(large[@"bubbleRole"], @"playerCreated");
        XCTAssertTrue([NSJSONSerialization isValidJSONObject:large]);
        [p release];
    }];
}
- (void)testPlayerGeometryUsesBottomLeftOriginAndPreservesBottom {
    [self onMain:^{
        Player *p = [Player new];
        p.contentSize = CGSizeMake(32, 48);
        p.position = CGPointMake(64, 96);
        p.scaleX = 1.5; p.scaleY = 0.5;
        NSDictionary *g = WhaleySnapshotGeometryDictionary(p, CGSizeMake(32, 16), YES);
        double bottom = [g[@"y"] doubleValue] - [g[@"dimensions"][@"height"] doubleValue] / 2;
        XCTAssertEqualWithAccuracy(bottom, p.position.y / 16, 1e-8);
        [p release];
    }];
}
- (void)testLegacyAndNonBubbleRolesAreNotInvented {
    [self onMain:^{
        Projectile *p = [Projectile new];
        p.contentSize = CGSizeMake(32, 32);
        XCTAssertNil(WhaleySnapshotLiveEntity(p, @"bubble", @"b", CGSizeMake(32, 32), NO)[@"bubbleRole"]);
        XCTAssertNil(WhaleySnapshotLiveEntity(p, @"coin", @"c", CGSizeMake(32, 32), YES)[@"bubbleRole"]);
        XCTAssertNil(WhaleySnapshotGeometryDictionary(p, CGSizeZero, NO));
        [p release];
    }];
}
@end
