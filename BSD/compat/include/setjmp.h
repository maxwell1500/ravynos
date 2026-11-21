/* BSD exposes _setjmp/_longjmp without signal-mask handling; Darwin's only
 * entry points are setjmp/longjmp, which preserve the same caller contract. */
#ifndef _RAVYN_COMPAT_SETJMP_H_
#define _RAVYN_COMPAT_SETJMP_H_

#include_next <setjmp.h>

#ifndef _setjmp
#define _setjmp setjmp
#endif
#ifndef _longjmp
#define _longjmp longjmp
#endif

#endif
