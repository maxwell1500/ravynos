/* SPDX-License-Identifier: ISC */
/* FreeBSD's strtonum(3): bounded string-to-integer conversion.  It lives in
 * libutil here because this tree has no BSD/lib/libc; several ported programs
 * (nproc, m4, sudo) call it. */
#include <sys/types.h>

#include <errno.h>
#include <limits.h>
#include <stdlib.h>

long long
strtonum(const char *numstr, long long minval, long long maxval,
    const char **errstrp)
{
	long long ll = 0;
	int error = 0;
	char *ep;
	struct errval {
		const char *errstr;
		int err;
	} ev[4] = {
		{ NULL, 0 },
		{ "invalid", EINVAL },
		{ "too small", ERANGE },
		{ "too large", ERANGE },
	};

	ev[0].err = errno;
	errno = 0;
	if (minval > maxval) {
		error = 1;
	} else {
		ll = strtoll(numstr, &ep, 10);
		if (numstr == ep || *ep != '\0')
			error = 1;
		else if ((ll == LLONG_MIN && errno == ERANGE) || ll < minval)
			error = 2;
		else if ((ll == LLONG_MAX && errno == ERANGE) || ll > maxval)
			error = 3;
	}
	if (errstrp != NULL)
		*errstrp = ev[error].errstr;
	errno = ev[error].err;
	if (error)
		ll = 0;

	return (ll);
}
