#include <assert.h>
#include <stdio.h>
#include "WhaleySnapshotGeometry.h"
static unsigned checks;
#define CHECK(x) do { ++checks; assert(x); } while (0)
static void near(double a, double b) { CHECK(fabs(a - b) < 1e-10); }
int main(void) {
    /* Growing a centered bubble must never introduce half-size translation. */
    for (int i = 1; i <= 120; ++i) {
        double size = i / 20.0;
        WhaleySnapshotGeometry b = WhaleyMakeSnapshotGeometry(64, 96,
            32 * size, 32 * size, 32, 16, false);
        CHECK(b.valid); near(b.x, 2); near(b.y, 6);
        near(b.width, size); near(b.height, 2 * size);
        /* Player retains bottom-left semantics under the SAME normalization. */
        WhaleySnapshotGeometry p = WhaleyMakeSnapshotGeometry(64, 96,
            32 * size, 48 * size, 32, 16, true);
        CHECK(p.valid); near(p.x - p.width / 2, 2); near(p.y - p.height / 2, 6);
    }
    CHECK(!WhaleyMakeSnapshotGeometry(NAN, 0, 1, 1, 32, 32, false).valid);
    CHECK(!WhaleyMakeSnapshotGeometry(0, INFINITY, 1, 1, 32, 32, false).valid);
    CHECK(!WhaleyMakeSnapshotGeometry(0, 0, 0, 1, 32, 32, false).valid);
    CHECK(!WhaleyMakeSnapshotGeometry(0, 0, -1, 1, 32, 32, false).valid);
    CHECK(!WhaleyMakeSnapshotGeometry(0, 0, 1, 1, 0, 32, false).valid);
    CHECK(!WhaleyMakeSnapshotGeometry(0, 0, 1, 1, 32, NAN, false).valid);
    CHECK(!WhaleyMakeSnapshotGeometry(DBL_MAX, 0, DBL_MAX, 1, 1, 1, true).valid);
    CHECK(!WhaleyMakeSnapshotGeometry(0, 0, DBL_MAX, 1, 1, 1, false).valid);
    CHECK(!WhaleyMakeSnapshotGeometry(0, 0, DBL_TRUE_MIN, 1, 1, 1, false).valid);
    printf("Snapshot geometry: %u assertions passed (scaled dimensions, centers, player bottoms, invalid data).\n", checks);
    return 0;
}
