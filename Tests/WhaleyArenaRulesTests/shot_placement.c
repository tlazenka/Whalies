#include "Whaley3DShotPlacement.h"
#include <assert.h>
#include <float.h>
#include <stdio.h>
static unsigned checks;
#define CHECK(x) do { ++checks; assert(x); } while (0)
static int near(double a, double b) { return fabs(a-b) < 1e-8; }
int main(void) {
    WhaleyArenaLayout a = WhaleyArenaMakeLayout(20, 30, 32, 32);
    Whaley3DShotPlacement p = Whaley3DPlanShot(a,316,300,32,false,NAN,NAN,22,22,0);
    CHECK(p.valid && near(p.x,316) && near(p.y,280) && near(p.scale,1));
    Whaley3DShotPlacement l = Whaley3DPlanShot(a,316,300,32,false,0,0,22,22,-1);
    Whaley3DShotPlacement r = Whaley3DPlanShot(a,316,300,32,false,0,0,22,22,1);
    CHECK(l.valid && r.valid && near(l.x,299) && near(r.x,333));
    CHECK(near(l.y,p.y) && near(r.y,p.y));
    CHECK(316-l.x >= 44.0/4 && r.x-316 >= 44.0/4);
    for (int side=-1;side<=1;side++) {
        p = Whaley3DPlanShot(a,316,600,32,true,240,300,22,22,side);
        Whaley3DShotPlacement q = Whaley3DPlanShot(a,420,750,32,true,240,300,22,22,side);
        CHECK(p.valid && q.valid && p.x == q.x && p.y == q.y && p.scale == q.scale);
    }
    p = Whaley3DPlanShot(a,316,53,32,false,0,0,22,22,0);
    CHECK(p.valid && p.scale < 1 && near(p.y+22*p.scale,55));
    CHECK(p.y-22*p.scale >= a.bottom - 1e-8);
    CHECK(!Whaley3DPlanShot(a,316,32,32,false,0,0,22,22,0).valid);
    for(int side=-1;side<=1;side++) {
      for (int x=48; x<=592; x+=8) {
        for (int y=53; y<=880; y+=7) {
          p=Whaley3DPlanShot(a,x,y,32,false,0,0,22,22,side);
          CHECK(p.valid);
          CHECK(p.x-22*p.scale >= a.left-1e-8 && p.x+22*p.scale <= a.right+1e-8);
          CHECK(p.y-22*p.scale >= a.bottom-1e-8 && p.y+22*p.scale <= a.top+1e-8);
          CHECK(side == 0 ? near(p.x,x) : (side < 0 ? p.x <= x+1e-8 : p.x >= x-1e-8));
        }
      }
    }
    CHECK(!Whaley3DPlanShot(a,NAN,300,32,false,0,0,22,22,0).valid);
    CHECK(!Whaley3DPlanShot(a,316,300,32,true,NAN,300,22,22,0).valid);
    CHECK(!Whaley3DPlanShot(a,316,300,32,true,316,INFINITY,22,22,0).valid);
    CHECK(!Whaley3DPlanShot(a,316,300,32,false,0,0,INFINITY,22,0).valid);
    CHECK(!Whaley3DPlanShot(a,316,300,32,false,0,0,22,22,2).valid);
    CHECK(!Whaley3DPlanShot((WhaleyArenaLayout){0},316,300,32,false,0,0,22,22,0).valid);
    CHECK(!Whaley3DPlanShot(a,316,300,32,false,0,0,DBL_MAX,DBL_MAX,0).valid);
    puts("Native shot-placement geometry checks completed");
    printf("%u assertions passed\n",checks);
}
