#pragma once
#import <Foundation/Foundation.h>

// Keep the original scoring arithmetic in a renderer-independent inline function.
// Inline linkage avoids requiring a separate compilation unit in either target.
static inline NSInteger WhaleyCalculateScore(NSInteger collectibles,
                                             NSInteger bubblesUsed,
                                             NSTimeInterval elapsedTime) {
    return (NSInteger)((collectibles * 100)
                       + (5000 / (bubblesUsed + 1))
                       + (30000 / (elapsedTime + .1)));
}
