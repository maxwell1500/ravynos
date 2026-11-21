/* SPDX-License-Identifier: BSD-2-Clause */
/* nice(1): run a command at a modified scheduling priority. */
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
	int adjustment = 10;
	int ch, prio;

	while ((ch = getopt(argc, argv, "n:")) != -1) {
		switch (ch) {
		case 'n':
			adjustment = (int)strtol(optarg, NULL, 10);
			break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc == 0)
		usage();
	errno = 0;
	prio = getpriority(PRIO_PROCESS, 0);
	if (errno != 0)
		err(EX_OSERR, "getpriority");
	if (setpriority(PRIO_PROCESS, 0, prio + adjustment) == -1)
		err(EX_OSERR, "setpriority");
	execvp(argv[0], argv);
	err(EX_OSERR, "%s", argv[0]);
}

static void
usage(void)
{
	fprintf(stderr, "usage: nice [-n increment] command [args ...]\n");
	exit(EX_USAGE);
}
