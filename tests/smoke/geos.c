/* zig-geos smoke test (C API): buffer a point by 1 with 64 quadrant
 * segments, check the area is close to pi, prints OK. */
#include <math.h>
#include <stdio.h>
#include <geos_c.h>

int main(void) {
    GEOSContextHandle_t h = GEOS_init_r();
    if (!h) {
        puts("FAIL: GEOS_init_r");
        return 1;
    }
    GEOSCoordSequence *seq = GEOSCoordSeq_create_r(h, 1, 2);
    GEOSCoordSeq_setXY_r(h, seq, 0, 0.0, 0.0);
    GEOSGeometry *pt = GEOSGeom_createPoint_r(h, seq);
    GEOSGeometry *buf = GEOSBuffer_r(h, pt, 1.0, 64);
    double area = 0.0;
    if (!buf || !GEOSArea_r(h, buf, &area)) {
        puts("FAIL: GEOSBuffer_r/GEOSArea_r");
        return 1;
    }
    printf("GEOS %s: area of buffer(POINT (0 0), 1) = %.6f\n", GEOSversion(), area);
    int ok = fabs(area - 3.14159265358979) < 1e-3;
    GEOSGeom_destroy_r(h, buf);
    GEOSGeom_destroy_r(h, pt);
    GEOS_finish_r(h);
    if (!ok) {
        puts("FAIL: area is not about pi");
        return 1;
    }
    puts("OK");
    return 0;
}
