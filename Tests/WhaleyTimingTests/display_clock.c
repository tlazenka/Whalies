#include "WhaleyDisplayClock.h"
#include <assert.h>
#include <stdio.h>

static void check_rate(int fps) {
    WhaleyDisplayClock clock = {0};
    double elapsed = 0;
    assert(WhaleyDisplayClockAdvance(&clock, 100, true) == 0);
    for (int i = 1; i <= fps * 600; ++i) {
        elapsed += WhaleyDisplayClockAdvance(&clock, 100 + (double)i / fps, true);
        if (i % (fps * 10) == 0) {
            assert(fabs(elapsed - (double)i / fps) < 0.000001);
        }
    }
    assert(clock.emittedMicroseconds == INT64_C(600000000));
}

static void check_jitter(void) {
    WhaleyDisplayClock clock = {0};
    double elapsed = 0;
    (void)WhaleyDisplayClockAdvance(&clock, 1, true);
    const double timestamps[] = {1.006, 1.031, 1.047, 3.8, 10.99, 11.0, 20.999, 21.0};
    for (unsigned i = 0; i < sizeof(timestamps) / sizeof(timestamps[0]); ++i) {
        elapsed += WhaleyDisplayClockAdvance(&clock, timestamps[i], true);
    }
    assert(fabs(elapsed - 20) < 0.000001);
}

static void check_pause(void) {
    WhaleyDisplayClock clock = {0};
    (void)WhaleyDisplayClockAdvance(&clock, 100, true);
    assert(WhaleyDisplayClockAdvance(&clock, 104, true) == 4);
    assert(WhaleyDisplayClockAdvance(&clock, 105, false) == 0);
    assert(WhaleyDisplayClockAdvance(&clock, 205, false) == 0);
    assert(WhaleyDisplayClockAdvance(&clock, 300, true) == 0);
    assert(WhaleyDisplayClockAdvance(&clock, 306, true) == 6);
    assert(clock.emittedMicroseconds == INT64_C(10000000));
}

static void check_background_and_invalid_samples(void) {
    WhaleyDisplayClock clock = {0};
    (void)WhaleyDisplayClockAdvance(&clock, 0, true);
    assert(WhaleyDisplayClockAdvance(&clock, 2, true) == 2);
    WhaleyDisplayClockSuspend(&clock);
    assert(WhaleyDisplayClockAdvance(&clock, 86400, true) == 0);
    assert(WhaleyDisplayClockAdvance(&clock, 86408, true) == 8);
    assert(WhaleyDisplayClockAdvance(&clock, NAN, true) == 0);
    assert(WhaleyDisplayClockAdvance(&clock, INFINITY, true) == 0);
    assert(WhaleyDisplayClockAdvance(&clock, -1, true) == 0);
    assert(clock.emittedMicroseconds == INT64_C(10000000));
}

int main(void) {
    check_rate(30);
    check_rate(60);
    check_rate(120);
    check_jitter();
    check_pause();
    check_background_and_invalid_samples();
    puts("PASS: 6 display-clock scenarios (30/60/120 Hz, jitter, pause, background/invalid samples)");
}
