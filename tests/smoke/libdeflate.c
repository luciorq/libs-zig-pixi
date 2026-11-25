/* zig-libdeflate smoke test: raw DEFLATE, zlib and gzip compress and
   decompress round trips, CRC-32 and Adler-32 of "123456789" (the
   standard check values), and the header's version macros against each
   other (libdeflate has no runtime version call); prints OK. */
#include <stdio.h>
#include <string.h>
#include <libdeflate.h>

typedef size_t (*compress_fn)(struct libdeflate_compressor *, const void *, size_t, void *, size_t);
typedef enum libdeflate_result (*decompress_fn)(struct libdeflate_decompressor *, const void *, size_t,
                                                void *, size_t, size_t *);

static char text[4096];
static size_t n;

static int round_trip(const char *name, struct libdeflate_compressor *c, struct libdeflate_decompressor *d,
                      compress_fn compress, decompress_fn decompress, size_t *packed_len) {
    char packed[4096];
    char unpacked[4096];
    size_t unpacked_len = 0;
    *packed_len = compress(c, text, n, packed, sizeof packed);
    if (*packed_len == 0) {
        printf("FAIL: %s compress\n", name);
        return 1;
    }
    enum libdeflate_result r = decompress(d, packed, *packed_len, unpacked, sizeof unpacked, &unpacked_len);
    if (r != LIBDEFLATE_SUCCESS) {
        printf("FAIL: %s decompress returned %d\n", name, (int)r);
        return 1;
    }
    if (unpacked_len != n || memcmp(unpacked, text, n) != 0) {
        printf("FAIL: %s round trip differs\n", name);
        return 1;
    }
    return 0;
}

int main(void) {
    while (n + 64 < sizeof text)
        n += (size_t)sprintf(text + n, "zig-libdeflate smoke test line %4u: the quick brown fox.\n", (unsigned)n);

    struct libdeflate_compressor *c = libdeflate_alloc_compressor(12);
    struct libdeflate_decompressor *d = libdeflate_alloc_decompressor();
    if (c == NULL || d == NULL) {
        puts("FAIL: alloc");
        return 1;
    }
    size_t raw_len, zlib_len, gzip_len;
    if (round_trip("deflate", c, d, libdeflate_deflate_compress, libdeflate_deflate_decompress, &raw_len) ||
        round_trip("zlib", c, d, libdeflate_zlib_compress, libdeflate_zlib_decompress, &zlib_len) ||
        round_trip("gzip", c, d, libdeflate_gzip_compress, libdeflate_gzip_decompress, &gzip_len))
        return 1;
    libdeflate_free_compressor(c);
    libdeflate_free_decompressor(d);

    const char *check = "123456789";
    uint32_t crc = libdeflate_crc32(0, check, strlen(check));
    uint32_t adler = libdeflate_adler32(1, check, strlen(check));
    if (crc != 0xCBF43926u || adler != 0x091E01DEu) {
        printf("FAIL: crc32 %08x (want cbf43926), adler32 %08x (want 091e01de)\n", (unsigned)crc,
               (unsigned)adler);
        return 1;
    }

    char v[32];
    snprintf(v, sizeof v, "%d.%d", LIBDEFLATE_VERSION_MAJOR, LIBDEFLATE_VERSION_MINOR);
    if (strcmp(v, LIBDEFLATE_VERSION_STRING) != 0) {
        printf("FAIL: version macros %s, string %s\n", v, LIBDEFLATE_VERSION_STRING);
        return 1;
    }
    printf("libdeflate %s: %lu -> deflate %lu, zlib %lu, gzip %lu bytes; crc32 %08x adler32 %08x\n",
           LIBDEFLATE_VERSION_STRING, (unsigned long)n, (unsigned long)raw_len, (unsigned long)zlib_len,
           (unsigned long)gzip_len, (unsigned)crc, (unsigned)adler);
    puts("OK");
    return 0;
}
