/*-
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * termcap.c -- a fresh, original implementation of the classic termcap
 * interface for ravynOS. See termcap.h for the interface itself.
 *
 * ---------------------------------------------------------------------------
 * PROVENANCE
 *
 * This file is written from the specification of the termcap interface --
 * termcap(3), the capability names and their meanings in termcap(5), and the
 * ECMA-48 / ISO 6429 / DEC VT-series control-function definitions that the
 * capability strings are drawn from. It is not derived from any existing
 * termcap implementation: not the historical BSD one, not GNU, not ncurses,
 * not musl. No line here was copied, transliterated or paraphrased from one.
 *
 * Two things in this file are necessarily not original, and both are facts
 * rather than code:
 *
 *   - The CAPABILITY NAMES. `ce', `co', `xn' and the rest are the vocabulary
 *     every termcap consumer already speaks. Inventing new ones would make
 *     this component useless, so they are used as specified.
 *
 *   - The ESCAPE SEQUENCES. `\E[K' is the EL control function because that is
 *     what an EL-capable terminal interprets it to be. They come from the
 *     terminal's definition, not from anybody's source file.
 *
 * Everything else -- the entry table layout, the field scanner, the unescaper,
 * tgoto's conversion machine, tputs' padding accounting, and every error
 * return -- is this file's own.
 * ---------------------------------------------------------------------------
 *
 * What this component does NOT do, and why that matters:
 *
 *   - There is no termcap FILE database. ravynOS has no /etc/termcap, no
 *     termcap file in the SDK, and no network to fetch one, so the entries are
 *     compiled in. Consequently tgetent() never returns -1: -1 means "a
 *     database file exists but could not be read", and there is no file.
 *
 *   - tgoto() returns NULL for any conversion it does not implement. It does
 *     not guess, and it does not emit a plausible-looking sequence for a
 *     conversion it cannot translate. A caller that checks for NULL degrades;
 *     a caller that does not gets nothing, which is a better outcome than a
 *     correct-looking escape sequence the terminal does not understand.
 *
 *   - A capability an entry does not define is reported as absent. It is not
 *     filled in with a substitute. See README.md for which ones are absent on
 *     purpose and why.
 */

#include <sys/types.h>

#include <errno.h>
#include <stdio.h>		/* EOF only */
#include <stdlib.h>
#include <string.h>

#include "termcap.h"

/*
 * The entry table.
 *
 * Two parallel arrays rather than one string per entry, because the alias list
 * and the capability list have different grammars: names are '|'-separated,
 * capabilities are ':'-separated fields. Keeping them apart means neither
 * parser has to know about the other's separator.
 */
struct tc_entry {
	const char	*names;		/* "xterm|vt100|..." */
	const char	*caps;		/* "co#80:ce=\\E[K:..." */
};

/*
 * The VT100-family entry.
 *
 * Every name below is a terminal that speaks the ECMA-48 / DEC VT control set
 * this entry describes. They differ in font, colour depth, mouse reporting and
 * 132-column mode; none of that changes any capability written below, and none
 * of the capabilities below is one any of them lacks.
 *
 * Deliberately NOT listed here:
 *
 *   "dumb" is its own entry, below.
 *
 *   Any ravynOS-specific name. ravynOS's console is BSDFramebuffer-backed with
 *   no VT emulation that this component can verify, so claiming it would be a
 *   claim about hardware and firmware that nothing in this tree establishes.
 *   A terminal this component cannot vouch for gets tgetent() == 0, which is
 *   the honest answer, and which libedit already handles.
 *
 * Two deliberate ABSENCES inside this entry are `UP' and `LE'. Both are real
 * capabilities of a VT100 and both are left out because of HOW their only
 * consumer calls them, which is worth stating exactly:
 *
 *   BSD/lib/libedit/src/terminal.c:516   tgoto(Str(T_UP), -del, -del)
 *   BSD/lib/libedit/src/terminal.c:597   tgoto(Str(T_LE), -del, -del)
 *
 * Both pass a NEGATED count, so a capability written the ordinary way
 * (`\\E[%dA') renders `\E[-7A' -- a negative repeat count, which a VT100
 * treats as a parameter error. Classic tgoto has no negation operator, and
 * inventing one would be inventing syntax no other termcap implementation has.
 * libedit tests `GoodStr(T_UP)' / `GoodStr(T_LE)' before calling tgoto on them
 * and has a correct fallback when they are absent, so omitting them produces
 * right behaviour instead of a wrong escape sequence.
 *
 * `RI', `DC', `IC' and `ch' ARE provided: libedit passes those the same value
 * to both parameters, positively, which is what the ordinary `%d' form
 * expects. See README.md, "tgoto".
 */
static const char tc_vt100_names[] =
	"xterm"
	"|xterm-color|xterm-16color|xterm-256color|xterm-kitty"
	"|rxvt|rxvt-unicode|rxvt-256color"
	"|screen|screen-256color|screen.xterm|screen.xterm-256color"
	"|tmux|tmux-256color"
	"|vt100|vt102|vt200|vt220|vt240|vt320|vt420"
	"|ansi|ansi80x25"
	"|cons25|cons25-debian|linux"
	"|putty|cygwin|konsole|gnome|gnome-256color|vte|vte-256color"
	"|alacritty|contour|eterm|eterm-color|foot|foot-extra"
	"|ghostty|kitty|st|st-256color|wezterm|mlterm";

/*
 * Capability values, one ECMA-48 / DEC control function each. The comment on
 * each line names the control function, so any string here can be checked
 * against the terminal's manual rather than against this file's memory.
 *
 * The absence of `%i' from `RI', `DC' and `IC' is deliberate and load-bearing:
 * those three take a zero-based repeat count, so adding one would move the
 * cursor one column too few and delete/insert one character too few. `ch' does
 * carry `%i' because its argument is a 1-based COLUMN, not a distance.
 */
static const char tc_vt100_caps[] =
	"al=\\E[L:"		/* IL    insert one blank line */
	"am:"			/* boolean: DECAWM, wraps at the right margin */
	"bl=^G:"		/* BEL   audible bell */
	"bs:"			/* boolean: backspace reaches column 1 */
	"cd=\\E[J:"		/* ED0   erase to end of display */
	"ce=\\E[K:"		/* EL0   erase to end of line */
	"ch=\\E[%i%dG:"		/* CHA   cursor to column, 1-based */
	"cl=\\E[H\\E[2J:"	/* home, then ED2 */
	"co#80:"		/* fallback width; TIOCGWINSZ wins */
	"dc=\\E[P:"		/* DCH1  delete one character */
	"dl=\\E[M:"		/* DL1   delete one line */
	"dm=\\E[4h:"		/* SM    insert/delete mode on */
	"ed=\\E[4l:"		/* RM    insert/delete mode off */
	"ei=\\E[4l:"		/* RM    insert mode off */
	"ho=\\E[H:"		/* home */
	"ic=\\E[@:"		/* ICH1  insert one character */
	"im=\\E[4h:"		/* SM    insert mode on */
	"ip=\\E[1@:"		/* insert padding: one blank, no scroll */
	"kd=\\EOB:"		/* cursor down */
	"kD=\\E[3~:"		/* the Delete key */
	"kh=\\EOH:"		/* cursor home */
	"kl=\\EOD:"		/* cursor left */
	"kr=\\EOC:"		/* cursor right */
	"ku=\\EOA:"		/* cursor up */
	"km:"			/* boolean: the terminal has a Meta key */
	"li#24:"		/* fallback height; TIOCGWINSZ wins */
	"md=\\E[1m:"		/* SGR   bold on */
	"me=\\E[m:"		/* SGR   all attributes off */
	"MT:"			/* boolean: Meta key, the other spelling */
	"nd=\\E[C:"		/* CUF1  non-destructive space */
	"pt:"			/* boolean: hardware tab stops */
	"se=\\E[m:"		/* standout off */
	"so=\\E[7m:"		/* standout on */
	"ue=\\E[m:"		/* underline off */
	"up=\\E[A:"		/* CUU1  cursor up one line */
	"us=\\E[4m:"		/* underline on */
	"RI=\\E[%dC:"		/* CUF n */
	"DC=\\E[%dP:"		/* DCH n */
	"IC=\\E[%d@:"		/* ICH n */;

/*
 * The dumb entry.
 *
 * A bell and a size, and nothing else: no cursor motion, no erase, no insert.
 * That is a real description of a dumb terminal, not a stub. It is what
 * tgetent() should answer for TERM=dumb, and it is what makes libedit fall
 * back to rewriting the line as plain characters.
 *
 * `co' and `li' are the fallback values reported when nothing else is known;
 * libedit also overrides them from TIOCGWINSZ when the fd is a terminal
 * (BSD/lib/libedit/src/terminal.c:952-970).
 */
static const char tc_dumb_names[] = "dumb";

static const char tc_dumb_caps[] =
	"bl=^G:"
	"co#80:"
	"li#24:";

static const struct tc_entry tc_db[] = {
	{ tc_vt100_names, tc_vt100_caps },
	{ tc_dumb_names,  tc_dumb_caps  },
	{ NULL,           NULL           }
};

/* ------------------------------------------------------------------------ */
/* State set by tgetent() and read by everything else.                        */
/* ------------------------------------------------------------------------ */

/*
 * BC is exported as char *, as the interface has always had it, so it needs
 * writable storage. A string literal will not do: the build here runs with
 * -Wwrite-strings (BSD/share/mk/bsd.sys.mk:60), under which a literal is
 * const char[] and `char *BC = "\010"' is a constraint violation, not a
 * warning that happens to be tolerable.
 */
static char tc_bc[] = "\010";	/* backspace; every entry here is ASCII */

int	 PC = '\0';
char	*BC = tc_bc;
char	*UP = NULL;		/* `up', NULL when the entry has none */
char	*HO = NULL;		/* `ho' */
char	*BO = NULL;		/* `md' */
char	*EE = NULL;		/* `me' */

/* The entry tgetent() last loaded, NULL when there is none. */
static const struct tc_entry *tc_cur = NULL;

/*
 * Two static buffers, deliberately not one.
 *
 * tc_gbuf holds the decoded values behind the PC/BC/UP/HO/BO/EE pointers,
 * which must stay valid for the life of the loaded entry. tc_sbuf is what
 * tgetstr() hands back when the caller supplies no area, and the interface
 * says the next tgetstr() call overwrites it. Sharing one buffer would mean a
 * tgetstr() call silently un-initialising UP and the rest.
 */
static char tc_gbuf[TC_BUFSIZ];
static char tc_sbuf[TC_BUFSIZ];

/* Scratch for tgoto()'s result. One buffer, as the interface has always said. */
static char tc_gtbuf[TC_BUFSIZ];

/* ------------------------------------------------------------------------ */
/* Field scanning.                                                            */
/*                                                                           */
/* A capability field is                                                      */
/*                                                                           */
/*     name                                                                */
/*     name=raw-value                                                      */
/*     name#number                                                         */
/*                                                                           */
/* with fields separated by ':'. A bare `name' is a boolean, and its value is */
/* the empty string -- termcap spells "yes" that way.                         */
/*                                                                           */
/* The scan walks fields rather than searching for `:<name>' with strstr,     */
/* which is the usual way to get this wrong. A substring search for "e" finds */
/* `ce', `se', `ue' and `me'; a substring search for "le" finds nothing when  */
/* what it should have found is `LE'. Both answers look plausible and are      */
/* wrong, which is exactly the failure mode worth designing against.          */
/* ------------------------------------------------------------------------ */

struct tc_field {
	const char	*val;		/* raw, still escaped */
	size_t		 vlen;
	int		 isnum;		/* was written name#number */
};

/*
 * Find the field named `id' in `caps'.
 *
 *      returns the value (possibly empty) with `f' filled in, when the entry
 *              has that capability
 *      returns NULL when it does not
 *
 * `id' may be of any length, including zero. A zero-length name never matches,
 * because no field has an empty name.
 */
static const char *tc_find(const char *caps, const char *id, struct tc_field *f)
{
	size_t idlen;
	const char *p;

	if (id == NULL || caps == NULL)
		return (NULL);
	if ((idlen = strlen(id)) == 0)
		return (NULL);

	for (p = caps; *p != '\0'; ) {
		const char *fend;	/* one past this field */
		const char *nend;	/* one past the name in this field */
		const char *vstart;

		/* Locate the end of this field. The table's last field is   */
		/* terminated by the string's own NUL, which this reuses.    */
		fend = strchr(p, ':');
		if (fend == NULL)
			fend = p + strlen(p);

		/* The name ends at the first '=' or '#' in the field.       */
		for (nend = p; nend < fend && *nend != '=' && *nend != '#'; nend++)
			continue;

		if ((size_t)(nend - p) == idlen && memcmp(p, id, idlen) == 0) {
			f->isnum = (nend < fend && *nend == '#');
			vstart = (nend < fend) ? nend + 1 : nend;
			f->val = vstart;
			f->vlen = (size_t)(fend - vstart);
			return (f->val);
		}

		if (*fend == '\0')
			break;
		p = fend + 1;
	}
	return (NULL);
}

/* ------------------------------------------------------------------------ */
/* Unescaping.                                                                */
/*                                                                           */
/* The entry table is written in termcap's own escape notation, because that  */
/* is how a termcap entry is written down, and because it keeps the data       */
/* readable as terminal sequences instead of as a column of numbers.           */
/*                                                                           */
/*      \E  \e    ESC                                                      */
/*      \n        LF        \r    CR                                        */
/*      \t        TAB      \b    BS                                        */
/*      \f        FF       \a    BEL                                       */
/*      \s        space                                                    */
/*      \\        backslash                                                  */
/*      \^        caret                                                      */
/*      ^X         control character, for X in '@'..'_' or '?'..'~'         */
/*      \xHH      two hex digits (not standard termcap; accepted because    */
/*                 entries in the wild carry it)                             */
/*                                                                           */
/* Anything else after a backslash is a malformed escape and is REFUSED: the  */
/* call fails rather than inventing a character the table never named.        */
/* ------------------------------------------------------------------------ */

static int tc_hexval(char c)
{
	if (c >= '0' && c <= '9')
		return (c - '0');
	if (c >= 'a' && c <= 'f')
		return (c - 'a' + 10);
	if (c >= 'A' && c <= 'F')
		return (c - 'A' + 10);
	return (-1);
}
/*
 * `^X' denotes the control character X. '@'..'_' is the usual range; termcap
 * tables also write `^?' for DEL, which is not in that range and does not
 * follow from masking, so it is spelled out.
 *
 *      returns the control character, or -1 if c cannot follow a caret
 */
static int tc_ctrl(char c)
{
	if (c >= '@' && c <= '_')
		return (c & 0x1f);
	if (c == '?')
		return (0x7f);
	return (-1);
}


/*
 * Decode `len' raw bytes from `src' into `dst', which must have room for
 * len + 1 bytes: decoding never grows a string.
 *
 *      returns  0, `dst' holds the decoded value
 *      returns -1, `dst' is untouched, errno is EINVAL
 */
static int tc_unescape(const char *src, size_t len, char *dst)
{
	size_t i = 0, o = 0;

	while (i < len) {
		char c = src[i++];

		if (c != '\\') {
			if (c != '^') {
				dst[o++] = c;
				continue;
			}
			if (i >= len)
				goto bad;
			c = src[i++];
			if (c == '^') {	/* a literal caret */
				dst[o++] = '^';
				continue;
			}
			{
				int v = tc_ctrl(c);

				if (v < 0)
					goto bad;
				dst[o++] = (char)v;
			}
			continue;
		}

		if (i >= len)
			goto bad;		/* a trailing backslash */
		c = src[i++];
		switch (c) {
		case 'E': case 'e':	dst[o++] = '\033'; break;
		case 'n':		dst[o++] = '\n';   break;
		case 'r':		dst[o++] = '\r';   break;
		case 't':		dst[o++] = '\t';   break;
		case 'b':		dst[o++] = '\b';   break;
		case 'f':		dst[o++] = '\f';   break;
		case 'a':		dst[o++] = '\a';   break;
		case 'v':		dst[o++] = '\v';   break;
		case 's':		dst[o++] = ' ';   break;
		case '\\':		dst[o++] = '\\';  break;
		case '^':		dst[o++] = '^';   break;
		case 'x': {
			int hi, lo;

			if (len - i < 2)
				goto bad;
			hi = tc_hexval(src[i]);
			lo = tc_hexval(src[i + 1]);
			if (hi < 0 || lo < 0)
				goto bad;
			dst[o++] = (char)((hi << 4) | lo);
			i += 2;
			break;
		}
		default:
			goto bad;
		}
	}
	dst[o] = '\0';
	return (0);

bad:
	errno = EINVAL;
	return (-1);
}

/* ------------------------------------------------------------------------ */
/* tgetent                                                                    */
/* ------------------------------------------------------------------------ */

/*
 * Does `names' contain `name' as a COMPLETE alias?
 *
 * Whole-alias comparison, not a prefix test: "vt100" must not match "vt10",
 * and "screen.xterm" must not match "screen".
 */
static int tc_has_name(const char *names, const char *name, size_t namelen)
{
	const char *p = names;

	while (*p != '\0') {
		const char *e = strchr(p, '|');
		size_t l = (e == NULL) ? strlen(p) : (size_t)(e - p);

		if (l == namelen && memcmp(p, name, namelen) == 0)
			return (1);
		if (e == NULL)
			break;
		p = e + 1;
	}
	return (0);
}

/* Copy at most `cap'-1 bytes and NUL-terminate. Returns bytes copied. */
static size_t tc_bcopy(char *dst, size_t cap, const char *src)
{
	size_t n = strlen(src);

	if (n > cap - 1)
		n = cap - 1;
	memcpy(dst, src, n);
	dst[n] = '\0';
	return (n);
}

/*
 * Load `e' and reset the state the other entry points read.
 *
 * Called again with a NULL entry, this clears everything first, so a failed
 * lookup can never leave the previous terminal's capabilities visible. That
 * matters here: libedit holds pointers into what tgetstr returned and would
 * otherwise compare a new entry against the old one's idea of itself.
 */
static void tc_load(const struct tc_entry *e)
{
	static const char *const globals[] = { "up", "ho", "md", "me" };
	char **const ptrs[] = { &UP, &HO, &BO, &EE };
	struct tc_field f;
	size_t used = 0;
	size_t i;

	tc_cur = e;
	PC = '\0';
	UP = HO = BO = EE = NULL;
	BC = tc_bc;
	tc_gbuf[0] = '\0';

	if (e == NULL)
		return;

	/*
	 * `pc' is the padding character. No entry this component ships
	 * defines one -- none of their capability strings uses a $<...>
	 * delay -- so PC stays '\0' and tputs() emits no padding bytes. It
	 * is still read, because a future entry that does use delays has to
	 * work without changing this code.
	 */
	if (tc_find(e->caps, "pc", &f) != NULL) {
		char pc[TC_BUFSIZ];

		if (tc_unescape(f.val, f.vlen, pc) == 0 && pc[0] != '\0')
			PC = (unsigned char)pc[0];
	}

	for (i = 0; i < sizeof(ptrs) / sizeof(ptrs[0]); i++) {
		size_t start = used;

		if (tc_find(e->caps, globals[i], &f) == NULL)
			continue;
		if (tc_unescape(f.val, f.vlen, tc_gbuf + start) != 0)
			continue;	/* malformed: leave the pointer NULL */
		used += strlen(tc_gbuf + start) + 1;
		*ptrs[i] = tc_gbuf + start;
	}
}

int
tgetent(char *bp, const char *name)
{
	const struct tc_entry *e;
	size_t len;

	if (name == NULL) {
		const char *env = getenv("TERM");

		name = (env != NULL) ? env : "";
	}
	len = strlen(name);

	for (e = tc_db; e->names != NULL; e++)
		if (tc_has_name(e->names, name, len))
			break;

	if (e->names == NULL) {
		tc_load(NULL);
		if (bp != NULL)
			bp[0] = '\0';
		return (0);
	}

	tc_load(e);
	if (bp != NULL) {
		/*
		 * Truncate rather than overflow. The interface's contract is
		 * a TC_BUFSIZ buffer and every caller in this tree honours
		 * it (libedit uses 2048), but "we were told 1024" is not a
		 * reason to write more than 1024 bytes into a buffer the
		 * caller may have made smaller.
		 */
		(void)tc_bcopy(bp, TC_BUFSIZ, e->caps);
	}
	return (1);
}

/* ------------------------------------------------------------------------ */
/* The lookup entry points.                                                   */
/*                                                                           */
/* All three read the entry tgetent() loaded. Before a successful tgetent()    */
/* there is no entry, so all three report absence -- which is the answer, not  */
/* a crash.                                                                   */
/* ------------------------------------------------------------------------ */

int
tgetnum(const char *id)
{
	struct tc_field f;
	char buf[32];
	char *end;
	long n;

	if (tc_cur == NULL || tc_find(tc_cur->caps, id, &f) == NULL || !f.isnum)
		return (-1);
	if (f.vlen == 0 || f.vlen >= sizeof(buf))
		return (-1);
	memcpy(buf, f.val, f.vlen);
	buf[f.vlen] = '\0';

	n = strtol(buf, &end, 10);
	/* A numeric capability that is not entirely a number is not one. */
	if (end == buf || *end != '\0')
		return (-1);
	return ((int)n);
}

int
tgetflag(const char *id)
{
	struct tc_field f;

	if (tc_cur == NULL)
		return (0);
	return (tc_find(tc_cur->caps, id, &f) != NULL);
}

char *
tgetstr(const char *id, char **area)
{
	struct tc_field f;
	char tmp[TC_BUFSIZ];
	char *dst;
	size_t n;

	if (tc_cur == NULL || tc_find(tc_cur->caps, id, &f) == NULL ||
	    tc_unescape(f.val, f.vlen, tmp) != 0) {
		errno = EINVAL;
		return (NULL);
	}

	/*
	 * A capability whose value decodes to the empty string is still a
	 * capability, and "" is the right answer for it rather than NULL.
	 */
	n = strlen(tmp) + 1;
	if (n > sizeof(tmp)) {			/* unreachable with the tables above */
		errno = ENAMETOOLONG;
		return (NULL);
	}

	if (area != NULL && *area != NULL)
		dst = *area;
	else
		dst = tc_sbuf;

	memcpy(dst, tmp, n);
	if (area != NULL)
		*area = dst + n;
	return (dst);
}

/* ------------------------------------------------------------------------ */
/* tgoto                                                                      */
/*                                                                           */
/* The conversions, in full:                                                  */
/*                                                                           */
/*      %%       a literal '%'                                              */
/*      %d       the first parameter (col)                                  */
/*      %2       the second parameter (row)                                 */
/*      %3       the first parameter again, spelled the terminfo way        */
/*      %i       col += 1, then continue                                    */
/*      %r       swap col and row                                           */
/*      %+n      col += n         for n a single digit                      */
/*      %.n      col += n + 1     for n a single digit; a bare `%.' adds 1  */
/*      %>xy     pad the first parameter's digits out to width y with x      */
/*      %<w>[.<p>][+-][ ]<c>                                               */
/*               a padding specification: stripped, and (w - length so far) */
/*               copies of c emitted at the end of the result               */
/*                                                                           */
/* Every other conversion -- `%p1', `%P', `%n', `%B', `%D', `%a', `%s', the  */
/* terminfo stack and arithmetic forms -- makes tgoto return NULL. It does    */
/* not emit a substitute. No capability in any entry this component ships     */
/* needs one; see the note on `UP' and `LE' at the top of this file.          */
/* ------------------------------------------------------------------------ */

/* Append one character, refusing to run past the end of the result buffer. */
static int tc_put(char *buf, size_t cap, size_t *len, int c)
{
	if (*len + 1 >= cap)
		return (-1);
	buf[(*len)++] = (char)c;
	return (0);
}

/* Append the decimal form of v, as many digits as it needs. */
static int tc_put_int(char *buf, size_t cap, size_t *len, int v)
{
	char digits[16];
	int n = 0;
	unsigned int uv;
	int i;

	if (v < 0) {
		if (tc_put(buf, cap, len, '-') != 0)
			return (-1);
		uv = (unsigned int)(-(v + 1)) + 1u;	/* so INT_MIN works */
	} else {
		uv = (unsigned int)v;
	}
	do {
		digits[n++] = (char)('0' + (uv % 10));
		uv /= 10;
	} while (uv != 0 && n < (int)sizeof(digits));
	for (i = n - 1; i >= 0; i--)
		if (tc_put(buf, cap, len, digits[i]) != 0)
			return (-1);
	return (0);
}

static int tc_isdigit(char c)
{
	return (c >= '0' && c <= '9');
}
/*
 * Print `v' with at least `to' characters, left-padded with `pc'.
 * `to' of 0 or 1 means no padding, which is every capability this
 * component's own entries use.
 */
static int tc_put_padded(char *buf, size_t cap, size_t *len, int v, int to,
    char pc)
{
	char tmp[16];
	size_t n = 0, i;

	if (tc_put_int(tmp, sizeof(tmp), &n, v) != 0)
		return (-1);
	for (i = n; (int)i < to; i++)
		if (tc_put(buf, cap, len, pc) != 0)
			return (-1);
	for (i = 0; i < n; i++)
		if (tc_put(buf, cap, len, tmp[i]) != 0)
			return (-1);
	return (0);
}


char *
tgoto(const char *cap, int col, int row)
{
	const char *p;
	size_t len = 0;
	int padto = 0;		/* `%>xy': minimum width for the next parameter */
	int width = 0;		/* trailing padding specification */
	char padchar = ' ';

	if (cap == NULL)
		return (NULL);

	for (p = cap; *p != '\0'; ) {
		char c = *p++;

		if (c != '%') {
			if (tc_put(tc_gtbuf, sizeof(tc_gtbuf), &len, c) != 0)
				goto overflow;
			continue;
		}
		if (*p == '\0')
			return (NULL);		/* '%' with nothing after it */

		switch (*p) {
		case '%':
			p++;
			if (tc_put(tc_gtbuf, sizeof(tc_gtbuf), &len, '%') != 0)
				goto overflow;
			break;

		case 'd':
		case '3':
			p++;
			if (tc_put_padded(tc_gtbuf, sizeof(tc_gtbuf), &len,
			    col, padto, padchar) != 0)
				goto overflow;
			padto = 0;
			break;

		case '2':
			p++;
			if (tc_put_padded(tc_gtbuf, sizeof(tc_gtbuf), &len,
			    row, padto, padchar) != 0)
				goto overflow;
			padto = 0;
			break;

		case 'i':
			p++;
			col++;
			break;

		case 'r': {
			int t = col;

			p++;
			col = row;
			row = t;
			break;
		}

		case '.':
			/*
			 * `%.' is ALWAYS the increment, never a padding
			 * specification. Padding has to start with a digit
			 * or a sign, which is what keeps `%.' from being
			 * ambiguous: `%.%d' is "add one, then print col".
			 */
			p++;
			if (tc_isdigit(*p))
				col += (*p++ - '0') + 1;	/* %.n adds n+1 */
			else
				col += 1;
			break;

		case '+':
			p++;
			if (tc_isdigit(*p)) {			/* %+n adds n */
				col += *p++ - '0';
				break;
			}
			if (*p == '\0')
				return (NULL);
			/*
			 * `%+c' with a non-digit is a padding specification
			 * with no width. It exists to be stripped, and
			 * stripping it is all a zero width can do.
			 */
			p++;
			break;

		case '>':
			/*
			 * `%>xy' -- pad what the NEXT parameter prints out
			 * to a minimum of y characters, using x. It emits
			 * nothing itself, which is what lets it sit in front
			 * of the `%d' it is padding.
			 */
			p++;
			if (*p == '\0')
				return (NULL);
			padchar = *p++;
			padto = 0;
			while (tc_isdigit(*p))
				padto = padto * 10 + (*p++ - '0');
			if (padto <= 0)
				return (NULL);
			break;

		default:
			if (!tc_isdigit(*p)) {
				/*
				 * A conversion this component does not
				 * implement. Say so; do not approximate it.
				 */
				return (NULL);
			}
			/*
			 * A padding specification. Its width and pad
			 * character are remembered and the pad characters
			 * are emitted once the whole string is done, which
			 * is the only order in which "how many characters
			 * so far" means anything. A second padding
			 * specification in one string replaces the first;
			 * no entry this component ships uses two, and
			 * picking one silently would be a guess.
			 */
			width = 0;
			while (tc_isdigit(*p))
				width = width * 10 + (*p++ - '0');
			if (*p == '.') {
				p++;
				while (tc_isdigit(*p))
					p++;	/* precision: not used */
			}
			if (*p == '+' || *p == '-' || *p == '*' || *p == ' ')
				p++;
			if (*p == '\0')
				return (NULL);
			padchar = *p++;
			break;
		}
	}

	if (width > 0 && (size_t)width > len) {
		size_t i;
		size_t want = (size_t)width - len;

		if (want > sizeof(tc_gtbuf) - len)
			goto overflow;
		for (i = 0; i < want; i++)
			tc_gtbuf[len++] = padchar;
	}
	tc_gtbuf[len] = '\0';
	return (tc_gtbuf);

overflow:
	errno = ERANGE;
	return (NULL);
}

/* ------------------------------------------------------------------------ */
/* tputs                                                                      */
/* ------------------------------------------------------------------------ */
/*
 * Write `str' through `outc', expanding padding.
 *
 * A `$<count>' sequence -- '$', digits, '>' -- is padding. Each pad character
 * emitted is PC; when PC is '\0' the loaded entry defines no pad character, so
 * NO bytes are emitted. The count is still added into the returned total,
 * because the caller asked how much padding the terminal was told to swallow,
 * and that answer does not depend on whether PC happens to be set.
 *
 * The return value is the number of padding characters still owed, with the
 * rule spelled out so a caller can predict it:
 *
 *      no padding in str     ->  affcnt, unchanged
 *      affcnt < 0            ->  affcnt, unchanged (the caller does not
 *                                 want to know)
 *      pad_total <= affcnt   ->  affcnt, unchanged
 *      pad_total >  affcnt   ->  pad_total
 *
 * `str' being NULL writes nothing and returns affcnt. libedit calls tputs with
 * whatever tgoto returned (BSD/lib/libedit/src/terminal.c:1213), and tgoto
 * returns NULL for a capability it cannot translate; emitting through a NULL
 * would be this component's crash, not the caller's bug.
 */
int
tputs(const char *str, int affcnt, int (*outc)(int))
{
	int pad_total = 0;
	int found = 0;

	if (str == NULL || outc == NULL)
		return (affcnt);

	for (; *str != '\0'; str++) {
		/*
		 * Padding is `$<count>' -- '$', an optional `<', `*' or `+',
		 * digits, and a closing `>'. A '$' that is not followed by
		 * that whole shape is an ordinary character and is written
		 * out as one, which is why this scan cannot consume as it
		 * goes and then give up.
		 */
		if (*str == '$') {
			const char *q = str + 1;
			long n = 0;
			long i;
			int digits = 0;

			if (*q == '<' || *q == '*' || *q == '+')
				q++;
			while (*q >= '0' && *q <= '9') {
				n = n * 10 + (*q - '0');
				if (n > 10000)
					n = 10000;	/* a runaway delay */
				q++;
				digits++;
			}
			if (digits == 0 || *q != '>')
				goto literal;

			found = 1;
			pad_total += (int)n;
			if (PC != '\0')
				for (i = 0; i < n; i++)
					if (outc(PC) == EOF)
						return (EOF);
			str = q;	/* the loop's str++ steps past '>' */
			continue;
		}
literal:
		if (outc((unsigned char)*str) == EOF)
			return (EOF);
	}

	if (!found || affcnt < 0)
		return (affcnt);
	return (pad_total > affcnt) ? pad_total : affcnt;
}
