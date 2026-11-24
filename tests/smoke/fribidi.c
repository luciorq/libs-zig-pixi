/* zig-fribidi smoke test: mixed Hebrew/Latin UTF-8 text reordered to
 * visual order (fribidi_charset_to_unicode, fribidi_log2vis), with a left-
 * to-right and a right-to-left paragraph; the library version. Prints OK. */
#include <stdio.h>
#include <string.h>
#include <fribidi.h>

static int failures = 0;

/* logical UTF-8 in, visual UTF-8 compared with want, the resolved
 * paragraph direction with want_dir */
static void reorder(const char *logical, const char *want, FriBidiParType want_dir,
                    const char *what) {
    FriBidiChar in[64], out[64];
    char visual[256];
    FriBidiParType dir = FRIBIDI_PAR_ON;
    FriBidiStrIndex n = fribidi_charset_to_unicode(FRIBIDI_CHAR_SET_UTF8, logical,
                                                   (FriBidiStrIndex)strlen(logical), in);
    FriBidiLevel max = fribidi_log2vis(in, n, &dir, out, NULL, NULL, NULL);
    fribidi_unicode_to_charset(FRIBIDI_CHAR_SET_UTF8, out, n, visual);
    if (max == 0 || strcmp(visual, want) != 0 || dir != want_dir) {
        printf("FAIL: %s: visual '%s' (want '%s'), direction %s\n", what, visual, want,
               dir == FRIBIDI_PAR_RTL ? "RTL" : "LTR");
        failures++;
    }
}

int main(void) {
    /* alef bet gimel: U+05D0..U+05D2 */
    reorder("abc \xD7\x90\xD7\x91\xD7\x92 def", "abc \xD7\x92\xD7\x91\xD7\x90 def",
            FRIBIDI_PAR_LTR, "LTR paragraph");
    reorder("\xD7\x90\xD7\x91\xD7\x92 abc", "abc \xD7\x92\xD7\x91\xD7\x90",
            FRIBIDI_PAR_RTL, "RTL paragraph");
    if (strstr(fribidi_version_info, "1.0.16") == NULL) {
        printf("FAIL: fribidi_version_info does not name 1.0.16\n");
        failures++;
    }
    printf("fribidi %s (Unicode %s): LTR and RTL paragraphs reordered\n",
           FRIBIDI_VERSION, fribidi_unicode_version);
    if (failures) return 1;
    puts("OK");
    return 0;
}
