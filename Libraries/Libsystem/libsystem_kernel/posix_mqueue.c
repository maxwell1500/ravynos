/* SPDX-License-Identifier: BSD-2-Clause */
/* POSIX message queues for ravynOS.
 *
 * XNU has no mqueue filesystem, so queues are files under
 * /tmp/.ravynos-mqueue-<uid>/ guarded by flock(2).  The on-disk format is a
 * header followed by fixed-size slots, which makes send/receive atomic across
 * processes without a broker: every operation takes an exclusive lock, reads
 * the header, mutates one slot and writes it back.  This is the same
 * name -> persistent object model POSIX specifies (mq_unlink removes the
 * name), and priority/FIFO ordering and attributes are honoured.  mq_notify
 * supports SIGEV_SIGNAL and SIGEV_NONE; SIGEV_THREAD cannot cross a process
 * boundary and reports ENOTSUP. */
#include <sys/types.h>
#include <sys/file.h>
#include <sys/stat.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifndef TIMER_ABSTIME
#define TIMER_ABSTIME 1
struct itimerspec {
	struct timespec it_interval;
	struct timespec it_value;
};
typedef void *timer_t;
#endif

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

#define MQ_MAGIC	0x4d515559u	/* "MQUY" */
#define MQ_PATH_MAX	208
#define MQ_NAME_MAX	200
#define MQ_DEFAULT_MAXMSG	16
#define MQ_DEFAULT_MSGSIZE	1024

struct mq_header {
	uint32_t magic;
	uint32_t maxmsg;
	uint32_t msgsize;
	uint32_t curmsgs;
	uint32_t seq;
	int32_t notify_pid;
	int32_t notify_sig;
	uint32_t notify_valid;
	uint32_t reserved;
};

struct mq_slot {
	uint32_t used;
	uint32_t prio;
	uint32_t len;
	uint32_t seq;
};

static size_t
slot_offset(const struct mq_header *hdr, uint32_t index)
{
	return sizeof(*hdr) + (size_t)index * (sizeof(struct mq_slot) +
	    hdr->msgsize);
}

static int
queue_path(const char *name, char *path, size_t pathlen)
{
	char dir[PATH_MAX];
	const char *p;

	if (name == NULL || name[0] != '/') {
		errno = EINVAL;
		return -1;
	}
	p = name + 1;
	if (*p == '\0' || strlen(p) > MQ_NAME_MAX) {
		errno = EINVAL;
		return -1;
	}
	for (const char *q = p; *q != '\0'; q++) {
		if (!((*q >= 'A' && *q <= 'Z') || (*q >= 'a' && *q <= 'z') ||
		    (*q >= '0' && *q <= '9') || *q == '.' || *q == '_' ||
		    *q == '-')) {
			errno = EINVAL;
			return -1;
		}
	}
	snprintf(dir, sizeof(dir), "/tmp/.ravynos-mqueue-%ld",
	    (long)getuid());
	if (mkdir(dir, 0700) != 0 && errno != EEXIST)
		return -1;
	if (snprintf(path, pathlen, "%s/%s", dir, p) >= (int)pathlen) {
		errno = ENAMETOOLONG;
		return -1;
	}
	return 0;
}

static int
read_header(int fd, struct mq_header *hdr)
{
	if (pread(fd, hdr, sizeof(*hdr), 0) != (ssize_t)sizeof(*hdr)) {
		errno = EINVAL;
		return -1;
	}
	if (hdr->magic != MQ_MAGIC || hdr->maxmsg == 0 ||
	    hdr->msgsize == 0) {
		errno = EINVAL;
		return -1;
	}
	return 0;
}

static int
write_header(int fd, const struct mq_header *hdr)
{
	if (pwrite(fd, hdr, sizeof(*hdr), 0) != (ssize_t)sizeof(*hdr)) {
		errno = EIO;
		return -1;
	}
	return 0;
}

mqd_t
mq_open(const char *name, int flags, ...)
{
	struct mq_header hdr;
	struct stat st;
	char path[PATH_MAX];
	mode_t mode = 0;
	struct mq_attr *attr = NULL;
	int fd, oflags;

	if (flags & O_CREAT) {
		va_list ap;
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		attr = va_arg(ap, struct mq_attr *);
		va_end(ap);
	}
	if (queue_path(name, path, sizeof(path)) != 0)
		return (mqd_t)-1;

	oflags = O_RDWR | O_NOFOLLOW;
	if (flags & O_CREAT)
		oflags |= O_CREAT;
	if (flags & O_EXCL)
		oflags |= O_EXCL;

	memset(&hdr, 0, sizeof(hdr));
	if (attr != NULL) {
		if (attr->mq_maxmsg <= 0 || attr->mq_msgsize <= 0) {
			errno = EINVAL;
			return (mqd_t)-1;
		}
		hdr.maxmsg = (uint32_t)attr->mq_maxmsg;
		hdr.msgsize = (uint32_t)attr->mq_msgsize;
	} else {
		hdr.maxmsg = MQ_DEFAULT_MAXMSG;
		hdr.msgsize = MQ_DEFAULT_MSGSIZE;
	}
	hdr.magic = MQ_MAGIC;
	hdr.seq = 1;

	fd = open(path, oflags, mode != 0 ? mode : 0600);
	if (fd < 0) {
		/* An existing queue with O_CREAT but no O_EXCL must open, not
		 * overwrite, and must not reinitialise its contents. */
		if (errno == EEXIST && (flags & O_CREAT) &&
		    !(flags & O_EXCL)) {
			fd = open(path, O_RDWR | O_NOFOLLOW);
		}
		if (fd < 0)
			return (mqd_t)-1;
	}

	if (flags & O_CREAT) {
		int created = 0;

		if (fstat(fd, &st) == 0 && st.st_size == 0)
			created = 1;
		if (created) {
			if (ftruncate(fd, (off_t)slot_offset(&hdr,
			    hdr.maxmsg)) != 0) {
				int saved = errno;
				close(fd);
				unlink(path);
				errno = saved;
				return (mqd_t)-1;
			}
			if (write_header(fd, &hdr) != 0) {
				int saved = errno;
				close(fd);
				unlink(path);
				errno = saved;
				return (mqd_t)-1;
			}
		} else if (read_header(fd, &hdr) != 0) {
			close(fd);
			return (mqd_t)-1;
		}
	} else if (read_header(fd, &hdr) != 0) {
		close(fd);
		return (mqd_t)-1;
	}
	if (flags & O_NONBLOCK)
		(void)fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
	return fd;
}

int
mq_close(mqd_t mqd)
{
	if (mqd < 0) {
		errno = EBADF;
		return -1;
	}
	return close(mqd);
}

int
mq_unlink(const char *name)
{
	char path[PATH_MAX];

	if (queue_path(name, path, sizeof(path)) != 0)
		return -1;
	return unlink(path);
}

static int
attr_from_fd(int fd, const struct mq_header *hdr, struct mq_attr *attr)
{
	int flags = fcntl(fd, F_GETFL);

	attr->mq_flags = (flags & O_NONBLOCK) ? O_NONBLOCK : 0;
	attr->mq_maxmsg = hdr->maxmsg;
	attr->mq_msgsize = hdr->msgsize;
	attr->mq_curmsgs = hdr->curmsgs;
	memset(attr->__reserved, 0, sizeof(attr->__reserved));
	return 0;
}

int
mq_getattr(mqd_t mqd, struct mq_attr *attr)
{
	struct mq_header hdr;

	if (mqd < 0 || attr == NULL) {
		errno = EINVAL;
		return -1;
	}
	if (flock(mqd, LOCK_SH) != 0)
		return -1;
	if (read_header(mqd, &hdr) != 0) {
		flock(mqd, LOCK_UN);
		return -1;
	}
	attr_from_fd(mqd, &hdr, attr);
	flock(mqd, LOCK_UN);
	return 0;
}

int
mq_setattr(mqd_t mqd, const struct mq_attr *restrict attr,
    struct mq_attr *restrict oattr)
{
	struct mq_header hdr;
	int flags;

	if (mqd < 0 || attr == NULL) {
		errno = EINVAL;
		return -1;
	}
	if (flock(mqd, LOCK_EX) != 0)
		return -1;
	if (read_header(mqd, &hdr) != 0) {
		flock(mqd, LOCK_UN);
		return -1;
	}
	if (oattr != NULL)
		attr_from_fd(mqd, &hdr, oattr);
	flags = fcntl(mqd, F_GETFL);
	if (attr->mq_flags & O_NONBLOCK)
		flags |= O_NONBLOCK;
	else
		flags &= ~O_NONBLOCK;
	(void)fcntl(mqd, F_SETFL, flags);
	flock(mqd, LOCK_UN);
	return 0;
}

static int
expired(const struct timespec *deadline)
{
	struct timespec now;

	if (deadline == NULL)
		return 0;
	clock_gettime(CLOCK_REALTIME, &now);
	return now.tv_sec > deadline->tv_sec ||
	    (now.tv_sec == deadline->tv_sec && now.tv_nsec >= deadline->tv_nsec);
}

int
mq_send(mqd_t mqd, const char *msg, size_t len, unsigned prio)
{
	return mq_timedsend(mqd, msg, len, prio, NULL);
}

int
mq_timedsend(mqd_t mqd, const char *msg, size_t len, unsigned prio,
    const struct timespec *deadline)
{
	struct mq_header hdr;
	struct mq_slot slot;
	char *buf = NULL;
	uint32_t i;
	int nonblock, result = 0;
	pid_t notify_pid = 0;
	int notify_sig = 0;

	if (mqd < 0 || (msg == NULL && len != 0)) {
		errno = EINVAL;
		return -1;
	}
	nonblock = (fcntl(mqd, F_GETFL) & O_NONBLOCK) != 0;
	if (len > INT_MAX) {
		errno = EMSGSIZE;
		return -1;
	}
	for (;;) {
		if (flock(mqd, LOCK_EX) != 0)
			return -1;
		if (read_header(mqd, &hdr) != 0) {
			flock(mqd, LOCK_UN);
			return -1;
		}
		if (len > hdr.msgsize) {
			flock(mqd, LOCK_UN);
			errno = EMSGSIZE;
			return -1;
		}
		if (hdr.curmsgs < hdr.maxmsg)
			break;
		flock(mqd, LOCK_UN);
		if (nonblock) {
			errno = EAGAIN;
			return -1;
		}
		if (expired(deadline)) {
			errno = ETIMEDOUT;
			return -1;
		}
		usleep(1000);
	}

	for (i = 0; i < hdr.maxmsg; i++) {
		if (pread(mqd, &slot, sizeof(slot),
		    (off_t)slot_offset(&hdr, i)) != (ssize_t)sizeof(slot)) {
			flock(mqd, LOCK_UN);
			errno = EIO;
			return -1;
		}
		if (!slot.used)
			break;
	}
	if (i == hdr.maxmsg) {
		flock(mqd, LOCK_UN);
		errno = EAGAIN;
		return -1;
	}
	if (len != 0 && (buf = malloc(len)) == NULL) {
		flock(mqd, LOCK_UN);
		return -1;
	}
	if (len != 0)
		memcpy(buf, msg, len);
	slot.used = 1;
	slot.prio = prio;
	slot.len = (uint32_t)len;
	slot.seq = hdr.seq++;
	if (pwrite(mqd, &slot, sizeof(slot),
	    (off_t)slot_offset(&hdr, i)) != (ssize_t)sizeof(slot) ||
	    (len != 0 && pwrite(mqd, buf, len,
	    (off_t)(slot_offset(&hdr, i) + sizeof(slot))) != (ssize_t)len)) {
		result = -1;
		errno = EIO;
	}
	free(buf);
	if (result == 0) {
		hdr.curmsgs++;
		/* A notification is delivered when the queue becomes
		 * non-empty, and only once per registration. */
		if (hdr.curmsgs == 1 && hdr.notify_valid) {
			notify_pid = hdr.notify_pid;
			notify_sig = hdr.notify_sig;
			hdr.notify_valid = 0;
		}
		if (write_header(mqd, &hdr) != 0)
			result = -1;
	}
	flock(mqd, LOCK_UN);
	if (result == 0 && notify_pid > 0)
		kill(notify_pid, notify_sig);
	return result;
}

ssize_t
mq_receive(mqd_t mqd, char *msg, size_t len, unsigned *prio)
{
	return mq_timedreceive(mqd, msg, len, prio, NULL);
}

ssize_t
mq_timedreceive(mqd_t mqd, char *restrict msg, size_t len,
    unsigned *restrict prio, const struct timespec *restrict deadline)
{
	struct mq_header hdr;
	struct mq_slot slot, best;
	uint32_t i, best_index;
	int nonblock;

	if (mqd < 0 || msg == NULL) {
		errno = EINVAL;
		return -1;
	}
	nonblock = (fcntl(mqd, F_GETFL) & O_NONBLOCK) != 0;
	for (;;) {
		if (flock(mqd, LOCK_EX) != 0)
			return -1;
		if (read_header(mqd, &hdr) != 0) {
			flock(mqd, LOCK_UN);
			return -1;
		}
		if (len < hdr.msgsize) {
			flock(mqd, LOCK_UN);
			errno = EMSGSIZE;
			return -1;
		}
		if (hdr.curmsgs > 0)
			break;
		flock(mqd, LOCK_UN);
		if (nonblock) {
			errno = EAGAIN;
			return -1;
		}
		if (expired(deadline)) {
			errno = ETIMEDOUT;
			return -1;
		}
		usleep(1000);
	}

	best.used = 0;
	best.prio = 0;
	best.seq = 0;
	best.len = 0;
	best_index = 0;
	for (i = 0; i < hdr.maxmsg; i++) {
		if (pread(mqd, &slot, sizeof(slot),
		    (off_t)slot_offset(&hdr, i)) != (ssize_t)sizeof(slot)) {
			flock(mqd, LOCK_UN);
			errno = EIO;
			return -1;
		}
		if (!slot.used)
			continue;
		if (!best.used || slot.prio > best.prio ||
		    (slot.prio == best.prio && slot.seq < best.seq)) {
			best = slot;
			best_index = i;
		}
	}
	if (!best.used) {
		flock(mqd, LOCK_UN);
		errno = EAGAIN;
		return -1;
	}
	if (best.len != 0 && pread(mqd, msg, best.len,
	    (off_t)(slot_offset(&hdr, best_index) + sizeof(slot))) !=
	    (ssize_t)best.len) {
		flock(mqd, LOCK_UN);
		errno = EIO;
		return -1;
	}
	slot.used = 0;
	slot.len = 0;
	if (pwrite(mqd, &slot, sizeof(slot),
	    (off_t)slot_offset(&hdr, best_index)) != (ssize_t)sizeof(slot)) {
		flock(mqd, LOCK_UN);
		errno = EIO;
		return -1;
	}
	hdr.curmsgs--;
	if (write_header(mqd, &hdr) != 0) {
		flock(mqd, LOCK_UN);
		return -1;
	}
	flock(mqd, LOCK_UN);
	if (prio != NULL)
		*prio = best.prio;
	return (ssize_t)best.len;
}

int
mq_notify(mqd_t mqd, const struct sigevent *event)
{
	struct mq_header hdr;

	if (mqd < 0) {
		errno = EINVAL;
		return -1;
	}
	if (event != NULL && event->sigev_notify == SIGEV_THREAD) {
		errno = ENOTSUP;
		return -1;
	}
	if (flock(mqd, LOCK_EX) != 0)
		return -1;
	if (read_header(mqd, &hdr) != 0) {
		flock(mqd, LOCK_UN);
		return -1;
	}
	if (event == NULL || event->sigev_notify == SIGEV_NONE) {
		hdr.notify_valid = 0;
		hdr.notify_pid = 0;
		hdr.notify_sig = 0;
	} else {
		hdr.notify_valid = 1;
		hdr.notify_pid = getpid();
		hdr.notify_sig = event->sigev_signo != 0 ? event->sigev_signo :
		    SIGALRM;
	}
	if (write_header(mqd, &hdr) != 0) {
		flock(mqd, LOCK_UN);
		return -1;
	}
	flock(mqd, LOCK_UN);
	return 0;
}

int
mq_getfd_np(mqd_t mqd)
{
	return mqd;
}
