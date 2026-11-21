/* SPDX-License-Identifier: BSD-2-Clause */
/* logger(1) for ravynOS: feed a message to syslog(3), or to stderr with -s.
 * Scripts in the image use it to record installer and launchd events. */
#include <sys/types.h>

#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <syslog.h>
#include <unistd.h>

static void usage(void);

static int
parse_priority(const char *s)
{
	static const struct {
		const char *name;
		int value;
	} levels[] = {
		{ "emerg", LOG_EMERG }, { "alert", LOG_ALERT },
		{ "crit", LOG_CRIT }, { "err", LOG_ERR },
		{ "warning", LOG_WARNING }, { "notice", LOG_NOTICE },
		{ "info", LOG_INFO }, { "debug", LOG_DEBUG },
	};
	unsigned i;
	const char *dot;
	char facility[32];

	facility[0] = '\0';
	if ((dot = strchr(s, '.')) != NULL &&
	    (size_t)(dot - s) < sizeof(facility)) {
		memcpy(facility, s, (size_t)(dot - s));
		facility[dot - s] = '\0';
		s = dot + 1;
	}
	for (i = 0; i < sizeof(levels) / sizeof(levels[0]); i++)
		if (strcmp(levels[i].name, s) == 0)
			return levels[i].value;
	return LOG_NOTICE;
}

int
main(int argc, char *argv[])
{
	const char *tag = NULL;
	int pri = LOG_NOTICE;
	int ch, i, status = LOG_USER;
	int slog = 0;
	char *message = NULL, *p;
	size_t len = 0;

	while ((ch = getopt(argc, argv, "ist:p:")) != -1) {
		switch (ch) {
		case 'i': break;	/* pid is included by syslog(3) */
		case 's': slog = 1; break;
		case 't': tag = optarg; break;
		case 'p': pri = parse_priority(optarg); break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	openlog(tag, LOG_PID, status);
	if (argc == 0) {
		for (;;) {
			char buf[1024];

			if (fgets(buf, sizeof(buf), stdin) == NULL)
				break;
			buf[strcspn(buf, "\n")] = '\0';
			syslog(pri, "%s", buf);
			if (slog) {
				fprintf(stderr, "%s\n", buf);
				fflush(stderr);
			}
		}
		closelog();
		return 0;
	}
	for (i = 0; i < argc; i++) {
		size_t n = strlen(argv[i]);

		if ((p = realloc(message, len + n + 2)) == NULL)
			err(EX_OSERR, NULL);
		message = p;
		memcpy(message + len, argv[i], n);
		len += n;
		message[len++] = (i + 1 < argc) ? ' ' : '\0';
	}
	syslog(pri, "%s", message);
	if (slog) {
		fprintf(stderr, "%s\n", message);
		fflush(stderr);
	}
	closelog();
	free(message);
	return 0;
}

static void
usage(void)
{
	fprintf(stderr, "usage: logger [-is] [-p pri] [-t tag] [message ...]\n");
	exit(EX_USAGE);
}
