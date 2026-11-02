/*
 * runas -- drop to a uid/gid and exec a program.
 *
 * Firefox refuses to start when getuid() == 0 and $HOME is not owned by root
 * ("Running Firefox as root in a regular user's session is not supported").
 * launchd's UserName key does not drop privileges in this tree yet, so the
 * test job uses this to run the browser as the ravyn user, which is also what
 * a normal session does.
 *
 *   runas [-t seconds] <uid> <gid> <program> [args...]
 *
 * -t forks a watcher that SIGKILLs the exec'd program after the timeout,
 *   so a process that hangs in startup is terminated even if it installs
 *   its own signal handlers (alarm/SIGALRM did not work: Gecko catches or
 *   masks it).  The shell's kill builtin is not reliable in this image, and
 *   a watchdog that waits forever never reports anything.
 */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int
main(int argc, char *argv[])
{
	if (argc >= 2 && strcmp(argv[1], "-t") == 0) {
		int secs;
		pid_t watcher;
		if (argc < 3) {
			fprintf(stderr, "usage: runas [-t seconds] uid gid program [args...]\n");
			return 2;
		}
		secs = atoi(argv[2]);
		watcher = fork();
		if (watcher < 0) {
			perror("runas: fork");
			return 1;
		}
		if (watcher == 0) {
			/* root watcher: survives the parent's setuid and the
			 * exec'd program's signal masks; SIGKILL cannot be caught */
			pid_t target = getppid();
			fprintf(stderr, "[runas] watchdog armed: self=%d target=%d secs=%d\n",
			    (int)getpid(), (int)target, secs);
			sleep(secs > 0 ? secs : 1);
			fprintf(stderr, "[runas] watchdog: target %d alive=%d\n",
			    (int)target, kill(target, 0) == 0 ? 1 : 0);
			/* SIGABRT makes the kernel print the stuck process's
			 * user stack (CORPSE frames); SIGKILL then guarantees
			 * the job completes. */
			fprintf(stderr, "[runas] watchdog: SIGABRT pid %d -> %d\n",
			    (int)target, kill(target, SIGABRT));
			sleep(2);
			fprintf(stderr, "[runas] watchdog: SIGKILL pid %d -> %d errno=%d\n",
			    (int)target, kill(target, SIGKILL), errno);
			_exit(0);
		}
		argv += 2;
		argc -= 2;
	}

	if (argc < 4) {
		fprintf(stderr, "usage: runas [-t seconds] uid gid program [args...]\n");
		return 2;
	}

	uid_t uid = (uid_t)atoi(argv[1]);
	gid_t gid = (gid_t)atoi(argv[2]);

	if (setgid(gid) != 0) {
		perror("runas: setgid");
		return 1;
	}
	if (setuid(uid) != 0) {
		perror("runas: setuid");
		return 1;
	}
	fprintf(stderr, "[runas] pid %d exec %s\n", (int)getpid(), argv[3]);
	execv(argv[3], &argv[3]);
	perror("runas: exec");
	return 1;
}
