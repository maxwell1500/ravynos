/* FreeBSD's libcapsicum helper layer.  The rights calls have no meaning on
 * ravynOS, so every helper succeeds without doing anything. */
#ifndef _RAVYN_COMPAT_CAPSICUM_HELPERS_H_
#define _RAVYN_COMPAT_CAPSICUM_HELPERS_H_

#include <sys/capsicum.h>

#define caph_cache_catpages()		(0)
#define caph_cache_tzdata()		(0)
#define caph_enter()			(0)
#define caph_enter_casper()		(0)
#define caph_rights_limit(fd, rights)	((void)(fd), (void)(rights), 0)
#define caph_ioctls_limit(fd, cmds, n)	((void)(fd), (void)(cmds), (void)(n), 0)
#define caph_fcntls_limit(fd, flags)	(0)
#define caph_limit_stdin()		(0)
#define caph_limit_stdout()		(0)
#define caph_limit_stderr()		(0)
#define caph_limit_stdio()		(0)

#endif
