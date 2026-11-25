/* zig-libxml2 smoke test: an in-memory ISO-8859-1 document (built-in
   decoder) and a Shift_JIS one (through libiconv) parse, their node values
   are the expected UTF-8 bytes, an XPath query finds the nodes, and the
   same document written gzip- and xz-compressed to files reads back through
   xmlReadFile (zlib, liblzma); prints OK. */
#include <stdio.h>
#include <string.h>
#include <lzma.h>
#include <zlib.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlversion.h>
#include <libxml/xpath.h>

static const char latin1_doc[] =
    "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n"
    "<root><item id=\"a\">caf\xe9</item><item id=\"b\">\xfc" "ber</item></root>\n";
/* "日本語" in Shift_JIS */
static const char sjis_doc[] =
    "<?xml version=\"1.0\" encoding=\"Shift_JIS\"?>\n"
    "<root><item id=\"ja\">\x93\xfa\x96\x7b\x8c\xea</item></root>\n";

/* the string value of the XPath expression's first node, or NULL */
static xmlChar *xpath_first(xmlDocPtr doc, const char *expr, int *count) {
    xmlXPathContextPtr ctx = xmlXPathNewContext(doc);
    xmlXPathObjectPtr obj = ctx ? xmlXPathEvalExpression((const xmlChar *)expr, ctx) : NULL;
    xmlChar *v = NULL;
    *count = 0;
    if (obj && obj->type == XPATH_NODESET && obj->nodesetval) {
        *count = obj->nodesetval->nodeNr;
        if (*count > 0) v = xmlNodeGetContent(obj->nodesetval->nodeTab[0]);
    }
    xmlXPathFreeObject(obj);
    xmlXPathFreeContext(ctx);
    return v;
}

static int check(xmlDocPtr doc, const char *what, const char *expr, int want_count, const char *want) {
    int n;
    xmlChar *v = xpath_first(doc, expr, &n);
    int ok = v && n == want_count && strcmp((const char *)v, want) == 0;
    if (!ok) printf("FAIL: %s: %s gives %d nodes, first '%s'\n", what, expr, n, v ? (const char *)v : "(null)");
    else printf("%s: %s -> %d node(s)\n", what, expr, n);
    xmlFree(v);
    return ok ? 0 : 1;
}

static int check_latin1(xmlDocPtr doc, const char *what) {
    if (!doc) {
        printf("FAIL: %s: not parsed\n", what);
        return 1;
    }
    int fails = check(doc, what, "//item", 2, "caf\xc3\xa9");
    fails += check(doc, what, "//item[@id='b']", 1, "\xc3\xbc" "ber");
    xmlFreeDoc(doc);
    return fails;
}

int main(void) {
    LIBXML_TEST_VERSION
    int fails = 0;

    fails += check_latin1(xmlReadMemory(latin1_doc, (int)strlen(latin1_doc), "latin1.xml", NULL, 0), "ISO-8859-1");

    xmlCharEncodingHandlerPtr h = xmlFindCharEncodingHandler("SHIFT_JIS");
    if (!h) {
        puts("FAIL: no SHIFT_JIS encoding handler (iconv)");
        return 1;
    }
    xmlCharEncCloseFunc(h);
    xmlDocPtr ja = xmlReadMemory(sjis_doc, (int)strlen(sjis_doc), "sjis.xml", NULL, 0);
    if (!ja) {
        puts("FAIL: Shift_JIS: not parsed");
        return 1;
    }
    fails += check(ja, "Shift_JIS", "/root/item[@id='ja']", 1, "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e");
    xmlFreeDoc(ja);

    /* gzip: written with zlib's gzopen, read through libxml2's xzlib/zlib
       file input */
    const char *gz = "libxml2-smoke.xml.gz";
    gzFile g = gzopen(gz, "wb9");
    if (!g || gzwrite(g, latin1_doc, (unsigned)strlen(latin1_doc)) != (int)strlen(latin1_doc) || gzclose(g) != Z_OK) {
        puts("FAIL: gzip write");
        return 1;
    }
    fails += check_latin1(xmlReadFile(gz, NULL, 0), "gzip file");
    remove(gz);

    /* xz: one .xz stream from liblzma, read through libxml2's xzlib */
    unsigned char packed[1024];
    size_t packed_len = 0;
    if (lzma_easy_buffer_encode(6, LZMA_CHECK_CRC64, NULL, (const uint8_t *)latin1_doc, strlen(latin1_doc), packed,
                                &packed_len, sizeof packed) != LZMA_OK) {
        puts("FAIL: lzma_easy_buffer_encode");
        return 1;
    }
    const char *xz = "libxml2-smoke.xml.xz";
    FILE *f = fopen(xz, "wb");
    if (!f || fwrite(packed, 1, packed_len, f) != packed_len || fclose(f) != 0) {
        puts("FAIL: xz write");
        return 1;
    }
    fails += check_latin1(xmlReadFile(xz, NULL, 0), "xz file");
    remove(xz);

    xmlCleanupParser();
    printf("libxml2 %s (header %s)\n", xmlParserVersion, LIBXML_DOTTED_VERSION);
    if (fails) return 1;
    puts("OK");
    return 0;
}
