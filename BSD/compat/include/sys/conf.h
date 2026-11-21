/* FreeBSD character-device switches.  dd includes this for the D_* type
 * constants it compares FIODTYPE against and for ioctl() itself, which Darwin
 * declares in <sys/ioctl.h>. */
#ifndef _RAVYN_COMPAT_SYS_CONF_H_
#define _RAVYN_COMPAT_SYS_CONF_H_

#include <sys/ioctl.h>
#include <sys/types.h>

#define D_TAPE		0
#define D_DISK		1
#define D_TTY		2
#define D_MEM		3
#define D_NULL		4
#define D_ZERO		5

#endif
