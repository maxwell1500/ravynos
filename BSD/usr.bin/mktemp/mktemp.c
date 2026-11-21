/* SPDX-License-Identifier: BSD-2-Clause */
/* mktemp(1) for ravynOS: create a uniquely named temporary file or directory
 * from a template ending in at least six X's.  Ports shell out to this; the
 * library mkstemp(3) is what actually does the work. */
#include <sys/types.h>
#include <sys/stat.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	const char *prefix = NULL;
	int dflag = 0, qflag = 0, uflag = 0, tflag = 0;
	int ch, fd;
	char *template, *path;
	const char *tmpdir;

	while ((ch = getopt(argc, argv, "dqt:u")) != -1) {
		switch (ch) {
		case 'd': dflag = 1; break;
		case 'q': qflag = 1; break;
		case 't': tflag = 1; prefix = optarg; break;
		case 'u': uflag = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (tflag) {
		if (argc > 1)
			usage();
		tmpdir = getenv("TMPDIR");
		if (tmpdir == NULL || *tmpdir == '\0')
			tmpdir = "/tmp";
		if (asprintf(&template, "%s/%s%s", tmpdir,
		    prefix ? prefix : "tmp", ".XXXXXXXX") == -1)
			err(EX_OSERR, NULL);
		argc = 1;
		argv = &template;
	} else if (argc == 0 || argc > 1) {
		usage();
	}
	template = argv[0];
	if (strlen(template) < 6 ||
	    strcmp(template + strlen(template) - 6, "XXXXXX") != 0) {
		if (!qflag)
			warnx("illegal template: %s", template);
		return 1;
	}
	if (dflag) {
		if ((path = mkdtemp(template)) == NULL) {
			if (!qflag)
				warn("%s", template);
			return 1;
		}
		puts(path);
		return 0;
	}
	if (uflag) {
		if ((path = mktemp(template)) == NULL || *path == '\0') {
			if (!qflag)
				warnx("cannot create %s", template);
			return 1;
		}
		puts(path);
		return 0;
	}
	if ((fd = mkstemp(template)) == -1) {
		if (!qflag)
			warn("%s", template);
		return 1;
	}
	close(fd);
	puts(template);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: mktemp [-dqu] [-t prefix] template\n");
	exit(EX_USAGE);
}
