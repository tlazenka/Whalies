#if __has_include(<UIKit/UIKit.h>)
#ifndef WHALEY_SPRITE_FRAME_TARGET_H
#define WHALEY_SPRITE_FRAME_TARGET_H
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// The logical action owner applies a COMPLETE cached frame to its drawable.
/// No child search, transform redirection, or second frame-metadata registry.
@protocol WhaleySpriteFrameTarget <NSObject>
- (BOOL)whaleyApplySpriteFrameNamed:(NSString *)name
    NS_SWIFT_NAME(applyWhaleyFrame(named:));
@end
NS_ASSUME_NONNULL_END
#endif
#endif
