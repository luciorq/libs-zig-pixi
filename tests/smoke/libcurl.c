/* zig-libcurl smoke test, no network: curl_version_info reports the
   version, Schannel as the TLS backend and the libz, zstd, brotli, SSPI,
   HTTP/2 (nghttp2), IDN (libidn2) and PSL (libpsl) features, libssh2
   with sftp and scp, and ldap among the protocols (slice3 D130); an
   international host name converted to punycode and back; a string
   escaped and unescaped and a URL built, read back and rewritten through
   the CURLU API; a temp file written and downloaded through a file:// URL
   into a memory buffer, equal to what was written; prints OK. */
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <curl/curl.h>
#ifdef _WIN32
#include <windows.h>
#endif

static int fails = 0;

static void expect(int ok, const char *what) {
    if (!ok) {
        printf("FAIL: %s\n", what);
        fails++;
    }
}

static int has_protocol(const curl_version_info_data *vi, const char *p) {
    for (const char *const *q = vi->protocols; q && *q; q++)
        if (strcmp(*q, p) == 0) return 1;
    return 0;
}

static void check_version(void) {
    const curl_version_info_data *vi = curl_version_info(CURLVERSION_NOW);
    printf("libcurl %s, ssl %s, libz %s, zstd %s, brotli %s\n", vi->version,
           vi->ssl_version ? vi->ssl_version : "(none)",
           vi->libz_version ? vi->libz_version : "(none)",
           vi->zstd_version ? vi->zstd_version : "(none)",
           vi->brotli_version ? vi->brotli_version : "(none)");
    expect(strcmp(vi->version, LIBCURL_VERSION) == 0, "version is the header's LIBCURL_VERSION");
    expect(vi->version_num == LIBCURL_VERSION_NUM, "version_num is the header's");
    expect(vi->ssl_version && strstr(vi->ssl_version, "Schannel") != NULL, "TLS backend is Schannel");
    expect((vi->features & CURL_VERSION_SSL) != 0, "feature SSL");
    expect((vi->features & CURL_VERSION_LIBZ) != 0 && vi->libz_version, "feature libz");
    expect((vi->features & CURL_VERSION_ZSTD) != 0 && vi->zstd_version, "feature zstd");
    expect((vi->features & CURL_VERSION_BROTLI) != 0 && vi->brotli_version, "feature brotli");
    printf("libssh2 %s, nghttp2 %s, libidn2 %s\n", vi->libssh_version ? vi->libssh_version : "(none)",
           vi->nghttp2_version ? vi->nghttp2_version : "(none)", vi->libidn ? vi->libidn : "(none)");
    expect((vi->features & CURL_VERSION_IDN) != 0 && vi->libidn, "feature IDN (libidn2, not WinIDN)");
    expect((vi->features & CURL_VERSION_PSL) != 0, "feature PSL (libpsl)");
    expect((vi->features & CURL_VERSION_HTTP2) != 0 && vi->nghttp2_version, "feature HTTP2 (nghttp2)");
    expect(vi->libssh_version && strncmp(vi->libssh_version, "libssh2/", 8) == 0, "libssh2");
    expect((vi->features & CURL_VERSION_SSPI) != 0, "feature SSPI");
    expect(has_protocol(vi, "sftp"), "protocol sftp (libssh2)");
    expect(has_protocol(vi, "scp"), "protocol scp (libssh2)");
    expect(has_protocol(vi, "https"), "protocol https");
    expect(has_protocol(vi, "file"), "protocol file");
    expect(has_protocol(vi, "ldap"), "protocol ldap (wldap32)");
    /* one backend only: no OpenSSL next to Schannel */
    const curl_ssl_backend **backends = NULL;
    curl_global_sslset(CURLSSLBACKEND_NONE, NULL, &backends);
    int n = 0;
    for (; backends && backends[n]; n++)
        printf("ssl backend: %s\n", backends[n]->name);
    expect(n == 1 && backends[0]->id == CURLSSLBACKEND_SCHANNEL, "Schannel is the only TLS backend");
}

static void check_url_api(CURL *h) {
    const char *raw = "a b&c=d/\xc3\xa9";
    char *esc = curl_easy_escape(h, raw, 0);
    expect(esc && strcmp(esc, "a%20b%26c%3Dd%2F%C3%A9") == 0, "curl_easy_escape");
    int len = 0;
    char *back = esc ? curl_easy_unescape(h, esc, 0, &len) : NULL;
    expect(back && len == (int)strlen(raw) && memcmp(back, raw, len) == 0, "curl_easy_unescape round trip");
    curl_free(back);

    CURLU *u = curl_url();
    char *host = NULL, *query = NULL, *full = NULL;
    expect(curl_url_set(u, CURLUPART_URL, "https://user@example.org:8443/dir/../p?x=1#frag", 0) == CURLUE_OK,
           "curl_url_set URL");
    expect(curl_url_get(u, CURLUPART_HOST, &host, 0) == CURLUE_OK && strcmp(host, "example.org") == 0,
           "curl_url_get host");
    expect(curl_url_set(u, CURLUPART_QUERY, "q=a b&c", CURLU_APPENDQUERY | CURLU_URLENCODE) == CURLUE_OK,
           "curl_url_set query (append, encode)");
    expect(curl_url_get(u, CURLUPART_QUERY, &query, 0) == CURLUE_OK && strcmp(query, "x=1&q=a+b%26c") == 0,
           "curl_url_get query");
    expect(curl_url_get(u, CURLUPART_URL, &full, 0) == CURLUE_OK &&
               strcmp(full, "https://user@example.org:8443/p?x=1&q=a+b%26c#frag") == 0,
           "curl_url_get URL (normalized path)");
    if (fails) printf("url: host '%s' query '%s' url '%s'\n", host ? host : "", query ? query : "", full ? full : "");
    curl_free(host);
    curl_free(query);
    curl_free(full);
    curl_url_cleanup(u);
    curl_free(esc);

    /* IDN through libidn2: a UTF-8 host to punycode and back. curl calls
       idn2_lookup_ul (no ENABLE_UNICODE), which reads the host in the
       locale's charset: in the "C" locale that is the ANSI code page
       (CP1252), so the test runs in a UTF-8 locale, as R does (its
       Windows builds use UTF-8 since 4.2) */
    setlocale(LC_CTYPE, ".UTF-8");
    CURLU *i = curl_url();
    char *puny = NULL, *idn = NULL;
    expect(curl_url_set(i, CURLUPART_URL, "https://b\xc3\xbc" "cher.example/", 0) == CURLUE_OK, "curl_url_set IDN URL");
    expect(curl_url_get(i, CURLUPART_HOST, &puny, CURLU_PUNYCODE) == CURLUE_OK &&
               strcmp(puny, "xn--bcher-kva.example") == 0,
           "IDN host to punycode");
    curl_url_set(i, CURLUPART_HOST, "xn--bcher-kva.example", 0);
    expect(curl_url_get(i, CURLUPART_HOST, &idn, CURLU_PUNY2IDN) == CURLUE_OK &&
               strcmp(idn, "b\xc3\xbc" "cher.example") == 0,
           "punycode host to IDN");
    printf("idn: %s <-> %s\n", puny ? puny : "(none)", idn ? idn : "(none)");
    curl_free(puny);
    curl_free(idn);
    curl_url_cleanup(i);
}

struct buf {
    char *data;
    size_t len;
};

static size_t on_write(char *p, size_t size, size_t n, void *userp) {
    struct buf *b = userp;
    size_t add = size * n;
    char *d = realloc(b->data, b->len + add + 1);
    if (!d) return 0;
    memcpy(d + b->len, p, add);
    b->data = d;
    b->len += add;
    b->data[b->len] = 0;
    return add;
}

static void check_file_download(CURL *h) {
    /* a few KB with every byte value, in a file named in the temp dir */
    enum { N = 5000 };
    static unsigned char content[N];
    for (int i = 0; i < N; i++) content[i] = (unsigned char)(i * 7 + i / 256);
    char path[1024];
#ifdef _WIN32
    char dir[MAX_PATH];
    DWORD dl = GetTempPathA(sizeof dir, dir);
    expect(dl > 0 && dl < sizeof dir, "GetTempPathA");
    snprintf(path, sizeof path, "%slibcurl-smoke-%lu.bin", dir, (unsigned long)GetCurrentProcessId());
#else
    snprintf(path, sizeof path, "/tmp/libcurl-smoke.bin");
#endif
    FILE *f = fopen(path, "wb");
    expect(f && fwrite(content, 1, N, f) == N, "write the temp file");
    if (f) fclose(f);

    /* file:///C:/Users/.../x.bin: forward slashes, percent-encoded path */
    char fpath[1100];
    snprintf(fpath, sizeof fpath, "%s%s", path[0] == '/' ? "" : "/", path);
    for (char *c = fpath; *c; c++)
        if (*c == '\\') *c = '/';
    CURLU *u = curl_url();
    char *url = NULL;
    expect(curl_url_set(u, CURLUPART_SCHEME, "file", 0) == CURLUE_OK &&
               curl_url_set(u, CURLUPART_PATH, fpath, CURLU_URLENCODE) == CURLUE_OK &&
               curl_url_get(u, CURLUPART_URL, &url, 0) == CURLUE_OK,
           "build the file:// URL");
    printf("file url: %s\n", url ? url : "(none)");

    struct buf b = {NULL, 0};
    curl_easy_setopt(h, CURLOPT_URL, url);
    curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, on_write);
    curl_easy_setopt(h, CURLOPT_WRITEDATA, &b);
    CURLcode rc = curl_easy_perform(h);
    if (rc != CURLE_OK) printf("curl_easy_perform: %s\n", curl_easy_strerror(rc));
    expect(rc == CURLE_OK, "file:// download");
    expect(b.len == N && memcmp(b.data, content, N) == 0, "downloaded bytes equal the file");
    printf("file download: %zu bytes\n", b.len);
    free(b.data);
    curl_free(url);
    curl_url_cleanup(u);
    remove(path);
}

int main(void) {
    check_version();
    expect(curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK, "curl_global_init");
    CURL *h = curl_easy_init();
    expect(h != NULL, "curl_easy_init");
    if (h) {
        check_url_api(h);
        check_file_download(h);
        curl_easy_cleanup(h);
    }
    curl_global_cleanup();
    if (fails) return 1;
    puts("OK");
    return 0;
}
