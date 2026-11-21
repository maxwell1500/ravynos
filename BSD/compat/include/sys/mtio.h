/* Magnetic-tape control ioctls.  ravynOS has no tape driver; the definitions
 * exist so tape-aware utilities (dd) compile and their ioctls fail with
 * ENOTTY at runtime, which is the correct behaviour without hardware. */
#ifndef _RAVYN_COMPAT_SYS_MTIO_H_
#define _RAVYN_COMPAT_SYS_MTIO_H_

#include <sys/ioccom.h>
#include <sys/ioctl.h>

struct mtop {
	short	mt_op;
	int	mt_count;
};

/* Opaque: callers only test whether MTIOCGET succeeds, to tell a tape from
 * another character device. */
struct mtget {
	int	mt_dummy;
};

#define MTIOCTOP	_IOW('m', 1, struct mtop)
#define MTIOCGET	_IOR('m', 2, struct mtget)

#define MTWEOF		0
#define MTFSF		1
#define MTBSF		2
#define MTFSR		3
#define MTBSR		4
#define MTREW		5
#define MTOFFL		6
#define MTNOP		7

#endif
