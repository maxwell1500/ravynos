/* SPDX-License-Identifier: BSD-2-Clause */
/* comm(1): three-column comparison of two sorted files. */
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

/* POSIX comm separates columns with tabs, and only for the columns that are
 * actually printed: a later enabled column contributes one leading tab. */
static void
column(const char *line, int col, const int *suppress)
{
	int i;

	for (i = 0; i < col; i++)
		if (!suppress[i])
			putchar('\t');
	fputs(line, stdout);
}

int
main(int argc, char *argv[])
{
	char *l1 = NULL, *l2 = NULL;
	size_t c1 = 0, c2 = 0;
	int suppress[3] = { 0, 0, 0 };
	int ch, e1, e2;
	FILE *f1, *f2;

	while ((ch = getopt(argc, argv, "123")) != -1) {
		switch (ch) {
		case '1': suppress[0] = 1; break;
		case '2': suppress[1] = 1; break;
		case '3': suppress[2] = 1; break;
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
	e1 = getline(&l1, &c1, f1) != -1;
	e2 = getline(&l2, &c2, f2) != -1;
	while (e1 || e2) {
		int cmp;

		if (!e1)
			cmp = 1;
		else if (!e2)
			cmp = -1;
		else
			cmp = strcmp(l1, l2);
		if (cmp < 0) {
			if (!suppress[0])
				column(l1, 0, suppress);
			e1 = getline(&l1, &c1, f1) != -1;
		} else if (cmp > 0) {
			if (!suppress[1])
				column(l2, 1, suppress);
			e2 = getline(&l2, &c2, f2) != -1;
		} else {
			if (!suppress[2])
				column(l1, 2, suppress);
			e1 = getline(&l1, &c1, f1) != -1;
			e2 = getline(&l2, &c2, f2) != -1;
		}
	}
	free(l1);
	free(l2);
	fclose(f1);
	fclose(f2);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: comm [-123] file1 file2\n");
	exit(EX_USAGE);
}
