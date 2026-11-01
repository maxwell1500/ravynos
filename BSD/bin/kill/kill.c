/*
 * kill -- send a signal by name or number.
 *
 * The in-tree BSD kill depends on sig2str/str2sig, which this libc does not
 * provide; this keeps the table local so the tool works on ravynOS.
 */
#include <err.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const struct {
	const char *name;
	int num;
} signals[] = {
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

static int
lookup(const char *name)
{
	if (name[0] >= '0' && name[0] <= '9')
		return atoi(name);
	if (strncasecmp(name, "SIG", 3) == 0)
		name += 3;
	for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++)
		if (strcasecmp(name, signals[i].name) == 0)
			return signals[i].num;
	return -1;
}

int
main(int argc, char **argv)
{
	int sig = SIGTERM;
	int i = 1;

	if (i < argc && strcmp(argv[i], "-l") == 0) {
		for (size_t n = 0; n < sizeof(signals) / sizeof(signals[0]); n++)
			printf("%d %s\n", signals[n].num, signals[n].name);
		return 0;
	}
	if (i < argc && strcmp(argv[i], "-s") == 0 && i + 1 < argc) {
		sig = lookup(argv[i + 1]);
		i += 2;
	} else if (i < argc && argv[i][0] == '-') {
		sig = lookup(argv[i] + 1);
		i++;
	}
	if (sig < 0)
		errx(1, "unknown signal");
	if (i >= argc)
		errx(1, "usage: kill [-s signal] pid ...");

	int status = 0;
	for (; i < argc; i++) {
		pid_t pid = (pid_t)atoi(argv[i]);
		if (kill(pid, sig) != 0) {
			warn("kill %s", argv[i]);
			status = 1;
		}
	}
	return status;
}
