#include "../../Sources/WhaleyObjectiveC/src/WhaleyFlameMotion.h"
#include <assert.h>
#include <stdio.h>

static unsigned checks;
#define CHECK(condition) do { assert(condition); checks++; } while (0)

int main(void) {
    const int dance[] = {0, 1, 2, 1, 0, -1, -2, -1};
    for (int step = 0; step <= 120; step++) {
        WhaleyFlamePose cw = WhaleyFlamePoseAt(0, step * 0.25, false);
        WhaleyFlamePose ccw = WhaleyFlamePoseAt(1, step * 0.25, false);
        CHECK(cw.clockwiseDegrees == step % 12 * 30);
        CHECK(ccw.clockwiseDegrees == -cw.clockwiseDegrees);
        CHECK(cw.offsetX == 0 && ccw.offsetX == 0);
    }
    for (int step = 0; step < 80; step++) {
        WhaleyFlamePose pose = WhaleyFlamePoseAt(2, step * 0.15, false);
        CHECK(pose.offsetX == dance[step % 8]);
        CHECK(pose.clockwiseDegrees == 0);
    }
    for (int fps = 30; fps <= 120; fps *= 2) {
        double elapsed = 0;
        for (int frame = 1; frame <= fps * 60; frame++) {
            elapsed = WhaleyFlameAdvance(elapsed, 1.0 / fps, false);
            for (size_t index = 0; index < 6; index++) {
                WhaleyFlamePose pose = WhaleyFlamePoseAt(index, elapsed, false);
                WhaleyFlamePose expected = WhaleyFlamePoseAt(index % 3, (double)frame / fps, false);
                CHECK(pose.offsetX == expected.offsetX);
                CHECK(pose.clockwiseDegrees == expected.clockwiseDegrees);
                CHECK(fabs(pose.offsetX) <= 2 && fabs(pose.clockwiseDegrees) <= 330);
                WhaleyFlamePose still = WhaleyFlamePoseAt(index, elapsed, true);
                CHECK(still.offsetX == 0 && still.clockwiseDegrees == 0);
            }
            CHECK(WhaleyFlameAdvance(elapsed, 1, true) == elapsed);
        }
    }
    CHECK(WhaleyFlameAdvance(0, 10, false) == 0.25);
    CHECK(WhaleyFlameAdvance(1, 0, false) == 1);
    CHECK(WhaleyFlameAdvance(1, -1, false) == 1);
    CHECK(WhaleyFlameAdvance(1, NAN, false) == 1);
    CHECK(WhaleyFlameAdvance(1, INFINITY, false) == 1);
    CHECK(WhaleyFlameAdvance(NAN, 0, false) == 0);
    CHECK(WhaleyFlameAdvance(-1, 0, false) == 0);
    CHECK(WhaleyFlameAdvance(5.9, 0.25, false) < 0.151);
    const double invalid[] = {NAN, INFINITY, -INFINITY, -1};
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        WhaleyFlamePose pose = WhaleyFlamePoseAt(0, invalid[i], false);
        CHECK(pose.offsetX == 0 && pose.clockwiseDegrees == 0);
    }
    puts("Clockwise, counterclockwise, dance, cadence, pause, reduced motion and invalid-input checks passed.");
    printf("%u flame checks passed.\n", checks);
    return 0;
}
