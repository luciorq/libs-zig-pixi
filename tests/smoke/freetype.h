/* The test font of the zig-freetype and zig-harfbuzz smoke tests
 * (freetype.c, harfbuzz.c): a TrueType font written byte by byte here, so
 * no font file (and no font licence) enters the repository. Three glyphs:
 * 0 .notdef (empty, advance 500), 1 a square (U+0041 'A', advance 600) and
 * 2 a triangle (U+0042 'B', advance 800), 1024 units per em. Tables: cmap
 * (format 4), glyf, head, hhea, hmtx, loca (long), maxp, name, post
 * (format 3); no hinting instructions, no OS/2, no GSUB. */
#ifndef ZIG_LIBS_SMOKE_TEST_FONT_H
#define ZIG_LIBS_SMOKE_TEST_FONT_H

#include <string.h>

#define TEST_FONT_UPEM 1024
#define TEST_FONT_GLYPHS 3

typedef struct {
    unsigned char *p;
    size_t n, cap;
} tf_buf;

static void tf_u8(tf_buf *b, unsigned v) {
    if (b->n < b->cap) b->p[b->n] = (unsigned char)v;
    b->n++;
}
static void tf_u16(tf_buf *b, unsigned v) { tf_u8(b, v >> 8 & 0xff); tf_u8(b, v & 0xff); }
static void tf_i16(tf_buf *b, int v) { tf_u16(b, (unsigned)(v & 0xffff)); }
static void tf_u32(tf_buf *b, unsigned long v) { tf_u16(b, (unsigned)(v >> 16 & 0xffff)); tf_u16(b, (unsigned)(v & 0xffff)); }
static void tf_pad4(tf_buf *b) { while (b->n % 4) tf_u8(b, 0); }

/* A simple glyph, one contour of on-curve points (clockwise, as TrueType
 * outer contours), coordinates as int16 deltas. */
static void tf_glyph(tf_buf *b, const int *xy, int npts) {
    int i, xmin = xy[0], xmax = xy[0], ymin = xy[1], ymax = xy[1], px = 0, py = 0;
    for (i = 1; i < npts; i++) {
        if (xy[2 * i] < xmin) xmin = xy[2 * i];
        if (xy[2 * i] > xmax) xmax = xy[2 * i];
        if (xy[2 * i + 1] < ymin) ymin = xy[2 * i + 1];
        if (xy[2 * i + 1] > ymax) ymax = xy[2 * i + 1];
    }
    tf_i16(b, 1);
    tf_i16(b, xmin); tf_i16(b, ymin); tf_i16(b, xmax); tf_i16(b, ymax);
    tf_u16(b, (unsigned)(npts - 1)); /* endPtsOfContours[0] */
    tf_u16(b, 0);                    /* no instructions */
    for (i = 0; i < npts; i++) tf_u8(b, 0x01); /* on curve, int16 x and y */
    for (i = 0; i < npts; i++) { tf_i16(b, xy[2 * i] - px); px = xy[2 * i]; }
    for (i = 0; i < npts; i++) { tf_i16(b, xy[2 * i + 1] - py); py = xy[2 * i + 1]; }
    tf_pad4(b);
}

/* Writes the font into out[0..cap) and returns its size, or 0 when cap is
 * too small. */
static size_t test_font(unsigned char *out, size_t cap) {
    enum { NT = 9 };
    static const char *tags[NT] = {"cmap", "glyf", "head", "hhea", "hmtx", "loca", "maxp", "name", "post"};
    static const int square[] = {100, 0, 100, 700, 500, 700, 500, 0};
    static const int triangle[] = {100, 0, 400, 700, 700, 0};
    static const char *names[2] = {"Smoke", "Regular"};
    size_t off[NT], len[NT], loca[TEST_FONT_GLYPHS + 1];
    tf_buf b = {out, 0, cap};
    size_t dir, t, i, k, gstart;

    /* offset table and directory, filled in at the end */
    tf_u32(&b, 0x00010000UL);
    tf_u16(&b, NT);
    tf_u16(&b, 128); tf_u16(&b, 3); tf_u16(&b, NT * 16 - 128);
    dir = b.n;
    for (t = 0; t < NT * 16; t++) tf_u8(&b, 0);

    /* cmap: one Windows Unicode BMP subtable, format 4: 'A'..'B' -> 1..2 */
    t = 0; off[t] = b.n;
    tf_u16(&b, 0); tf_u16(&b, 1);
    tf_u16(&b, 3); tf_u16(&b, 1); tf_u32(&b, 12);
    tf_u16(&b, 4); tf_u16(&b, 32); tf_u16(&b, 0);
    tf_u16(&b, 4); tf_u16(&b, 4); tf_u16(&b, 1); tf_u16(&b, 0); /* 2 segments */
    tf_u16(&b, 0x42); tf_u16(&b, 0xffff);                       /* endCode */
    tf_u16(&b, 0);                                              /* reservedPad */
    tf_u16(&b, 0x41); tf_u16(&b, 0xffff);                       /* startCode */
    tf_i16(&b, 1 - 0x41); tf_i16(&b, 1);                        /* idDelta */
    tf_u16(&b, 0); tf_u16(&b, 0);                               /* idRangeOffset */
    len[t] = b.n - off[t]; tf_pad4(&b);

    /* glyf */
    t = 1; off[t] = gstart = b.n;
    loca[0] = 0;
    loca[1] = 0; /* .notdef: no outline */
    tf_glyph(&b, square, 4);
    loca[2] = b.n - gstart;
    tf_glyph(&b, triangle, 3);
    loca[3] = b.n - gstart;
    len[t] = b.n - off[t];

    /* head */
    t = 2; off[t] = b.n;
    tf_u32(&b, 0x00010000UL); tf_u32(&b, 0x00010000UL);
    tf_u32(&b, 0);             /* checkSumAdjustment */
    tf_u32(&b, 0x5F0F3CF5UL);  /* magic */
    tf_u16(&b, 0x000B);        /* baseline at y=0, lsb at x=0, integer ppem */
    tf_u16(&b, TEST_FONT_UPEM);
    for (i = 0; i < 16; i++) tf_u8(&b, 0); /* created, modified */
    tf_i16(&b, 100); tf_i16(&b, 0); tf_i16(&b, 700); tf_i16(&b, 700);
    tf_u16(&b, 0); tf_u16(&b, 8); tf_i16(&b, 2);
    tf_i16(&b, 1);             /* indexToLocFormat: long */
    tf_i16(&b, 0);
    len[t] = b.n - off[t]; tf_pad4(&b);

    /* hhea */
    t = 3; off[t] = b.n;
    tf_u32(&b, 0x00010000UL);
    tf_i16(&b, 800); tf_i16(&b, -200); tf_i16(&b, 0);
    tf_u16(&b, 800);
    tf_i16(&b, 100); tf_i16(&b, 100); tf_i16(&b, 700);
    tf_i16(&b, 1); tf_i16(&b, 0); tf_i16(&b, 0);
    for (i = 0; i < 4; i++) tf_i16(&b, 0);
    tf_i16(&b, 0); tf_u16(&b, TEST_FONT_GLYPHS);
    len[t] = b.n - off[t]; tf_pad4(&b);

    /* hmtx */
    t = 4; off[t] = b.n;
    tf_u16(&b, 500); tf_i16(&b, 0);
    tf_u16(&b, 600); tf_i16(&b, 100);
    tf_u16(&b, 800); tf_i16(&b, 100);
    len[t] = b.n - off[t]; tf_pad4(&b);

    /* loca */
    t = 5; off[t] = b.n;
    for (i = 0; i <= TEST_FONT_GLYPHS; i++) tf_u32(&b, (unsigned long)loca[i]);
    len[t] = b.n - off[t];

    /* maxp 1.0 */
    t = 6; off[t] = b.n;
    tf_u32(&b, 0x00010000UL);
    tf_u16(&b, TEST_FONT_GLYPHS);
    tf_u16(&b, 4); tf_u16(&b, 1); tf_u16(&b, 0); tf_u16(&b, 0);
    tf_u16(&b, 2);
    for (i = 0; i < 8; i++) tf_u16(&b, 0);
    len[t] = b.n - off[t]; tf_pad4(&b);

    /* name: family and subfamily, Windows Unicode, UTF-16BE */
    t = 7; off[t] = b.n;
    tf_u16(&b, 0); tf_u16(&b, 2); tf_u16(&b, 6 + 2 * 12);
    for (i = 0, k = 0; i < 2; i++) {
        size_t sl = 2 * strlen(names[i]);
        tf_u16(&b, 3); tf_u16(&b, 1); tf_u16(&b, 0x0409); tf_u16(&b, (unsigned)(i + 1));
        tf_u16(&b, (unsigned)sl); tf_u16(&b, (unsigned)k);
        k += sl;
    }
    for (i = 0; i < 2; i++)
        for (k = 0; names[i][k]; k++) tf_u16(&b, (unsigned char)names[i][k]);
    len[t] = b.n - off[t]; tf_pad4(&b);

    /* post 3.0: no glyph names */
    t = 8; off[t] = b.n;
    tf_u32(&b, 0x00030000UL); tf_u32(&b, 0);
    tf_i16(&b, -100); tf_i16(&b, 50);
    for (i = 0; i < 5; i++) tf_u32(&b, 0);
    len[t] = b.n - off[t]; tf_pad4(&b);

    if (b.n > cap) return 0;
    for (t = 0; t < NT; t++) {
        unsigned long sum = 0;
        size_t e = dir + 16 * t;
        for (i = 0; i < (len[t] + 3) / 4; i++) {
            size_t q = off[t] + 4 * i;
            sum += (unsigned long)out[q] << 24 | (unsigned long)out[q + 1] << 16 |
                   (unsigned long)out[q + 2] << 8 | out[q + 3];
        }
        b.n = e;
        for (k = 0; k < 4; k++) tf_u8(&b, (unsigned char)tags[t][k]);
        tf_u32(&b, sum & 0xffffffffUL);
        tf_u32(&b, (unsigned long)off[t]);
        tf_u32(&b, (unsigned long)len[t]);
    }
    return off[NT - 1] + ((len[NT - 1] + 3) & ~(size_t)3);
}

#endif
