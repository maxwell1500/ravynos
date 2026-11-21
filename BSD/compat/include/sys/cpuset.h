/* FreeBSD CPU-set interface.  ravynOS has no per-thread affinity, so the
 * mask always describes "every configured CPU"; programs such as nproc only
 * read it to report a count. */
#ifndef _RAVYN_COMPAT_SYS_CPUSET_H_
#define _RAVYN_COMPAT_SYS_CPUSET_H_

#include <sys/types.h>
#include <unistd.h>

typedef unsigned long long cpuset_t;

#define CPU_ZERO(set)		(*(set) = 0ULL)
#define CPU_SET(cpu, set)	(*(set) |= (1ULL << (cpu)))
#define CPU_CLR(cpu, set)	(*(set) &= ~(1ULL << (cpu)))
#define CPU_ISSET(cpu, set)	((*(set) & (1ULL << (cpu))) != 0)
#define CPU_COUNT(set)		(__builtin_popcountll(*(set)))

#define CPU_LEVEL_WHICH	3
#define CPU_WHICH_TID	-1
#define CPU_WHICH_PID	-2

static inline int
cpuset_getaffinity(int level, int which, id_t id, size_t setSize, cpuset_t *mask)
{
	long count = sysconf(_SC_NPROCESSORS_CONF);

	(void)level; (void)which; (void)id;
	if (mask == NULL || setSize < sizeof(*mask))
		return -1;
	if (count < 0)
		return -1;
	*mask = (count >= 64) ? ~0ULL : ((1ULL << count) - 1);
	return 0;
}

#endif
