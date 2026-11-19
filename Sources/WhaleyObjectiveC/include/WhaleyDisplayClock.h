#ifndef WHALEY_DISPLAY_CLOCK_H
#define WHALEY_DISPLAY_CLOCK_H

#include <math.h>
#include <stdbool.h>
#include <stdint.h>

/* Accumulate measured, active display time. Quantize the total rather than
 * each 1/60 or 1/120 interval, so periodic cues don't drift with frame rate. */
typedef struct {
    double previousTimestamp;
    double activeSeconds;
    int64_t emittedMicroseconds;
    bool primed;
} WhaleyDisplayClock;

static inline void WhaleyDisplayClockSuspend(WhaleyDisplayClock *clock) {
    clock->primed = false;
}

static inline double WhaleyDisplayClockAdvance(WhaleyDisplayClock *clock,
                                               double timestamp, bool running) {
    if (!running || !isfinite(timestamp) || timestamp < 0) {
        WhaleyDisplayClockSuspend(clock);
        return 0;
    }
    if (!clock->primed) {
        clock->previousTimestamp = timestamp;
        clock->primed = true;
        return 0;
    }
    double delta = timestamp - clock->previousTimestamp;
    clock->previousTimestamp = timestamp;
    if (!isfinite(delta) || delta <= 0) return 0;
    clock->activeSeconds += delta;
    int64_t total = (int64_t)llround(clock->activeSeconds * 1000000.0);
    int64_t elapsed = total - clock->emittedMicroseconds;
    clock->emittedMicroseconds = total;
    return (double)elapsed / 1000000.0;
}

#endif
