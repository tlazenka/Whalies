#include "WhaleyArenaRules.h"
#include <assert.h>
#include <stdio.h>
#include <float.h>
int main(void) {
    int checks = 0;
    #define CHECK(x) do { assert(x); ++checks; } while(0)
    WhaleyArenaLayout a = WhaleyArenaMakeLayout(20, 30, 32, 32);
    CHECK(a.valid); CHECK(a.left == 32 && a.right == 608);
    CHECK(a.bottom == 32 && a.top == 928);
    CHECK(!WhaleyArenaBlocksRect(a, 100, 100, 24, 24));
    CHECK(WhaleyArenaBlocksRect(a, 31, 100, 24, 24));
    CHECK(WhaleyArenaBlocksRect(a, 600, 100, 24, 24));
    CHECK(WhaleyArenaBlocksRect(a, 100, 31, 24, 24));
    CHECK(WhaleyArenaBlocksRect(a, 100, 920, 24, 24));
    CHECK(!WhaleyArenaBlocksRect(a, a.left, a.bottom, 24, 24));
    CHECK(WhaleyArenaBlocksRect(a, NAN, 100, 24, 24));
    for (long y=0; y<30; ++y) for (long x=0; x<20; ++x) {
        CHECK(WhaleyArenaIsPerimeter(x,y,20,30) == (x==0 || y==0 || x==19 || y==29));
    }
    CHECK(!WhaleyArenaIsPerimeter(-1, 0, 20, 30));
    CHECK(!WhaleyArenaIsPerimeter(20, 0, 20, 30));
    for (size_t i=0; i<a.bubbleCount; ++i) {
        double x = WhaleyArenaBubbleX(a,i);
        CHECK(x-a.bubbleRadius >= a.left-1e-9);
        CHECK(x+a.bubbleRadius <= a.right+1e-9);
        if (i) CHECK(x-WhaleyArenaBubbleX(a,i-1) <= 2*a.bubbleRadius);
    }
    CHECK(isnan(WhaleyArenaBubbleX(a,a.bubbleCount)));
    CHECK(!WhaleyArenaMakeLayout(2,30,32,32).valid);
    CHECK(!WhaleyArenaMakeLayout(20,30,0,32).valid);
    CHECK(!WhaleyArenaMakeLayout(20,30,NAN,32).valid);
    CHECK(!WhaleyArenaConsumesBubble(true,true));
    CHECK(WhaleyArenaConsumesBubble(false,true));
    CHECK(!WhaleyArenaConsumesBubble(false,false));
    CHECK(!WhaleyArenaMakeLayout(20,30,DBL_TRUE_MIN,DBL_TRUE_MIN).valid);
    CHECK(!WhaleyArenaMakeLayout(20,30,INFINITY,32).valid);
    CHECK(!WhaleyArenaMakeLayout(20,30,DBL_MAX,32).valid);
    CHECK(!WhaleyArenaBlocksRect(a, a.right-24, a.top-24, 24, 24));
    CHECK(WhaleyArenaBlocksRect(a, 100, 100, -1, 24));
    CHECK(!WhaleyArenaConsumesBubble(true,false));
    // Repeated contacts cannot consume a foundation; each fresh shot is consumable.
    for (int bounce=0; bounce<100; ++bounce) {
        CHECK(!WhaleyArenaConsumesBubble(true,true));
        CHECK(WhaleyArenaConsumesBubble(false,true));
    }
    printf("Arena rules: %d assertions passed\n",checks);
}
