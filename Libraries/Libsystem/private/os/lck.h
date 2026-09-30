/*
 * ============================================================================
 * PROVISIONAL - ravynOS-INTERNAL. NOT Apple's ABI. DO NOT TREAT AS A RECOVERED
 * STRUCTURE.
 * ============================================================================
 *
 * WHY THIS FILE EXISTS
 *
 * There is no lck.h anywhere in this tree. Upstream xnu ships
 * osfmk/kern/lck.h and libkern/lck.h; this checkout has neither -- `find . -name
 * lck.h' returns nothing, and lck_spin_t is declared only in kernel-only osfmk
 * headers (osfmk/i386/locks.h, osfmk/kern/locks_internal.h), which cannot be
 * included by a userspace dylib.
 *
 * That breaks libsystem_trace, and only indirectly:
 *
 *     Kernel/xnu/libkern/os/log_encode_types.h:39   #include "log_mem.h"
 *     Kernel/xnu/libkern/os/log_mem.h:36            lck_spin_t  lm_lock;
 *
 * so <os/log_encode_types.h> -- which log.c includes at log.c:50 -- drags in
 * log_mem.h, which needs lck_spin_t, which does not exist. The failure is
 *
 *     Kernel/xnu/libkern/os/log_mem.h:36:2: error: unknown type name 'lck_spin_t'
 *
 * Note that log_mem.h uses the type ONLY as a struct member and calls no lock
 * routine on it, so nothing in libsystem_trace ever takes this lock; it exists
 * solely to satisfy the kernel-side header that the userspace encoder never
 * actually uses.
 *
 * WHY IT IS SAFE
 *
 * No code in this tree reads or writes lm_lock. Defining the type is enough to
 * compile log_mem.h; the struct is never instantiated by any reachable path in
 * a userspace process. If libsystem_trace ever starts using logmem_t for real,
 * this file must be replaced by the real lock header rather than extended --
 * a no-op lock on a path that actually needs mutual exclusion would be a
 * silent correctness bug, which is worse than the compile error it fixes here.
 * ============================================================================
 */

#ifndef __RAVYNOS_OS_LCK_PRIVATE_H
#define __RAVYNOS_OS_LCK_PRIVATE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>		/* NULL */

#ifdef __cplusplus
extern "C" {
#endif

/*
 * A plain test-and-test-and-set spinlock built on __atomic. Real, not a stub:
 * it is correct if anything ever does use it. See the note above about when it
 * must be replaced rather than relied upon.
 */
typedef struct lck_spin_s {
	volatile uint32_t	lck_atomic;
} lck_spin_t;

static inline void
lck_spin_init(lck_spin_t *lck)
{
	if (lck != NULL) {
		__atomic_store_n(&lck->lck_atomic, 0U, __ATOMIC_RELEASE);
	}
}

static inline bool
lck_spin_grab(lck_spin_t *lck)
{
	uint32_t	expected = 0U;

	if (lck == NULL) {
		return false;
	}
	return __atomic_compare_exchange_n(&lck->lck_atomic, &expected, 1U,
	    false, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED);
}

static inline void
lck_spin_release(lck_spin_t *lck)
{
	if (lck != NULL) {
		__atomic_store_n(&lck->lck_atomic, 0U, __ATOMIC_RELEASE);
	}
}

#ifdef __cplusplus
}
#endif

#endif /* __RAVYNOS_OS_LCK_PRIVATE_H */