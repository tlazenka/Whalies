#pragma once
#if __has_include(<UIKit/UIKit.h>)
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@class Player;
void WhaleySrcTrajectoryReset(void);
void WhaleySrcTrajectoryRecord(Player *player, NSTimeInterval dt);
NSUInteger WhaleySrcTrajectorySampleCount(void);
NSTimeInterval WhaleySrcTrajectoryFirstTime(void);
NSTimeInterval WhaleySrcTrajectoryLastTime(void);
NSTimeInterval WhaleySrcSemanticTime(void);
BOOL WhaleySrcTrajectoryProjectPlayer(Player *player, NSTimeInterval seconds);
#endif
