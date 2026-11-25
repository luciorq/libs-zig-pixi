/* zig-libtiff smoke test: an 8-bit RGB image written to a TIFF file in the
 * current directory with each codec the package must have (LZW, Deflate
 * through zlib/libdeflate, JPEG, WebP, ZSTD, LZMA), read back with
 * TIFFReadScanline and compared: exactly for the lossless codecs, by mean
 * and maximum absolute error for JPEG and lossy WebP. TIFFIsCODECConfigured
 * for each codec; TIFFGetVersion. Prints OK. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tiffio.h>

#define W 64
#define H 48

static int failures = 0;

static void check(int ok, const char *what, const char *codec) {
    if (!ok) {
        printf("FAIL: %s: %s\n", codec, what);
        failures++;
    }
}

static void on_error(const char *module, const char *fmt, va_list ap) {
    printf("libtiff error (%s): ", module ? module : "-");
    vprintf(fmt, ap);
    printf("\n");
}

struct codec {
    uint16_t id;
    const char *name;
    int lossy;
};

static const struct codec codecs[] = {
    {COMPRESSION_LZW, "lzw", 0},
    {COMPRESSION_ADOBE_DEFLATE, "deflate", 0},
    {COMPRESSION_JPEG, "jpeg", 1},
    {COMPRESSION_WEBP, "webp", 1},
    {COMPRESSION_ZSTD, "zstd", 0},
    {COMPRESSION_LZMA, "lzma", 0},
};

static uint8_t image[H][W * 3];

static int roundtrip(const struct codec *c) {
    char path[64];
    TIFF *tif;
    uint8_t row[W * 3];
    uint32_t w = 0, h = 0;
    uint16_t comp = 0;
    long sum = 0;
    int y, i, max = 0;

    snprintf(path, sizeof path, "smoke-libtiff-%s.tif", c->name);
    tif = TIFFOpen(path, "w");
    check(tif != NULL, "TIFFOpen w", c->name);
    if (!tif) return 0;
    TIFFSetField(tif, TIFFTAG_IMAGEWIDTH, (uint32_t)W);
    TIFFSetField(tif, TIFFTAG_IMAGELENGTH, (uint32_t)H);
    TIFFSetField(tif, TIFFTAG_BITSPERSAMPLE, 8);
    TIFFSetField(tif, TIFFTAG_SAMPLESPERPIXEL, 3);
    TIFFSetField(tif, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);
    TIFFSetField(tif, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_RGB);
    TIFFSetField(tif, TIFFTAG_ROWSPERSTRIP, (uint32_t)H);
    check(TIFFSetField(tif, TIFFTAG_COMPRESSION, c->id) == 1, "TIFFTAG_COMPRESSION", c->name);
    if (c->id == COMPRESSION_JPEG) TIFFSetField(tif, TIFFTAG_JPEGQUALITY, 90);
    if (c->id == COMPRESSION_WEBP) TIFFSetField(tif, TIFFTAG_WEBP_LEVEL, 90);
    if (!c->lossy) TIFFSetField(tif, TIFFTAG_PREDICTOR, PREDICTOR_HORIZONTAL);
    for (y = 0; y < H; y++)
        check(TIFFWriteScanline(tif, image[y], (uint32_t)y, 0) == 1, "TIFFWriteScanline", c->name);
    TIFFClose(tif);

    tif = TIFFOpen(path, "r");
    check(tif != NULL, "TIFFOpen r", c->name);
    if (!tif) return 0;
    TIFFGetField(tif, TIFFTAG_IMAGEWIDTH, &w);
    TIFFGetField(tif, TIFFTAG_IMAGELENGTH, &h);
    TIFFGetField(tif, TIFFTAG_COMPRESSION, &comp);
    check(w == W && h == H && comp == c->id, "dimensions and compression tag", c->name);
    for (y = 0; y < H; y++) {
        if (TIFFReadScanline(tif, row, (uint32_t)y, 0) != 1) {
            check(0, "TIFFReadScanline", c->name);
            break;
        }
        for (i = 0; i < W * 3; i++) {
            int d = abs((int)row[i] - (int)image[y][i]);
            sum += d;
            if (d > max) max = d;
        }
    }
    TIFFClose(tif);
    remove(path);
    if (c->lossy)
        check(sum <= (long)W * H * 3 * 4 && max <= 64, "lossy pixels close", c->name);
    else
        check(sum == 0, "lossless pixels exact", c->name);
    printf("%-8s mean abs error %.3f, max %d\n", c->name, (double)sum / (W * H * 3), max);
    return 1;
}

int main(void) {
    const char *v = TIFFGetVersion();
    size_t i;
    int x, y;

    TIFFSetErrorHandler(on_error);
    /* smooth gradients, so JPEG and lossy WebP stay close */
    for (y = 0; y < H; y++)
        for (x = 0; x < W; x++) {
            image[y][x * 3 + 0] = (uint8_t)(x * 4);
            image[y][x * 3 + 1] = (uint8_t)(y * 5);
            image[y][x * 3 + 2] = (uint8_t)(128 + (x - y));
        }

    for (i = 0; i < sizeof codecs / sizeof codecs[0]; i++) {
        check(TIFFIsCODECConfigured(codecs[i].id), "TIFFIsCODECConfigured", codecs[i].name);
        roundtrip(&codecs[i]);
    }

    check(v != NULL && strstr(v, "4.7.1") != NULL, "TIFFGetVersion 4.7.1", "version");
    printf("%.*s\n", v ? (int)strcspn(v, "\n") : 0, v ? v : "");
    if (failures) return 1;
    puts("OK");
    return 0;
}
