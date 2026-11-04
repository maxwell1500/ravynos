/*
 * Minimal libbsm.0.dylib for stock macOS clients.
 *
 * Firefox binds _audit_token_to_pid from /usr/lib/libbsm.0.dylib.  The
 * audit token is the kernel's audit_token_t: val[5] is the pid, val[6] the
 * audit session id and val[7] the pid version.  These are the documented
 * accessors, not fabricated values.
 */
#include <mach/message.h>
#include <sys/types.h>

pid_t
audit_token_to_pid(audit_token_t atoken)
{
	return (pid_t)atoken.val[5];
}

uint32_t
audit_token_to_asid(audit_token_t atoken)
{
	return (uint32_t)atoken.val[6];
}

uint32_t
audit_token_to_pidversion(audit_token_t atoken)
{
	return (uint32_t)atoken.val[7];
}
