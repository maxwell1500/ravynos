/*-
 * Copyright (c) 2026 ravynOS
 * All rights reserved.
 *
 * The CPU-set type login_class.c uses.
 *
 * FreeBSD's setclasscpumask() takes a cpuset_t from <sys/cpuset.h> and hands
 * it to cpuset_setaffinity(2).  Neither exists here: there is no
 * sys/cpuset.h in this SDK, no cpuset syscall anywhere in Kernel/xnu, and no
 * cpuset/cpu_set symbol in any dylib under the SDK's usr/lib.  The kernel's
 * only affinity interface is thread_affinity_set(), which tags a thread for
 * cache-locality grouping and carries no CPU list, so there is nothing to
 * pass a mask to.
 *
 * So the mask is still parsed and range-checked exactly as upstream does --
 * that is real validation of the login.conf cpumask= capability, and it is
 * what makes a malformed mask diagnosable -- and setclasscpumask() then
 * reports that the parsed set could not be applied.  The representation below
 * is a byte per CPU with a fixed CPU_SETSIZE, matching FreeBSD's cpuset_t
 * geometry, so the parse code is the upstream parse code.
 */

#ifndef _LOGIN_CLASS_LOCAL_H_
#define	_LOGIN_CLASS_LOCAL_H_

#include <sys/types.h>
#include <string.h>

#define	CPU_SETSIZE	1024
#define	CPU_NBYTES	((CPU_SETSIZE + 7) / 8)

typedef struct cpuset {
	unsigned char	_set[CPU_NBYTES];
} cpuset_t;

#define	CPU_ISSET(cpu, set)						\
    (((set)->_set[(cpu) / 8] & (1 << ((cpu) & 7))) != 0)
#define	CPU_SET(cpu, set)						\
    ((set)->_set[(cpu) / 8] |= (1 << ((cpu) & 7)))
#define	CPU_ZERO(set)							\
    memset((set), 0, sizeof(*(set)))

#endif /* !_LOGIN_CLASS_LOCAL_H_ */