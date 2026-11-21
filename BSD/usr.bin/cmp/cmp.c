/* SPDX-License-Identifier: BSD-2-Clause */
/* cmp(1): byte comparison; -l lists every difference, -s says nothing and
 * only sets the exit status. */
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	FILE *f1, *f2;
	long long line = 1, byte = 1;
	int c1, c2, lflag = 0, sflag = 0, ch, differ = 0;

	while ((ch = getopt(argc, argv, "ls")) != -1) {
		switch (ch) {
		case 'l': lflag = 1; break;
		case 's': sflag = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 2)
		usage();
	if ((f1 = fopen(argv[0], "r")) == NULL)
		err(EX_NOINPUT, "%s", argv[0]);
	if ((f2 = fopen(argv[1], "r")) == NULL)
		err(EX_NOINPUT, "%s", argv[1]);
	while ((c1 = getc(f1)) == (c2 = getc(f2))) {
		if (c1 == EOF) {
			if (ferror(f1) || ferror(f2))
				err(EX_IOERR, "read");
			return differ ? 1 : 0;
		}
		if (c1 == '\n')
			line++;
		byte++;
	}
	if (sflag)
		return 1;
	differ = 1;
	if (lflag) {
		do {
			if (c1 != c2) {
				printf("%lld %o %o\n", byte,
				    c1 == EOF ? 0 : c1, c2 == EOF ? 0 : c2);
			}
			if (c1 != EOF) {
				if (c1 == '\n')
					line++;
				byte++;
			}
		} while ((c1 = getc(f1)) != EOF || (c2 = getc(f2)) != EOF);
		return 1;
	}
	printf("%s %s differ: char %lld, line %lld\n",
	    argv[0], argv[1], byte, line);
	return 1;
}

static void
usage(void)
{
	fprintf(stderr, "usage: cmp [-ls] file1 file2\n");
	exit(EX_USAGE);
}
