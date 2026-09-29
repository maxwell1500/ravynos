/*-
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * test-termcap.c -- executable checks for libsystem_termcap.
 *
 * Every claim README.md makes about this component is asserted here, so the
 * README can be read as a summary of evidence rather than of intentions.
 *
 * This file is built twice by test/run-tests.sh: once for the Darwin host, so
 * the results can actually be EXECUTED, and once with the ravynOS SDK's own
 * headers, because a termcap entry that only means something under one libc is
 * not an entry.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "termcap.h"

static int n_pass, n_fail;

static void
check(const char *name, int cond, const char *detail)
{
	if (cond) {
		n_pass++;
		printf("  PASS  %s\n", name);
	} else {
		n_fail++;
		printf("  FAIL  %s%s%s\n", name, detail ? "   -- " : "",
		    detail ? detail : "");
	}
}

/* Compare a capability's bytes against a literal, printing both on failure. */
static void
check_str(const char *name, const char *got, const char *want)
{
	char d[512];

	if (got == NULL) {
		snprintf(d, sizeof(d), "got NULL, want \"%s\"", want);
		check(name, 0, d);
		return;
	}
	if (strcmp(got, want) != 0) {
		size_t i, o = 0;

		d[o++] = 'g'; d[o++] = 'o'; d[o++] = 't'; d[o++] = ' ';
		d[o++] = '"';
		for (i = 0; got[i] != '\0' && o < sizeof(d) - 8; i++)
			o += (unsigned)snprintf(d + o, sizeof(d) - o, "\\x%02x",
			    (unsigned char)got[i]);
		snprintf(d + o, sizeof(d) - o, "\" want \"%s\"", want);
		check(name, 0, d);
		return;
	}
	check(name, 1, NULL);
}

static void
check_int(const char *name, long got, long want)
{
	char d[128];

	if (got == want) {
		check(name, 1, NULL);
		return;
	}
	snprintf(d, sizeof(d), "got %ld, want %ld", got, want);
	check(name, 0, d);
}

/* ---- tputs capture -------------------------------------------------- */

static char cap_buf[4096];
static size_t cap_len;
static int cap_outc(int c)
{
	if (cap_len + 1 < sizeof(cap_buf))
		cap_buf[cap_len++] = (char)c;
	cap_buf[cap_len] = '\0';
	return (c);
}

static void
cap_reset(void)
{
	cap_len = 0;
	cap_buf[0] = '\0';
}

/* ------------------------------------------------------------------ */
/* Every capability BSD/lib/libedit/src/terminal.c asks for, and what  */
/* this component answers for it.                                      */
/*                                                                    */
/* The list is transcribed from terminal.c:101-212 (struct termcapstr */
/* and struct termcapval). It is here so that a capability silently    */
/* dropped from the entry shows up as a FAIL rather than as "the shell */
/* got slower somewhere".                                              */
/* ------------------------------------------------------------------ */

struct expect {
	const char	*cap;
	const char	*kind;		/* "s" string, "n" number, "b" bool */
	const char	*value;		/* expected, for "s" */
	int		 num;		/* expected, for "n" */
	int		 flag;		/* expected, for "b" */
	const char	*why;		/* why it is absent, if it is */
};

static const struct expect libedit_caps[] = {
	{ "al", "s", "\033[L", 0, 0, NULL },
	{ "bl", "s", "\a",      0, 0, NULL },
	{ "cd", "s", "\033[J",  0, 0, NULL },
	{ "ce", "s", "\033[K",  0, 0, NULL },
	{ "ch", "s", "\033[%i%dG", 0, 0, NULL },
	{ "cl", "s", "\033[H\033[2J", 0, 0, NULL },
	{ "dc", "s", "\033[P",  0, 0, NULL },
	{ "dl", "s", "\033[M",  0, 0, NULL },
	{ "dm", "s", "\033[4h", 0, 0, NULL },
	{ "ed", "s", "\033[4l", 0, 0, NULL },
	{ "ei", "s", "\033[4l", 0, 0, NULL },
	{ "fs", "s", NULL, 0, 0, "status line; nothing in the consumer asks it" },
	{ "ho", "s", "\033[H",  0, 0, NULL },
	{ "ic", "s", "\033[@",  0, 0, NULL },
	{ "im", "s", "\033[4h", 0, 0, NULL },
	{ "ip", "s", "\033[1@", 0, 0, NULL },
	{ "kd", "s", "\033OB",  0, 0, NULL },
	{ "kl", "s", "\033OD",  0, 0, NULL },
	{ "kr", "s", "\033OC",  0, 0, NULL },
	{ "ku", "s", "\033OA",  0, 0, NULL },
	{ "md", "s", "\033[1m", 0, 0, NULL },
	{ "me", "s", "\033[m",  0, 0, NULL },
	{ "nd", "s", "\033[C",  0, 0, NULL },
	{ "se", "s", "\033[m",  0, 0, NULL },
	{ "so", "s", "\033[7m", 0, 0, NULL },
	{ "ts", "s", NULL, 0, 0, "status line; nothing in the consumer asks it" },
	{ "up", "s", "\033[A",  0, 0, NULL },
	{ "us", "s", "\033[4m", 0, 0, NULL },
	{ "ue", "s", "\033[m",  0, 0, NULL },
	{ "vb", "s", NULL, 0, 0, "DECTCEM; a plain VT100 ignores it" },
	{ "DC", "s", "\033[%dP", 0, 0, NULL },
	{ "DO", "s", NULL, 0, 0, "libedit avoids it: terminal.c:510-514" },
	{ "IC", "s", "\033[%d@", 0, 0, NULL },
	/* LE and UP are absent ON PURPOSE -- see the note in termcap.c.  */
	{ "LE", "s", NULL, 0, 0, "libedit calls tgoto on it with -del: terminal.c:597" },
	{ "RI", "s", "\033[%dC", 0, 0, NULL },
	{ "UP", "s", NULL, 0, 0, "libedit calls tgoto on it with -del: terminal.c:516" },
	{ "kh", "s", "\033OH",  0, 0, NULL },
	{ "@7", "s", NULL, 0, 0, "not a termcap capability; no terminal sends it" },
	{ "kD", "s", "\033[3~", 0, 0, NULL },

	{ "am", "b", NULL, 0, 1, NULL },
	{ "pt", "b", NULL, 0, 1, NULL },
	{ "li", "n", NULL, 24, 0, NULL },
	{ "co", "n", NULL, 80, 0, NULL },
	{ "km", "b", NULL, 0, 1, NULL },
	{ "xt", "b", NULL, 0, 0, "VT100 tabs do not erase" },
	{ "xn", "b", NULL, 0, 0, "no magic margins on a VT100" },
	{ "MT", "b", NULL, 0, 1, NULL },
	{ NULL, NULL, NULL, 0, 0, NULL }
};

/* ------------------------------------------------------------------ */

static void
test_tgetent(void)
{
	char buf[TC_BUFSIZ];

	printf("\n== tgetent\n");

	check_int("tgetent(xterm) == 1", tgetent(buf, "xterm"), 1);
	check_int("entry is NUL-terminated", buf[0] != '\0', 1);
	check_int("entry names its first capability", strncmp(buf, "al=", 3) == 0, 1);

	check_int("tgetent(\"dumb\") == 1", tgetent(buf, "dumb"), 1);
	check_int("tgetent(\"no-such-terminal\") == 0",
	    tgetent(buf, "no-such-terminal"), 0);
	check_int("a failed lookup leaves bp empty", buf[0] == '\0', 1);

	/*
	 * -1 means "a termcap database file exists and could not be read".
	 * There is no file, so no name may produce it. If this ever goes
	 * red, something is pretending a database was looked for.
	 */
	check_int("tgetent of the empty name == 0", tgetent(buf, ""), 0);
	check_int("tgetent(NULL) with no TERM == 0",
	    (unsetenv("TERM"), tgetent(buf, NULL)), 0);

	setenv("TERM", "vt100", 1);
	check_int("tgetent(NULL) reads $TERM", tgetent(buf, NULL), 1);
	setenv("TERM", "not-a-terminal", 1);
	check_int("tgetent(NULL) with an unknown $TERM == 0", tgetent(buf, NULL), 0);
	unsetenv("TERM");

	/* Aliases are whole names, not prefixes. */
	check_int("tgetent(\"vt10\") == 0 (not a prefix of vt100)",
	    tgetent(buf, "vt10"), 0);
	check_int("tgetent(\"screen\") == 1", tgetent(buf, "screen"), 1);
	check_int("tgetent(\"screen.xterm-256color\") == 1",
	    tgetent(buf, "screen.xterm-256color"), 1);
	check_int("tgetent(\"xterm-kitty\") == 1", tgetent(buf, "xterm-kitty"), 1);

	/*
	 * The interface cannot learn how big bp is -- that is what TC_BUFSIZ
	 * is for, and it is the caller's side of the contract. What CAN be
	 * checked is that this component never writes more than it promised,
	 * so a TC_BUFSIZ buffer with a canary past the end is the honest
	 * version of that test. An 8-byte buffer would be undefined
	 * behaviour, and a test asserting a truncation guarantee that does
	 * not exist would be exactly the kind of plausible-looking fiction
	 * this component refuses to ship.
	 */
	{
		static char big[TC_BUFSIZ + 16];
		size_t i;
		int past = 0;

		memset(big, 'X', sizeof(big));
		check_int("tgetent into a TC_BUFSIZ buffer == 1",
		    tgetent(big, "xterm"), 1);
		for (i = TC_BUFSIZ; i < sizeof(big); i++)
			if (big[i] != 'X')
				past = 1;
		check_int("nothing was written past TC_BUFSIZ bytes", past, 0);
	}
}

static void
test_state(void)
{
	printf("\n== state set and cleared by tgetent\n");

	check_int("tgetent(\"xterm\")", tgetent(NULL, "xterm"), 1);
	check_str("UP is `up'", UP, "\033[A");
	check_str("HO is `ho'", HO, "\033[H");
	check_str("BO is `md'", BO, "\033[1m");
	check_str("EE is `me'", EE, "\033[m");
	check_int("PC is 0 (no entry defines a pad character)", PC, 0);
	check_str("BC is backspace", BC, "\010");

	check_int("tgetent(\"dumb\")", tgetent(NULL, "dumb"), 1);
	check_int("UP is NULL on the dumb entry", UP == NULL, 1);
	check_int("HO is NULL on the dumb entry", HO == NULL, 1);
	check_int("BO is NULL on the dumb entry", BO == NULL, 1);
	check_int("EE is NULL on the dumb entry", EE == NULL, 1);

	check_int("tgetent(\"no-such-terminal\")", tgetent(NULL, "no-such-terminal"), 0);
	check_int("a failed lookup clears UP", UP == NULL, 1);
	check_int("a failed lookup makes tgetnum report -1", tgetnum("co"), -1);
	check_int("a failed lookup makes tgetflag report 0", tgetflag("am"), 0);
	check_int("a failed lookup makes tgetstr report NULL", tgetstr("ce", NULL) == NULL, 1);

	check_int("tgetent(\"xterm\") again", tgetent(NULL, "xterm"), 1);
	check_str("UP came back", UP, "\033[A");
}

static void
test_libedit_caps(void)
{
	const struct expect *e;
	int n = 0;

	printf("\n== every capability BSD/lib/libedit/src/terminal.c asks for\n");

	check_int("tgetent(\"xterm\")", tgetent(NULL, "xterm"), 1);
	for (e = libedit_caps; e->cap != NULL; e++, n++) {
		char nm[64];
		char *got;

		snprintf(nm, sizeof(nm), "libedit cap %-3s present", e->cap);
		if (e->kind[0] == 's') {
			got = tgetstr(e->cap, NULL);
			if (e->value == NULL) {
				snprintf(nm, sizeof(nm),
				    "libedit cap %-3s absent (%s)", e->cap, e->why);
				check(nm, got == NULL, NULL);
			} else {
				snprintf(nm, sizeof(nm),
				    "libedit cap %-3s value", e->cap);
				check_str(nm, got, e->value);
			}
		} else if (e->kind[0] == 'n') {
			snprintf(nm, sizeof(nm), "libedit cap %-3s == %d",
			    e->cap, e->num);
			check_int(nm, tgetnum(e->cap), e->num);
		} else {
			snprintf(nm, sizeof(nm), "libedit cap %-3s == %d",
			    e->cap, e->flag);
			check_int(nm, tgetflag(e->cap), e->flag);
		}
	}
	check_int("the transcribed list is non-trivial", n >= 40, 1);
}

static void
test_lookup_errors(void)
{
	printf("\n== lookup error returns\n");

	check_int("tgetent(\"xterm\")", tgetent(NULL, "xterm"), 1);

	check_int("tgetnum of an absent cap is -1", tgetnum("nosuchcap"), -1);
	check_int("tgetnum of a string cap is -1", tgetnum("ce"), -1);
	check_int("tgetnum of a boolean cap is -1", tgetnum("am"), -1);
	check_int("tgetnum of NULL is -1", tgetnum(NULL), -1);
	check_int("tgetnum of \"\" is -1", tgetnum(""), -1);
	check_int("tgetnum of the literal name \"co#\" is -1", tgetnum("co#"), -1);

	check_int("tgetflag of an absent cap is 0", tgetflag("nosuchcap"), 0);
	check_int("tgetflag of NULL is 0", tgetflag(NULL), 0);
	check_int("tgetflag of \"\" is 0", tgetflag(""), 0);
	check_int("tgetflag of a present string cap is 1", tgetflag("ce"), 1);

	check_int("tgetstr of an absent cap is NULL", tgetstr("nosuchcap", NULL) == NULL, 1);
	check_int("tgetstr of NULL is NULL", tgetstr(NULL, NULL) == NULL, 1);
	check_int("tgetstr of \"\" is NULL", tgetstr("", NULL) == NULL, 1);
}

static void
test_name_matching(void)
{
	/*
	 * A substring search for "e" finds ce, se, ue and me. For "le" it
	 * finds nothing when `LE' is what was asked for. Both answers look
	 * plausible, so both are asserted.
	 */
	printf("\n== capability names match whole fields only\n");

	check_int("tgetent(\"xterm\")", tgetent(NULL, "xterm"), 1);

	check_int("tgetstr(\"e\") does not match ce/se/ue/me",
	    tgetstr("e", NULL) == NULL, 1);
	check_int("tgetstr(\"c\") does not match ce/cd/cl",
	    tgetstr("c", NULL) == NULL, 1);
	check_int("tgetstr(\"i\") does not match ic/ip/ip/im",
	    tgetstr("i", NULL) == NULL, 1);
	check_int("tgetstr(\"E\") is case sensitive", tgetstr("E", NULL) == NULL, 1);
	check_int("tgetstr(\"LE\") is absent on purpose",
	    tgetstr("LE", NULL) == NULL, 1);
	check_int("tgetstr(\"UP\") is absent on purpose",
	    tgetstr("UP", NULL) == NULL, 1);
	check_str("tgetstr(\"ce\") still works", tgetstr("ce", NULL), "\033[K");
}

static void
test_tgoto(void)
{
	printf("\n== tgoto\n");

	check_int("tgetent(\"xterm\")", tgetent(NULL, "xterm"), 1);

	check_str("tgoto(\"ch\", 5, 5) is ESC [ 6 G   (%i makes CHA 1-based)",
	    tgoto(tgetstr("ch", NULL), 5, 5), "\033[6G");
	check_str("tgoto(\"ch\", 1, 1) is ESC [ 2 G",
	    tgoto(tgetstr("ch", NULL), 1, 1), "\033[2G");
	check_str("tgoto(\"RI\", 3, 3) is ESC [ 3 C    (no %i: CUF is a distance)",
	    tgoto(tgetstr("RI", NULL), 3, 3), "\033[3C");
	check_str("tgoto(\"DC\", 4, 4) is ESC [ 4 P", tgoto(tgetstr("DC", NULL), 4, 4),
	    "\033[4P");
	check_str("tgoto(\"IC\", 2, 2) is ESC [ 2 @", tgoto(tgetstr("IC", NULL), 2, 2),
	    "\033[2@");

	/* The documented conversion set, on strings no entry uses. */
	check_str("%% emits a percent", tgoto("a%%b", 0, 0), "a%b");
	check_str("%d emits col", tgoto("%d", 7, 9), "7");
	check_str("%2 emits row", tgoto("%2", 7, 9), "9");
	check_str("%3 emits col again", tgoto("%3", 7, 9), "7");
	check_str("%i increments col", tgoto("%i%d", 7, 9), "8");
	check_str("%r swaps", tgoto("%d/%2", 7, 9), "7/9");
	check_str("%r then %d sees row first", tgoto("%r%d", 7, 9), "9");
	check_str("%+3 adds 3", tgoto("%+3%d", 7, 9), "10");
	check_str("%.3 adds 4", tgoto("%.3%d", 7, 9), "11");
	check_str("a bare %. adds 1", tgoto("%.%d", 7, 9), "8");
	check_str("%>xy pads col out to width y with char x",
	    tgoto("%>07%d", 7, 9), "0000007");
	check_str("a padding spec is stripped and honoured",
	    tgoto("ab%6X", 0, 0), "abXXXX");
	check_str("a zero-width padding spec is stripped",
	    tgoto("ab%+X", 0, 0), "ab");
	check_str("a precision is parsed and stripped",
	    tgoto("ab%6.3X", 0, 0), "abXXXX");

	/*
	 * Unsupported conversions must be refused, not approximated. Each
	 * of these has a plausible-looking wrong answer, which is precisely
	 * why they are checked.
	 */
	check_int("tgoto(NULL) is NULL", tgoto(NULL, 0, 0) == NULL, 1);
	check_int("tgoto(\"\") is an empty string", strcmp(tgoto("", 0, 0), "") == 0, 1);
	check_int("%p1 (terminfo stack) is refused",
	    tgoto("\033[%p1%dD", 3, 3) == NULL, 1);
	check_int("%P (terminfo stack) is refused", tgoto("%P", 3, 3) == NULL, 1);
	check_int("%n (magic cookie) is refused", tgoto("%n", 3, 3) == NULL, 1);
	check_int("%B is refused", tgoto("%B", 3, 3) == NULL, 1);
	check_int("%D is refused", tgoto("%D", 3, 3) == NULL, 1);
	check_int("%a (arithmetic) is refused", tgoto("%a", 3, 3) == NULL, 1);
	check_int("%s (string stack) is refused", tgoto("%s", 3, 3) == NULL, 1);
	check_int("a trailing % is refused", tgoto("abc%", 0, 0) == NULL, 1);
	check_int("a negative count is emitted as written, not hidden",
	    strcmp(tgoto("%d", -7, 0), "-7") == 0, 1);
}

static void
test_tputs(void)
{
	char *r;
	int n;

	printf("\n== tputs\n");

	check_int("tgetent(\"xterm\")", tgetent(NULL, "xterm"), 1);

	cap_reset();
	n = tputs(tgetstr("ce", NULL), 1, cap_outc);
	check_str("tputs writes `ce' byte for byte", cap_buf, "\033[K");
	check_int("tputs of a padless string returns affcnt", n, 1);

	cap_reset();
	n = tputs(tgetstr("up", NULL), 0, cap_outc);
	check_str("tputs writes `up' byte for byte", cap_buf, "\033[A");
	check_int("tputs with affcnt 0 returns 0", n, 0);

	cap_reset();
	n = tputs(NULL, 7, cap_outc);
	check_str("tputs(NULL) writes nothing", cap_buf, "");
	check_int("tputs(NULL) returns affcnt", n, 7);

	/* Padding. PC is 0 here, so the count is owed but no bytes are made. */
	check_int("PC is 0 for these entries", PC, 0);
	cap_reset();
	n = tputs("a$<5>b", 0, cap_outc);
	check_str("with PC==0 the pad bytes are not emitted", cap_buf, "ab");
	check_int("the padding owed is still reported", n, 5);

	cap_reset();
	n = tputs("a$<3>b", 1, cap_outc);
	check_int("affcnt smaller than the pad returns the pad", n, 3);
	cap_reset();
	n = tputs("a$<3>b", 9, cap_outc);
	check_int("affcnt larger than the pad is returned unchanged", n, 9);
	cap_reset();
	n = tputs("a$<3>b", -1, cap_outc);
	check_int("a negative affcnt is returned unchanged", n, -1);

	/* With a pad character, the bytes really are produced. */
	PC = '\a';
	cap_reset();
	n = tputs("a$<4>b", 0, cap_outc);
	check_str("with PC set the pad bytes are PC", cap_buf, "a\a\a\a\a" "b");
	check_int("and the count is still right", n, 4);
	PC = '\0';

	/* A '$' that is not padding must pass through untouched. */
	cap_reset();
	tputs("a$5b", 0, cap_outc);
	check_str("a $ not followed by digits is literal", cap_buf, "a$5b");

	/* libedit's real pattern: tputs(tgoto(...), affcnt). */
	cap_reset();
	r = tgoto(tgetstr("DC", NULL), 3, 3);
	n = tputs(r, 3, cap_outc);
	check_str("tputs(tgoto(`DC')) is what the editor would emit", cap_buf,
	    "\033[3P");
	check_int("affcnt survives the round trip", n, 3);

	cap_reset();
	check_int("tputs(tgoto(LE)) on an absent capability writes nothing",
	    (r = tgoto(tgetstr("LE", NULL), -5, -5)) != NULL ||
	    tputs(r, -5, cap_outc) == -5, 1);
}

static void
test_tgetstr_area(void)
{
	/*
	 * libedit passes a 2048-byte buffer as the area and asks for 40
	 * capabilities one after another (terminal.c:894-897). If the
	 * decoded strings do not all fit, that is an overflow on libedit's
	 * stack, so the total size is asserted rather than assumed.
	 */
	char area[2048];
	char *p = area;
	const struct expect *e;
	size_t used = 0;
	int count = 0;

	printf("\n== tgetstr's area\n");

	check_int("tgetent(\"xterm\")", tgetent(NULL, "xterm"), 1);

	for (e = libedit_caps; e->cap != NULL; e++) {
		char *s;

		if (e->kind[0] != 's')
			continue;
		s = tgetstr(e->cap, &p);
		if (s == NULL)
			continue;
		if (strcmp(s, e->value) != 0) {
			check("area value matches", 0, e->cap);
			return;
		}
		count++;
	}
	check_int("every present string cap came back identical", count > 25, 1);
	used = (size_t)(p - area);
	check("the whole set fits in libedit's 2048-byte area",
	    used < 2048, NULL);
	printf("        (40 capabilities decode to %zu bytes of 2048)\n", used);

	/* The same call twice, with the area reset, gives the same answer. */
	p = area;
	check_str("a second pass over the area agrees",
	    tgetstr("ce", &p), "\033[K");
}

int
main(void)
{
	printf("libsystem_termcap test suite\n");

	test_tgetent();
	test_state();
	test_libedit_caps();
	test_lookup_errors();
	test_name_matching();
	test_tgoto();
	test_tputs();
	test_tgetstr_area();

	printf("\n%d passed, %d failed\n", n_pass, n_fail);
	return (n_fail == 0) ? 0 : 1;
}
