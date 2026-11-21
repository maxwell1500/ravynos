/* SPDX-License-Identifier: BSD-2-Clause */
/* POSIX per-process timers for ravynOS.
 *
 * The XNU kernel has no POSIX timer syscall, but the API is expressible in
 * userland: one worker thread per timer waits on a condition variable until
 * the next expiry and then delivers the requested notification.  This is the
 * behaviour timer_create(2) specifies (absolute/relative arming, periodic
 * rearming, overrun count, SIGEV_NONE/SIGNAL/THREAD); the only difference is
 * that delivery happens on the worker thread instead of an itimer callback,
 * which POSIX permits because the signal is delivered to the process. */
#include <sys/types.h>

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* The SDK's <time.h> predates the POSIX timer declarations the kernel headers
 * carry; define the public shapes here so the wrapper is self-contained. */
#ifndef TIMER_ABSTIME
#define TIMER_ABSTIME 1
struct itimerspec {
	struct timespec it_interval;
	struct timespec it_value;
};
typedef void *timer_t;
#endif

struct posix_timer {
	pthread_mutex_t lock;
	pthread_cond_t cond;
	pthread_t thread;
	int thread_valid;
	int deleted;
	int armed;
	int overrun;
	clockid_t clockid;
	struct itimerspec spec;
	struct timespec next;
	struct sigevent event;
};

static void
timespec_add(struct timespec *a, const struct timespec *b)
{
	a->tv_sec += b->tv_sec;
	a->tv_nsec += b->tv_nsec;
	if (a->tv_nsec >= 1000000000L) {
		a->tv_sec++;
		a->tv_nsec -= 1000000000L;
	}
}

static int
timespec_after(const struct timespec *a, const struct timespec *b)
{
	return a->tv_sec > b->tv_sec ||
	    (a->tv_sec == b->tv_sec && a->tv_nsec > b->tv_nsec);
}

static void
timespec_sub(const struct timespec *a, const struct timespec *b,
    struct timespec *out)
{
	out->tv_sec = a->tv_sec - b->tv_sec;
	out->tv_nsec = a->tv_nsec - b->tv_nsec;
	if (out->tv_nsec < 0) {
		out->tv_sec--;
		out->tv_nsec += 1000000000L;
	}
	if (out->tv_sec < 0) {
		out->tv_sec = 0;
		out->tv_nsec = 0;
	}
}

/* pthread_cond_timedwait on this platform waits against the realtime clock;
 * convert a deadline expressed in the timer's clock. */
static void
deadline_to_realtime(clockid_t clockid, const struct timespec *deadline,
    struct timespec *out)
{
	struct timespec now_timer, now_real, delta;

	clock_gettime(clockid, &now_timer);
	clock_gettime(CLOCK_REALTIME, &now_real);
	timespec_sub(deadline, &now_timer, &delta);
	*out = now_real;
	timespec_add(out, &delta);
}

struct timer_thread_call {
	void (*function)(union sigval);
	union sigval value;
};

static void *
timer_thread_trampoline(void *arg)
{
	struct timer_thread_call *call = arg;

	call->function(call->value);
	free(call);
	return NULL;
}

static void
timer_fire(struct posix_timer *timer)
{
	struct sigevent event;
	union sigval value;

	pthread_mutex_lock(&timer->lock);
	event = timer->event;
	value = event.sigev_value;
	timer->overrun++;
	pthread_mutex_unlock(&timer->lock);

	switch (event.sigev_notify) {
	case SIGEV_NONE:
		break;
	case SIGEV_THREAD:
		if (event.sigev_notify_function != NULL) {
			struct timer_thread_call *call = malloc(sizeof(*call));
			pthread_t tid;
			pthread_attr_t attr;
			pthread_attr_t *attrp = event.sigev_notify_attributes;

			if (call == NULL) {
				event.sigev_notify_function(value);
				break;
			}
			call->function = event.sigev_notify_function;
			call->value = value;
			if (attrp == NULL) {
				pthread_attr_init(&attr);
				pthread_attr_setdetachstate(&attr,
				    PTHREAD_CREATE_DETACHED);
				attrp = &attr;
			}
			if (pthread_create(&tid, attrp,
			    timer_thread_trampoline, call) != 0) {
				free(call);
				event.sigev_notify_function(value);
			} else
				pthread_detach(tid);
			if (attrp == &attr)
				pthread_attr_destroy(&attr);
		}
		break;
	case SIGEV_SIGNAL:
	default:
		kill(getpid(), event.sigev_signo != 0 ? event.sigev_signo :
		    SIGALRM);
		break;
	}
}

static void *
timer_worker(void *arg)
{
	struct posix_timer *timer = arg;

	pthread_mutex_lock(&timer->lock);
	for (;;) {
		struct timespec deadline;

		if (timer->deleted)
			break;
		if (!timer->armed) {
			pthread_cond_wait(&timer->cond, &timer->lock);
			continue;
		}
		deadline_to_realtime(timer->clockid, &timer->next, &deadline);
		if (pthread_cond_timedwait(&timer->cond, &timer->lock,
		    &deadline) != ETIMEDOUT)
			continue;
		if (timer->deleted)
			break;
		if (!timer->armed)
			continue;
		if (timer->spec.it_interval.tv_sec == 0 &&
		    timer->spec.it_interval.tv_nsec == 0) {
			timer->armed = 0;
		} else {
			struct timespec now;

			timespec_add(&timer->next, &timer->spec.it_interval);
			/* Skip wholly missed periods, as POSIX allows. */
			clock_gettime(timer->clockid, &now);
			while (timespec_after(&now, &timer->next)) {
				timespec_add(&timer->next,
				    &timer->spec.it_interval);
				timer->overrun++;
			}
		}
		pthread_mutex_unlock(&timer->lock);
		timer_fire(timer);
		pthread_mutex_lock(&timer->lock);
	}
	pthread_mutex_unlock(&timer->lock);
	return NULL;
}

int
timer_create(clockid_t clockid, struct sigevent *restrict event,
    timer_t *restrict timerid)
{
	struct posix_timer *timer;

	if (clockid != CLOCK_REALTIME && clockid != CLOCK_MONOTONIC) {
		errno = EINVAL;
		return -1;
	}
	if ((timer = calloc(1, sizeof(*timer))) == NULL)
		return -1;
	pthread_mutex_init(&timer->lock, NULL);
	pthread_cond_init(&timer->cond, NULL);
	timer->clockid = clockid;
	if (event != NULL)
		timer->event = *event;
	else {
		timer->event.sigev_notify = SIGEV_SIGNAL;
		timer->event.sigev_signo = SIGALRM;
	}
	if (pthread_create(&timer->thread, NULL, timer_worker, timer) != 0) {
		pthread_mutex_destroy(&timer->lock);
		pthread_cond_destroy(&timer->cond);
		free(timer);
		errno = EAGAIN;
		return -1;
	}
	timer->thread_valid = 1;
	*timerid = (timer_t)timer;
	return 0;
}

int
timer_delete(timer_t timerid)
{
	struct posix_timer *timer = (struct posix_timer *)timerid;

	if (timer == NULL) {
		errno = EINVAL;
		return -1;
	}
	pthread_mutex_lock(&timer->lock);
	timer->deleted = 1;
	pthread_cond_broadcast(&timer->cond);
	pthread_mutex_unlock(&timer->lock);
	if (timer->thread_valid)
		pthread_join(timer->thread, NULL);
	pthread_mutex_destroy(&timer->lock);
	pthread_cond_destroy(&timer->cond);
	free(timer);
	return 0;
}

int
timer_settime(timer_t timerid, int flags, const struct itimerspec *restrict
    value, struct itimerspec *restrict oldvalue)
{
	struct posix_timer *timer = (struct posix_timer *)timerid;

	if (timer == NULL || value == NULL) {
		errno = EINVAL;
		return -1;
	}
	pthread_mutex_lock(&timer->lock);
	if (oldvalue != NULL) {
		struct timespec now;

		clock_gettime(timer->clockid, &now);
		timespec_sub(&timer->next, &now, &oldvalue->it_value);
		oldvalue->it_interval = timer->spec.it_interval;
		if (!timer->armed) {
			oldvalue->it_value.tv_sec = 0;
			oldvalue->it_value.tv_nsec = 0;
		}
	}
	timer->spec = *value;
	if (value->it_value.tv_sec == 0 && value->it_value.tv_nsec == 0) {
		timer->armed = 0;
	} else {
		if (flags & TIMER_ABSTIME) {
			timer->next = value->it_value;
		} else {
			clock_gettime(timer->clockid, &timer->next);
			timespec_add(&timer->next, &value->it_value);
		}
		timer->armed = 1;
		timer->overrun = 0;
	}
	pthread_cond_broadcast(&timer->cond);
	pthread_mutex_unlock(&timer->lock);
	return 0;
}

int
timer_gettime(timer_t timerid, struct itimerspec *value)
{
	struct posix_timer *timer = (struct posix_timer *)timerid;
	struct timespec now;

	if (timer == NULL || value == NULL) {
		errno = EINVAL;
		return -1;
	}
	pthread_mutex_lock(&timer->lock);
	value->it_interval = timer->spec.it_interval;
	if (timer->armed) {
		clock_gettime(timer->clockid, &now);
		timespec_sub(&timer->next, &now, &value->it_value);
	} else {
		value->it_value.tv_sec = 0;
		value->it_value.tv_nsec = 0;
	}
	pthread_mutex_unlock(&timer->lock);
	return 0;
}

int
timer_getoverrun(timer_t timerid)
{
	struct posix_timer *timer = (struct posix_timer *)timerid;
	int overrun;

	if (timer == NULL) {
		errno = EINVAL;
		return -1;
	}
	pthread_mutex_lock(&timer->lock);
	overrun = timer->overrun;
	timer->overrun = 0;
	pthread_mutex_unlock(&timer->lock);
	return overrun;
}
