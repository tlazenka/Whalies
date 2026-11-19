#ifndef WHALEY_FLAME_MOTION_H
#define WHALEY_FLAME_MOTION_H

#include <math.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct { double offsetX, clockwiseDegrees; } WhaleyFlamePose;

// Six seconds is the common period of the three-second spin and 1.2-second dance.
static inline double WhaleyFlameAdvance(double elapsed, double seconds, bool paused) {
    if (!isfinite(elapsed) || elapsed < 0) elapsed = 0;
    if (paused || !isfinite(seconds) || seconds <= 0) return elapsed;
    return fmod(elapsed + fmin(seconds, 0.25), 6.0);
}

static inline WhaleyFlamePose WhaleyFlamePoseAt(size_t index, double elapsed, bool reducedMotion) {
    if (reducedMotion || !isfinite(elapsed) || elapsed < 0) return (WhaleyFlamePose){0, 0};
    double time = fmod(elapsed, 6.0);
    switch (index % 3) {
        case 0: return (WhaleyFlamePose){0, (int)floor(time / 0.25 + 1e-9) % 12 * 30};
        case 1: return (WhaleyFlamePose){0, -((int)floor(time / 0.25 + 1e-9) % 12 * 30)};
        default: {
            static const int steps[] = {0, 1, 2, 1, 0, -1, -2, -1};
            return (WhaleyFlamePose){steps[(int)floor(time / 0.15 + 1e-9) % 8], 0};
        }
    }
}
#endif
