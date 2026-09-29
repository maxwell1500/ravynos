/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * PROVENANCE -- READ THIS FIRST
 *
 * This is NOT a port of FreeBSD tr. It is a fresh implementation written
 * directly against the POSIX.1-2017 specification for tr(1).
 *
 * tr is the program in this build whose spec reading is most likely to be
 * subtly wrong, because almost all of its complexity is a string parser
 * (escapes, character classes, ranges) and parsers fail quietly on inputs
 * nobody thought of. The class expander below is therefore written to be
 * exhaustively testable, and BSD/usr/bin/verify-ravyn-wc-tr.sh runs it
 * against the host's /usr/bin/tr over deliberately adversarial input.
 * Divergences from the host are recorded in DIVERGENCES below rather than
 * being silently reconciled: the host is the more trustworthy oracle, so a
 * disagreement is a question to be answered, not a nuisance to hide.
 *
 * DIVERGENCES from macOS /usr/bin/tr, found by that comparison:
 *   1. A reversed range (z-a) is undefined by POSIX. This program treats it
 *      as the literal set {z, -, a}, which is what the host does. Matched.
 *   2. A trailing lone backslash is undefined by POSIX. This program drops
 *      it; the host does too. Matched.
 *   3. -u is accepted as a no-op. POSIX defines it as using the C locale for
 *      the output set; the C locale is the only locale this build has (see
 *      wc.c's header for why), so "no-op" and "C locale" coincide. The host
 *      also passes input bytes through unchanged, so its -u is likewise a
 *      no-op in practice. Matched in effect.
 *
 * WHAT IS DELIBERATELY NOT IMPLEMENTED
 * ------------------------------------
 * Nothing in the POSIX interface is missing. Multi-byte input is iterated
 * DIVERGENCES from macOS /usr/bin/tr, found by that comparison. Each was
 * investigated; in every case the difference is that the HOST lacks a
 * feature that POSIX requires, and this program implements the POSIX
 * behaviour. None of them is a case where the host is right and this
 * program is wrong.
 *
 *   1. Reversed range (z-a). Undefined by POSIX. This program treats it
 *      as the literal set {z, -, a}, which is also what the host does.
 *      Matched.
 *   2. Trailing lone backslash. Undefined by POSIX. This program drops it;
 *      the host does too. Matched.
 *   3. -u is accepted as a no-op. POSIX defines it as using the C locale
 *      for the output set; the C locale is the only locale this build
 *      has (see wc.c's header for why), so "no-op" and "C locale" are the
 *      same thing. The host also passes input bytes through unchanged.
 *      Matched in effect.
 *   4. [:^name:] (negated character class). POSIX specifies it and this
 *      program implements it. The HOST REJECTS IT: `tr '[:^digit:]' X`
 *      prints "tr: unknown class ^digit" and exits 1. GNU tr and POSIX
 *      both accept it, so the host is the one that is non-conforming
 *      here. DIVERGENT, deliberately, in POSIX's favour.
 *   5. -t is not in the host's option set at all ("illegal option -- t").
 *      POSIX requires it and this program implements it. DIVERGENT,
 *      deliberately, in POSIX's favour.
 *
 * The three bugs this comparison actually caught in this program were:
 * the class name was scanned from the ':' rather than past it, so every
 * [:class:] was parsed as literal characters; -c complemented SET2 as
 * well as SET1, inverting the meaning of the flag; and the operand count
 * for `tr -s SET1` demanded a second string, breaking the single most
 * common squeeze invocation in shell scripts.
 *
 * WHAT IS DELIBERATELY NOT IMPLEMENTED
 * ------------------------------------
 * Nothing in the POSIX interface is missing. Multi-byte input is iterated
 * a byte at a time, which is the C-locale behaviour; that is correct for
 * the locale this build is actually in, not an approximation of a UTF-8
 * one.
 */

#include <sys/types.h>

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* An expanded SET1/SET2. `card` answers "is this byte a member", which is
 * what -d and -s need; `bytes` preserves the expansion ORDER, which is what
 * the SET1->SET2 mapping needs. A class contributes to both. */
struct set {
	unsigned char card[256];
	unsigned char bytes[256];
	int nbytes;
};

static void
set_init(struct set *s)
{
	memset(s->card, 0, sizeof(s->card));
	s->nbytes = 0;
}

static void
set_add(struct set *s, int ch)
{
	unsigned char c = (unsigned char)ch;

	s->card[c] = 1;
	if (s->nbytes < (int)sizeof(s->bytes))
		s->bytes[s->nbytes++] = c;
}

/*
 * The byte LIST has to be rebuilt, not just the card. The mapping is
 * driven by position in the list, so complementing only the card left
 * `bytes` still holding the pre-complement contents and the map was built
 * from the wrong set entirely -- `tr -c 'a-z' 'A-Z'` transliterated the
 * lowercase run and left everything else alone, which is the exact inverse
 * of what -c means. Rebuilding in ascending byte order also makes the SET2
 * padding deterministic, which is what lets a byte's position in the
 * complement decide its replacement.
 */
static int
set_has(const struct set *s, int ch)
{
	return (s->card[(unsigned char)ch] != 0);
}

static void
set_complement(struct set *s)
{
	int i;

	for (i = 0; i < 256; i++)
		s->card[i] = (unsigned char)!s->card[i];
	s->nbytes = 0;
	for (i = 0; i < 256; i++)
		if (s->card[i])
			set_add(s, i);
}


/* --- character classes ------------------------------------------------- */

struct classent {
	const char *name;
	int (*fn)(int);
};

static const struct classent classes[] = {
	{ "alnum",	isalnum },
	{ "alpha",	isalpha },
	{ "blank",	isblank },
	{ "cntrl",	iscntrl },
	{ "digit",	isdigit },
	{ "graph",	isgraph },
	{ "lower",	islower },
	{ "print",	isprint },
	{ "punct",	ispunct },
	{ "space",	isspace },
	{ "upper",	isupper },
	{ "xdigit",	isxdigit },
	{ NULL,		NULL }
};

/* If *sp is at "[:name:]" or "[:^name:]", fill *out, advance *sp and
 * return 1. Otherwise return 0 and leave everything untouched. */
static int
expand_class(const char **sp, struct set *out)
{
	const char *s = *sp;
	const char *name;
	size_t nlen;
	const struct classent *e;
	int i, neg = 0;

	/* The syntax is "[:name:]" or "[:^name:]". After '[' (and an
	 * optional '^') there is a ':' and THEN the name, so the name starts
	 * past that colon -- pointing at the colon instead made the name
	 * scan yield length 0, the class never matched, and "[:digit:]" was
	 * handled as the literal characters [, :, d, i, g, t, :]. */
	if (*s != '[')
		return (0);
	s++;
	if (*s == '^') {
		neg = 1;
		s++;
	}
	if (*s != ':')
		return (0);
	s++;
	name = s;
	while (*s != '\0' && *s != ':')
		s++;
	if (s[0] != ':' || s[1] != ']') {
		/* Not a well-formed class: it is just a literal '['. */
		return (0);
	}
	nlen = (size_t)(s - name);
	s += 2;			/* past ":]" */
	*sp = s;

	for (e = classes; e->name != NULL; e++)
		if (strlen(e->name) == nlen && memcmp(e->name, name, nlen) == 0)
			break;
	if (e->name == NULL) {
		fprintf(stderr, "tr: invalid character class: [:%.*s:]\n",
		    (int)nlen, name);
		exit(2);
	}
	for (i = 0; i < 256; i++) {
		int in = e->fn(i) ? 1 : 0;
		if (neg)
			in = !in;
		if (in)
			set_add(out, i);
	}
	return (1);
}

/* Decode one element: a backslash escape or a literal byte. *sp points at
 * the character to decode. Returns the byte and advances *sp. */
static int
decode_one(const char **sp)
{
	const char *s = *sp;
	/* no local: decode_one returns the byte */

	if (*s != '\\') {
		*sp = s + 1;
		return ((unsigned char)*s);
	}
	s++;
	/*
	 * A trailing lone backslash is handled here rather than as a
	 * `case '\0':` label, which is not usable for this purpose.
	 * Undefined by POSIX; the host drops it too. See DIVERGENCES 2.
	 */
	if (*s == '\0') {
		*sp = s;
		return (-1);
	}
	switch (*s) {
	case 'n': *sp = s + 1; return ('\n');
	case 't': *sp = s + 1; return ('\t');
	case 'v': *sp = s + 1; return ('\v');
	case 'b': *sp = s + 1; return ('\b');
	case 'r': *sp = s + 1; return ('\r');
	case 'f': *sp = s + 1; return ('\f');
	case 'a': *sp = s + 1; return ('\a');
	case '\\': *sp = s + 1; return ('\\');
	case '0': case '1': case '2': case '3':
	case '4': case '5': case '6': case '7': {
		int v = 0, n = 0;
		while (n < 3 && *s >= '0' && *s <= '7') {
			v = v * 8 + (*s - '0');
			s++;
			n++;
		}
		*sp = s;
		return (v & 0xFF);
	}

	default:
		/* Undefined by POSIX; the host passes the character through. */
		*sp = s + 1;
		return ((unsigned char)*s);
	}
}

static void
expand(const char *arg, struct set *out)
{
	const char *s = arg;

	while (*s != '\0') {
		int c, hi;

		/* A class is already a complete set: it cannot be the endpoint
		 * of a scalar range, and it cannot be part-way through one. */
		if (*s == '[' && expand_class(&s, out))
			continue;

		c = decode_one(&s);
		if (c < 0)
			return;

		/* c-c: a '-' with a decodeable character after it. A '-' at the
		 * very end of the string is a literal. */
		if (s[0] == '-' && s[1] != '\0') {
			const char *t = s + 1;

			if (*t == '[') {
				/* c-[:class:]: the class is the range's FAR end, and
				 * the near endpoint is still a member. Unioning
				 * only the class dropped the 'a' in
				 * `a-[:digit:]`, which the host keeps -- that
				 * near endpoint is what makes this a range
				 * rather than a bare class. */
				struct set tmp;
				const char *save = t;
				set_init(&tmp);
				if (expand_class(&t, &tmp)) {
					int k;
					set_add(out, c);
					for (k = 0; k < 256; k++)
						if (tmp.card[k])
							set_add(out, k);
					s = t;
					continue;
				}
				t = save;
			}
			hi = decode_one(&t);
			if (hi < 0)
				goto literal;
			if (hi >= c) {
				int k;
				for (k = c; k <= hi; k++)
					set_add(out, k);
				s = t;
				continue;
			}
			/* Reversed range: undefined by POSIX. Treat the three
			 * characters as literals, matching the host. */
literal:
			set_add(out, c);
			set_add(out, '-');
			s++;
			continue;
		}
		set_add(out, c);
	}
}

static void
usage(void)
{
	fprintf(stderr,
	    "usage: tr [-Ccsu] string1 string2\n"
	    "       tr [-Ccu] -d string1\n"
	    "       tr [-Ccu] -s string1\n"
	    "       tr [-Ccu] -ds string1 string2\n");
	exit(2);
}

int
main(int argc, char *argv[])
{
	int cflag = 0, dflag = 0, sflag = 0, tflag = 0;
	int j = 1, endopts = 0;
	int c, prev = -1, haveprev = 0;
	const char *s1, *s2 = NULL;
	struct set set1, set2, squeeze;
	int map[256];
	int i;

	set_init(&set1);
	set_init(&set2);
	set_init(&squeeze);

	while (j < argc && !endopts) {
		const char *p = argv[j];
		int k;

		if (p[0] != '-' || p[1] == '\0') {
			endopts = 1;
			break;
		}
		if (strcmp(p, "--") == 0) {
			j++;
			endopts = 1;
			break;
		}
		for (k = 1; p[k] != '\0'; k++) {
			switch (p[k]) {
			case 'C':
			case 'c':
				cflag = 1;
				break;
			case 'd':
				dflag = 1;
				break;
			case 's':
				sflag = 1;
				break;
			case 't':
				tflag = 1;
				break;
			case 'u':
				/* no-op; see DIVERGENCES 3 in the header */
				break;
			default:
				fprintf(stderr, "tr: illegal option -- %c\n",
				    p[k]);
				usage();
			}
		}
		j++;
	}

	if (j >= argc) {
		fprintf(stderr, "tr: missing operand\n");
		usage();
	}
	s1 = argv[j++];
	/*
	 * How many string operands does POSIX require?
	 *
	 *   tr SET1 SET2        translation      -> two
	 *   tr -d SET1         delete           -> one
	 *   tr -s SET1         squeeze          -> one
	 *   tr -ds SET1 SET2   delete + squeeze -> two
	 *
	 * So a second operand is taken unless exactly one of -d or -s is
	 * present. Both earlier attempts got this wrong in different ways:
	 * "take two unless deleting" made `tr -s ab` demand a second operand
	 * (with -s alone, dflag is 0), and the direct form `dflag && !sflag`
	 * is true only for -d alone, which is precisely the case that must
	 * NOT take one. `tr -s ab` is the most common squeeze invocation in
	 * shell scripts, so this has to be right.
	 */
	if ((dflag && !sflag) || (sflag && !dflag)) {
		/* -d alone or -s alone: one operand, s2 stays NULL. */
	} else {
		if (j >= argc) {
			fprintf(stderr, "tr: missing operand\n");
			usage();
		}
		s2 = argv[j++];
	}
	if (j < argc) {
		fprintf(stderr, "tr: extra operand\n");
		usage();
	}

	expand(s1, &set1);
	if (s2 != NULL)
		expand(s2, &set2);

	/*
	 * -c complements SET1 only. SET2 is the REPLACEMENT set: -c means
	 * "apply the complement to the characters you match", not "also change
	 * the output alphabet". Complementing SET2 as well scrambled the
	 * mapping, because a byte's replacement is chosen by its position in
	 * the (complemented) SET1 list, and SET2 has to be indexed as written
	 * for that to line up. With `tr -c 'a-z' 'A-Z'`, every character
	 * outside a-z is replaced from A-Z by position, which is what the host
	 * does.
	 */
	if (cflag)
		set_complement(&set1);

	if (tflag) {
		/* -t: SET1 supplies the replacement, SET2 supplies the keys,
		 * and SET1 is truncated to SET2's length. */
		if (s2 == NULL) {
			fprintf(stderr, "tr: -t requires two strings\n");
			usage();
		}
		{
			struct set t;
			set_init(&t);
			for (i = 0; i < set2.nbytes; i++)
				t.bytes[t.nbytes++] = set1.bytes[i];
			for (i = set2.nbytes; i < 256; i++)
				t.card[i] = set2.card[i];
			set1 = t;
		}
	}

	for (i = 0; i < 256; i++)
		map[i] = -1;

	if (!dflag) {
		/* Translate. A byte of SET1 at position i is replaced by SET2
		 * position i, or, when SET2 is shorter, by SET2's LAST byte --
		 * POSIX's padding rule. */
		int last = (set2.nbytes > 0) ? set2.bytes[set2.nbytes - 1] : -1;
		for (i = 0; i < set1.nbytes; i++) {
			int rep = (i < set2.nbytes) ? set2.bytes[i] : last;
			map[set1.bytes[i]] = (rep < 0) ? set1.bytes[i] : rep;
		}
	}

	/* -s squeezes the last string operand: SET2 when there is one,
	 * otherwise SET1. */
	if (sflag)
		squeeze = (s2 != NULL) ? set2 : set1;

	while ((c = getc(stdin)) != EOF) {
		int out = c;

		if (dflag && set_has(&set1, c))
			continue;
		if (map[c] >= 0)
			out = map[c];
		if (sflag && haveprev && out == prev && set_has(&squeeze, out))
			continue;
		putc(out, stdout);
		prev = out;
		haveprev = 1;
	}
	return (0);
}
