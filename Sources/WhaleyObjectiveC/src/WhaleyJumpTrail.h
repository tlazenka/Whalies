#ifndef WHALEY_JUMP_TRAIL_H
#define WHALEY_JUMP_TRAIL_H

#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

enum {
    WhaleyTrailCapacity = 48,
    WhaleyPuddleCapacity = 48,
    WhaleyWaterLaneCount = 3,
    WhaleyWaterLandedMask = (1u << WhaleyWaterLaneCount) - 1u,
    WhaleyTrailMarkCapacity = WhaleyTrailCapacity * WhaleyWaterLaneCount * 2 + WhaleyPuddleCapacity * 2
};
static const double WhaleyTrailLifetime = 0.30;
static const double WhaleyWaterLifetime = 0.75;
static const double WhaleyPuddleLifetime = 4.0;
static const double WhaleyTrailWidth = 32; // Original player sprite, in logical pixels.
typedef struct { double x, y; } WhaleyTrailPoint;
typedef struct { double left, right, y; } WhaleyTrailSurface;
// Return the highest exposed surface crossed by a descending droplet's bottom.
typedef bool (*WhaleyTrailSurfaceQuery)(void *context, double x, double fromBottom,
                                      double toBottom, WhaleyTrailSurface *surface);
typedef struct {
    WhaleyTrailPoint point, normal;
    double age;
    bool rainbow;
    unsigned landedMask;
} WhaleyTrailSample;
typedef struct {
    WhaleyTrailPoint point;
    double left, right, width, age;
} WhaleyTrailPuddle;
typedef struct {
    WhaleyTrailSample samples[WhaleyTrailCapacity];
    WhaleyTrailPuddle puddles[WhaleyPuddleCapacity];
    size_t count, puddleCount;
    unsigned launchCycle;
    bool active, rainbow, hasPrevious;
    WhaleyTrailPoint previous;
    double distanceRemainder;
} WhaleyJumpTrail;
typedef struct {
    WhaleyTrailPoint center;
    double width, height, alpha;
    uint8_t red, green, blue;
} WhaleyTrailMark;

static inline void WhaleyTrailReset(WhaleyJumpTrail *trail) {
    memset(trail, 0, sizeof(*trail));
}

static inline void WhaleyTrailStop(WhaleyJumpTrail *trail) {
    trail->count = 0;
    trail->puddleCount = 0;
    trail->active = false;
    trail->hasPrevious = false;
    trail->distanceRemainder = 0;
}

static inline WhaleyTrailPoint WhaleyTrailWaterOrigin(const WhaleyTrailSample *sample,
                                                     size_t lane) {
    double spread = WhaleyTrailWidth - 2 * fabs(sample->normal.x) - 3 * fabs(sample->normal.y);
    double offset = ((double)lane / (WhaleyWaterLaneCount - 1) - 0.5) * spread;
    return (WhaleyTrailPoint){floor(sample->point.x + sample->normal.x * offset + 0.5),
                             sample->point.y + sample->normal.y * offset};
}

static inline void WhaleyTrailDeposit(WhaleyJumpTrail *trail, double x,
                                     WhaleyTrailSurface surface, double age) {
    if (age >= WhaleyPuddleLifetime) return;
    for (size_t i = 0; i < trail->puddleCount; i++) {
        WhaleyTrailPuddle *puddle = &trail->puddles[i];
        if (fabs(puddle->point.x - x) <= 6 && fabs(puddle->point.y - surface.y) <= 1e-9 &&
            puddle->left == surface.left && puddle->right == surface.right) {
            puddle->width = fmin(12, puddle->width + 2);
            puddle->age = fmin(puddle->age, age);
            return;
        }
    }
    if (trail->puddleCount == WhaleyPuddleCapacity) {
        memmove(trail->puddles, trail->puddles + 1,
                (WhaleyPuddleCapacity - 1) * sizeof(WhaleyTrailPuddle));
        trail->puddleCount--;
    }
    trail->puddles[trail->puddleCount++] = (WhaleyTrailPuddle){
        {x, surface.y}, surface.left, surface.right, 8, age};
}

static inline void WhaleyTrailCollideSample(WhaleyJumpTrail *trail, WhaleyTrailSample *sample,
    double fromAge, double toAge, WhaleyTrailSurfaceQuery query, void *context) {
    if (!query || sample->rainbow) return;
    double sweptAge = fmin(toAge, WhaleyWaterLifetime);
    for (size_t lane = 0; lane < WhaleyWaterLaneCount; lane++) {
        if (sample->landedMask & (1u << lane)) continue;
        WhaleyTrailPoint origin = WhaleyTrailWaterOrigin(sample, lane);
        double bottom = origin.y - 1.5;
        double fromBottom = bottom - 20 * fromAge - 90 * fromAge * fromAge;
        double toBottom = bottom - 20 * sweptAge - 90 * sweptAge * sweptAge;
        WhaleyTrailSurface surface;
        if (query(context, origin.x, fromBottom, toBottom, &surface)) {
            sample->landedMask |= 1u << lane;
            // Keep the part of this frame after impact, including a final sweep at expiry.
            double hitAge = fmax(fromAge,
                (-20 + sqrt(fmax(0, 400 + 360 * (bottom - surface.y)))) / 180);
            WhaleyTrailDeposit(trail, origin.x, surface, fmax(0, toAge - hitAge));
        }
    }
}

static inline void WhaleyTrailAppendWithSurfaces(WhaleyJumpTrail *trail, WhaleyTrailSample sample,
                                                 WhaleyTrailSurfaceQuery query, void *context) {
    WhaleyTrailCollideSample(trail, &sample, 0, sample.age, query, context);
    if (sample.age >= (sample.rainbow ? WhaleyTrailLifetime : WhaleyWaterLifetime) ||
        (!sample.rainbow && sample.landedMask == WhaleyWaterLandedMask)) return;
    if (trail->count == WhaleyTrailCapacity) {
        memmove(trail->samples, trail->samples + 1,
                (WhaleyTrailCapacity - 1) * sizeof(WhaleyTrailSample));
        trail->count--;
    }
    trail->samples[trail->count++] = sample;
}

static inline void WhaleyTrailAppend(WhaleyJumpTrail *trail, WhaleyTrailSample sample) {
    WhaleyTrailAppendWithSurfaces(trail, sample, NULL, NULL);
}

// Consume completed gameplay observations; never move or rotate the player.
static inline void WhaleyTrailAdvanceWithSurfaces(WhaleyJumpTrail *trail, WhaleyTrailPoint point,
    double seconds, bool airborne, bool playing, bool jumped, bool paused, bool reducedMotion,
    WhaleyTrailSurfaceQuery query, void *context) {
    if (!isfinite(point.x) || !isfinite(point.y) || !playing || reducedMotion) {
        WhaleyTrailStop(trail);
        return;
    }
    if (paused) {
        trail->previous = point;
        trail->hasPrevious = true;
        trail->distanceRemainder = 0;
        return;
    }
    if (!isfinite(seconds) || seconds <= 0) return;
    if (seconds > 0.25) {
        WhaleyTrailStop(trail);
        trail->previous = point;
        trail->hasPrevious = true;
        return;
    }
    size_t remaining = 0;
    for (size_t i = 0; i < trail->puddleCount; i++) {
        WhaleyTrailPuddle puddle = trail->puddles[i];
        puddle.age += seconds;
        if (puddle.age < WhaleyPuddleLifetime) trail->puddles[remaining++] = puddle;
    }
    trail->puddleCount = remaining;
    remaining = 0;
    for (size_t i = 0; i < trail->count; i++) {
        WhaleyTrailSample sample = trail->samples[i];
        double age = sample.age + seconds;
        WhaleyTrailCollideSample(trail, &sample, sample.age, age, query, context);
        sample.age = age;
        double lifetime = sample.rainbow ? WhaleyTrailLifetime : WhaleyWaterLifetime;
        if (sample.age < lifetime && (sample.rainbow || sample.landedMask != WhaleyWaterLandedMask))
            trail->samples[remaining++] = sample;
    }
    trail->count = remaining;
    WhaleyTrailPoint delta = trail->hasPrevious
        ? (WhaleyTrailPoint){point.x - trail->previous.x, point.y - trail->previous.y}
        : (WhaleyTrailPoint){0, 0};
    double distance = hypot(delta.x, delta.y);
    // A checkpoint, scene edit or long discontinuity must not paint a connecting line.
    if (!isfinite(distance) || distance > 96) {
        WhaleyTrailStop(trail);
        distance = 0;
    }
    if (jumped && airborne) {
        trail->launchCycle = (trail->launchCycle + 1) % 4;
        trail->rainbow = trail->launchCycle == 0;
        trail->active = true;
        trail->distanceRemainder = 0;
        WhaleyTrailPoint normal = distance > 1e-9
            ? (WhaleyTrailPoint){-delta.y / distance, delta.x / distance}
            : (WhaleyTrailPoint){-1, 0};
        WhaleyTrailAppendWithSurfaces(trail,
            (WhaleyTrailSample){point, normal, 0, trail->rainbow, 0}, query, context);
    } else {
        if (!airborne) {
            trail->active = false;
            trail->distanceRemainder = 0;
        }
        if (trail->active && distance > 1e-9) {
            double spacing = trail->rainbow ? 2 : 4;
            WhaleyTrailPoint normal = {-delta.y / distance, delta.x / distance};
            for (double offset = spacing - trail->distanceRemainder;
                 offset <= distance + 1e-9; offset += spacing) {
                double fraction = fmin(1, offset / distance);
                WhaleyTrailPoint position = {trail->previous.x + delta.x * fraction,
                                            trail->previous.y + delta.y * fraction};
                WhaleyTrailAppendWithSurfaces(trail, (WhaleyTrailSample){position, normal,
                    seconds * (1 - fraction), trail->rainbow, 0}, query, context);
            }
            trail->distanceRemainder = fmod(trail->distanceRemainder + distance, spacing);
            if (trail->distanceRemainder < 1e-9 || spacing - trail->distanceRemainder < 1e-9)
                trail->distanceRemainder = 0;
        }
    }
    trail->previous = point;
    trail->hasPrevious = true;
}

static inline void WhaleyTrailAdvance(WhaleyJumpTrail *trail, WhaleyTrailPoint point,
    double seconds, bool airborne, bool playing, bool jumped, bool paused, bool reducedMotion) {
    WhaleyTrailAdvanceWithSurfaces(trail, point, seconds, airborne, playing, jumped, paused,
                                   reducedMotion, NULL, NULL);
}

// Bottom-left world coordinates, rounded to logical pixels before camera projection.
static inline size_t WhaleyTrailMarks(const WhaleyJumpTrail *trail,
                                     WhaleyTrailMark marks[WhaleyTrailMarkCapacity]) {
    static const uint8_t colors[6][3] = {
        {239, 82, 82}, {255, 165, 66}, {255, 221, 87},
        {86, 200, 116}, {0, 114, 206}, {150, 100, 225}
    };
    size_t count = 0;
    for (size_t i = 0; i < trail->puddleCount; i++) {
        const WhaleyTrailPuddle *puddle = &trail->puddles[i];
        double fraction = puddle->age / WhaleyPuddleLifetime;
        double spread = 0.75 + 0.25 * fmin(puddle->age / 0.15, 1);
        double width = fmax(2, floor(puddle->width * spread * (1 - 0.6 * fraction) + 0.5));
        double wantedLeft = floor(puddle->point.x - width / 2 + 0.5);
        double left = fmax(puddle->left, wantedLeft);
        double right = fmin(puddle->right, wantedLeft + width);
        width = right - left;
        if (width < 1) continue;
        double height = puddle->age < 2 ? 2 : 1;
        WhaleyTrailPoint center = {(left + right) / 2, puddle->point.y + height / 2};
        marks[count++] = (WhaleyTrailMark){center, width, height, 0.6 * (1 - fraction), 0, 114, 206};
        center.y = puddle->point.y + height - 0.5;
        marks[count++] = (WhaleyTrailMark){center, fmax(1, floor(width * 0.5 + 0.5)), 1,
            0.45 * (1 - fraction), 150, 220, 255};
    }
    for (size_t i = 0; i < trail->count; i++) {
        const WhaleyTrailSample *sample = &trail->samples[i];
        double lifetime = sample->rainbow ? WhaleyTrailLifetime : WhaleyWaterLifetime;
        double alpha = 0.8 * fmax(0, 1 - sample->age / lifetime);
        if (sample->rainbow) {
            for (size_t band = 0; band < 6; band++) {
                // Subtract the square's projected footprint so the full ribbon spans 32 pixels.
                double spread = WhaleyTrailWidth - 6 * (fabs(sample->normal.x) + fabs(sample->normal.y));
                double offset = ((double)band / 5 - 0.5) * spread;
                WhaleyTrailPoint center = {
                    floor(sample->point.x + sample->normal.x * offset + 0.5),
                    floor(sample->point.y + sample->normal.y * offset + 0.5)
                };
                marks[count++] = (WhaleyTrailMark){center, 6, 6, alpha,
                    colors[band][0], colors[band][1], colors[band][2]};
            }
        } else {
            double age = sample->age;
            for (size_t lane = 0; lane < WhaleyWaterLaneCount; lane++) {
                if (sample->landedMask & (1u << lane)) continue;
                WhaleyTrailPoint center = WhaleyTrailWaterOrigin(sample, lane);
                center.y = floor(center.y - 20 * age - 90 * age * age + 0.5);
                marks[count++] = (WhaleyTrailMark){center, 2, 3, alpha, 0, 114, 206};
                center.x -= 0.5;
                center.y += 0.5;
                marks[count++] = (WhaleyTrailMark){center, 1, 1, alpha, 255, 255, 255};
            }
        }
    }
    return count;
}
#endif
