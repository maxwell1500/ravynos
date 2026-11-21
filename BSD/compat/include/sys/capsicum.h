/* Capsicum is FreeBSD-only.  Programs in this tree call its rights API to
 * sandbox themselves; on ravynOS the calls must compile and be no-ops rather
 * than pull a FreeBSD kernel interface that does not exist here. */
#ifndef _RAVYN_COMPAT_SYS_CAPSICUM_H_
#define _RAVYN_COMPAT_SYS_CAPSICUM_H_

#include <unistd.h>

typedef struct {
	unsigned long long rights;
} cap_rights_t;

#define CAP_READ	 (1ULL << 0)
#define CAP_WRITE	 (1ULL << 1)
#define CAP_SEEK	 (1ULL << 2)
#define CAP_FTRUNCATE	 (1ULL << 3)
#define CAP_IOCTL	 (1ULL << 4)
#define CAP_FSYNC	 (1ULL << 5)
#define CAP_LOOKUP	 (1ULL << 6)
#define CAP_FEXECVE	 (1ULL << 7)
#define CAP_EVENT	 (1ULL << 8)
#define CAP_KQUEUE	 (1ULL << 9)
#define CAP_ALL		 (~0ULL)

#define cap_rights_init(_r, ...)	((_r)->rights = 0, (_r))
#define cap_rights_set(_r, ...)		((_r)->rights = CAP_ALL, (_r))
#define cap_rights_clear(_r, ...)	((_r)->rights = 0, (_r))
#define cap_rights_is_set(_r, ...)	(1)
#define cap_rights_limit(fd, rights)	(0)
#define cap_ioctls_limit(fd, cmds, n)	(0)
#define cap_fcntls_limit(fd, flags)	(0)
#define cap_enter()			(0)
#define cap_getmode(modep)		(*(modep) = 0, 0)

#endif
