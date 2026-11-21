/* SPDX-License-Identifier: BSD-2-Clause */
/* FreeBSD's check_utility_compat(3): a utility switches to its historical
 * (non-POSIX) behaviour when the environment asks for it.  expr(1) calls this
 * for -e mode, so the symbol has to exist for the program to link. */
#include <sys/types.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int
check_utility_compat(const char *utility)
{
	char name[64];
	const char *value;

	if (utility == NULL || issetugid())
		return 0;
	if (snprintf(name, sizeof(name), "_COMPAT_%s", utility) >=
	    (int)sizeof(name))
		return 0;
	value = getenv(name);
	if (value == NULL)
		return 0;
	return (value[0] == '\0' || strcmp(value, "1") == 0 ||
	    strcasecmp(value, "yes") == 0 || strcasecmp(value, "true") == 0);
}
