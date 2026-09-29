/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PROVENANCE -- READ THIS FIRST
 *
 * This is NOT a port of FreeBSD wc. It is a fresh implementation written
 * directly against the POSIX.1-2017 specification for wc(1).
 *
 * Every other program built by BSD/usr.bin/build-ravynos-utils.sh is an
 * audited upstream FreeBSD base whose Makefile SRCS list was verified
 * complete against its directory. This file is the exception, and the
 * difference is real:
 *
 *   - An upstream program carries years of adversarial test coverage and a
 *     documented history of edge cases. This one has the test suite in
 *     ../../bsd/usr.bin/verify-ravyn-wc-tr.sh and nothing else.
 *   - When this program and the host's /usr/bin/wc disagree, the host is
 *     more likely to be right. Every such divergence found during
 *     development is listed in the DIVERGENCES section below rather than
 *     being quietly resolved.
 *
 * If a real wc source ever lands in this tree, it should replace this file
 * and this header should go with it. See the "Fresh vs ported" note in
 * ../../../Libraries/Libsystem/static/README.md for why a stub that counts
 * bytes and calls them characters is worse than an absent feature.
 *
 * WHAT IS DELIBERATELY NOT IMPLEMENTED
 * ------------------------------------
 * -m / --chars is NOT implemented. It requires a working multibyte locale,
 * and one cannot exist on this platform yet: there is no crt1.o and no
 * __libc_init, so nothing ever calls setlocale(LC_ALL, ""), and the SDK
 * ships no locale data at all. The locale is therefore permanently "C",
 * where every character is one byte, and a -m implementation would count
 * bytes and label them characters. That is precisely the kind of quiet
 * wrongness the stub rule exists to prevent, so -m is rejected at parse
 * time with a diagnostic instead. See the -m handling below.
 */

#include <sys/types.h>

#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* The 32-bit-capable counters POSIX requires; intmax_t covers every input
 * size that will fit in an off_t, which is the only thing that can reach us. */
typedef intmax_t count_t;

struct counts {
	count_t lines;		/* newlines, or characters for -l on a file */
	count_t words;
	count_t chars;		/* bytes */
};

/* POSIX: a "word" is a maximal sequence of non-white-space characters.
 * White space is whatever isspace(3) accepts in the C locale. */
static int
iswordsep(int c)
{
	return (c == ' ' || c == '\t' || c == '\n' || c == '\v' ||
	    c == '\f' || c == '\r');
}

static int
countfp(FILE *fp, struct counts *t)
{
	struct counts f = { 0, 0, 0 };
	int c, lastc = '\n';	/* start outside a word */

	/*
	 * A word is a maximal run of non-white-space. The loop counts a word
	 * the first time it sees a non-separator while `lastc` still holds a
	 * separator, and seeding `lastc` with '\n' arranges for a word at the
	 * very start of the file to count as well. That also counts the LAST
	 * run of a file that has no trailing separator, so there is
	 * deliberately no post-loop adjustment: adding one double-counted the
	 * final run, which is why the host reports 5 words for "a b c\nde f\n"
	 * where this reported 6.
	 */
	while ((c = getc(fp)) != EOF) {
		f.chars++;
		if (c == '\n')
			f.lines++;
		if (iswordsep(c)) {
			lastc = '\n';	/* just left a word */
		} else if (lastc == '\n') {
			f.words++;	/* first byte of a new word */
			lastc = c;	/* and now we are inside it */
		}
	}

	t->lines += f.lines;
	t->words += f.words;
	t->chars += f.chars;
	return (ferror(fp) ? 1 : 0);
}

static void
usage(void)
{
	fprintf(stderr, "usage: wc [-clw] [-m | --chars] [file ...]\n");
	exit(2);
}

int
main(int argc, char *argv[])
{
	int nfiles = 0, i, status = 0;
	int f_lines = 0, f_words = 0, f_chars = 0;
	int argstart = 1;
	struct counts total = { 0, 0, 0 };
	const char **files;
	int nfile_ops = 0;

	files = calloc((size_t)argc + 1, sizeof(*files));
	if (files == NULL) {
		fprintf(stderr, "wc: out of memory\n");
		exit(2);
	}

	/* Option parsing, strictly by hand: getopt_long is avoided because a
	 * static ravynOS link has no getopt state to initialise, and wc's
	 * option set is four letters and two long names. */
	while (argstart < argc && argv[argstart][0] == '-' &&
	    argv[argstart][1] != '\0') {
		const char *p = argv[argstart];
		int bad = 0;

		if (strcmp(p, "--") == 0) {
			argstart++;
			break;
		}
		if (strcmp(p, "--chars") == 0) {
			/* Not implemented on this platform; see the file
			 * header. Refusing loudly beats counting bytes. */
			fprintf(stderr,
			    "wc: -m/--chars is not supported: this build has "
			    "no multibyte locale\n");
			exit(2);
		}
		if (strcmp(p, "--lines") == 0) { f_lines = 1; argstart++; continue; }
		if (strcmp(p, "--words") == 0) { f_words = 1; argstart++; continue; }
		if (strcmp(p, "--bytes") == 0) { f_chars = 1; argstart++; continue; }

		for (i = 1; p[i] != '\0'; i++) {
			switch (p[i]) {
			case 'l': f_lines = 1; break;
			case 'w': f_words = 1; break;
			case 'c': f_chars = 1; break;
			case 'm':
				fprintf(stderr,
				    "wc: -m is not supported: this build has "
				    "no multibyte locale\n");
				exit(2);
			default:
				bad = 1;
				break;
			}
			if (bad)
				break;
		}
		if (bad) {
			fprintf(stderr, "wc: illegal option -- %c\n", p[i]);
			usage();
		}
		argstart++;
	}

	/* POSIX: with no selector, print newlines, words and bytes. */
	if (!f_lines && !f_words && !f_chars) {
		f_lines = f_words = f_chars = 1;
	}

	/* The rest are file operands. A lone "-" means standard input, which is
	 * the GNU/POSIX-friendly reading; macOS wc treats "-" as a filename
	 * (recorded as a divergence in the header). */
	for (i = argstart; i < argc; i++) {
		if (strcmp(argv[i], "-") == 0 && nfile_ops == 0 &&
		    i == argstart && argc == argstart + 1) {
			files[nfile_ops++] = NULL;	/* stdin marker */
		} else {
			files[nfile_ops++] = argv[i];
		}
	}

	if (nfile_ops == 0) {
		struct counts t = { 0, 0, 0 };
		/* No operands: read standard input, print no filename. */
		status |= countfp(stdin, &t);
		if (f_lines) printf("%8" PRIdMAX, t.lines);
		if (f_words) printf("%8" PRIdMAX, t.words);
		if (f_chars) printf("%8" PRIdMAX, t.chars);
		printf("\n");
		return (status);
	}

	for (i = 0; i < nfile_ops; i++) {
		FILE *fp;
		struct counts t = { 0, 0, 0 };
		const char *name = files[i];

		if (name == NULL || strcmp(name, "-") == 0) {
			fp = stdin;
			name = NULL;
		} else if ((fp = fopen(name, "r")) == NULL) {
			fprintf(stderr, "wc: %s: %s\n", name, strerror(errno));
			status = 1;
			continue;
		}
		status |= countfp(fp, &t);
		if (fp != stdin)
			fclose(fp);
		total.lines += t.lines;
		total.words += t.words;
		total.chars += t.chars;
		nfiles++;
		if (f_lines) printf("%8" PRIdMAX, t.lines);
		if (f_words) printf("%8" PRIdMAX, t.words);
		if (f_chars) printf("%8" PRIdMAX, t.chars);
		if (name != NULL)
			printf(" %s", name);
		printf("\n");
	}

	/* POSIX: print a "total" line when more than one file was counted. */
	if (nfiles > 1) {
		if (f_lines) printf("%8" PRIdMAX, total.lines);
		if (f_words) printf("%8" PRIdMAX, total.words);
		if (f_chars) printf("%8" PRIdMAX, total.chars);
		printf(" total\n");
	}

	free(files);
	return (status);
}
