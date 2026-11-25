/* zig-hdf5 smoke test: in a file in the temp directory, a chunked,
   deflate-compressed 2-D int dataset with an attribute (zlib through the
   deflate filter), the same ints through the szip filter (libaec) and an H5LT (hdf5_hl) double dataset; the file closed,
   reopened and read back: values, attribute, filter and a stored size
   below the raw size; the native types of the pre-generated H5Tinit.c
   against the compiler's (long is 4 bytes on Windows), the doubles also
   read as long double and the ints as long long (type conversion); the
   library version against the header's; prints OK. */
#include <stdio.h>
#include <string.h>
#include <windows.h>
#include <zlib.h>
#include <hdf5.h>
#include <hdf5_hl.h>

#define NX 64
#define NY 48

static int fails = 0;

static void expect(int ok, const char *what) {
    if (!ok) {
        printf("FAIL: %s\n", what);
        fails++;
    }
}

int main(void) {
    char dir[MAX_PATH], path[MAX_PATH + 64];
    DWORD dl = GetTempPathA(sizeof dir, dir);
    if (dl == 0 || dl >= sizeof dir) {
        puts("FAIL: GetTempPathA");
        return 1;
    }
    snprintf(path, sizeof path, "%shdf5-smoke-%lu.h5", dir, (unsigned long)GetCurrentProcessId());

    /* H5Tinit.c's native types are the compiler's */
    expect(H5Tget_size(H5T_NATIVE_INT) == sizeof(int), "H5T_NATIVE_INT size");
    expect(H5Tget_size(H5T_NATIVE_LONG) == sizeof(long), "H5T_NATIVE_LONG size");
    expect(H5Tget_size(H5T_NATIVE_LLONG) == sizeof(long long), "H5T_NATIVE_LLONG size");
    expect(H5Tget_size(H5T_NATIVE_LDOUBLE) == sizeof(long double), "H5T_NATIVE_LDOUBLE size");
    expect(H5Tget_precision(H5T_NATIVE_LDOUBLE) == (sizeof(long double) == 8 ? 64 : 80),
           "H5T_NATIVE_LDOUBLE precision");
    expect(H5Zfilter_avail(H5Z_FILTER_DEFLATE) > 0, "deflate filter available");
    unsigned szinfo = 0;
    expect(H5Zfilter_avail(H5Z_FILTER_SZIP) > 0 && H5Zget_filter_info(H5Z_FILTER_SZIP, &szinfo) >= 0 &&
               (szinfo & H5Z_FILTER_CONFIG_ENCODE_ENABLED),
           "szip filter available, with encoding");

    static int data[NX][NY], back[NX][NY];
    static double dd[NX], dback[NX];
    static long double ldback[NX];
    static long long llback[NX][NY];
    for (int i = 0; i < NX; i++) {
        for (int j = 0; j < NY; j++) data[i][j] = (i * NY + j) % 97 - 40;
        dd[i] = i * 0.25 - 3.0;
    }

    /* write: chunked + deflate int dataset with an attribute, H5LT dataset */
    hid_t f = H5Fcreate(path, H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    if (f < 0) {
        printf("FAIL: H5Fcreate %s\n", path);
        return 1;
    }
    hsize_t dims[2] = {NX, NY}, chunk[2] = {16, 16};
    hid_t space = H5Screate_simple(2, dims, NULL);
    hid_t dcpl = H5Pcreate(H5P_DATASET_CREATE);
    expect(H5Pset_chunk(dcpl, 2, chunk) >= 0, "H5Pset_chunk");
    expect(H5Pset_deflate(dcpl, 6) >= 0, "H5Pset_deflate");
    hid_t ds = H5Dcreate2(f, "ints", H5T_STD_I32LE, space, H5P_DEFAULT, dcpl, H5P_DEFAULT);
    expect(ds >= 0, "H5Dcreate2");
    expect(H5Dwrite(ds, H5T_NATIVE_INT, H5S_ALL, H5S_ALL, H5P_DEFAULT, data) >= 0, "H5Dwrite");
    hid_t aspace = H5Screate(H5S_SCALAR);
    hid_t attr = H5Acreate2(ds, "scale", H5T_IEEE_F64LE, aspace, H5P_DEFAULT, H5P_DEFAULT);
    double scale = 2.5;
    expect(attr >= 0 && H5Awrite(attr, H5T_NATIVE_DOUBLE, &scale) >= 0, "attribute write");
    H5Aclose(attr);
    H5Sclose(aspace);
    H5Dclose(ds);
    H5Pclose(dcpl);
    /* the same ints through the szip filter (libaec) */
    dcpl = H5Pcreate(H5P_DATASET_CREATE);
    expect(H5Pset_chunk(dcpl, 2, chunk) >= 0 && H5Pset_szip(dcpl, H5_SZIP_NN_OPTION_MASK, 16) >= 0, "H5Pset_szip");
    ds = H5Dcreate2(f, "ints_szip", H5T_STD_I32LE, space, H5P_DEFAULT, dcpl, H5P_DEFAULT);
    expect(ds >= 0 && H5Dwrite(ds, H5T_NATIVE_INT, H5S_ALL, H5S_ALL, H5P_DEFAULT, data) >= 0, "szip dataset write");
    H5Dclose(ds);
    H5Pclose(dcpl);
    H5Sclose(space);
    hsize_t ddims[1] = {NX};
    expect(H5LTmake_dataset_double(f, "/doubles", 1, ddims, dd) >= 0, "H5LTmake_dataset_double");
    expect(H5Fclose(f) >= 0, "H5Fclose");

    /* reopen and read back */
    f = H5Fopen(path, H5F_ACC_RDONLY, H5P_DEFAULT);
    expect(f >= 0, "H5Fopen");
    ds = H5Dopen2(f, "ints", H5P_DEFAULT);
    expect(ds >= 0, "H5Dopen2");
    expect(H5Dread(ds, H5T_NATIVE_INT, H5S_ALL, H5S_ALL, H5P_DEFAULT, back) >= 0, "H5Dread");
    expect(memcmp(data, back, sizeof data) == 0, "ints read back differ");
    expect(H5Dread(ds, H5T_NATIVE_LLONG, H5S_ALL, H5S_ALL, H5P_DEFAULT, llback) >= 0, "H5Dread as long long");
    int ll_ok = 1;
    for (int i = 0; i < NX; i++)
        for (int j = 0; j < NY; j++) ll_ok &= llback[i][j] == data[i][j];
    expect(ll_ok, "ints read as long long differ");
    hsize_t stored = H5Dget_storage_size(ds);
    expect(stored > 0 && stored < sizeof data, "deflate: stored size below the raw size");
    dcpl = H5Dget_create_plist(ds);
    unsigned flags, cd[4];
    size_t ncd = 4;
    char fname[64];
    expect(H5Pget_nfilters(dcpl) == 1 &&
               H5Pget_filter2(dcpl, 0, &flags, &ncd, cd, sizeof fname, fname, NULL) == H5Z_FILTER_DEFLATE,
           "deflate filter on the dataset");
    H5Pclose(dcpl);
    attr = H5Aopen(ds, "scale", H5P_DEFAULT);
    double scale_back = 0;
    expect(attr >= 0 && H5Aread(attr, H5T_NATIVE_DOUBLE, &scale_back) >= 0 && scale_back == scale,
           "attribute read back");
    H5Aclose(attr);
    H5Dclose(ds);
    memset(back, 0, sizeof back);
    ds = H5Dopen2(f, "ints_szip", H5P_DEFAULT);
    expect(ds >= 0 && H5Dread(ds, H5T_NATIVE_INT, H5S_ALL, H5S_ALL, H5P_DEFAULT, back) >= 0 &&
               memcmp(data, back, sizeof data) == 0,
           "szip ints read back");
    H5Dclose(ds);
    expect(H5LTread_dataset_double(f, "/doubles", dback) >= 0, "H5LTread_dataset_double");
    expect(memcmp(dd, dback, sizeof dd) == 0, "doubles read back differ");
    ds = H5Dopen2(f, "/doubles", H5P_DEFAULT);
    expect(ds >= 0 && H5Dread(ds, H5T_NATIVE_LDOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, ldback) >= 0,
           "H5Dread as long double");
    int ld_ok = 1;
    for (int i = 0; i < NX; i++) ld_ok &= ldback[i] == (long double)dd[i];
    expect(ld_ok, "doubles read as long double differ");
    H5Dclose(ds);
    H5Fclose(f);
    remove(path);

    unsigned maj, min, rel;
    expect(H5get_libversion(&maj, &min, &rel) >= 0, "H5get_libversion");
    expect(maj == H5_VERS_MAJOR && min == H5_VERS_MINOR && rel == H5_VERS_RELEASE, "library version differs from the header's");
    printf("HDF5 %u.%u.%u (header %s, zlib %s): %dx%d ints chunked+deflate -> %llu bytes stored, "
           "H5LT doubles, long double %u bytes\n",
           maj, min, rel, H5_VERS_INFO, zlibVersion(), NX, NY, (unsigned long long)stored,
           (unsigned)sizeof(long double));
    if (fails) return 1;
    puts("OK");
    return 0;
}
