/* zig-libssh2 smoke test: the header against the library version, the
   crypto backend (OpenSSL, slice3 D130), and a session's supported method
   lists: zlib compression (zig-zlib), ssh-ed25519 host keys and
   curve25519 key exchange (algorithms the OpenSSL backend has and WinCNG
   lacks), aes256-gcm ciphers. No network; prints OK. */
#include <stdio.h>
#include <string.h>
#include <libssh2.h>

static int has_alg(LIBSSH2_SESSION *s, int method, const char *want) {
    const char **algs = NULL;
    int n = libssh2_session_supported_algs(s, method, &algs);
    if (n <= 0) {
        printf("FAIL: libssh2_session_supported_algs(%d): %d\n", method, n);
        return 0;
    }
    int found = 0;
    for (int i = 0; i < n; i++)
        if (strcmp(algs[i], want) == 0) found = 1;
    libssh2_free(s, algs);
    printf("method %d: %d algorithms, %s %s\n", method, n, want, found ? "yes" : "MISSING");
    return found;
}

int main(void) {
    const char *v = libssh2_version(0);
    printf("libssh2 %s (header %s)\n", v ? v : "(null)", LIBSSH2_VERSION);
    if (!v || strcmp(v, LIBSSH2_VERSION) != 0) {
        printf("FAIL: library %s, header %s\n", v ? v : "(null)", LIBSSH2_VERSION);
        return 1;
    }
    if (libssh2_crypto_engine() != libssh2_openssl) {
        printf("FAIL: crypto engine %d, want OpenSSL (%d)\n", (int)libssh2_crypto_engine(), (int)libssh2_openssl);
        return 1;
    }
    printf("crypto engine: OpenSSL\n");
    if (libssh2_init(0) != 0) {
        printf("FAIL: libssh2_init\n");
        return 1;
    }
    LIBSSH2_SESSION *s = libssh2_session_init();
    if (!s) {
        printf("FAIL: libssh2_session_init\n");
        return 1;
    }
    /* the COMP lists hold zlib only once the session asks for
       compression (src/comp.c _libssh2_comp_methods): set the flag first */
    int ok = 1;
    if (libssh2_session_flag(s, LIBSSH2_FLAG_COMPRESS, 1) != 0) {
        printf("FAIL: libssh2_session_flag(COMPRESS)\n");
        ok = 0;
    }
    ok &= has_alg(s, LIBSSH2_METHOD_COMP_CS, "zlib")
        & has_alg(s, LIBSSH2_METHOD_HOSTKEY, "ssh-ed25519")
        & has_alg(s, LIBSSH2_METHOD_KEX, "curve25519-sha256")
        & has_alg(s, LIBSSH2_METHOD_CRYPT_CS, "aes256-gcm@openssh.com");
    libssh2_session_free(s);
    libssh2_exit();
    if (!ok) return 1;
    printf("OK\n");
    return 0;
}
