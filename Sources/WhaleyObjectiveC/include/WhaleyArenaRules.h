#ifndef WHALEY_ARENA_RULES_H
#define WHALEY_ARENA_RULES_H
#include <stdbool.h>
#include <stddef.h>
#include <math.h>

/* A one-tile-thick perimeter. Geometry is shared by collision and snapshot code.
 * Units are original engine pixels; tile classification is independent of TMX GID. */
typedef struct {
    double left, right, bottom, top;
    double bubbleRadius;
    size_t bubbleCount;
    bool valid;
} WhaleyArenaLayout;

static inline WhaleyArenaLayout WhaleyArenaMakeLayout(
    size_t columns, size_t rows, double tileWidth, double tileHeight) {
    WhaleyArenaLayout a = {0};
    if (columns < 3 || rows < 4 || !isfinite(tileWidth) || !isfinite(tileHeight)
        || tileWidth <= 0 || tileHeight <= 0) return a;
    a.left = tileWidth;
    a.right = (columns - 1) * tileWidth;
    a.bottom = tileHeight;
    a.top = (rows - 1) * tileHeight;
    a.bubbleRadius = fmin(tileWidth, tileHeight) * 0.33;
    if (!isfinite(a.right) || !isfinite(a.top) || a.bubbleRadius <= 0 ||
        !isfinite(a.bubbleRadius)) return (WhaleyArenaLayout){0};
    double usable = a.right - a.left - 2 * a.bubbleRadius;
    double intervals = ceil(usable / (a.bubbleRadius * 1.6));
    /* Bound allocations even for corrupted level dimensions. */
    if (!isfinite(intervals) || intervals < 0 || intervals > 4095) return (WhaleyArenaLayout){0};
    a.bubbleCount = (size_t)intervals + 1;
    a.valid = true;
    return a;
}

static inline bool WhaleyArenaIsPerimeter(long x, long y, long columns, long rows) {
    return columns > 0 && rows > 0 && x >= 0 && y >= 0 && x < columns && y < rows
        && (x == 0 || y == 0 || x == columns - 1 || y == rows - 1);
}

static inline double WhaleyArenaBubbleX(WhaleyArenaLayout a, size_t index) {
    if (!a.valid || index >= a.bubbleCount) return NAN;
    if (a.bubbleCount == 1) return (a.left + a.right) / 2;
    return a.left + a.bubbleRadius
        + (a.right - a.left - 2 * a.bubbleRadius) * index / (a.bubbleCount - 1);
}

static inline bool WhaleyArenaBlocksRect(WhaleyArenaLayout a,
    double x, double y, double width, double height) {
    return !a.valid || !isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height)
        || width < 0 || height < 0
        || x < a.left || y < a.bottom || x + width > a.right || y + height > a.top;
}

static inline bool WhaleyArenaConsumesBubble(bool foundation, bool upwardBounce) {
    return !foundation && upwardBounce;
}
#endif
