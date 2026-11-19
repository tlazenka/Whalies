#ifndef WHALEY_EXPRESSION_POLICY_H
#define WHALEY_EXPRESSION_POLICY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

// Presentation-only 60 Hz policy, mirrored by Scala's CharacterPresentation.
// Inputs are observations of completed gameplay ticks; this never changes them.
enum {
    WhaleyExpressionNeutral, WhaleyExpressionPensive, WhaleyExpressionAlarmed,
    WhaleyExpressionRelief, WhaleyExpressionHappy, WhaleyExpressionPlayful,
    WhaleyExpressionRelaxed, WhaleyExpressionWhistle, WhaleyExpressionTongueOut,
    WhaleyExpressionEyeRoll, WhaleyExpressionExasperated, WhaleyExpressionRows
};
enum { WhaleyExpressionPlaying, WhaleyExpressionDead, WhaleyExpressionWon };
enum { WhaleyExpressionNoTarget, WhaleyExpressionHazard, WhaleyExpressionCoin };
enum { WhaleyExpressionCollect, WhaleyExpressionJump, WhaleyExpressionBounce };

typedef struct { double x, y; } WhaleyExpressionPoint;
typedef struct {
    int kind;
    uint64_t identifier;
    WhaleyExpressionPoint point;
    bool active;
} WhaleyExpressionTarget;
typedef struct {
    int kind;
    uint64_t identifier;
    int side;
} WhaleyExpressionEvent;
typedef struct { int row, column; } WhaleyExpressionFrame;
typedef struct {
    uint64_t tick, targetSince, reactionStart, reactionEnd;
    uint64_t lastCoin, lastJump, lastSide, lastContact, lastBubble;
    unsigned coinStreak, jumpStreak, sideStreak, idleTicks, safeTicks;
    int reaction, priority, side;
    bool hasCoin, hasJump, hasSide, hasContact, closeCall, hasPrevious;
    WhaleyExpressionPoint previous;
    WhaleyExpressionTarget target;
} WhaleyExpressionState;
typedef struct {
    WhaleyExpressionTarget target;
    double score;
    int rank;
    bool valid, urgent;
} WhaleyExpressionCandidate;

static inline void WhaleyExpressionReset(WhaleyExpressionState *state) {
    memset(state, 0, sizeof(*state));
}

static inline double WhaleyExpressionDistanceSquared(WhaleyExpressionPoint a,
                                                     WhaleyExpressionPoint b) {
    double x = a.x - b.x, y = a.y - b.y;
    return x * x + y * y;
}

static inline double WhaleyExpressionSegmentDistance(WhaleyExpressionPoint target,
    WhaleyExpressionPoint center, WhaleyExpressionPoint motion) {
    double x = motion.x * 18, y = motion.y * 18;
    double length = x * x + y * y;
    double t = length > 0 ? ((target.x - center.x) * x + (target.y - center.y) * y) / length : 0;
    t = fmax(0, fmin(1, t));
    return WhaleyExpressionDistanceSquared(target,
        (WhaleyExpressionPoint){center.x + x * t, center.y + y * t});
}

static inline WhaleyExpressionCandidate WhaleyExpressionCandidateFor(
    WhaleyExpressionTarget target, WhaleyExpressionPoint center,
    WhaleyExpressionPoint motion, bool facingLeft, double radius) {
    WhaleyExpressionCandidate result = {0};
    double distance = WhaleyExpressionDistanceSquared(target.point, center);
    if (distance > radius * radius) return result;
    result.target = target;
    if (target.kind == WhaleyExpressionHazard && target.active) {
        result.score = WhaleyExpressionSegmentDistance(target.point, center, motion);
        if (result.score > 96 * 96) return result;
        result.urgent = result.score <= 40 * 40 && distance <= 96 * 96;
        result.rank = result.urgent ? 0 : 1;
    } else if (target.kind == WhaleyExpressionCoin) {
        if (motion.x * motion.x + motion.y * motion.y <= 0.01 * 0.01) {
            motion = (WhaleyExpressionPoint){facingLeft ? -1 : 1, 0};
        }
        double dot = (target.point.x - center.x) * motion.x + (target.point.y - center.y) * motion.y;
        if (dot < -24 * sqrt(motion.x * motion.x + motion.y * motion.y)) return result;
        result.score = distance;
        result.rank = 2;
    } else return result;
    result.valid = true;
    return result;
}

static inline bool WhaleyExpressionSameTarget(WhaleyExpressionTarget a,
                                              WhaleyExpressionTarget b) {
    return a.kind == b.kind && a.identifier == b.identifier;
}

static inline bool WhaleyExpressionBetter(WhaleyExpressionCandidate a,
                                         WhaleyExpressionCandidate b) {
    return a.valid && (!b.valid || a.rank < b.rank ||
        (a.rank == b.rank && (a.score < b.score ||
            (a.score == b.score && a.target.identifier < b.target.identifier))));
}

static inline void WhaleyExpressionReact(WhaleyExpressionState *state, int expression,
                                        int priority, unsigned duration, bool urgent) {
    if (urgent || (state->tick < state->reactionEnd && priority < state->priority)) return;
    state->reaction = expression;
    state->priority = priority;
    state->reactionStart = state->tick;
    state->reactionEnd = state->tick + duration;
}

static inline WhaleyExpressionFrame WhaleyExpressionStep(WhaleyExpressionState *state,
    WhaleyExpressionPoint center, bool facingLeft, bool grounded, int status,
    const WhaleyExpressionTarget *targets, size_t targetCount,
    const WhaleyExpressionEvent *events, size_t eventCount) {
    if (status != WhaleyExpressionPlaying) {
        WhaleyExpressionReset(state);
        return status == WhaleyExpressionDead
            ? (WhaleyExpressionFrame){WhaleyExpressionExasperated, 4}
            : (WhaleyExpressionFrame){WhaleyExpressionHappy, 4};
    }
    WhaleyExpressionPoint previous = state->hasPrevious ? state->previous : center;
    WhaleyExpressionPoint motion = state->hasPrevious
        ? (WhaleyExpressionPoint){center.x - state->previous.x, center.y - state->previous.y}
        : (WhaleyExpressionPoint){0, 0};
    state->previous = center;
    state->hasPrevious = true;
    state->tick++;
    if (state->tick >= state->reactionEnd) state->priority = 0;
    if (grounded) { state->jumpStreak = 0; state->hasJump = false; }

    WhaleyExpressionCandidate best = {0}, current = {0};
    double nearestHazard = INFINITY;
    for (size_t i = 0; i < targetCount; i++) {
        WhaleyExpressionTarget target = targets[i];
        if (target.kind == WhaleyExpressionHazard && target.active) {
            double distance = WhaleyExpressionDistanceSquared(target.point, center);
            nearestHazard = fmin(nearestHazard, distance);
            if (distance <= 36 * 36 && WhaleyExpressionDistanceSquared(target.point, previous) > 36 * 36) {
                state->closeCall = true;
            }
        }
        WhaleyExpressionCandidate candidate = WhaleyExpressionCandidateFor(target, center, motion, facingLeft, 160);
        if (WhaleyExpressionBetter(candidate, best)) best = candidate;
        if (WhaleyExpressionSameTarget(target, state->target)) {
            current = WhaleyExpressionCandidateFor(target, center, motion, facingLeft, 200);
        }
    }
    bool urgent = best.valid && best.urgent;
    bool switchTarget = !current.valid || (urgent && !current.urgent) ||
        (best.valid && state->tick - state->targetSince >= 18 &&
         (best.rank < current.rank || (best.rank == current.rank && best.score < current.score * 0.64)));
    WhaleyExpressionCandidate selected = switchTarget ? best : current;
    if (selected.valid) {
        if (!WhaleyExpressionSameTarget(selected.target, state->target)) state->targetSince = state->tick;
        state->target = selected.target;
    } else state->target = (WhaleyExpressionTarget){0};
    if (urgent) { state->priority = 0; state->reactionEnd = state->tick; }

    if (state->closeCall) {
        state->safeTicks = !urgent && nearestHazard > 64 * 64 ? state->safeTicks + 1 : 0;
        if (state->safeTicks >= 12) {
            WhaleyExpressionReact(state, WhaleyExpressionRelief, 80, 48, urgent);
            state->closeCall = false;
            state->safeTicks = 0;
        }
    }

    unsigned coins = 0, jumps = 0;
    const WhaleyExpressionEvent *bounce = NULL;
    for (size_t i = 0; i < eventCount; i++) {
        if (events[i].kind == WhaleyExpressionCollect) coins++;
        else if (events[i].kind == WhaleyExpressionJump) jumps++;
        else if (events[i].kind == WhaleyExpressionBounce && !bounce) bounce = &events[i];
    }
    if (coins) {
        state->coinStreak = (unsigned)fmin(3, state->hasCoin && state->tick - state->lastCoin <= 90 ? state->coinStreak + coins : coins);
        state->lastCoin = state->tick;
        state->hasCoin = true;
        unsigned combo = state->coinStreak;
        WhaleyExpressionReact(state, combo == 2 ? WhaleyExpressionPlayful : WhaleyExpressionHappy,
            combo >= 3 ? 55 : combo == 2 ? 45 : 40, combo >= 3 ? 54 : 36, urgent);
    }
    if (jumps) {
        state->jumpStreak = (unsigned)fmin(3, state->hasJump && state->tick - state->lastJump <= 120 ? state->jumpStreak + jumps : jumps);
        state->lastJump = state->tick;
        state->hasJump = true;
        unsigned combo = state->jumpStreak;
        WhaleyExpressionReact(state, combo >= 3 ? WhaleyExpressionPlayful : combo == 2 ? WhaleyExpressionTongueOut : WhaleyExpressionHappy,
            combo >= 3 ? 50 : 40, combo >= 3 ? 27 : combo == 2 ? 30 : 24, urgent);
    }
    if (bounce && (!state->hasContact || bounce->identifier != state->lastBubble || state->tick - state->lastContact >= 18)) {
        state->lastBubble = bounce->identifier;
        state->lastContact = state->tick;
        state->hasContact = true;
        state->sideStreak = state->hasSide && state->tick - state->lastSide <= 90 &&
            bounce->side != state->side ? (unsigned)fmin(3, state->sideStreak + 1) : 1;
        state->side = bounce->side;
        state->lastSide = state->tick;
        state->hasSide = true;
        unsigned combo = state->sideStreak;
        WhaleyExpressionReact(state, combo >= 3 ? WhaleyExpressionExasperated : combo == 2 ? WhaleyExpressionEyeRoll : WhaleyExpressionTongueOut,
            combo >= 3 ? 70 : combo == 2 ? 60 : 40, combo >= 3 ? 42 : combo == 2 ? 36 : 24, urgent);
    }

    bool idle = grounded && motion.x * motion.x + motion.y * motion.y <= 0.01 * 0.01 &&
        !eventCount && !urgent && nearestHazard > 96 * 96;
    state->idleTicks = idle ? (unsigned)fmin(300, state->idleTicks + 1) : 0;
    int row = urgent ? WhaleyExpressionAlarmed : state->priority ? state->reaction :
        state->idleTicks >= 300 ? WhaleyExpressionWhistle : state->idleTicks >= 180 ? WhaleyExpressionRelaxed :
        selected.valid ? WhaleyExpressionPensive : WhaleyExpressionNeutral;
    int column = 4;
    if (row == WhaleyExpressionEyeRoll) {
        const int eyeRoll[] = {3, 0, 1, 2, 5, 4};
        column = eyeRoll[(unsigned)fmin(5, (state->tick - state->reactionStart) / 6)];
    }
    else if (selected.valid) {
        double x = selected.target.point.x - center.x, y = selected.target.point.y - center.y;
        if (facingLeft) x = -x;
        int horizontal = x < -8 ? 0 : x > 8 ? 2 : 1;
        int vertical = y > 8 ? 0 : y < -8 ? 2 : 1;
        column = vertical * 3 + horizontal;
    }
    return (WhaleyExpressionFrame){row, column};
}

#endif
