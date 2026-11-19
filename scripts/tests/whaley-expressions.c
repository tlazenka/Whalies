#include <assert.h>
#include <stdio.h>
#include "../../Sources/WhaleyObjectiveC/src/WhaleyExpressionPolicy.h"

static unsigned checks;
static WhaleyExpressionFrame step(WhaleyExpressionState *s, double x, double y, bool grounded,
    const WhaleyExpressionTarget *targets, size_t targetCount,
    const WhaleyExpressionEvent *events, size_t eventCount) {
    WhaleyExpressionFrame frame = WhaleyExpressionStep(s, (WhaleyExpressionPoint){x, y}, false,
        grounded, WhaleyExpressionPlaying, targets, targetCount, events, eventCount);
    assert(frame.row >= 0 && frame.row < WhaleyExpressionRows && frame.column >= 0 && frame.column < 9);
    checks++;
    return frame;
}

static void expect(WhaleyExpressionFrame frame, int row, int column) {
    if (frame.row != row || frame.column != column) {
        fprintf(stderr, "expected frame %d,%d; got %d,%d\n", row, column, frame.row, frame.column);
        assert(0 && "expression frame mismatch");
    }
    checks++;
}

static WhaleyExpressionFrame quiet(WhaleyExpressionState *s, unsigned ticks, bool grounded) {
    WhaleyExpressionFrame frame = {0};
    for (unsigned i = 0; i < ticks; i++) frame = step(s, 0, 0, grounded, NULL, 0, NULL, 0);
    return frame;
}

static void targeting(void) {
    WhaleyExpressionState s = {0};
    WhaleyExpressionTarget targets[] = {
        {WhaleyExpressionCoin, 2, {60, 30}, true},
        {WhaleyExpressionCoin, 1, {60, 30}, true}
    };
    expect(step(&s, 0, 0, false, targets, 2, NULL, 0), WhaleyExpressionPensive, 2);
    assert(s.target.identifier == 1); // Stable ID breaks equal-distance ties.
    targets[0].point = (WhaleyExpressionPoint){10, -20};
    for (unsigned i = 0; i < 17; i++) step(&s, 0, 0, false, targets, 2, NULL, 0);
    assert(s.target.identifier == 1); // Hold through age 17.
    expect(step(&s, 0, 0, false, targets, 2, NULL, 0), WhaleyExpressionPensive, 8);
    assert(s.target.identifier == 2);
    // Coins behind the travel direction are discarded; hazards can preempt the lock.
    targets[0] = (WhaleyExpressionTarget){WhaleyExpressionHazard, 7, {-20, 0}, true};
    expect(step(&s, 0, 0, false, targets, 2, NULL, 0), WhaleyExpressionAlarmed, 3);
    expect(WhaleyExpressionStep(&s, (WhaleyExpressionPoint){0, 0}, true, false,
        WhaleyExpressionPlaying, targets, 2, NULL, 0), WhaleyExpressionAlarmed, 5);
    targets[0].active = false;
    targets[1].point = (WhaleyExpressionPoint){-25, 0};
    expect(step(&s, 0, 0, false, targets, 2, NULL, 0), WhaleyExpressionNeutral, 4);

    WhaleyExpressionReset(&s);
    targets[0] = (WhaleyExpressionTarget){WhaleyExpressionCoin, 3, {150, 0}, true};
    step(&s, 0, 0, false, targets, 1, NULL, 0);
    targets[0].point.x = 190;
    expect(step(&s, 0, 0, false, targets, 1, NULL, 0), WhaleyExpressionPensive, 5);
    targets[0].point.x = 201;
    expect(step(&s, 0, 0, false, targets, 1, NULL, 0), WhaleyExpressionNeutral, 4);

    WhaleyExpressionReset(&s);
    quiet(&s, 1, false);
    targets[0] = (WhaleyExpressionTarget){WhaleyExpressionHazard, 4, {90, 0}, true};
    // A 4px tick projects 72px forward, making the approaching hazard urgent.
    expect(step(&s, 4, 0, false, targets, 1, NULL, 0), WhaleyExpressionAlarmed, 5);

    WhaleyExpressionReset(&s);
    s.previous = (WhaleyExpressionPoint){0, 0};
    s.hasPrevious = true;
    targets[0] = (WhaleyExpressionTarget){WhaleyExpressionHazard, 4, {146, 50}, true};
    targets[1] = (WhaleyExpressionTarget){WhaleyExpressionCoin, 2, {26, 0}, true};
    expect(step(&s, 6, 0, false, targets, 2, NULL, 0), WhaleyExpressionPensive, 2);
    // Keep the hazard outside acquisition (160px), inside retention (200px),
    // and near the projected path. A much closer coin has lower priority even
    // after the 18-tick hold expires. Synthetic positions isolate that boundary.
    for (unsigned tick = 2; tick <= 20; tick++) {
        double x = tick * 6;
        targets[0].point = (WhaleyExpressionPoint){x + 170, 50};
        targets[1].point = (WhaleyExpressionPoint){x + 20, 0};
        expect(step(&s, x, 0, false, targets, 2, NULL, 0), WhaleyExpressionPensive, 2);
        assert(s.target.kind == WhaleyExpressionHazard && s.target.identifier == 4);
    }
    targets[0].active = false;
    targets[1].point.x = 146;
    expect(step(&s, 126, 0, false, targets, 2, NULL, 0), WhaleyExpressionPensive, 5);
    assert(s.target.kind == WhaleyExpressionCoin && s.target.identifier == 2);
}

static void closeCalls(void) {
    WhaleyExpressionState s = {0};
    WhaleyExpressionTarget hazard = {WhaleyExpressionHazard, 1, {0, 0}, true};
    step(&s, 30, 0, false, &hazard, 1, NULL, 0);
    assert(!s.closeCall); // Merely spawning near a hazard does not count.
    step(&s, 100, 0, false, &hazard, 1, NULL, 0);
    for (unsigned i = 0; i < 12; i++) step(&s, 100, 0, false, &hazard, 1, NULL, 0);
    assert(s.priority == 0);

    step(&s, 30, 0, false, &hazard, 1, NULL, 0);
    assert(s.closeCall);
    for (unsigned i = 0; i < 11; i++) step(&s, 100, 0, false, &hazard, 1, NULL, 0);
    assert(s.priority == 0);
    expect(step(&s, 100, 0, false, &hazard, 1, NULL, 0), WhaleyExpressionRelief, 4);
    assert(!s.closeCall);
    WhaleyExpressionEvent coin = {WhaleyExpressionCollect, 0, 0};
    expect(step(&s, 100, 0, false, &hazard, 1, &coin, 1), WhaleyExpressionRelief, 4);
    for (unsigned i = 0; i < 47; i++) step(&s, 100, 0, false, &hazard, 1, NULL, 0);
    assert(s.priority == 0); // Suppressed coin celebration is never queued.

    step(&s, 30, 0, false, &hazard, 1, NULL, 0);
    assert(s.closeCall);
    expect(WhaleyExpressionStep(&s, (WhaleyExpressionPoint){30, 0}, false, false,
        WhaleyExpressionDead, &hazard, 1, NULL, 0), WhaleyExpressionExasperated, 4);
    assert(!s.closeCall && !s.priority && !s.hasCoin);
}

static void celebrations(void) {
    WhaleyExpressionState s = {0};
    WhaleyExpressionEvent coin = {WhaleyExpressionCollect, 0, 0};
    expect(step(&s, 0, 0, false, NULL, 0, &coin, 1), WhaleyExpressionHappy, 4);
    expect(step(&s, 0, 0, false, NULL, 0, &coin, 1), WhaleyExpressionPlayful, 4);
    expect(step(&s, 0, 0, false, NULL, 0, &coin, 1), WhaleyExpressionHappy, 4);
    expect(quiet(&s, 6, false), WhaleyExpressionHappy, 4);
    expect(quiet(&s, 48, false), WhaleyExpressionNeutral, 4);
    quiet(&s, 37, false); // 91 ticks since the last collection starts a fresh combo.
    expect(step(&s, 0, 0, false, NULL, 0, &coin, 1), WhaleyExpressionHappy, 4);

    WhaleyExpressionTarget danger = {WhaleyExpressionHazard, 1, {20, 0}, true};
    expect(step(&s, 0, 0, false, &danger, 1, &coin, 1), WhaleyExpressionAlarmed, 5);
    expect(quiet(&s, 1, false), WhaleyExpressionNeutral, 4);
    assert(s.coinStreak == 2); // Counters continue, interrupted reactions do not.

    WhaleyExpressionReset(&s);
    WhaleyExpressionEvent jump = {WhaleyExpressionJump, 1, 0};
    expect(step(&s, 0, 0, false, NULL, 0, &jump, 1), WhaleyExpressionHappy, 4);
    expect(step(&s, 0, 0, false, NULL, 0, &jump, 1), WhaleyExpressionTongueOut, 4);
    expect(step(&s, 0, 0, false, NULL, 0, &jump, 1), WhaleyExpressionPlayful, 4);
    expect(quiet(&s, 24, false), WhaleyExpressionPlayful, 4);
    expect(quiet(&s, 3, false), WhaleyExpressionNeutral, 4);
    quiet(&s, 1, true); // A landing resets the upward chain.
    expect(step(&s, 0, 0, false, NULL, 0, &jump, 1), WhaleyExpressionHappy, 4);
    assert(s.jumpStreak == 1);

    WhaleyExpressionReset(&s);
    WhaleyExpressionEvent simultaneous[] = {jump, coin};
    step(&s, 0, 0, false, NULL, 0, simultaneous, 2);
    // Shared policy processes coins then jumps, regardless of hook emission order.
    expect(quiet(&s, 24, false), WhaleyExpressionNeutral, 4);

    WhaleyExpressionReset(&s);
    WhaleyExpressionEvent combo[] = {coin, coin, coin};
    WhaleyExpressionTarget nextCoin = {WhaleyExpressionCoin, 7, {40, 40}, true};
    expect(step(&s, 0, 0, false, &nextCoin, 1, combo, 3), WhaleyExpressionHappy, 2);
    nextCoin.point.y = -40;
    expect(step(&s, 0, 0, false, &nextCoin, 1, NULL, 0), WhaleyExpressionHappy, 8);
}

static void ricochets(void) {
    WhaleyExpressionState s = {0};
    WhaleyExpressionEvent bounce = {WhaleyExpressionBounce, 1, 1};
    expect(step(&s, 0, 0, false, NULL, 0, &bounce, 1), WhaleyExpressionTongueOut, 4);
    for (unsigned i = 0; i < 17; i++) step(&s, 0, 0, false, NULL, 0, &bounce, 1);
    assert(s.lastContact == 1); // Held contact does not retrigger every frame.
    step(&s, 0, 0, false, NULL, 0, &bounce, 1);
    assert(s.lastContact == 19);
    bounce = (WhaleyExpressionEvent){WhaleyExpressionBounce, 2, -1};
    expect(step(&s, 0, 0, false, NULL, 0, &bounce, 1), WhaleyExpressionEyeRoll, 3);
    const int eyeRoll[] = {0, 1, 2, 5, 4};
    for (unsigned i = 0; i < 5; i++) expect(quiet(&s, 6, false), WhaleyExpressionEyeRoll, eyeRoll[i]);
    bounce = (WhaleyExpressionEvent){WhaleyExpressionBounce, 3, 1};
    expect(step(&s, 0, 0, false, NULL, 0, &bounce, 1), WhaleyExpressionExasperated, 4);
    WhaleyExpressionEvent coins[] = {
        {WhaleyExpressionCollect, 0, 0}, {WhaleyExpressionCollect, 0, 0}, {WhaleyExpressionCollect, 0, 0}
    };
    expect(step(&s, 0, 0, false, NULL, 0, coins, 3), WhaleyExpressionExasperated, 4);
    expect(quiet(&s, 41, false), WhaleyExpressionNeutral, 4);

    WhaleyExpressionReset(&s);
    WhaleyExpressionEvent contacts[] = {
        {WhaleyExpressionBounce, 1, -1}, {WhaleyExpressionBounce, 2, 1}
    };
    expect(step(&s, 0, 0, false, NULL, 0, contacts, 2), WhaleyExpressionTongueOut, 4);
    assert(s.sideStreak == 1); // Multiple contacts in one tick produce one side cue.
}

static void idleAndTerminal(void) {
    WhaleyExpressionState s = {0};
    expect(quiet(&s, 179, true), WhaleyExpressionNeutral, 4);
    expect(quiet(&s, 1, true), WhaleyExpressionRelaxed, 4);
    expect(quiet(&s, 120, true), WhaleyExpressionWhistle, 4);
    expect(step(&s, 0.02, 0, true, NULL, 0, NULL, 0), WhaleyExpressionNeutral, 4);
    quiet(&s, 301, true);
    WhaleyExpressionTarget nearby = {WhaleyExpressionHazard, 0, {80, 0}, true};
    expect(step(&s, 0, 0, true, &nearby, 1, NULL, 0), WhaleyExpressionPensive, 5);
    assert(s.idleTicks == 0);
    for (unsigned i = 0; i < 55; i++) {
        expect(WhaleyExpressionStep(&s, (WhaleyExpressionPoint){0, 0}, false, true,
            WhaleyExpressionWon, NULL, 0, NULL, 0), WhaleyExpressionHappy, 4);
    }
    WhaleyExpressionReset(&s);
    expect(quiet(&s, 1, false), WhaleyExpressionNeutral, 4);
    assert(!s.hasCoin && !s.hasJump && !s.hasContact && !s.closeCall && !s.target.kind);
}

int main(void) {
    targeting(); closeCalls(); celebrations(); ricochets(); idleAndTerminal();
    printf("PASS: 5 native expression scenarios (%u checked frames/assertions); targeting, relief, facial combos, ricochets, idle/terminal states.\n", checks);
    return 0;
}
