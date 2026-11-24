/* zig-mpfr smoke test: pi to 200 bits, the thread-safe build option, and
   the header against the library version; prints OK. */
#include <stdio.h>
#include <string.h>
#include <mpfr.h>

int main(void) {
    /* pi = 3.14159265358979323846264338327950288419716939937510 58209...,
       so correctly rounded to 50 decimals the last digit is 1 */
    const char *want = "3.14159265358979323846264338327950288419716939937511";
    char got[64];
    mpfr_t pi;
    mpfr_init2(pi, 200);
    mpfr_const_pi(pi, MPFR_RNDN);
    mpfr_snprintf(got, sizeof got, "%.50Rf", pi);
    if (strcmp(got, want) != 0) {
        printf("FAIL: pi = %s (want %s)\n", got, want);
        return 1;
    }
    /* configure cannot run its TLS test when cross-compiling; the recipe
       passes --enable-thread-safe, so this must be 1 */
    if (!mpfr_buildopt_tls_p()) {
        puts("FAIL: mpfr_buildopt_tls_p() is 0 (not thread-safe)");
        return 1;
    }
    if (strcmp(mpfr_get_version(), MPFR_VERSION_STRING) != 0) {
        printf("FAIL: library %s, header %s\n", mpfr_get_version(), MPFR_VERSION_STRING);
        return 1;
    }
    printf("mpfr %s (gmp %s): pi = %s\n", mpfr_get_version(), gmp_version, got);
    mpfr_clear(pi);
    mpfr_free_cache();
    puts("OK");
    return 0;
}
