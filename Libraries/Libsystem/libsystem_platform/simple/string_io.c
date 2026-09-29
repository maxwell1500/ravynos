/*
 * Copyright (c) 2005, 2006, 2009 Apple Computer, Inc. All rights reserved.
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

#include <stdlib.h>
#include <unistd.h>
#include <mach/mach_init.h>
#include <mach/vm_map.h>
#include <errno.h>

#include "os/internal.h"
#include "_simple.h"
#include "platform/string.h"
#include "platform/compat.h"

#ifndef VM_PAGE_SIZE
#define VM_PAGE_SIZE	4096
#endif

#define BUF_SIZE(s)	(((BUF *)(s))->end - ((BUF *)(s))->buf + 1)
#if DEBUG
#define MYBUFSIZE	256
#else
/* we use a small buffer to minimize stack usage constraints */
#define MYBUFSIZE	32
#endif

typedef struct _BUF {
	char *buf;
	char *ptr;
	char *end;
	int fd;
	void (*full)(struct _BUF *);
} BUF;

/* flush the buffer */
static void
_flush(BUF *b)
{
	char *buf = b->buf;
	ssize_t n = b->ptr - buf;
	ssize_t w;

	while (n > 0) {
		w = write(b->fd, buf, n);
		if (w < 0) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			break;
		}
		n -= w;
		buf += n;
	}
}

/* flush the buffer and reset the pointer */
static void
_flush_reset(BUF *b)
{
	_flush(b);
	b->ptr = b->buf;
}

/* enlarge the buffer */
static void
_enlarge(BUF *b)
{
	vm_address_t new;
	vm_size_t sold, snew;
	intptr_t diff;
	kern_return_t kr;

	new = (vm_address_t)(b->end + 1);
	if(vm_allocate(mach_task_self(), &new, VM_PAGE_SIZE, 0) == 0) {
		/* page is adjacent */
		b->end += VM_PAGE_SIZE;
		return;
	}
	sold = BUF_SIZE(b);
	snew = (sold + VM_PAGE_SIZE) & ~(VM_PAGE_SIZE - 1);
	if ((kr = vm_allocate(mach_task_self(), &new, snew, 1)) != 0) {
		__LIBPLATFORM_CLIENT_CRASH__(kr, "Failed to allocate memory for buffer");
	}
	diff = new - (vm_address_t)b->buf;
	memmove((void *)new, b->buf, sold);
	if((intptr_t)(b->buf) & (VM_PAGE_SIZE - 1)) {
		sold &= ~(VM_PAGE_SIZE - 1);
		b->buf = (char *)((intptr_t)(b->buf + VM_PAGE_SIZE) & ~(VM_PAGE_SIZE - 1));
		b->end = (char *)(new + snew - 1);
	} else
		b->end += diff + VM_PAGE_SIZE;
	if(sold > 0) {
		vm_deallocate(mach_task_self(), (vm_address_t)b->buf, sold);
	}
	b->buf = (char *)new;
	b->ptr += diff;
}

static inline void put_s(BUF *, _esc_func, const char *);
/* output a single character */
static inline void
put_c(BUF *b, _esc_func esc, unsigned char c)
{
	const char *cp;

	if(esc && (cp = esc(c)) != NULL)
		put_s(b, NULL, cp);
	else {
		if(b->ptr >= b->end)
			b->full(b);
		*b->ptr++ = c;
	}
}

/* output a null-terminated string */
static inline void
put_s(BUF *b, _esc_func esc, const char *str)
{
	while(*str)
		put_c(b, esc, *str++);
}

/* output a string of the specified size */
static inline void
put_n(BUF *b, _esc_func esc, const char *str, ssize_t n)
{
	while(n-- > 0)
		put_c(b, esc, *str++);
}

/*
 * Output the signed decimal string representing the number in "in".  "width" is
 * the minimum field width, and "zero" is a boolean value, true for zero padding
 * (otherwise blank padding).
 */
static void
dec(BUF *b, _esc_func esc, long long in, int width, int zero)
{
	char buf[32];
	char *cp = buf + sizeof(buf);
	ssize_t pad;
	int neg = 0;
	unsigned long long n = (unsigned long long)in;

	if(in < 0) {
		neg++;
		width--;
		n = ~n + 1;
	}
	*--cp = 0;
	if(n) {
		while(n) {
			*--cp = (n % 10) + '0';
			n /= 10;
		}
	} else
		*--cp = '0';
	if(neg && zero) {
		put_c(b, esc, '-');
		neg = 0;
	}
	pad = width - strlen(cp);
	zero = zero ? '0' : ' ';
	while(pad-- > 0)
		put_c(b, esc, zero);
	if(neg)
		put_c(b, esc, '-');
	put_s(b, esc, cp);
}

/*
 * Output the octal string representing the number in "n".  "width" is
 * the minimum field width, and "zero" is a boolean value, true for zero padding
 * (otherwise blank padding).
 */
static void
oct(BUF *b, _esc_func esc, unsigned long long n, int width, int zero)
{
	char buf[32];
	char *cp = buf + sizeof(buf);
	ssize_t pad;

	*--cp = 0;
	if (n) {
		while (n) {
			*--cp = (n % 8) + '0';
			n /= 8;
		}
	} else {
		*--cp = '0';
	}
	pad = width - strlen(cp);
	zero = zero ? '0' : ' ';
	while (pad-- > 0) {
		put_c(b, esc, zero);
	}
	put_s(b, esc, cp);
}

/*
 * Output the hex string representing the number in "n".  "width" is the
 * minimum field width, and "zero" is a boolean value, true for zero padding
 * (otherwise blank padding).  "upper" is a boolean value, true for upper
 * case hex characters, lower case otherwise.  "p" is a boolean value, true
 * if 0x should be prepended (for %p), otherwise nothing.
 */
static const char _h[] = "0123456789abcdef";
static const char _H[] = "0123456789ABCDEF";
static const char _0x[] = "0x";

static void
hex(BUF *b, _esc_func esc, unsigned long long n, int width, int zero, int upper, int p)
{
	char buf[32];
	char *cp = buf + sizeof(buf);
	const char *h = upper ? _H : _h;

	*--cp = 0;
	if(n) {
		while(n) {
			*--cp = h[n & 0xf];
			n >>= 4;
		}
	} else
		*--cp = '0';
	if(p) {
		width -= 2;
		if(zero) {
			put_s(b, esc, _0x);
			p = 0;
		}
	}
	width -= strlen(cp);
	zero = zero ? '0' : ' ';
	while(width-- > 0)
		put_c(b, esc, zero);
	if(p)
		put_s(b, esc, _0x);
	put_s(b, esc, cp);
}

/*
 * Output the unsigned decimal string representing the number in "n".  "width"
 * is the minimum field width, and "zero" is a boolean value, true for zero
 * padding (otherwise blank padding).
 */
static void
udec(BUF *b, _esc_func esc, unsigned long long n, int width, int zero)
{
	char buf[32];
	char *cp = buf + sizeof(buf);
	ssize_t pad;

	*--cp = 0;
	if(n) {
		while(n) {
			*--cp = (n % 10) + '0';
			n /= 10;
		}
	} else
		*--cp = '0';
	pad = width - strlen(cp);
	zero = zero ? '0' : ' ';
	while(pad-- > 0)
		put_c(b, esc, zero);
	put_s(b, esc, cp);
}

/*
 * Output the unsigned decimal string representing the number in "n", rounded
 * to the nearest MB, KB or b.  "width" is the minimum field width, and "zero"
 * is a boolean value, true for zero padding (otherwise blank padding).
 */
static void
ydec(BUF *b, _esc_func esc, unsigned long long n, int width, int zero)
{
	if(n >= 10 * (1 << 20)) {
		n += (1 << 19);
		udec(b, esc, n >> 20, width, zero);
		put_s(b, esc, "MB");
	} else if (n >= 10 * (1 << 10)) {
		n += (1 << 9);
		udec(b, esc, n >> 10, width, zero);
		put_s(b, esc, "KB");
	} else {
		udec(b, esc, n, width, zero);
		put_s(b, esc, "b");
	}
}

/*
 * The actual engine for all the _simple_*printf routines.
 */
static void
__simple_bprintf(BUF *b, _esc_func esc, const char *fmt, va_list ap)
{
	while(*fmt) {
		int lflag, zero, width;
		char *cp;
		if(!(cp = strchr(fmt, '%'))) {
			put_s(b, esc, fmt);
			break;
		}
		put_n(b, esc, fmt, cp - fmt);
		fmt = cp + 1;
		if(*fmt == '%') {
			put_c(b, esc, '%');
			fmt++;
			continue;
		}
		lflag = zero = width = 0;
		for(;;) {
			switch(*fmt) {
			case '0':
				zero++;
				fmt++;
				/* drop through */
			case '1': case '2': case '3': case '4': case '5':
			case '6': case '7': case '8': case '9':
				while(*fmt >= '0' && *fmt <= '9')
					width = 10 * width + (*fmt++ - '0');
				continue;
			case 'c':
				zero = zero ? '0' : ' ';
				width--;
				while(width-- > 0)
					put_c(b, esc, zero);
				put_c(b, esc, va_arg(ap, int));
				break;
			case 'd': case 'i':
				switch(lflag) {
				case 0:
					dec(b, esc, va_arg(ap, int), width, zero);
					break;
				case 1:
					dec(b, esc, va_arg(ap, long), width, zero);
					break;
				default:
					dec(b, esc, va_arg(ap, long long), width, zero);
					break;
				}
				break;
			case 'l':
				lflag++;
				fmt++;
				continue;
			case 'o':
				switch (lflag) {
				case 0:
					oct(b, esc, va_arg(ap, int), width, zero);
					break;
				case 1:
					oct(b, esc, va_arg(ap, long), width, zero);
					break;
				default:
					oct(b, esc, va_arg(ap, long long), width, zero);
					break;
				}
				break;
			case 'p':
				hex(b, esc, (unsigned long)va_arg(ap, void *), width, zero, 0, 1);
				break;
			case 's':
				cp = va_arg(ap, char *);
				cp = cp ? cp : "(null)";
				width -= strlen(cp);
				zero = zero ? '0' : ' ';
				while(width-- > 0)
					put_c(b, esc, zero);
				put_s(b, esc, cp);
				break;
			case 'u':
				switch(lflag) {
				case 0:
					udec(b, esc, va_arg(ap, unsigned int), width, zero);
					break;
				case 1:
					udec(b, esc, va_arg(ap, unsigned long), width, zero);
					break;
				default:
					udec(b, esc, va_arg(ap, unsigned long long), width, zero);
					break;
				}
				break;
			case 'X': case 'x':
				switch(lflag) {
				case 0:
					hex(b, esc, va_arg(ap, unsigned int), width, zero,
						*fmt == 'X', 0);
					break;
				case 1:
					hex(b, esc, va_arg(ap, unsigned long), width, zero,
						*fmt == 'X', 0);
					break;
				default:
					hex(b, esc, va_arg(ap, unsigned long long), width, zero,
						*fmt == 'X', 0);
					break;
				}
				break;
			case 'y':
				switch(lflag) {
				case 0:
					ydec(b, esc, va_arg(ap, unsigned int), width, zero);
					break;
				case 1:
					ydec(b, esc, va_arg(ap, unsigned long), width, zero);
					break;
				default:
					ydec(b, esc, va_arg(ap, unsigned long long), width, zero);
					break;
				}
				break;
			default:
				/*
				 * An UNSUPPORTED conversion used to print its own
				 * character literally and continue, so "%#x" rendered as the
				 * two characters "#x" -- a plausible-looking token where a
				 * number should have been, with no error and no marker.  That
				 * is how a diagnostic goes missing without anyone noticing: a
				 * probe of this plan printed "off0=#x" and it was very nearly
				 * read as a value.  (The same shape as the otool __framesize
				 * placeholder, BOOT-PLAN section 36.3.)
				 *
				 * There are no flag handlers in this switch at all -- '0' is a
				 * width digit and nothing consumes '#', '+', ' ', '-', '.' or
				 * '*'.  So emit a marker that cannot be mistaken for output, and
				 * consume no argument, so the rest of the format still lines up.
				 *
				 * Supported conversions: %c %d %i %o %p %s %u %x %X %y, with %l
				 * as a length modifier.  Everything else lands here.
				 */
				put_s(b, esc, "<UNSUPPORTED-CONVERSION>");
				break;
			}
			break;
		}
		fmt++;
	}
}

/*
 * A simplified vfprintf variant.  The format string is interpreted with
 * arguments from the va_list, and the results are written to the given
 * file descriptor.
 */
void
_simple_vdprintf(int fd, const char *fmt, va_list ap)
{
	BUF b;
	char buf[MYBUFSIZE];

	b.buf = buf;
	b.fd = fd;
	b.ptr = b.buf;
	b.end = b.buf + MYBUFSIZE;
	b.full = _flush_reset;
	__simple_bprintf(&b, NULL, fmt, ap);
	_flush(&b);
}

/*
 * A simplified fprintf variant.  The format string is interpreted with
 * arguments from the variable argument list, and the results are written
 * to the given file descriptor.
 */
void
_simple_dprintf(int fd, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	_simple_vdprintf(fd, fmt, ap);
	va_end(ap);
}

/*
 * A simplified string allocate routine.  Pass the opaque pointer to structure
 * to _simple_*sprintf() routines.  Use _simple_string() to retrieve the
 * current string (the string is guaranteed to be null terminated only on
 * the call to _simple_string()).  Use _simple_sfree() to free the structure
 * and string memory.
 */
/*
 * ⚠️⚠️ UNVERIFIED — WRITTEN BUT NEVER BUILT, NEVER BOOTED. This is a design
 * plus a diff, not a result. Nothing here has been compiled or run.
 *
 * WHY. dyld's bootstrap allocator reaches this function before it has called
 * mach_init(), and it reaches it through the MIG-generated vm_allocate(). A
 * MIG call needs a reply port; obtaining one calls mach_port_construct; the
 * kernelrpc path for that re-enters this allocator. The cycle terminates in
 * STACK EXHAUSTION, not a bad address: the faulting instruction is
 * 'movl %edi, -0x8(%rbp)', the fourth instruction of
 * __kernelrpc_mach_port_construct, a plain stack write, faulting because
 * RSP sat 0x90 below RBP.
 *
 * The circularity is created by ROUTING, so before the mach layer exists we
 * route around MIG using the direct trap, which is already present in the
 * image as __kernelrpc_mach_vm_allocate_trap. No new syscall plumbing.
 *
 * THE BOUNDARY, and it is a runtime check rather than a comment on purpose.
 * The no_shared_cr3 block in this project was a correct mechanism whose
 * precondition nobody had verified was live, and a comment is exactly as
 * silent as that mistake was. A gate should test the precondition the thing
 * actually requires, and here that is literally "the mach layer has been
 * initialised" — which is what mach_task_self_ encodes: it is
 * MACH_PORT_NULL until mach_init_doit() assigns task_self_trap() exactly once.
 *
 * It IS a proxy and is labelled as one: mach_init_doit() is also reached from
 * _mach_fork_child(), so the boundary is "mach_init or fork has run" rather
 * than "mach_init specifically ran". That is the condition under which the MIG
 * path is safe, so it is the predicate worth testing.
 *
 * WHY IT LIVES HERE AND NOT IN DYLD. libsystem_platform.a:string_io.o also
 * provides __simple_dprintf and 13 other symbols dyld uses, so the archive
 * member is pulled into every link needing the simple_* API whether or not
 * __simple_salloc is defined elsewhere; a dyld-local definition of
 * __simple_salloc is a duplicate symbol, not a shim. Intercepting at dyld's 6
 * call sites was rejected because one missed site would silently reintroduce
 * the circularity, and a fix whose failure mode is silence is the failure mode
 * this project exists to eliminate.
 *
 * AFTER THE BOUNDARY this reaches the original vm_allocate() path, unchanged,
 * so no consumer — dyld or anything else — ever gets a divergent allocator.
 *
 * ⚠️ THE PREDICTED FAILURE MODE, recorded so the first test can check it. A
 * static reading cannot show WHICH of dyld's 6 __simple_salloc call sites
 * execute before mach_init(). If any early allocation reaches memory by
 * another route entirely, this gate does not cover it and THE SIGNATURE WILL
 * NOT MOVE. If the signature is unchanged after this, the first thing to check
 * is whether such a path exists — not the gate, and not the predicate.
 */
_SIMPLE_STRING
_simple_salloc(void)
{
	BUF *b;
	int kr;

	if (mach_task_self_ == MACH_PORT_NULL) {
		/* Pre-mach_init bootstrap: take the direct trap, not MIG. */
		/*
		 * ONE leading underscore, not two.  This is the canonical libsyscall
		 * spelling -- Kernel/xnu/libsyscall/mach/mach_vm.c:55 calls
		 * `_kernelrpc_mach_vm_allocate_trap` with exactly one, and that is the
		 * name libkernel.a's mach_traps.o DEFINES.
		 *
		 * The two-underscore form was a real bug that survived a green build
		 * and a link.  It compiled, linked, and still produced a loader
		 * import, because `__kernelrpc_...` and `_kernelrpc_...` are two
		 * DIFFERENT symbols: the definition landed in the image as a local
		 * `t` at 0xbbc20 while the reference stayed an undefined
		 * `___kernelrpc_...` (3 underscores in Mach-O) in the same binary.
		 * A definition that is present and does not satisfy the reference --
		 * not a missing trap, and not missing syscall plumbing.
		 *
		 * This is the same defect class as the ___chkstk_darwin name, and the
		 * tell in both cases is the same: the count went down, the outcome did
		 * not move, and the import was still there.  Count the underscores
		 * before believing an import is unresolvable.
		 */
		kr = _kernelrpc_mach_vm_allocate_trap(mach_task_self(), (vm_address_t *)&b, VM_PAGE_SIZE, 1);
	} else {
		kr = vm_allocate(mach_task_self(), (vm_address_t *)&b, VM_PAGE_SIZE, 1);
	}
	if (kr)
		return NULL;
	b->ptr = b->buf = (char *)b + sizeof(BUF);
	b->end = (char *)b + VM_PAGE_SIZE - 1;
	b->full = _enlarge;
	return (_SIMPLE_STRING)b;
}

/*
 * The format string is interpreted with arguments from the va_list, and the
 * results are appended to the string maintained by the opaque structure, as
 * returned by a previous call to _simple_salloc().  Non-zero is returned on
 * out-of-memory error.
 */
int
_simple_vsprintf(_SIMPLE_STRING b, const char *fmt, va_list ap)
{
	return _simple_vesprintf(b, NULL, fmt, ap);
}

/*
 * The format string is interpreted with arguments from the variable argument
 * list, and the results are appended to the string maintained by the opaque
 * structure, as returned by a previous call to _simple_salloc().  Non-zero is
 * returned on out-of-memory error.
 */
int
_simple_sprintf(_SIMPLE_STRING b, const char *fmt, ...)
{
	va_list ap;
	int ret;

	va_start(ap, fmt);
	ret = _simple_vesprintf(b, NULL, fmt, ap);
	va_end(ap);
	return ret;
}

/*
 * Like _simple_vsprintf(), except __esc is a function to call on each
 * character; the function returns NULL if the character should be passed
 * as is, otherwise, the returned character string is used instead.
 */
int
_simple_vesprintf(_SIMPLE_STRING b, _esc_func esc, const char *fmt, va_list ap)
{
	__simple_bprintf((BUF *)b, esc, fmt, ap);
	return 0;
}

/*
 * Like _simple_sprintf(), except __esc is a function to call on each
 * character; the function returns NULL if the character should be passed
 * as is, otherwise, the returned character string is used instead.
 */
int _simple_esprintf(_SIMPLE_STRING b, _esc_func esc, const char *fmt, ...)
{
	va_list ap;
	int ret;

	va_start(ap, fmt);
	ret = _simple_vesprintf(b, esc, fmt, ap);
	va_end(ap);
	return ret;
}

/*
 * Return the null terminated string from the opaque structure, as returned
 * by a previous call to _simple_salloc().
 */
char *
_simple_string(_SIMPLE_STRING b)
{
	*((BUF *)b)->ptr = 0;
	return ((BUF *)b)->buf;
}

/*
 * Reposition the pointer to the first null in the buffer.  After a call to
 * _simple_string, the buffer can be modified, and shrunk.
 */
void
_simple_sresize(_SIMPLE_STRING b)
{
	((BUF *)b)->ptr = ((BUF *)b)->buf + strlen(((BUF *)b)->buf);
}

/*
 * Append the null-terminated string to the string associated with the opaque
 * structure.  Non-zero is returned on out-of-memory error.
 */
int
_simple_sappend(_SIMPLE_STRING b, const char *str)
{
	return _simple_esappend(b, NULL, str);
}

/*
 * Like _simple_sappend(), except __esc is a function to call on each
 * character; the function returns NULL if the character should be passed
 * as is, otherwise, the returned character string is used instead.
 */
int _simple_esappend(_SIMPLE_STRING b, _esc_func esc, const char *str)
{
	put_s((BUF *)b, esc, str);
	return 0;
}

/*
 * Write the string associated with the opaque structure to the file descriptor.
 */
void
_simple_put(_SIMPLE_STRING b, int fd)
{
	((BUF *)b)->fd = fd;
	_flush((BUF *)b);
}

/*
 * Write the string associated with the opaque structure and a trailing newline,
 * to the file descriptor.
 */
void
_simple_putline(_SIMPLE_STRING b, int fd)
{
	((BUF *)b)->fd = fd;
	*((BUF *)b)->ptr++ = '\n';
	_flush((BUF *)b);
	((BUF *)b)->ptr--;
}

/*
 * Free the opaque structure, and the associated string.
 */
void
_simple_sfree(_SIMPLE_STRING b)
{
	vm_size_t s;

	if(b == NULL) return;
	if(((intptr_t)(((BUF *)b)->buf) & (VM_PAGE_SIZE - 1)) == 0) {
		vm_deallocate(mach_task_self(), (vm_address_t)((BUF *)b)->buf, BUF_SIZE(b));
		s = VM_PAGE_SIZE;
	} else {
		s = ((BUF *)b)->end - (char *)b + 1;
	}
	vm_deallocate(mach_task_self(), (vm_address_t)b, s);
}
