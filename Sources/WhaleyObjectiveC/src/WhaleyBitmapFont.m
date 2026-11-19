#if __has_include(<UIKit/UIKit.h>)
#import "WhaleyBitmapFont.h"
#import "WhaleyBootstrap.h"
#import "WhaleyTitleGeometry.h"
#import <UIKit/UIKit.h>
#include <stdint.h>

static NSNumber *WhaleyKerningKey(unichar first, unichar second) {
    return @(((uint32_t)first << 16) | (uint32_t)second);
}

static NSDictionary *WhaleyFontInfo(NSString *fontFile) {
    static NSMutableDictionary *fonts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fonts = [NSMutableDictionary new]; });
    NSDictionary *cached = fonts[fontFile];
    if (cached) return cached;
    NSURL *url = WhaleySrcResourceURL(fontFile);
    NSString *source = url ? [NSString stringWithContentsOfURL:url
        encoding:NSUTF8StringEncoding error:nil] : nil;
    NSMutableDictionary *glyphs = [NSMutableDictionary dictionary];
    NSMutableDictionary *kernings = [NSMutableDictionary dictionary];
    NSUInteger lineHeight = 16;
    NSRegularExpression *pairs = [NSRegularExpression
        regularExpressionWithPattern:@"([a-zA-Z]+)=(-?[0-9]+)" options:0 error:nil];
    for (NSString *line in [source componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if ([line hasPrefix:@"common "]) {
            NSRange r = [line rangeOfString:@"lineHeight="];
            if (r.location != NSNotFound) {
                lineHeight = [[line substringFromIndex:r.location + r.length] integerValue];
            }
        }
        BOOL isGlyph = [line hasPrefix:@"char id="];
        BOOL isKerning = [line hasPrefix:@"kerning "];
        if (!isGlyph && !isKerning) continue;
        NSMutableDictionary *g = [NSMutableDictionary dictionary];
        for (NSTextCheckingResult *m in [pairs matchesInString:line options:0
            range:NSMakeRange(0, line.length)]) {
            NSString *key = [line substringWithRange:[m rangeAtIndex:1]];
            NSString *value = [line substringWithRange:[m rangeAtIndex:2]];
            g[key] = @([value integerValue]);
        }
        if (isGlyph && g[@"id"]) glyphs[g[@"id"]] = g;
        if (isKerning && g[@"first"] && g[@"second"] && g[@"amount"]) {
            kernings[WhaleyKerningKey([g[@"first"] unsignedShortValue],
                                     [g[@"second"] unsignedShortValue])] = g[@"amount"];
        }
    }
    // Cache missing assets too, so unavailable fonts cannot cause repeated I/O.
    NSString *png = [[fontFile stringByDeletingPathExtension] stringByAppendingPathExtension:@"png"];
    NSURL *pngURL = WhaleySrcResourceURL(png);
    UIImage *image = pngURL ? [UIImage imageWithContentsOfFile:pngURL.path] : nil;
    NSDictionary *info = @{@"glyphs": glyphs, @"kernings": kernings,
                           @"lineHeight": @(MAX(1, lineHeight)),
                           @"image": image ?: [NSNull null]};
    fonts[fontFile] = info;
    return info;
}

static CGFloat WhaleyFontBaseSize(NSString *fontFile) {
    return [fontFile hasPrefix:@"title_"] ? 32.0 : 16.0;
}

static SKTexture *WhaleyGlyphTexture(NSString *fontFile, unichar code, NSDictionary *g) {
    static NSMutableDictionary *textures;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ textures = [NSMutableDictionary new]; });
    NSString *key = [NSString stringWithFormat:@"%@:%u", fontFile, code];
    SKTexture *cached = textures[key];
    if (cached) return cached;
    id value = WhaleyFontInfo(fontFile)[@"image"];
    UIImage *image = [value isKindOfClass:[UIImage class]] ? value : nil;
    CGImageRef atlas = image.CGImage;
    if (!atlas || !g) return nil;
    CGRect rect = CGRectMake([g[@"x"] doubleValue], [g[@"y"] doubleValue],
                             [g[@"width"] doubleValue], [g[@"height"] doubleValue]);
    if (CGRectIsEmpty(rect) || !CGRectContainsRect(
            CGRectMake(0, 0, CGImageGetWidth(atlas), CGImageGetHeight(atlas)), rect)) return nil;
    CGImageRef cropped = CGImageCreateWithImageInRect(atlas, rect);
    if (!cropped) return nil;
    SKTexture *texture = [SKTexture textureWithImage:[UIImage imageWithCGImage:cropped]];
    texture.filteringMode = SKTextureFilteringNearest;
    CGImageRelease(cropped);
    textures[key] = texture;
    return texture;
}

@implementation WhaleyBitmapLabel {
    NSString *_fontFile;
    NSString *_text;
    CGFloat _fontSize;
    CGFloat _advance;
    CGFloat _lineHeight;
}

+ (instancetype)labelWithText:(NSString *)text fontFile:(NSString *)file
                         size:(CGFloat)size position:(CGPoint)position {
    WhaleyBitmapLabel *label = [[[self alloc] init] autorelease];
    label->_fontFile = [file copy];
    label->_fontSize = size;
    label.position = position;
    label.text = text;
    return label;
}

+ (CGFloat)advanceForCharacter:(unichar)character fontFile:(NSString *)file
                          size:(CGFloat)size {
    NSDictionary *g = WhaleyFontInfo(file)[@"glyphs"][@(character)];
    CGFloat advance = g ? [g[@"xadvance"] doubleValue] : WhaleyFontBaseSize(file) * 0.75;
    return advance * size / WhaleyFontBaseSize(file);
}
+ (CGFloat)lineHeightForFontFile:(NSString *)file size:(CGFloat)size {
    return [WhaleyFontInfo(file)[@"lineHeight"] doubleValue] * size / WhaleyFontBaseSize(file);
}
+ (CGFloat)kerningForFirst:(unichar)first second:(unichar)second
                 fontFile:(NSString *)file size:(CGFloat)size {
    return [WhaleyFontInfo(file)[@"kernings"][WhaleyKerningKey(first, second)] doubleValue]
        * size / WhaleyFontBaseSize(file);
}
- (NSString *)text { return _text; }
- (CGFloat)advanceWidth { return _advance; }
- (void)setText:(NSString *)text {
    if ([_text isEqualToString:text]) return;
    [_text release];
    _text = [text copy];
    [self removeAllChildren];
    NSDictionary *info = WhaleyFontInfo(_fontFile);
    NSDictionary *glyphs = info[@"glyphs"];
    NSDictionary *kernings = info[@"kernings"];
    CGFloat scale = _fontSize / WhaleyFontBaseSize(_fontFile);
    CGFloat lineHeight = [info[@"lineHeight"] doubleValue];
    _lineHeight = lineHeight * scale;
    _advance = 0;
    for (NSUInteger i = 0; i < _text.length; ++i) {
        unichar code = [_text characterAtIndex:i];
        NSDictionary *g = glyphs[@(code)];
        if (i > 0) _advance += [kernings[WhaleyKerningKey([_text characterAtIndex:i - 1], code)] doubleValue] * scale;
        _advance += (g ? [g[@"xadvance"] doubleValue] : WhaleyFontBaseSize(_fontFile) * 0.75) * scale;
    }
    CGFloat pen = -_advance / 2;
    for (NSUInteger i = 0; i < _text.length; ++i) {
        unichar code = [_text characterAtIndex:i];
        NSDictionary *g = glyphs[@(code)];
        if (i > 0) pen += [kernings[WhaleyKerningKey([_text characterAtIndex:i - 1], code)] doubleValue] * scale;
        CGFloat advance = (g ? [g[@"xadvance"] doubleValue] : WhaleyFontBaseSize(_fontFile) * 0.75) * scale;
        if (g) {
            SKTexture *texture = WhaleyGlyphTexture(_fontFile, code, g);
            if (texture) {
                CGFloat width = [g[@"width"] doubleValue] * scale;
                CGFloat height = [g[@"height"] doubleValue] * scale;
                SKSpriteNode *sprite = [SKSpriteNode spriteNodeWithTexture:texture
                    size:CGSizeMake(width, height)];
                WhaleyTitlePoint center = WhaleyBitmapGlyphCenter(pen, lineHeight,
                    [g[@"xoffset"] doubleValue], [g[@"yoffset"] doubleValue],
                    [g[@"width"] doubleValue], [g[@"height"] doubleValue], scale);
                sprite.position = CGPointMake(center.x, center.y);
                // Preserve the original glyph order even with ignoresSiblingOrder.
                sprite.zPosition = (CGFloat)i;
                [self addChild:sprite];
            }
        }
        pen += advance;
    }
}
- (BOOL)hitTestPoint:(CGPoint)point fromNode:(SKNode *)source {
    CGPoint local = [self convertPoint:point fromNode:source];
    // General labels retain their padded target. The title deliberately uses
    // painted-glyph intersections instead, matching MainMenu's original loop.
    CGRect box = CGRectInset(CGRectMake(-_advance / 2, -_lineHeight / 2,
                                        _advance, _lineHeight), -3, -3);
    if (CGRectContainsPoint(box, local)) return YES;
    for (SKNode *child in self.children) {
        if (CGRectContainsPoint(CGRectInset(child.frame, -3, -3), local)) return YES;
    }
    return NO;
}
- (void)dealloc {
    [_text release];
    [_fontFile release];
    [super dealloc];
}
@end
#endif
