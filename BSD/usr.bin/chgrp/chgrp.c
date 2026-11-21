/* SPDX-License-Identifier: BSD-2-Clause */
/* chgrp(1) for ravynOS: accepts a group name or numeric gid, -R for
 * recursion, -h to change the link itself.  Mirrors chown(1)'s traversal. */
#include <sys/types.h>
#include <sys/stat.h>

#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static int rflag;
static int hflag;
static gid_t gid;

static void
usage(void)
{
	fprintf(stderr, "usage: chgrp [-fhR] group file ...\n");
	exit(EX_USAGE);
}

static gid_t
parse_group(const char *arg)
{
	struct group *gr;
	char *end;
	long id;

	if ((gr = getgrnam(arg)) != NULL)
		return gr->gr_gid;
	errno = 0;
	id = strtol(arg, &end, 10);
	if (errno != 0 || *end != '\0' || id < 0)
		errx(EX_USAGE, "unknown group: %s", arg);
	return (gid_t)id;
}

static int
do_chgrp(const char *path)
{
	struct stat sb;

	if ((hflag ? lstat(path, &sb) : stat(path, &sb)) == -1) {
		warn("%s", path);
		return 1;
	}
	if ((hflag ? lchown(path, (uid_t)-1, gid) : chown(path,
	    (uid_t)-1, gid)) == -1) {
		warn("%s", path);
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

	ret |= do_chgrp(path);
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
	int ch, ret = 0;

	while ((ch = getopt(argc, argv, "fhR")) != -1) {
		switch (ch) {
		case 'f':
			break;
		case 'h':
			hflag = 1;
			break;
		case 'R':
			rflag = 1;
			break;
		default:
			usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc < 2)
		usage();
	gid = parse_group(argv[0]);
	for (int i = 1; i < argc; i++)
		ret |= walk(argv[i]);
	return ret;
}
