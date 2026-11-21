/* SPDX-License-Identifier: BSD-2-Clause */
/* chown(1) for ravynOS: BSD/bin/chown was not imported, but the image's
 * install steps and ports need it.  Accepts owner, :group, owner:group and
 * numeric ids, walks -R without following symlinks. */
#include <sys/types.h>
#include <sys/stat.h>

#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <grp.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static int rflag;
static int hflag;
static uid_t uid;
static gid_t gid;
static int uid_set, gid_set;
static int rc;

static void usage(void);

static int
parse_owner(const char *arg)
{
	char *copy, *group, *end;
	struct passwd *pw;
	struct group *gr;
	long id;

	if ((copy = strdup(arg)) == NULL)
		err(EX_OSERR, NULL);
	if ((group = strchr(copy, ':')) != NULL)
		*group++ = '\0';
	if (*copy != '\0') {
		if ((pw = getpwnam(copy)) != NULL)
			uid = pw->pw_uid;
		else {
			errno = 0;
			id = strtol(copy, &end, 10);
			if (errno != 0 || *end != '\0' || id < 0)
				errx(EX_USAGE, "unknown user: %s", copy);
			uid = (uid_t)id;
		}
		uid_set = 1;
	}
	if (group != NULL) {
		if (*group != '\0') {
			if ((gr = getgrnam(group)) != NULL)
				gid = gr->gr_gid;
			else {
				errno = 0;
				id = strtol(group, &end, 10);
				if (errno != 0 || *end != '\0' || id < 0)
					errx(EX_USAGE, "unknown group: %s", group);
				gid = (gid_t)id;
			}
			gid_set = 1;
		}
	}
	free(copy);
	return 0;
}

static int
do_chown(const char *path)
{
	struct stat sb;
	int error;

	if ((hflag ? lstat(path, &sb) : stat(path, &sb)) == -1) {
		warn("%s", path);
		return 1;
	}
	if (hflag ? lchown(path, uid_set ? uid : (uid_t)-1,
	    gid_set ? gid : (gid_t)-1) == -1 :
	    chown(path, uid_set ? uid : (uid_t)-1,
	    gid_set ? gid : (gid_t)-1) == -1) {
		error = errno;
		warn("%s", path);
		errno = error;
		return 1;
	}
	return 0;
}

static int
walk(const char *path)
{
	DIR *dir;
	struct dirent *dp;
	char *sub;
	int ret = 0;

	ret |= do_chown(path);
	if (!rflag)
		return ret;
	if ((dir = opendir(path)) == NULL) {
		warn("%s", path);
		return 1;
	}
	while ((dp = readdir(dir)) != NULL) {
		if (strcmp(dp->d_name, ".") == 0 || strcmp(dp->d_name, "..") == 0)
			continue;
		if (asprintf(&sub, "%s/%s", path, dp->d_name) == -1)
			err(EX_OSERR, NULL);
		ret |= walk(sub);
		free(sub);
	}
	closedir(dir);
	return ret;
}

int
main(int argc, char *argv[])
{
	int ch, i;

	while ((ch = getopt(argc, argv, "Rfhv")) != -1) {
		switch (ch) {
		case 'R': rflag = 1; break;
		case 'h': hflag = 1; break;
		case 'v': case 'f': break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc < 2)
		usage();
	parse_owner(argv[0]);
	for (i = 1; i < argc; i++)
		rc |= walk(argv[i]);
	return rc;
}

static void
usage(void)
{
	fprintf(stderr, "usage: chown [-R] [-h] owner[:group] file ...\n");
	exit(EX_USAGE);
}
