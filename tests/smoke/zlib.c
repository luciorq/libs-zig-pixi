/* zig-zlib smoke test: compress/uncompress round trip, prints OK. */
#include <stdio.h>
#include <string.h>
#include <zlib.h>

int main(void) {
    const char *text = "zig-zlib smoke test: the quick brown fox jumps over the lazy dog, "
                       "the quick brown fox jumps over the lazy dog.";
    uLong n = (uLong)strlen(text) + 1;
    Bytef packed[512];
    Bytef unpacked[512];
    uLongf packed_len = sizeof packed;
    uLongf unpacked_len = sizeof unpacked;

    if (compress2(packed, &packed_len, (const Bytef *)text, n, Z_BEST_COMPRESSION) != Z_OK) {
        puts("FAIL: compress2");
        return 1;
    }
    if (uncompress(unpacked, &unpacked_len, packed, packed_len) != Z_OK) {
        puts("FAIL: uncompress");
        return 1;
    }
    if (unpacked_len != n || memcmp(unpacked, text, n) != 0) {
        puts("FAIL: round trip differs");
        return 1;
    }
    printf("zlib %s: %lu -> %lu -> %lu bytes\n", zlibVersion(), (unsigned long)n,
           (unsigned long)packed_len, (unsigned long)unpacked_len);
    puts("OK");
    return 0;
}
