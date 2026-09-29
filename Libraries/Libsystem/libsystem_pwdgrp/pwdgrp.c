/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * libsystem_pwdgrp -- the ravynOS passwd and group database.
 *
 * A real, self-contained implementation of the POSIX (plus the historical
 * BSD) passwd/group database API, reading /etc/passwd and /etc/group. It
 * exists because the real implementations -- getpwnam, getpwuid, getpwent,
 * getgrnam, getgrgid, getgrent, user_from_uid, group_from_gid -- do live in
 * this tree, in Libraries/Libsystem/libsystem_info/libinfo.a, but that
 * archive is self-referential onto the SystemInformation framework and
 * libsystem_info/MISSING_DEPS.md already records it as blocked on absent
 * libxpc / libsystem_trace / libsystem_notify. Eight functions are not worth
 * that closure, so they are implemented here, with no si_* dependency and
 * no dispatch, no notify and no mach ports.
 *
 * See README.md in this directory for why the parser is shaped the way it
 * is, and for the handover note about BSD/bin/sh/ravynos_port.c.
 *
 * This file is the single owner of these symbols. Two definitions of one
 * symbol is a link error.
 */

#include <sys/types.h>

#include <errno.h>
#include <grp.h>
#include <limits.h>
#include <pwd.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/*
 * The SDK declares only the POSIX surface. This one declares the rest of
 * what is defined below, so every definition here has a visible prototype
 * and -Wmissing-prototypes stays quiet -- which matters, because the two
 * spellings of a function drifting apart is exactly how a library ends up
 * with two different getpwnam signatures.
 */
#include "libsystem_pwdgrp.h"

/*
 * The databases. Overridable so the parser can be tested against a known
 * database -- NIS lines, over-long lines, malformed entries, a missing file
 * -- without touching the real one. The defaults are the real thing and no
 * production build passes anything else.
 */
#ifndef _RAVYN_PASSWD_FILE
#define	_RAVYN_PASSWD_FILE "/etc/passwd"
#endif
#ifndef _RAVYN_GROUP_FILE
#define	_RAVYN_GROUP_FILE "/etc/group"
#endif

/*
 * A field can never be longer than the line it came from, so every field
 * buffer is sized at the line length. A smaller fixed bound (256 used to be
 * enough to try) silently truncates a long name, and then the entry is
 * unreachable: a lookup by the full name compares against the truncated copy
 * and fails.
 */
#define	_RAV_LINEMAX	1024

/*
 * gr_mem is a NULL-terminated array of pointers into the member text. Both
 * are static, so the array needs a static bound. This one is provably
 * lossless rather than merely generous: an over-long line is drained and
 * discarded, so no line longer than _RAV_LINEMAX is ever parsed, and a
 * member list inside such a line cannot hold more than _RAV_LINEMAX/2
 * entries (each costs at least one character plus its comma).
 */
#define	_RAV_GROUPMEMMAX	(_RAV_LINEMAX / 2)

/* ------------------------------------------------------------------ */
/* Shared line reading and field splitting			      */
/* ------------------------------------------------------------------ */

/*
 * Read one line into buf, without its newline. Returns 1 for a line, 0 at
 * end of file (or on a read error -- fopen's errno is already set and the
 * caller has nothing to add to it).
 *
 * Two things fgets leaves behind must not reach the fields.
 *
 * The trailing newline. The LAST field of a line has no colon after it, so
 * the field extractor falls back to "copy to end of string" and copies the
 * '\n' along with it -- pw_shell would come back as "/bin/sh\n", and
 * anything that strcmp()s or exec's it is wrong.
 *
 * An over-long line. fgets stops at the buffer size, so the tail of a longer
 * line is returned by the NEXT call and parsed as though it were an entry
 * of its own, with a garbage name and a garbage uid that a real lookup
 * could match. Drain the rest of the line so it is discarded instead.
 */
static int
_rav_readline(FILE *fp, char *buf, size_t bufsz)
{
	size_t len;

	if (fgets(buf, (int)bufsz, fp) == NULL)
		return 0;

	len = strlen(buf);
	while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
		buf[--len] = '\0';

	if (len + 1 == bufsz) {
		int c;

		while ((c = fgetc(fp)) != EOF && c != '\n')
			;
	}
	return 1;
}

/* Copy one colon-delimited field out of *sp into buf; advance *sp past it. */
static char *
_rav_field(char **sp, char *buf, size_t bufsz)
{
	char *s = *sp, *e;
	size_t n;

	e = strchr(s, ':');
	if (e == NULL)
		e = s + strlen(s);
	n = (size_t)(e - s);
	if (n >= bufsz)
		n = bufsz - 1;
	memcpy(buf, s, n);
	buf[n] = '\0';
	*sp = (*e == ':') ? e + 1 : e;
	return buf;
}

/*
 * Parse a decimal id. The whole field must be decimal digits: a field that
 * is empty, signed, or has trailing garbage is a malformed line, not an id.
 * strtoul alone would answer 0 for "root" and 0 for "" alike, and a uid-0
 * entry fabricated out of a malformed line is exactly the kind of silent
 * misparse this parser must not do. Overflow is rejected for the same
 * reason: a wrapped id is a wrong id, not a near-enough one.
 */
static int
_rav_uid(const char *s, uid_t *out)
{
	unsigned long v = 0;
	const char *p;

	if (*s == '\0')
		return -1;
	for (p = s; *p != '\0'; p++) {
		if (*p < '0' || *p > '9')
			return -1;
		if (v > (ULONG_MAX - (unsigned long)(*p - '0')) / 10)
			return -1;
		v = v * 10 + (unsigned long)(*p - '0');
	}
	*out = (uid_t)v;
	return 0;
}

static int
_rav_gid(const char *s, gid_t *out)
{
	uid_t v;

	if (_rav_uid(s, &v) != 0)
		return -1;
	*out = (gid_t)v;
	return 0;
}

/* Copy s into *bufp, advance *bufp past it, and return where it landed. */
static char *
_rav_stow(char **bufp, const char *s)
{
	char *dst = *bufp;
	size_t n = strlen(s) + 1;

	memcpy(dst, s, n);
	*bufp = dst + n;
	return dst;
}

/* How many ':' separators a line has, i.e. how many fields it can yield. */
static int
_rav_ncolons(const char *s)
{
	int n = 0;

	for (; *s != '\0'; s++) {
		if (*s == ':')
			n++;
	}
	return n;
}

/* ------------------------------------------------------------------ */
/* passwd database						      */
/* ------------------------------------------------------------------ */

static char _pw_line[_RAV_LINEMAX];
static char _pw_name[_RAV_LINEMAX];
static char _pw_passwd[_RAV_LINEMAX];
static char _pw_gecos[_RAV_LINEMAX];
static char _pw_dir[_RAV_LINEMAX];
static char _pw_shell[_RAV_LINEMAX];
static char _pw_class[_RAV_LINEMAX] = "";
static char _pw_uid[_RAV_LINEMAX];
static char _pw_gid[_RAV_LINEMAX];

static struct passwd _pw_ent;

static FILE *_pw_fp;
static int _pw_rewind;

void
setpwent(void)
{
	if (_pw_fp != NULL)
		rewind(_pw_fp);
	else
		_pw_fp = fopen(_RAVYN_PASSWD_FILE, "r");
	_pw_rewind = 0;
}

int
setpassent(int unused)
{
	(void)unused;
	setpwent();
	return 0;
}

void
endpwent(void)
{
	if (_pw_fp != NULL) {
		(void)fclose(_pw_fp);
		_pw_fp = NULL;
	}
	_pw_rewind = 0;
}

/*
 * Parse one passwd line. Returns 0 on success and -1 if the line is not an
 * entry, in which case _pw_ent is left exactly as the previous entry left it
 * -- a rejected line must not be observable.
 */
static int
_pw_parse(char *line)
{
	char *p = line;
	uid_t uid;
	gid_t gid;

	/* Comment or blank. */
	if (*p == '#' || *p == '\0')
		return -1;

	/*
	 * NIS. A line beginning with '+' or '-' is a netgroup directive --
	 * "+user" pulls a NIS entry in, "-user" keeps it out -- and is not a
	 * passwd entry. Splitting it on colons would yield an entry named "+"
	 * with uid 0, which a getpwuid(0) would then match.
	 */
	if (*p == '+' || *p == '-')
		return -1;

	_rav_field(&p, _pw_name, sizeof(_pw_name));
	_rav_field(&p, _pw_passwd, sizeof(_pw_passwd));
	_rav_field(&p, _pw_uid, sizeof(_pw_uid));
	_rav_field(&p, _pw_gid, sizeof(_pw_gid));

	/*
	 * The four mandatory fields -- name, passwd, uid, gid -- must be
	 * there, and the ids must be ids. Anything past gid is optional, so
	 * an entry may legitimately stop at gid; what may not happen is a
	 * short line, whose missing fields would otherwise be
	 * indistinguishable from empty ones.
	 */
	if (_rav_ncolons(line) < 3)
		return -1;
	if (_pw_name[0] == '\0')
		return -1;
	if (_rav_uid(_pw_uid, &uid) != 0)
		return -1;
	if (_rav_gid(_pw_gid, &gid) != 0)
		return -1;

	/* The rest is optional: an entry can stop at gid. */
	_rav_field(&p, _pw_gecos, sizeof(_pw_gecos));
	_rav_field(&p, _pw_dir, sizeof(_pw_dir));
	_rav_field(&p, _pw_shell, sizeof(_pw_shell));

	_pw_ent.pw_name = _pw_name;
	_pw_ent.pw_passwd = _pw_passwd;
	_pw_ent.pw_uid = uid;
	_pw_ent.pw_gid = gid;
	_pw_ent.pw_change = (time_t)-1;
	_pw_ent.pw_class = _pw_class;
	_pw_ent.pw_gecos = _pw_gecos;
	_pw_ent.pw_dir = _pw_dir;
	_pw_ent.pw_shell = _pw_shell;
	_pw_ent.pw_expire = (time_t)-1;
	return 0;
}

/*
 * The next entry, or NULL at end of file. A call made after a NULL return
 * starts the database over: POSIX specifies that behaviour and callers
 * depend on it, so the stream is kept open and rewound rather than being
 * closed at end of file and reopened.
 */
struct passwd *
getpwent(void)
{
	if (_pw_fp == NULL)
		setpwent();
	else if (_pw_rewind) {
		rewind(_pw_fp);
		_pw_rewind = 0;
	}
	if (_pw_fp == NULL)
		return NULL;

	for (;;) {
		if (!_rav_readline(_pw_fp, _pw_line, sizeof(_pw_line))) {
			/*
			 * End of file: remember it, so that the NEXT call
			 * rewinds and starts the database over.
			 */
			_pw_rewind = 1;
			return NULL;
		}
		if (_pw_parse(_pw_line) == 0)
			return &_pw_ent;
	}
}

/* The same parse over a caller-supplied stream. */
struct passwd *
fgetpwent(FILE *stream)
{
	if (stream == NULL)
		return NULL;
	while (_rav_readline(stream, _pw_line, sizeof(_pw_line))) {
		if (_pw_parse(_pw_line) == 0)
			return &_pw_ent;
	}
	return NULL;
}

struct passwd *
getpwnam(const char *name)
{
	struct passwd *pw;

	if (name == NULL || *name == '\0')
		return NULL;
	setpwent();
	while ((pw = getpwent()) != NULL) {
		if (strcmp(pw->pw_name, name) == 0) {
			endpwent();
			return pw;
		}
	}
	endpwent();
	return NULL;
}

struct passwd *
getpwuid(uid_t uid)
{
	struct passwd *pw;

	setpwent();
	while ((pw = getpwent()) != NULL) {
		if (pw->pw_uid == uid) {
			endpwent();
			return pw;
		}
	}
	endpwent();
	return NULL;
}

/*
 * Serialise the entry currently held in _pw_ent into the caller's buffer and
 * fill in the caller's struct passwd. Returns 0, or ERANGE if the buffer is
 * too small -- in which case the caller's buffer and struct are untouched.
 */
static int
_pw_copy_out(struct passwd *pwd, char *buffer, size_t buflen)
{
	char *p = buffer;
	size_t need;

	/* Six string fields, each needing room for its NUL. */
	need = strlen(_pw_name) + strlen(_pw_passwd) + strlen(_pw_gecos) +
	    strlen(_pw_dir) + strlen(_pw_shell) + strlen(_pw_class) + 6;
	if (need > buflen)
		return ERANGE;

	pwd->pw_name = _rav_stow(&p, _pw_name);
	pwd->pw_passwd = _rav_stow(&p, _pw_passwd);
	pwd->pw_gecos = _rav_stow(&p, _pw_gecos);
	pwd->pw_dir = _rav_stow(&p, _pw_dir);
	pwd->pw_shell = _rav_stow(&p, _pw_shell);
	pwd->pw_class = _rav_stow(&p, _pw_class);

	pwd->pw_uid = _pw_ent.pw_uid;
	pwd->pw_gid = _pw_ent.pw_gid;
	pwd->pw_change = _pw_ent.pw_change;
	pwd->pw_expire = _pw_ent.pw_expire;
	return 0;
}

int
getpwnam_r(const char *name, struct passwd *pwd, char *buffer, size_t buflen,
    struct passwd **result)
{
	struct passwd *pw;
	int rc;

	/* A null `result' is the one argument that is a hard error: the caller
	 * has given us nowhere to report "found" or "not found". */
	if (result == NULL)
		return EINVAL;
	*result = NULL;
	if (name == NULL || *name == '\0')
		return EINVAL;
	if (pwd == NULL || buffer == NULL || buflen == 0)
		return EINVAL;

	if ((pw = getpwnam(name)) == NULL)
		return 0;			/* not found: success, *result NULL */

	if ((rc = _pw_copy_out(pwd, buffer, buflen)) != 0)
		return rc;
	*result = pwd;
	return 0;
}

int
getpwuid_r(uid_t uid, struct passwd *pwd, char *buffer, size_t buflen,
    struct passwd **result)
{
	struct passwd *pw;
	int rc;

	if (result == NULL)
		return EINVAL;
	*result = NULL;
	if (pwd == NULL || buffer == NULL || buflen == 0)
		return EINVAL;

	if ((pw = getpwuid(uid)) == NULL)
		return 0;			/* not found: success, *result NULL */

	if ((rc = _pw_copy_out(pwd, buffer, buflen)) != 0)
		return rc;
	*result = pwd;
	return 0;
}

int
getpwent_r(struct passwd *pwd, char *buffer, size_t buflen,
    struct passwd **result)
{
	struct passwd *pw;
	int rc;

	if (result == NULL)
		return EINVAL;
	*result = NULL;
	if (pwd == NULL || buffer == NULL || buflen == 0)
		return EINVAL;

	if ((pw = getpwent()) == NULL)
		return 0;			/* end of file: *result NULL */

	if ((rc = _pw_copy_out(pwd, buffer, buflen)) != 0)
		return rc;
	*result = pwd;
	return 0;
}

int
fgetpwent_r(FILE *stream, struct passwd *pwd, char *buffer, size_t buflen,
    struct passwd **result)
{
	struct passwd *pw;
	int rc;

	if (result == NULL)
		return EINVAL;
	*result = NULL;
	if (pwd == NULL || buffer == NULL || buflen == 0)
		return EINVAL;
	if (stream == NULL)
		return EINVAL;

	if ((pw = fgetpwent(stream)) == NULL)
		return 0;			/* end of file: *result NULL */

	if ((rc = _pw_copy_out(pwd, buffer, buflen)) != 0)
		return rc;
	*result = pwd;
	return 0;
}

/* ------------------------------------------------------------------ */
/* group database						      */
/* ------------------------------------------------------------------ */

static char _gr_line[_RAV_LINEMAX];
static char _gr_name[_RAV_LINEMAX];
static char _gr_passwd[_RAV_LINEMAX];
static char _gr_gid[_RAV_LINEMAX];
static char _gr_members[_RAV_LINEMAX];
static char *_gr_memptr[_RAV_GROUPMEMMAX + 1];

static struct group _gr_ent;

static FILE *_gr_fp;
static int _gr_rewind;

static const char _gr_default_file[] = _RAVYN_GROUP_FILE;
static char _gr_file[_RAV_LINEMAX];

static const char *
_gr_path(void)
{
	return _gr_file[0] != '\0' ? _gr_file : _gr_default_file;
}

/*
 * Point the group database at another file. Declared by the ravynOS SDK's
 * own <grp.h> and defined by no archive in this tree, so it is a link
 * failure waiting to happen; it is the runtime form of the same
 * redirection the _RAVYN_GROUP_FILE macro gives at compile time.
 *
 * The open stream is closed rather than left pointing at the old file, so
 * that "used by subsequent calls" means what it says. The next getgrent()
 * sees no stream and opens the new path.
 */
void
setgrfile(const char *path)
{
	size_t n;

	if (path == NULL || *path == '\0')
		return;
	n = strlen(path);
	if (n >= sizeof(_gr_file))
		n = sizeof(_gr_file) - 1;
	memcpy(_gr_file, path, n);
	_gr_file[n] = '\0';

	if (_gr_fp != NULL) {
		(void)fclose(_gr_fp);
		_gr_fp = NULL;
	}
	_gr_rewind = 0;
}

static int
_gr_parse(char *line)
{
	char *p = line;
	char *m;
	gid_t gid;
	size_t n;

	/* Comment or blank. */
	if (*p == '#' || *p == '\0')
		return -1;

	/* NIS directive, same as the passwd database. */
	if (*p == '+' || *p == '-')
		return -1;

	_rav_field(&p, _gr_name, sizeof(_gr_name));
	_rav_field(&p, _gr_passwd, sizeof(_gr_passwd));
	_rav_field(&p, _gr_gid, sizeof(_gr_gid));

	/*
	 * name:passwd:gid:members -- all four must be present. The members
	 * field may be EMPTY, but the colon that introduces it may not be
	 * missing: a three-field line is a malformed line, not a group with
	 * no members. Every real /etc/group line carries the fourth colon
	 * even when the list is empty, which is why this is the rule rather
	 * than a guess.
	 */
	if (_rav_ncolons(line) < 3)
		return -1;
	if (_gr_name[0] == '\0')
		return -1;
	if (_rav_gid(_gr_gid, &gid) != 0)
		return -1;

	/* The rest of the line is the comma-separated member list. */
	_rav_field(&p, _gr_members, sizeof(_gr_members));

	for (n = 0, m = _gr_members; ; ) {
		char *c = strchr(m, ',');

		if (c != NULL)
			*c = '\0';
		if (*m != '\0' && n < _RAV_GROUPMEMMAX)
			_gr_memptr[n++] = m;
		if (c == NULL)
			break;
		m = c + 1;
	}
	_gr_memptr[n] = NULL;

	_gr_ent.gr_name = _gr_name;
	_gr_ent.gr_passwd = _gr_passwd;
	_gr_ent.gr_gid = gid;
	/*
	 * Never NULL. A group with no members gets an empty array, because
	 * every caller that walks gr_mem is entitled to walk it to the
	 * terminating NULL, and a NULL gr_mem is a crash in all of them.
	 */
	_gr_ent.gr_mem = _gr_memptr;
	return 0;
}

void
setgrent(void)
{
	if (_gr_fp != NULL)
		rewind(_gr_fp);
	else
		_gr_fp = fopen(_gr_path(), "r");
	_gr_rewind = 0;
}

int
setgroupent(int unused)
{
	(void)unused;
	setgrent();
	return 0;
}

void
endgrent(void)
{
	if (_gr_fp != NULL) {
		(void)fclose(_gr_fp);
		_gr_fp = NULL;
	}
	_gr_rewind = 0;
}

struct group *
getgrent(void)
{
	if (_gr_fp == NULL)
		setgrent();
	else if (_gr_rewind) {
		rewind(_gr_fp);
		_gr_rewind = 0;
	}
	if (_gr_fp == NULL)
		return NULL;

	for (;;) {
		if (!_rav_readline(_gr_fp, _gr_line, sizeof(_gr_line))) {
			_gr_rewind = 1;
			return NULL;
		}
		if (_gr_parse(_gr_line) == 0)
			return &_gr_ent;
	}
}

struct group *
fgetgrent(FILE *stream)
{
	if (stream == NULL)
		return NULL;
	while (_rav_readline(stream, _gr_line, sizeof(_gr_line))) {
		if (_gr_parse(_gr_line) == 0)
			return &_gr_ent;
	}
	return NULL;
}

struct group *
getgrnam(const char *name)
{
	struct group *gr;

	if (name == NULL || *name == '\0')
		return NULL;
	setgrent();
	while ((gr = getgrent()) != NULL) {
		if (strcmp(gr->gr_name, name) == 0) {
			endgrent();
			return gr;
		}
	}
	endgrent();
	return NULL;
}

struct group *
getgrgid(gid_t gid)
{
	struct group *gr;

	setgrent();
	while ((gr = getgrent()) != NULL) {
		if (gr->gr_gid == gid) {
			endgrent();
			return gr;
		}
	}
	endgrent();
	return NULL;
}

/*
 * Serialise the entry currently held in _gr_ent into the caller's buffer and
 * fill in the caller's struct group. The gr_mem array lives in the caller's
 * buffer too, so the array has to land on a real pointer boundary, and the
 * padding that takes must be part of the size test rather than discovered
 * after the buffer has already been written.
 */
static int
_gr_copy_out(struct group *grp, char *buffer, size_t buflen)
{
	char *p = buffer;
	uintptr_t base = (uintptr_t)buffer;
	size_t i, n, strbytes, off;
	char **mp;

	for (i = 0, strbytes = 0; _gr_memptr[i] != NULL; i++)
		strbytes += strlen(_gr_memptr[i]) + 1;
	n = i + 1;				/* slots, including the NULL */
	strbytes += strlen(_gr_name) + strlen(_gr_passwd) + 2;

	/* The lowest offset in the buffer at which a char * may be stored. */
	off = (size_t)((base + sizeof(char *) - 1) &
	    ~(uintptr_t)(sizeof(char *) - 1));
	off = (off - (size_t)base) + strbytes;
	off += (sizeof(char *) - (off % sizeof(char *))) % sizeof(char *);

	if (off + n * sizeof(char *) > buflen)
		return ERANGE;

	grp->gr_name = _rav_stow(&p, _gr_name);
	grp->gr_passwd = _rav_stow(&p, _gr_passwd);

	/* The offset was computed above so that this address really is pointer
	 * aligned; the cast is the only way to get there from a char buffer. */
	mp = (char **)(void *)(buffer + off);
	for (i = 0; i + 1 < n; i++)
		mp[i] = _rav_stow(&p, _gr_memptr[i]);
	mp[i] = NULL;

	grp->gr_gid = _gr_ent.gr_gid;
	grp->gr_mem = mp;
	return 0;
}

int
getgrnam_r(const char *name, struct group *grp, char *buffer, size_t bufsize,
    struct group **result)
{
	struct group *g;
	int rc;

	if (result == NULL)
		return EINVAL;
	*result = NULL;
	if (name == NULL || *name == '\0')
		return EINVAL;
	if (grp == NULL || buffer == NULL || bufsize == 0)
		return EINVAL;

	if ((g = getgrnam(name)) == NULL)
		return 0;			/* not found: success, *result NULL */

	if ((rc = _gr_copy_out(grp, buffer, bufsize)) != 0)
		return rc;
	*result = grp;
	return 0;
}

int
getgrgid_r(gid_t gid, struct group *grp, char *buffer, size_t bufsize,
    struct group **result)
{
	struct group *g;
	int rc;

	if (result == NULL)
		return EINVAL;
	*result = NULL;
	if (grp == NULL || buffer == NULL || bufsize == 0)
		return EINVAL;

	if ((g = getgrgid(gid)) == NULL)
		return 0;			/* not found: success, *result NULL */

	if ((rc = _gr_copy_out(grp, buffer, bufsize)) != 0)
		return rc;
	*result = grp;
	return 0;
}

int
getgrent_r(struct group *grp, char *buffer, size_t bufsize, struct group **result)
{
	struct group *g;
	int rc;

	if (result == NULL)
		return EINVAL;
	*result = NULL;
	if (grp == NULL || buffer == NULL || bufsize == 0)
		return EINVAL;

	if ((g = getgrent()) == NULL)
		return 0;			/* end of file: *result NULL */

	if ((rc = _gr_copy_out(grp, buffer, bufsize)) != 0)
		return rc;
	*result = grp;
	return 0;
}

int
fgetgrent_r(FILE *stream, struct group *grp, char *buffer, size_t bufsize,
    struct group **result)
{
	struct group *g;
	int rc;

	if (result == NULL)
		return EINVAL;
	*result = NULL;
	if (grp == NULL || buffer == NULL || bufsize == 0)
		return EINVAL;
	if (stream == NULL)
		return EINVAL;

	if ((g = fgetgrent(stream)) == NULL)
		return 0;			/* end of file: *result NULL */

	if ((rc = _gr_copy_out(grp, buffer, bufsize)) != 0)
		return rc;
	*result = grp;
	return 0;
}

/* ------------------------------------------------------------------ */
/* name from id							      */
/* ------------------------------------------------------------------ */

/*
 * Transcribed from libsystem_info/lookup.subproj/libinfo.c:3356, the real
 * implementation: the name if the id is known, NULL if it is not and the
 * second argument says so, and otherwise the decimal id. Both the name and
 * the number are static storage, so the result is overwritten by the next
 * lookup -- that is the real behaviour, and ls/rm (which pass 0) rely on
 * getting a printable string for an id they do not recognise.
 */
char *
user_from_uid(uid_t uid, int nouser)
{
	struct passwd *pw;
	static char buf[16];

	pw = getpwuid(uid);
	if (pw != NULL)
		return pw->pw_name;
	if (nouser)
		return NULL;
	snprintf(buf, sizeof(buf), "%u", (unsigned int)uid);
	return buf;
}

char *
group_from_gid(gid_t gid, int nogroup)
{
	struct group *gr;
	static char buf[16];

	gr = getgrgid(gid);
	if (gr != NULL)
		return gr->gr_name;
	if (nogroup)
		return NULL;
	snprintf(buf, sizeof(buf), "%u", (unsigned int)gid);
	return buf;
}
