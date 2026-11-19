#ifndef WHALEY_EXPRESSION_PRESENTATION_H
#define WHALEY_EXPRESSION_PRESENTATION_H

#import "WhaleyScene.h"

#if defined(WHALEY_SPRITEKIT_COMPAT)
@interface WhaleyExpressionPresentation : NSObject
- (instancetype)initWithPlayer:(Player *)player;
- (void)advance:(Whaley *)game seconds:(ccTime)seconds;
- (void)collectCoin;
- (void)contactBubble:(Projectile *)projectile player:(Player *)player jumped:(BOOL)jumped;
@end
#endif

#endif
