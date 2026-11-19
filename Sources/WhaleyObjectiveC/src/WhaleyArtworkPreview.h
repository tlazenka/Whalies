#ifndef WHALEY_ARTWORK_PREVIEW_H
#define WHALEY_ARTWORK_PREVIEW_H
#if __has_include(<UIKit/UIKit.h>)
#import <SpriteKit/SpriteKit.h>

/// Owns only the presentation transition, not menu selection or gameplay state.
/// Remains attached while fading out so the menu can consume intervening taps.
@interface WhaleyArtworkPreview : SKNode
- (void)presentInNode:(SKNode *)parent;
- (void)dismiss;
@end
#endif
#endif
