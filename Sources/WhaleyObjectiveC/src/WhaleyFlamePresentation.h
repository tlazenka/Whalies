#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyScene.h"
#if defined(WHALEY_SPRITEKIT_COMPAT)

@interface WhaleyFlamePresentation : NSObject
- (void)advance:(Whaley *)game seconds:(ccTime)seconds;
@end
#endif
#endif
