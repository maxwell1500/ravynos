/*
 * locale_charset() for libcharset.1.dylib.
 *
 * GNU's libcharset answers with the current locale's codeset.  This system
 * has no nl_langinfo(CODESET); the environment is the only source, and UTF-8
 * is the default for every locale this system defines.
 */
#include <stdlib.h>
#include <string.h>
#include "localcharset.h"

const char *locale_charset(void)
{
    const char *lang = getenv("LC_ALL");
    const char *codeset = "";
    const char *dot;

    if (lang == NULL || *lang == '\0') {
        lang = getenv("LC_CTYPE");
    }
    if (lang == NULL || *lang == '\0') {
        lang = getenv("LANG");
    }
    if (lang != NULL && (dot = strchr(lang, '.')) != NULL) {
        codeset = dot + 1;
        if (strcmp(codeset, "UTF-8") == 0 || strcmp(codeset, "utf8") == 0 ||
            strcmp(codeset, "UTF8") == 0) {
            return "UTF-8";
        }
        return codeset;
    }
    return "UTF-8";
}
