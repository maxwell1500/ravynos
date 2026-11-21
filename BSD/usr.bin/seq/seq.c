/* SPDX-License-Identifier: BSD-2-Clause */
/* seq(1): print a numeric sequence; -s separator, -w zero-padded widths,
 * -f printf format (the three are mutually exclusive, as in BSD). */
#include <err.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	const char *sep = "\n", *fmt = NULL;
	int wflag = 0, ch;
	double first = 1.0, step = 1.0, last;
	double v;
	int i, n;

	while ((ch = getopt(argc, argv, "f:s:w")) != -1) {
		switch (ch) {
		case 'f': fmt = optarg; break;
		case 's': sep = optarg; break;
		case 'w': wflag = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc == 1)
		last = atof(argv[0]);
	else if (argc == 2) {
		first = atof(argv[0]);
		last = atof(argv[1]);
	} else if (argc == 3) {
		first = atof(argv[0]);
		step = atof(argv[1]);
		last = atof(argv[2]);
	} else
		usage();
	if (step == 0.0)
		errx(EX_USAGE, "zero increment");
	n = (int)((last - first) / step) + 1;
	if (n < 0)
		n = 0;
	for (i = 0; i < n; i++) {
		v = first + step * i;
		if (fmt != NULL)
			printf(fmt, v);
		else if (wflag) {
			int width = snprintf(NULL, 0, "%.0f", last);

			printf("%0*.0f", width, v);
		} else
			printf("%.0f", v);
		if (i + 1 < n)
			fputs(sep, stdout);
	}
	if (n > 0)
		putchar('\n');
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: seq [-w] [-f format] [-s sep] [first [incr]] last\n");
	exit(EX_USAGE);
}
