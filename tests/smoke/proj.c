/* zig-proj smoke test (C API): EPSG:4326 -> EPSG:3857 for (lon 10,
 * lat 50) in visualization (lon, lat) order, compared with
 * x = 1113194.9079, y = 6446275.8410 within 1e-3; prints the database
 * proj.db came from (a path under PROJ_DATA when set, else the embedded
 * copy) and OK. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <proj.h>

int main(void) {
    PJ_INFO info = proj_info();
    const char *env = getenv("PROJ_DATA");
    printf("PROJ %s, PROJ_DATA=%s\n", info.release, env ? env : "(unset)");
    PJ_CONTEXT *ctx = proj_context_create();
    PJ *p = proj_create_crs_to_crs(ctx, "EPSG:4326", "EPSG:3857", NULL);
    if (!p) {
        printf("FAIL: proj_create_crs_to_crs: %s\n",
               proj_context_errno_string(ctx, proj_context_errno(ctx)));
        return 1;
    }
    const char *db = proj_context_get_database_path(ctx);
    printf("database: %s\n", db ? db : "(null)");
    PJ *n = proj_normalize_for_visualization(ctx, p);
    proj_destroy(p);
    if (!n) {
        puts("FAIL: proj_normalize_for_visualization");
        return 1;
    }
    PJ_COORD c = proj_coord(10.0, 50.0, 0.0, 0.0);
    PJ_COORD r = proj_trans(n, PJ_FWD, c);
    printf("(10, 50) -> (%.4f, %.4f)\n", r.xy.x, r.xy.y);
    int ok = fabs(r.xy.x - 1113194.9079) < 1e-3 && fabs(r.xy.y - 6446275.8410) < 1e-3;
    proj_destroy(n);
    proj_context_destroy(ctx);
    if (!ok) {
        puts("FAIL: want (1113194.9079, 6446275.8410)");
        return 1;
    }
    puts("OK");
    return 0;
}
