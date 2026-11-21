/* SPDX-License-Identifier: BSD-2-Clause */
/* strings(1): print printable runs from a file; -n sets the minimum run
 * length, -t d|x prefixes the offset in decimal or hex. */
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

static void
print_run(const char *buf, size_t len, long long start, int tflag, char tchar)
{
	if (tflag) {
		if (tchar == 'x')
			printf("%7llx ", start);
		else
			printf("%7lld ", start);
	}
	fwrite(buf, 1, len, stdout);
	putchar('\n');
}

int
main(int argc, char *argv[])
{
	int ch, minlen = 4, tflag = 0, seenfile = 0;
	char tchar = 0;
	long long off = 0, start = 0;
	int c;
	FILE *fp = stdin;
	char *buf = NULL;
	size_t len = 0, cap = 0;

	while ((ch = getopt(argc, argv, "an:t:")) != -1) {
		switch (ch) {
		case 'a': break;
		case 'n': minlen = (int)strtol(optarg, NULL, 10); break;
		case 't': tflag = 1; tchar = optarg[0]; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	do {
		if (argc > 0) {
			if ((fp = fopen(argv[seenfile], "rb")) == NULL)
				err(EX_NOINPUT, "%s", argv[seenfile]);
		}
		off = 0;
		start = 0;
		len = 0;
		while ((c = getc(fp)) != EOF) {
			if (c >= 0x20 && c < 0x7f) {
				if (len == 0)
					start = off;
				if (len + 1 >= cap) {
					char *nb;

					cap = cap ? cap * 2 : 128;
					if ((nb = realloc(buf, cap)) == NULL)
						err(EX_OSERR, NULL);
					buf = nb;
				}
				buf[len++] = (char)c;
			} else {
				if ((int)len >= minlen)
					print_run(buf, len, start, tflag, tchar);
				len = 0;
			}
			off++;
		}
		if ((int)len >= minlen)
			print_run(buf, len, start, tflag, tchar);
		if (fp != stdin)
			fclose(fp);
	} while (++seenfile < argc);
	free(buf);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: strings [-a] [-n minlen] [-t d|x] [file ...]\n");
	exit(EX_USAGE);
}
