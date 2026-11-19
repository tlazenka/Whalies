#ifndef WHALEY_SNAPSHOT_GEOMETRY_H
#define WHALEY_SNAPSHOT_GEOMETRY_H
#include <stdbool.h>
#include <math.h>
#include <float.h>

/* Input: original engine pixels and already-scaled dimensions.
 * Output: center and dimensions in tile units. The player's origin is its
 * bottom-left; circular gameplay objects already store their center. */
typedef struct {
    double x, y, width, height;
    bool valid;
} WhaleySnapshotGeometry;

static inline WhaleySnapshotGeometry WhaleyMakeSnapshotGeometry(
    double x, double y, double width, double height,
    double tileWidth, double tileHeight, bool bottomLeftOrigin) {
    WhaleySnapshotGeometry invalid = {0};
    if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) ||
        !isfinite(tileWidth) || !isfinite(tileHeight) || width <= 0 || height <= 0 ||
        tileWidth <= 0 || tileHeight <= 0) return invalid;
    if (bottomLeftOrigin) { x += width / 2; y += height / 2; }
    WhaleySnapshotGeometry g = {x / tileWidth, y / tileHeight,
        width / tileWidth, height / tileHeight, true};
    if (!isfinite(g.x) || !isfinite(g.y) || !isfinite(g.width) || !isfinite(g.height) ||
        fabs(g.x) > FLT_MAX || fabs(g.y) > FLT_MAX ||
        g.width > FLT_MAX || g.height > FLT_MAX ||
        (float)g.width <= 0 || (float)g.height <= 0) return invalid;
    return g;
}
#endif
