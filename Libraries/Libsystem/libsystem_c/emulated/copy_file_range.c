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
 * copy_file_range(2)
 *
 * ravynOS's kernel has no copy_file_range syscall.  Kernel/xnu
 * bsd/kern/syscalls.master defines 34 chflags and 35 fchflags and no
 * SYS_copy_file_range at all; bsd/vfs/vfs_syscalls.c has no
 * copy_file_range entry point, and libsystem_kernel has no wrapper (its
 * sys/_*.s files define one wrapper per syscall, and there is no
 * SYS_copy_file_range among them).  Grepping the tree for
 * "copy_file_range" outside BSD userland hits only BSD/include/unistd.h's
 * declaration, so there is no reference implementation here to defer to.
 *
 * It is therefore built from the primitives that do exist and are real:
 * pread(2) and pwrite(2), both already used elsewhere inside this library
 * (db/hash/FreeBSD/hash_page.c, db/hash/FreeBSD/hash.c).
 *
 * Contract, as specified by Linux and FreeBSD and as BSD/bin/cp/utils.c
 * depends on:
 *
 *   - Returns the number of bytes copied, which may be fewer than len.
 *     A return of 0 means end-of-input was reached.
 *   - A NULL off_in/off_out means "use the file's current offset, and
 *     advance it".  A non-NULL one is read on entry and updated on return
 *     with the offset just past the last byte copied.
 *   - Returns -1 with errno set on error.
 *   - Only flags == 0 is defined; anything else is EINVAL.  Upstream
 *     reserves flag bit 0 for future cross-filesystem negotiation.
 *   - EINTR on a read is reported to the caller rather than retried,
 *     matching pread(2).  cp(1) treats a negative return as failure, which
 *     is the correct outcome: a signal interrupted the copy, so the caller
 *     must not assume it completed.  A short write is a different case --
 *     that is normal, not an error, so it is retried until the chunk is
 *     fully written rather than silently truncating the destination.
 *
 * Unlike a same-filesystem kernel implementation this does not preserve
 * holes: data moves byte for byte, so a sparse input becomes a dense
 * output.  That is the honest consequence of the available primitives and
 * is stated here rather than papered over.
 */

#include <sys/types.h>
#include <stddef.h>
#include <errno.h>
#include <unistd.h>

/*
 * cp(1) calls this with len == SSIZE_MAX (BSD/bin/cp/utils.c:210), so this
 * must loop rather than attempt a single transfer.  64 KiB matches the
 * kernel's own maximum recommended transfer size (vn_pathconf answers
 * 65536 for _PC_REC_MAX_XFER_SIZE, Kernel/xnu/bsd/vfs/vfs_vnops.c:1891)
 * and keeps the buffer off the heap so the call stays usable before
 * malloc is available.
 */
#define	CFR_BUFSIZE	65536

ssize_t
copy_file_range(int fd_in, off_t *off_in, int fd_out, off_t *off_out,
    size_t len, unsigned int flags)
{
	char buf[CFR_BUFSIZE];
	size_t remaining = len;
	size_t total = 0;
	off_t in_pos, out_pos;
	int saved_errno = 0;

	if (flags != 0) {
		errno = EINVAL;
		return (-1);
	}

	/*
	 * Establish both starting positions before any I/O, so a failure to
	 * determine them is reported as -1 rather than after a partial copy.
	 */
	if (off_in != NULL) {
		in_pos = *off_in;
	} else if ((in_pos = lseek(fd_in, 0, SEEK_CUR)) == (off_t)-1) {
		return (-1);
	}
	if (off_out != NULL) {
		out_pos = *off_out;
	} else if ((out_pos = lseek(fd_out, 0, SEEK_CUR)) == (off_t)-1) {
		return (-1);
	}

	while (remaining > 0) {
		size_t chunk = (remaining < CFR_BUFSIZE) ? remaining : CFR_BUFSIZE;
		size_t done;
		ssize_t nread, nwritten;

		nread = pread(fd_in, buf, chunk, in_pos);
		if (nread < 0) {
			saved_errno = errno;
			break;
		}
		if (nread == 0) {
			/* End of input: a short count, not an error. */
			break;
		}

		/*
		 * Drain the whole chunk.  pwrite(2) may return short, and
		 * stopping early would silently truncate the destination.
		 */
		for (done = 0; done < (size_t)nread; ) {
			nwritten = pwrite(fd_out, buf + done,
			    (size_t)nread - done, out_pos + (off_t)done);
			if (nwritten < 0) {
				if (errno == EINTR)
					continue;
				saved_errno = errno;
				break;
			}
			done += (size_t)nwritten;
		}
		if (done != (size_t)nread)
			break;

		in_pos += nread;
		out_pos += nread;
		total += (size_t)nread;
		remaining -= (size_t)nread;
	}

	/*
	 * Commit the positions.  pread(2)/pwrite(2) leave the file offset
	 * untouched, so the "NULL means use and advance the current offset"
	 * half of the contract is discharged here with an explicit lseek(2).
	 * A failure to record the position is only fatal if nothing moved;
	 * otherwise the byte count already returned is the useful answer and
	 * the error is reported through errno alongside it.
	 */
	if (off_in != NULL) {
		*off_in = in_pos;
	} else if (lseek(fd_in, in_pos, SEEK_SET) == (off_t)-1 &&
	    saved_errno == 0) {
		saved_errno = errno;
	}
	if (off_out != NULL) {
		*off_out = out_pos;
	} else if (lseek(fd_out, out_pos, SEEK_SET) == (off_t)-1 &&
	    saved_errno == 0) {
		saved_errno = errno;
	}

	if (total == 0 && saved_errno != 0) {
		errno = saved_errno;
		return (-1);
	}
	if (saved_errno != 0)
		errno = saved_errno;
	return ((ssize_t)total);
}
