/*
 * Copyright (c) 2000-2003 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. The rights granted to you under the License
 * may not be used to create, or enable the creation or redistribution of,
 * unlawful or unlicensed copies of an Apple operating system, or to
 * circumvent, violate, or enable the circumvention or violation of, any
 * terms of an Apple operating system software license agreement.
 *
 * Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_END@
 */

#ifndef _SYS_PTHREAD_INTERNAL_H_
#define _SYS_PTHREAD_INTERNAL_H_

#include <sys/user.h>
#include <kern/thread_call.h>

#ifdef __LP64__
#define _KSYN_WAITQ_ELEMENT_SIZE	48
#else
#define _KSYN_WAITQ_ELEMENT_SIZE	32
#endif

/*
 * This used to be an opaque blob sized so that the pthread kext's own copy of
 * the structure (Kernel/Extensions/pthread/kern/kern_internal.h) would fit in
 * the uthread's uu_save union.  ravynOS now links that code statically, so
 * there is no module boundary left to hide behind and the two definitions
 * would collide - the real one has to be shared.  It is slightly larger than
 * the old blob, but uu_save is sized by its largest member and no other member
 * is that small, so struct uthread's layout is unchanged (asserted in
 * sys/user.h).
 */
#if defined(PSYNCH) && defined(BSD_KERNEL_PRIVATE)

struct ksyn_waitq_element {
	TAILQ_ENTRY(ksyn_waitq_element) kwe_list;	/* link to other list members */
	void *          kwe_kwqqueue;		/* queue blocked on */
	thread_t        kwe_thread;
	uint16_t        kwe_state;		/* state */
	uint16_t        kwe_flags;
	uint32_t        kwe_lockseq;		/* the sequence of the entry */
	uint32_t	kwe_count;		/* upper bound on number of matches still pending */
	uint32_t 	kwe_psynchretval;	/* thread retval */
	void		*kwe_uth;		/* uthread */
};

#endif /* PSYNCH && BSD_KERNEL_PRIVATE */

void workq_mark_exiting(struct proc *);
void workq_exit(struct proc *);
void pthread_init(void);

#endif /* _SYS_PTHREAD_INTERNAL_H_ */
