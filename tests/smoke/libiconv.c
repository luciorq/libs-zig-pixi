/* zig-libiconv smoke test: ISO-8859-1, SHIFT_JIS and EUC-JP to UTF-8
   through iconv_open/iconv, checked byte for byte; an invalid SHIFT_JIS
   sequence is reported as EILSEQ; prints OK. */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <iconv.h>

static int convert(const char *from, const char *in, size_t in_len, const char *want, size_t want_len) {
    iconv_t cd = iconv_open("UTF-8", from);
    if (cd == (iconv_t)-1) {
        printf("FAIL: iconv_open(UTF-8, %s): errno %d\n", from, errno);
        return 1;
    }
    char out[64];
    char *ip = (char *)in, *op = out;
    size_t il = in_len, ol = sizeof out;
    size_t r = iconv(cd, &ip, &il, &op, &ol);
    iconv_close(cd);
    size_t n = sizeof out - ol;
    if (r == (size_t)-1 || il != 0 || n != want_len || memcmp(out, want, want_len) != 0) {
        printf("FAIL: %s -> UTF-8: %lu bytes out, %lu left\n", from, (unsigned long)n, (unsigned long)il);
        return 1;
    }
    printf("%s -> UTF-8: %lu -> %lu bytes\n", from, (unsigned long)in_len, (unsigned long)n);
    return 0;
}

int main(void) {
    /* "café über" */
    static const char latin1[] = "caf\xe9 \xfc" "ber";
    static const char latin1_utf8[] = "caf\xc3\xa9 \xc3\xbc" "ber";
    /* "日本語" (U+65E5 U+672C U+8A9E) */
    static const char sjis[] = "\x93\xfa\x96\x7b\x8c\xea";
    static const char eucjp[] = "\xc6\xfc\xcb\xdc\xb8\xec";
    static const char ja_utf8[] = "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e";

    int fails = 0;
    fails += convert("ISO-8859-1", latin1, sizeof latin1 - 1, latin1_utf8, sizeof latin1_utf8 - 1);
    fails += convert("SHIFT_JIS", sjis, sizeof sjis - 1, ja_utf8, sizeof ja_utf8 - 1);
    fails += convert("EUC-JP", eucjp, sizeof eucjp - 1, ja_utf8, sizeof ja_utf8 - 1);
    if (fails) return 1;

    /* 0x81 0x20: a lead byte without a valid trail byte */
    iconv_t cd = iconv_open("UTF-8", "SHIFT_JIS");
    char bad[] = "\x81\x20", out[16];
    char *ip = bad, *op = out;
    size_t il = 2, ol = sizeof out;
    errno = 0;
    size_t r = iconv(cd, &ip, &il, &op, &ol);
    iconv_close(cd);
    if (r != (size_t)-1 || errno != EILSEQ) {
        printf("FAIL: invalid SHIFT_JIS not reported as EILSEQ (errno %d)\n", errno);
        return 1;
    }
    printf("libiconv %d.%d\n", _libiconv_version >> 8, _libiconv_version & 0xff);
    if (_libiconv_version != _LIBICONV_VERSION) {
        printf("FAIL: library %#x, header %#x\n", _libiconv_version, _LIBICONV_VERSION);
        return 1;
    }
    puts("OK");
    return 0;
}
