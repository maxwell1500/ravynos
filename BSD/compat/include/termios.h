/* FreeBSD termios names that Darwin lacks.  VERASE2 is the second erase
 * character; Darwin's c_cc has no slot for it, so index 7 (unused there) is
 * used and the control character defaults to disabled. */
#ifndef _RAVYN_COMPAT_TERMIOS_H_
#define _RAVYN_COMPAT_TERMIOS_H_

#include_next <termios.h>

#ifndef VERASE2
#define VERASE2		7
#endif
#ifndef CERASE2
#define CERASE2		0x7f
#endif

/* FreeBSD hardware-flow-control flags.  Darwin's termios has no such bits and
 * the driver ignores them; zero keeps stty's flag tables compiling and the
 * settings displayable without claiming hardware support that does not exist. */
#ifndef CCTS_OFLOW
#define CCTS_OFLOW	0
#endif
#ifndef CDSR_OFLOW
#define CDSR_OFLOW	0
#endif
#ifndef CDTR_IFLOW
#define CDTR_IFLOW	0
#endif
#ifndef CRTS_IFLOW
#define CRTS_IFLOW	0
#endif
#ifndef CNO_RTSDTR
#define CNO_RTSDTR	0
#endif

/* Implemented in libutil (cfmakesane.c); declared in FreeBSD <termios.h>. */
void cfmakesane(struct termios *);

#endif
