/*-
 * Copyright (c) 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#if defined(LIBC_SCCS) && !defined(lint)
static char sccsid[] = "@(#)err.c	8.1 (Berkeley) 6/4/93";
#endif /* LIBC_SCCS and not lint */
#include <sys/cdefs.h>
__FBSDID("$FreeBSD: src/lib/libc/gen/err.c,v 1.15 2008/04/03 20:36:44 imp Exp $");

#include "namespace.h"
#include <err.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vis.h>
#include "un-namespace.h"

#ifdef __BLOCKS__
#include <Block.h>
#endif /* __BLOCKS__ */
#include "libc_private.h"
#ifdef __has_include
#if __has_include(<os/tsd.h>)
/*
 * The per-thread errno accessor.  <sys/errno.h> declares
 *
 *	extern int * __error(void);
 *	#define errno (*__error())
 *
 * so EVERY use of errno in the entire userspace -- including dyld's, in
 * src/glue.c -- is a call to this one function.  libsystem_pthread owns the
 * storage: struct _pthread has an `errno_t err_no`, and both of its thread-init
 * paths (pthread.c:905 and :1629) publish the address of that field into TSD
 * slot __TSD_ERRNO.  Nothing reads the field directly, so this slot is the only
 * accessor path, and returning it is the whole contract.
 *
 * The storage is deliberately in the pthread struct and NOT in a __thread
 * variable.  That is not an accident of style: dyld calls __error() before the
 * pthread runtime has populated any TSD slot, so an implementation that
 * depended on runtime initialisation -- or on dynamic TLS being set up by the
 * loader at that moment -- would fail in the one component that has to work
 * first.  Do not "simplify" this into a __thread.
 *
 * _os_tsd_get_direct() is the x86_64 Darwin mechanism and is NOT written here:
 * it comes from <os/tsd.h>, which resolves to a %gs-relative read of the TSD
 * base (%gs:0).  On this target it compiles to a single
 *
 *	movq %gs:__error(,%rax,8), %rax
 */
#include <os/tsd.h>
#endif /* __has_include(<os/tsd.h>) */
#endif /* __has_include */

#define ERR_EXIT_UNDEF	0
#ifdef __BLOCKS__
#define ERR_EXIT_BLOCK	1
#endif /* __BLOCKS__ */
#define ERR_EXIT_FUNC	2
struct _e_err_exit {
	unsigned int type;
#ifdef __BLOCKS__
	union {
#endif /* __BLOCKS__ */
		void (*func)(int);
#ifdef __BLOCKS__
		void (^block)(int);
	};
#endif /* __BLOCKS__ */
};

#ifdef BUILDING_VARIANT

__private_extern__ FILE *_e_err_file; /* file to use for error output */
__private_extern__ struct _e_err_exit _e_err_exit;
__private_extern__ void _e_visprintf(FILE * __restrict, const char * __restrict, va_list);

#else /* !BUILDING_VARIANT */

__private_extern__ FILE *_e_err_file = NULL; /* file to use for error output */
__private_extern__ struct _e_err_exit _e_err_exit = {ERR_EXIT_UNDEF};

/*
 * zero means pass as is
 * 255 means use \nnn (octal)
 * otherwise use \x (x is value)
 * (NUL isn't used)
 */
static const unsigned char escape[256] = {
     /* NUL */
	 0, /* Unused: strings can't contain nulls */
     /*      SOH  STX  ETX  EOT  ENQ  ACK  BEL */
	     255, 255, 255, 255, 255, 255, 'a',
     /* BS   HT   NL   VT   NP   CR   SO   SI  */
	'b',  0,   0,  'v', 'f', 'r', 255, 255,
     /* DLE  DC1  DC2  DC3  DC4  NAK  SYN  ETB */
	255, 255, 255, 255, 255, 255, 255, 255,
     /* CAN  EM   SUB  ESC  FS   GS   RS   US  */
	255, 255, 255, 255, 255, 255, 255, 255,
     /* the rest are zero */
};

/*
 * Make characters visible.  If we can't allocate enough
 * memory, we fall back on vfprintf().
 */
__private_extern__ void
_e_visprintf(FILE * __restrict stream, const char * __restrict format, va_list ap)
{
	int failed = 0;
	char *str, *visstr;
	va_list backup;

	va_copy(backup, ap);
	vasprintf(&str, format, ap);
	if (str != NULL) {
		if ((visstr = malloc(4 * strlen(str) + 1)) != NULL) {
			unsigned char *fp = (unsigned char *)str;
			unsigned char *tp = (unsigned char *)visstr;
			while(*fp) {
				switch(escape[*fp]) {
				case 0:
					*tp++ = *fp;
					break;
				case 255:
					sprintf((char *)tp, "\\%03o", *fp);
					tp += 4;
					break;
				default:
					*tp++ = '\\';
					*tp++ = escape[*fp];
					break;
				}
				fp++;
			}
			*tp = 0;
			fputs(visstr, stream);
			free(visstr);
		} else
			failed = 1;
		free(str);
	} else
		failed = 1;
	if (failed)
		vfprintf(stream, format, backup);
	va_end(backup);
}

/*
 * This is declared to take a `void *' so that the caller is not required
 * to include <stdio.h> first.  However, it is really a `FILE *', and the
 * manual page documents it as such.
 */
void
err_set_file(void *fp)
{
	if (fp)
		_e_err_file = fp;
	else
		_e_err_file = stderr;
}

void
err_set_exit(void (*ef)(int))
{
#ifdef __BLOCKS__
	if (_e_err_exit.type == ERR_EXIT_BLOCK) {
		Block_release(_e_err_exit.block);
		_e_err_exit.block = NULL;
	}
#endif /* __BLOCKS__ */
	_e_err_exit.type = ef ? ERR_EXIT_FUNC : ERR_EXIT_UNDEF;
	_e_err_exit.func = ef;
}

#ifdef __BLOCKS__
void
err_set_exit_b(void (^ef)(int))
{
	if (_e_err_exit.type == ERR_EXIT_BLOCK) {
		Block_release(_e_err_exit.block);
	}
	_e_err_exit.type = ef ? ERR_EXIT_BLOCK : ERR_EXIT_UNDEF;
	_e_err_exit.block = Block_copy(ef);
}
#endif /* __BLOCKS__ */
#endif /* !BUILDING_VARIANT */

__weak_reference(_err, err);

void
_err(int eval, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	verrc(eval, errno, fmt, ap);
	va_end(ap);
}

void
verr(eval, fmt, ap)
	int eval;
	const char *fmt;
	va_list ap;
{
	verrc(eval, errno, fmt, ap);
}

void
errc(int eval, int code, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	verrc(eval, code, fmt, ap);
	va_end(ap);
}

void
verrc(int eval, int code, const char *fmt, va_list ap)
{
	if (_e_err_file == 0)
		err_set_file((FILE *)0);
	fprintf(_e_err_file, "%s: ", _getprogname());
	if (fmt != NULL) {
		_e_visprintf(_e_err_file, fmt, ap);
		fprintf(_e_err_file, ": ");
	}
	fprintf(_e_err_file, "%s\n", strerror(code));
	if (_e_err_exit.type) {
#ifdef __BLOCKS__
		if (_e_err_exit.type == ERR_EXIT_BLOCK) {
			_e_err_exit.block(eval);
		} else {
			_e_err_exit.func(eval);
		}
#else
		_e_err_exit.func(eval);
#endif /* __BLOCKS__ */
	}
	exit(eval);
}

void
errx(int eval, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	verrx(eval, fmt, ap);
	va_end(ap);
}

void
verrx(int eval, const char *fmt, va_list ap)
{
	if (_e_err_file == 0)
		err_set_file((FILE *)0);
	fprintf(_e_err_file, "%s: ", _getprogname());
	if (fmt != NULL)
		_e_visprintf(_e_err_file, fmt, ap);
	fprintf(_e_err_file, "\n");
	if (_e_err_exit.type) {
#ifdef __BLOCKS__
		if (_e_err_exit.type == ERR_EXIT_BLOCK) {
			_e_err_exit.block(eval);
		} else {
			_e_err_exit.func(eval);
		}
#else
		_e_err_exit.func(eval);
#endif /* __BLOCKS__ */
	}
	exit(eval);
}

__weak_reference(_warn, warn);

void
_warn(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vwarnc(errno, fmt, ap);
	va_end(ap);
}

void
vwarn(const char *fmt, va_list ap)
{
	vwarnc(errno, fmt, ap);
}

void
warnc(int code, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vwarnc(code, fmt, ap);
	va_end(ap);
}

void
vwarnc(int code, const char *fmt, va_list ap)
{
	if (_e_err_file == 0)
		err_set_file((FILE *)0);
	fprintf(_e_err_file, "%s: ", _getprogname());
	if (fmt != NULL) {
		_e_visprintf(_e_err_file, fmt, ap);
		fprintf(_e_err_file, ": ");
	}
	fprintf(_e_err_file, "%s\n", strerror(code));
}

void
warnx(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vwarnx(fmt, ap);
	va_end(ap);
}

void
vwarnx(const char *fmt, va_list ap)
{
	if (_e_err_file == 0)
		err_set_file((FILE *)0);
	fprintf(_e_err_file, "%s: ", _getprogname());
	if (fmt != NULL)
		_e_visprintf(_e_err_file, fmt, ap);
	fprintf(_e_err_file, "\n");
}

/*
 * __error -- see the block comment near the top of this file for why this
 * lives in the pthread TSD rather than in TLS, and why it must not move.
 *
 * Returns a pointer to the CALLING THREAD's errno.  Callers store through it
 * (errno = X), so the pointee must be per-thread storage, not a shared global.
 */
__attribute__((weak))
int *
__error(void)
{
#if defined(__has_include) && __has_include(<os/tsd.h>)
	return (int *)_os_tsd_get_direct(__TSD_ERRNO);
#else
#error "no per-thread errno storage: refusing to define __error() as a global"
#endif
}
