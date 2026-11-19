#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyArtworkPreview.h"

@implementation WhaleyArtworkPreview {
    BOOL _dismissing;
}

- (void)presentInNode:(SKNode *)parent {
    if (self.parent) return;
    _dismissing = NO;
    self.alpha = 0;
    [parent addChild:self];
    // The menu stays beneath the artwork; alpha produces the cross-dissolve.
    [self runAction:[SKAction fadeInWithDuration:0.1] withKey:@"preview-opacity"];
}

- (void)dismiss {
    if (!self.parent || _dismissing) return;
    _dismissing = YES;
    // Cancel an in-progress reveal, then fade from the current alpha. No
    // callback captures the menu and no delayed completion can remove a new
    // preview or change selection after scene replacement.
    [self removeActionForKey:@"preview-opacity"];
    [self runAction:[SKAction sequence:@[
        [SKAction fadeOutWithDuration:0.1],
        [SKAction removeFromParent]
    ]] withKey:@"preview-opacity"];
}
@end
#endif
