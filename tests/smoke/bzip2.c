/* zig-bzip2 smoke test: BZ2_bzBuffToBuffCompress/Decompress round trip,
   and the library version against 1.0.8; prints OK. */
#include <stdio.h>
#include <string.h>
#include <bzlib.h>

int main(void) {
    const char *text = "zig-bzip2 smoke test: the quick brown fox jumps over the lazy dog, "
                       "the quick brown fox jumps over the lazy dog.";
    unsigned int n = (unsigned int)strlen(text) + 1;
    char packed[512];
    char unpacked[512];
    unsigned int packed_len = sizeof packed;
    unsigned int unpacked_len = sizeof unpacked;

    /* "1.0.8, 13-Jul-2019" */
    const char *v = BZ2_bzlibVersion();
    if (v == NULL || strncmp(v, "1.0.8", 5) != 0) {
        printf("FAIL: BZ2_bzlibVersion = %s (want 1.0.8)\n", v ? v : "(null)");
        return 1;
    }
    int rc = BZ2_bzBuffToBuffCompress(packed, &packed_len, (char *)text, n, 9, 0, 0);
    if (rc != BZ_OK) {
        printf("FAIL: BZ2_bzBuffToBuffCompress = %d\n", rc);
        return 1;
    }
    rc = BZ2_bzBuffToBuffDecompress(unpacked, &unpacked_len, packed, packed_len, 0, 0);
    if (rc != BZ_OK) {
        printf("FAIL: BZ2_bzBuffToBuffDecompress = %d\n", rc);
        return 1;
    }
    if (unpacked_len != n || memcmp(unpacked, text, n) != 0) {
        puts("FAIL: round trip differs");
        return 1;
    }
    printf("bzip2 %s: %u -> %u -> %u bytes\n", v, n, packed_len, unpacked_len);
    puts("OK");
    return 0;
}
