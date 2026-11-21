/* SPDX-License-Identifier: BSD-2-Clause */
/* FreeBSD's cfmakesane(3): restore conventional "sane" terminal settings.
 * Darwin has cfmakeraw but no sane counterpart, and stty(1) prints and
 * applies the driver defaults through this. */
#include <sys/types.h>

#include <termios.h>
#include <unistd.h>

void
cfmakesane(struct termios *t)
{
	t->c_iflag = ICRNL | IXON;
	t->c_oflag = OPOST | ONLCR;
	t->c_cflag = (t->c_cflag & (CSIZE | CSTOPB | PARENB | PARODD | CLOCAL |
	    CREAD)) | CS8 | CREAD | HUPCL;
	t->c_lflag = ISIG | ICANON | ECHO | ECHOE | ECHOK | ECHOCTL | ECHOKE |
	    IEXTEN;
	t->c_cc[VEOF] = 4;	/* ^D */
	t->c_cc[VEOL] = _POSIX_VDISABLE;
	t->c_cc[VERASE] = 0x7f;
	t->c_cc[VINTR] = 3;	/* ^C */
	t->c_cc[VKILL] = 21;	/* ^U */
	t->c_cc[VQUIT] = 28;	/* ^\ */
	t->c_cc[VSUSP] = 26;	/* ^Z */
	t->c_cc[VSTART] = 17;	/* ^Q */
	t->c_cc[VSTOP] = 19;	/* ^S */
	t->c_cc[VMIN] = 1;
	t->c_cc[VTIME] = 0;
}
