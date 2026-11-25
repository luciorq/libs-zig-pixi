/* zig-brotli smoke test: BrotliEncoderCompress/BrotliDecoderDecompress
   round trip (libbrotlienc, libbrotlidec, libbrotlicommon), and the
   decoder's version against 1.2.0; prints OK. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <brotli/decode.h>
#include <brotli/encode.h>

int main(void) {
    const char *text = "zig-brotli smoke test: the quick brown fox jumps over the lazy dog, "
                       "the quick brown fox jumps over the lazy dog.";
    size_t n = strlen(text) + 1;
    uint8_t packed[512];
    uint8_t unpacked[512];
    size_t packed_len = sizeof packed;
    size_t unpacked_len = sizeof unpacked;

    /* BrotliDecoderVersion: major << 24 | minor << 12 | patch */
    uint32_t v = BrotliDecoderVersion();
    if (v != ((1u << 24) | (2u << 12) | 0u)) {
        printf("FAIL: BrotliDecoderVersion = 0x%08x (want 1.2.0)\n", (unsigned)v);
        return 1;
    }
    if (!BrotliEncoderCompress(BROTLI_MAX_QUALITY, BROTLI_DEFAULT_WINDOW, BROTLI_MODE_TEXT, n,
                               (const uint8_t *)text, &packed_len, packed)) {
        puts("FAIL: BrotliEncoderCompress");
        return 1;
    }
    if (BrotliDecoderDecompress(packed_len, packed, &unpacked_len, unpacked) !=
        BROTLI_DECODER_RESULT_SUCCESS) {
        puts("FAIL: BrotliDecoderDecompress");
        return 1;
    }
    if (unpacked_len != n || memcmp(unpacked, text, n) != 0) {
        puts("FAIL: round trip differs");
        return 1;
    }
    printf("brotli %u.%u.%u: %lu -> %lu -> %lu bytes\n", (unsigned)(v >> 24),
           (unsigned)((v >> 12) & 0xfff), (unsigned)(v & 0xfff), (unsigned long)n,
           (unsigned long)packed_len, (unsigned long)unpacked_len);
    puts("OK");
    return 0;
}
