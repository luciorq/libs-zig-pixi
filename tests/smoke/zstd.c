/* zig-zstd smoke test: ZSTD_compress/ZSTD_decompress round trip, the
   frame's content size, and the header against the library version;
   prints OK. */
#include <stdio.h>
#include <string.h>
#include <zstd.h>

int main(void) {
    char text[4096];
    char packed[4096];
    char unpacked[4096];
    size_t n = 0;
    while (n + 64 < sizeof text)
        n += (size_t)sprintf(text + n, "zig-zstd smoke test line %4u: the quick brown fox.\n", (unsigned)n);

    size_t packed_len = ZSTD_compress(packed, sizeof packed, text, n, 19);
    if (ZSTD_isError(packed_len)) {
        printf("FAIL: ZSTD_compress: %s\n", ZSTD_getErrorName(packed_len));
        return 1;
    }
    unsigned long long size = ZSTD_getFrameContentSize(packed, packed_len);
    if (size != n) {
        printf("FAIL: frame content size %llu (want %lu)\n", size, (unsigned long)n);
        return 1;
    }
    size_t unpacked_len = ZSTD_decompress(unpacked, sizeof unpacked, packed, packed_len);
    if (ZSTD_isError(unpacked_len)) {
        printf("FAIL: ZSTD_decompress: %s\n", ZSTD_getErrorName(unpacked_len));
        return 1;
    }
    if (unpacked_len != n || memcmp(unpacked, text, n) != 0) {
        puts("FAIL: round trip differs");
        return 1;
    }
    if (ZSTD_versionNumber() != ZSTD_VERSION_NUMBER || strcmp(ZSTD_versionString(), ZSTD_VERSION_STRING) != 0) {
        printf("FAIL: library %s (%u), header %s (%u)\n", ZSTD_versionString(), ZSTD_versionNumber(),
               ZSTD_VERSION_STRING, (unsigned)ZSTD_VERSION_NUMBER);
        return 1;
    }
    printf("zstd %s: %lu -> %lu -> %lu bytes\n", ZSTD_versionString(), (unsigned long)n,
           (unsigned long)packed_len, (unsigned long)unpacked_len);
    puts("OK");
    return 0;
}
