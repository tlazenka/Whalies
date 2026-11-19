#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../../Sources/WhaleyObjectiveC/src/WhaleyTitleGeometry.h"

/* Numeric fixtures from the existing title_font.fnt/title_font2.fnt, not a
 * font copy or substitute asset. Golden rectangles are evaluated separately
 * from Legacy/MainMenu's (24, height - 109 - 20) and CCLabelBMFont formulas.
 * Both files have the same metrics; the completed title changes characters. */
typedef struct {
    double advance, xoffset, yoffset, width, height;
} Glyph;
typedef struct { double x, y, width, height; } Bounds;

static Glyph glyph(char c) {
    switch (c) {
        case 'G': return (Glyph){45, 8, 24, 50, 59};
        case 'r': return (Glyph){15, 1, 42, 29, 20};
        case 'a': return (Glyph){22, 2, 40, 41, 23};
        case 'y': return (Glyph){18, -32, 41, 91, 54};
        case ' ': return (Glyph){16, 0, 60, 0, 0};
        case 'W': return (Glyph){60, 7, 19, 106, 44};
        case 'h': return (Glyph){21, 1, 1, 93, 62};
        case 'l': return (Glyph){16, 3, 6, 66, 56};
        case 'e': return (Glyph){16, 3, 42, 32, 20};
        case 'd': return (Glyph){21, 1, 5, 89, 61};
        default: assert(0 && "unexpected fixture character"); return (Glyph){0};
    }
}

static void near(double actual, double expected) {
    assert(isfinite(actual) && isfinite(expected));
    if (fabs(actual - expected) >= 1e-9) {
        fprintf(stderr, "expected %.9f, got %.9f\n", expected, actual);
        assert(0 && "geometry mismatch");
    }
}

static void layout(const char *text, double height, Bounds out[10]) {
    double pen = 0;
    for (unsigned i = 0; i < 10; ++i) {
        Glyph g = glyph(text[i]);
        WhaleyTitlePoint owner = WhaleyTitleLetterCenter(height, 109, pen, g.advance);
        WhaleyTitlePoint painted = WhaleyBitmapGlyphCenter(-g.advance / 2, 109,
            g.xoffset, g.yoffset, g.width, g.height, 1);
        out[i] = (Bounds){owner.x + painted.x - g.width / 2,
                         owner.y + painted.y - g.height / 2, g.width, g.height};
        pen += g.advance;
    }
}

static void checkTitle(const char *text, const Bounds expected[10]) {
    for (int pass = 0; pass < 2; ++pass) {
        double height = pass == 0 ? 568 : 480;
        Bounds actual[10];
        layout(text, height, actual);
        for (unsigned i = 0; i < 10; ++i) {
            near(actual[i].x, expected[i].x);
            near(actual[i].y, expected[i].y + height - 568);
            near(actual[i].width, expected[i].width);
            near(actual[i].height, expected[i].height);
        }
    }
}

int main(void) {
    const Bounds gray[10] = {
        {32,465,50,59}, {70,486,29,20}, {86,485,41,23}, {74,453,91,54},
        {124,488,0,0}, {147,485,106,44}, {201,485,93,62}, {223,485,41,23},
        {246,486,66,56}, {262,486,32,20}
    };
    const Bounds glad[10] = {
        {32,465,50,59}, {72,486,66,56}, {87,485,41,23}, {108,482,89,61},
        {128,488,0,0}, {151,485,106,44}, {205,485,93,62}, {227,485,41,23},
        {250,486,66,56}, {266,486,32,20}
    };
    checkTitle("Gray Whale", gray);
    checkTitle("Glad Whale", glad);

    WhaleyTitlePoint reward = WhaleyTitleRewardCenter(320, 568, 109);
    near(reward.x, 141); near(reward.y, 504);
    reward = WhaleyTitleRewardCenter(320, 480, 109);
    near(reward.x, 141); near(reward.y, 416);
    reward = WhaleyTitleRewardCenter(768, 1024, 109);
    near(reward.x, 365); near(reward.y, 960);
    WhaleyTitlePoint first = WhaleyTitleLetterCenter(1024, 109, 0, 45);
    near(first.x - 45.0 / 2, 24); // A wider surface never re-centers title glyphs.
    near(first.y + 109.0 / 2, 1004);

    reward = WhaleyTitleRewardCenter(320, 568, 109);
    assert(WhaleyTitleRewardHit(141, 504, reward));
    assert(WhaleyTitleRewardHit(168.999, 504, reward));
    assert(!WhaleyTitleRewardHit(169, 504, reward));
    assert(!WhaleyTitleRewardHit(170, 504, reward));
    assert(!WhaleyTitleRewardHit(NAN, 504, reward));
    assert(!WhaleyTitleRewardHit(141, INFINITY, reward));
    near(WhaleyTitleRewardDiameter(), 16);
    near(WhaleyTitleRewardAlpha() * 255, 150);
    near(WhaleyTitleChalkAlpha() * 255, 100);
    near(WhaleyTitleFadeSeconds(), 0.1);

    // One touch can hit both y and W when the reward has already been popped.
    // It must not be reduced to a single nearest advance-cell candidate.
    unsigned mask = 0;
    for (unsigned i = 0; i < 10; ++i) {
        Bounds b = gray[i];
        if (WhaleyTitleGlyphHit(150,500,b.x,b.y,b.width,b.height)) mask |= 1u << i;
    }
    assert(mask == ((1u << 3) | (1u << 5)));
    assert(WhaleyTitleRewardHit(150,500,reward)); // visible reward takes precedence
    // Negative overhang is hittable; empty advance space and boundaries are not.
    assert(WhaleyTitleGlyphHit(75,454,74,453,91,54));
    assert(!WhaleyTitleGlyphHit(124,488,124,488,0,0));
    assert(!WhaleyTitleGlyphHit(165,454,74,453,91,54));
    assert(!WhaleyTitleGlyphHit(NAN,454,74,453,91,54));
    assert(WhaleyTitleGlyphHit(73.5,454,74,453,91,54)); // original 1x1 touch rect

    // Font scaling affects offsets, not the caller's already-scaled pen.
    WhaleyTitlePoint half = WhaleyBitmapGlyphCenter(-11.25,109,8,24,50,59,0.5);
    near(half.x,5.25); near(half.y,0.5);
    // Synthetic kerning: MainMenu adjusts the pen before invoking the helper.
    WhaleyTitlePoint kerned = WhaleyTitleLetterCenter(568,109,45 - 2,15);
    near(kerned.x,74.5);
    puts("PASS: Gray/Glad golden glyph rectangles (480/568), fixed title origin,");
    puts("reward geometry/strict hit radius, overlapping glyph hits, alpha/timing, scaling and kerning.");
    return 0;
}
