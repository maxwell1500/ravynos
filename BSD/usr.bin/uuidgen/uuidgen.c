/* SPDX-License-Identifier: BSD-2-Clause */
/* uuidgen(1): generate a version-4 UUID; -l lowercases it. */
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>
#include <uuid/uuid.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	uuid_t u;
	char str[37];
	int ch, lower = 0;

	while ((ch = getopt(argc, argv, "l")) != -1) {
		switch (ch) {
		case 'l': lower = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 0)
		usage();
	uuid_generate(u);
	uuid_unparse(u, str);
	if (lower) {
		char *p;

		for (p = str; *p; p++)
			*p = (char)(*p >= 'A' && *p <= 'F' ? *p - 'A' + 'a' : *p);
	}
	puts(str);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: uuidgen [-l]\n");
	exit(EX_USAGE);
}
