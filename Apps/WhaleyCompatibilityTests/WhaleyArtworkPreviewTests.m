#import <XCTest/XCTest.h>
#import <Metal/Metal.h>
#import <SpriteKit/SpriteKit.h>
#import "../../Sources/WhaleyObjectiveC/src/WhaleyArtworkPreview.h"

@interface WhaleyArtworkPreviewTests : XCTestCase
@end

@implementation WhaleyArtworkPreviewTests
- (void)onMain:(void (^)(void))body {
    if ([NSThread isMainThread]) body();
    else dispatch_sync(dispatch_get_main_queue(), body);
}

- (void)testFadeOutRetainsInputCoverageUntilRemoval {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    XCTSkipIf(device == nil, @"SpriteKit action stepping requires Metal");
    [self onMain:^{
        SKScene *scene = [SKScene sceneWithSize:CGSizeMake(320, 568)];
        SKRenderer *renderer = [SKRenderer rendererWithDevice:device];
        renderer.scene = scene;
        [renderer updateAtTime:1];
        WhaleyArtworkPreview *preview = [WhaleyArtworkPreview node];
        [preview presentInNode:scene];
        XCTAssertEqual(preview.alpha, 0);
        BOOL sawIntermediateAlpha = NO;
        for (NSInteger i = 1; i <= 20; ++i) {
            [renderer updateAtTime:1 + i * 0.02];
            sawIntermediateAlpha |= preview.alpha > 0 && preview.alpha < 1;
        }
        XCTAssertTrue(sawIntermediateAlpha);
        XCTAssertEqualWithAccuracy(preview.alpha, 1, 0.001);
        [preview dismiss];
        XCTAssertEqual(preview.parent, scene);
        [renderer updateAtTime:1.42];
        [renderer updateAtTime:1.46];
        XCTAssertEqual(preview.parent, scene);
        XCTAssertLessThan(preview.alpha, 1);
        XCTAssertGreaterThan(preview.alpha, 0);
        [preview dismiss]; // Repeated taps must not restart the fade-out.
        [renderer updateAtTime:1.7];
        XCTAssertNil(preview.parent);
    }];
    [device release];
}

- (void)testInterruptedRevealCannotRemoveANewerPreview {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    XCTSkipIf(device == nil, @"SpriteKit action stepping requires Metal");
    [self onMain:^{
        SKScene *scene = [SKScene sceneWithSize:CGSizeMake(320, 568)];
        SKRenderer *renderer = [SKRenderer rendererWithDevice:device];
        renderer.scene = scene;
        [renderer updateAtTime:1];
        WhaleyArtworkPreview *old = [WhaleyArtworkPreview node];
        [old presentInNode:scene];
        [renderer updateAtTime:1.02];
        [renderer updateAtTime:1.04];
        CGFloat before = old.alpha;
        [old dismiss];
        XCTAssertEqual(old.alpha, before); // No snap to fully opaque.
        WhaleyArtworkPreview *next = [WhaleyArtworkPreview node];
        [next presentInNode:scene];
        for (NSInteger i = 3; i <= 25; ++i) [renderer updateAtTime:1 + i * 0.02];
        XCTAssertNil(old.parent);
        XCTAssertEqual(next.parent, scene);
        XCTAssertEqualWithAccuracy(next.alpha, 1, 0.001);
    }];
    [device release];
}
@end
