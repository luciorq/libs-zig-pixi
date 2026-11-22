/* zig-sqlite smoke test: an RTREE table (insert, range query), then
 * PRAGMA compile_options compared with the list the recipe keeps
 * (recipes/zig-sqlite/compile-options.h): every option printed, the
 * COMPILER=<clang> line aside, must be in the list and every listed option
 * printed. Prints OK and exits 0, else FAIL lines and exits 1. */
#include <stdio.h>
#include <string.h>
#include <sqlite3.h>

static const char *expected[] = {
#define SQLITE_OPTION_SET(o) o,
#define SQLITE_OPTION_DEFAULT(o) o,
#include "../../recipes/zig-sqlite/compile-options.h"
};
#define N_EXPECTED (sizeof expected / sizeof expected[0])

static int fail(sqlite3 *db, const char *what) {
    printf("FAIL: %s: %s\n", what, db ? sqlite3_errmsg(db) : "");
    return 1;
}

int main(void) {
    sqlite3 *db = NULL;
    sqlite3_stmt *st = NULL;
    int seen[N_EXPECTED] = {0};
    int bad = 0, n = 0;
    size_t i;

    printf("sqlite %s (%s)\n", sqlite3_libversion(), sqlite3_sourceid());
    if (sqlite3_open(":memory:", &db) != SQLITE_OK) return fail(db, "open");
    if (sqlite3_exec(db,
            "CREATE VIRTUAL TABLE box USING rtree(id, minx, maxx, miny, maxy);"
            "INSERT INTO box VALUES (1, 0, 10, 0, 10), (2, 5, 15, 5, 15), (3, 20, 30, 20, 30);",
            NULL, NULL, NULL) != SQLITE_OK)
        return fail(db, "rtree create/insert");
    if (sqlite3_prepare_v2(db, "SELECT group_concat(id) FROM (SELECT id FROM box"
            " WHERE maxx >= 6 AND minx <= 8 AND maxy >= 6 AND miny <= 8 ORDER BY id)",
            -1, &st, NULL) != SQLITE_OK || sqlite3_step(st) != SQLITE_ROW)
        return fail(db, "rtree query");
    printf("rtree query: %s\n", (const char *)sqlite3_column_text(st, 0));
    if (strcmp((const char *)sqlite3_column_text(st, 0), "1,2") != 0) {
        puts("FAIL: rtree query, want 1,2");
        bad = 1;
    }
    sqlite3_finalize(st);

    if (sqlite3_prepare_v2(db, "PRAGMA compile_options", -1, &st, NULL) != SQLITE_OK)
        return fail(db, "PRAGMA compile_options");
    while (sqlite3_step(st) == SQLITE_ROW) {
        const char *o = (const char *)sqlite3_column_text(st, 0);
        printf("compile_option %s\n", o);
        n++;
        if (strncmp(o, "COMPILER=", 9) == 0) continue;
        for (i = 0; i < N_EXPECTED; i++)
            if (strcmp(o, expected[i]) == 0) break;
        if (i == N_EXPECTED) {
            printf("FAIL: compile option %s is not in compile-options.h\n", o);
            bad = 1;
        } else seen[i] = 1;
    }
    sqlite3_finalize(st);
    for (i = 0; i < N_EXPECTED; i++)
        if (!seen[i]) {
            printf("FAIL: compile option %s missing\n", expected[i]);
            bad = 1;
        }
    printf("%d compile options, %d expected (plus COMPILER=)\n", n, (int)N_EXPECTED);
    sqlite3_close(db);
    if (bad) return 1;
    puts("OK");
    return 0;
}
