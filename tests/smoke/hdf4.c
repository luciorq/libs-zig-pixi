/* zig-hdf4 smoke test: in a new file in the temp directory (SD API), a
   2-D int32 SDS compressed with deflate (zlib) and one with szip (libaec)
   when the build can encode szip, a string attribute; the file closed,
   reopened and read back: values, compression type, attribute; the
   library version (Hgetlibversion) against 4.2.15; prints OK. */
#include <stdio.h>
#include <string.h>
#include <windows.h>
#include <mfhdf.h>
#include <szlib.h>

#define NX 40
#define NY 30

static int fails = 0;

static void expect(int ok, const char *what) {
    if (!ok) {
        printf("FAIL: %s\n", what);
        fails++;
    }
}

static int32 data[NX][NY], back[NX][NY];

static void write_sds(int32 sd, const char *name, comp_coder_t coder, comp_info *ci) {
    int32 dims[2] = {NX, NY}, start[2] = {0, 0};
    int32 sds = SDcreate(sd, name, DFNT_INT32, 2, dims);
    expect(sds != FAIL, "SDcreate");
    expect(SDsetcompress(sds, coder, ci) != FAIL, "SDsetcompress");
    expect(SDwritedata(sds, start, NULL, dims, (VOIDP)data) != FAIL, "SDwritedata");
    expect(SDendaccess(sds) != FAIL, "SDendaccess");
}

static void read_sds(int32 sd, const char *name, comp_coder_t want) {
    int32 dims[2] = {NX, NY}, start[2] = {0, 0};
    int32 idx = SDnametoindex(sd, name);
    expect(idx != FAIL, "SDnametoindex");
    int32 sds = SDselect(sd, idx);
    expect(sds != FAIL, "SDselect");
    comp_coder_t coder = COMP_CODE_INVALID;
    comp_info ci;
    memset(&ci, 0, sizeof ci);
    expect(SDgetcompinfo(sds, &coder, &ci) != FAIL && coder == want, "SDgetcompinfo coder");
    memset(back, 0, sizeof back);
    expect(SDreaddata(sds, start, NULL, dims, (VOIDP)back) != FAIL, "SDreaddata");
    expect(memcmp(back, data, sizeof data) == 0, "values read back");
    expect(SDendaccess(sds) != FAIL, "SDendaccess (read)");
    printf("%s: compression %d, %d x %d int32 read back\n", name, (int)coder, NX, NY);
}

int main(void) {
    char dir[MAX_PATH], path[MAX_PATH + 64];
    DWORD dl = GetTempPathA(sizeof dir, dir);
    if (dl == 0 || dl >= sizeof dir) {
        puts("FAIL: GetTempPathA");
        return 1;
    }
    snprintf(path, sizeof path, "%shdf4-smoke-%lu.hdf", dir, (unsigned long)GetCurrentProcessId());

    uint32 major = 0, minor = 0, release = 0;
    char version[128]; /* LIBVSTR_LEN (80, hfile.h) + 1 is enough */
    memset(version, 0, sizeof version);
    expect(Hgetlibversion(&major, &minor, &release, version) != FAIL, "Hgetlibversion");
    printf("%s (%u.%u.%u)\n", version, (unsigned)major, (unsigned)minor, (unsigned)release);
    expect(major == 4 && minor == 2 && release == 15, "library version 4.2.15");

    uint32 deflate_cfg = 0, szip_cfg = 0;
    expect(HCget_config_info(COMP_CODE_DEFLATE, &deflate_cfg) != FAIL &&
               (deflate_cfg & COMP_ENCODER_ENABLED),
           "deflate encoder");
    int szip = HCget_config_info(COMP_CODE_SZIP, &szip_cfg) != FAIL && (szip_cfg & COMP_ENCODER_ENABLED);
    expect(szip, "szip encoder (libaec)");

    for (int i = 0; i < NX; i++)
        for (int j = 0; j < NY; j++) data[i][j] = 1000 * i + j - 5000;

    int32 sd = SDstart(path, DFACC_CREATE);
    if (sd == FAIL) {
        printf("FAIL: SDstart(%s, DFACC_CREATE)\n", path);
        return 1;
    }
    comp_info ci;
    memset(&ci, 0, sizeof ci);
    ci.deflate.level = 6;
    write_sds(sd, "deflated", COMP_CODE_DEFLATE, &ci);
    if (szip) {
        memset(&ci, 0, sizeof ci);
        ci.szip.options_mask = SZ_NN_OPTION_MASK;
        ci.szip.pixels_per_block = 16;
        write_sds(sd, "szipped", COMP_CODE_SZIP, &ci);
    }
    const char *units = "zig-hdf4 smoke units";
    expect(SDsetattr(sd, "units", DFNT_CHAR8, (int32)strlen(units), units) != FAIL, "SDsetattr");
    expect(SDend(sd) != FAIL, "SDend");

    sd = SDstart(path, DFACC_READ);
    if (sd == FAIL) {
        printf("FAIL: SDstart(%s, DFACC_READ)\n", path);
        return 1;
    }
    read_sds(sd, "deflated", COMP_CODE_DEFLATE);
    if (szip) read_sds(sd, "szipped", COMP_CODE_SZIP);
    char name[H4_MAX_NC_NAME], text[64];
    int32 nt = 0, count = 0;
    int32 a = SDfindattr(sd, "units");
    expect(a != FAIL, "SDfindattr");
    expect(SDattrinfo(sd, a, name, &nt, &count) != FAIL && nt == DFNT_CHAR8 &&
               count == (int32)strlen(units),
           "SDattrinfo");
    memset(text, 0, sizeof text);
    expect(SDreadattr(sd, a, text) != FAIL && strcmp(text, units) == 0, "SDreadattr");
    expect(SDend(sd) != FAIL, "SDend (read)");
    remove(path);

    if (fails) return 1;
    puts("OK");
    return 0;
}
