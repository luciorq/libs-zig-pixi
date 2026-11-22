/* zig-openssl smoke test: SHA-256 of "abc" through EVP, compared with the
 * FIPS 180-2 test vector; prints the OpenSSL version and OK. */
#include <stdio.h>
#include <string.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/ssl.h>

static const unsigned char expected[32] = {
    0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
    0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c, 0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad};

int main(void) {
    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int len = 0;
    unsigned int i;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    SSL_CTX *ssl;

    if (ctx == NULL || EVP_DigestInit_ex(ctx, EVP_sha256(), NULL) != 1 ||
        EVP_DigestUpdate(ctx, "abc", 3) != 1 || EVP_DigestFinal_ex(ctx, md, &len) != 1) {
        puts("FAIL: EVP SHA-256");
        return 1;
    }
    EVP_MD_CTX_free(ctx);
    printf("%s\nsha256(abc) = ", OpenSSL_version(OPENSSL_VERSION));
    for (i = 0; i < len; i++) printf("%02x", md[i]);
    putchar('\n');
    if (len != sizeof expected || memcmp(md, expected, sizeof expected) != 0) {
        puts("FAIL: digest differs");
        return 1;
    }
    /* libssl links and initialises (TLS method table, default config) */
    ssl = SSL_CTX_new(TLS_client_method());
    if (ssl == NULL) {
        puts("FAIL: SSL_CTX_new");
        return 1;
    }
    SSL_CTX_free(ssl);
    printf("%s\n", OpenSSL_version(OPENSSL_DIR));
    puts("OK");
    return 0;
}
