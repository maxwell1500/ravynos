/*
 * sandbox_check()/sandbox_init() for launchd.
 *
 * libSystem in this tree does not implement the sandbox API, so launchd did
 * not link once core.c's sandbox paths compiled.  The daily-driver plan makes
 * sandbox application an accept-and-log no-op until Phase 5.4: queries are
 * allowed (sandbox_check returns 0) and applying a profile succeeds, with one
 * line naming the profile so the audit trail shows what would have been
 * confined.  This is a no-op by decision, not a silent fake.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <sys/types.h>

int
sandbox_check(pid_t pid, const char *operation, int filter_type, ...)
{
	(void)pid;
	(void)operation;
	(void)filter_type;
	return (0);	/* allowed */
}

int
sandbox_init(const char *profile, uint64_t flags, char **errorbuf)
{
	(void)flags;
	if (errorbuf != NULL)
		*errorbuf = NULL;
	fprintf(stderr, "[sandbox] profile applied as no-op: %s\n",
	    profile ? profile : "(null)");
	return (0);
}

int
sandbox_free_error(char *errorbuf)
{
	(void)errorbuf;
	return (0);
}
