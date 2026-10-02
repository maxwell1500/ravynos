/*
 * pthread_cond_unix03.c -- pthread_cond_wait$UNIX2003.
 *
 * WHY THIS IS A REAL FUNCTION AND NOT AN ALIAS
 * pthread_cond_wait is the one entry point in this group that the $UNIX2003
 * spelling does NOT denote the same code as the unsuffixed one, so it
 * cannot be a .globl/.set alias the way the three pthread_rwlock_* aliases in
 * pthread_unix03_aliases.c are.
 *
 * The reason is cancellation. internal.h:570-572 defines the three
 * conformance modes this component implements:
 *
 *     PTHREAD_CONFORM_DARWIN_LEGACY     0
 *     PTHREAD_CONFORM_UNIX03_NOCANCEL   1
 *     PTHREAD_CONFORM_UNIX03_CANCELABLE 2
 *
 * and pthread_cancelable.c:524-527 shows the unsuffixed entry point asking
 * for the process's *current* mode at every call:
 *
 *     int
 *     pthread_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex)
 *     {
 *             return _pthread_cond_wait(cond, mutex, NULL, 0,
 *                                        _pthread_conformance());
 *     }
 *
 * The suffix on a pthread symbol names the conformance the entry point is
 * pinned to, not an alternative spelling of it. pthread_cond.c:581-589 is
 * where that argument is consumed: when `conforming` is set,
 * pthread_cond_wait wraps the kernel wait in a cleanup handler and calls
 * _pthread_testcancel() on the way out, making it a cancellation point as
 * SUSv3 requires; when it is clear, the wait is not interruptible.
 *
 * So the $UNIX2003 variant is the one that is unconditionally
 * cancellation-enabled, whatever the process default happens to be. That is
 * what a VARIANT_UNIX03 build of pthread_cond_wait would emit, and it is
 * what the SDK's pthread/pthread.h promises every caller compiled against
 * it: libobjc calls pthread_cond_wait$UNIX2003 and expects a cancellation
 * point.
 *
 * Passing PTHREAD_CONFORM_UNIX03_CANCELABLE here -- rather than aliasing to
 * the unsuffixed function, which would silently inherit whatever
 * _pthread_conformance() returns -- is the whole content of this file.
 */

#include <pthread.h>

extern int _pthread_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex,
	const struct timespec *abstime, int isRelative, int isconforming);

#ifndef PTHREAD_CONFORM_UNIX03_CANCELABLE
#define PTHREAD_CONFORM_UNIX03_CANCELABLE	2
#endif

int
rav_pthread_cond_wait_unix03(pthread_cond_t *cond, pthread_mutex_t *mutex)
	__asm__("_pthread_cond_wait$UNIX2003");
int
rav_pthread_cond_wait_unix03(pthread_cond_t *cond, pthread_mutex_t *mutex)
{
	return _pthread_cond_wait(cond, mutex, NULL, 0,
	    PTHREAD_CONFORM_UNIX03_CANCELABLE);
}
