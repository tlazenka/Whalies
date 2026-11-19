#if __has_include(<UIKit/UIKit.h>)
#import <SpriteKit/SpriteKit.h>

// Renders the original cocos2d BMFont metrics and atlas in SpriteKit.
// A node per label preserves the existing action, opacity and hit-test model.
@interface WhaleyBitmapLabel : SKNode
@property (nonatomic, copy) NSString *text;
/// Full glyph-run advance, including spaces, in rendered points.
@property (nonatomic, readonly) CGFloat advanceWidth;
+ (instancetype)labelWithText:(NSString *)text fontFile:(NSString *)file
                         size:(CGFloat)size position:(CGPoint)position;
+ (CGFloat)advanceForCharacter:(unichar)character fontFile:(NSString *)file
                          size:(CGFloat)size;
/// BMFont common.lineHeight, not the nominal font size or painted bounds.
+ (CGFloat)lineHeightForFontFile:(NSString *)file size:(CGFloat)size;
+ (CGFloat)kerningForFirst:(unichar)first second:(unichar)second
                 fontFile:(NSString *)file size:(CGFloat)size;
- (BOOL)hitTestPoint:(CGPoint)point fromNode:(SKNode *)source;
@end
#endif
