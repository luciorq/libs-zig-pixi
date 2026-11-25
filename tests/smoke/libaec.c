/* zig-libaec smoke test: 16-bit samples compressed and decompressed in
   memory through the szip API (SZ_BufftoBuffCompress/Decompress, szlib.h)
   and through libaec's own (aec_buffer_encode/decode), each compared with
   the input; the szip encoder must be there (SZ_encoder_enabled); prints
   OK. */
#include <stdio.h>
#include <string.h>
#include <szlib.h>
#include <libaec.h>

#define N 4096

static unsigned short data[N];
static unsigned char packed[4 * N];
static unsigned short unpacked[N];

static int szip_round_trip(void) {
    SZ_com_t p;
    p.options_mask = SZ_ALLOW_K13_OPTION_MASK | SZ_NN_OPTION_MASK | SZ_LSB_OPTION_MASK;
    p.bits_per_pixel = 16;
    p.pixels_per_block = 16;
    p.pixels_per_scanline = 256;
    size_t packed_len = sizeof packed;
    int rc = SZ_BufftoBuffCompress(packed, &packed_len, data, sizeof data, &p);
    if (rc != SZ_OK) {
        printf("FAIL: SZ_BufftoBuffCompress: %d\n", rc);
        return 1;
    }
    size_t unpacked_len = sizeof unpacked;
    memset(unpacked, 0, sizeof unpacked);
    rc = SZ_BufftoBuffDecompress(unpacked, &unpacked_len, packed, packed_len, &p);
    if (rc != SZ_OK) {
        printf("FAIL: SZ_BufftoBuffDecompress: %d\n", rc);
        return 1;
    }
    if (unpacked_len != sizeof data || memcmp(unpacked, data, sizeof data) != 0) {
        puts("FAIL: szip round trip differs");
        return 1;
    }
    printf("szip: %lu -> %lu -> %lu bytes\n", (unsigned long)sizeof data, (unsigned long)packed_len,
           (unsigned long)unpacked_len);
    return 0;
}

static int aec_round_trip(void) {
    struct aec_stream s;
    memset(&s, 0, sizeof s);
    s.bits_per_sample = 16;
    s.block_size = 16;
    s.rsi = 128;
    s.flags = AEC_DATA_PREPROCESS;
    s.next_in = (const unsigned char *)data;
    s.avail_in = sizeof data;
    s.next_out = packed;
    s.avail_out = sizeof packed;
    int rc = aec_buffer_encode(&s);
    if (rc != AEC_OK) {
        printf("FAIL: aec_buffer_encode: %d\n", rc);
        return 1;
    }
    size_t packed_len = s.total_out;
    memset(unpacked, 0, sizeof unpacked);
    memset(&s, 0, sizeof s);
    s.bits_per_sample = 16;
    s.block_size = 16;
    s.rsi = 128;
    s.flags = AEC_DATA_PREPROCESS;
    s.next_in = packed;
    s.avail_in = packed_len;
    s.next_out = (unsigned char *)unpacked;
    s.avail_out = sizeof unpacked;
    rc = aec_buffer_decode(&s);
    if (rc != AEC_OK) {
        printf("FAIL: aec_buffer_decode: %d\n", rc);
        return 1;
    }
    if (s.total_out != sizeof data || memcmp(unpacked, data, sizeof data) != 0) {
        puts("FAIL: aec round trip differs");
        return 1;
    }
    printf("aec: %lu -> %lu -> %lu bytes\n", (unsigned long)sizeof data, (unsigned long)packed_len,
           (unsigned long)s.total_out);
    return 0;
}

int main(void) {
    /* a smooth ramp with a little noise: compressible, not trivial */
    unsigned int seed = 12345u;
    for (int i = 0; i < N; i++) {
        seed = seed * 1103515245u + 12345u;
        data[i] = (unsigned short)(1000 + i / 4 + ((seed >> 16) & 7));
    }
    if (SZ_encoder_enabled() != 1) {
        puts("FAIL: SZ_encoder_enabled() != 1");
        return 1;
    }
    if (szip_round_trip() != 0 || aec_round_trip() != 0) return 1;
    puts("OK");
    return 0;
}
