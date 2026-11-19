#ifndef WHALEY_3D_SHOT_PLACEMENT_H
#define WHALEY_3D_SHOT_PLACEMENT_H
#include "WhaleyArenaRules.h"
#include <float.h>

/* Pure geometry, in original engine pixels. side names the BUBBLE side:
 * a left bubble produces the legacy rightward response, and vice versa.
 * No view size, scene translation or smoothed camera position participates. */
typedef struct {
    double x, y, scale;
    bool valid;
} Whaley3DShotPlacement;

static inline Whaley3DShotPlacement Whaley3DPlanShot(
    WhaleyArenaLayout arena, double playerX, double playerBottom,
    double playerWidth, bool useAnchor, double anchorX, double anchorBottom,
    double radiusX, double radiusY, int side) {
    Whaley3DShotPlacement none = {0};
    if (!arena.valid || !isfinite(arena.left) || !isfinite(arena.right) ||
        !isfinite(arena.bottom) || !isfinite(arena.top) ||
        arena.right <= arena.left || arena.top <= arena.bottom ||
        !isfinite(playerX) || !isfinite(playerBottom) ||
        !isfinite(playerWidth) || playerWidth <= 0 ||
        !isfinite(radiusX) || !isfinite(radiusY) || radiusX <= 1 || radiusY <= 1 ||
        side < -1 || side > 1) return none;
    double x = useAnchor ? anchorX : playerX;
    double y = useAnchor ? anchorBottom : playerBottom;
    if (!isfinite(x) || !isfinite(y) || x < arena.left || x > arena.right ||
        y < arena.bottom || y > arena.top) return none;

    /* Two pixels overlap the player's bottom, allowing the legacy one-pixel
     * collision inset to detect contact. Near the floor start with a smaller
     * real bubble instead of clamping a full-size bubble through Whaley. */
    const double contactDepth = 2;
    double horizontalRoom = fmin(x - arena.left, arena.right - x);
    double below = (y - arena.bottom + contactDepth) / 2;
    double scale = fmin(1, fmin(horizontalRoom / radiusX, below / radiusY));
    if (!isfinite(scale) || scale < FLT_MIN) return none;
    double rx = radiusX * scale, ry = radiusY * scale;
    if (rx <= 1 || ry <= 1) return none;
    double offset = fmax(playerWidth / 2 + 1, rx / 2 + 1);
    double desiredX = x + side * offset;
    double desiredY = y - ry + contactDepth;
    double minX = arena.left + rx, maxX = arena.right - rx;
    double minY = arena.bottom + ry, maxY = arena.top - ry;
    if (!isfinite(desiredX) || !isfinite(desiredY) ||
        minX > maxX || minY > maxY) return none;
    double placedX = fmax(minX, fmin(maxX, desiredX));
    double placedY = fmax(minY, fmin(maxY, desiredY));
    return (Whaley3DShotPlacement){placedX, placedY, scale, true};
}
#endif
