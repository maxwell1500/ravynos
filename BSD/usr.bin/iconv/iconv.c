/* SPDX-License-Identifier: BSD-2-Clause */
/* iconv(1): convert a stream between character encodings using iconv(3).
 * Build scripts pipe text through this; -c drops unconvertible characters. */
#include <err.h>
#include <errno.h>
#include <iconv.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	const char *from = "UTF-8", *to = "UTF-8";
	int ch, discard = 0, silent = 0;
	iconv_t cd;
	char inbuf[8192], outbuf[8192];
	char *inp, *outp;
	size_t inleft, outleft;
	ssize_t n;
	FILE *fp = stdin;

	while ((ch = getopt(argc, argv, "csf:t:")) != -1) {
		switch (ch) {
		case 'c': discard = 1; break;
		case 's': silent = 1; break;
		case 'f': from = optarg; break;
		case 't': to = optarg; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc > 1)
		usage();
	if (argc == 1 && (fp = fopen(argv[0], "r")) == NULL)
		err(EX_NOINPUT, "%s", argv[0]);
	if ((cd = iconv_open(to, from)) == (iconv_t)-1)
		errx(EX_USAGE, "iconv_open(%s, %s): %s", to, from,
		    strerror(errno));
	while ((n = fread(inbuf, 1, sizeof(inbuf), fp)) > 0) {
		inp = inbuf;
		inleft = (size_t)n;
		while (inleft > 0) {
			outp = outbuf;
			outleft = sizeof(outbuf);
			if (iconv(cd, &inp, &inleft, &outp, &outleft) ==
			    (size_t)-1) {
				if (errno == E2BIG) {
					fwrite(outbuf, 1, sizeof(outbuf) - outleft,
					    stdout);
					continue;
				}
				if (discard) {
					inp++;
					inleft--;
					continue;
				}
				if (!silent)
					warnx("conversion error");
				return 1;
			}
			fwrite(outbuf, 1, sizeof(outbuf) - outleft, stdout);
		}
	}
	iconv_close(cd);
	if (fp != stdin)
		fclose(fp);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: iconv [-cs] -f from -t to [file]\n");
	exit(EX_USAGE);
}
