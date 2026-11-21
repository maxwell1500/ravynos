/*
 * Copyright (c) 2013 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.apple.com/publicsource and read it before using this file.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

#include <sys/errno.h>
#include <sys/semaphore.h>
#include <sys/types.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/*
 * sem_init(3) and friends were ENOSYS.  The rest of the POSIX semaphore API
 * already exists in libsystem_kernel (sem_open/sem_close/sem_wait/sem_post
 * are syscall stubs; the kernel, bsd/kern/posix_sem.c, casts the sem_t value
 * to a file descriptor).  An unnamed semaphore is therefore a named psem that
 * is unlinked immediately: the open fd keeps it alive, and sem_t stores it.
 */

int
sem_init(sem_t *s, int pshared, unsigned int value)
{
	char name[64];
	static unsigned long sequence;
	sem_t *opened;
	int fd;

	if (s == NULL) {
		errno = EINVAL;
		return -1;
	}
	/* The fd-backed construction is process-private by definition. */
	if (pshared != 0) {
		errno = ENOSYS;
		return -1;
	}
	if (value > SEM_VALUE_MAX) {
		errno = EINVAL;
		return -1;
	}

	snprintf(name, sizeof(name), "/ravynsem.%d.%lu",
	    (int)getpid(), sequence++);

	opened = sem_open(name, O_CREAT | O_EXCL, 0600, (int)value);
	if (opened == SEM_FAILED)
		return -1;

	fd = (int)(intptr_t)opened;
	sem_unlink(name);

	*s = (sem_t)fd;
	return 0;
}

int
sem_destroy(sem_t *s)
{
	if (s == NULL || *s < 0) {
		errno = EINVAL;
		return -1;
	}
	if (sem_close((sem_t *)(intptr_t)*s) != 0)
		return -1;
	*s = -1;
	return 0;
}

int
sem_getvalue(sem_t * __restrict s, int * __restrict value)
{
	if (s == NULL || value == NULL || *s < 0) {
		errno = EINVAL;
		return -1;
	}
	/* There is no syscall that reports the kernel psem count, so sample it:
	 * a successful trywait proves the value was at least one, and posting
	 * immediately puts it back.  POSIX allows the value to change between
	 * the call and the caller's use of it. */
	if (sem_trywait(s) == 0) {
		sem_post(s);
		*value = 1;
	} else if (errno == EAGAIN) {
		*value = 0;
	} else {
		return -1;
	}
	return 0;
}
