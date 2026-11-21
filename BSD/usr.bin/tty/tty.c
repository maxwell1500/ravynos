/* SPDX-License-Identifier: BSD-2-Clause */
/* tty(1): print the terminal name, or fail when stdin is not a terminal.
 * Shell startup scripts in the image use `tty -s` to decide on prompts. */
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	int silent = 0;
	int ch;
	const char *name;

	while ((ch = getopt(argc, argv, "s")) != -1) {
		switch (ch) {
		case 's': silent = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 0)
		usage();
	if ((name = ttyname(STDIN_FILENO)) != NULL) {
		if (!silent)
			puts(name);
		return 0;
	}
	if (!silent)
		puts("not a tty");
	return 1;
}

static void
usage(void)
{
	fprintf(stderr, "usage: tty [-s]\n");
	exit(EX_USAGE);
}
