/* SPDX-License-Identifier: BSD-2-Clause */
/* more(1) for ravynOS: a small terminal pager.  When output is not a terminal
 * the file is copied unchanged, which is what scripts and `man` need. */
#include <sys/ioctl.h>

#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <termios.h>
#include <unistd.h>

static void usage(void);

int
main(int argc, char *argv[])
{
	int ch, lines = 0;
	int squeeze = 0;
	FILE *fp = stdin;
	FILE *tty;
	struct winsize ws;
	char *line = NULL;
	size_t cap = 0;
	int shown = 0, eof = 0;
	int ch2, lastblank = 0;

	while ((ch = getopt(argc, argv, "n:s")) != -1) {
		switch (ch) {
		case 'n': lines = (int)strtol(optarg, NULL, 10); break;
		case 's': squeeze = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc > 1)
		usage();
	if (argc == 1 && (fp = fopen(argv[0], "r")) == NULL)
		err(EX_NOINPUT, "%s", argv[0]);
	if (lines <= 0) {
		if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 2)
			lines = ws.ws_row - 2;
		else
			lines = 22;
	}
	if (!isatty(STDOUT_FILENO)) {
		while ((ch2 = getc(fp)) != EOF)
			putchar(ch2);
		return 0;
	}
	if ((tty = fopen("/dev/tty", "r")) == NULL)
		tty = stdin;
	while (!eof) {
		shown = 0;
		while (shown < lines) {
			if (getline(&line, &cap, fp) == -1) {
				eof = 1;
				break;
			}
			if (squeeze && line[0] == '\n' && lastblank) {
				lastblank = 1;
				continue;
			}
			lastblank = line[0] == '\n';
			fputs(line, stdout);
			shown++;
		}
		if (eof)
			break;
		fputs("--More--", stdout);
		fflush(stdout);
		ch2 = getc(tty);
		fputs("\r        \r", stdout);
		if (ch2 == 'q' || ch2 == 'Q')
			break;
		if (ch2 == '\n' || ch2 == '\r')
			lines = 1;
		else
			lines = 22;
	}
	free(line);
	if (fp != stdin)
		fclose(fp);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: more [-s] [-n lines] [file]\n");
	exit(EX_USAGE);
}
