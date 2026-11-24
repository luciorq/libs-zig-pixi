/* zig-udunits2 smoke test: write a two-entry unit database (meter, kilo),
   read it with ut_read_xml (expat), convert 2.5 km to m, prints OK. */
#include <stdio.h>
#include <math.h>
#include <udunits2.h>

static const char *xml =
    "<?xml version=\"1.0\" encoding=\"US-ASCII\"?>\n"
    "<unit-system>\n"
    "  <unit><base/><name><singular>meter</singular></name><symbol>m</symbol></unit>\n"
    "  <prefix><value>1e3</value><name>kilo</name><symbol>k</symbol></prefix>\n"
    "</unit-system>\n";

int main(void) {
    const char *path = "udunits2-smoke.xml";
    FILE *f = fopen(path, "w");
    if (!f || fputs(xml, f) < 0 || fclose(f) != 0) {
        puts("FAIL: cannot write the XML file");
        return 1;
    }
    ut_set_error_message_handler(ut_ignore);
    ut_system *sys = ut_read_xml(path);
    if (!sys) {
        printf("FAIL: ut_read_xml status %d\n", (int)ut_get_status());
        return 1;
    }
    ut_unit *km = ut_parse(sys, "km", UT_ASCII), *m = ut_parse(sys, "m", UT_ASCII);
    cv_converter *cv = km && m ? ut_get_converter(km, m) : NULL;
    double v = cv ? cv_convert_double(cv, 2.5) : -1.0;
    printf("udunits2: 2.5 km = %g m\n", v);
    if (fabs(v - 2500.0) > 1e-9) {
        puts("FAIL: wrong conversion");
        return 1;
    }
    cv_free(cv);
    ut_free(km);
    ut_free(m);
    ut_free_system(sys);
    remove(path);
    puts("OK");
    return 0;
}
