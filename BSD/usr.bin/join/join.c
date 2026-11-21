/* SPDX-License-Identifier: BSD-2-Clause */
/* join(1) for ravynOS: relational join of two sorted text files.
 * Supports the option subset build scripts use: -1/-2 field numbers, -t
 * separator (default runs of whitespace), -a/-v file selection. */
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static int f1 = 1, f2 = 1;
static char sep;
static int a1, a2, v1, v2;
static int rc;

static void usage(void);

/* Split a line in place into fields; returns a malloced vector. */
static char **
split(char *line, int *nfields)
{
	char **v = NULL;
	int n = 0, cap = 0;
	char *p = line;

	p[strcspn(p, "\n")] = '\0';

	for (;;) {
		while (*p != '\0' && (sep ? *p == sep : (*p == ' ' || *p == '\t')))
			p++;
		if (*p == '\0')
			break;
		if (n == cap) {
			cap = cap ? cap * 2 : 8;
			if ((v = realloc(v, (size_t)cap * sizeof(*v))) == NULL)
				err(EX_OSERR, NULL);
		}
		v[n++] = p;
		if (sep) {
			while (*p != '\0' && *p != sep)
				p++;
		} else {
			while (*p != '\0' && *p != ' ' && *p != '\t')
				p++;
		}
		if (*p != '\0')
			*p++ = '\0';
	}
	*nfields = n;
	return v;
}

static void
emit(char **a, int na, int ja, char **b, int nb, int jb, int useb)
{
	int i;

	if (ja < 0 || ja >= na)
		return;
	fputs(a[ja], stdout);
	for (i = 0; i < na; i++)
		if (i != ja) {
			putchar(sep ? sep : ' ');
			fputs(a[i], stdout);
		}
	if (useb)
		for (i = 0; i < nb; i++)
			if (i != jb) {
				putchar(sep ? sep : ' ');
				fputs(b[i], stdout);
			}
	putchar('\n');
}

int
main(int argc, char *argv[])
{
	FILE *fa, *fb;
	char *la = NULL, *lb = NULL;
	size_t ca = 0, cb = 0;
	int ha, hb, na, nb, ch;
	char **va = NULL, **vb = NULL;

	while ((ch = getopt(argc, argv, "1:2:a:e:j:o:t:v")) != -1) {
		switch (ch) {
		case '1': f1 = (int)strtol(optarg, NULL, 10); break;
		case '2': f2 = (int)strtol(optarg, NULL, 10); break;
		case 't': sep = optarg[0]; break;
		case 'a': if (optarg[0] == '1') a1 = 1; else a2 = 1; break;
		case 'v': if (optarg[0] == '1') v1 = 1; else v2 = 1; break;
		case 'e': case 'j': case 'o': break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 2)
		usage();
	if ((fa = fopen(argv[0], "r")) == NULL)
		err(EX_NOINPUT, "%s", argv[0]);
	if ((fb = fopen(argv[1], "r")) == NULL)
		err(EX_NOINPUT, "%s", argv[1]);
	if (f1 < 1 || f2 < 1)
		errx(EX_USAGE, "bad field number");
	ha = getline(&la, &ca, fa) != -1;
	hb = getline(&lb, &cb, fb) != -1;
	va = ha ? split(la, &na) : NULL;
	vb = hb ? split(lb, &nb) : NULL;
	while (ha || hb) {
		int cmp;

		if (!ha)
			cmp = 1;
		else if (!hb)
			cmp = -1;
		else {
			const char *ka = f1 - 1 < na ? va[f1 - 1] : "";
			const char *kb = f2 - 1 < nb ? vb[f2 - 1] : "";

			cmp = strcmp(ka, kb);
		}
		if (cmp < 0) {
			if (a1 || v1)
				emit(va, na, f1 - 1, vb, nb, f2 - 1, 0);
			ha = getline(&la, &ca, fa) != -1;
			if (ha) {
				free(va);
				va = split(la, &na);
			}
		} else if (cmp > 0) {
			if (a2 || v2)
				emit(vb, nb, f2 - 1, va, na, f1 - 1, 0);
			hb = getline(&lb, &cb, fb) != -1;
			if (hb) {
				free(vb);
				vb = split(lb, &nb);
			}
		} else {
			emit(va, na, f1 - 1, vb, nb, f2 - 1, 1);
			ha = getline(&la, &ca, fa) != -1;
			hb = getline(&lb, &cb, fb) != -1;
			if (ha) {
				free(va);
				va = split(la, &na);
			}
			if (hb) {
				free(vb);
				vb = split(lb, &nb);
			}
		}
	}
	free(va);
	free(vb);
	free(la);
	free(lb);
	fclose(fa);
	fclose(fb);
	return rc;
}

static void
usage(void)
{
	fprintf(stderr, "usage: join [-a 1|2] [-v 1|2] [-1 field] [-2 field] "
	    "[-t char] file1 file2\n");
	exit(EX_USAGE);
}
