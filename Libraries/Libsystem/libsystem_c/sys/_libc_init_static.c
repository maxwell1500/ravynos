/*
 * ravynOS STATIC-BUILD initializer list.
 *
 * This is a sibling of __libc_init (sys/_libc_init.c), not a modification
 * of it.  __libc_init is untouched: the dynamic build still calls
 * _libc_initializer() exactly as it always has, and nothing in this file is
 * compiled into the dynamic path's behaviour.  It exists because the static
 * build has no __libc_init to call -- a static binary has no
 * libSystem_initializer() constructor -- and hand-assigning the individual
 * publications from static-start.c is the drift this file removes.
 *
 * The list below is _libc_initializer()'s list, in its own order, with one
 * entry omitted.  Each omission is a line, saying what it would have done
 * and why it is unavailable.
 *
 * OMITTED: _init_clock_port()  [ _libc_init.c:58 ]
 *
 *   It calls host_get_clock_service(host, SYSTEM_CLOCK, &clock_port) and
 *   abort()s if that is not KERN_SUCCESS (gen/nanosleep.c:45-60).  On
 *   ravynOS the routine is IMPLEMENTED (osfmk/kern/clock_oldops.c:253) and
 *   DECLARED (osfmk/mach/mach_host.defs:159), but it has NO mach trap
 *   registration, so the trap the userland stub issues returns failure and
 *   the abort is the check doing its job correctly.
 *
 *   Publishing anything cannot make this check pass.  It is a SERVICE --
 *   Libc must OBTAIN a clock service port from the kernel -- not a startup
 *   value, so there is nothing for ravyn_static_startup to publish.  This is
 *   a workaround for a kernel gap, not a fix, and the gap is filed with the
 *   Kernel/xnu workstream: host_get_clock_service is implemented and
 *   declared but unwired.
 *
 *   Consequence, measured from the linked binary rather than assumed: the
 *   only consumers of clock_port/clock_sem are _init_clock_port,
 *   _nanosleep and _nanosleep$NOCANCEL.  With this omitted they stay
 *   MACH_PORT_NULL, so nanosleep() and therefore sleep() cannot work on
 *   ravynOS today.  That is the state the system is already in; omitting
 *   the call does not break a working sleep, it stops aborting about a
 *   broken one.
 */

#include "../darwin/libc_private.h"
#include <mach/mach.h>
#include <stddef.h>

extern void _program_vars_init(const struct ProgramVars *vars);
extern void _libc_fork_init(const struct _libc_functions *funcs);
extern void __confstr_init(const struct _libc_functions *funcs);
extern void __atexit_init(void);
extern void __chk_init(void);
extern void __xlocale_init(void);
extern void __guard_setup(const char *apple[]);

void
__ravyn_static_libc_init(const struct ProgramVars *vars,
                         void (*atfork_prepare)(void),
                         void (*atfork_parent)(void),
                         void (*atfork_child)(void),
                         const char *apple[])
{
	/* Built here, not by the caller: the struct is Libc's and is versioned,
	 * so it must not be duplicated in static-start.c. */
	const struct _libc_functions funcs = {
		.version = 1,
		.atfork_prepare = atfork_prepare,
		.atfork_parent = atfork_parent,
		.atfork_child = atfork_child,
#if !TARGET_OS_DRIVERKIT
		.dirhelper = NULL,
#endif
	};

	/* Same order as _libc_initializer() at _libc_init.c:54-61. */
	_program_vars_init(vars);
	_libc_fork_init(&funcs);		/* the atfork table -- the point */
	__confstr_init(&funcs);
	__atexit_init();
	/* _init_clock_port() omitted -- see the block comment above. */
	__chk_init();
	__xlocale_init();
	__guard_setup(apple);
}
