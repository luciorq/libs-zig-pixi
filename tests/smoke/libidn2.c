/* zig-libidn2 smoke test: IDNA2008 with UTS#46 mapping to ASCII and back
   ("bücher.example" <-> "xn--bcher-kva.example"), upper case mapped by
   TR46, a disallowed code point rejected; prints OK. Offline. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <idn2.h>

int main(void) {
    int bad = 0;
    printf("libidn2 %s\n", idn2_check_version(NULL));
    char *out = NULL;
    /* "bücher.example" in UTF-8 */
    int rc = idn2_to_ascii_8z("b\xc3\xbc" "cher.example", &out, IDN2_NONTRANSITIONAL);
    if (rc != IDN2_OK || strcmp(out, "xn--bcher-kva.example") != 0) {
        printf("FAIL: to_ascii: %s (%s)\n", out ? out : "(null)", idn2_strerror(rc));
        bad++;
    } else printf("to_ascii: %s\n", out);
    idn2_free(out);

    out = NULL;
    rc = idn2_to_unicode_8z8z("xn--bcher-kva.example", &out, 0);
    if (rc != IDN2_OK || strcmp(out, "b\xc3\xbc" "cher.example") != 0) {
        printf("FAIL: to_unicode (%s)\n", idn2_strerror(rc));
        bad++;
    } else printf("to_unicode: %lu bytes\n", (unsigned long)strlen(out));
    idn2_free(out);

    /* TR46 maps "BÜCHER" (upper case) to the same label */
    out = NULL;
    rc = idn2_to_ascii_8z("B\xc3\x9c" "CHER.example", &out, IDN2_NONTRANSITIONAL);
    if (rc != IDN2_OK || strcmp(out, "xn--bcher-kva.example") != 0) {
        printf("FAIL: TR46 mapping: %s (%s)\n", out ? out : "(null)", idn2_strerror(rc));
        bad++;
    } else printf("TR46 mapping: %s\n", out);
    idn2_free(out);

    /* U+2615 (hot beverage) is fine, U+0640 alone (Arabic tatweel) is not
       valid IDNA2008 as a label: disallowed / contextual */
    out = NULL;
    rc = idn2_lookup_u8((const uint8_t *)"\xd9\x80.example", (uint8_t **)&out, IDN2_NONTRANSITIONAL);
    if (rc == IDN2_OK) {
        printf("FAIL: U+0640 label accepted: %s\n", out);
        bad++;
    } else printf("U+0640 label rejected: %s\n", idn2_strerror_name(rc));
    idn2_free(out);

    if (bad) return 1;
    printf("OK\n");
    return 0;
}
