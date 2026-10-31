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
 * -t arms alarm(3) before exec, so a process that hangs in startup is
 * terminated by SIGALRM and the kernel prints its user stack.  The shell's
 * kill builtin is not reliable in this image, and a watchdog that waits
 * forever never reports anything.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int
main(int argc, char *argv[])
{
	if (argc >= 2 && strcmp(argv[1], "-t") == 0) {
		if (argc < 3) {
			fprintf(stderr, "usage: runas [-t seconds] uid gid program [args...]\n");
			return 2;
		}
		alarm((unsigned)atoi(argv[2]));
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
	execv(argv[3], &argv[3]);
	perror("runas: exec");
	return 1;
}
