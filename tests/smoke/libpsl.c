/* zig-libpsl smoke test: the built-in Public Suffix List (psl_builtin):
   public suffixes, registrable domains, a private-section suffix, and an
   IDN suffix in Unicode and in punycode (psl_str_to_utf8lower lowercases
   through libunistring; the built-in context needs no IDNA conversion, so
   libidn2's own code is exercised by tests/smoke/libidn2.c); prints OK.
   Offline. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libpsl.h>

static int expect_suffix(const psl_ctx_t *psl, const char *d, int want) {
    int got = psl_is_public_suffix(psl, d);
    printf("is_public_suffix(%s) = %d\n", d, got);
    if (got != want) { printf("FAIL: want %d\n", want); return 1; }
    return 0;
}

static int expect_reg(const psl_ctx_t *psl, const char *d, const char *want) {
    const char *got = psl_registrable_domain(psl, d);
    printf("registrable_domain(%s) = %s\n", d, got ? got : "(null)");
    if (got == NULL || strcmp(got, want) != 0) { printf("FAIL: want %s\n", want); return 1; }
    return 0;
}

int main(void) {
    int bad = 0;
    const psl_ctx_t *psl = psl_builtin();
    printf("libpsl %s, built-in list: %d rules\n", psl_get_version(), psl ? psl_suffix_count(psl) : -1);
    if (psl == NULL) { printf("FAIL: no built-in list\n"); return 1; }
    if (psl_suffix_count(psl) < 1000) { printf("FAIL: few rules\n"); bad++; }
    bad += expect_suffix(psl, "co.uk", 1);
    bad += expect_suffix(psl, "bbc.co.uk", 0);
    bad += expect_suffix(psl, "com", 1);
    bad += expect_suffix(psl, "github.io", 1); /* private section */
    bad += expect_reg(psl, "www.bbc.co.uk", "bbc.co.uk");
    bad += expect_reg(psl, "a.b.example.com", "example.com");
    /* 公司.cn (an IDN suffix), in UTF-8 and as punycode */
    bad += expect_suffix(psl, "\xe5\x85\xac\xe5\x8f\xb8.cn", 1);
    bad += expect_suffix(psl, "xn--55qx5d.cn", 1);
    /* upper-case UTF-8 to lower case through libidn2/libunistring */
    char *lower = NULL;
    psl_error_t e = psl_str_to_utf8lower("WWW.B\xc3\x9c" "CHER.DE", "utf-8", NULL, &lower);
    if (e != PSL_SUCCESS || lower == NULL || strcmp(lower, "www.b\xc3\xbc" "cher.de") != 0) {
        printf("FAIL: str_to_utf8lower %d\n", (int)e);
        bad++;
    } else printf("str_to_utf8lower: %s\n", "www.b\\xc3\\xbccher.de");
    psl_free_string(lower);
    if (bad) return 1;
    printf("OK\n");
    return 0;
}
