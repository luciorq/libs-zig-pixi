/* zig-libgnurx smoke test: regcomp/regexec with REG_EXTENDED and
   submatch offsets, REG_ICASE, a REG_NOMATCH case and regerror's text
   for a bad pattern (what htslib's hts_expr.c uses); prints OK. */
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <regex.h>

int main(void) {
    regex_t re;
    regmatch_t m[3];
    int rc = regcomp(&re, "([a-z]+)-([0-9]+)", REG_EXTENDED);
    if (rc != 0) { printf("FAIL: regcomp %d\n", rc); return 1; }
    const char *s = "read chr-17 at 42";
    rc = regexec(&re, s, 3, m, 0);
    if (rc != 0 || m[0].rm_so != 5 || m[0].rm_eo != 11 || m[1].rm_so != 5
        || m[1].rm_eo != 8 || m[2].rm_so != 9 || m[2].rm_eo != 11) {
        printf("FAIL: regexec %d, offsets %d-%d %d-%d %d-%d\n", rc, (int)m[0].rm_so,
               (int)m[0].rm_eo, (int)m[1].rm_so, (int)m[1].rm_eo, (int)m[2].rm_so, (int)m[2].rm_eo);
        return 1;
    }
    printf("submatches: '%.*s' '%.*s'\n", (int)(m[1].rm_eo - m[1].rm_so), s + m[1].rm_so,
           (int)(m[2].rm_eo - m[2].rm_so), s + m[2].rm_so);
    if (regexec(&re, "no digits here", 0, NULL, 0) != REG_NOMATCH) {
        printf("FAIL: expected REG_NOMATCH\n");
        return 1;
    }
    regfree(&re);

    if (regcomp(&re, "^SAMPLE_[0-9]+$", REG_EXTENDED | REG_ICASE | REG_NOSUB) != 0
        || regexec(&re, "sample_007", 0, NULL, 0) != 0) {
        printf("FAIL: REG_ICASE\n");
        return 1;
    }
    regfree(&re);

    rc = regcomp(&re, "a(b", REG_EXTENDED);
    char err[128];
    regerror(rc, &re, err, sizeof err);
    if (rc != REG_EPAREN || strlen(err) == 0) {
        printf("FAIL: regcomp(\"a(b\") %d '%s'\n", rc, err);
        return 1;
    }
    printf("regerror: %s\n", err);
    printf("OK\n");
    return 0;
}
