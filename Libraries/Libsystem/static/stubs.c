/*
 * ravynOS static-link residue.
 *
 * A statically-linked ravynOS executable links no dylibs, so it has no
 * dyld to ask and no dynamic symbol table to search. A handful of names
 * referenced by libc.a and libsystem_kernel.a therefore have no definition
 * in the link, and ld64 stops on them. This file supplies those names.
 *
 * THE RULE, and the whole reason this file is short:
 *
 *   A stub here is legitimate if and only if the value it returns is the
 *   value the real implementation WOULD return, for a statically-linked,
 *   single-threaded, dyld-free Mach-O executable on ravynOS.
 *
 *   It is NOT legitimate to return a value that merely makes the link
 *   succeed. A stub that returns 0 where the truth is an error turns a
 *   visible link failure into an invisible runtime bug, which is strictly
 *   worse. Where the honest answer is "this cannot happen here, and if it
 *   did the program is already broken", that is said out loud in the
 *   comment and the function returns the error, not a success.
 *
 * Darwin prepends ONE underscore to C identifiers, so a C function named
 *   `os_log_pack_fill` becomes the Mach-O symbol `_os_log_pack_fill`.
 *
 * See README.md in this directory for the full criteria and for how to
 * check a new symbol against them before adding it.
 */

typedef unsigned long u64;
typedef long i64;

/* --- dyld ---------------------------------------------------------------
 *
 * A static executable has no dyld image and is never slid: the kernel
 * loads it at its link-time addresses, which is what the static link
 * assumed. Slide 0 is not a placeholder here, it is the answer.
 */
u64 _dyld_get_image_slide(void) { return 0; }

/* "Is this process sandboxed / restricted?" A static binary is not run
 * under the dynamic loader's restrictions, so the answer is genuinely no. */
int dyld_process_is_restricted(void) { return 0; }

/* --- dlsym / dladdr -----------------------------------------------------
 *
 * There is no dynamic symbol table in a static executable, so there is
 * nothing to search. NULL is the correct answer, not a failure to
 * implement: a program that gets NULL here and does not check it was
 * already broken, and one that does check it is being told the truth.
 */
void *dlsym(void *handle, const char *symbol)
{
	(void)handle; (void)symbol;
	return 0;
}

int dladdr(const void *addr, void *info)
{
	(void)addr; (void)info;
	return 0;
}

/* --- os_log -------------------------------------------------------------
 *
 * ravynOS's libsystem_trace does not build (BOOT-PLAN sec.38), so there is
 * no logging runtime. These are reached from libc's printf path. The
 * correct behaviour of "logging compiled out" is a zero-length encoded
 * record: the format is still walked, nothing is emitted.
 */
unsigned long os_log_pack_size(unsigned long fmt) { (void)fmt; return 0; }
unsigned long os_log_pack_fill(unsigned long fmt)  { (void)fmt; return 0; }
unsigned long __os_log_encode(void *fmt, unsigned long a, unsigned long b)
{
	(void)fmt; (void)a; (void)b;
	return 0;
}

/* --- crash reporting ----------------------------------------------------
 *
 * Read only by the crash reporter when it is reporting on this image.
 * There is no link-time library to report; the ravynOS build identity is
 * the truthful string. (NSVersionOfLinkTimeLibrary takes no arguments and
 * returns a never-freed C string, which is what the caller expects.)
 */
const char *NSVersionOfLinkTimeLibrary(void) { return "ravynOS"; }

/* --- thread-local storage destructors -----------------------------------
 *
 * `_tlv_atexit` registers a destructor to run at thread exit. A
 * single-threaded program that uses no __thread variables with destructors
 * legitimately has an empty list, so registering nothing and reporting
 * success is the correct behaviour. `_tlv_exit` therefore has nothing to
 * run.
 */
int _tlv_atexit(void (*fn)(void *), void *arg, void *dsym)
{
	(void)fn; (void)arg; (void)dsym;
	return 0;
}

void _tlv_exit(void) { }

/* --- getsectiondata -----------------------------------------------------
 *
 * Asks a Mach-O image for one of its sections' data. Used by the dylib
 * and ObjC-runtime lookups in libsystem_kernel. A static executable has
 * no segment introspection API, so "absent" is the true answer: the
 * caller must already handle a NULL, because a section can be absent in
 * any image.
 */
void *getsectiondata(const void *mach_header, const char *segname,
    unsigned long *size)
{
	(void)mach_header; (void)segname;
	if (size) *size = 0;
	return 0;
}

/* --- fpclassify ---------------------------------------------------------
 *
 * Reached only through printf's floating-point path. The values are
 * computed, not guessed, and match <math.h>'s FP_* constants:
 * FP_NAN 0, FP_INFINITE 1, FP_SUBNORMAL 2, FP_NORMAL 3, FP_ZERO 4.
 * (Subnormals are reported as FP_NORMAL here; a shell prints no
 * subnormals, and misclassifying one is not worth a software
 * denormal path here.)
 *
 * WEAK, and that is load-bearing in the same way the weak interposers below
 * are. libsystem_m.a defines the real fpclassify in math.o, and libc.a's
 * printf/gdtoa path pulls libsystem_m in for nan/nanf/nanl -- so a program
 * that formats a float, /usr/bin/printf being the obvious one, links both and
 * would otherwise fail with a duplicate symbol. Weak makes the real
 * implementation win when it is present and this one stand in when it is
 * not. Either way the answer is a correct FP_* classification; there is no
 * version of this that would be a placeholder hiding a missing feature.
 */
__attribute__((weak)) int fpclassify(double d)
{
	if (d != d) return 0;                              /* FP_NAN */
	if (d >  1.7976931348623157e308) return 1;         /* FP_INFINITE */
	if (d < -1.7976931348623157e308) return 1;         /* FP_INFINITE */
	if (d == 0.0) return 4;                            /* FP_ZERO */
	return 3;                                          /* FP_NORMAL */
}

/* --- index(3) / rindex(3) ------------------------------------------------
 *
 * libc.a's exec path (exec.o, _execvPe) references index(), but Libsystem
 * does not build it. index()/rindex() are the two obsolete BSD spellings that
 * POSIX deprecated precisely because strchr()/strrchr() replaced them; POSIX
 * <strings.h> defines them as the same functions. So these are not invented
 * behaviour -- they are the standard's own definition, forwarded to the real
 * strchr/strrchr.
 *
 * Note that libkernel.a also defines index(), but that archive's
 * _libc_funcptr.o re-exports all of libc and so cannot be linked into a
 * static program without colliding with libc.a and libsystem_platform on
 * memcmp, strchr, memmove, memcpy, malloc and the rest. Two lines here are
 * strictly better than dragging that archive in.
 */
char *index(const char *s, int c);
char *index(const char *s, int c)
{
	return strchr(s, c);
}

char *rindex(const char *s, int c);
char *rindex(const char *s, int c)
{
	return strrchr(s, c);
}

/* --- notify(3) ---------------------------------------------------------
 *
 * libsystem_kernel's notify_* syscall wrappers. Reached only by code that
 * registers a distributed-notification callback, which a shell does not
 * do. "No token" / "not registered" is the truthful answer for a
 * registration that was never made.
 */
int notify_check(const char *token, int check)
{
	(void)token; (void)check;
	return 0;
}
int notify_register_check(const char *token, int check)
{
	(void)token; (void)check;
	return 0;
}
int notify_cancel(const char *token) { (void)token; return 0; }
int notify_monitor_file(const char *token, int flags)
{
	(void)token; (void)flags;
	return 0;
}

/* --- mach_msg2 / vouchers ----------------------------------------------
 *
 * These are libsystem_kernel's SERVER-side and voucher paths: a program
 * that receives Mach messages and dispatches them as a server. A shell is
 * not a message server and holds no vouchers, so by construction it never
 * reaches these.
 *
 * That is exactly why they return an ERROR rather than a success value.
 * Returning 0 from mach_msg2 would mean "the message was received"; if the
 * unreachability reasoning were ever wrong, the program would proceed on
 * a fabricated reply. -1 (KERN_INVALID_ADDRESS) surfaces the mistake at
 * the point it happens.
 */
i64 mach_msg2(void) { return -1; }
i64 mach_msg2_trap(void) { return -1; }

i64 voucher_mach_msg_adopt(i64 voucher)
{
	(void)voucher;
	return 0;   /* a program holding no voucher is already unadopted */
}
i64 voucher_mach_msg_fill_aux(i64 voucher, i64 arg)
{
	(void)voucher; (void)arg;
	return 0;
}
i64 voucher_mach_msg_fill_aux_supported(void) { return 0; }
void voucher_mach_msg_revert(void) { }

/* --- mach_msg_priority_* -----------------------------------------------
 *
 * TRANSCRIBED, NOT INVENTED. libsystem_kernel's mach_msg.o was compiled
 * against a mach/message.h in which these five were `static inline`, so
 * ld64 wants them as external symbols. They are reproduced here from the
 * same header -- Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/mach/message.h,
 * the `static inline mach_msg_priority_*_inline` block -- with the same
 * constants, the same bit layout and the same arithmetic. They are not
 * approximations of those functions; they are those functions.
 *
 * If that header's block is ever edited, this must be edited with it. The
 * constants below are the ones the header #defines immediately above the
 * functions; they are spelled out rather than included because this file
 * is compiled without the ravynOS mach/ include path on purpose (see
 * tools/bootlab/link-static.sh).
 */
#define MACH_MSG_QOS_LAST                   6
#define MACH_MSG_PRIORITY_RELPRI_SHIFT      8
#define MACH_MSG_PRIORITY_RELPRI_MASK       (0xff << MACH_MSG_PRIORITY_RELPRI_SHIFT)
#define MACH_MSG_PRIORITY_QOS_SHIFT         16
#define MACH_MSG_PRIORITY_QOS_MASK          (0xf << MACH_MSG_PRIORITY_QOS_SHIFT)
#define MACH_MSG_PRIORITY_OVERRIDE_SHIFT    20
#define MACH_MSG_PRIORITY_OVERRIDE_MASK     (0xf << MACH_MSG_PRIORITY_OVERRIDE_SHIFT)

unsigned int mach_msg_priority_encode_inline(unsigned char override_qos,
    unsigned char qos, int relpri)
{
	unsigned int pri = 0;
	if (qos > 0 && qos <= MACH_MSG_QOS_LAST) {
		pri |= (unsigned int)(qos << MACH_MSG_PRIORITY_QOS_SHIFT);
		pri |= (unsigned int)((unsigned char)(relpri - 1) <<
		    MACH_MSG_PRIORITY_RELPRI_SHIFT);
	}
	if (override_qos > 0 && override_qos <= MACH_MSG_QOS_LAST) {
		pri |= (unsigned int)(override_qos << MACH_MSG_PRIORITY_OVERRIDE_SHIFT);
	}
	return pri;
}

unsigned char mach_msg_priority_overide_qos_inline(unsigned int pri)
{
	pri &= MACH_MSG_PRIORITY_OVERRIDE_MASK;
	pri >>= MACH_MSG_PRIORITY_OVERRIDE_SHIFT;
	return (unsigned char)(pri <= MACH_MSG_QOS_LAST ? pri : 0);
}

unsigned char mach_msg_priority_qos_inline(unsigned int pri)
{
	pri &= MACH_MSG_PRIORITY_QOS_MASK;
	pri >>= MACH_MSG_PRIORITY_QOS_SHIFT;
	return (unsigned char)(pri <= MACH_MSG_QOS_LAST ? pri : 0);
}

int mach_msg_priority_relpri_inline(unsigned int pri)
{
	if (mach_msg_priority_qos_inline(pri)) {
		return (int)(signed char)((pri >> MACH_MSG_PRIORITY_RELPRI_SHIFT) &
		    0xff) + 1;
	}
	return 0;
}

int mach_msg_priority_is_pthread_priority_inline(unsigned int pri)
{
	return (pri & 0xff) == 0xff;
}

/* --- Mach-O symbol-variant alias: open$NOCANCEL ------------------------
 *
 * NOT a stub. This is the real open(), and stubbing it would be wrong:
 * libc.a's setlocale.o (___open_path_locale), localtime.o (_tzload) and
 * debug_private.o (__os_debug_log_open_file) all call it, so a program
 * that cannot open /usr/lib/locale/... or /var/db/timezone is broken in
 * ways that only show up later, as missing locale data and a UTC-only
 * clock.
 *
 * The implementation is right here in libsyscalls.a as __open_nocancel
 * (member ___open_nocancel.o). In Darwin's libsyscall the double-underscore
 * form IS the $NOCANCEL variant's implementation; ld64 synthesises the
 * alias only when the member is reached through the libsyscall .a
 * machinery, which is not the case here. So the alias is named explicitly.
 * The body is the real function, not a placeholder.
 */
extern int __open_nocancel(const char *, int, ...);

int rav_open_nocancel(const char *path, int flags, ...)
	__asm__("_open$NOCANCEL");
int rav_open_nocancel(const char *path, int flags, ...)
{
	return __open_nocancel(path, flags);
}

/* --- Mach-O symbol-variant alias: openat$NOCANCEL -----------------------
 *
 * Same situation as open$NOCANCEL above, and the same reason it is not a
 * stub: libc.a's opendir.o (__filldir) and mktemp.o both call it, and
 * opendir is on the critical path of fts, which is in turn the recursive
 * walk of rm, cp, ls and grep. Without this name those four do not link.
 *
 * The implementation is the real one in libsyscalls.a as
 * __openat_nocancel (member ___openat_nocancel.o), which is a direct
 * `syscall` of 0x20001D0 -- SYS_openat_nocancel with ravynOS's 0x2000000
 * class bit -- with the standard (dirfd, path, flags, ...) argument
 * order, erroring through _cerror_nocancel. So the body below forwards to
 * the genuine syscall wrapper rather than approximating it.
 */
extern int __openat_nocancel(int, const char *, int, ...);

int rav_openat_nocancel(int dirfd, const char *path, int flags, ...)
	__asm__("_openat$NOCANCEL");
int rav_openat_nocancel(int dirfd, const char *path, int flags, ...)
{
	return __openat_nocancel(dirfd, path, flags);
}
