/* zig-gdal smoke (DESIGN 5.10): GDAL's C API through `pkgconf --libs gdal`
 * alone. Registers all drivers, then
 *   - OSR: EPSG:4326 to WKT, and (10, 50) EPSG:4326 -> EPSG:3857 (PROJ,
 *     its proj.db from PROJ_DATA or embedded in libproj.a);
 *   - GPKG: a layer with one point in /vsimem/ (SQLite, PROJ), read back;
 *   - GTiff: a 4x3 Byte raster written to /vsimem/ and read back;
 *   - GeoJSON: a FeatureCollection read from a string;
 * and prints `OK` when all pass (exit 0), else exits 1. */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "cpl_conv.h"
#include "cpl_error.h"
#include "cpl_vsi.h"
#include "gdal.h"
#include "ogr_api.h"
#include "ogr_srs_api.h"

static int fails = 0;
#define CHECK(c, ...)                                   \
    do {                                                \
        if (!(c)) {                                     \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__); \
            fprintf(stderr, __VA_ARGS__);               \
            fprintf(stderr, " (%s)\n", CPLGetLastErrorMsg()); \
            fails++;                                    \
        }                                               \
    } while (0)

static void osr(void) {
    OGRSpatialReferenceH s = OSRNewSpatialReference(NULL);
    CHECK(OSRImportFromEPSG(s, 4326) == OGRERR_NONE, "EPSG:4326");
    char *wkt = NULL;
    CHECK(OSRExportToWkt(s, &wkt) == OGRERR_NONE && wkt && strstr(wkt, "WGS 84"), "WKT");
    if (wkt) printf("EPSG:4326 WKT: %.60s...\n", wkt);
    CPLFree(wkt);
    OGRSpatialReferenceH t = OSRNewSpatialReference(NULL);
    CHECK(OSRImportFromEPSG(t, 3857) == OGRERR_NONE, "EPSG:3857");
    OSRSetAxisMappingStrategy(s, OAMS_TRADITIONAL_GIS_ORDER);
    OSRSetAxisMappingStrategy(t, OAMS_TRADITIONAL_GIS_ORDER);
    OGRCoordinateTransformationH ct = OCTNewCoordinateTransformation(s, t);
    CHECK(ct != NULL, "transformation");
    if (ct) {
        double x = 10, y = 50;
        CHECK(OCTTransform(ct, 1, &x, &y, NULL), "transform");
        printf("(10, 50) -> (%.4f, %.4f)\n", x, y);
        CHECK(fabs(x - 1113194.9079) < 1e-3 && fabs(y - 6446275.8410) < 1e-3, "3857 value");
        OCTDestroyCoordinateTransformation(ct);
    }
    OSRDestroySpatialReference(t);
    OSRDestroySpatialReference(s);
}

static void gpkg(void) {
    const char *path = "/vsimem/smoke.gpkg";
    GDALDriverH d = GDALGetDriverByName("GPKG");
    CHECK(d != NULL, "GPKG driver");
    if (!d) return;
    GDALDatasetH ds = GDALCreate(d, path, 0, 0, 0, GDT_Unknown, NULL);
    CHECK(ds != NULL, "GPKG create");
    if (!ds) return;
    OGRSpatialReferenceH s = OSRNewSpatialReference(NULL);
    OSRImportFromEPSG(s, 4326);
    OGRLayerH l = GDALDatasetCreateLayer(ds, "pts", s, wkbPoint, NULL);
    OSRDestroySpatialReference(s);
    CHECK(l != NULL, "GPKG layer");
    if (l) {
        OGRFieldDefnH fd = OGR_Fld_Create("name", OFTString);
        OGR_L_CreateField(l, fd, TRUE);
        OGR_Fld_Destroy(fd);
        OGRFeatureH f = OGR_F_Create(OGR_L_GetLayerDefn(l));
        OGR_F_SetFieldString(f, 0, "a point");
        OGRGeometryH g = OGR_G_CreateGeometry(wkbPoint);
        OGR_G_SetPoint_2D(g, 0, 10, 50);
        OGR_F_SetGeometryDirectly(f, g);
        CHECK(OGR_L_CreateFeature(l, f) == OGRERR_NONE, "GPKG feature");
        OGR_F_Destroy(f);
    }
    GDALClose(ds);
    ds = GDALOpenEx(path, GDAL_OF_VECTOR, NULL, NULL, NULL);
    CHECK(ds != NULL, "GPKG reopen");
    if (!ds) return;
    l = GDALDatasetGetLayerByName(ds, "pts");
    CHECK(l && OGR_L_GetFeatureCount(l, TRUE) == 1, "GPKG count");
    if (l) {
        OGR_L_ResetReading(l);
        OGRFeatureH f = OGR_L_GetNextFeature(l);
        OGRGeometryH g = f ? OGR_F_GetGeometryRef(f) : NULL;
        CHECK(g && OGR_G_GetX(g, 0) == 10 && OGR_G_GetY(g, 0) == 50, "GPKG point");
        OGRSpatialReferenceH ls = OGR_L_GetSpatialRef(l);
        const char *auth = ls ? OSRGetAuthorityCode(ls, NULL) : NULL;
        CHECK(auth && strcmp(auth, "4326") == 0, "GPKG srs");
        printf("GPKG: %lld feature, '%s', srs EPSG:%s\n", (long long)OGR_L_GetFeatureCount(l, TRUE),
               f ? OGR_F_GetFieldAsString(f, 0) : "?", auth ? auth : "?");
        if (f) OGR_F_Destroy(f);
    }
    GDALClose(ds);
    VSIUnlink(path);
}

static void gtiff(void) {
    const char *path = "/vsimem/smoke.tif";
    GDALDriverH d = GDALGetDriverByName("GTiff");
    CHECK(d != NULL, "GTiff driver");
    if (!d) return;
    char *opts[] = {"COMPRESS=DEFLATE", NULL};
    GDALDatasetH ds = GDALCreate(d, path, 4, 3, 1, GDT_Byte, opts);
    CHECK(ds != NULL, "GTiff create");
    if (!ds) return;
    unsigned char buf[12];
    for (int i = 0; i < 12; i++) buf[i] = (unsigned char)(i * 7);
    double gt[6] = {10, 1, 0, 50, 0, -1};
    GDALSetGeoTransform(ds, gt);
    CHECK(GDALRasterIO(GDALGetRasterBand(ds, 1), GF_Write, 0, 0, 4, 3, buf, 4, 3, GDT_Byte, 0, 0) == CE_None, "GTiff write");
    GDALClose(ds);
    ds = GDALOpen(path, GA_ReadOnly);
    CHECK(ds != NULL, "GTiff reopen");
    if (!ds) return;
    unsigned char back[12] = {0};
    CHECK(GDALRasterIO(GDALGetRasterBand(ds, 1), GF_Read, 0, 0, 4, 3, back, 4, 3, GDT_Byte, 0, 0) == CE_None, "GTiff read");
    CHECK(memcmp(buf, back, 12) == 0, "GTiff values");
    printf("GTiff: %dx%d, driver %s, pixel(3,2) = %d\n", GDALGetRasterXSize(ds), GDALGetRasterYSize(ds),
           GDALGetDriverShortName(GDALGetDatasetDriver(ds)), back[11]);
    GDALClose(ds);
    VSIUnlink(path);
}

static void geojson(void) {
    const char *js =
        "{\"type\":\"FeatureCollection\",\"features\":["
        "{\"type\":\"Feature\",\"properties\":{\"v\":1},\"geometry\":{\"type\":\"Point\",\"coordinates\":[1,2]}},"
        "{\"type\":\"Feature\",\"properties\":{\"v\":2},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[0,0],[3,4]]}}]}";
    GDALDatasetH ds = GDALOpenEx(js, GDAL_OF_VECTOR, NULL, NULL, NULL);
    CHECK(ds != NULL, "GeoJSON open");
    if (!ds) return;
    OGRLayerH l = GDALDatasetGetLayer(ds, 0);
    CHECK(l && OGR_L_GetFeatureCount(l, TRUE) == 2, "GeoJSON count");
    double len = 0;
    if (l) {
        OGRFeatureH f;
        OGR_L_ResetReading(l);
        while ((f = OGR_L_GetNextFeature(l)) != NULL) {
            OGRGeometryH g = OGR_F_GetGeometryRef(f);
            if (g && wkbFlatten(OGR_G_GetGeometryType(g)) == wkbLineString) len = OGR_G_Length(g);
            OGR_F_Destroy(f);
        }
    }
    CHECK(len == 5, "GeoJSON line length");
    printf("GeoJSON: driver %s, %lld features, line length %g\n",
           GDALGetDriverShortName(GDALGetDatasetDriver(ds)), l ? (long long)OGR_L_GetFeatureCount(l, TRUE) : -1LL, len);
    GDALClose(ds);
}

int main(void) {
    GDALAllRegister();
    const char *gd = CPLGetConfigOption("GDAL_DATA", NULL);
    const char *pd = CPLGetConfigOption("PROJ_DATA", NULL);
    printf("%s, GDAL_DATA=%s, PROJ_DATA=%s\n", GDALVersionInfo("--version"), gd ? gd : "(unset)", pd ? pd : "(unset)");
    int n = GDALGetDriverCount();
    printf("drivers: %d\n", n);
    CHECK(n > 100, "driver count");
    const char *xsd = CPLFindFile("gdal", "gdalvrt.xsd");
    printf("gdalvrt.xsd: %s\n", xsd ? xsd : "(not found as a file)");
    osr();
    gpkg();
    gtiff();
    geojson();
    if (fails) {
        printf("%d check(s) failed\n", fails);
        return 1;
    }
    printf("OK\n");
    return 0;
}
