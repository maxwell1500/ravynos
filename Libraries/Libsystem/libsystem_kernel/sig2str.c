/* SPDX-License-Identifier: BSD-2-Clause */
/* sig2str(3)/str2sig(3): the BSD signal-name conversions that FreeBSD libc
 * exports and kill(1) otherwise carries privately. */
#include <sys/types.h>

#include <errno.h>
#include <signal.h>
#include <string.h>

struct signal_name {
	const char *name;
	int number;
};

static const struct signal_name signals[] = {
	{ "HUP", SIGHUP }, { "INT", SIGINT }, { "QUIT", SIGQUIT },
	{ "ILL", SIGILL }, { "TRAP", SIGTRAP }, { "ABRT", SIGABRT },
	{ "EMT", SIGEMT }, { "FPE", SIGFPE }, { "KILL", SIGKILL },
	{ "BUS", SIGBUS }, { "SEGV", SIGSEGV }, { "SYS", SIGSYS },
	{ "PIPE", SIGPIPE }, { "ALRM", SIGALRM }, { "TERM", SIGTERM },
	{ "URG", SIGURG }, { "STOP", SIGSTOP }, { "TSTP", SIGTSTP },
	{ "CONT", SIGCONT }, { "CHLD", SIGCHLD }, { "TTIN", SIGTTIN },
	{ "TTOU", SIGTTOU }, { "IO", SIGIO }, { "XCPU", SIGXCPU },
	{ "XFSZ", SIGXFSZ }, { "VTALRM", SIGVTALRM }, { "PROF", SIGPROF },
	{ "WINCH", SIGWINCH }, { "INFO", SIGINFO }, { "USR1", SIGUSR1 },
	{ "USR2", SIGUSR2 },
};

int
sig2str(int signo, char *signalname)
{
	unsigned i;

	for (i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
		if (signals[i].number == signo) {
			strcpy(signalname, signals[i].name);
			return 0;
		}
	}
	errno = EINVAL;
	return -1;
}

int
str2sig(const char *signalname, int *signop)
{
	unsigned i;
	const char *name = signalname;

	if (strncasecmp(name, "SIG", 3) == 0)
		name += 3;
	for (i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
		if (strcasecmp(signals[i].name, name) == 0) {
			*signop = signals[i].number;
			return 0;
		}
	}
	errno = EINVAL;
	return -1;
}
