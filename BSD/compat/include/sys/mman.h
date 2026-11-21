/* FreeBSD mmap hint flags that Darwin's <sys/mman.h> lacks.  They are hints
 * only (MAP_NOCORE: do not dump; MAP_NOSYNC: delay writeback), so 0 is the
 * correct no-op value. */
#ifndef _RAVYN_COMPAT_SYS_MMAN_H_
#define _RAVYN_COMPAT_SYS_MMAN_H_

#include_next <sys/mman.h>

#ifndef MAP_NOCORE
#define MAP_NOCORE 0
#endif
#ifndef MAP_NOSYNC
#define MAP_NOSYNC 0
#endif

#endif
