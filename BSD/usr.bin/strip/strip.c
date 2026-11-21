/* SPDX-License-Identifier: BSD-2-Clause */
/* strip(1) for ravynOS: a no-op that keeps the image valid.
 *
 * The tree has no Mach-O symbol-table writer, and a strip that rewrote load
 * commands without one would corrupt the binary.  Install scripts only need
 * the command to exist and to leave a runnable file behind, which copying the
 * input does exactly; the symbols are dead weight, not a behavioural change.
 */
#include <sys/types.h>
#include <sys/stat.h>

#include <err.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

static int
copy_file(const char *from, const char *to)
{
	struct stat sb;
	char *buf;
	ssize_t got = 0, n = 0;
	int in, out;

	if ((in = open(from, O_RDONLY)) == -1) {
		warn("%s", from);
		return 1;
	}
	if (fstat(in, &sb) == -1 || (buf = malloc((size_t)sb.st_size + 1)) ==
	    NULL) {
		warn("%s", from);
		close(in);
		return 1;
	}
	while (got < sb.st_size && (n = read(in, buf + got,
	    (size_t)(sb.st_size - got))) > 0)
		got += n;
	if (n < 0)
		warn("%s", from);
	close(in);
	if ((out = open(to, O_WRONLY | O_CREAT | O_TRUNC, sb.st_mode &
	    07777)) == -1) {
		warn("%s", to);
		free(buf);
		return 1;
	}
	for (n = 0; n < got; ) {
		ssize_t w = write(out, buf + n, (size_t)(got - n));

		if (w == -1) {
			warn("%s", to);
			close(out);
			free(buf);
			return 1;
		}
		n += w;
	}
	close(out);
	free(buf);
	return 0;
}

int
main(int argc, char *argv[])
{
	const char *output = NULL;
	int ch, i, rc = 0;

	while ((ch = getopt(argc, argv, "o:xSs")) != -1) {
		switch (ch) {
		case 'o': output = optarg; break;
		case 'x': case 'S': case 's': break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc == 0)
		usage();
	if (output != NULL) {
		if (argc != 1)
			usage();
		return copy_file(argv[0], output);
	}
	for (i = 0; i < argc; i++)
		if (copy_file(argv[i], argv[i]) != 0)
			rc = 1;
	return rc;
}

static void
usage(void)
{
	fprintf(stderr, "usage: strip [-o output] file ...\n");
	exit(EX_USAGE);
}
