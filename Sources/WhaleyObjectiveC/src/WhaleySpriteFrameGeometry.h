#ifndef WHALEY_SPRITE_FRAME_GEOMETRY_H
#define WHALEY_SPRITE_FRAME_GEOMETRY_H
#include <stdbool.h>
#include <math.h>

/* The exercised CCSprite contract, independent of UIKit. Atlas rectangles
 * are top-left based. Width/height describe the UNROTATED trimmed frame;
 * a clockwise-packed frame occupies height x width pixels in the atlas.
 * Reference: cocos2d/CCSprite.m setTextureRect:rotated:untrimmedSize:.
 */
typedef struct { double x, y, width, height; } WhaleyFrameRect;
typedef struct {
    double centerX, centerY;
    double width, height;       /* physical cropped texture size */
    double scaleX, scaleY;     /* flips in texture axes, before rotation */
    bool quarterTurn;          /* +pi/2 restores clockwise-packed artwork */
} WhaleyFramePlacement;

static inline bool WhaleyFrameRegion(WhaleyFrameRect rect, bool rotated,
    double atlasWidth, double atlasHeight, WhaleyFrameRect *out) {
    if (!out || !isfinite(rect.x) || !isfinite(rect.y) ||
        !isfinite(rect.width) || !isfinite(rect.height) ||
        !isfinite(atlasWidth) || !isfinite(atlasHeight) ||
        atlasWidth <= 0 || atlasHeight <= 0 || rect.x < 0 || rect.y < 0 ||
        rect.width < 0 || rect.height < 0) return false;
    const double width = rotated ? rect.height : rect.width;
    const double height = rotated ? rect.width : rect.height;
    /* Subtraction avoids overflow from x+width on malformed input. */
    if (rect.x > atlasWidth || rect.y > atlasHeight ||
        width > atlasWidth - rect.x || height > atlasHeight - rect.y) return false;
    *out = (WhaleyFrameRect){rect.x / atlasWidth,
        (atlasHeight - rect.y - height) / atlasHeight,
        width / atlasWidth, height / atlasHeight};
    return true;
}

static inline WhaleyFramePlacement WhaleyPlaceFrame(double trimmedWidth,
    double trimmedHeight, double originalWidth, double originalHeight,
    double offsetX, double offsetY, double anchorX, double anchorY,
    bool flipX, bool flipY, bool rotated) {
    /* The wrapper's anchor belongs to the full, untrimmed logical rectangle.
     * Its drawable is centered, so flips never move an untrimmed sprite out
     * of its logical box. Only trim offsets change sign under a flip.
     */
    const double fx = flipX ? -1.0 : 1.0;
    const double fy = flipY ? -1.0 : 1.0;
    return (WhaleyFramePlacement){
        (0.5 - anchorX) * originalWidth + fx * offsetX,
        (0.5 - anchorY) * originalHeight + fy * offsetY,
        rotated ? trimmedHeight : trimmedWidth,
        rotated ? trimmedWidth : trimmedHeight,
        rotated ? fy : fx, rotated ? fx : fy, rotated
    };
}
#endif
