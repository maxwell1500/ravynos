/*-
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * probe.c -- a static ravynOS program that touches every entry point this
 * component provides, so that tools/bootlab/link-static.sh is asked the
 * question "does a -nostdlib -static link of this resolve?" and answers it.
 *
 * It deliberately includes <termcap.h> with no -I of its own. In the target
 * build the only termcap.h on the include path is the one this component
 * installs into the ravynOS SDK, so a successful compile is also the proof
 * that the header was installed where libedit will look for it.
 *
 * Nothing here is a test; it exists to be linked.
 */

#include <termcap.h>

#include <stdio.h>

static int
sink(int c)
{
	return (c);
}

int
main(void)
{
	char buf[TC_BUFSIZ];
	char *area = buf;
	char *s;
	int n;

	if (tgetent(buf, "xterm") != 1)
		return (1);

	n = tgetnum("co") + tgetnum("li") + tgetnum("nosuchcap");
	n += tgetflag("am") + tgetflag("xn");

	s = tgetstr("ce", &area);
	s = tgetstr("up", area == NULL ? NULL : &area);
	s = tgetstr("nosuchcap", NULL);
	if (s != NULL)
		return (2);

	s = tgoto(tgetstr("DC", &area), 3, 3);
	if (s == NULL)
		return (3);

	n += tputs(s, 3, sink);
	n += tputs(NULL, 1, sink);
	n += (int)PC + (BC != NULL) + (UP != NULL) + (HO != NULL) +
	    (BO != NULL) + (EE != NULL);

	/*
	 * Something observable, so a run of this is not silent. `n' is the
	 * sum of every return value the calls above produced; it is printed
	 * rather than branched on, because the point of this file is to be
	 * LINKED, not to be an oracle.
	 */
	(void)printf("termcap probe: co=%d li=%d am=%d calls=%d\n",
	    tgetnum("co"), tgetnum("li"), tgetflag("am"), n);
	return (0);
}
