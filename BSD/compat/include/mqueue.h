/* POSIX message queues: the SDK has no <mqueue.h> or <sys/mqueue.h>; the
 * implementation lives in libsystem_kernel/posix_mqueue.c. */
#ifndef _RAVYN_COMPAT_MQUEUE_H_
#define _RAVYN_COMPAT_MQUEUE_H_

#include <sys/types.h>
#include <sys/signal.h>
#include <time.h>

#ifndef _RAVYN_MQ_TYPES
#define _RAVYN_MQ_TYPES
typedef int mqd_t;
struct mq_attr {
	long mq_flags;
	long mq_maxmsg;
	long mq_msgsize;
	long mq_curmsgs;
	long __reserved[4];
};
#endif

#ifdef __cplusplus
extern "C" {
#endif
int mq_close(mqd_t);
int mq_getattr(mqd_t, struct mq_attr *);
int mq_notify(mqd_t, const struct sigevent *);
mqd_t mq_open(const char *, int, ...);
ssize_t mq_receive(mqd_t, char *, size_t, unsigned *);
int mq_send(mqd_t, const char *, size_t, unsigned);
int mq_setattr(mqd_t, const struct mq_attr *__restrict,
    struct mq_attr *__restrict);
ssize_t mq_timedreceive(mqd_t, char *__restrict, size_t,
    unsigned *__restrict, const struct timespec *__restrict);
int mq_timedsend(mqd_t, const char *, size_t, unsigned,
    const struct timespec *);
int mq_unlink(const char *);
int mq_getfd_np(mqd_t);
#ifdef __cplusplus
}
#endif

#endif
