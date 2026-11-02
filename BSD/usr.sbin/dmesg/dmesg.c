/*
 * dmesg -- print the kernel message buffer.
 *
 * proc_info(PROC_INFO_CALL_KERNMSGBUF) is the same path Apple's dmesg uses;
 * the kernel returns the circular buffer already de-syslog'd and newline
 * terminated.  It is root-only (suser), which is correct for the kernel log.
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/syscall.h>

#ifndef PROC_INFO_CALL_KERNMSGBUF
#define PROC_INFO_CALL_KERNMSGBUF 0x4
#endif
#include <unistd.h>

int
main(void)
{
	char buffer[65536];
	/* On success the syscall return value is the byte count that
	 * log_dmesg() placed in retval; on failure it is -1 with errno. */
	int n = syscall(SYS_proc_info, PROC_INFO_CALL_KERNMSGBUF,
	    0, 0, (uint64_t)0, buffer, (uint32_t)sizeof(buffer));

	if (n < 0) {
		perror("dmesg");
		return 1;
	}
	if (n > 0 && write(STDOUT_FILENO, buffer, (size_t)n) < 0) {
		perror("dmesg: write");
		return 1;
	}
	return 0;
}
