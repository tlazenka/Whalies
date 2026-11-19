#include "../../Sources/WhaleyObjectiveC/src/WhaleyJumpTrail.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
#define CHECK(value) do { checks++; if (!(value)) { \
    fprintf(stderr, "line %d: %s\n", __LINE__, #value); exit(1); } } while (0)

static void checkWidth(WhaleyTrailPoint normal, WhaleyTrailPoint point, bool rainbow, double age) {
    WhaleyJumpTrail trail = {0};
    trail.count = 1;
    trail.samples[0] = (WhaleyTrailSample){.point = point, .normal = normal, .age = age, .rainbow = rainbow};
    WhaleyTrailMark marks[WhaleyTrailMarkCapacity];
    unsigned char original[sizeof(trail)];
    memcpy(original, &trail, sizeof(trail));
    size_t count = WhaleyTrailMarks(&trail, marks);
    CHECK(count == 6);
    CHECK(memcmp(original, &trail, sizeof(trail)) == 0);
    double low = INFINITY, high = -INFINITY;
    for (size_t i = 0; i < count; i++) {
        // Water highlights sit inside their droplets and do not widen the effect.
        double center = marks[i].center.x * normal.x + marks[i].center.y * normal.y;
        double half = (marks[i].width * fabs(normal.x) + marks[i].height * fabs(normal.y)) / 2;
        low = fmin(low, center - half);
        high = fmax(high, center + half);
        if (!rainbow && i % 2 == 0) {
            CHECK(marks[i].width == 2 && marks[i].height == 3);
            CHECK(marks[i].red == 0 && marks[i].green == 114 && marks[i].blue == 206);
        }
    }
    // Each independently snapped endpoint can move up to half a pixel per axis.
    CHECK(fabs(high - low - 32) <= sqrt(2.0) + 1e-8);
    if (normal.x == 0 || normal.y == 0) CHECK(fabs(high - low - 32) < 1e-8);
}

int main(void) {
    for (int style = 0; style < 2; style++) {
        for (int direction = 0; direction < 360; direction++) {
            double angle = direction * 3.14159265358979323846 / 180;
            WhaleyTrailPoint normal = {cos(angle), sin(angle)};
            for (int origin = 0; origin < 4; origin++) {
                for (int age = 0; age < 3; age++) {
                    checkWidth(normal, (WhaleyTrailPoint){10.25 * origin, -20.25 * origin},
                               style != 0, 0.14 * age);
                }
            }
        }
        checkWidth((WhaleyTrailPoint){1, 0}, (WhaleyTrailPoint){0, 0}, style != 0, 0);
        checkWidth((WhaleyTrailPoint){0, 1}, (WhaleyTrailPoint){0, 0}, style != 0, 0);
        WhaleyJumpTrail full = {0};
        full.count = WhaleyTrailCapacity;
        for (size_t i = 0; i < full.count; i++)
            full.samples[i] = (WhaleyTrailSample){.point = {0, 0}, .normal = {1, 0}, .rainbow = style != 0};
        WhaleyTrailMark marks[WhaleyTrailMarkCapacity];
        CHECK(WhaleyTrailMarks(&full, marks) == WhaleyTrailCapacity * 6);
    }
    printf("Whaley trail width: %u checks passed\n", checks);
    return 0;
}
