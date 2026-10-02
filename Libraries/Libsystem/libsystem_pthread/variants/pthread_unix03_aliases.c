/*
 * pthread_unix03_aliases.c -- the $UNIX2003 spellings of the pthread
 * entry points, as Mach-O symbol aliases.
 *
 * WHY THIS FILE EXISTS
 * libsystem_pthread is built with -D__DARWIN_UNIX03 and the SDK's
 * libc-features.h setting __DARWIN_ONLY_UNIX_CONFORMANCE to 0, so
 * sys/cdefs.h expands
 *
 *     #define __DARWIN_SUF_UNIX03 "$UNIX2003"
 *     #define __DARWIN_ALIAS(sym) __asm("_" __STRING(sym) __DARWIN_SUF_UNIX03)
 *
 * and the SDK's pthread/pthread.h declares
 *
 *     int pthread_rwlock_rdlock(pthread_rwlock_t *) __DARWIN_ALIAS(pthread_rwlock_rdlock);
 *
 * A client compiled against that header therefore calls
 * _pthread_rwlock_rdlock$UNIX2003. Two clients in this closure do:
 * libobjc, and the prebuilt LLVM libunwind.a that libunwind.dylib and
 * libobjc both link. All three were importing the name with nothing to
 * bind it to.
 *
 * Why nothing binds it: this component compiles its own pthread.h rather
 * than the SDK's, so the definitions in pthread_cond.c and pthread_rwlock.c
 * land as the unsuffixed _pthread_rwlock_rdlock and _pthread_cond_wait. nm
 * on libsystem_pthread.dylib shows those names defined and no $UNIX2003
 * name at all. The functions themselves are complete and correct -- they
 * are the same ones every pthread client already calls successfully -- so
 * what is missing is the second spelling, not the code.
 *
 * Darwin builds Libc and libsystem_pthread from parallel VARIANT_UNIX03
 * source sets and exports both spellings; this build only produces the
 * unsuffixed set. These aliases supply the other one.
 *
 * They are .globl/.set aliases rather than wrapper functions on purpose: an
 * alias resolves to the identical address, so there is no second
 * implementation that could diverge from the one the unsuffixed callers
 * use, and no call overhead. `nm` shows all three spellings at one address.
 */

/*
 * COND_WAIT is the odd one out: pthread_cond_wait is a cancellation point,
 * so its $UNIX2003 variant is a distinct entry point on Apple rather than a
 * spelling of the same code -- Darwin's VARIANT_UNIX03 set implements it
 * with cancellation disabled around the wait. It is therefore NOT aliased
 * here; see pthread_cond_unix03.c for the real implementation, which the
 * Makefile compiles into this component alongside this file.
 */

#define RAV_PTHREAD_UNIX03_ALIAS(base)                                       \
	__asm__(".globl _" #base "$UNIX2003\n"                              \
		".set   _" #base "$UNIX2003, _" #base "\n")

RAV_PTHREAD_UNIX03_ALIAS(pthread_rwlock_rdlock);
RAV_PTHREAD_UNIX03_ALIAS(pthread_rwlock_wrlock);
RAV_PTHREAD_UNIX03_ALIAS(pthread_rwlock_unlock);
