#ifndef WHALEY_TITLE_GEOMETRY_H
#define WHALEY_TITLE_GEOMETRY_H

#include <stdbool.h>
#include <math.h>

/* The equations used by MainMenu.m and WhaleyBitmapFont.m. Kept independent
 * of UIKit so the production geometry can also be executed on non-Apple CI.
 * Reference: Legacy/MainMenu.m and cocos2d/CCLabelBMFont.m:createFontChars.
 * All values are logical points after the caller's font scale is applied. */
typedef struct { double x, y; } WhaleyTitlePoint;

static inline WhaleyTitlePoint WhaleyTitleLetterCenter(
    double viewportHeight, double lineHeight, double pen, double advance) {
    return (WhaleyTitlePoint){24.0 + pen + advance / 2.0,
                             viewportHeight - 20.0 - lineHeight / 2.0};
}

/* A centered bitmap label's glyph center, including painted overhangs.
 * pen is already scaled; the font offsets/dimensions are atlas units. */
static inline WhaleyTitlePoint WhaleyBitmapGlyphCenter(
    double pen, double lineHeight, double xOffset, double yOffset,
    double width, double height, double scale) {
    return (WhaleyTitlePoint){pen + (xOffset + width / 2.0) * scale,
                             (lineHeight / 2.0 - yOffset - height / 2.0) * scale};
}

static inline WhaleyTitlePoint WhaleyTitleRewardCenter(
    double viewportWidth, double viewportHeight, double lineHeight) {
    return (WhaleyTitlePoint){viewportWidth / 2.0 - 19.0,
                             viewportHeight - lineHeight - 20.0 + 65.0};
}

static inline double WhaleyTitleRewardDiameter(void) { return 128.0 * 0.125; }
static inline double WhaleyTitleRewardAlpha(void) { return 150.0 / 255.0; }
static inline double WhaleyTitleChalkAlpha(void) { return 100.0 / 255.0; }
static inline double WhaleyTitleFadeSeconds(void) { return 0.1; }

/* Original Helpers.rectIntersectsCircle uses a 1x1 touch rectangle: its
 * closest point reduces to the touch itself. The reward gets +20 radius. */
static inline bool WhaleyTitleRewardHit(double x, double y, WhaleyTitlePoint center) {
    if (!isfinite(x) || !isfinite(y)) return false;
    const double dx = x - center.x, dy = y - center.y;
    const double radius = WhaleyTitleRewardDiameter() / 2.0 + 20.0;
    return dx * dx + dy * dy < radius * radius;
}

/* Match the original 1x1 touch/painted-glyph rectangle intersection, not a
 * guessed advance-cell target. The caller visits EVERY overlapping glyph. */
static inline bool WhaleyTitleGlyphHit(double x, double y, double left,
    double bottom, double width, double height) {
    return isfinite(x) && isfinite(y) && width > 0 && height > 0 &&
        x < left + width && x + 1.0 > left &&
        y < bottom + height && y + 1.0 > bottom;
}
#endif
