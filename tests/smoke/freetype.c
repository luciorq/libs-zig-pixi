/* zig-freetype smoke test: library init and version; garbage bytes are
 * refused as an unknown file format; the test font (freetype.h) loads from
 * memory and its 'A' (a square) renders to an antialiased bitmap; the same
 * font, compressed with zlib's compress2, comes back through
 * FT_Gzip_Uncompress (freetype's zlib path), and compressed with libbz2,
 * opens as a face through FT_Stream_OpenBzip2 (freetype's bzip2 path). PNG
 * (sbix/CBDT bitmaps) and Brotli (WOFF2) are checked as compiled in only:
 * the installed ftoption.h must enable both. Prints OK. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <bzlib.h>
#include <zlib.h>

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_BZIP2_H
#include FT_GZIP_H

#include "freetype.h"

/* the features zig-freetype is built with (recipe, slice2 D122) */
#if !defined(FT_CONFIG_OPTION_USE_ZLIB) || !defined(FT_CONFIG_OPTION_SYSTEM_ZLIB)
#error "ftoption.h: zlib (system) not enabled"
#endif
#ifndef FT_CONFIG_OPTION_USE_BZIP2
#error "ftoption.h: bzip2 not enabled"
#endif
#ifndef FT_CONFIG_OPTION_USE_PNG
#error "ftoption.h: PNG not enabled"
#endif
#ifndef FT_CONFIG_OPTION_USE_BROTLI
#error "ftoption.h: Brotli not enabled"
#endif
#ifdef FT_CONFIG_OPTION_USE_HARFBUZZ
#error "ftoption.h: HarfBuzz enabled (zig-freetype is built without it)"
#endif

static void *mem_alloc(FT_Memory m, long size) { (void)m; return malloc((size_t)size); }
static void mem_free(FT_Memory m, void *p) { (void)m; free(p); }
static void *mem_realloc(FT_Memory m, long cur, long size, void *p) {
    (void)m; (void)cur;
    return realloc(p, (size_t)size);
}

/* 'A' at 32 px: the square spans x 100..500 and y 0..700 of 1024 units,
 * about 12.5 x 22 pixels, with full-coverage pixels inside. */
static int check_render(FT_Face face, const char *how) {
    FT_Error e = FT_Set_Pixel_Sizes(face, 0, 32);
    FT_Bitmap *bm;
    unsigned r, c, full = 0;
    if (e) { printf("FAIL: %s: FT_Set_Pixel_Sizes = %d\n", how, e); return 1; }
    e = FT_Load_Char(face, 'A', FT_LOAD_RENDER);
    if (e) { printf("FAIL: %s: FT_Load_Char('A', FT_LOAD_RENDER) = %d\n", how, e); return 1; }
    bm = &face->glyph->bitmap;
    if (bm->pixel_mode != FT_PIXEL_MODE_GRAY || bm->width < 12 || bm->width > 14 ||
        bm->rows < 21 || bm->rows > 23) {
        printf("FAIL: %s: bitmap mode %d, %u x %u (want gray, about 13 x 22)\n", how,
               bm->pixel_mode, bm->width, bm->rows);
        return 1;
    }
    for (r = 0; r < bm->rows; r++)
        for (c = 0; c < bm->width; c++)
            if (bm->buffer[r * (unsigned)abs(bm->pitch) + c] == 255) full++;
    if (full < 10 * 20) {
        printf("FAIL: %s: %u full-coverage pixels in %u x %u\n", how, full, bm->width, bm->rows);
        return 1;
    }
    /* the unhinted advance, 16.16 pixels (the hinted one is rounded) */
    if (face->glyph->linearHoriAdvance != 600L * 32 * 65536 / TEST_FONT_UPEM) {
        printf("FAIL: %s: linear advance %ld (want %ld)\n", how,
               (long)face->glyph->linearHoriAdvance, 600L * 32 * 65536 / TEST_FONT_UPEM);
        return 1;
    }
    printf("%s: 'A' %u x %u px, %u full pixels\n", how, bm->width, bm->rows, full);
    return 0;
}

int main(void) {
    static unsigned char font[2048], unpacked[2048], zpacked[4096];
    static char bzpacked[4096];
    /* 4 KiB of text lines, which every driver refuses as an unknown
     * format (tried with FreeType 2.14: a buffer under 256 bytes gives a
     * stream error, text without newlines FT_Err_Invalid_File_Format from
     * one of the drivers) */
    static unsigned char garbage[4096];
    struct FT_MemoryRec_ memrec = {NULL, mem_alloc, mem_free, mem_realloc};
    FT_StreamRec src, bz;
    FT_Open_Args args;
    FT_Library lib;
    FT_Face face;
    FT_Int major, minor, patch;
    FT_ULong unpacked_len = sizeof unpacked;
    uLongf zpacked_len = sizeof zpacked;
    unsigned int bzpacked_len = sizeof bzpacked;
    size_t n;
    FT_Error e;

    if ((e = FT_Init_FreeType(&lib)) != 0) { printf("FAIL: FT_Init_FreeType = %d\n", e); return 1; }
    FT_Library_Version(lib, &major, &minor, &patch);
    printf("FreeType %d.%d.%d (headers %d.%d.%d)\n", major, minor, patch, FREETYPE_MAJOR,
           FREETYPE_MINOR, FREETYPE_PATCH);
    if (major != FREETYPE_MAJOR || minor != FREETYPE_MINOR || patch != FREETYPE_PATCH) {
        puts("FAIL: library and header versions differ");
        return 1;
    }

    for (n = 0; n < sizeof garbage; n++) garbage[n] = (unsigned char)"This is not a font.\n"[n % 20];
    e = FT_New_Memory_Face(lib, garbage, sizeof garbage, 0, &face);
    if (e != FT_Err_Unknown_File_Format) {
        printf("FAIL: FT_New_Memory_Face(garbage) = %d (want FT_Err_Unknown_File_Format %d)\n", e,
               FT_Err_Unknown_File_Format);
        return 1;
    }

    n = test_font(font, sizeof font);
    if (n == 0) { puts("FAIL: test font does not fit"); return 1; }
    if ((e = FT_New_Memory_Face(lib, font, (FT_Long)n, 0, &face)) != 0) {
        printf("FAIL: FT_New_Memory_Face(test font, %u bytes) = %d\n", (unsigned)n, e);
        return 1;
    }
    if (face->num_glyphs != TEST_FONT_GLYPHS || face->units_per_EM != TEST_FONT_UPEM ||
        !FT_IS_SFNT(face) || !FT_IS_SCALABLE(face) || FT_Get_Char_Index(face, 'B') != 2 ||
        face->family_name == NULL || strcmp(face->family_name, "Smoke") != 0) {
        printf("FAIL: test font face: %ld glyphs, %d upem, family %s\n", (long)face->num_glyphs,
               face->units_per_EM, face->family_name ? face->family_name : "(null)");
        return 1;
    }
    if (check_render(face, "memory")) return 1;
    FT_Done_Face(face);

    /* zlib */
    if (compress2(zpacked, &zpacked_len, font, (uLong)n, Z_BEST_COMPRESSION) != Z_OK) {
        puts("FAIL: compress2");
        return 1;
    }
    e = FT_Gzip_Uncompress(&memrec, unpacked, &unpacked_len, zpacked, (FT_ULong)zpacked_len);
    if (e || unpacked_len != n || memcmp(unpacked, font, n) != 0) {
        printf("FAIL: FT_Gzip_Uncompress = %d, %lu bytes (want %u, same as the font)\n", e,
               (unsigned long)unpacked_len, (unsigned)n);
        return 1;
    }

    /* bzip2: a face read through freetype's bzip2 stream */
    if (BZ2_bzBuffToBuffCompress(bzpacked, &bzpacked_len, (char *)font, (unsigned)n, 9, 0, 0) != BZ_OK) {
        puts("FAIL: BZ2_bzBuffToBuffCompress");
        return 1;
    }
    memset(&src, 0, sizeof src);
    memset(&bz, 0, sizeof bz);
    src.base = (unsigned char *)bzpacked;
    src.size = bzpacked_len;
    src.memory = &memrec;
    if ((e = FT_Stream_OpenBzip2(&bz, &src)) != 0) {
        printf("FAIL: FT_Stream_OpenBzip2 = %d\n", e);
        return 1;
    }
    memset(&args, 0, sizeof args);
    args.flags = FT_OPEN_STREAM;
    args.stream = &bz;
    if ((e = FT_Open_Face(lib, &args, 0, &face)) != 0) {
        printf("FAIL: FT_Open_Face(bzip2 stream) = %d\n", e);
        return 1;
    }
    if (check_render(face, "bzip2 stream")) return 1;
    FT_Done_Face(face);

    printf("zlib: %u -> %lu -> %lu bytes; bzip2: %u -> %u bytes\n", (unsigned)n,
           (unsigned long)zpacked_len, (unsigned long)unpacked_len, (unsigned)n, bzpacked_len);
    FT_Done_FreeType(lib);
    puts("OK");
    return 0;
}
