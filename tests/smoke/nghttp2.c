/* zig-nghttp2 smoke test: the header against the library version, an
   HPACK deflate/inflate round trip of four header fields, and a client
   session that writes the connection preface and a SETTINGS frame into
   memory (no network); prints OK. */
#include <stdio.h>
#include <string.h>
#include <nghttp2/nghttp2.h>

#define NV(n, v) { (uint8_t *)(n), (uint8_t *)(v), sizeof(n) - 1, sizeof(v) - 1, NGHTTP2_NV_FLAG_NONE }

static int hpack_round_trip(void) {
    nghttp2_nv nva[] = {
        NV(":method", "GET"),
        NV(":path", "/zig-libs/smoke"),
        NV(":authority", "example.org"),
        NV("user-agent", "zig-nghttp2-smoke"),
    };
    size_t nvlen = sizeof nva / sizeof nva[0];
    nghttp2_hd_deflater *def;
    nghttp2_hd_inflater *inf;
    if (nghttp2_hd_deflate_new(&def, 4096) != 0 || nghttp2_hd_inflate_new(&inf) != 0) {
        printf("FAIL: HPACK deflater/inflater\n");
        return 1;
    }
    uint8_t buf[512];
    nghttp2_ssize n = nghttp2_hd_deflate_hd2(def, buf, sizeof buf, nva, nvlen);
    if (n <= 0) {
        printf("FAIL: nghttp2_hd_deflate_hd2: %ld\n", (long)n);
        return 1;
    }
    size_t seen = 0;
    const uint8_t *in = buf;
    size_t inlen = (size_t)n;
    for (;;) {
        nghttp2_nv out;
        int flags = 0;
        nghttp2_ssize r = nghttp2_hd_inflate_hd3(inf, &out, &flags, in, inlen, 1);
        if (r < 0) {
            printf("FAIL: nghttp2_hd_inflate_hd3: %s\n", nghttp2_strerror((int)r));
            return 1;
        }
        in += r;
        inlen -= (size_t)r;
        if (flags & NGHTTP2_HD_INFLATE_EMIT) {
            if (seen >= nvlen || out.namelen != nva[seen].namelen || out.valuelen != nva[seen].valuelen
                || memcmp(out.name, nva[seen].name, out.namelen) != 0
                || memcmp(out.value, nva[seen].value, out.valuelen) != 0) {
                printf("FAIL: HPACK field %lu differs\n", (unsigned long)seen);
                return 1;
            }
            seen++;
        }
        if (flags & NGHTTP2_HD_INFLATE_FINAL) {
            nghttp2_hd_inflate_end_headers(inf);
            break;
        }
        if (inlen == 0 && r == 0) break;
    }
    nghttp2_hd_deflate_del(def);
    nghttp2_hd_inflate_del(inf);
    if (seen != nvlen) {
        printf("FAIL: HPACK: %lu of %lu fields back\n", (unsigned long)seen, (unsigned long)nvlen);
        return 1;
    }
    printf("HPACK: %lu fields -> %ld bytes -> %lu fields\n", (unsigned long)nvlen, (long)n, (unsigned long)seen);
    return 0;
}

static int client_preface(void) {
    nghttp2_session_callbacks *cbs;
    nghttp2_session *s;
    if (nghttp2_session_callbacks_new(&cbs) != 0 || nghttp2_session_client_new(&s, cbs, NULL) != 0) {
        printf("FAIL: client session\n");
        return 1;
    }
    nghttp2_settings_entry iv[] = { { NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, 100 } };
    if (nghttp2_submit_settings(s, NGHTTP2_FLAG_NONE, iv, 1) != 0) {
        printf("FAIL: nghttp2_submit_settings\n");
        return 1;
    }
    size_t total = 0;
    int preface = 0;
    for (;;) {
        const uint8_t *data;
        nghttp2_ssize n = nghttp2_session_mem_send2(s, &data);
        if (n < 0) {
            printf("FAIL: nghttp2_session_mem_send2: %s\n", nghttp2_strerror((int)n));
            return 1;
        }
        if (n == 0) break;
        if (total == 0 && (size_t)n >= NGHTTP2_CLIENT_MAGIC_LEN
            && memcmp(data, NGHTTP2_CLIENT_MAGIC, NGHTTP2_CLIENT_MAGIC_LEN) == 0)
            preface = 1;
        total += (size_t)n;
    }
    nghttp2_session_del(s);
    nghttp2_session_callbacks_del(cbs);
    /* the 24-byte preface, then a SETTINGS frame: 9-byte header + 6 per entry */
    if (!preface || total < NGHTTP2_CLIENT_MAGIC_LEN + 9 + 6) {
        printf("FAIL: client preface %d, %lu bytes\n", preface, (unsigned long)total);
        return 1;
    }
    printf("client session: preface and SETTINGS, %lu bytes\n", (unsigned long)total);
    return 0;
}

int main(void) {
    nghttp2_info *info = nghttp2_version(0);
    printf("nghttp2 %s (header %s)\n", info->version_str, NGHTTP2_VERSION);
    if (strcmp(info->version_str, NGHTTP2_VERSION) != 0 || info->version_num != NGHTTP2_VERSION_NUM) {
        printf("FAIL: library %s, header %s\n", info->version_str, NGHTTP2_VERSION);
        return 1;
    }
    if (hpack_round_trip() || client_preface()) return 1;
    printf("OK\n");
    return 0;
}
