/* SPDX-License-Identifier: BSD-2-Clause */
/* split(1): split a file into pieces by line count (-l, default 1000) or
 * byte count (-b).  Suffixes are aa, ab, ... like the BSD tool. */
#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

static char *
next_name(const char *prefix, int n)
{
	static char name[4096];
	char *p;
	int i;

	if (strlen(prefix) + 3 >= sizeof(name))
		errx(EX_USAGE, "prefix too long");
	strcpy(name, prefix);
	p = name + strlen(name);
	p[0] = 'a' + (n / 26) % 26;
	p[1] = 'a' + n % 26;
	p[2] = '\0';
	for (i = 1; n >= 26 * 26 && i < 2; i++)
		;
	return name;
}

int
main(int argc, char *argv[])
{
	long long lines = 1000, bytes = 0;
	int ch, n = 0;
	FILE *in = stdin, *out = NULL;
	char *line = NULL;
	size_t cap = 0;
	char buf[8192];
	const char *prefix = "x";
	long long count = 0, written = 0;

	while ((ch = getopt(argc, argv, "b:l:")) != -1) {
		switch (ch) {
		case 'b': bytes = strtoll(optarg, NULL, 10); break;
		case 'l': lines = strtoll(optarg, NULL, 10); break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc > 0 && (in = fopen(argv[0], "r")) == NULL)
		err(EX_NOINPUT, "%s", argv[0]);
	if (argc > 1)
		prefix = argv[1];
	if (bytes > 0) {
		size_t nread;

		while ((nread = fread(buf, 1, sizeof(buf), in)) > 0) {
			size_t off = 0;

			while (off < nread) {
				size_t chunk;

				if (out == NULL) {
					if ((out = fopen(next_name(prefix, n++),
					    "w")) == NULL)
						err(EX_CANTCREAT, "%s",
						    next_name(prefix, n - 1));
					written = 0;
				}
				chunk = (size_t)(bytes - written);
				if (chunk > nread - off)
					chunk = nread - off;
				fwrite(buf + off, 1, chunk, out);
				written += (long long)chunk;
				off += chunk;
				if (written >= bytes) {
					fclose(out);
					out = NULL;
				}
			}
		}
	} else {
		while (getline(&line, &cap, in) != -1) {
			if (out == NULL) {
				if ((out = fopen(next_name(prefix, n++), "w")) == NULL)
					err(EX_CANTCREAT, "%s",
					    next_name(prefix, n - 1));
				count = 0;
			}
			fputs(line, out);
			if (++count >= lines) {
				fclose(out);
				out = NULL;
			}
		}
	}
	if (out != NULL)
		fclose(out);
	free(line);
	if (in != stdin)
		fclose(in);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: split [-l line_count] [-b byte_count] [file [prefix]]\n");
	exit(EX_USAGE);
}
