/* zig-libjpeg smoke test: an RGB image compressed to memory (jpeg_mem_dest)
 * and decompressed (jpeg_mem_src), dimensions and pixels checked; the
 * library version (JPEG_LIB_VERSION, JVERSION). windows.h first: rpcndr.h
 * typedefs boolean, and jconfig.h must agree with it. Prints OK. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jpeglib.h>
#include <jerror.h>

#define W 64
#define H 48

static int failures = 0;

static void check(int ok, const char *what) {
    if (!ok) {
        printf("FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    static unsigned char rgb[W * H * 3];
    static unsigned char out[W * H * 3];
    struct jpeg_compress_struct c;
    struct jpeg_decompress_struct d;
    struct jpeg_error_mgr cerr, derr;
    unsigned char *jpg = NULL;
    size_t jpg_len = 0; /* jpeg_mem_dest takes a size_t * in 9f */
    char version[JMSG_LENGTH_MAX];
    int x, y, maxdiff = 0;

    /* a smooth gradient: lossy JPEG keeps it within a few levels */
    for (y = 0; y < H; y++)
        for (x = 0; x < W; x++) {
            unsigned char *p = rgb + (y * W + x) * 3;
            p[0] = (unsigned char)(x * 255 / (W - 1));
            p[1] = (unsigned char)(y * 255 / (H - 1));
            p[2] = 128;
        }

    c.err = jpeg_std_error(&cerr);
    jpeg_create_compress(&c);
    jpeg_mem_dest(&c, &jpg, &jpg_len);
    c.image_width = W;
    c.image_height = H;
    c.input_components = 3;
    c.in_color_space = JCS_RGB;
    jpeg_set_defaults(&c);
    jpeg_set_quality(&c, 95, TRUE);
    jpeg_start_compress(&c, TRUE);
    while (c.next_scanline < c.image_height) {
        JSAMPROW row = rgb + c.next_scanline * W * 3;
        jpeg_write_scanlines(&c, &row, 1);
    }
    jpeg_finish_compress(&c);
    jpeg_destroy_compress(&c);
    check(jpg != NULL && jpg_len > 2 && jpg[0] == 0xFF && jpg[1] == 0xD8, "JPEG SOI marker");

    d.err = jpeg_std_error(&derr);
    jpeg_create_decompress(&d);
    jpeg_mem_src(&d, jpg, jpg_len);
    check(jpeg_read_header(&d, TRUE) == JPEG_HEADER_OK, "jpeg_read_header");
    jpeg_start_decompress(&d);
    check(d.output_width == W && d.output_height == H && d.output_components == 3,
          "decoded dimensions");
    while (d.output_scanline < d.output_height) {
        JSAMPROW row = out + d.output_scanline * W * 3;
        jpeg_read_scanlines(&d, &row, 1);
    }
    jpeg_finish_decompress(&d);
    jpeg_destroy_decompress(&d);
    free(jpg);

    for (x = 0; x < W * H * 3; x++) {
        int diff = abs((int)out[x] - (int)rgb[x]);
        if (diff > maxdiff) maxdiff = diff;
    }
    check(maxdiff <= 16, "decoded pixels within 16 levels");

    check(JPEG_LIB_VERSION == 90, "JPEG_LIB_VERSION 90");
    /* JVERSION is in the library's message table (jversion.h is private) */
    derr.msg_code = JMSG_VERSION;
    derr.format_message((j_common_ptr)&d, version);
    check(strncmp(version, "9f", 2) == 0, "JVERSION 9f");

    printf("libjpeg %d (%s): %dx%d RGB -> %u bytes JPEG -> max diff %d\n",
           JPEG_LIB_VERSION, version, W, H, (unsigned)jpg_len, maxdiff);
    if (failures) return 1;
    puts("OK");
    return 0;
}
