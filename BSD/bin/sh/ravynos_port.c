/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * ravynOS port glue for BSD/bin/sh.
 *
 * The general static-link residue -- dyld slide, os_log, TLV, mach_msg2,
 * vouchers, mach_msg_priority_*, notify_*, fpclassify, getsectiondata, and the
 * open$NOCANCEL variant -- lives in Libraries/Libsystem/static/stubs.c and is
 * linked into every static ravynOS program by tools/bootlab/link-static.sh.
 * This file deliberately does NOT duplicate it: two definitions of the same
 * symbol is a link error, and two near-copies is worse.
 *
 * The entry point is tools/bootlab/static-start.c, shared by every static
 * ravynOS program for the same reason.
 *
 * So what is left here is exactly what the shell needs and nothing else
 * provides. Each item is a measured gap, and each returns the value that is
 * correct rather than a placeholder that hides the gap.
 *
 *   1. getpwnam/getpwuid/getpwnam_r/getpwuid_r/getpwent/...
 *      NO LONGER HERE. The passwd database moved to
 *      Libraries/Libsystem/libsystem_pwdgrp/, which is a real component with
 *      25 exported symbols covering both the passwd and group databases, the
 *      fget* forms, the iteration _r forms and user_from_uid/group_from_gid.
 *      The shell links its static archive through RAVYN_EXTRA_LIBS.
 *
 *      This file used to carry a private parser for those functions, and that
 *      arrangement is now deliberately gone rather than merely unused. It
 *      cannot coexist: one link, one getpwnam. Two definitions is a link
 *      error, which is the same lesson as openat$NOCANCEL arriving from two
 *      places. One owner for one symbol is the only correct arrangement.
 *
 *      Nothing was lost in the move. The library's parser carries all three
 *      fixes forward, and they were worth carrying:
 *        - the trailing '\n'/'\r' is stripped before parsing, because the last
 *          field of a line has no colon after it and would otherwise absorb
 *          the line terminator (pw_shell came back as "/bin/sh\n");
 *        - a line longer than the buffer is drained to the next newline
 *          instead of having its tail parsed as an entry in its own right;
 *        - field buffers are sized at the line length, so a name longer than
 *          the old 256 bytes is reachable instead of silently truncated.
 *
 *   2. openat$NOCANCEL -- SUPPLIED BY stubs.c NOW, not here.
 *      stubs.c grew an openat$NOCANCEL alias while this file already had one,
 *      which is a duplicate symbol. This file's copy was removed and stubs.c's
 *      kept: one owner, again.
 *
 *   3. getrlimit$UNIX2003, pthread_join$NOCANCEL$UNIX2003
 *      The Mach-O variant story: ld64 synthesises $<variant> aliases from
 *      libsyscall's double-underscore objects only when they are reached
 *      through the libsyscall .a machinery; linking raw .o members does not
 *      create them, so the two spellings the pthread build references are
 *      named explicitly. The bodies are the real functions.
 */

/* No #include is needed any more. What remains is two long-returning
 * functions over an extern long declaration, and every type in sight
 * (long, void *) is a builtin. Carrying <pwd.h>, <stdio.h> and friends here
 * would be an accurate-looking lie about what this file still depends on. */

/* ------------------------------------------------------------------ */
/* 2 + 3. Mach-O symbol variants					      */
/* ------------------------------------------------------------------ */
/*
 * Not stubs. Each body is the real function; only the Mach-O spelling of the
 * symbol differs, which is exactly what the $NOCANCEL / $UNIX2003 variants
 * are. The double-underscore forms live in libsyscalls.a and
 * libpthread_static.a.
 */
extern long __getrlimit(void *rlim, void *unused);

long rav_getrlimit_u2003(void *rlim, void *unused)
	__asm__("_getrlimit$UNIX2003");
long
rav_getrlimit_u2003(void *rlim, void *unused)
{
	return __getrlimit(rlim, unused);
}

/* C identifiers cannot contain '$', and the compiler prepends an underscore
 * to whatever spelling it is handed, so a variant is declared under a legal C
 * name and given its exact Mach-O spelling with an asm label.
 *
 * libpthread_static.a already defines _pthread_join$NOCANCEL, so this is a
 * declaration, not a second definition: only the $UNIX2003 spelling -- which
 * ld64 will not synthesise for a raw .o -- needs a body. */
extern long rav_pthread_join_nc(long, void **)
	__asm__("_pthread_join$NOCANCEL");

long rav_pthread_join_nc_u2003(long thread, void **retval)
	__asm__("_pthread_join$NOCANCEL$UNIX2003");
long
rav_pthread_join_nc_u2003(long thread, void **retval)
{
	return rav_pthread_join_nc(thread, retval);
}
