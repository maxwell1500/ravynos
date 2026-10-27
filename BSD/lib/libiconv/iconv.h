/*
 * <iconv.h> for ravynOS.
 *
 * Apple's libiconv is the GNU implementation at the ABI macOS clients record:
 * an unversioned API with `iconv_t`, plus the GNU `libiconv*` spellings that
 * some ports link instead.  Both are exported by libiconv.2.dylib.
 */
#ifndef _ICONV_H_
#define _ICONV_H_

#include <sys/cdefs.h>
#include <stddef.h>

__BEGIN_DECLS

typedef void *iconv_t;

extern iconv_t iconv_open(const char *tocode, const char *fromcode);
extern size_t iconv(iconv_t cd, char **restrict inbuf,
                    size_t *restrict inbytesleft,
                    char **restrict outbuf, size_t *restrict outbytesleft);
extern int iconv_close(iconv_t cd);

/* GNU extensions */
#define ICONV_VERSION 0x010B
extern int iconvctl(iconv_t cd, int request, void *argument);
extern void iconvlist(int (*do_one)(unsigned int, const char *const *, void *), void *data);
extern char *iconv_canonicalize(const char *name);

/* The GNU spellings are the same entry points under a different prefix. */
extern iconv_t libiconv_open(const char *tocode, const char *fromcode);
extern size_t libiconv(iconv_t cd, char **restrict inbuf,
                       size_t *restrict inbytesleft,
                       char **restrict outbuf, size_t *restrict outbytesleft);
extern int libiconv_close(iconv_t cd);
extern int libiconvctl(iconv_t cd, int request, void *argument);
extern void libiconvlist(int (*do_one)(unsigned int, const char *const *, void *), void *data);
extern void libiconv_set_relocation_prefix(const char *orig_prefix, const char *curr_prefix);
extern const int _libiconv_version;

/* iconvctl() requests */
#define ICONV_TRIVIALP    0
#define ICONV_GET_TRANSLITERATE 1
#define ICONV_SET_TRANSLITERATE 2
#define ICONV_GET_DISCARD_ILSEQ 3
#define ICONV_SET_DISCARD_ILSEQ 4

__END_DECLS

#endif /* _ICONV_H_ */
