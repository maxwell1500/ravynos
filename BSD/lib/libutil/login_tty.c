/* SPDX-License-Identifier: BSD-3-Clause */
/* FreeBSD's login_tty(3): make a descriptor the controlling terminal and
 * attach stdin/stdout/stderr to it.  launchctl uses it for single-user mode. */
#include <sys/types.h>

#include <errno.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

int
login_tty(int fd)
{
	if (setsid() == -1)
		return -1;
	if (ioctl(fd, TIOCSCTTY, NULL) == -1)
		return -1;
	if (dup2(fd, STDIN_FILENO) == -1 ||
	    dup2(fd, STDOUT_FILENO) == -1 ||
	    dup2(fd, STDERR_FILENO) == -1)
		return -1;
	if (fd > STDERR_FILENO)
		close(fd);
	return 0;
}
