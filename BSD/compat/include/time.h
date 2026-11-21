/* POSIX timers: the SDK's <time.h> predates the declarations FreeBSD's
 * <time.h> carries.  The implementation is libsystem_kernel/posix_timer.c. */
#ifndef _RAVYN_COMPAT_TIME_H_
#define _RAVYN_COMPAT_TIME_H_

#include_next <time.h>

#ifndef TIMER_ABSTIME
#define TIMER_ABSTIME 1

#ifndef _RAVYN_TIMER_T_DEFINED
#define _RAVYN_TIMER_T_DEFINED
typedef void *timer_t;
#endif

struct itimerspec {
	struct timespec it_interval;
	struct timespec it_value;
};

struct sigevent;

#ifdef __cplusplus
extern "C" {
#endif
int timer_create(clockid_t, struct sigevent *__restrict,
    timer_t *__restrict);
int timer_delete(timer_t);
int timer_gettime(timer_t, struct itimerspec *);
int timer_getoverrun(timer_t);
int timer_settime(timer_t, int, const struct itimerspec *__restrict,
    struct itimerspec *__restrict);
#ifdef __cplusplus
}
#endif

#endif
#endif
