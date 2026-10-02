/*
 * symbol_variants.c -- Mach-O symbol variants that libsystem_kernel owes its
 * clients but does not currently export.
 *
 * Three groups, all of them real code rather than placeholders.
 *
 * ---------------------------------------------------------------------------
 * 1. The $UNIX2003 variants of the syscall wrappers.
 * ---------------------------------------------------------------------------
 * Every ravynOS Libsystem component is compiled with the SDK's
 * libc-features.h configuration, in which __DARWIN_UNIX03 is 1 and
 * __DARWIN_ONLY_UNIX_CONFORMANCE is 0. sys/cdefs.h therefore expands
 *
 *     #define __DARWIN_SUF_UNIX03 "$UNIX2003"
 *     #define __DARWIN_ALIAS(sym) __asm("_" __STRING(sym) __DARWIN_SUF_UNIX03)
 *
 * so the SDK's unistd.h declares, for example,
 *
 *     int close(int) __DARWIN_ALIAS_C(close);
 *
 * and every consumer compiled against that header emits a call to
 * _close$UNIX2003. libobjc and libcompiler_rt both do, and both were
 * importing it with nothing in the closure to bind it.
 *
 * The reason nothing binds it is visible in nm: libsystem_kernel exports
 * _close, _fsync, _open, _pread, _write and _mprotect and NOT one
 * $UNIX2003-suffixed name. The wrapper bodies are present and correct --
 * this component already defines the unsuffixed symbol -- so the missing
 * half is the alias, and the alias is what the SDK's own header promises.
 * That is why these are emitted as .globl/.set aliases below: each name
 * resolves to the address of the real, already-working wrapper rather than
 * to a second copy of it that could drift.
 *
 * Darwin gets this the same way, by building Libc's UNIX03 variant archives
 * and exporting both spellings from libsystem_c/libsystem_kernel. Only the
 * unsuffixed variant is built here, so the aliases supply the second
 * spelling.
 *
 * ---------------------------------------------------------------------------
 * 2. open$NOCANCEL / openat$NOCANCEL.
 * ---------------------------------------------------------------------------
 * These are NOT aliases. They are genuinely separate entry points: the
 * $NOCANCEL family must issue the non-cancelable syscall
 * (SYS_open_nocancel / SYS_openat_nocancel) rather than the cancelable
 * one, because a cancellation point in a non-cancelable region is a bug
 * the caller cannot recover from. This component already contains both
 * syscall wrappers -- nm shows ___open_nocancel and ___openat_nocancel --
 * so the $NOCANCEL functions below are thin, faithful forwarders to them,
 * carrying the same varargs signature the public prototypes use.
 *
 * Libraries/Libsystem/static/stubs.c already carries the identical pair for
 * the static libc, with the same reasoning written out; these are the
 * dylib-side equivalents and they have to live in the component that owns
 * the underlying syscalls.
 *
 * ---------------------------------------------------------------------------
 * 3. mach_msg_priority_*_inline.
 * ---------------------------------------------------------------------------
 * Kernel/xnu/libsyscall/mach/mach_msg.c defines the five non-inline
 * mach_msg_priority_* entry points by forwarding to their _inline twins:
 *
 *     mach_msg_priority_encode(...)
 *         { return mach_msg_priority_encode_inline(override_qos, qos, relpri); }
 *
 * Those twins are `static inline` functions declared in osfmk/mach/message.h
 * inside a `#if PRIVATE` region. This component compiles with -DPRIVATE, so
 * the declarations are visible -- but the header the build actually reads is
 * the SDK's mach/message.h, and this SDK's copy carries no `#if PRIVATE`
 * region for the priority helpers at all. The result is that each call site
 * sees no declaration, falls back to an implicit `int f()` declaration, and
 * emits a call to an undefined external named
 * _mach_msg_priority_encode_inline. nm on mach_msg.o shows exactly that:
 * five defined _mach_msg_priority_* wrappers and five undefined
 * _mach_msg_priority_*_inline references beside them.
 *
 * The fix belongs in the header, which is generated, so the definitions are
 * supplied here instead. The bodies are the xnu ones, transcribed: these are
 * the bit-packing rules for a mach_msg priority word, and libsystem_kernel's
 * own five forwarding wrappers call them, so getting them wrong would
 * corrupt every priority word the component hands the kernel. They are real
 * definitions, and being real out-of-line functions they are also what a
 * client that calls the _inline spelling directly gets.
 */

#include <sys/types.h>
#include <fcntl.h>
#include <stdarg.h>

/*
 * O_TMPFILE is a Linux open(2) flag with no Darwin counterpart: the public
 * Darwin open/openat prototypes never carry a mode argument for it, so this
 * SDK's fcntl.h does not define it. Defining it to 0 makes the mode-argument
 * test below reduce to the O_CREAT case, which is the whole of the condition
 * that can apply on Darwin.
 */
#ifndef O_TMPFILE
#define O_TMPFILE 0
#endif

/* ------------------------------------------------------------------------ */
/* 1. $UNIX2003 aliases for the wrappers this component already defines.     */
/* ------------------------------------------------------------------------ */

#define RAV_UNIX03_ALIAS(base)                                              \
	__asm__(".globl _" #base "$UNIX2003\n"                              \
		".set   _" #base "$UNIX2003, _" #base "\n")

RAV_UNIX03_ALIAS(close);
RAV_UNIX03_ALIAS(fsync);
RAV_UNIX03_ALIAS(open);
RAV_UNIX03_ALIAS(pread);
RAV_UNIX03_ALIAS(write);
RAV_UNIX03_ALIAS(mprotect);

/* ------------------------------------------------------------------------ */
/* 2. The $NOCANCEL open family -- real forwarders to the nocancel syscalls. */
/* ------------------------------------------------------------------------ */

extern int __open_nocancel(const char *, int, ...);
extern int __openat_nocancel(int, const char *, int, ...);

int rav_open_nocancel(const char *path, int flags, ...)
	__asm__("_open$NOCANCEL");
int
rav_open_nocancel(const char *path, int flags, ...)
{
	/* O_CREAT and O_TMPFILE both carry a trailing mode argument. */
	mode_t mode = 0;
	if (flags & (O_CREAT | O_TMPFILE)) {
		va_list ap;
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
	}
	return __open_nocancel(path, flags, mode);
}

int rav_openat_nocancel(int dirfd, const char *path, int flags, ...)
	__asm__("_openat$NOCANCEL");
int
rav_openat_nocancel(int dirfd, const char *path, int flags, ...)
{
	mode_t mode = 0;
	if (flags & (O_CREAT | O_TMPFILE)) {
		va_list ap;
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
	}
	return __openat_nocancel(dirfd, path, flags, mode);
}

/* ------------------------------------------------------------------------ */
/* 3. mach_msg_priority_*_inline -- the xnu bodies, out of line.              */
/* ------------------------------------------------------------------------ */

#define MACH_MSG_QOS_LAST			6
#define MACH_MSG_PRIORITY_RELPRI_SHIFT		8
#define MACH_MSG_PRIORITY_QOS_SHIFT		16
#define MACH_MSG_PRIORITY_QOS_MASK		(0xf << MACH_MSG_PRIORITY_QOS_SHIFT)
#define MACH_MSG_PRIORITY_OVERRIDE_SHIFT	20
#define MACH_MSG_PRIORITY_OVERRIDE_MASK		(0xf << MACH_MSG_PRIORITY_OVERRIDE_SHIFT)

int
mach_msg_priority_is_pthread_priority_inline(unsigned int pri)
{
	return (pri & 0xff) == 0xff;
}

unsigned int
mach_msg_priority_encode_inline(unsigned int override_qos,
		unsigned int qos, int relpri)
{
	unsigned int pri = 0;
	if (qos > 0 && qos <= MACH_MSG_QOS_LAST) {
		pri |= (unsigned int)(qos << MACH_MSG_PRIORITY_QOS_SHIFT);
		pri |= (unsigned int)((unsigned char)(relpri - 1) <<
		    MACH_MSG_PRIORITY_RELPRI_SHIFT);
	}
	if (override_qos > 0 && override_qos <= MACH_MSG_QOS_LAST) {
		pri |= (unsigned int)(override_qos <<
		    MACH_MSG_PRIORITY_OVERRIDE_SHIFT);
	}
	return pri;
}

unsigned int
mach_msg_priority_overide_qos_inline(unsigned int pri)
{
	pri &= MACH_MSG_PRIORITY_OVERRIDE_MASK;
	pri >>= MACH_MSG_PRIORITY_OVERRIDE_SHIFT;
	return (pri <= MACH_MSG_QOS_LAST ? pri : 0);
}

unsigned int
mach_msg_priority_qos_inline(unsigned int pri)
{
	pri &= MACH_MSG_PRIORITY_QOS_MASK;
	pri >>= MACH_MSG_PRIORITY_QOS_SHIFT;
	return (pri <= MACH_MSG_QOS_LAST ? pri : 0);
}

int
mach_msg_priority_relpri_inline(unsigned int pri)
{
	if (mach_msg_priority_qos_inline(pri)) {
		return (int)(signed char)((pri >> MACH_MSG_PRIORITY_RELPRI_SHIFT) &
		    0xff) + 1;
	}
	return 0;
}
