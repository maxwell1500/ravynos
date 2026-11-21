/* Darwin has fsync(2) but no fdatasync(2); fsync provides the same data
 * durability and stronger metadata guarantees. */
#ifndef _RAVYN_COMPAT_UNISTD_H_
#define _RAVYN_COMPAT_UNISTD_H_

#include_next <unistd.h>

#ifndef fdatasync
#define fdatasync(fd) fsync(fd)
#endif

/* FreeBSD declares getentropy(2) in <unistd.h>; Darwin only declares it in
 * <sys/random.h>, which some imported sources do not include. */
int getentropy(void *, size_t);

/* FreeBSD declares these in <unistd.h>; expr(1) and other ports call them. */
int check_utility_compat(const char *utility);

#endif
