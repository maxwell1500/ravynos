/* SPDX-License-Identifier: BSD-2-Clause */
/* pkill(1)/pgrep(1) for ravynOS.
 *
 * The FreeBSD program reads the process table through libkvm, and ravynOS has
 * no libkvm: process state comes from the kernel's proc_info interface, which
 * is also what ps(1) uses (sysctl KERN_PROC).  This is the same instrument
 * with the subset of options scripts use.  Both names are the one binary,
 * selected by argv[0]. */
#include <sys/types.h>
#include <sys/sysctl.h>

#include <err.h>
#include <errno.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static int fflag;		/* match against full argument list */
static int xflag;		/* exact match */
static int nflag;		/* newest process only */
static int oflag;		/* oldest process only */

static void usage(void);

static uid_t
parse_uid(const char *s)
{
	struct passwd *pw;
	char *end;
	unsigned long v;

	if ((pw = getpwnam(s)) != NULL)
		return pw->pw_uid;
	v = strtoul(s, &end, 10);
	if (*s == '\0' || *end != '\0')
		errx(EX_USAGE, "unknown user: %s", s);
	return (uid_t)v;
}

static int
matches(const char *pattern, const char *candidate)
{
	if (xflag)
		return strcmp(pattern, candidate) == 0;
	return strstr(candidate, pattern) != NULL;
}

/* KERN_PROCARGS2 returns: int argc, executable path, NULs, then argc
 * NUL-separated strings.  Join the arguments with spaces for -f matching. */
static char *
procargs(pid_t pid)
{
	int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid };
	size_t size = 0;
	char *buf, *p, *end, *out = NULL;
	size_t outlen = 0;
	int argc, i;

	if (sysctl(mib, 3, NULL, &size, NULL, 0) == -1 || size == 0)
		return NULL;
	if ((buf = malloc(size + 1)) == NULL)
		return NULL;
	if (sysctl(mib, 3, buf, &size, NULL, 0) == -1) {
		free(buf);
		return NULL;
	}
	buf[size] = '\0';
	memcpy(&argc, buf, sizeof(argc));
	end = buf + size;
	p = buf + sizeof(argc);
	while (p < end && *p != '\0')	/* executable path */
		p++;
	while (p < end && *p == '\0')
		p++;
	for (i = 0; i < argc && p < end && *p != '\0'; i++) {
		size_t n = strlen(p);
		char *nb = realloc(out, outlen + n + 2);

		if (nb == NULL) {
			free(out);
			free(buf);
			return NULL;
		}
		out = nb;
		memcpy(out + outlen, p, n);
		outlen += n;
		out[outlen++] = ' ';
		p += n + 1;
	}
	if (out != NULL)
		out[outlen > 0 ? outlen - 1 : 0] = '\0';
	free(buf);
	return out;
}

static int
signal_number(const char *s)
{
	static const struct {
		const char *name;
		int num;
	} sigs[] = {
		{ "HUP", SIGHUP }, { "INT", SIGINT }, { "QUIT", SIGQUIT },
		{ "KILL", SIGKILL }, { "TERM", SIGTERM }, { "STOP", SIGSTOP },
		{ "CONT", SIGCONT }, { "USR1", SIGUSR1 }, { "USR2", SIGUSR2 },
	};
	unsigned i;
	char *end;
	long n;

	if (strncmp(s, "SIG", 3) == 0)
		s += 3;
	for (i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++)
		if (strcmp(sigs[i].name, s) == 0)
			return sigs[i].num;
	n = strtol(s, &end, 10);
	return (*end == '\0' && n > 0 && n < NSIG) ? (int)n : -1;
}

int
main(int argc, char *argv[])
{
	struct kinfo_proc *procs, *kp;
	size_t size;
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
	int ch, sig = SIGTERM, i, nproc, matched = 0;
	int pgrep_mode;
	int uflag = 0, Uflag = 0, gflag = 0, Pflag = 0;
	uid_t uid = 0;
	pid_t pgid = 0, ppid = 0;
	pid_t newest = 0, oldest = 0;
	const char *pattern;
	const char *base;

	base = strrchr(argv[0], '/');
	base = base ? base + 1 : argv[0];
	pgrep_mode = strcmp(base, "pgrep") == 0;
	while ((ch = getopt(argc, argv, "fnoP:g:s:U:u:x")) != -1) {
		switch (ch) {
		case 'f': fflag = 1; break;
		case 'n': nflag = 1; break;
		case 'o': oflag = 1; break;
		case 'x': xflag = 1; break;
		case 'u': uflag = 1; uid = parse_uid(optarg); break;
		case 'U': Uflag = 1; uid = parse_uid(optarg); break;
		case 'g': gflag = 1; pgid = (pid_t)strtol(optarg, NULL, 10); break;
		case 'P': Pflag = 1; ppid = (pid_t)strtol(optarg, NULL, 10); break;
		case 's': break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc == 0)
		usage();
	pattern = argv[0];
	if (!pgrep_mode && pattern[0] == '-' && pattern[1] != '\0') {
		int n = signal_number(pattern + 1);

		if (n == -1)
			usage();
		sig = n;
		argc--;
		argv++;
		if (argc == 0)
			usage();
		pattern = argv[0];
	}
	for (;;) {
		if (sysctl(mib, 4, NULL, &size, NULL, 0) == -1)
			err(EX_OSERR, "sysctl");
		if ((procs = malloc(size)) == NULL)
			err(EX_OSERR, NULL);
		if (sysctl(mib, 4, procs, &size, NULL, 0) == 0)
			break;
		if (errno != ENOMEM)
			err(EX_OSERR, "sysctl");
		free(procs);
	}
	nproc = (int)(size / sizeof(*procs));
	for (kp = procs, i = 0; i < nproc; i++, kp++) {
		char *args = NULL;
		int hit;

		if (kp->kp_proc.p_pid == getpid())
			continue;
		if (kp->kp_proc.p_stat == 0)	/* empty slot */
			continue;
		if (uflag && kp->kp_eproc.e_ucred.cr_uid != uid)
			continue;
		if (Uflag && kp->kp_eproc.e_pcred.p_ruid != uid)
			continue;
		if (gflag && kp->kp_eproc.e_pgid != pgid)
			continue;
		if (Pflag && kp->kp_eproc.e_ppid != ppid)
			continue;
		if (fflag) {
			args = procargs(kp->kp_proc.p_pid);
			hit = args != NULL && matches(pattern, args);
			free(args);
		} else
			hit = matches(pattern, kp->kp_proc.p_comm);
		if (!hit)
			continue;
		matched++;
		if (nflag && kp->kp_proc.p_pid > newest)
			newest = kp->kp_proc.p_pid;
		if (oflag && (oldest == 0 || kp->kp_proc.p_pid < oldest))
			oldest = kp->kp_proc.p_pid;
		if (pgrep_mode && !nflag && !oflag)
			printf("%d\n", kp->kp_proc.p_pid);
		else if (!pgrep_mode && !nflag && !oflag)
			if (kill(kp->kp_proc.p_pid, sig) == -1 && errno != ESRCH)
				warn("kill %d", kp->kp_proc.p_pid);
	}
	if (nflag && newest != 0) {
		if (pgrep_mode)
			printf("%d\n", newest);
		else
			kill(newest, sig);
	}
	if (oflag && oldest != 0) {
		if (pgrep_mode)
			printf("%d\n", oldest);
		else
			kill(oldest, sig);
	}
	free(procs);
	return matched ? 0 : 1;
}

static void
usage(void)
{
	fprintf(stderr, "usage: pkill [-fno] [-signal] [-u user] [-P ppid] pattern\n");
	exit(EX_USAGE);
}
