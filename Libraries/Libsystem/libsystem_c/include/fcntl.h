/*
 * Copyright (c) 2000 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
#include <sys/fcntl.h>

/*
 * FreeBSD's open(2)/openat(2) "resolve beneath" safety flags.
 *
 * FreeBSD spells this guarantee AT_RESOLVE_BENEATH (in the *at flag word)
 * and O_RESOLVE_BENEATH (in the open(2) flag word): the path is resolved
 * normally, but no symbolic link encountered anywhere along it may lead
 * outside the directory named by the dirfd.
 *
 * ravynOS's kernel implements the same guarantee, under Darwin's names:
 * O_NOFOLLOW_ANY and AT_SYMLINK_NOFOLLOW_ANY.  See Kernel/xnu:
 *
 *   bsd/vfs/vfs_vnops.c:412      O_NOFOLLOW_ANY && O_NOFOLLOW -> EINVAL
 *   bsd/vfs/vfs_vnops.c:447,565  vn_open_auth() sets NAMEI_NOFOLLOW_ANY
 *   bsd/vfs/vfs_syscalls.c:7395  fstatat() accepts AT_SYMLINK_NOFOLLOW_ANY
 *                                alongside AT_SYMLINK_NOFOLLOW
 *
 * and NAMEI_NOFOLLOW_ANY makes namei(9) return ELOOP on the first symlink
 * component it meets.  So the guarantee is genuinely enforced, and mapping
 * the FreeBSD spellings onto the Darwin ones keeps it enforced rather than
 * silently dropping it -- which is what defining these to zero would do.
 *
 * The Darwin flags are *stricter* than FreeBSD's: they refuse every symlink
 * in the path, not only one that escapes.  Refusing more than necessary is
 * the safe direction for a flag whose entire purpose is to prevent an
 * escape, and it is what the rest of ravynOS's own callers already pass.
 */
#define	O_RESOLVE_BENEATH	O_NOFOLLOW_ANY
#define	AT_RESOLVE_BENEATH	AT_SYMLINK_NOFOLLOW_ANY
