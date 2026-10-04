/*-
 * Copyright (c) 2026 ravynOS
 * All rights reserved.
 *
 * The one private declaration shared between the libutil translation units
 * that implement the login_cap(3) subsystem (login_cap.c, login_class.c,
 * login_auth.c, _secure_path.c).  It is not installed, which is what makes it
 * private: _secure_path(3) is FreeBSD libsysutil API, but nothing outside this
 * library should be reaching for it here.
 *
 * It exists because this tree has no other copy.  login_cap.c calls it on the
 * login.conf and .login_conf it is about to parse -- it is what stops a
 * world-writable or unowned capability database from being honoured -- and
 * FreeBSD's own lives in lib/libc, which login_cap.c is not part of here.
 */

#ifndef _LIBUTIL_INTERNAL_H_
#define	_LIBUTIL_INTERNAL_H_

#include <sys/types.h>

__BEGIN_DECLS

/*
 * FreeBSD _secure_path(3): -2 if the file does not exist, -1 on a security
 * test failure, 0 otherwise.  See _secure_path.c.
 */
int	_secure_path(const char *path, uid_t uid, gid_t gid);

__END_DECLS

#endif /* !_LIBUTIL_INTERNAL_H_ */