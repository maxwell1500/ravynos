/* SPDX-License-Identifier: BSD-2-Clause */
/* paste(1): merge corresponding lines of files; -d list of delimiters,
 * -s serial (one file per output line). */
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	const char *delims = "\t";
	int sflag = 0, ch, i, file;
	int nfiles;
	FILE **fps;
	char *line = NULL;
	size_t cap = 0;

	while ((ch = getopt(argc, argv, "d:s")) != -1) {
		switch (ch) {
		case 'd': delims = optarg; break;
		case 's': sflag = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc == 0)
		usage();
	nfiles = argc;
	if ((fps = calloc((size_t)nfiles, sizeof(*fps))) == NULL)
		err(EX_OSERR, NULL);
	for (i = 0; i < nfiles; i++) {
		if (strcmp(argv[i], "-") == 0)
			fps[i] = stdin;
		else if ((fps[i] = fopen(argv[i], "r")) == NULL)
			err(EX_NOINPUT, "%s", argv[i]);
	}
	if (sflag) {
		for (file = 0; file < nfiles; file++) {
			int first = 1;

			while (getline(&line, &cap, fps[file]) != -1) {
				line[strcspn(line, "\n")] = '\0';
				if (!first)
					putchar(delims[0]);
				fputs(line, stdout);
				first = 0;
			}
			putchar('\n');
		}
	} else {
		int done;

		do {
			done = 1;
			for (file = 0; file < nfiles; file++) {
				if (getline(&line, &cap, fps[file]) == -1)
					continue;
				line[strcspn(line, "\n")] = '\0';
				if (file > 0)
					putchar(delims[0]);
				fputs(line, stdout);
				done = 0;
			}
			if (!done)
				putchar('\n');
		} while (!done);
	}
	free(line);
	free(fps);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: paste [-s] [-d delimiters] file ...\n");
	exit(EX_USAGE);
}
