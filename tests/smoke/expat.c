/* zig-expat smoke test: parse a small document, count start elements and
   check the root's attribute, prints OK. */
#include <stdio.h>
#include <string.h>
#include <expat.h>

struct seen {
    int elements;
    int root_ok;
};

static void XMLCALL on_start(void *data, const XML_Char *name, const XML_Char **atts) {
    struct seen *s = data;
    s->elements++;
    if (strcmp(name, "library") == 0 && atts[0] && strcmp(atts[0], "name") == 0 &&
        strcmp(atts[1], "expat") == 0)
        s->root_ok = 1;
}

int main(void) {
    const char *doc = "<?xml version=\"1.0\"?>\n"
                      "<library name=\"expat\"><item>one</item><item>two</item>"
                      "<item><sub/></item></library>\n";
    struct seen s = {0, 0};
    XML_Parser p = XML_ParserCreate(NULL);
    if (!p) {
        puts("FAIL: XML_ParserCreate");
        return 1;
    }
    XML_SetUserData(p, &s);
    XML_SetStartElementHandler(p, on_start);
    if (XML_Parse(p, doc, (int)strlen(doc), 1) == XML_STATUS_ERROR) {
        printf("FAIL: %s at line %lu\n", XML_ErrorString(XML_GetErrorCode(p)),
               (unsigned long)XML_GetCurrentLineNumber(p));
        XML_ParserFree(p);
        return 1;
    }
    XML_ParserFree(p);
    if (s.elements != 5 || !s.root_ok) {
        printf("FAIL: %d start elements (want 5), root attribute ok %d\n", s.elements, s.root_ok);
        return 1;
    }
    printf("%s: %d start elements\n", XML_ExpatVersion(), s.elements);
    puts("OK");
    return 0;
}
