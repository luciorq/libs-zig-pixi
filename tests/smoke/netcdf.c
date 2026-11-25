/* zig-netcdf smoke test, in the temp directory: a netCDF-4 file with a
   deflate (zlib) and an szip (libaec) variable and attributes, a classic
   (CDF-1) and a CDF-5 file with attributes; each closed, reopened and read
   back (values, format, filters, attributes). An HDF4 file written with
   HDF4's SD API (zig-hdf4) and read back through nc_open (netCDF's HDF4
   support). Prints nc_inq_libvers and OK. DAP needs a server and is not
   tested here.
   netcdf.h before mfhdf.h: HDF4's netCDF-2 header (hdf4_netcdf.h) has
   netCDF's include guard _NETCDF_, so it is skipped and mfhdf.h builds on
   netcdf.h's nc_type and NC_* names, as in netCDF's own libhdf4. In the
   other order netcdf.h would be the one skipped. */
#include <stdio.h>
#include <string.h>
#include <windows.h>
#include <netcdf.h>
#include <netcdf_meta.h>
#include <mfhdf.h>

#define NX 40
#define NY 30

static int fails = 0;

static void expect(int ok, const char *what) {
    if (!ok) {
        printf("FAIL: %s\n", what);
        fails++;
    }
}

/* nc_* status: report the call and netCDF's message */
static int nc_ok(int st, const char *what) {
    if (st != NC_NOERR) {
        printf("FAIL: %s: %s\n", what, nc_strerror(st));
        fails++;
        return 0;
    }
    return 1;
}

static int data[NX][NY], back[NX][NY];
static char dir[MAX_PATH];

static void tmp_path(char *out, size_t n, const char *stem, const char *ext) {
    snprintf(out, n, "%snetcdf-smoke-%lu-%s.%s", dir, (unsigned long)GetCurrentProcessId(), stem, ext);
}

static void check_text_att(int ncid, int varid, const char *name, const char *want) {
    char text[128];
    size_t len = 0;
    memset(text, 0, sizeof text);
    expect(nc_ok(nc_inq_attlen(ncid, varid, name, &len), "nc_inq_attlen") && len == strlen(want) &&
               len < sizeof text && nc_ok(nc_get_att_text(ncid, varid, name, text), "nc_get_att_text") &&
               strcmp(text, want) == 0,
           name);
}

static void netcdf4(void) {
    char path[MAX_PATH + 64];
    tmp_path(path, sizeof path, "nc4", "nc");
    int ncid, dims[2], vdef, vsz;
    double scale = 0.25, scale_back = 0;
    if (!nc_ok(nc_create(path, NC_NETCDF4 | NC_CLOBBER, &ncid), "nc_create netCDF-4")) return;
    nc_ok(nc_def_dim(ncid, "x", NX, &dims[0]), "nc_def_dim x");
    nc_ok(nc_def_dim(ncid, "y", NY, &dims[1]), "nc_def_dim y");
    nc_ok(nc_def_var(ncid, "deflated", NC_INT, 2, dims, &vdef), "nc_def_var deflated");
    nc_ok(nc_def_var_deflate(ncid, vdef, 1, 1, 6), "nc_def_var_deflate");
    nc_ok(nc_def_var(ncid, "szipped", NC_INT, 2, dims, &vsz), "nc_def_var szipped");
    nc_ok(nc_def_var_szip(ncid, vsz, NC_SZIP_NN, 16), "nc_def_var_szip");
    nc_ok(nc_put_att_text(ncid, NC_GLOBAL, "title", strlen("zig-netcdf smoke"), "zig-netcdf smoke"),
          "nc_put_att_text");
    nc_ok(nc_put_att_double(ncid, vdef, "scale_factor", NC_DOUBLE, 1, &scale), "nc_put_att_double");
    nc_ok(nc_enddef(ncid), "nc_enddef netCDF-4");
    nc_ok(nc_put_var_int(ncid, vdef, &data[0][0]), "nc_put_var_int deflated");
    nc_ok(nc_put_var_int(ncid, vsz, &data[0][0]), "nc_put_var_int szipped");
    nc_ok(nc_close(ncid), "nc_close netCDF-4");

    if (!nc_ok(nc_open(path, NC_NOWRITE, &ncid), "nc_open netCDF-4")) return;
    int fmt = 0, shuffle = 0, deflate = 0, level = 0, mask = 0, ppb = 0;
    expect(nc_ok(nc_inq_format(ncid, &fmt), "nc_inq_format") && fmt == NC_FORMAT_NETCDF4, "netCDF-4 format");
    nc_ok(nc_inq_varid(ncid, "deflated", &vdef), "nc_inq_varid deflated");
    nc_ok(nc_inq_varid(ncid, "szipped", &vsz), "nc_inq_varid szipped");
    expect(nc_ok(nc_inq_var_deflate(ncid, vdef, &shuffle, &deflate, &level), "nc_inq_var_deflate") &&
               shuffle == 1 && deflate == 1 && level == 6,
           "deflate settings read back");
    expect(nc_ok(nc_inq_var_szip(ncid, vsz, &mask, &ppb), "nc_inq_var_szip") && (mask & NC_SZIP_NN) && ppb == 16,
           "szip settings read back");
    memset(back, 0, sizeof back);
    expect(nc_ok(nc_get_var_int(ncid, vdef, &back[0][0]), "nc_get_var_int deflated") &&
               memcmp(back, data, sizeof data) == 0,
           "deflated values read back");
    memset(back, 0, sizeof back);
    expect(nc_ok(nc_get_var_int(ncid, vsz, &back[0][0]), "nc_get_var_int szipped") &&
               memcmp(back, data, sizeof data) == 0,
           "szipped values read back");
    check_text_att(ncid, NC_GLOBAL, "title", "zig-netcdf smoke");
    expect(nc_ok(nc_get_att_double(ncid, vdef, "scale_factor", &scale_back), "nc_get_att_double") &&
               scale_back == scale,
           "scale_factor read back");
    nc_ok(nc_close(ncid), "nc_close netCDF-4 (read)");
    remove(path);
    printf("netCDF-4: deflate (level %d) and szip (mask %d, %d pixels per block) %d x %d int read back\n", level,
           mask, ppb, NX, NY);
}

/* classic model: CDF-1 (cmode 0, NC_FORMAT_CLASSIC) or CDF-5
   (NC_64BIT_DATA, NC_FORMAT_CDF5, with a CDF-5-only type) */
static void classic(int cmode, int want_fmt, const char *stem) {
    char path[MAX_PATH + 64];
    tmp_path(path, sizeof path, stem, "nc");
    int ncid, dims[2], v, v64 = -1;
    long long big[NX], big_back[NX];
    for (int i = 0; i < NX; i++) big[i] = (long long)i * 3000000000LL - 7;
    if (!nc_ok(nc_create(path, cmode | NC_CLOBBER, &ncid), "nc_create classic")) return;
    nc_ok(nc_def_dim(ncid, "x", NX, &dims[0]), "nc_def_dim x");
    nc_ok(nc_def_dim(ncid, "y", NY, &dims[1]), "nc_def_dim y");
    nc_ok(nc_def_var(ncid, "values", NC_INT, 2, dims, &v), "nc_def_var values");
    if (cmode & NC_64BIT_DATA) nc_ok(nc_def_var(ncid, "big", NC_INT64, 1, dims, &v64), "nc_def_var int64");
    nc_ok(nc_put_att_text(ncid, v, "units", strlen(stem), stem), "nc_put_att_text units");
    nc_ok(nc_enddef(ncid), "nc_enddef classic");
    nc_ok(nc_put_var_int(ncid, v, &data[0][0]), "nc_put_var_int classic");
    if (v64 >= 0) nc_ok(nc_put_var_longlong(ncid, v64, big), "nc_put_var_longlong");
    nc_ok(nc_close(ncid), "nc_close classic");

    if (!nc_ok(nc_open(path, NC_NOWRITE, &ncid), "nc_open classic")) return;
    int fmt = -1;
    expect(nc_ok(nc_inq_format(ncid, &fmt), "nc_inq_format classic") && fmt == want_fmt, "classic format");
    nc_ok(nc_inq_varid(ncid, "values", &v), "nc_inq_varid values");
    memset(back, 0, sizeof back);
    expect(nc_ok(nc_get_var_int(ncid, v, &back[0][0]), "nc_get_var_int classic") &&
               memcmp(back, data, sizeof data) == 0,
           "classic values read back");
    check_text_att(ncid, v, "units", stem);
    if (cmode & NC_64BIT_DATA) {
        nc_type t = 0;
        memset(big_back, 0, sizeof big_back);
        expect(nc_ok(nc_inq_varid(ncid, "big", &v64), "nc_inq_varid big") &&
                   nc_ok(nc_inq_vartype(ncid, v64, &t), "nc_inq_vartype") && t == NC_INT64 &&
                   nc_ok(nc_get_var_longlong(ncid, v64, big_back), "nc_get_var_longlong") &&
                   memcmp(big, big_back, sizeof big) == 0,
               "CDF-5 int64 values read back");
    }
    nc_ok(nc_close(ncid), "nc_close classic (read)");
    remove(path);
    printf("%s: format %d, %d x %d int%s read back\n", stem, fmt, NX, NY, (cmode & NC_64BIT_DATA) ? " and int64" : "");
}

/* HDF4: an SDS written with HDF4's SD API, read through netCDF */
static void hdf4(void) {
    char path[MAX_PATH + 64];
    tmp_path(path, sizeof path, "hdf4", "hdf");
    int32 dims[2] = {NX, NY}, start[2] = {0, 0};
    int32 sd = SDstart(path, DFACC_CREATE);
    if (sd == FAIL) {
        printf("FAIL: SDstart(%s, DFACC_CREATE)\n", path);
        fails++;
        return;
    }
    int32 sds = SDcreate(sd, "sds", DFNT_INT32, 2, dims);
    expect(sds != FAIL, "SDcreate");
    expect(SDwritedata(sds, start, NULL, dims, (VOIDP)data) != FAIL, "SDwritedata");
    expect(SDendaccess(sds) != FAIL, "SDendaccess");
    expect(SDend(sd) != FAIL, "SDend");

    int ncid, v, fmt = 0, ndims = 0;
    nc_type t = 0;
    if (!nc_ok(nc_open(path, NC_NOWRITE, &ncid), "nc_open HDF4")) return;
    expect(nc_ok(nc_inq_format_extended(ncid, &fmt, NULL), "nc_inq_format_extended") && fmt == NC_FORMATX_NC_HDF4,
           "HDF4 dispatch");
    expect(nc_ok(nc_inq_varid(ncid, "sds", &v), "nc_inq_varid sds") &&
               nc_ok(nc_inq_var(ncid, v, NULL, &t, &ndims, NULL, NULL), "nc_inq_var sds") && t == NC_INT &&
               ndims == 2,
           "HDF4 SDS as an NC_INT 2-D variable");
    memset(back, 0, sizeof back);
    expect(nc_ok(nc_get_var_int(ncid, v, &back[0][0]), "nc_get_var_int HDF4") && memcmp(back, data, sizeof data) == 0,
           "HDF4 values read back through netCDF");
    nc_ok(nc_close(ncid), "nc_close HDF4");
    remove(path);
    printf("HDF4: SDS %d x %d int32 written with SDwritedata, read back with nc_get_var_int\n", NX, NY);
}

int main(void) {
    DWORD dl = GetTempPathA(sizeof dir, dir);
    if (dl == 0 || dl >= sizeof dir) {
        puts("FAIL: GetTempPathA");
        return 1;
    }
    printf("netCDF %s\n", nc_inq_libvers());
    expect(strncmp(nc_inq_libvers(), NC_VERSION, strlen(NC_VERSION)) == 0, "library version is netcdf_meta.h's");
    expect(NC_HAS_NC4 && NC_HAS_HDF4 && NC_HAS_DAP2 && NC_HAS_DAP4 && NC_HAS_SZIP, "netcdf_meta.h features");

    for (int i = 0; i < NX; i++)
        for (int j = 0; j < NY; j++) data[i][j] = 1000 * i + j - 5000;

    netcdf4();
    classic(0, NC_FORMAT_CLASSIC, "cdf1");
    classic(NC_64BIT_DATA, NC_FORMAT_CDF5, "cdf5");
    hdf4();

    if (fails) return 1;
    puts("OK");
    return 0;
}
