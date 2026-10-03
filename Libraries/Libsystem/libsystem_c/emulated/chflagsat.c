/*
 * Copyright (c) 2026 ravynOS. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License,
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * chflagsat(2)
 *
 * ravynOS's kernel has no chflagsat syscall.  Kernel/xnu
 * bsd/kern/syscalls.master defines 34 chflags and 35 fchflags and no
 * chflagsat; bsd/vfs/vfs_syscalls.c implements only chflags(2),
 * fchflags(2) and the fchownat-style helpers, none of which take a dirfd.
 *
 * It is built on setattrlistat(2), which is a real syscall here (SYS_
 * setattrlistat 524) and which does take the (fd, path) pair -- exactly
 * the shape chflagsat needs.  bsd/vfs/vfs_attrlist.c:4776 resolves the
 * path with nameiat(2) against uap->fd, so the dirfd-relative lookup
 * happens in the kernel rather than being faked in user space.  Setting
 * ATTR_CMN_FLAGS with a uint32_t is the same path chflags(2) itself uses
 * via vnode_setattr(VATTR_SET(&va, va_flags, flags)).
 *
 * Symlink handling maps directly: the kernel's setattrlistat clears its
 * FOLLOW flag when FSOPT_NOFOLLOW or FSOPT_NOFOLLOW_ANY is set
 * (vfs_attrlist.c:4745-4750), and AT_SYMLINK_NOFOLLOW /
 * AT_RESOLVE_BENEATH are translated to those options.  FSOPT_NOFOLLOW_ANY
 * is the resolve-beneath form -- see the note in <fcntl.h>, where
 * AT_RESOLVE_BENEATH is defined as AT_SYMLINK_NOFOLLOW_ANY -- so it is
 * passed through as FSOPT_NOFOLLOW_ANY and the kernel enforces it with
 * NAMEI_NOFOLLOW_ANY.
 *
 * Errors are propagated, never swallowed.  In particular a filesystem that
 * does not store BSD flags makes the kernel return ENOTSUP: chflags1()
 * does `if ((error == 0) && !VATTR_IS_SUPPORTED(&va, va_flags)) error =
 * ENOTSUP` (bsd/vfs/vfs_syscalls.c:7623), and setattrlist's own
 * unsupported-attribute handling behaves the same way.  cp(1) already
 * treats ENOTSUP as non-fatal for this call (BSD/bin/cp/utils.c:381-392
 * only reports when the call fails and the caller's warning logic keys off
 * errno), so propagating it is both correct and what the utility expects.
 * Reporting success here would claim flags were set on a filesystem that
 * silently dropped them.
 */

#include <sys/types.h>
#include <sys/attr.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

int
chflagsat(int dfd, const char *path, unsigned int flags, int atflags)
{
	struct attrlist al;
	unsigned int fflags = flags;
	unsigned long options = 0;

	/* Reject anything we cannot honour rather than ignore it. */
	if (atflags & ~(AT_SYMLINK_NOFOLLOW | AT_RESOLVE_BENEATH)) {
		errno = EINVAL;
		return (-1);
	}
	if (atflags & AT_RESOLVE_BENEATH) {
		/*
		 * Refuse any symlink anywhere in the path.  The kernel backs
		 * this with NAMEI_NOFOLLOW_ANY, which returns ELOOP on the
		 * first symlink component met.
		 */
		options |= FSOPT_NOFOLLOW_ANY;
	} else if (atflags & AT_SYMLINK_NOFOLLOW) {
		/* Do not follow a symlink in the final component only. */
		options |= FSOPT_NOFOLLOW;
	}

	memset(&al, 0, sizeof(al));
	al.bitmapcount = ATTR_BIT_MAP_COUNT;
	al.commonattr = ATTR_CMN_FLAGS;

	/*
	 * The flag value is passed as a uint32_t; ATTR_CMN_FLAGS is defined
	 * with .size = sizeof(uint32_t) in the kernel's attribute table
	 * (bsd/vfs/vfs_attrlist.c:343), so the buffer must match exactly or
	 * setattrlist(2) rejects it with EINVAL.
	 */
	return setattrlistat(dfd, path, &al, &fflags,
	    sizeof(fflags), options);
}
