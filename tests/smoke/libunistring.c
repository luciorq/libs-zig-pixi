/* zig-libunistring smoke test: UTF-8 validation, case folding, NFC/NFD
   normalization and the iconv bridge (ISO-8859-1 to UTF-8), each checked
   byte for byte; prints OK. Offline, no locale needed. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistr.h>
#include <unicase.h>
#include <uninorm.h>
#include <uniconv.h>
#include <unistring/version.h>

static int same(const char *what, const uint8_t *got, size_t n, const char *want) {
    if (got == NULL || n != strlen(want) || memcmp(got, want, n) != 0) {
        printf("FAIL: %s (%lu bytes)\n", what, (unsigned long)n);
        return 1;
    }
    printf("%s: %lu bytes\n", what, (unsigned long)n);
    return 0;
}

int main(void) {
    int bad = 0;
    /* _libunistring_version: major << 16 | minor << 8 | subminor */
    printf("libunistring %d.%d.%d\n", _libunistring_version >> 16, (_libunistring_version >> 8) & 0xff,
           _libunistring_version & 0xff);
    /* "Straße Ÿ" in UTF-8; an overlong sequence is invalid */
    const uint8_t s[] = "Stra\xc3\x9f" "e \xc5\xb8";
    if (u8_check(s, sizeof s - 1) != NULL) { printf("FAIL: u8_check valid\n"); bad++; }
    const uint8_t overlong[] = "\xc0\xaf";
    if (u8_check(overlong, 2) == NULL) { printf("FAIL: u8_check overlong\n"); bad++; }

    size_t n = 0;
    uint8_t *f = u8_casefold(s, sizeof s - 1, NULL, NULL, NULL, &n);
    /* ß folds to "ss", Ÿ (U+0178) to ÿ (U+00FF) */
    bad += same("casefold", f, n, "strasse \xc3\xbf");
    free(f);

    n = 0;
    uint8_t *up = u8_toupper(s, sizeof s - 1, "", NULL, NULL, &n);
    bad += same("toupper", up, n, "STRASSE \xc5\xb8");
    free(up);

    /* é precomposed (U+00E9) <-> e + U+0301 */
    const uint8_t nfc[] = "caf\xc3\xa9";
    n = 0;
    uint8_t *d = u8_normalize(UNINORM_NFD, nfc, sizeof nfc - 1, NULL, &n);
    bad += same("NFD", d, n, "cafe\xcc\x81");
    size_t m = 0;
    uint8_t *c = u8_normalize(UNINORM_NFC, d, n, NULL, &m);
    bad += same("NFC", c, m, "caf\xc3\xa9");
    free(d);
    free(c);

    /* the iconv bridge: "café" in ISO-8859-1 */
    const char latin1[] = "caf\xe9";
    n = 0;
    uint8_t *u = u8_conv_from_encoding("ISO-8859-1", iconveh_error, latin1, 4, NULL, NULL, &n);
    bad += same("ISO-8859-1 -> UTF-8", u, n, "caf\xc3\xa9");
    free(u);

    if (bad) return 1;
    printf("OK\n");
    return 0;
}
