/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * test-pwdgrp -- executed proof for Libraries/Libsystem/libsystem_pwdgrp.
 *
 * Built twice by test/run-tests.sh:
 *
 *   test-pwdgrp           against the REAL /etc/passwd and /etc/group, so the
 *                         hit / miss / rewind / short-buffer / user_from_uid
 *                         cases run against actual database content.
 *   test-pwdgrp-fixture   against a generated database containing a comment,
 *                         a blank line, a too-short line, a non-numeric id,
 *                         a '+' NIS line, a '-' NIS line, an over-long line
 *                         and a long-name entry. None of those can be asked
 *                         for of a real /etc/passwd.
 *
 * Both builds run the same code, so both builds use the same assertions; only
 * the names and ids of the entries they are expected to find differ. That
 * is what KNOWN_PW / KNOWN_GRP below are for. The cases that only make sense
 * against the fixture -- the malformed and NIS lines -- are compiled only
 * into the fixture build and report SKIP in the other, rather than silently
 * passing.
 */

#include <sys/types.h>

#include <errno.h>
#include <grp.h>
#include <limits.h>
#include <pwd.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "libsystem_pwdgrp.h"

#ifndef _RAVYN_TEST_PW_PATH
#define	_RAVYN_TEST_PW_PATH	"/etc/passwd"
#endif
#ifndef _RAVYN_TEST_GR_PATH
#define	_RAVYN_TEST_GR_PATH	"/etc/group"
#endif

/* An id no database here contains, in either build. */
#define	NO_SUCH_UID	((uid_t)0x7ffffffe)
#define	NO_SUCH_GID	((gid_t)0x7ffffffd)

#ifdef _RAVYN_TEST_FIXTURE
#define	KNOWN_PW	"froot"
#define	KNOWN_PW_UID	((uid_t)4000)
#define	KNOWN_PW_GID	((gid_t)4000)
#define	KNOWN_PW_DIR	"/home/froot"
#define	KNOWN_PW_SHELL	"/bin/sh"
#define	KNOWN_GRP	"fgroup"
#define	KNOWN_GRP_GID	((gid_t)5000)
#define	BUILD_TAG	"FIXTURE"
#else
#define	KNOWN_PW	"root"
#define	KNOWN_PW_UID	((uid_t)0)
#define	KNOWN_PW_GID	((gid_t)0)
#define	KNOWN_PW_DIR	"/var/root"
#define	KNOWN_PW_SHELL	"/bin/sh"
#define	KNOWN_GRP	"wheel"
#define	KNOWN_GRP_GID	((gid_t)0)
#define	BUILD_TAG	"real system"
#endif

#define	BUFSZ	4096

static int checks;
static int failures;
static int skips;
static char buf[BUFSZ];

static void
ok(int cond, const char *fmt, ...)
{
	va_list ap;

	checks++;
	if (!cond)
		failures++;
	printf("%s ", cond ? "ok  " : "FAIL");
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	putchar('\n');
	fflush(stdout);
}

static void
skip(const char *what)
{
	skips++;
	printf("skip %s\n", what);
	fflush(stdout);
}

static int
inbuf(const void *p, const void *b, size_t n)
{
	const char *c = p;
	const char *s = b;

	return c >= s && c < s + n;
}

/* ------------------------------------------------------------------ */
/* Runs against either database.					      */
/* ------------------------------------------------------------------ */

static void
test_pwnam(void)
{
	struct passwd *pw;

	pw = getpwnam(KNOWN_PW);
	ok(pw != NULL, "getpwnam(\"%s\") -> %s", KNOWN_PW,
	    pw != NULL ? pw->pw_name : "(null)");
	if (pw != NULL) {
		ok(strcmp(pw->pw_name, KNOWN_PW) == 0, "  pw_name == \"%s\"",
		    KNOWN_PW);
		ok(pw->pw_passwd != NULL, "  pw_passwd present");
		ok(pw->pw_gecos != NULL, "  pw_gecos present");
		ok(pw->pw_dir != NULL && *pw->pw_dir != '\0',
		    "  pw_dir == \"%s\"", pw->pw_dir);
		ok(pw->pw_shell != NULL && *pw->pw_shell != '\0',
		    "  pw_shell == \"%s\"", pw->pw_shell);
		ok(strcmp(pw->pw_dir, KNOWN_PW_DIR) == 0,
		    "  pw_dir is the database's own, not a neighbour's");
		ok(strcmp(pw->pw_shell, KNOWN_PW_SHELL) == 0,
		    "  pw_shell is the database's own");
		/* The trailing-newline bug: "/bin/sh\n", not "/bin/sh". */
		ok(strchr(pw->pw_shell, '\n') == NULL,
		    "  pw_shell carries no trailing newline");
		ok(pw->pw_uid == KNOWN_PW_UID && pw->pw_gid == KNOWN_PW_GID,
		    "  pw_uid == %u, pw_gid == %u", (unsigned)pw->pw_uid,
		    (unsigned)pw->pw_gid);
	}

	ok(getpwnam("no-such-user-ravynos-test") == NULL,
	    "getpwnam(\"no-such-user-ravynos-test\") -> NULL");
	ok(getpwnam("") == NULL, "getpwnam(\"\") -> NULL");
}

static void
test_pwuid(void)
{
	struct passwd *pw;

	pw = getpwuid(KNOWN_PW_UID);
	ok(pw != NULL, "getpwuid(%u) -> %s", (unsigned)KNOWN_PW_UID,
	    pw != NULL ? pw->pw_name : "(null)");
	ok(pw != NULL && pw->pw_uid == KNOWN_PW_UID,
	    "  pw_uid == %u", (unsigned)KNOWN_PW_UID);
	ok(getpwuid(NO_SUCH_UID) == NULL, "getpwuid(%u) -> NULL",
	    (unsigned)NO_SUCH_UID);
}

/*
 * The rewind-after-EOF behaviour, which nothing else exercises.
 *
 * The contract is: getpwent() returns NULL at end of file, and the call made
 * AFTER that NULL starts the database over. The first NULL is therefore
 * produced by the iteration loop itself; calling getpwent() a second time to
 * "check" it is exactly the call that triggers the rewind, which is why this
 * does not do that.
 */
static void
test_pwent_rewind(void)
{
	struct passwd *pw;
	char first[256];
	int n, n2;

	setpwent();
	pw = getpwent();
	ok(pw != NULL, "getpwent() first entry -> %s",
	    pw != NULL ? pw->pw_name : "(null)");
	if (pw != NULL)
		snprintf(first, sizeof(first), "%s", pw->pw_name);
	else
		first[0] = '\0';

	for (n = 1; getpwent() != NULL; n++)
		;
	ok(n > 0, "getpwent() returned NULL after %d entries", n);

	pw = getpwent();
	ok(pw != NULL, "getpwent() called AFTER that NULL -> %s (rewound)",
	    pw != NULL ? pw->pw_name : "(null)");
	ok(pw != NULL && strcmp(pw->pw_name, first) == 0,
	    "  and it is the FIRST entry again (\"%s\")", first);

	for (n2 = 1; getpwent() != NULL; n2++)
		;
	ok(n2 == n, "the second full pass saw the same %d entries", n2);
	endpwent();
}

static void
test_grnam(void)
{
	struct group *gr;
	char **m;

	gr = getgrnam(KNOWN_GRP);
	ok(gr != NULL, "getgrnam(\"%s\") -> %s", KNOWN_GRP,
	    gr != NULL ? gr->gr_name : "(null)");
	if (gr != NULL) {
		ok(strcmp(gr->gr_name, KNOWN_GRP) == 0, "  gr_name == \"%s\"",
		    KNOWN_GRP);
		ok(gr->gr_gid == KNOWN_GRP_GID, "  gr_gid == %u",
		    (unsigned)gr->gr_gid);
		ok(gr->gr_mem != NULL, "  gr_mem is never NULL");
		for (m = gr->gr_mem; m != NULL && *m != NULL; m++)
			printf("       member: %s\n", *m);
		ok(gr->gr_passwd != NULL, "  gr_passwd present");
	}
	ok(getgrnam("no-such-group-ravynos-test") == NULL,
	    "getgrnam(\"no-such-group-ravynos-test\") -> NULL");
}

static void
test_grgid(void)
{
	struct group *gr;

	gr = getgrgid(KNOWN_GRP_GID);
	ok(gr != NULL, "getgrgid(%u) -> %s", (unsigned)KNOWN_GRP_GID,
	    gr != NULL ? gr->gr_name : "(null)");
	ok(gr != NULL && gr->gr_gid == KNOWN_GRP_GID, "  gr_gid == %u",
	    (unsigned)KNOWN_GRP_GID);
	ok(getgrgid(NO_SUCH_GID) == NULL, "getgrgid(%u) -> NULL",
	    (unsigned)NO_SUCH_GID);
}

static void
test_grent_rewind(void)
{
	struct group *gr;
	char first[256];
	int n, n2;

	setgrent();
	gr = getgrent();
	ok(gr != NULL, "getgrent() first entry -> %s",
	    gr != NULL ? gr->gr_name : "(null)");
	if (gr != NULL)
		snprintf(first, sizeof(first), "%s", gr->gr_name);
	else
		first[0] = '\0';

	for (n = 1; getgrent() != NULL; n++)
		;
	ok(n > 0, "getgrent() returned NULL after %d entries", n);

	gr = getgrent();
	ok(gr != NULL, "getgrent() called AFTER that NULL -> %s (rewound)",
	    gr != NULL ? gr->gr_name : "(null)");
	ok(gr != NULL && strcmp(gr->gr_name, first) == 0,
	    "  and it is the FIRST entry again (\"%s\")", first);

	for (n2 = 1; getgrent() != NULL; n2++)
		;
	ok(n2 == n, "the second full pass saw the same %d entries", n2);
	endgrent();
}

/*
 * The caller-supplied-buffer forms. Two things matter here: a miss is
 * 0-with-NULL-*result (success, not an error, and NOT a filled buffer), and
 * a short buffer is ERANGE with the caller's buffer and struct untouched.
 */
static void
test_r_forms(void)
{
	struct passwd pw, saved;
	struct passwd *res;
	struct group gr;
	struct group *gres;
	char tiny[8];
	size_t need;
	int rc;

	memset(buf, 'X', sizeof(buf));
	res = (struct passwd *)(uintptr_t)0x1;
	rc = getpwnam_r("no-such-user-ravynos-test", &pw, buf, sizeof(buf), &res);
	ok(rc == 0, "getpwnam_r(miss) returns 0, not an error (rc=%d)", rc);
	ok(res == NULL, "  and *result == NULL, not the incoming value");
	ok(buf[0] == 'X', "  and the caller buffer was NOT touched");

	memset(buf, 'X', sizeof(buf));
	res = (struct passwd *)(uintptr_t)0x1;
	rc = getpwuid_r(NO_SUCH_UID, &pw, buf, sizeof(buf), &res);
	ok(rc == 0 && res == NULL, "getpwuid_r(miss) rc=%d, *result NULL", rc);
	ok(buf[0] == 'X', "  and the caller buffer was NOT touched");

	memset(buf, 0, sizeof(buf));
	rc = getpwnam_r(KNOWN_PW, &pw, buf, sizeof(buf), &res);
	ok(rc == 0 && res == &pw, "getpwnam_r(\"%s\") rc=%d, *result == pwd",
	    KNOWN_PW, rc);
	if (rc == 0 && res == &pw) {
		ok(strcmp(pw.pw_name, KNOWN_PW) == 0, "  pw_name == \"%s\"",
		    pw.pw_name);
		ok(inbuf(pw.pw_name, buf, sizeof(buf)),
		    "  pw_name points into the caller's buffer");
		ok(inbuf(pw.pw_shell, buf, sizeof(buf)),
		    "  pw_shell points into the caller's buffer");
		ok(strchr(pw.pw_shell, '\n') == NULL, "  pw_shell == \"%s\"",
		    pw.pw_shell);
		ok(pw.pw_class != NULL && *pw.pw_class == '\0',
		    "  pw_class is the empty string, not NULL");

		/* One byte short of what the entry needs. */
		saved = pw;
		need = strlen(saved.pw_name) + strlen(saved.pw_passwd) +
		    strlen(saved.pw_gecos) + strlen(saved.pw_dir) +
		    strlen(saved.pw_shell) + strlen(saved.pw_class) + 6;
		memset(buf, 'X', sizeof(buf));
		res = (struct passwd *)(uintptr_t)0x1;
		rc = getpwnam_r(KNOWN_PW, &pw, buf, need - 1, &res);
		ok(rc == ERANGE, "getpwnam_r(%s, buflen=%lu) -> ERANGE (%d)",
		    KNOWN_PW, (unsigned long)(need - 1), rc);
		ok(res == NULL, "  and *result is NULL");
		ok(buf[0] == 'X', "  and the caller's buffer was NOT touched");
		ok(pw.pw_name == saved.pw_name,
		    "  and the caller's struct was NOT touched");

		/* Exactly enough is enough. */
		memset(buf, 0, sizeof(buf));
		res = NULL;
		rc = getpwnam_r(KNOWN_PW, &pw, buf, need, &res);
		ok(rc == 0 && res == &pw,
		    "getpwnam_r(%s, buflen=%lu) -> 0 (the exact size works)",
		    KNOWN_PW, (unsigned long)need);
	}

	ok(getpwnam_r(KNOWN_PW, &pw, buf, sizeof(buf), NULL) == EINVAL,
	    "getpwnam_r(result == NULL) -> EINVAL");
	ok(getpwnam_r(NULL, &pw, buf, sizeof(buf), &res) == EINVAL,
	    "getpwnam_r(name == NULL) -> EINVAL");
	ok(getpwnam_r("", &pw, buf, sizeof(buf), &res) == EINVAL,
	    "getpwnam_r(name == \"\") -> EINVAL");
	ok(getpwnam_r(KNOWN_PW, NULL, buf, sizeof(buf), &res) == EINVAL,
	    "getpwnam_r(pwd == NULL) -> EINVAL");
	ok(getpwnam_r(KNOWN_PW, &pw, NULL, 100, &res) == EINVAL,
	    "getpwnam_r(buffer == NULL) -> EINVAL");
	ok(getpwnam_r(KNOWN_PW, &pw, buf, 0, &res) == EINVAL,
	    "getpwnam_r(buflen == 0) -> EINVAL");

	/* Group, same contract. */
	memset(buf, 'X', sizeof(buf));
	res = (struct passwd *)(uintptr_t)0x1;
	rc = getgrnam_r("no-such-group-ravynos-test", &gr, buf, sizeof(buf),
	    &gres);
	ok(rc == 0 && gres == NULL, "getgrnam_r(miss) rc=%d, *result NULL", rc);
	ok(buf[0] == 'X', "  and the caller buffer was NOT touched");

	memset(buf, 0, sizeof(buf));
	rc = getgrnam_r(KNOWN_GRP, &gr, buf, sizeof(buf), &gres);
	ok(rc == 0 && gres == &gr, "getgrnam_r(\"%s\") rc=%d", KNOWN_GRP, rc);
	if (rc == 0 && gres == &gr) {
		ok(gr.gr_mem != NULL, "  gr_mem is not NULL");
		if (gr.gr_mem[0] != NULL) {
			ok(inbuf(gr.gr_mem[0], buf, sizeof(buf)),
			    "  gr_mem[0] points into the caller's buffer");
			ok(gr.gr_mem[1] == NULL ||
			    inbuf(gr.gr_mem[1], buf, sizeof(buf)),
			    "  gr_mem[1] points into the caller's buffer");
		} else {
			printf("       (this group has no members)\n");
		}
		ok((uintptr_t)gr.gr_mem % sizeof(char *) == 0,
		    "  the gr_mem array itself is pointer-aligned");
	}

	memset(tiny, 'Y', sizeof(tiny));
	res = (struct passwd *)(uintptr_t)0x1;
	gres = (struct group *)(uintptr_t)0x1;
	rc = getgrnam_r(KNOWN_GRP, &gr, tiny, sizeof(tiny), &gres);
	ok(rc == ERANGE, "getgrnam_r(%s, buflen=8) -> ERANGE (%d)", KNOWN_GRP,
	    rc);
	ok(tiny[0] == 'Y', "  and the caller's buffer was NOT touched");
	ok(gres == NULL, "  and *result is NULL");

	ok(getgrnam_r(KNOWN_GRP, &gr, buf, sizeof(buf), NULL) == EINVAL,
	    "getgrnam_r(result == NULL) -> EINVAL");
	ok(getgrnam_r(NULL, &gr, buf, sizeof(buf), &gres) == EINVAL,
	    "getgrnam_r(name == NULL) -> EINVAL");
	ok(getgrnam_r(KNOWN_GRP, NULL, buf, sizeof(buf), &gres) == EINVAL,
	    "getgrnam_r(grp == NULL) -> EINVAL");
}

static void
test_fget(void)
{
	FILE *fp;
	struct passwd *pw, pwr;
	struct passwd *res;
	struct group *gr, grr;
	struct group *gres;
	int n;

	ok(fgetpwent(NULL) == NULL, "fgetpwent(NULL) -> NULL");
	ok(fgetgrent(NULL) == NULL, "fgetgrent(NULL) -> NULL");

	fp = fopen(_RAVYN_TEST_PW_PATH, "r");
	ok(fp != NULL, "fopen(\"%s\")", _RAVYN_TEST_PW_PATH);
	if (fp == NULL)
		return;
	for (n = 0; (pw = fgetpwent(fp)) != NULL; n++)
		;
	ok(n > 0, "fgetpwent() read %d entries from a caller-supplied stream",
	    n);
	ok(fgetpwent(fp) == NULL, "fgetpwent() still NULL at end of file");
	ok(getpwnam(KNOWN_PW) != NULL,
	    "fgetpwent() did not disturb the getpwnam() stream");

	rewind(fp);
	memset(buf, 0, sizeof(buf));
	ok(fgetpwent_r(fp, &pwr, buf, sizeof(buf), &res) == 0 && res == &pwr,
	    "fgetpwent_r() -> 0 with the caller's struct");
	fclose(fp);

	fp = fopen(_RAVYN_TEST_GR_PATH, "r");
	ok(fp != NULL, "fopen(\"%s\")", _RAVYN_TEST_GR_PATH);
	if (fp == NULL)
		return;
	for (n = 0; (gr = fgetgrent(fp)) != NULL; n++)
		;
	ok(n > 0, "fgetgrent() read %d entries", n);
	rewind(fp);
	memset(buf, 0, sizeof(buf));
	ok(fgetgrent_r(fp, &grr, buf, sizeof(buf), &gres) == 0 &&
	    gres == &grr, "fgetgrent_r() -> 0 with the caller's struct");
	fclose(fp);
}

static void
test_from_id(void)
{
	char *n;

	n = user_from_uid(KNOWN_PW_UID, 0);
	ok(n != NULL && strcmp(n, KNOWN_PW) == 0, "user_from_uid(%u, 0) -> %s",
	    (unsigned)KNOWN_PW_UID, n != NULL ? n : "(null)");
	n = user_from_uid(KNOWN_PW_UID, 1);
	ok(n != NULL && strcmp(n, KNOWN_PW) == 0, "user_from_uid(%u, 1) -> %s",
	    (unsigned)KNOWN_PW_UID, n != NULL ? n : "(null)");

	n = user_from_uid(NO_SUCH_UID, 0);
	ok(n != NULL && strcmp(n, "2147483646") == 0,
	    "user_from_uid(2147483646, 0) -> \"%s\" (the decimal id)",
	    n != NULL ? n : "(null)");
	ok(user_from_uid(NO_SUCH_UID, 1) == NULL,
	    "user_from_uid(2147483646, 1) -> NULL");


	n = group_from_gid(KNOWN_GRP_GID, 0);
	ok(n != NULL && strcmp(n, KNOWN_GRP) == 0, "group_from_gid(%u, 0) -> %s",
	    (unsigned)KNOWN_GRP_GID, n != NULL ? n : "(null)");
	n = group_from_gid(NO_SUCH_GID, 0);
	ok(n != NULL && strcmp(n, "2147483645") == 0,
	    "group_from_gid(2147483645, 0) -> \"%s\" (the decimal id)",
	    n != NULL ? n : "(null)");
	ok(group_from_gid(NO_SUCH_GID, 1) == NULL,
	    "group_from_gid(2147483645, 1) -> NULL");
}

static void
test_setgrfile(void)
{
	struct group *gr;

	setgrfile("/nonexistent/ravynos-group-file");
	ok(getgrent() == NULL,
	    "after setgrfile(\"/nonexistent/...\"): getgrent() -> NULL");
	ok(getgrgid(KNOWN_GRP_GID) == NULL,
	    "  and getgrgid(%u) -> NULL", (unsigned)KNOWN_GRP_GID);

	setgrfile(_RAVYN_TEST_GR_PATH);
	gr = getgrgid(KNOWN_GRP_GID);
	ok(gr != NULL, "after setgrfile(real group file): getgrgid(%u) -> %s",
	    (unsigned)KNOWN_GRP_GID, gr != NULL ? gr->gr_name : "(null)");
}

/* ------------------------------------------------------------------ */
/* Cases that need a database with known-bad lines in it.		      */
/* ------------------------------------------------------------------ */

static void
test_fixture(void)
{
#ifndef _RAVYN_TEST_FIXTURE
	skip("malformed / NIS / over-long cases (this is the real-database build)");
#else
	/*
	 * The order the fixture's entries must come out in. The fourth is
	 * the 300-character name, which is written as NULL because spelling
	 * it out here would be a second copy of the rule that gen_fixture in
	 * test/run-tests.sh already states; it is compared by prefix and
	 * length below instead.
	 */
	static const char *const order[] = {
		"froot", "fdaemon", "fempty", NULL, "fmember",
		"fnomembers", "overlong"
	};
	struct passwd *pw;
	struct group *gr;
	char want[301];
	int i, n;

	setpwent();
	for (i = 0; i < (int)(sizeof(order) / sizeof(order[0])); i++) {
		pw = getpwent();
		if (order[i] == NULL) {
			ok(pw != NULL && strlen(pw->pw_name) == 300 &&
			    strncmp(pw->pw_name, "flongname", 9) == 0,
			    "fixture getpwent()[%d] -> the 300-character name "
			    "(%d chars)", i,
			    pw != NULL ? (int)strlen(pw->pw_name) : 0);
			continue;
		}
		ok(pw != NULL && strcmp(pw->pw_name, order[i]) == 0,
		    "fixture getpwent()[%d] -> %s (expected %s)", i,
		    pw != NULL ? pw->pw_name : "(null)", order[i]);
	}
	ok(getpwent() == NULL, "fixture getpwent() -> NULL after the last entry");

	/*
	 * A '+' line is seven fields, so without the '+'/'-' skip it parses
	 * as an entry named "+" with uid 0 and getpwuid(0) matches it. That
	 * is the whole point of this check.
	 */
	ok(getpwuid(0) == NULL,
	    "fixture getpwuid(0) -> NULL ('+' line skipped, not uid 0)");
	ok(getpwnam("+") == NULL, "fixture getpwnam(\"+\") -> NULL");
	ok(getpwnam("-") == NULL, "fixture getpwnam(\"-\") -> NULL");
	ok(getgrgid(0) == NULL, "fixture getgrgid(0) -> NULL ('+' line skipped)");
	ok(getgrnam("+") == NULL, "fixture getgrnam(\"+\") -> NULL");
	ok(getgrnam("-") == NULL, "fixture getgrnam(\"-\") -> NULL");

	/* A line with fewer than the mandatory fields is not an entry. */
	ok(getpwnam("short") == NULL,
	    "fixture getpwnam(\"short\") -> NULL (only three fields)");
	ok(getpwnam("badsid") == NULL,
	    "fixture getpwnam(\"badsid\") -> NULL (non-numeric uid)");
	ok(getpwnam("nagid") == NULL,
	    "fixture getpwnam(\"nagid\") -> NULL (non-numeric gid)");
	ok(getgrnam("gshort") == NULL,
	    "fixture getgrnam(\"gshort\") -> NULL (only three fields)");
	ok(getgrnam("gbadgid") == NULL,
	    "fixture getgrnam(\"gbadgid\") -> NULL (non-numeric gid)");

	/* gecos, dir and shell are optional. */
	pw = getpwnam("fempty");
	ok(pw != NULL && pw->pw_uid == 4005,
	    "fixture getpwnam(\"fempty\") -> uid %u (an entry may stop at gid)",
	    pw != NULL ? (unsigned)pw->pw_uid : 0u);

	/*
	 * A name longer than any small fixed field buffer must still be
	 * reachable by a lookup. The fixture's is "flongname" followed by
	 * 291 'z' -- 300 characters, past the 256 that used to be the field
	 * buffer size. test/run-tests.sh's gen_fixture writes it from the
	 * same rule; it is stated on both sides so the two cannot drift.
	 */
	memcpy(want, "flongname", 9);
	memset(want + 9, 'z', sizeof(want) - 9 - 1);
	want[sizeof(want) - 1] = '\0';
	pw = getpwnam(want);
	ok(pw != NULL && strcmp(pw->pw_name, want) == 0,
	    "fixture getpwnam(%d-char name) -> %s", (int)strlen(want),
	    pw != NULL ? "found, name intact" : "NULL");

	/*
	 * The over-long line: the first 1023 bytes are a valid entry and the
	 * rest of the line is a SECOND valid entry. Without the drain,
	 * getpwnam("ftail") would find it.
	 */
	pw = getpwnam("overlong");
	ok(pw != NULL && pw->pw_uid == 4008,
	    "fixture getpwnam(\"overlong\") -> uid %u (the line itself parsed)",
	    pw != NULL ? (unsigned)pw->pw_uid : 0u);
	ok(getpwnam("ftail") == NULL,
	    "fixture getpwnam(\"ftail\") -> NULL (the over-long line was drained)");

	gr = getgrnam("fgroup");
	ok(gr != NULL && gr->gr_gid == 5000,
	    "fixture getgrnam(\"fgroup\") -> gid %u",
	    gr != NULL ? (unsigned)gr->gr_gid : 0u);
	if (gr != NULL) {
		ok(gr->gr_mem != NULL, "  gr_mem is not NULL");
		ok(gr->gr_mem[0] != NULL && strcmp(gr->gr_mem[0], "fa") == 0,
		    "  gr_mem[0] == \"%s\"", gr->gr_mem[0]);
		ok(gr->gr_mem[1] != NULL && strcmp(gr->gr_mem[1], "fb") == 0,
		    "  gr_mem[1] == \"%s\"", gr->gr_mem[1]);
		ok(gr->gr_mem[2] == NULL, "  gr_mem[2] == NULL (terminated)");
	}
	gr = getgrnam("fnomembers");
	ok(gr != NULL && gr->gr_mem != NULL && gr->gr_mem[0] == NULL,
	    "fixture group with no members: gr_mem is an empty array, not NULL");

	setpwent();
	for (n = 0; getpwent() != NULL; n++)
		;
	ok(n == (int)(sizeof(order) / sizeof(order[0])),
	    "fixture: the whole database iterated as %d entries, none of them "
	    "a rejected line", n);
	pw = getpwent();
	ok(pw != NULL && strcmp(pw->pw_name, "froot") == 0,
	    "  then rewound to the first entry again");
	endpwent();
#endif
}

/* ------------------------------------------------------------------ */

int
main(void)
{
	printf("== databases: %s / %s -- %s build\n\n", _RAVYN_TEST_PW_PATH,
	    _RAVYN_TEST_GR_PATH, BUILD_TAG);

	test_pwnam();
	test_pwuid();
	test_pwent_rewind();
	test_grnam();
	test_grgid();
	test_grent_rewind();
	test_r_forms();
	test_fget();
	test_from_id();
	test_setgrfile();
	test_fixture();

	printf("\n%d checks, %d failures, %d skips\n", checks, failures, skips);
	return failures != 0;
}
