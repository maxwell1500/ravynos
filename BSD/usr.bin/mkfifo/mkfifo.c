/* SPDX-License-Identifier: BSD-2-Clause */
/* mkfifo(1): create named pipes; -m sets the permission bits. */
#include <sys/types.h>
#include <sys/stat.h>

#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	mode_t mode = 0666;
	mode_t mask;
	int ch, rc = 0, i;

	while ((ch = getopt(argc, argv, "m:")) != -1) {
		switch (ch) {
		case 'm':
			mode = (mode_t)strtol(optarg, NULL, 8);
			break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc == 0)
		usage();
	mask = umask(0);
	umask(mask);
	for (i = 0; i < argc; i++)
		if (mkfifo(argv[i], mode & ~mask) == -1) {
			warn("%s", argv[i]);
			rc = 1;
		}
	return rc;
}

static void
usage(void)
{
	fprintf(stderr, "usage: mkfifo [-m mode] fifo ...\n");
	exit(EX_USAGE);
}
