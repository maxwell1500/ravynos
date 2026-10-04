/*-
 * Copyright (c) 2000 Dag-Erling Smorgrav
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote
 *    products derived from this software without specific prior written
 *    permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * Check for common security problems on a given path.
 *
 * ravynOS: vendored from FreeBSD lib/libutil/_secure_path.c, because
 * login_cap.c calls it on every login.conf and .login_conf before parsing
 * them and this tree has no other copy (FreeBSD's is in lib/libc, and
 * login_cap.c here is built into libutil, not libc).
 */
#include <sys/types.h>
#include <sys/stat.h>

#include <errno.h>
#include <stddef.h>
#include <syslog.h>

#include "libutil_internal.h"

/*
 * It must be:
 * 1. A regular file, and exists
 * 2. Owned and writable only by root (or given owner)
 * 3. Group ownership is given group or is non-group writable
 *
 * Returns:	-2 if file does not exist,
 *		-1 if security test failure
 *		0  otherwise
 */

int
_secure_path(const char *path, uid_t uid, gid_t gid)
{
    int		r = -1;
    struct stat	sb;
    const char	*msg = NULL;

    if (lstat(path, &sb) < 0) {
	if (errno == ENOENT) /* special case */
	    r = -2;  /* if it is just missing, skip the log entry */
	else
	    msg = "%s: cannot stat %s: %m";
    }
    else if (!S_ISREG(sb.st_mode))
    	msg = "%s: %s is not a regular file";
    else if (sb.st_mode & S_IWOTH)
    	msg = "%s: %s is world writable";
    else if ((int)uid != -1 && sb.st_uid != uid && sb.st_uid != 0) {
    	if (uid == 0)
    		msg = "%s: %s is not owned by root";
    	else
    		msg = "%s: %s is not owned by uid %d";
    } else if ((int)gid != -1 && sb.st_gid != gid && (sb.st_mode & S_IWGRP))
    	msg = "%s: %s is group writeable by non-authorised groups";
    else
    	r = 0;
    if (msg != NULL)
	syslog(LOG_ERR, msg, "_secure_path", path, uid);
    return r;
}