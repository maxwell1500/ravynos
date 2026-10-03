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
 * acl_is_trivial_np(3)
 *
 * An ACL is "trivial" when it conveys nothing the file's mode bits do not
 * already say: it is exactly the three POSIX.1e base entries
 * (ACL_USER_OBJ, ACL_GROUP_OBJ, ACL_OTHER) and nothing else.  A utility
 * that sees a trivial ACL can skip applying it, because the mode bits it
 * copied across already reproduce it.
 *
 * Why this is careful about failing
 * ---------------------------------
 * ravynOS has no POSIX.1e or NFSv4 ACL support at all.  The kernel
 * defines no acl_get_file / acl_set_file / extattr syscalls
 * (Kernel/xnu bsd/kern/syscalls.master), and the ACL layer in this
 * library is built on Darwin's filesec instead: acl_get_fd_np() and
 * acl_get_file1() (posix1e/acl_file.c) both reject any type other than
 * ACL_TYPE_EXTENDED with EINVAL.  So the only acl_t that can ever be
 * produced here is an ACL_TYPE_EXTENDED one, whose entries carry
 * ACL_EXTENDED_ALLOW / ACL_EXTENDED_DENY tags rather than POSIX.1e base
 * tags.
 *
 * Those two tag spaces are not interchangeable, and answering "trivial"
 * for one while meaning the other would be a fabrication.  So this
 * function reports the failure honestly:
 *
 *   - A NULL acl or NULL out-parameter is EINVAL.
 *   - An ACL that is not POSIX.1e-shaped -- which is every ACL ravynOS
 *     can actually produce -- is EINVAL.  The caller learns that the
 *     question cannot be answered, rather than being handed a
 *     convenient "yes, it is trivial".
 *   - A genuine POSIX.1e-shaped ACL is walked entry by entry and the
 *     answer is computed from what is actually there.
 *
 * BSD/bin/cp/utils.c and BSD/bin/mv/mv.c never actually reach this call
 * on ravynOS, and that is correct rather than a gap: they gate it behind
 * fpathconf(fd, _PC_ACL_NFS4) / _pathconf(fd, _PC_ACL_EXTENDED), and the
 * kernel answers ENOTSUP for both (vn_pathconf's default arm,
 * bsd/vfs/vfs_vnops.c:1929, reaches err_pathconf in
 * bsd/vfs/vfs_support.c:661), so they skip ACL preservation entirely.
 * This function exists so that a caller which does reach it gets a true
 * answer instead of a hardcoded one.
 */

#include <sys/types.h>
#include <sys/acl.h>
#include <sys/stat.h>
#include <errno.h>
#include <stddef.h>

#include "aclvar.h"

int
acl_is_trivial_np(acl_t acl, int *trivial_p)
{
	acl_entry_t entry;
	acl_tag_t tag;
	int entries = 0;

	if (acl == NULL || trivial_p == NULL) {
		errno = EINVAL;
		return (-1);
	}

	/*
	 * Walk the three base entries.  A trivial ACL has exactly these, in
	 * this order, with nothing appended; the first entry that is not one
	 * of them, or any fourth entry, means the ACL carries real
	 * information and is therefore not trivial.
	 */
	while (acl_get_entry(acl,
	    entries == 0 ? ACL_FIRST_ENTRY : ACL_NEXT_ENTRY, &entry) == 0) {
		acl_tag_t expected;

		switch (entries) {
		case 0:
			expected = ACL_USER_OBJ;
			break;
		case 1:
			expected = ACL_GROUP_OBJ;
			break;
		case 2:
			expected = ACL_OTHER;
			break;
		default:
			/* A fourth entry: definitely not trivial. */
			*trivial_p = 0;
			return (0);
		}

		if (acl_get_tag_type(entry, &tag) != 0) {
			/*
			 * Cannot classify the entries, so this is not an ACL
			 * we can reason about.  Report that rather than
			 * guessing.
			 */
			errno = EINVAL;
			return (-1);
		}
		if ((int)tag != (int)expected) {
			/*
			 * Not a POSIX.1e base entry.  On ravynOS this is the
			 * expected result for an ACL_TYPE_EXTENDED object,
			 * whose tags are ACL_EXTENDED_ALLOW/DENY; the answer
			 * cannot be computed, so say so.
			 */
			errno = EINVAL;
			return (-1);
		}

		entries++;
	}

	if (entries == 3) {
		/* Exactly the three base entries: nothing beyond the mode. */
		*trivial_p = 1;
		return (0);
	}

	/* Fewer than three: not a well-formed POSIX.1e ACL. */
	errno = EINVAL;
	return (-1);
}
