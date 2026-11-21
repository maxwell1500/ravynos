/* FreeBSD sources ask for O_DIRECT, which Darwin has no open flag for; the
 * equivalent (F_NOCACHE) applies to an open descriptor.  Zero keeps callers
 * correct and simply uncached-less. */
#ifndef _RAVYN_COMPAT_FCNTL_H_
#define _RAVYN_COMPAT_FCNTL_H_

#include_next <fcntl.h>

#ifndef O_DIRECT
#define O_DIRECT 0
#endif

#endif
