/* zig-gmp smoke test: 30! and a Mersenne prime with the C API, prints OK. */
#include <stdio.h>
#include <string.h>
#include <gmp.h>

int main(void) {
    const char *want = "265252859812191058636308480000000";
    mpz_t f, m;
    mpz_init(f);
    mpz_init(m);
    mpz_fac_ui(f, 30);
    char *got = mpz_get_str(NULL, 10, f);
    if (strcmp(got, want) != 0) {
        printf("FAIL: 30! = %s (want %s)\n", got, want);
        return 1;
    }
    /* 2^127 - 1 is prime, 2^127 + 1 is not */
    mpz_ui_pow_ui(m, 2, 127);
    mpz_sub_ui(m, m, 1);
    int p = mpz_probab_prime_p(m, 25);
    mpz_add_ui(m, m, 2);
    int q = mpz_probab_prime_p(m, 25);
    if (p == 0 || q != 0) {
        printf("FAIL: primality of 2^127-1 %d (want >0), of 2^127+1 %d (want 0)\n", p, q);
        return 1;
    }
    printf("gmp %s: 30! = %s\n", gmp_version, got);
    mpz_clear(f);
    mpz_clear(m);
    puts("OK");
    return 0;
}
