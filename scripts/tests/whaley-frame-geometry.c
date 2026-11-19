#include <assert.h>
#include <float.h>
#include <stdio.h>
#include "../../Sources/WhaleyObjectiveC/src/WhaleySpriteFrameGeometry.h"

static unsigned checks;
static void near(double a, double b) {
    ++checks;
    if (!isfinite(a) || !isfinite(b) || fabs(a - b) > 1e-9) {
        fprintf(stderr, "expected %.15g, got %.15g\n", b, a);
        assert(0 && "frame contract mismatch");
    }
}

static void checkCorners(double w, double h, double ow, double oh,
                         double ox, double oy, double ax, double ay,
                         bool fx, bool fy, bool rotated) {
    WhaleyFramePlacement p = WhaleyPlaceFrame(w,h,ow,oh,ox,oy,ax,ay,fx,fy,rotated);
    // Independent reference equations from CCSprite's quad and node anchor.
    double left = (fx ? -ox : ox) + (ow-w)/2 - ax*ow;
    double bottom = (fy ? -oy : oy) + (oh-h)/2 - ay*oh;
    for (unsigned u=0; u<2; ++u) for (unsigned v=0; v<2; ++v) {
        double x = ((double)u-0.5)*p.width*p.scaleX;
        double y = ((double)v-0.5)*p.height*p.scaleY;
        if (p.quarterTurn) { double prior=x; x=-y; y=prior; }
        // Reference UV assignments: a clockwise-packed frame's top-left
        // source corner maps to the logical bottom-left corner.
        unsigned lx = rotated ? 1-v : u;
        unsigned ly = rotated ? u : v;
        if (fx) lx=1-lx;
        if (fy) ly=1-ly;
        near(p.centerX+x,left+lx*w);
        near(p.centerY+y,bottom+ly*h);
    }
}

int main(void) {
    // Actual spout.plist entries: 1024x1024 atlas, 32x32 logical frames.
    const double heights[] = {17,22,27,32};
    const double offsets[] = {-7.5,-5,-2.5,0};
    const double origins[] = {1,34,67,100};
    for (unsigned i=0; i<4; ++i) {
        WhaleyFrameRect uv;
        assert(WhaleyFrameRegion((WhaleyFrameRect){origins[i],1,32,heights[i]},false,1024,1024,&uv));
        near(uv.x,origins[i]/1024); near(uv.y,(1023-heights[i])/1024);
        near(uv.width,32.0/1024); near(uv.height,heights[i]/1024);
        WhaleyFramePlacement p=WhaleyPlaceFrame(32,heights[i],32,32,0,offsets[i],0,0,false,false,false);
        near(p.centerX-p.width/2,0); near(p.centerY-p.height/2,0);
        p=WhaleyPlaceFrame(32,heights[i],32,32,0,offsets[i],0,0,false,true,false);
        near(p.centerY+p.height/2,32); // Flipped trim stays at the logical top.
    }
    const double anchors[] = {0,0.25,0.5,0.75,1};
    for (unsigned i=0; i<5; ++i) for(unsigned j=0; j<5; ++j)
        for(unsigned flags=0; flags<8; ++flags) {
            checkCorners(12,20,40,36,3,-4,anchors[i],anchors[j],flags&1,flags&2,flags&4);
            checkCorners(32,32,32,32,0,0,anchors[i],anchors[j],flags&1,flags&2,flags&4);
        }
    // Deterministic varied metadata, including non-centered anchors/offsets.
    for (unsigned i=1;i<=500;++i) {
        double w=1+i%31,h=1+i%23;
        checkCorners(w,h,w+10,h+20,(int)(i%9)-4,(int)(i%11)-5,
                     (i%13)/12.0,(i%17)/16.0,i&1,i&2,i&4);
    }
    WhaleyFrameRect uv;
    assert(WhaleyFrameRegion((WhaleyFrameRect){10,20,12,18},true,64,80,&uv));
    near(uv.x,10.0/64); near(uv.y,48.0/80);
    near(uv.width,18.0/64); near(uv.height,12.0/80);
    assert(WhaleyFrameRegion((WhaleyFrameRect){0,0,64,80},false,64,80,&uv));
    near(uv.x,0); near(uv.y,0); near(uv.width,1); near(uv.height,1);
    assert(WhaleyFrameRegion((WhaleyFrameRect){64,80,0,0},false,64,80,&uv));
    near(uv.width,0); near(uv.height,0);
    assert(!WhaleyFrameRegion((WhaleyFrameRect){0,0,1,1},false,0,1,&uv));
    assert(!WhaleyFrameRegion((WhaleyFrameRect){-1,0,1,1},false,64,80,&uv));
    assert(!WhaleyFrameRegion((WhaleyFrameRect){0,0,-1,1},false,64,80,&uv));
    assert(!WhaleyFrameRegion((WhaleyFrameRect){63,0,2,1},false,64,80,&uv));
    assert(!WhaleyFrameRegion((WhaleyFrameRect){63,0,1,2},true,64,80,&uv));
    assert(!WhaleyFrameRegion((WhaleyFrameRect){NAN,0,1,1},false,64,80,&uv));
    assert(!WhaleyFrameRegion((WhaleyFrameRect){0,0,INFINITY,1},false,64,80,&uv));
    assert(!WhaleyFrameRegion((WhaleyFrameRect){0,0,1,1},false,INFINITY,80,&uv));
    assert(!WhaleyFrameRegion((WhaleyFrameRect){DBL_MAX,0,DBL_MAX,1},false,DBL_MAX,80,&uv));
    assert(!WhaleyFrameRegion((WhaleyFrameRect){0,0,1,1},false,64,80,NULL));
    // Invalid metadata must not partially replace a valid result.
    uv=(WhaleyFrameRect){1,2,3,4};
    assert(!WhaleyFrameRegion((WhaleyFrameRect){0,0,1000,1},false,64,80,&uv));
    near(uv.x,1); near(uv.y,2); near(uv.width,3); near(uv.height,4);
    printf("PASS: %u frame geometry comparisons; trim/anchor/flip/rotation/UV and validation.\n",checks);
    return 0;
}
