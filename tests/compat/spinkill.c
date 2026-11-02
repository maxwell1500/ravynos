/*
 * spinkill -- prove that SIGKILL reaches a process spinning in userspace.
 *
 * A process that never makes a syscall only checks for signals when it
 * returns to user mode after an interrupt (the AST path).  If the kernel
 * misses that check, the process is unkillable until reboot, which is
 * exactly what a busy allocator loop in a large app looks like.  The
 * child here spins without syscalls; the parent must be able to kill it.
 */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

static void
timeout_handler(int sig)
{
	(void)sig;
	static const char msg[] = "FIXTURE spinkill rc=1 (child survived SIGKILL)\n";
	write(1, msg, sizeof(msg) - 1);
	_exit(1);
}

int
main(void)
{
	pid_t child;
	int status;

	child = fork();
	if (child < 0) {
		perror("spinkill: fork");
		printf("FIXTURE spinkill rc=1\n");
		return 1;
	}
	if (child == 0) {
		volatile unsigned long x = 0;
		for (;;) {
			x = x * 1103515245UL + 12345UL; /* no syscalls */
		}
	}

	sleep(1);
	kill(child, SIGKILL);

	signal(SIGALRM, timeout_handler);
	alarm(5);
	if (waitpid(child, &status, 0) < 0) {
		perror("spinkill: waitpid");
		printf("FIXTURE spinkill rc=1\n");
		return 1;
	}
	alarm(0);

	if (WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL) {
		printf("FIXTURE spinkill rc=0\n");
		return 0;
	}
	printf("FIXTURE spinkill rc=1 (status=0x%x)\n", status);
	return 1;
}
