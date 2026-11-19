#ifndef WHALEY_LEVEL_ARTWORK_H
#define WHALEY_LEVEL_ARTWORK_H

#import <Foundation/Foundation.h>

// Shared by gameplay and both native galleries.
static inline NSString *WhaleyLevelArtworkFilename(NSInteger level, BOOL tallScreen) {
    return [NSString stringWithFormat:@"level%ld%@.png", (long)level,
                                      tallScreen ? @"-568h" : @""];
}

#endif
