#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyTrajectory.h"
#import "Player.h"

static NSMutableArray *WhaleyTrajectoryTimes = nil;
static NSMutableArray *WhaleyTrajectoryPositions = nil;
static NSTimeInterval WhaleySemanticElapsedTime = 0;

void WhaleySrcTrajectoryReset(void) {
    [WhaleyTrajectoryTimes release];
    [WhaleyTrajectoryPositions release];
    WhaleyTrajectoryTimes = [[NSMutableArray alloc] init];
    WhaleyTrajectoryPositions = [[NSMutableArray alloc] init];
    WhaleySemanticElapsedTime = 0;
}

void WhaleySrcTrajectoryRecord(Player *player, NSTimeInterval dt) {
    if (!player) {
        return;
    }
    if (!WhaleyTrajectoryTimes) {
        WhaleySrcTrajectoryReset();
    }
    WhaleySemanticElapsedTime += MAX(0, dt);
    [WhaleyTrajectoryTimes addObject:@(WhaleySemanticElapsedTime)];
    [WhaleyTrajectoryPositions addObject:[NSValue valueWithCGPoint:player.position]];
    const NSUInteger maximumSamples = 36000;
    if (WhaleyTrajectoryTimes.count > maximumSamples) {
        [WhaleyTrajectoryTimes removeObjectAtIndex:0];
        [WhaleyTrajectoryPositions removeObjectAtIndex:0];
    }
}

NSUInteger WhaleySrcTrajectorySampleCount(void) { return WhaleyTrajectoryTimes.count; }
NSTimeInterval WhaleySrcTrajectoryFirstTime(void) { return WhaleyTrajectoryTimes.count ? [WhaleyTrajectoryTimes[0] doubleValue] : 0; }
NSTimeInterval WhaleySrcTrajectoryLastTime(void) { return WhaleyTrajectoryTimes.count ? [[WhaleyTrajectoryTimes lastObject] doubleValue] : 0; }
NSTimeInterval WhaleySrcSemanticTime(void) { return WhaleySemanticElapsedTime; }

BOOL WhaleySrcTrajectoryProjectPlayer(Player *player, NSTimeInterval seconds) {
    NSUInteger count = WhaleyTrajectoryTimes.count;
    if (!player || count == 0) {
        return NO;
    }
    NSTimeInterval target = MAX(0, seconds);
    if (target <= [WhaleyTrajectoryTimes[0] doubleValue]) {
        player.position = [WhaleyTrajectoryPositions[0] CGPointValue];
        return YES;
    }
    if (target >= [[WhaleyTrajectoryTimes lastObject] doubleValue]) {
        player.position = [[WhaleyTrajectoryPositions lastObject] CGPointValue];
        return YES;
    }
    // Samples are monotonically ordered. Binary search avoids scanning the
    // entire recording for each scrub or future renderer projection.
    NSUInteger low = 1;
    NSUInteger high = count - 1;
    while (low < high) {
        NSUInteger middle = low + (high - low) / 2;
        if ([WhaleyTrajectoryTimes[middle] doubleValue] < target) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    NSUInteger i = low;
    NSTimeInterval upperTime = [WhaleyTrajectoryTimes[i] doubleValue];
        NSTimeInterval lowerTime = [WhaleyTrajectoryTimes[i - 1] doubleValue];
        CGPoint lower = [WhaleyTrajectoryPositions[i - 1] CGPointValue];
        CGPoint upper = [WhaleyTrajectoryPositions[i] CGPointValue];
        double span = upperTime - lowerTime;
        double fraction = span > 0 ? (target - lowerTime) / span : 0;
        player.position = CGPointMake(lower.x + (upper.x - lower.x) * fraction,
                                      lower.y + (upper.y - lower.y) * fraction);
        return YES;
}

#endif
