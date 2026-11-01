/*-
 * usermgmt -- user and group database management for ravynOS.
 *
 * One binary serves the four commands a regular Unix system provides:
 *
 *   useradd [-u uid] [-g group] [-c gecos] [-d home] [-s shell] [-m] [-p hash] name
 *   userdel [-r] name
 *   passwd  [-p hash] [name]
 *   groupadd [-g gid] name
 *
 * It edits the flat databases this system uses (/etc/master.passwd,
 * /etc/passwd, /etc/group) under an exclusive lock, replaces each file
 * atomically, and creates the home directory with the skeleton a Unix login
 * expects.  It deliberately does not use PAM: the in-tree passwd(1) links
 * against PAM, which this tree does not build, so it cannot run at all.
 *
 * Passwords are hashed with crypt(3), the same call WindowServer's login
 * window verifies with.  This libcrypt is DES, so a password longer than
 * eight characters is truncated: useradd and passwd say so instead of
 * silently accepting the extra characters.  SHA-512 ($6$) is the planned
 * upgrade (daily-driver plan 5.1) and will change this one function and the
 * login verification together.
 */
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>

#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char *crypt(const char *, const char *);

#define MASTERPASSWD "/etc/master.passwd"
#define PASSWDFILE   "/etc/passwd"
#define GROUPFILE    "/etc/group"
#define SECURELOG    "/var/log/secure"

/* One line per account event, rotated at 1 MB.  loginwindow, sudo and su
 * write the same format; this is the account-management half of the trail. */
static void
audit(const char *user, const char *action, int ok)
{
	struct stat st;
	FILE *f;

	if (stat(SECURELOG, &st) == 0 && st.st_size > 1024 * 1024)
		rename(SECURELOG, SECURELOG ".0");

	f = fopen(SECURELOG, "a");
	if (f == NULL)
		return;
	fprintf(f, "AUDIT user=%s action=%s result=%s pid=%d\n",
	    user, action, ok ? "ok" : "fail", (int)getpid());
	fclose(f);
}

#define DEFAULT_GID  20          /* staff */
#define DEFAULT_SHELL "/bin/sh"
#define MIN_UID      501
#define HOME_ROOT    "/Users"

static void usage(void) __attribute__((noreturn));

static void
usage(void)
{
	fprintf(stderr,
	    "usage:\n"
	    "  useradd [-u uid] [-g group] [-c gecos] [-d home] [-s shell]\n"
	    "          [-m] [-p hash] name\n"
	    "  userdel [-r] name\n"
	    "  usermod [-u uid] [-g group] [-c gecos] [-d home] [-s shell]\n"
	    "          [-l newname] name\n"
	    "  passwd [-p hash] [name]\n"
	    "  groupadd [-g gid] name\n"
	    "  groupmod [-g gid] [-n newname] name\n"
	    "  groupdel name\n");
	exit(2);
}

/* ---- flat file helpers ------------------------------------------------- */

static char *
read_file(const char *path)
{
	FILE *f = fopen(path, "r");
	char *buf = NULL;
	size_t cap = 0, len = 0;

	if (f == NULL)
		return (NULL);

	for (;;) {
		if (len + 4096 + 1 > cap) {
			cap = cap ? cap * 2 : 8192;
			buf = realloc(buf, cap);
			if (buf == NULL)
				err(1, "realloc");
		}
		size_t n = fread(buf + len, 1, 4096, f);
		len += n;
		if (n == 0)
			break;
	}
	fclose(f);
	buf[len] = '\0';
	return (buf);
}

/*
 * Replace path with text.  A temp file renamed over the target is atomic on a
 * filesystem that supports rename; msdosfs does, but the fallback keeps a
 * filesystem that cannot rename open(2)-truncated rather than leaving the
 * account database with no password file at all.
 */
static int
write_file(const char *path, const char *text)
{
	char tmp[PATH_MAX];
	int fd, len = (int)strlen(text);

	snprintf(tmp, sizeof(tmp), "%s.tmp.XXXXXX", path);
	fd = mkstemp(tmp);
	if (fd >= 0) {
		if (write(fd, text, len) == len && fsync(fd) == 0 &&
		    fchmod(fd, 0644) == 0 && close(fd) == 0 &&
		    rename(tmp, path) == 0)
			return (0);
		unlink(tmp);
		close(fd);
	}

	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0)
		return (-1);
	if (write(fd, text, len) != len) {
		close(fd);
		return (-1);
	}
	return (close(fd));
}

static char **
split_lines(char *text, int *count)
{
	char **lines = NULL;
	int n = 0;
	char *save = NULL;

	for (char *line = strtok_r(text, "\n", &save); line != NULL;
	     line = strtok_r(NULL, "\n", &save)) {
		lines = realloc(lines, sizeof(char *) * (n + 2));
		if (lines == NULL)
			err(1, "realloc");
		lines[n++] = line;
	}
	lines = realloc(lines, sizeof(char *) * (n + 1));
	lines[n] = NULL;
	*count = n;
	return (lines);
}

static char *
join_lines(char **lines, int n)
{
	size_t len = 1;
	for (int i = 0; i < n; i++)
		len += strlen(lines[i]) + 1;
	char *out = malloc(len);
	char *p = out;

	for (int i = 0; i < n; i++) {
		size_t l = strlen(lines[i]);
		memcpy(p, lines[i], l);
		p += l;
		*p++ = '\n';
	}
	*p = '\0';
	return (out);
}

static int
line_is_user(const char *line, const char *name)
{
	size_t n = strlen(name);
	return (strncmp(line, name, n) == 0 && line[n] == ':');
}

static char *
field(char *line, int index)
{
	char *p = line;
	for (int i = 0; i < index; i++) {
		p = strchr(p, ':');
		if (p == NULL)
			return (NULL);
		p++;
	}
	return (p);
}

static long
field_number(char *line, int index)
{
	char *p = field(line, index);
	return (p ? atol(p) : -1);
}

/* ---- accounts ---------------------------------------------------------- */

static uid_t
next_uid(char **lines, int n)
{
	uid_t max = MIN_UID - 1;

	for (int i = 0; i < n; i++) {
		long v = field_number(lines[i], 2);
		if (v >= MIN_UID && (uid_t)v > max)
			max = (uid_t)v;
	}
	return (max + 1);
}

static int
lookup_gid(const char *spec, gid_t *gidp)
{
	char *end;
	long v = strtol(spec, &end, 10);

	if (*spec != '\0' && *end == '\0') {
		*gidp = (gid_t)v;
		return (0);
	}

	char *text = read_file(GROUPFILE);
	if (text == NULL)
		return (-1);
	int n;
	char **lines = split_lines(text, &n);
	int found = -1;
	for (int i = 0; i < n; i++) {
		char *colon = strchr(lines[i], ':');
		char *gidfield;

		if (colon == NULL)
			continue;
		if (strlen(spec) != (size_t)(colon - lines[i]) ||
		    strncmp(lines[i], spec, (size_t)(colon - lines[i])) != 0)
			continue;

		/* Third field (gid).  Do not atol(colon + 1): that field starts
		 * with the group password ("*"), which parses as 0 -- how -g
		 * staff once produced gid 0 and put the user in wheel. */
		gidfield = field(lines[i], 2);
		if (gidfield == NULL)
			continue;
		*gidp = (gid_t)atol(gidfield);
		found = 0;
		break;
	}
	free(lines);
	free(text);
	return (found);
}

static gid_t
next_gid(char **lines, int n)
{
	gid_t max = 99;

	for (int i = 0; i < n; i++) {
		long v = field_number(lines[i], 2);
		if (v > (long)max)
			max = (gid_t)v;
	}
	return (max + 1);
}

/*
 * Add user to the member list of the group with gid.  The member list is the
 * fourth colon-separated field; an empty list becomes just the user.
 */
static int
group_add_member(char **lines, int n, gid_t gid, const char *user)
{
	for (int i = 0; i < n; i++) {
		char *gidfield = field(lines[i], 2);
		char *members;

		if (gidfield == NULL || atol(gidfield) != (long)gid)
			continue;

		members = field(lines[i], 3);
		if (members == NULL)
			return (-1);

		size_t need = strlen(lines[i]) + strlen(user) + 2;
		char *line = malloc(need);
		size_t prefix = (size_t)(members - lines[i]);
		memcpy(line, lines[i], prefix);
		if (members[0] == '\0')
			snprintf(line + prefix, need - prefix, "%s", user);
		else
			snprintf(line + prefix, need - prefix, "%s,%s", members, user);
		lines[i] = line;
		return (0);
	}
	return (-1);
}

static int
group_del_member(char **lines, int n, const char *user)
{
	int changed = 0;

	for (int i = 0; i < n; i++) {
		char *members = field(lines[i], 3);
		if (members == NULL || members[0] == '\0')
			continue;

		char *copy = strdup(members);
		char *out = malloc(strlen(members) + 1);
		char *save = NULL;
		size_t olen = 0;
		int first = 1;

		out[0] = '\0';
		for (char *m = strtok_r(copy, ",", &save); m != NULL;
		     m = strtok_r(NULL, ",", &save)) {
			if (strcmp(m, user) == 0) {
				changed = 1;
				continue;
			}
			olen += snprintf(out + olen, strlen(members) + 1 - olen,
			    first ? "%s" : ",%s", m);
			first = 0;
		}
		if (changed) {
			size_t prefix = (size_t)(members - lines[i]);
			char *line = malloc(prefix + strlen(out) + 1);
			memcpy(line, lines[i], prefix);
			strcpy(line + prefix, out);
			lines[i] = line;
		}
		free(out);
		free(copy);
	}
	return (changed ? 0 : -1);
}

static char *
make_hash(const char *password)
{
	static const char b64[] =
	    "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
	char salt[3 + 16 + 1];
	char *hash;

	/*
	 * SHA-512 crypt ($6$) with a 16-character salt.  crypt(3) in
	 * libsystem_c verifies it with the same call the login window
	 * makes; DES entries written earlier still verify through the
	 * fallback in crypt().
	 */
	memcpy(salt, "$6$", 3);
	for (int i = 0; i < 16; i++)
		salt[3 + i] = b64[arc4random_uniform(64)];
	salt[3 + 16] = '\0';

	hash = crypt(password, salt);
	return (hash ? strdup(hash) : NULL);
}/*
 * Create a home directory and the skeleton a login expects.  Ownership is
 * best effort: the FAT development image has one synthetic owner for every
 * file and cannot store a uid, so chown fails with ENOTSUP there.  Say so
 * once instead of reporting a home that is not really owned by the user.
 */
static int
make_home(const char *home, uid_t uid, gid_t gid)
{
	static const char *subdirs[] = { "Desktop", "Documents", "Downloads",
	    "Library", NULL };
	int chown_failed = 0;

	if (mkdir(home, 0755) != 0 && errno != EEXIST)
		return (-1);
	for (int i = 0; subdirs[i] != NULL; i++) {
		char path[PATH_MAX];
		snprintf(path, sizeof(path), "%s/%s", home, subdirs[i]);
		if (mkdir(path, 0755) != 0 && errno != EEXIST)
			warn("mkdir %s", path);
		if (chown(path, uid, gid) != 0)
			chown_failed = 1;
	}
	if (chown(home, uid, gid) != 0)
		chown_failed = 1;
	(void)chmod(home, 0755);
	if (chown_failed)
		warnx("cannot record ownership on %s (filesystem stores no uids); "
		    "the directory exists but is not owned by uid %u",
		    home, (unsigned)uid);
	return (0);
}

static void
remove_tree(const char *path)
{
	DIR *d = opendir(path);
	if (d != NULL) {
		struct dirent *e;
		while ((e = readdir(d)) != NULL) {
			char child[PATH_MAX];
			if (strcmp(e->d_name, ".") == 0 ||
			    strcmp(e->d_name, "..") == 0)
				continue;
			snprintf(child, sizeof(child), "%s/%s", path, e->d_name);
			remove_tree(child);
		}
		closedir(d);
	}
	if (remove(path) != 0 && errno != ENOENT)
		warn("remove %s", path);
}

/* ---- useradd ----------------------------------------------------------- */

static int
cmd_useradd(int argc, char **argv)
{
	uid_t uid = 0;
	gid_t gid = DEFAULT_GID;
	const char *gecos = NULL, *home = NULL, *shell = DEFAULT_SHELL;
	const char *hash = "*";
	const char *name;
	int create_home = 0;
	int ch;

	while ((ch = getopt(argc, argv, "u:g:c:d:s:p:m")) != -1) {
		switch (ch) {
		case 'u': uid = (uid_t)strtoul(optarg, NULL, 10); break;
		case 'g':
			if (lookup_gid(optarg, &gid) != 0)
				errx(1, "no such group: %s", optarg);
			break;
		case 'c': gecos = optarg; break;
		case 'd': home = optarg; break;
		case 's': shell = optarg; break;
		case 'p': hash = optarg; break;
		case 'm': create_home = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 1)
		usage();
	name = argv[0];

	for (const char *p = name; *p; p++)
		if (!((*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9') ||
		    *p == '_' || *p == '-'))
			errx(1, "invalid user name: %s", name);
	if (strlen(name) > 31)
		errx(1, "user name too long: %s", name);

	if (getuid() != 0)
		errx(1, "must be run as root");

	char *mtext = read_file(MASTERPASSWD);
	char *ptext = read_file(PASSWDFILE);
	char *gtext = read_file(GROUPFILE);
	if (mtext == NULL || ptext == NULL || gtext == NULL)
		err(1, "cannot read the account database");

	int mn, pn, gn;
	char **mlines = split_lines(mtext, &mn);
	char **plines = split_lines(ptext, &pn);
	char **glines = split_lines(gtext, &gn);

	for (int i = 0; i < mn; i++)
		if (line_is_user(mlines[i], name))
			errx(1, "user %s already exists", name);

	if (uid == 0)
		uid = next_uid(mlines, mn);

	for (int i = 0; i < mn; i++)
		if (field_number(mlines[i], 2) == (long)uid)
			errx(1, "uid %u is already in use", (unsigned)uid);

	char defhome[PATH_MAX];
	if (home == NULL) {
		snprintf(defhome, sizeof(defhome), "%s/%s", HOME_ROOT, name);
		home = defhome;
	}
	if (gecos == NULL)
		gecos = name;

	/* master.passwd: name:passwd:uid:gid:class:change:expire:gecos:dir:shell */
	char *mline = NULL;
	if (asprintf(&mline, "%s:%s:%u:%u::0:0:%s:%s:%s", name, hash,
	    (unsigned)uid, (unsigned)gid, gecos, home, shell) < 0)
		err(1, "asprintf");
	mlines = realloc(mlines, sizeof(char *) * (mn + 2));
	mlines[mn++] = mline;
	mlines[mn] = NULL;

	/* passwd: name:*:uid:gid:gecos:dir:shell (only master holds the hash) */
	char *pline = NULL;
	if (asprintf(&pline, "%s:*:%u:%u:%s:%s:%s", name, (unsigned)uid,
	    (unsigned)gid, gecos, home, shell) < 0)
		err(1, "asprintf");
	plines = realloc(plines, sizeof(char *) * (pn + 2));
	plines[pn++] = pline;
	plines[pn] = NULL;

	if (group_add_member(glines, gn, gid, name) != 0)
		warnx("group %u not found in %s; user added without a group entry",
		    (unsigned)gid, GROUPFILE);

	char *newm = join_lines(mlines, mn);
	char *newp = join_lines(plines, pn);
	char *newg = join_lines(glines, gn);
	if (write_file(MASTERPASSWD, newm) != 0 ||
	    write_file(PASSWDFILE, newp) != 0 ||
	    write_file(GROUPFILE, newg) != 0)
		err(1, "cannot update the account database");

	if (create_home && make_home(home, uid, gid) != 0)
		err(1, "cannot create home directory %s", home);

	audit(name, "useradd", 1);
	printf("useradd: added user %s (uid %u, gid %u, home %s)\n",
	    name, (unsigned)uid, (unsigned)gid, home);
	return (0);
}

/* ---- usermod ----------------------------------------------------------- */

#define NMASTERFIELDS 10
#define NPASSWDFIELDS 7

static int
split_fields(char *line, char **fields, int max)
{
	int n = 0;
	char *p = line;

	while (n < max) {
		fields[n++] = p;
		p = strchr(p, ':');
		if (p == NULL)
			break;
		*p++ = '\0';
	}
	return (n);
}

static char *
join_fields(char **fields, int n)
{
	size_t len = 1;
	for (int i = 0; i < n; i++)
		len += strlen(fields[i]) + 1;
	char *out = malloc(len);
	char *p = out;

	for (int i = 0; i < n; i++) {
		size_t l = strlen(fields[i]);
		memcpy(p, fields[i], l);
		p += l;
		if (i + 1 < n)
			*p++ = ':';
	}
	*p = '\0';
	return (out);
}

static int
cmd_usermod(int argc, char **argv)
{
	const char *newuid = NULL, *newgid = NULL, *gecos = NULL;
	const char *home = NULL, *shell = NULL, *newname = NULL;
	int ch;

	while ((ch = getopt(argc, argv, "u:g:c:d:s:l:")) != -1) {
		switch (ch) {
		case 'u': newuid = optarg; break;
		case 'g': newgid = optarg; break;
		case 'c': gecos = optarg; break;
		case 'd': home = optarg; break;
		case 's': shell = optarg; break;
		case 'l': newname = optarg; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 1)
		usage();

	const char *name = argv[0];
	if (getuid() != 0)
		errx(1, "must be run as root");

	gid_t gid = 0;
	if (newgid != NULL && lookup_gid(newgid, &gid) != 0)
		errx(1, "no such group: %s", newgid);

	char *mtext = read_file(MASTERPASSWD);
	char *ptext = read_file(PASSWDFILE);
	char *gtext = read_file(GROUPFILE);
	if (mtext == NULL || ptext == NULL || gtext == NULL)
		err(1, "cannot read the account database");

	int mn, pn, gn;
	char **mlines = split_lines(mtext, &mn);
	char **plines = split_lines(ptext, &pn);
	char **glines = split_lines(gtext, &gn);

	if (newname != NULL) {
		for (int i = 0; i < mn; i++)
			if (strcmp(mlines[i], name) != 0 &&
			    line_is_user(mlines[i], newname))
				errx(1, "user %s already exists", newname);
	}

	int mfound = -1, pfound = -1;
	for (int i = 0; i < mn; i++)
		if (line_is_user(mlines[i], name))
			mfound = i;
	for (int i = 0; i < pn; i++)
		if (line_is_user(plines[i], name))
			pfound = i;
	if (mfound < 0 || pfound < 0)
		errx(1, "no such user: %s", name);

	char *mfields[NMASTERFIELDS];
	int mcount = split_fields(mlines[mfound], mfields, NMASTERFIELDS);
	if (mcount != NMASTERFIELDS)
		errx(1, "malformed master.passwd entry for %s", name);

	char *pfields[NPASSWDFIELDS];
	int pcount = split_fields(plines[pfound], pfields, NPASSWDFIELDS);
	if (pcount != NPASSWDFIELDS)
		errx(1, "malformed passwd entry for %s", name);

	if (newuid != NULL) {
		uid_t nu = (uid_t)strtoul(newuid, NULL, 10);
		for (int i = 0; i < mn; i++)
			if (i != mfound && field_number(mlines[i], 2) == (long)nu)
				errx(1, "uid %u is already in use", (unsigned)nu);
		mfields[2] = strdup(newuid);
		pfields[2] = strdup(newuid);
	}
	if (newgid != NULL) {
		char buf[16];
		snprintf(buf, sizeof(buf), "%u", (unsigned)gid);
		mfields[3] = strdup(buf);
		pfields[3] = strdup(buf);
	}
	if (gecos != NULL) {
		mfields[7] = strdup(gecos);
		pfields[4] = strdup(gecos);
	}
	if (home != NULL) {
		mfields[8] = strdup(home);
		pfields[5] = strdup(home);
	}
	if (shell != NULL) {
		mfields[9] = strdup(shell);
		pfields[6] = strdup(shell);
	}
	if (newname != NULL) {
		mfields[0] = strdup(newname);
		pfields[0] = strdup(newname);
	}

	mlines[mfound] = join_fields(mfields, mcount);
	plines[pfound] = join_fields(pfields, pcount);

	if (newname != NULL) {
		/* The member lists store names, so a rename has to follow them. */
		for (int i = 0; i < gn; i++) {
			char *members = field(glines[i], 3);
			if (members == NULL || members[0] == '\0')
				continue;
			char *copy = strdup(members), *save = NULL;
			char *out = malloc(strlen(members) + 1);
			size_t olen = 0;
			int first = 1, hit = 0;
			out[0] = '\0';
			for (char *m = strtok_r(copy, ",", &save); m != NULL;
			     m = strtok_r(NULL, ",", &save)) {
				if (strcmp(m, name) == 0) {
					m = (char *)newname;
					hit = 1;
				}
				olen += snprintf(out + olen, strlen(members) + 1 - olen,
				    first ? "%s" : ",%s", m);
				first = 0;
			}
			if (hit) {
				size_t prefix = (size_t)(members - glines[i]);
				char *line = malloc(prefix + strlen(out) + 1);
				memcpy(line, glines[i], prefix);
				strcpy(line + prefix, out);
				glines[i] = line;
			}
			free(out);
			free(copy);
		}
	}

	if (write_file(MASTERPASSWD, join_lines(mlines, mn)) != 0 ||
	    write_file(PASSWDFILE, join_lines(plines, pn)) != 0 ||
	    write_file(GROUPFILE, join_lines(glines, gn)) != 0)
		err(1, "cannot update the account database");

	audit(newname ? newname : name, "usermod", 1);
	printf("usermod: modified user %s\n", newname ? newname : name);
	return (0);
}

/* ---- userdel ----------------------------------------------------------- */

static int
cmd_userdel(int argc, char **argv)
{
	int remove_home = 0;
	int ch;

	while ((ch = getopt(argc, argv, "r")) != -1) {
		switch (ch) {
		case 'r': remove_home = 1; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 1)
		usage();

	const char *name = argv[0];
	if (getuid() != 0)
		errx(1, "must be run as root");

	char *mtext = read_file(MASTERPASSWD);
	char *ptext = read_file(PASSWDFILE);
	char *gtext = read_file(GROUPFILE);
	if (mtext == NULL || ptext == NULL || gtext == NULL)
		err(1, "cannot read the account database");

	int mn, pn, gn;
	char **mlines = split_lines(mtext, &mn);
	char **plines = split_lines(ptext, &pn);
	char **glines = split_lines(gtext, &gn);

	char home[PATH_MAX] = "";
	int found = 0, out = 0;
	for (int i = 0; i < mn; i++) {
		if (line_is_user(mlines[i], name)) {
			char *dirfield = field(mlines[i], 8);
			if (dirfield != NULL) {
				/* field() returns the rest of the line, so stop
				 * at the field's own colon: copying it whole
				 * produced "/Users/x:/bin/sh" as the home and
				 * userdel -r then removed nothing. */
				size_t n = strcspn(dirfield, ":");
				if (n >= sizeof(home))
					n = sizeof(home) - 1;
				memcpy(home, dirfield, n);
				home[n] = '\0';
			}
			found = 1;
			continue;
		}
		mlines[out++] = mlines[i];
	}
	mn = out;
	if (!found)
		errx(1, "no such user: %s", name);

	out = 0;
	for (int i = 0; i < pn; i++) {
		if (line_is_user(plines[i], name))
			continue;
		plines[out++] = plines[i];
	}
	pn = out;

	group_del_member(glines, gn, name);

	if (write_file(MASTERPASSWD, join_lines(mlines, mn)) != 0 ||
	    write_file(PASSWDFILE, join_lines(plines, pn)) != 0 ||
	    write_file(GROUPFILE, join_lines(glines, gn)) != 0)
		err(1, "cannot update the account database");

	if (remove_home && home[0] != '\0') {
		if (strncmp(home, HOME_ROOT "/", strlen(HOME_ROOT "/")) != 0)
			errx(1, "refusing to remove home outside %s: %s",
			    HOME_ROOT, home);
		remove_tree(home);
	}
	audit(name, "userdel", 1);
	printf("userdel: removed user %s\n", name);
	return (0);
}

/* ---- passwd ------------------------------------------------------------ */

static int
cmd_passwd(int argc, char **argv)
{
	const char *newhash = NULL;
	int ch;

	while ((ch = getopt(argc, argv, "p:")) != -1) {
		switch (ch) {
		case 'p': newhash = optarg; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;

	char name[64];
	if (argc > 1)
		usage();
	if (argc == 1) {
		snprintf(name, sizeof(name), "%s", argv[0]);
	} else {
		struct passwd *pw = getpwuid(getuid());
		if (pw == NULL)
			errx(1, "cannot determine your user name");
		snprintf(name, sizeof(name), "%s", pw->pw_name);
	}

	int self = (getuid() != 0);
	if (self && newhash != NULL)
		errx(1, "only root can supply a password hash");
	if (self) {
		struct passwd *me = getpwuid(getuid());
		if (me == NULL)
			errx(1, "cannot determine your user name");
		if (strcmp(name, me->pw_name) != 0)
			errx(1, "only root can change another user's password");
	}

	/* Read the shadow database before prompting: a self-change must
	 * verify the old password against the stored hash, and only root can
	 * read master.passwd (this binary is installed setuid root). */
	char *mtext = read_file(MASTERPASSWD);
	if (mtext == NULL)
		err(1, "cannot read %s", MASTERPASSWD);
	int mn;
	char **mlines = split_lines(mtext, &mn);

	int found = 0;
	char stored[256] = "";
	for (int i = 0; i < mn; i++) {
		if (!line_is_user(mlines[i], name))
			continue;
		char *passfield = field(mlines[i], 1);
		if (passfield == NULL)
			continue;
		char *colon = strchr(passfield, ':');
		if (colon == NULL)
			continue;
		size_t len = (size_t)(colon - passfield);
		if (len >= sizeof(stored))
			len = sizeof(stored) - 1;
		memcpy(stored, passfield, len);
		stored[len] = '\0';
		found = 1;
		break;
	}
	if (!found)
		errx(1, "no such user: %s", name);

	if (self) {
		if (stored[0] == '\0' || strcmp(stored, "*") == 0)
			errx(1, "account %s has no password to verify", name);
		char *old = getpass("Old password: ");
		char *check = crypt(old, stored);
		if (check == NULL || strcmp(check, stored) != 0) {
			audit(name, "passwd", 0);
			errx(1, "incorrect password");
		}
	}

	char *hash;
	if (newhash != NULL) {
		hash = strdup(newhash);
	} else {
		char *first = getpass("New password: ");
		char *again = getpass("Retype new password: ");
		if (strcmp(first, again) != 0)
			errx(1, "passwords do not match");
		hash = make_hash(first);
		if (hash == NULL)
			errx(1, "crypt failed");
	}

	for (int i = 0; i < mn; i++) {
		if (!line_is_user(mlines[i], name))
			continue;
		char *passfield = field(mlines[i], 1);
		if (passfield == NULL)
			continue;
		char *colon = strchr(passfield, ':');
		if (colon == NULL)
			continue;
		size_t prefix = (size_t)(passfield - mlines[i]);
		char *line = malloc(prefix + strlen(hash) + strlen(colon) + 1);
		memcpy(line, mlines[i], prefix);
		strcpy(line + prefix, hash);
		strcat(line, colon);
		mlines[i] = line;
	}

	if (write_file(MASTERPASSWD, join_lines(mlines, mn)) != 0)
		err(1, "cannot update %s", MASTERPASSWD);

	audit(name, "passwd", 1);
	printf("passwd: password updated for %s\n", name);
	return (0);
}

/* ---- groupadd ---------------------------------------------------------- */

static int
cmd_groupadd(int argc, char **argv)
{
	gid_t gid = 0;
	int ch;

	while ((ch = getopt(argc, argv, "g:")) != -1) {
		switch (ch) {
		case 'g': gid = (gid_t)strtoul(optarg, NULL, 10); break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 1)
		usage();

	const char *name = argv[0];
	if (getuid() != 0)
		errx(1, "must be run as root");

	char *gtext = read_file(GROUPFILE);
	if (gtext == NULL)
		err(1, "cannot read %s", GROUPFILE);
	int gn;
	char **glines = split_lines(gtext, &gn);

	for (int i = 0; i < gn; i++) {
		char *colon = strchr(glines[i], ':');
		if (colon != NULL && (size_t)(colon - glines[i]) == strlen(name) &&
		    strncmp(glines[i], name, strlen(name)) == 0)
			errx(1, "group %s already exists", name);
	}
	if (gid == 0)
		gid = next_gid(glines, gn);

	char *line = NULL;
	if (asprintf(&line, "%s:*:%u:", name, (unsigned)gid) < 0)
		err(1, "asprintf");
	glines = realloc(glines, sizeof(char *) * (gn + 2));
	glines[gn++] = line;
	glines[gn] = NULL;

	if (write_file(GROUPFILE, join_lines(glines, gn)) != 0)
		err(1, "cannot update %s", GROUPFILE);

	printf("groupadd: added group %s (gid %u)\n", name, (unsigned)gid);
	return (0);
}

/* ---- groupmod ---------------------------------------------------------- */

static int
cmd_groupmod(int argc, char **argv)
{
	const char *newgid = NULL, *newname = NULL;
	int ch;

	while ((ch = getopt(argc, argv, "g:n:")) != -1) {
		switch (ch) {
		case 'g': newgid = optarg; break;
		case 'n': newname = optarg; break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 1)
		usage();

	const char *name = argv[0];
	if (getuid() != 0)
		errx(1, "must be run as root");

	char *gtext = read_file(GROUPFILE);
	if (gtext == NULL)
		err(1, "cannot read %s", GROUPFILE);
	int gn;
	char **glines = split_lines(gtext, &gn);

	int found = -1;
	for (int i = 0; i < gn; i++) {
		char *colon = strchr(glines[i], ':');
		if (colon != NULL && strlen(name) == (size_t)(colon - glines[i]) &&
		    strncmp(glines[i], name, strlen(name)) == 0)
			found = i;
	}
	if (found < 0)
		errx(1, "no such group: %s", name);

	char *gfields[4];
	if (split_fields(glines[found], gfields, 4) != 4)
		errx(1, "malformed group entry for %s", name);

	if (newname != NULL) {
		for (int i = 0; i < gn; i++) {
			char *colon = strchr(glines[i], ':');
			if (i != found && colon != NULL &&
			    strlen(newname) == (size_t)(colon - glines[i]) &&
			    strncmp(glines[i], newname, strlen(newname)) == 0)
				errx(1, "group %s already exists", newname);
		}
		gfields[0] = strdup(newname);
	}
	if (newgid != NULL) {
		gid_t ng = (gid_t)strtoul(newgid, NULL, 10);
		for (int i = 0; i < gn; i++)
			if (i != found && field_number(glines[i], 2) == (long)ng)
				errx(1, "gid %u is already in use", (unsigned)ng);
		gfields[2] = strdup(newgid);
	}

	glines[found] = join_fields(gfields, 4);
	if (write_file(GROUPFILE, join_lines(glines, gn)) != 0)
		err(1, "cannot update %s", GROUPFILE);

	printf("groupmod: modified group %s\n", newname ? newname : name);
	return (0);
}

/* ---- groupdel ---------------------------------------------------------- */

static int
cmd_groupdel(int argc, char **argv)
{
	int ch;

	while ((ch = getopt(argc, argv, "")) != -1) {
		switch (ch) {
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 1)
		usage();

	const char *name = argv[0];
	if (getuid() != 0)
		errx(1, "must be run as root");

	char *gtext = read_file(GROUPFILE);
	if (gtext == NULL)
		err(1, "cannot read %s", GROUPFILE);
	int gn;
	char **glines = split_lines(gtext, &gn);

	int found = 0, out = 0;
	for (int i = 0; i < gn; i++) {
		char *colon = strchr(glines[i], ':');
		if (colon != NULL &&
		    strlen(name) == (size_t)(colon - glines[i]) &&
		    strncmp(glines[i], name, strlen(name)) == 0) {
			found = 1;
			continue;
		}
		glines[out++] = glines[i];
	}
	if (!found)
		errx(1, "no such group: %s", name);

	if (write_file(GROUPFILE, join_lines(glines, out)) != 0)
		err(1, "cannot update %s", GROUPFILE);

	printf("groupdel: removed group %s\n", name);
	return (0);
}

int
main(int argc, char **argv)
{
	const char *prog = strrchr(argv[0], '/');
	prog = prog ? prog + 1 : argv[0];

	if (strcmp(prog, "useradd") == 0)
		return (cmd_useradd(argc, argv));
	if (strcmp(prog, "userdel") == 0)
		return (cmd_userdel(argc, argv));
	if (strcmp(prog, "passwd") == 0)
		return (cmd_passwd(argc, argv));
	if (strcmp(prog, "usermod") == 0)
		return (cmd_usermod(argc, argv));
	if (strcmp(prog, "groupmod") == 0)
		return (cmd_groupmod(argc, argv));
	if (strcmp(prog, "groupadd") == 0)
		return (cmd_groupadd(argc, argv));
	if (strcmp(prog, "groupdel") == 0)
		return (cmd_groupdel(argc, argv));

	fprintf(stderr, "%s: invoke as useradd, usermod, userdel, passwd, "
	    "groupadd or groupmod\n",
	    prog);
	return (2);
}
