/*
 * libiconv.2.dylib for ravynOS.
 *
 * macOS clients record /usr/lib/libiconv.2.dylib at compatibility 7.0.0 (the
 * ABI libiconv has carried since 2009) and call the POSIX iconv() entry
 * points.  Nothing in this tree implemented them: no libSystem export, no
 * libiconv.  This file is the implementation.
 *
 * What it converts directly:
 *   UTF-8, UTF-16/16LE/16BE, UTF-32/32LE/32BE, UCS-2/2LE/2BE, UCS-4,
 *   US-ASCII, ISO-8859-1/LATIN1, ISO-8859-15, WINDOWS-1252/CP1252,
 *   MACINTOSH/MACROMAN, and the WCHAR_T/CHAR pseudo-encodings.
 *
 * Anything else is handed to ICU's converter engine
 * (ucnv_convertEx), which is already on the system as libicucore.A.dylib and
 * covers every charset ICU knows (Shift_JIS, EUC-JP, GB18030, KOI8-R, …).
 * That is a dlopen, not a link: libiconv must load on a system image that
 * does not carry ICU.
 *
 * Semantics follow POSIX and GNU libiconv: EILSEQ for invalid input, EINVAL
 * for an incomplete sequence at the end of the buffer, E2BIG when the output
 * buffer fills; iconv(cd, NULL, NULL, NULL, NULL) resets the conversion
 * state.  //TRANSLIT and //IGNORE suffixes are accepted; TRANSLIT is treated
 * as IGNORE for unrepresentable characters only when requested, and IGNORE
 * skips invalid input instead of failing.
 */

#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "iconv.h"

enum enc_kind {
    ENC_UTF8,
    ENC_UTF16,
    ENC_UTF16LE,
    ENC_UTF16BE,
    ENC_UTF32,
    ENC_UTF32LE,
    ENC_UTF32BE,
    ENC_UCS2,
    ENC_UCS2LE,
    ENC_UCS2BE,
    ENC_ASCII,
    ENC_LATIN1,
    ENC_LATIN9,
    ENC_CP1252,
    ENC_MACROMAN,
    ENC_WCHAR,
    ENC_ICU               /* handled by libicucore */
};

struct iconv_handle {
    enum enc_kind from;
    enum enc_kind to;
    int ignore;                 /* //IGNORE: drop invalid input */
    int translit;               /* //TRANSLIT */
    /* ICU path */
    void *icu_from;
    void *icu_to;
    char *icu_from_name;
    char *icu_to_name;
    char *pivot;                /* UTF-16 pivot buffer for ucnv_convertEx */
    /* Streaming state for UTF-16/32 with BOM, and for ICU */
    unsigned int state;
    unsigned int codepoint;
    unsigned int pending_units;
    unsigned short pending_surrogate;
};

/* ---------------------------------------------------------------- ICU glue */

struct icu_api {
    void *(*ucnv_open)(const char *, int *);
    void (*ucnv_close)(void *);
    const char *(*ucnv_convertEx)(void *dst, void *src,
                                  char **target, const char *targetLimit,
                                  const char **source, const char *sourceLimit,
                                  char *pivotStart, char **pivotSource,
                                  char **pivotTarget, const char *pivotLimit,
                                  int reset, int flush, int *err);
    void (*ucnv_reset)(void *);
    void (*ucnv_resetToUnicode)(void *);
    void (*ucnv_resetFromUnicode)(void *);
    int (*ucnv_setToUCallBack)(void *, int, const void *, const void *, void **, int *);
    int (*ucnv_setFromUCallBack)(void *, int, const void *, const void *, void **, int *);
    int (*ucnv_getMaxCharSize)(const void *);
};

static struct icu_api *g_icu;

static struct icu_api *icu_load(void)
{
    static int tried;
    static struct icu_api api;
    void *lib;

    if (tried) {
        return g_icu;
    }
    tried = 1;
    lib = dlopen("/usr/lib/libicucore.A.dylib", RTLD_LAZY);
    if (lib == NULL) {
        lib = dlopen("libicucore.A.dylib", RTLD_LAZY);
    }
    if (lib == NULL) {
        return NULL;
    }
    api.ucnv_open = (void *(*)(const char *, int *))dlsym(lib, "ucnv_open");
    api.ucnv_close = (void (*)(void *))dlsym(lib, "ucnv_close");
    api.ucnv_convertEx = (const char *(*)(void *, void *, char **, const char *,
                                          const char **, const char *,
                                          char *, char **, char **, const char *,
                                          int, int, int *))dlsym(lib, "ucnv_convertEx");
    api.ucnv_reset = (void (*)(void *))dlsym(lib, "ucnv_reset");
    api.ucnv_resetToUnicode = (void (*)(void *))dlsym(lib, "ucnv_resetToUnicode");
    api.ucnv_resetFromUnicode = (void (*)(void *))dlsym(lib, "ucnv_resetFromUnicode");
    api.ucnv_setToUCallBack = (int (*)(void *, int, const void *, const void *, void **, int *))
        dlsym(lib, "ucnv_setToUCallBack");
    api.ucnv_setFromUCallBack = (int (*)(void *, int, const void *, const void *, void **, int *))
        dlsym(lib, "ucnv_setFromUCallBack");
    api.ucnv_getMaxCharSize = (int (*)(const void *))dlsym(lib, "ucnv_getMaxCharSize");

    if (api.ucnv_open == NULL || api.ucnv_convertEx == NULL ||
        api.ucnv_close == NULL) {
        return NULL;
    }
    g_icu = &api;
    return g_icu;
}

/* ------------------------------------------------------------- name parsing */

static void strip_suffixes(char *name, struct iconv_handle *h)
{
    char *slash;

    for (;;) {
        slash = strstr(name, "//");
        if (slash == NULL) {
            break;
        }
        *slash = '\0';
        slash += 2;
        if (strcasecmp(slash, "TRANSLIT") == 0) {
            h->translit = 1;
        } else if (strcasecmp(slash, "IGNORE") == 0) {
            h->ignore = 1;
        }
        /* Any other suffix is ignored, as GNU libiconv does. */
    }
}

static enum enc_kind kind_from_name(const char *name)
{
    if (strcasecmp(name, "UTF-8") == 0 || strcasecmp(name, "UTF8") == 0)
        return ENC_UTF8;
    if (strcasecmp(name, "UTF-16") == 0 || strcasecmp(name, "UTF16") == 0)
        return ENC_UTF16;
    if (strcasecmp(name, "UTF-16LE") == 0)
        return ENC_UTF16LE;
    if (strcasecmp(name, "UTF-16BE") == 0)
        return ENC_UTF16BE;
    if (strcasecmp(name, "UTF-32") == 0 || strcasecmp(name, "UTF32") == 0)
        return ENC_UTF32;
    if (strcasecmp(name, "UTF-32LE") == 0)
        return ENC_UTF32LE;
    if (strcasecmp(name, "UTF-32BE") == 0)
        return ENC_UTF32BE;
    if (strcasecmp(name, "UCS-2") == 0 || strcasecmp(name, "UCS2") == 0)
        return ENC_UCS2;
    if (strcasecmp(name, "UCS-2LE") == 0)
        return ENC_UCS2LE;
    if (strcasecmp(name, "UCS-2BE") == 0)
        return ENC_UCS2BE;
    if (strcasecmp(name, "UCS-4") == 0 || strcasecmp(name, "UCS-4LE") == 0)
        return ENC_UTF32LE;
    if (strcasecmp(name, "UCS-4BE") == 0)
        return ENC_UTF32BE;
    if (strcasecmp(name, "US-ASCII") == 0 || strcasecmp(name, "ASCII") == 0 ||
        strcasecmp(name, "ANSI_X3.4-1968") == 0 || strcasecmp(name, "646") == 0)
        return ENC_ASCII;
    if (strcasecmp(name, "ISO-8859-1") == 0 || strcasecmp(name, "ISO8859-1") == 0 ||
        strcasecmp(name, "LATIN1") == 0 || strcasecmp(name, "L1") == 0 ||
        strcasecmp(name, "CP819") == 0)
        return ENC_LATIN1;
    if (strcasecmp(name, "ISO-8859-15") == 0 || strcasecmp(name, "LATIN9") == 0 ||
        strcasecmp(name, "L9") == 0)
        return ENC_LATIN9;
    if (strcasecmp(name, "WINDOWS-1252") == 0 || strcasecmp(name, "CP1252") == 0 ||
        strcasecmp(name, "MS-ANSI") == 0)
        return ENC_CP1252;
    if (strcasecmp(name, "MACINTOSH") == 0 || strcasecmp(name, "MAC") == 0 ||
        strcasecmp(name, "MACROMAN") == 0 || strcasecmp(name, "CSMACINTOSH") == 0)
        return ENC_MACROMAN;
    if (strcasecmp(name, "WCHAR_T") == 0 || strcasecmp(name, "WCHAR-T") == 0)
        return ENC_WCHAR;
    if (strcasecmp(name, "CHAR") == 0 || strcasecmp(name, "CHARSET") == 0)
        return ENC_LATIN1;
    return ENC_ICU;
}

/* ----------------------------------------------------------- single codecs */

static const unsigned short latin1_table[32] = {
    /* The 0x80..0x9F range of Windows-1252 and MacRoman differ; this table is
     * cp1252's. */
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
};

static unsigned int cp1252_to_ucs(unsigned char c)
{
    if (c >= 0x80 && c <= 0x9F) {
        return latin1_table[c - 0x80];
    }
    return c;
}

static int ucs_to_cp1252(unsigned int ucs, unsigned char *out)
{
    int i;
    if (ucs < 0x80 || (ucs >= 0xA0 && ucs <= 0xFF)) {
        *out = (unsigned char)ucs;
        return 1;
    }
    for (i = 0; i < 32; i++) {
        if (latin1_table[i] == ucs) {
            *out = (unsigned char)(0x80 + i);
            return 1;
        }
    }
    return 0;
}

/* MacRoman 0x80..0xFF to Unicode. */
static const unsigned short macroman_table[128] = {
    0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1,
    0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8,
    0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3,
    0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC,
    0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF,
    0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,
    0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211,
    0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x03A9, 0x00E6, 0x00F8,
    0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB,
    0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153,
    0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA,
    0x00FF, 0x0178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
    0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1,
    0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4,
    0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC,
    0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7
};

static unsigned int macroman_to_ucs(unsigned char c)
{
    return (c < 0x80) ? c : macroman_table[c - 0x80];
}

static int ucs_to_macroman(unsigned int ucs, unsigned char *out)
{
    int i;
    if (ucs < 0x80) {
        *out = (unsigned char)ucs;
        return 1;
    }
    for (i = 0; i < 128; i++) {
        if (macroman_table[i] == ucs) {
            *out = (unsigned char)(0x80 + i);
            return 1;
        }
    }
    return 0;
}

/* UTF-8 decode one scalar. Returns bytes consumed, 0 = incomplete,
 * -1 = invalid. */
static int utf8_decode(const unsigned char *s, size_t n, unsigned int *out)
{
    unsigned int cp;
    int extra, i;

    if (n == 0) {
        return 0;
    }
    if (s[0] < 0x80) {
        *out = s[0];
        return 1;
    }
    if ((s[0] & 0xE0) == 0xC0) {
        cp = s[0] & 0x1F; extra = 1;
    } else if ((s[0] & 0xF0) == 0xE0) {
        cp = s[0] & 0x0F; extra = 2;
    } else if ((s[0] & 0xF8) == 0xF0) {
        cp = s[0] & 0x07; extra = 3;
    } else {
        return -1;
    }
    if (n < (size_t)(extra + 1)) {
        return 0;
    }
    for (i = 1; i <= extra; i++) {
        if ((s[i] & 0xC0) != 0x80) {
            return -1;
        }
        cp = (cp << 6) | (s[i] & 0x3F);
    }
    /* Reject overlong forms and surrogates. */
    if ((extra == 1 && cp < 0x80) || (extra == 2 && cp < 0x800) ||
        (extra == 3 && cp < 0x10000) || cp > 0x10FFFF ||
        (cp >= 0xD800 && cp <= 0xDFFF)) {
        return -1;
    }
    *out = cp;
    return extra + 1;
}

static int utf8_encode(unsigned int cp, unsigned char *out)
{
    if (cp < 0x80) {
        out[0] = (unsigned char)cp;
        return 1;
    }
    if (cp < 0x800) {
        out[0] = (unsigned char)(0xC0 | (cp >> 6));
        out[1] = (unsigned char)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (unsigned char)(0xE0 | (cp >> 12));
        out[1] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (unsigned char)(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (unsigned char)(0xF0 | (cp >> 18));
    out[1] = (unsigned char)(0x80 | ((cp >> 12) & 0x3F));
    out[2] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
    out[3] = (unsigned char)(0x80 | (cp & 0x3F));
    return 4;
}

/* Read one scalar from the source encoding.  Returns:
 *  >0 bytes consumed
 *   0 incomplete input (EINVAL)
 *  -1 invalid input (EILSEQ) */
static int decode_one(struct iconv_handle *h, const unsigned char *s, size_t n,
                      unsigned int *out)
{
    switch (h->from) {
    case ENC_UTF8:
        return utf8_decode(s, n, out);
    case ENC_ASCII:
        if (n < 1) return 0;
        if (s[0] > 0x7F) return -1;
        *out = s[0];
        return 1;
    case ENC_LATIN1:
        if (n < 1) return 0;
        *out = s[0];
        return 1;
    case ENC_LATIN9: {
        if (n < 1) return 0;
        if (s[0] == 0xA4) { *out = 0x20AC; return 1; }
        if (s[0] == 0xA6) { *out = 0x0160; return 1; }
        if (s[0] == 0xA8) { *out = 0x0161; return 1; }
        if (s[0] == 0xB4) { *out = 0x017D; return 1; }
        if (s[0] == 0xB8) { *out = 0x017E; return 1; }
        if (s[0] == 0xBC) { *out = 0x0152; return 1; }
        if (s[0] == 0xBD) { *out = 0x0153; return 1; }
        if (s[0] == 0xBE) { *out = 0x0178; return 1; }
        *out = s[0];
        return 1;
    }
    case ENC_CP1252:
        if (n < 1) return 0;
        *out = cp1252_to_ucs(s[0]);
        return 1;
    case ENC_MACROMAN:
        if (n < 1) return 0;
        *out = macroman_to_ucs(s[0]);
        return 1;
    case ENC_UTF16:
    case ENC_UTF16LE:
    case ENC_UTF16BE:
    case ENC_UCS2:
    case ENC_UCS2LE:
    case ENC_UCS2BE: {
        unsigned int unit, unit2;
        int be = (h->from == ENC_UTF16BE || h->from == ENC_UCS2BE);
        if (n < 2) return 0;
        unit = be ? ((s[0] << 8) | s[1]) : (s[0] | (s[1] << 8));
        if (unit >= 0xD800 && unit <= 0xDBFF) {
            if (h->from == ENC_UCS2 || h->from == ENC_UCS2LE ||
                h->from == ENC_UCS2BE) return -1;
            if (n < 4) return 0;
            unit2 = be ? ((s[2] << 8) | s[3]) : (s[2] | (s[3] << 8));
            if (unit2 < 0xDC00 || unit2 > 0xDFFF) return -1;
            *out = 0x10000 + ((unit - 0xD800) << 10) + (unit2 - 0xDC00);
            return 4;
        }
        if (unit >= 0xDC00 && unit <= 0xDFFF) return -1;
        *out = unit;
        return 2;
    }
    case ENC_UTF32:
    case ENC_UTF32LE:
    case ENC_UTF32BE: {
        unsigned int v;
        int be = (h->from == ENC_UTF32BE);
        if (n < 4) return 0;
        v = be ? ((unsigned int)s[0] << 24 | (unsigned int)s[1] << 16 |
                  (unsigned int)s[2] << 8 | s[3])
               : ((unsigned int)s[3] << 24 | (unsigned int)s[2] << 16 |
                  (unsigned int)s[1] << 8 | s[0]);
        if (v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)) return -1;
        *out = v;
        return 4;
    }
    case ENC_WCHAR: {
        wchar_t wc;
        if (n < sizeof(wchar_t)) return 0;
        memcpy(&wc, s, sizeof(wc));
        *out = (unsigned int)wc;
        return (int)sizeof(wchar_t);
    }
    default:
        return -1;
    }
}

/* Encode one scalar.  Returns bytes written, or 0 when the character has no
 * representation in the target (EILSEQ). */
static int encode_one(struct iconv_handle *h, unsigned int cp,
                      unsigned char *out, size_t room)
{
    switch (h->to) {
    case ENC_UTF8: {
        unsigned char tmp[4];
        int n = utf8_encode(cp, tmp);
        if ((size_t)n > room) return -2;      /* E2BIG */
        memcpy(out, tmp, (size_t)n);
        return n;
    }
    case ENC_ASCII:
        if (cp > 0x7F) return 0;
        if (room < 1) return -2;
        out[0] = (unsigned char)cp;
        return 1;
    case ENC_LATIN1:
        if (cp > 0xFF) return 0;
        if (room < 1) return -2;
        out[0] = (unsigned char)cp;
        return 1;
    case ENC_LATIN9: {
        unsigned char c;
        if (cp == 0x20AC) c = 0xA4;
        else if (cp == 0x0160) c = 0xA6;
        else if (cp == 0x0161) c = 0xA8;
        else if (cp == 0x017D) c = 0xB4;
        else if (cp == 0x017E) c = 0xB8;
        else if (cp == 0x0152) c = 0xBC;
        else if (cp == 0x0153) c = 0xBD;
        else if (cp == 0x0178) c = 0xBE;
        else if (cp <= 0xFF) c = (unsigned char)cp;
        else return 0;
        if (room < 1) return -2;
        out[0] = c;
        return 1;
    }
    case ENC_CP1252: {
        unsigned char c;
        if (!ucs_to_cp1252(cp, &c)) return 0;
        if (room < 1) return -2;
        out[0] = c;
        return 1;
    }
    case ENC_MACROMAN: {
        unsigned char c;
        if (!ucs_to_macroman(cp, &c)) return 0;
        if (room < 1) return -2;
        out[0] = c;
        return 1;
    }
    case ENC_UTF16:
    case ENC_UTF16LE:
    case ENC_UTF16BE:
    case ENC_UCS2:
    case ENC_UCS2LE:
    case ENC_UCS2BE: {
        int be = (h->to == ENC_UTF16BE || h->to == ENC_UCS2BE);
        unsigned int units[2];
        int count;
        if (cp < 0x10000) {
            if ((h->to == ENC_UCS2 || h->to == ENC_UCS2LE || h->to == ENC_UCS2BE) &&
                cp > 0xFFFF) return 0;
            units[0] = cp; count = 1;
        } else {
            if (h->to == ENC_UCS2 || h->to == ENC_UCS2LE || h->to == ENC_UCS2BE)
                return 0;
            units[0] = 0xD800 + ((cp - 0x10000) >> 10);
            units[1] = 0xDC00 + ((cp - 0x10000) & 0x3FF);
            count = 2;
        }
        if (room < (size_t)count * 2) return -2;
        for (int i = 0; i < count; i++) {
            if (be) {
                out[i * 2] = (unsigned char)(units[i] >> 8);
                out[i * 2 + 1] = (unsigned char)units[i];
            } else {
                out[i * 2] = (unsigned char)units[i];
                out[i * 2 + 1] = (unsigned char)(units[i] >> 8);
            }
        }
        return count * 2;
    }
    case ENC_UTF32:
    case ENC_UTF32LE:
    case ENC_UTF32BE: {
        int be = (h->to == ENC_UTF32BE);
        if (room < 4) return -2;
        if (be) {
            out[0] = (unsigned char)(cp >> 24);
            out[1] = (unsigned char)(cp >> 16);
            out[2] = (unsigned char)(cp >> 8);
            out[3] = (unsigned char)cp;
        } else {
            out[0] = (unsigned char)cp;
            out[1] = (unsigned char)(cp >> 8);
            out[2] = (unsigned char)(cp >> 16);
            out[3] = (unsigned char)(cp >> 24);
        }
        return 4;
    }
    case ENC_WCHAR: {
        wchar_t wc = (wchar_t)cp;
        if (room < sizeof(wchar_t)) return -2;
        memcpy(out, &wc, sizeof(wc));
        return (int)sizeof(wc);
    }
    default:
        return 0;
    }
}

/* --------------------------------------------------------------- public API */

iconv_t iconv_open(const char *tocode, const char *fromcode)
{
    struct iconv_handle *h;
    char *to, *from;

    if (tocode == NULL || fromcode == NULL) {
        errno = EINVAL;
        return (iconv_t)-1;
    }
    h = (struct iconv_handle *)calloc(1, sizeof(*h));
    if (h == NULL) {
        errno = ENOMEM;
        return (iconv_t)-1;
    }
    to = strdup(tocode);
    from = strdup(fromcode);
    if (to == NULL || from == NULL) {
        free(to); free(from); free(h);
        errno = ENOMEM;
        return (iconv_t)-1;
    }
    strip_suffixes(to, h);
    strip_suffixes(from, h);
    h->to = kind_from_name(to);
    h->from = kind_from_name(from);

    if (h->to == ENC_ICU || h->from == ENC_ICU) {
        struct icu_api *icu = icu_load();
        int err = 0;
        if (icu == NULL) {
            free(to); free(from); free(h);
            errno = EINVAL;
            return (iconv_t)-1;
        }
        /* Both sides go through ICU on this path: ICU also knows the
         * encodings this file implements natively, so a mixed conversion is
         * the same code as an ICU-only one instead of a second bridge. */
        h->icu_from = icu->ucnv_open(from, &err);
        h->icu_from_name = strdup(from);
        /* ICU reports warnings as negative UErrorCode values; only a
         * positive value is a failure. */
        if (err > 0 || h->icu_from == NULL) {
            free(h->icu_from_name); free(to); free(from); free(h);
            errno = EINVAL;
            return (iconv_t)-1;
        }
        err = 0;
        h->icu_to = icu->ucnv_open(to, &err);
        h->icu_to_name = strdup(to);
        if (err > 0 || h->icu_to == NULL) {
            if (h->icu_from) icu->ucnv_close(h->icu_from);
            free(h->icu_from_name); free(h->icu_to_name);
            free(to); free(from); free(h);
            errno = EINVAL;
            return (iconv_t)-1;
        }
        /* ICU's convertEx needs a UTF-16 pivot buffer; 8 KiB is one maximum
         * ICU character size times a comfortable batch. */
        h->pivot = (char *)malloc(8192);
        if (h->pivot == NULL) {
            if (h->icu_from) icu->ucnv_close(h->icu_from);
            if (h->icu_to) icu->ucnv_close(h->icu_to);
            free(h->icu_from_name); free(h->icu_to_name);
            free(to); free(from); free(h);
            errno = ENOMEM;
            return (iconv_t)-1;
        }
    }

    free(to);
    free(from);
    return (iconv_t)h;
}

static size_t iconv_icu(struct iconv_handle *h, char **inbuf, size_t *inbytesleft,
                        char **outbuf, size_t *outbytesleft)
{
    struct icu_api *icu = g_icu;
    char *pivot_start = h->pivot;
    char *pivot_src = h->pivot;
    char *pivot_tgt = h->pivot;
    const char *src = *inbuf;
    const char *src_limit = *inbuf + *inbytesleft;
    char *dst = *outbuf;
    char *dst_limit = *outbuf + *outbytesleft;
    int err = 0;

    if (icu == NULL || h->icu_from == NULL || h->icu_to == NULL) {
        errno = EINVAL;
        return (size_t)-1;
    }

    /* The pivot is reset at the START of each call and flushed at the end:
     * callers hand iconv() arbitrarily small output buffers, and the pivot
     * only exists to bridge the two converters inside one call.  State that
     * must survive calls (partial input sequences, shift state) lives in the
     * converters themselves, which is why reset=0. */
    pivot_src = pivot_start;
    pivot_tgt = pivot_start;

    icu->ucnv_convertEx(h->icu_to, h->icu_from,
                        &dst, dst_limit, &src, src_limit,
                        pivot_start, &pivot_src, &pivot_tgt,
                        pivot_start + 8192,
                        0 /* reset */, 1 /* flush */, &err);

    *inbytesleft -= (size_t)(src - *inbuf);
    *inbuf = (char *)src;
    *outbytesleft -= (size_t)(dst - *outbuf);
    *outbuf = dst;

    if (err <= 0) {
        return 0;
    }
    if (err == 15 /* U_BUFFER_OVERFLOW_ERROR */) {
        errno = E2BIG;
        return (size_t)-1;
    }
    if (err == 10 /* U_INVALID_CHAR_FOUND */ || err == 12 /* U_ILLEGAL_CHAR_FOUND */) {
        if (h->ignore) {
            return 0;
        }
        errno = EILSEQ;
        return (size_t)-1;
    }
    if (err == 11 /* U_TRUNCATED_CHAR_FOUND */) {
        errno = EINVAL;
        return (size_t)-1;
    }
    errno = EINVAL;
    return (size_t)-1;
}

size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft,
             char **outbuf, size_t *outbytesleft)
{
    struct iconv_handle *h = (struct iconv_handle *)cd;
    size_t nonreversible = 0;

    if (h == NULL) {
        errno = EBADF;
        return (size_t)-1;
    }
    if (inbuf == NULL) {
        /* Reset the conversion state. */
        h->state = 0;
        h->pending_units = 0;
        if (g_icu != NULL) {
            if (h->icu_from) g_icu->ucnv_resetToUnicode(h->icu_from);
            if (h->icu_to) g_icu->ucnv_resetFromUnicode(h->icu_to);
        }
        return 0;
    }

    if ((h->from == ENC_ICU || h->to == ENC_ICU) && g_icu != NULL) {
        return iconv_icu(h, inbuf, inbytesleft, outbuf, outbytesleft);
    }

    while (*inbytesleft > 0) {
        unsigned int cp;
        int consumed = decode_one(h, (const unsigned char *)*inbuf, *inbytesleft, &cp);
        int produced;

        if (consumed == 0) {
            errno = EINVAL;
            return (size_t)-1;
        }
        if (consumed < 0) {
            if (h->ignore) {
                (*inbuf)++;
                (*inbytesleft)--;
                continue;
            }
            errno = EILSEQ;
            return (size_t)-1;
        }

        produced = encode_one(h, cp, (unsigned char *)*outbuf, *outbytesleft);
        if (produced == -2) {
            errno = E2BIG;
            *outbytesleft = 0;
            return (size_t)-1;
        }
        if (produced == 0) {
            /* Unrepresentable.  IGNORE drops it; TRANSLIT substitutes '?'
             * only where the target is single-byte and can hold one. */
            if (h->ignore || h->translit) {
                if (h->translit && (h->to == ENC_ASCII || h->to == ENC_LATIN1 ||
                                    h->to == ENC_CP1252 || h->to == ENC_MACROMAN)) {
                    if (*outbytesleft < 1) {
                        errno = E2BIG;
                        return (size_t)-1;
                    }
                    **outbuf = '?';
                    (*outbuf)++;
                    (*outbytesleft)--;
                }
                nonreversible++;
                *inbuf += consumed;
                *inbytesleft -= (size_t)consumed;
                continue;
            }
            errno = EILSEQ;
            return (size_t)-1;
        }

        *inbuf += consumed;
        *inbytesleft -= (size_t)consumed;
        *outbuf += produced;
        *outbytesleft -= (size_t)produced;
    }

    return nonreversible;
}

int iconv_close(iconv_t cd)
{
    struct iconv_handle *h = (struct iconv_handle *)cd;

    if (h == NULL) {
        errno = EBADF;
        return -1;
    }
    if (g_icu != NULL) {
        if (h->icu_from) g_icu->ucnv_close(h->icu_from);
        if (h->icu_to) g_icu->ucnv_close(h->icu_to);
    }
    free(h->icu_from_name);
    free(h->icu_to_name);
    free(h->pivot);
    free(h);
    return 0;
}

int iconvctl(iconv_t cd, int request, void *argument)
{
    struct iconv_handle *h = (struct iconv_handle *)cd;
    (void)argument;

    if (h == NULL) {
        errno = EBADF;
        return -1;
    }
    switch (request) {
    case ICONV_TRIVIALP:
        if (argument) *(int *)argument = (h->from == h->to);
        return 0;
    case ICONV_GET_TRANSLITERATE:
        if (argument) *(int *)argument = h->translit;
        return 0;
    case ICONV_SET_TRANSLITERATE:
        if (argument) h->translit = *(int *)argument;
        return 0;
    case ICONV_GET_DISCARD_ILSEQ:
        if (argument) *(int *)argument = h->ignore;
        return 0;
    case ICONV_SET_DISCARD_ILSEQ:
        if (argument) h->ignore = *(int *)argument;
        return 0;
    default:
        errno = EINVAL;
        return -1;
    }
}

static const char *const g_encoding_names[] = {
    "UTF-8", "UTF-16", "UTF-16LE", "UTF-16BE", "UTF-32", "UTF-32LE",
    "UTF-32BE", "UCS-2", "UCS-2LE", "UCS-2BE", "US-ASCII", "ISO-8859-1",
    "ISO-8859-15", "WINDOWS-1252", "MACINTOSH", "WCHAR_T", NULL
};

void iconvlist(int (*do_one)(unsigned int, const char *const *, void *), void *data)
{
    unsigned int count = 0;
    while (g_encoding_names[count] != NULL) {
        count++;
    }
    if (do_one) {
        do_one(count, g_encoding_names, data);
    }
}

char *iconv_canonicalize(const char *name)
{
    static char buffer[64];
    if (name == NULL) {
        return NULL;
    }
    strncpy(buffer, name, sizeof(buffer) - 1);
    buffer[sizeof(buffer) - 1] = '\0';
    /* Canonical spelling for the names this library knows. */
    for (int i = 0; g_encoding_names[i] != NULL; i++) {
        if (strcasecmp(g_encoding_names[i], name) == 0) {
            strncpy(buffer, g_encoding_names[i], sizeof(buffer) - 1);
            break;
        }
    }
    return buffer;
}

/* GNU aliases */
iconv_t libiconv_open(const char *tocode, const char *fromcode)
{
    return iconv_open(tocode, fromcode);
}

size_t libiconv(iconv_t cd, char **inbuf, size_t *inbytesleft,
                char **outbuf, size_t *outbytesleft)
{
    return iconv(cd, inbuf, inbytesleft, outbuf, outbytesleft);
}

int libiconv_close(iconv_t cd)
{
    return iconv_close(cd);
}

int libiconvctl(iconv_t cd, int request, void *argument)
{
    return iconvctl(cd, request, argument);
}

void libiconvlist(int (*do_one)(unsigned int, const char *const *, void *), void *data)
{
    iconvlist(do_one, data);
}

void libiconv_set_relocation_prefix(const char *orig_prefix, const char *curr_prefix)
{
    (void)orig_prefix;
    (void)curr_prefix;
}

const int _libiconv_version = ICONV_VERSION;
