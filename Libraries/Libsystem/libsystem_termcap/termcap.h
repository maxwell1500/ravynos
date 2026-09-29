/*-
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * termcap.h -- the classic termcap interface, for ravynOS.
 *
 * This header is installed into the SDK as <termcap.h>, which is the name a
 * program (BSD/lib/libedit's src/terminal.c among them) includes. It is
 * installed under that name deliberately; see README.md, "The header name".
 *
 * Nothing here is new. The entry points, their argument order, their return
 * values and the meaning of the PC/BC/... globals are the termcap interface
 * that every termcap consumer already assumes. What is new is the
 * implementation behind them, in termcap.c, which is original code written
 * for this tree -- see that file's provenance note and README.md.
 *
 * A program must NOT include this together with a curses or ncurses header:
 * those declare the same six functions with the same shapes, and the
 * duplication is the caller's to avoid.
 */

#ifndef	_LIBSYSTEM_TERMCAP_H
#define	_LIBSYSTEM_TERMCAP_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * The size of the buffer tgetent() is documented to be called with, and the
 * size of the buffer tgetstr() uses when the caller does not supply one.
 *
 * This is NOT a limit on tgetent(): it copies into the caller's buffer and
 * truncates rather than overflowing, so a smaller buffer is safe but loses
 * the tail of a long entry. It IS a hard limit for tgetstr()'s internal
 * buffer -- see README.md, "tgetstr and the caller's area".
 */
#define	TC_BUFSIZ	1024

/*
 * PC     the padding character, or '\0' when the current entry defines none.
 *        tputs() emits no padding at all when PC is '\0'; it still counts
 *        the padding owed so the caller learns the right affcnt.
 *
 * BC     the backspace sequence, as a string because it may be longer than
 *        one character. "\b" for every terminal described here.
 *
 * UP, HO, BO, EE   cursor-up, home-cursor, bold-on and exit-attribute-mode,
 *        or NULL when the current entry has no such capability. They are set
 *        by tgetent() and cleared by a tgetent() that finds no entry, so they
 *        never describe a previously-loaded terminal.
 *
 * All six are set only from the built-in entry tgetent() matched. There is no
 * file database, so nothing else can set them.
 */
extern int	 PC;
extern char	*BC;
extern char	*UP;
extern char	*HO;
extern char	*BO;
extern char	*EE;

/*
 * tgetent -- load the built-in entry named `name' into `bp'.
 *
 *      name == NULL   use $TERM
 *      returns  1     the entry was loaded; *bp holds it, NUL-terminated
 *             0     no entry for that terminal name
 *            -1     the termcap database could not be found or read
 *
 * This implementation has no file database -- see README.md -- so it never
 * returns -1. That is not a stub value: -1 means "I looked for a database
 * file and could not use it", and there is no file to look for. A caller that
 * tests `i <= 0' for "no editing available" is still correct.
 *
 * `bp' may be NULL, which loads the entry and discards the text but still
 * updates PC/BC/UP/... and the state tgetnum/tgetflag/tgetstr read.
 */
int	 tgetent(char *, const char *);

/*
 * tgetnum -- the integer value of a numeric capability, or -1 if the entry
 * has no such capability. -1 is also the honest answer for a capability the
 * entry does not define, and for one that exists but is not numeric.
 */
int	 tgetnum(const char *);

/*
 * tgetflag -- 1 if the entry has the capability, 0 if it does not.
 *
 * A boolean capability is present-and-true even when its value is the empty
 * string, which is how termcap spells "yes".
 */
int	 tgetflag(const char *);

/*
 * tgetstr -- the string value of a capability, or NULL if the entry has no
 * such capability.
 *
 * When `area' is non-NULL and *area is non-NULL, the value is copied there
 * and *area is advanced past it, so repeated calls fill one buffer. The
 * caller is responsible for that buffer being large enough; TC_BUFSIZ is
 * enough for every entry this component ships. When `area' is NULL or *area
 * is NULL, the value is copied into a TC_BUFSIZ static buffer that the next
 * tgetstr() call overwrites.
 */
char	*tgetstr(const char *, char **);

/*
 * tgoto -- substitute `col' and `row' into a parameterised capability and
 * strip its padding specifications.
 *
 *      returns  a pointer to a static buffer holding the result, valid
 *               until the next tgoto() call
 *      returns  NULL  if `cap' is NULL, or if it contains a conversion
 *                     outside the supported set -- see README.md, "tgoto"
 *
 * NULL means "do not emit this capability". It is never a plausible-looking
 * substitute for a conversion this component cannot translate.
 */
char	*tgoto(const char *, int, int);

/*
 * tputs -- write `str' to the terminal through `outc', expanding any
 * $<count> padding specifications against PC, and return the number of
 * padding characters still owed to the caller.
 *
 *      str == NULL  writes nothing and returns affcnt unchanged
 *
 * See README.md, "tputs and padding", for the exact return rule.
 */
int	 tputs(const char *, int, int (*)(int));

#ifdef __cplusplus
}
#endif

#endif	/* _LIBSYSTEM_TERMCAP_H */
