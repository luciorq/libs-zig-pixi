/* zig-harfbuzz smoke test, in C: HarfBuzz is C++ built without exceptions,
 * RTTI and the C++ runtime (its meson build links it as C), so linking
 * this C program with `zig cc` and no libc++ shows libharfbuzz.a needs
 * none. Checks: hb_version_string against HB_VERSION_STRING; script and
 * direction guessing for Latin and Arabic text; the test font
 * (freetype.h) as a blob and face, "ABA" shaped with HarfBuzz's own font
 * functions (glyphs 1 2 1, advances 600 800 600 font units); the same
 * font through FreeType (hb_ft_font_create_referenced, freetype's
 * integration) gives the same glyphs and advances. Prints OK. */
#include <stdio.h>
#include <string.h>

#include <hb.h>
#include <hb-ft.h>

#include "freetype.h"

static const unsigned want_gid[3] = {1, 2, 1};
static const int want_adv[3] = {600, 800, 600};

/* Shapes "ABA" with font; the advances must be want_adv * mult. */
static int check_shape(hb_font_t *font, int mult, const char *how) {
    hb_buffer_t *buf = hb_buffer_create();
    hb_glyph_info_t *info;
    hb_glyph_position_t *pos;
    unsigned i, len;
    int bad = 0;
    hb_buffer_add_utf8(buf, "ABA", -1, 0, -1);
    hb_buffer_guess_segment_properties(buf);
    hb_shape(font, buf, NULL, 0);
    info = hb_buffer_get_glyph_infos(buf, &len);
    pos = hb_buffer_get_glyph_positions(buf, NULL);
    if (len != 3) {
        printf("FAIL: %s: %u glyphs for \"ABA\" (want 3)\n", how, len);
        bad = 1;
    }
    for (i = 0; !bad && i < len; i++) {
        if (info[i].codepoint != want_gid[i] || pos[i].x_advance != want_adv[i] * mult ||
            pos[i].y_advance != 0) {
            printf("FAIL: %s: glyph %u: id %u, advance %d (want id %u, advance %d)\n", how, i,
                   info[i].codepoint, pos[i].x_advance, want_gid[i], want_adv[i] * mult);
            bad = 1;
        }
    }
    if (!bad)
        printf("%s: \"ABA\" -> glyphs %u %u %u, advances %d %d %d\n", how, info[0].codepoint,
               info[1].codepoint, info[2].codepoint, pos[0].x_advance, pos[1].x_advance,
               pos[2].x_advance);
    hb_buffer_destroy(buf);
    return bad;
}

int main(void) {
    static unsigned char font[2048];
    hb_buffer_t *buf;
    hb_blob_t *blob;
    hb_face_t *face;
    hb_font_t *font_ot, *font_ft;
    FT_Library lib;
    FT_Face ft_face;
    FT_Error e;
    size_t n;

    printf("HarfBuzz %s (headers %s)\n", hb_version_string(), HB_VERSION_STRING);
    if (strcmp(hb_version_string(), HB_VERSION_STRING) != 0 ||
        !hb_version_atleast(HB_VERSION_MAJOR, HB_VERSION_MINOR, HB_VERSION_MICRO)) {
        puts("FAIL: library and header versions differ");
        return 1;
    }

    /* segment properties: HarfBuzz's own Unicode data (no ICU, no GLib) */
    buf = hb_buffer_create();
    hb_buffer_add_utf8(buf, "Hello", -1, 0, -1);
    hb_buffer_guess_segment_properties(buf);
    if (hb_buffer_get_script(buf) != HB_SCRIPT_LATIN ||
        hb_buffer_get_direction(buf) != HB_DIRECTION_LTR) {
        puts("FAIL: \"Hello\" is not Latin, left to right");
        return 1;
    }
    hb_buffer_reset(buf);
    hb_buffer_add_utf8(buf, "\xd8\xb3\xd9\x84\xd8\xa7\xd9\x85", -1, 0, -1); /* salam */
    hb_buffer_guess_segment_properties(buf);
    if (hb_buffer_get_script(buf) != HB_SCRIPT_ARABIC ||
        hb_buffer_get_direction(buf) != HB_DIRECTION_RTL || hb_buffer_get_length(buf) != 4) {
        puts("FAIL: Arabic text is not Arabic, right to left, 4 code points");
        return 1;
    }
    hb_buffer_destroy(buf);

    n = test_font(font, sizeof font);
    if (n == 0) { puts("FAIL: test font does not fit"); return 1; }
    blob = hb_blob_create((const char *)font, (unsigned)n, HB_MEMORY_MODE_READONLY, NULL, NULL);
    face = hb_face_create(blob, 0);
    if (hb_face_get_glyph_count(face) != TEST_FONT_GLYPHS ||
        hb_face_get_upem(face) != TEST_FONT_UPEM) {
        printf("FAIL: face: %u glyphs, %u upem\n", hb_face_get_glyph_count(face),
               hb_face_get_upem(face));
        return 1;
    }
    font_ot = hb_font_create(face); /* scale: font units */
    if (check_shape(font_ot, 1, "hb-ot")) return 1;
    hb_font_destroy(font_ot);
    hb_face_destroy(face);
    hb_blob_destroy(blob);

    /* FreeType integration: at 1024 ppem (one pixel per font unit) hb-ft's
     * advances are font units in 26.6 */
    if ((e = FT_Init_FreeType(&lib)) != 0) { printf("FAIL: FT_Init_FreeType = %d\n", e); return 1; }
    if ((e = FT_New_Memory_Face(lib, font, (FT_Long)n, 0, &ft_face)) != 0) {
        printf("FAIL: FT_New_Memory_Face = %d\n", e);
        return 1;
    }
    if ((e = FT_Set_Pixel_Sizes(ft_face, 0, TEST_FONT_UPEM)) != 0) {
        printf("FAIL: FT_Set_Pixel_Sizes = %d\n", e);
        return 1;
    }
    font_ft = hb_ft_font_create_referenced(ft_face);
    if (hb_ft_font_get_ft_face(font_ft) != ft_face) { puts("FAIL: hb_ft_font_get_ft_face"); return 1; }
    if (check_shape(font_ft, 64, "hb-ft")) return 1;
    hb_font_destroy(font_ft);
    FT_Done_Face(ft_face);
    FT_Done_FreeType(lib);

    puts("OK");
    return 0;
}
