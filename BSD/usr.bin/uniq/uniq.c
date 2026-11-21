/* SPDX-License-Identifier: BSD-2-Clause */
/* uniq(1): filter adjacent equal lines; -c prefix counts, -d only duplicates,
 * -u only unique lines, -i compares case-insensitively. */
#include <ctype.h>
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

static int
same(const char *a, const char *b, int icase)
{
	if (!icase)
		return strcmp(a, b) == 0;
	for (; *a && *b; a++, b++)
		if (tolower((unsigned char)*a) != tolower((unsigned char)*b))
			return 0;
	return *a == *b;
}

int
main(int argc, char *argv[])
{
	int cflag = 0, dflag = 0, uflag = 0, iflag = 0;
	int ch;
	char *prev = NULL, *line = NULL;
	size_t cap = 0;
	long count = 0;
	FILE *fp = stdin;
	FILE *out = stdout;

	while ((ch = getopt(argc, argv, "cdiu")) != -1) {
		switch (ch) {
		case 'c': cflag = 1; break;
		case 'd': dflag = 1; break;
		case 'i': iflag = 1; break;
		case 'u': uflag = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc > 2)
		usage();
	if (argc >= 1 && (fp = fopen(argv[0], "r")) == NULL)
		err(EX_NOINPUT, "%s", argv[0]);
	if (argc == 2 && (out = fopen(argv[1], "w")) == NULL)
		err(EX_CANTCREAT, "%s", argv[1]);
	while (getline(&line, &cap, fp) != -1) {
		if (prev != NULL && same(prev, line, iflag)) {
			count++;
			continue;
		}
		if (prev != NULL) {
			if (!(dflag && count == 1) && !(uflag && count > 1)) {
				if (cflag)
					fprintf(out, "%7ld ", count);
				fputs(prev, out);
			}
		}
		free(prev);
		if ((prev = strdup(line)) == NULL)
			err(EX_OSERR, NULL);
		count = 1;
	}
	if (prev != NULL &&
	    !(dflag && count == 1) && !(uflag && count > 1)) {
		if (cflag)
			printf("%7ld ", count);
		fputs(prev, out);
	}
	free(prev);
	free(line);
	if (fp != stdin)
		fclose(fp);
	if (out != stdout)
		fclose(out);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: uniq [-cdiu] [input [output]]\n");
	exit(EX_USAGE);
}
