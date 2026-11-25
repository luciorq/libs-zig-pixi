/* zig-libpq smoke test: the library version, OpenSSL in the build,
   conninfo parsing, bytea unescaping, and a refused connection (libpq's
   Winsock start-up and error path); prints OK. Needs no server. */
#include <stdio.h>
#include <string.h>
#include <libpq-fe.h>

int main(void) {
    int v = PQlibVersion();
    if (v != 160010) { printf("FAIL: PQlibVersion() = %d (want 160010)\n", v); return 1; }

    /* built with OpenSSL (zig-openssl): the attribute names the library */
    const char *lib = PQsslAttribute(NULL, "library");
    if (lib == NULL || strcmp(lib, "OpenSSL") != 0) {
        printf("FAIL: PQsslAttribute(NULL, \"library\") = %s (want OpenSSL)\n", lib ? lib : "NULL");
        return 1;
    }

    char *err = NULL;
    PQconninfoOption *opts = PQconninfoParse("host=example.invalid port=5433 dbname=x sslmode=require", &err);
    if (opts == NULL) { printf("FAIL: PQconninfoParse: %s\n", err ? err : "?"); return 1; }
    int port_ok = 0;
    for (PQconninfoOption *o = opts; o->keyword; o++)
        if (strcmp(o->keyword, "port") == 0 && o->val && strcmp(o->val, "5433") == 0) port_ok = 1;
    PQconninfoFree(opts);
    if (!port_ok) { puts("FAIL: conninfo port is not 5433"); return 1; }

    size_t n = 0;
    unsigned char *b = PQunescapeBytea((const unsigned char *)"\\x4f4b", &n);
    if (b == NULL || n != 2 || memcmp(b, "OK", 2) != 0) { puts("FAIL: PQunescapeBytea(\\x4f4b)"); return 1; }
    PQfreemem(b);

    /* nothing listens on port 1: a refused connection, with a message */
    PGconn *c = PQconnectdb("host=127.0.0.1 port=1 connect_timeout=5 sslmode=disable");
    if (PQstatus(c) != CONNECTION_BAD || strlen(PQerrorMessage(c)) == 0) {
        puts("FAIL: a connection to 127.0.0.1:1 did not fail with a message");
        return 1;
    }
    printf("libpq %d (%s): refused as expected: %s", v, lib, PQerrorMessage(c));
    PQfinish(c);
    puts("OK");
    return 0;
}
