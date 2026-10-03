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
 * vfork(2) -- fork-based fallback.  THIS IS NOT REAL vfork.
 *
 * Read this before trusting the name.  Everything a caller is normally
 * entitled to assume about vfork() is absent here:
 *
 *   - NO address-space sharing.  Real vfork's defining property is that
 *     the child runs in the parent's address space until it execve()s or
 *     _exit()s.  This child gets an ordinary private copy-on-write
 *     address space, exactly as fork(2) would give it.
 *
 *   - NO execve/_exit-only restriction is enforced, and none can be.
 *     Nothing in this implementation stops a child from reading or
 *     writing memory.  It does not need to: because the child has its
 *     own address space, the classic vfork hazard -- a child corrupting
 *     its parent's state, or racing the parent through a lock the parent
 *     already holds -- cannot arise.  Correctness here comes from fork's
 *     isolation plus the caller's own discipline, NOT from any guarantee
 *     this function provides.
 *
 *   - COST: a page-table copy per call.  That is a performance
 *     difference, not a correctness one.  Real vfork avoids the copy by
 *     sharing; this one pays it.
 *
 * Why a fallback at all
 * ---------------------
 * ravynOS's kernel has no usable vfork syscall.  bsd/kern/syscalls.master
 * slot 66 is guarded by "#if CONFIG_VFORK", and CONFIG_VFORK is never
 * defined anywhere in the tree, so the slot compiles to the "#else" arm,
 * the placeholder "AUE_NULL ... { old vfork }".  The real definition
 * (line 66, "int vfork(void) NO_SYSCALL_STUB") is behind that #if and is
 * therefore not compiled in.  Consistently, no vfork() exists anywhere in
 * bsd/kern or bsd/vfs.  NO_SYSCALL_STUB also means libSystem gets no
 * wrapper generated for it, so there is nothing to call and nothing that
 * would work if called.  A caller invoking SYS_vfork 66 directly would
 * reach the null stub.
 *
 * Note that <unistd.h> still declares vfork() (usr/include/unistd.h:773),
 * so BSD userland that calls it compiles but must be given a definition
 * to link against.  mv(1) calls it twice (BSD/bin/mv/mv.c:382 and :409),
 * in each case solely to exec _PATH_CP or _PATH_RM.
 *
 * Why __fork() and not fork()
 * --------------------------
 * This is the one part that must stay as written.  fork()
 * (libsystem_c/sys/fork.c) calls _libSystem_atfork_prepare/_parent/_child,
 * which run the pthread atfork callbacks: they can take locks and mutate
 * process-wide state.  Those handlers exist to make ordinary fork() safe
 * for the child, and running them in a process created to be an exec
 * trampoline is pure overhead at best.  __fork() is the bare syscall
 * wrapper underneath fork() ("___fork", defined in libsystem_kernel), so
 * calling it directly gives a child process with no atfork handler chain
 * executed -- the behaviour a vfork caller expects.
 *
 * This is the same shape as the POSIX-obsolescent libc vfork aliases.
 */

#include <sys/types.h>
#include <unistd.h>

extern pid_t __fork(void);

pid_t
vfork(void)
{
	/*
	 * The bare syscall wrapper, deliberately bypassing fork()'s atfork
	 * handler chain.  This gives a private COW address space, NOT the
	 * shared space real vfork provides -- see the file comment.
	 */
	return (__fork());
}
