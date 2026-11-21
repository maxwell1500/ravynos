/* FreeBSD declares strtonum(3) in <stdlib.h>; the macOS stdlib does not.
 * include_next keeps every other declaration from the SDK header. */
#ifndef _RAVYN_COMPAT_STDLIB_H_
#define _RAVYN_COMPAT_STDLIB_H_

#include_next <stdlib.h>

long long strtonum(const char *numstr, long long minval, long long maxval,
    const char **errstrp);

#endif
