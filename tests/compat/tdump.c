/*
 * tdump -- per-thread state of a process, via proc_info(2).
 *
 * ps shows only the process state.  A process that is "R" but never makes
 * progress (and cannot be killed) has at least one thread stuck inside the
 * kernel; this prints every thread's run state, CPU time and name so the
 * stuck thread can be identified without a kernel debugger.
 *
 *   tdump <pid>
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/syscall.h>
#include <unistd.h>

/* bsd/sys/proc_info_private.h: PROC_INFO_CALL_PIDINFO */
#define PROC_INFO_CALL_PIDINFO 0x2

static int
call_proc_info(int pid, int flavor, uint64_t arg, void *buf, uint32_t size)
{
	int n = syscall(SYS_proc_info, PROC_INFO_CALL_PIDINFO, pid, flavor, arg,
	    buf, size);
	if (n < 0)
		return -1;
	return n;
}

int
main(int argc, char **argv)
{
	uint64_t tids[256];
	struct proc_threadinfo pth;
	int pid, n, count;

	if (argc != 2) {
		fprintf(stderr, "usage: tdump <pid>\n");
		return 2;
	}
	pid = atoi(argv[1]);

	n = call_proc_info(pid, PROC_PIDLISTTHREADS, 0, tids, sizeof(tids));
	if (n < 0) {
		perror("tdump: PROC_PIDLISTTHREADS");
		return 1;
	}
	count = n / (int)sizeof(uint64_t);
	printf("tdump: pid %d threads=%d\n", pid, count);
	for (int i = 0; i < count; i++) {
		memset(&pth, 0, sizeof(pth));
		if (call_proc_info(pid, PROC_PIDTHREADINFO, tids[i], &pth,
		    sizeof(pth)) < 0) {
			printf("  tid %llu: ERR %s\n",
			    (unsigned long long)tids[i], strerror(errno));
			continue;
		}
		printf("  tid %llu state=%d cpu=%d user=%llu sys=%llu pri=%d name=%s\n",
		    (unsigned long long)tids[i], pth.pth_run_state,
		    pth.pth_cpu_usage,
		    (unsigned long long)pth.pth_user_time,
		    (unsigned long long)pth.pth_system_time,
		    pth.pth_curpri,
		    pth.pth_name[0] ? pth.pth_name : "-");
	}
	return 0;
}
