/* SPDX-License-Identifier: BSD-2-Clause */
/* getconf(1): print POSIX configuration values.  Configure scripts ask for a
 * handful of names; unsupported names fail with a clear diagnostic. */
#include <err.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

struct conf {
	const char *name;
	long value;
};

static const struct conf confs[] = {
	{ "ARG_MAX", _SC_ARG_MAX },
	{ "CHILD_MAX", _SC_CHILD_MAX },
	{ "CLK_TCK", _SC_CLK_TCK },
	{ "NGROUPS_MAX", _SC_NGROUPS_MAX },
	{ "OPEN_MAX", _SC_OPEN_MAX },
	{ "STREAM_MAX", _SC_STREAM_MAX },
	{ "TZNAME_MAX", _SC_TZNAME_MAX },
	{ "JOB_CONTROL", _SC_JOB_CONTROL },
	{ "SAVED_IDS", _SC_SAVED_IDS },
	{ "VERSION", _SC_VERSION },
	{ "LINE_MAX", _SC_LINE_MAX },
	{ "IOV_MAX", _SC_IOV_MAX },
	{ "PAGESIZE", _SC_PAGESIZE },
	{ "PAGE_SIZE", _SC_PAGESIZE },
	{ "PHYS_PAGES", _SC_PHYS_PAGES },
	{ "NPROCESSORS_ONLN", _SC_NPROCESSORS_ONLN },
	{ "NPROCESSORS_CONF", _SC_NPROCESSORS_CONF },
	{ "_POSIX_VERSION", _SC_VERSION },
	{ "SYMLOOP_MAX", _SC_SYMLOOP_MAX },
	{ "HOST_NAME_MAX", _SC_HOST_NAME_MAX },
	{ "LOGIN_NAME_MAX", _SC_LOGIN_NAME_MAX },
	{ "TTY_NAME_MAX", _SC_TTY_NAME_MAX },
};

int
main(int argc, char *argv[])
{
	const char *path = NULL;
	size_t i;
	int ch;
	long v;

	while ((ch = getopt(argc, argv, "")) != -1)
		usage();
	argc -= optind;
	argv += optind;
	if (argc < 1 || argc > 2)
		usage();
	if (argc == 2)
		path = argv[1];
	if (strcmp(argv[0], "PATH") == 0) {
		puts(getenv("PATH") ? getenv("PATH") : "");
		return 0;
	}
	for (i = 0; i < sizeof(confs) / sizeof(confs[0]); i++) {
		if (strcmp(confs[i].name, argv[0]) != 0)
			continue;
		if ((v = sysconf(confs[i].value)) == -1) {
			if (!path)
				errx(EX_USAGE, "unsupported: %s", argv[0]);
			puts("undefined");
			return 1;
		}
		printf("%ld\n", v);
		return 0;
	}
	errx(EX_USAGE, "unknown variable: %s", argv[0]);
}

static void
usage(void)
{
	fprintf(stderr, "usage: getconf name [path]\n");
	exit(EX_USAGE);
}
