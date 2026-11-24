/* zig-libwebp smoke test: an RGBA image encoded losslessly
 * (WebPEncodeLosslessRGBA) and decoded (WebPDecodeRGBA), pixels compared
 * exactly; demux and mux on the result; the decoder version. Prints OK. */
#include <stdio.h>
#include <string.h>
#include <webp/decode.h>
#include <webp/demux.h>
#include <webp/encode.h>
#include <webp/mux.h>

#define W 37
#define H 23

static int failures = 0;

static void check(int ok, const char *what) {
    if (!ok) {
        printf("FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    static uint8_t rgba[W * H * 4];
    uint8_t *webp = NULL, *out;
    size_t webp_len;
    int x, y, w = 0, h = 0, dec = WebPGetDecoderVersion();

    for (y = 0; y < H; y++)
        for (x = 0; x < W; x++) {
            uint8_t *p = rgba + (y * W + x) * 4;
            p[0] = (uint8_t)(x * 7);
            p[1] = (uint8_t)(y * 11);
            p[2] = (uint8_t)((x ^ y) * 5);
            p[3] = (uint8_t)(255 - x - y);
        }

    webp_len = WebPEncodeLosslessRGBA(rgba, W, H, W * 4, &webp);
    check(webp_len > 12 && memcmp(webp, "RIFF", 4) == 0 && memcmp(webp + 8, "WEBP", 4) == 0,
          "WebPEncodeLosslessRGBA: RIFF/WEBP");

    out = WebPDecodeRGBA(webp, webp_len, &w, &h);
    check(out != NULL && w == W && h == H, "WebPDecodeRGBA dimensions");
    check(out != NULL && memcmp(out, rgba, sizeof rgba) == 0, "lossless pixels exact");
    WebPFree(out);

    {   /* libwebpdemux: one frame of the image's size */
        WebPData data = {webp, webp_len};
        WebPDemuxer *demux = WebPDemux(&data);
        check(demux != NULL && WebPDemuxGetI(demux, WEBP_FF_CANVAS_WIDTH) == W &&
                  WebPDemuxGetI(demux, WEBP_FF_FRAME_COUNT) == 1,
              "WebPDemux canvas width and frame count");
        WebPDemuxDelete(demux);
    }
    {   /* libwebpmux: the image back out of a mux */
        WebPData data = {webp, webp_len}, assembled = {NULL, 0};
        WebPMux *mux = WebPMuxCreate(&data, 0);
        check(mux != NULL && WebPMuxAssemble(mux, &assembled) == WEBP_MUX_OK &&
                  assembled.size > 0,
              "WebPMuxCreate and WebPMuxAssemble");
        WebPDataClear(&assembled);
        WebPMuxDelete(mux);
    }
    WebPFree(webp);

    check(dec == 0x010600, "WebPGetDecoderVersion 0x010600");
    printf("libwebp %d.%d.%d (encoder %06x): %dx%d RGBA -> %u bytes lossless -> exact\n",
           dec >> 16, (dec >> 8) & 0xff, dec & 0xff, WebPGetEncoderVersion(), W, H,
           (unsigned)webp_len);
    if (failures) return 1;
    puts("OK");
    return 0;
}
