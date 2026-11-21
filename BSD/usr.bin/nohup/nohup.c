/* SPDX-License-Identifier: BSD-2-Clause */
/* nohup(1): run a command immune to hangup, with output redirected to
 * nohup.out when stdout is a terminal. */
#include <sys/types.h>

#include <err.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	int fd;

	if (argc < 2)
		usage();
	if (signal(SIGHUP, SIG_IGN) == SIG_ERR)
		err(EX_OSERR, "signal");
	if (isatty(STDOUT_FILENO)) {
		if ((fd = open("nohup.out", O_WRONLY | O_CREAT | O_APPEND,
		    0600)) == -1) {
			const char *home = getenv("HOME");
			char *path = NULL;

			if (home != NULL &&
			    asprintf(&path, "%s/nohup.out", home) != -1 &&
			    (fd = open(path, O_WRONLY | O_CREAT | O_APPEND,
			    0600)) != -1) {
				free(path);
			} else {
				err(EX_CANTCREAT, "nohup.out");
			}
		}
		if (fd != STDOUT_FILENO) {
			if (dup2(fd, STDOUT_FILENO) == -1)
				err(EX_OSERR, "dup2");
			close(fd);
		}
		if (isatty(STDERR_FILENO) && dup2(STDOUT_FILENO, STDERR_FILENO) == -1)
			err(EX_OSERR, "dup2");
	}
	execvp(argv[1], argv + 1);
	err(EX_OSERR, "%s", argv[1]);
}

static void
usage(void)
{
	fprintf(stderr, "usage: nohup command [args ...]\n");
	exit(EX_USAGE);
}
