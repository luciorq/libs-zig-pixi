/* zig-xz smoke test: lzma_easy_buffer_encode/lzma_stream_buffer_decode
   round trip of an .xz stream (CRC64 check), and the header against the
   library version; prints OK. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <lzma.h>

int main(void) {
    char text[4096];
    uint8_t packed[4096];
    uint8_t unpacked[4096];
    size_t n = 0;
    while (n + 64 < sizeof text)
        n += (size_t)sprintf(text + n, "zig-xz smoke test line %4u: the quick brown fox.\n", (unsigned)n);

    size_t packed_len = 0;
    lzma_ret r = lzma_easy_buffer_encode(6 | LZMA_PRESET_EXTREME, LZMA_CHECK_CRC64, NULL,
                                         (const uint8_t *)text, n, packed, &packed_len, sizeof packed);
    if (r != LZMA_OK) {
        printf("FAIL: lzma_easy_buffer_encode returned %d\n", (int)r);
        return 1;
    }
    uint64_t memlimit = UINT64_MAX;
    size_t in_pos = 0, unpacked_len = 0;
    r = lzma_stream_buffer_decode(&memlimit, 0, NULL, packed, &in_pos, packed_len, unpacked,
                                  &unpacked_len, sizeof unpacked);
    if (r != LZMA_OK || in_pos != packed_len) {
        printf("FAIL: lzma_stream_buffer_decode returned %d (read %lu of %lu)\n", (int)r,
               (unsigned long)in_pos, (unsigned long)packed_len);
        return 1;
    }
    if (unpacked_len != n || memcmp(unpacked, text, n) != 0) {
        puts("FAIL: round trip differs");
        return 1;
    }
    if (lzma_version_number() != LZMA_VERSION || strcmp(lzma_version_string(), LZMA_VERSION_STRING) != 0) {
        printf("FAIL: library %s (%lu), header %s (%lu)\n", lzma_version_string(),
               (unsigned long)lzma_version_number(), LZMA_VERSION_STRING, (unsigned long)LZMA_VERSION);
        return 1;
    }
    printf("liblzma %s: %lu -> %lu -> %lu bytes\n", lzma_version_string(), (unsigned long)n,
           (unsigned long)packed_len, (unsigned long)unpacked_len);
    puts("OK");
    return 0;
}
