/* FreeBSD pthread spellings used by imported sources.  Darwin's pthreads
 * implement the same semantics under different names. */
#ifndef _RAVYN_COMPAT_PTHREAD_H_
#define _RAVYN_COMPAT_PTHREAD_H_

#include_next <pthread.h>

#ifndef PTHREAD_MUTEX_ADAPTIVE_NP
#define PTHREAD_MUTEX_ADAPTIVE_NP PTHREAD_MUTEX_DEFAULT
#endif

#ifndef PTHREAD_DETACHED
#define PTHREAD_DETACHED PTHREAD_CREATE_DETACHED
#endif

#include <sched.h>
#ifndef pthread_yield
#define pthread_yield() sched_yield()
#endif

#endif
