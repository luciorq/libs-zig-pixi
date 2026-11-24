/* zig-libpng smoke test: an 8x8 RGBA image written to a memory buffer
   (png_set_write_fn, deflate through zlib) and read back (png_set_read_fn),
   pixels compared, and the library version against the header's; prints
   OK. */
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <png.h>
#include <zlib.h>

#define W 8
#define H 8

struct buf {
    unsigned char *data;
    size_t len, cap, pos;
};

static void write_fn(png_structp p, png_bytep data, size_t n) {
    struct buf *b = (struct buf *)png_get_io_ptr(p);
    if (b->len + n > b->cap) {
        size_t cap = (b->len + n) * 2;
        unsigned char *d = (unsigned char *)realloc(b->data, cap);
        if (d == NULL) png_error(p, "out of memory");
        b->data = d;
        b->cap = cap;
    }
    memcpy(b->data + b->len, data, n);
    b->len += n;
}

static void flush_fn(png_structp p) { (void)p; }

static void read_fn(png_structp p, png_bytep data, size_t n) {
    struct buf *b = (struct buf *)png_get_io_ptr(p);
    if (b->pos + n > b->len) png_error(p, "read past the end");
    memcpy(data, b->data + b->pos, n);
    b->pos += n;
}

static unsigned char px(int y, int x, int c) {
    return (unsigned char)(c == 3 ? 255 - 8 * (x + y) : 32 * x + 3 * y + 50 * c);
}

int main(void) {
    png_uint_32 v = png_access_version_number();
    if (v != PNG_LIBPNG_VER) {
        printf("FAIL: png_access_version_number = %lu (header %d)\n", (unsigned long)v,
               PNG_LIBPNG_VER);
        return 1;
    }

    unsigned char img[H][W * 4], back[H][W * 4];
    png_bytep rows[H];
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++)
            for (int c = 0; c < 4; c++) img[y][4 * x + c] = px(y, x, c);

    struct buf b = {NULL, 0, 0, 0};
    png_structp wp = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    png_infop wi = wp ? png_create_info_struct(wp) : NULL;
    if (wi == NULL) {
        puts("FAIL: png_create_write_struct");
        return 1;
    }
    if (setjmp(png_jmpbuf(wp))) {
        puts("FAIL: writing the PNG");
        return 1;
    }
    png_set_write_fn(wp, &b, write_fn, flush_fn);
    png_set_IHDR(wp, wi, W, H, 8, PNG_COLOR_TYPE_RGBA, PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    for (int y = 0; y < H; y++) rows[y] = img[y];
    png_set_rows(wp, wi, rows);
    png_write_png(wp, wi, PNG_TRANSFORM_IDENTITY, NULL);
    png_destroy_write_struct(&wp, &wi);

    static const unsigned char sig[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    if (b.len < 8 || memcmp(b.data, sig, 8) != 0) {
        puts("FAIL: no PNG signature");
        return 1;
    }

    png_structp rp = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    png_infop ri = rp ? png_create_info_struct(rp) : NULL;
    if (ri == NULL) {
        puts("FAIL: png_create_read_struct");
        return 1;
    }
    if (setjmp(png_jmpbuf(rp))) {
        puts("FAIL: reading the PNG");
        return 1;
    }
    png_set_read_fn(rp, &b, read_fn);
    png_read_info(rp, ri);
    if (png_get_image_width(rp, ri) != W || png_get_image_height(rp, ri) != H ||
        png_get_color_type(rp, ri) != PNG_COLOR_TYPE_RGBA || png_get_bit_depth(rp, ri) != 8) {
        puts("FAIL: IHDR read back differs");
        return 1;
    }
    for (int y = 0; y < H; y++) rows[y] = back[y];
    png_read_image(rp, rows);
    png_read_end(rp, NULL);
    png_destroy_read_struct(&rp, &ri, NULL);

    if (memcmp(img, back, sizeof img) != 0) {
        puts("FAIL: pixels read back differ");
        return 1;
    }
    printf("libpng %s (zlib %s): %dx%d RGBA -> %lu bytes PNG -> pixels equal\n",
           png_get_libpng_ver(NULL), zlibVersion(), W, H, (unsigned long)b.len);
    free(b.data);
    puts("OK");
    return 0;
}
