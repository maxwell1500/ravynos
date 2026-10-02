/*
 * C++ static initialization guard protocol (__cxa_guard_*).
 *
 * The C++ compiler emits calls to these three functions around every
 * function-local static variable that has a non-trivial initializer:
 *
 *	if (__cxa_guard_acquire(&guard)) {
 *		... run the initializer ...
 *		__cxa_guard_release(&guard);
 *	}
 *
 * and, if the initializer throws,
 *
 *	__cxa_guard_abort(&guard);
 *
 * so the next attempt retries the initialization.
 *
 * The guard word is a state variable with three meaningful values:
 *
 *	0  initialization not started (or was aborted)
 *	1  initialization in progress by exactly one thread
 *	2  initialization complete
 *
 * They normally come from libc++abi. ravynOS has no libc++abi component, but
 * libSystem.B.dylib references the three symbols, so dyld cannot bind the
 * image without them. The protocol is self-contained -- an atomic word test and
 * set, plus a blocking wait for the winner -- so it lives here in libc.
 */

#include <stdint.h>

typedef int cxa_guard_t;

/*
 * Block until *guard leaves the "initialization in progress" state. State 2
 * means somebody finished; state 0 means the initializer threw and was rolled
 * back, so this thread retries the initialization itself. Both return at once,
 * so only the running state needs waiting on.
 */
static void
cxa_guard_wait(cxa_guard_t *guard)
{
	while (__atomic_load_n(guard, __ATOMIC_ACQUIRE) == 1)
		__asm__ __volatile__("pause" ::: "memory");
}

/*
 * Returns nonzero if the caller must run the guarded initializer, zero if it
 * has already run (or is running elsewhere). The loser of the race never
 * returns until the winner has published "complete".
 */
int
__cxa_guard_acquire(cxa_guard_t *guard)
{
	cxa_guard_t expected = 0;

	if (__atomic_compare_exchange_n(guard, &expected, 1, 0,
	    __ATOMIC_ACQUIRE, __ATOMIC_RELAXED))
		return 1;	/* we own the initialization */

	/* Expected held 1 (in progress) or 2 (done). Both need a wait. */
	cxa_guard_wait(guard);

	return __atomic_load_n(guard, __ATOMIC_ACQUIRE) != 2;
}

void
__cxa_guard_release(cxa_guard_t *guard)
{
	__atomic_store_n(guard, 2, __ATOMIC_RELEASE);
}

void
__cxa_guard_abort(cxa_guard_t *guard)
{
	__atomic_store_n(guard, 0, __ATOMIC_RELEASE);
}