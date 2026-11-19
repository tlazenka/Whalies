#include "../../Sources/WhaleyObjectiveC/src/WhaleyJumpTrail.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
#define CHECK(value) do { checks++; if (!(value)) { \
    fprintf(stderr, "line %d: %s\n", __LINE__, #value); exit(1); } } while (0)
static const double dt = 1.0 / 60.0;
static void step(WhaleyJumpTrail *trail, double x, double y, bool jump, bool airborne) {
    WhaleyTrailAdvance(trail, (WhaleyTrailPoint){x, y}, dt, airborne, true, jump, false, false);
}
static void valid(const WhaleyJumpTrail *trail) {
    WhaleyTrailMark marks[WhaleyTrailMarkCapacity];
    size_t count = WhaleyTrailMarks(trail, marks);
    CHECK(trail->count <= WhaleyTrailCapacity);
    CHECK(count <= WhaleyTrailMarkCapacity);
    for (size_t i = 0; i < count; i++) {
        CHECK(isfinite(marks[i].center.x) && isfinite(marks[i].center.y));
        CHECK(marks[i].width > 0 && marks[i].height > 0);
        CHECK(marks[i].alpha >= 0 && marks[i].alpha <= 0.8);
    }
}

int main(void) {
    WhaleyJumpTrail trail = {0};
    for (int i = 0; i < 60; i++) step(&trail, 100, 200 - i, false, true);
    CHECK(!trail.active && trail.count == 0); // Falling is not a launch.
    for (unsigned launch = 1; launch <= 8; launch++) {
        step(&trail, 100, 100, true, true);
        CHECK(trail.active);
        CHECK(trail.rainbow == (launch % 4 == 0));
        step(&trail, 104, 104, false, true);
        CHECK(trail.count >= 2);
        valid(&trail);
        step(&trail, 104, 104, false, false);
        CHECK(!trail.active && trail.count > 0);
        for (int i = 0; i < 60; i++) step(&trail, 104, 104, false, false);
        CHECK(trail.count == 0);
    }
    WhaleyTrailReset(&trail);
    step(&trail, 20, 20, true, true);
    step(&trail, 24, 24, false, true);
    WhaleyTrailMark before[WhaleyTrailMarkCapacity], after[WhaleyTrailMarkCapacity];
    size_t count = WhaleyTrailMarks(&trail, before);
    for (int i = 0; i < 100; i++)
        WhaleyTrailAdvance(&trail, (WhaleyTrailPoint){24, 24}, dt, true, true, false, true, false);
    CHECK(WhaleyTrailMarks(&trail, after) == count);
    for (size_t i = 0; i < count; i++) {
        CHECK(before[i].center.x == after[i].center.x);
        CHECK(before[i].center.y == after[i].center.y);
        CHECK(before[i].alpha == after[i].alpha);
    }
    step(&trail, 300, 400, false, true);
    CHECK(!trail.active && trail.count == 0); // No checkpoint streak.
    step(&trail, 302, 402, false, true);
    CHECK(trail.count == 0);
    step(&trail, 302, 402, true, true);
    CHECK(trail.count == 1);
    WhaleyTrailAdvance(&trail, (WhaleyTrailPoint){304, 404}, dt, true, false, false, false, false);
    CHECK(!trail.active && trail.count == 0); // Death or win.
    step(&trail, 302, 402, true, true);
    WhaleyTrailAdvance(&trail, (WhaleyTrailPoint){304, 404}, dt, true, true, false, false, true);
    CHECK(!trail.active && trail.count == 0); // Reduce Motion cancels emission.
    step(&trail, 306, 406, false, true);
    CHECK(trail.count == 0);
    step(&trail, 306, 406, true, true);
    WhaleyTrailAdvance(&trail, (WhaleyTrailPoint){306, 406}, NAN, true, true, false, false, false);
    CHECK(trail.count == 1 && trail.samples[0].age == 0);
    WhaleyTrailAdvance(&trail, (WhaleyTrailPoint){NAN, 406}, dt, true, true, false, false, false);
    CHECK(trail.count == 0 && !trail.hasPrevious);
    step(&trail, 0, 0, true, true);
    WhaleyTrailAdvance(&trail, (WhaleyTrailPoint){4, 4}, 10, true, true, false, false, false);
    CHECK(trail.count == 0 && !trail.active);
    WhaleyTrailReset(&trail);
    for (int i = 0; i < 500; i++) {
        step(&trail, i * 40, i * 20, i % 30 == 0, true);
        valid(&trail);
    }
    CHECK(trail.count == WhaleyTrailCapacity);
    // A straight observed path produces the same samples at 30/60/120 observations per second.
    WhaleyJumpTrail reference = {0};
    step(&reference, 0, 0, true, true);
    for (int i = 1; i <= 12; i++) step(&reference, i * 4, i * 2, false, true);
    for (int rate = 30; rate <= 120; rate *= 2) {
        WhaleyJumpTrail other = {0};
        step(&other, 0, 0, true, true);
        for (int i = 1; i <= rate / 5; i++)
            WhaleyTrailAdvance(&other, (WhaleyTrailPoint){240.0 * i / rate, 120.0 * i / rate},
                1.0 / rate, true, true, false, false, false);
        CHECK(reference.count == other.count);
        for (size_t i = 0; i < other.count; i++) {
            CHECK(fabs(reference.samples[i].point.x - other.samples[i].point.x) < 1e-8);
            CHECK(fabs(reference.samples[i].point.y - other.samples[i].point.y) < 1e-8);
            CHECK(fabs(reference.samples[i].age - other.samples[i].age) < 1e-8);
        }
    }
    WhaleyTrailReset(&trail);
    CHECK(trail.count == 0 && trail.launchCycle == 0 && !trail.active);
    step(&trail, 0, 0, true, true);
    CHECK(!trail.rainbow);
    printf("Whaley jump trails: %u checks passed\n", checks);
    return 0;
}
