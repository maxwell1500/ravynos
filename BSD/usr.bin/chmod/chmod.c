/* SPDX-License-Identifier: BSD-2-Clause */
/* chmod(1) for ravynOS.
 *
 * This is not the FreeBSD program: BSD/bin/chmod was not imported into this
 * tree, but the image and every port's install step need it.  The mode parser
 * accepts the POSIX symbolic grammar (classes ugoa, ops +-=, permissions
 * rwxXst plus the ugo copy forms) and numeric modes, and -R walks the tree
 * depth first without following symlinks. */
#include <sys/types.h>
#include <sys/stat.h>

#include <ctype.h>
#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static int rflag;
static int hflag;

static void usage(void);

static mode_t
apply_symbolic(mode_t mode, const char *spec, const char *path, int isdir)
{
	const char *p = spec;
	mode_t who_mask, perm;
	int op, done;

	while (*p != '\0') {
		who_mask = 0;
		for (done = 0; !done; p++) {
			switch (*p) {
			case 'u': who_mask |= S_IRWXU; break;
			case 'g': who_mask |= S_IRWXG; break;
			case 'o': who_mask |= S_IRWXO; break;
			case 'a': who_mask |= S_IRWXU | S_IRWXG | S_IRWXO; break;
			default: done = 1; p--; break;
			}
		}
		if (who_mask == 0)
			who_mask = S_IRWXU | S_IRWXG | S_IRWXO;
		op = *p++;
		if (op != '+' && op != '-' && op != '=')
			errx(EX_USAGE, "%s: invalid mode: %s", path, spec);

		perm = 0;
		for (; *p != '\0' && *p != ','; p++) {
			switch (*p) {
			case 'r': perm |= (who_mask & S_IRWXU ? S_IRUSR : 0) |
			    (who_mask & S_IRWXG ? S_IRGRP : 0) |
			    (who_mask & S_IRWXO ? S_IROTH : 0); break;
			case 'w': perm |= (who_mask & S_IRWXU ? S_IWUSR : 0) |
			    (who_mask & S_IRWXG ? S_IWGRP : 0) |
			    (who_mask & S_IRWXO ? S_IWOTH : 0); break;
			case 'x': perm |= (who_mask & S_IRWXU ? S_IXUSR : 0) |
			    (who_mask & S_IRWXG ? S_IXGRP : 0) |
			    (who_mask & S_IRWXO ? S_IXOTH : 0); break;
			case 'X':
				if (isdir || (mode & (S_IXUSR|S_IXGRP|S_IXOTH)))
					perm |= (who_mask & S_IRWXU ? S_IXUSR : 0) |
					    (who_mask & S_IRWXG ? S_IXGRP : 0) |
					    (who_mask & S_IRWXO ? S_IXOTH : 0);
				break;
			case 's':
				perm |= (who_mask & S_IRWXU ? S_ISUID : 0) |
				    (who_mask & S_IRWXG ? S_ISGID : 0);
				break;
			case 't': perm |= S_ISVTX; break;
			case 'u': perm |= (mode & 0700) >> 0; break;
			case 'g': perm |= (mode & 0070) << 3; break;
			case 'o': perm |= (mode & 0007) << 6; break;
			default:
				errx(EX_USAGE, "%s: invalid mode: %s", path, spec);
			}
		}
		switch (op) {
		case '+': mode |= perm; break;
		case '-': mode &= ~perm; break;
		case '=':
			mode &= ~who_mask;
			mode |= perm;
			break;
		}
		if (*p == ',')
			p++;
	}
	return mode;
}

static int
do_chmod(const char *path, const char *spec)
{
	struct stat sb;
	mode_t mode;
	int error;

	if ((hflag ? lstat(path, &sb) : stat(path, &sb)) == -1) {
		warn("%s", path);
		return 1;
	}
	mode = sb.st_mode;
	if (*spec >= '0' && *spec <= '7' && strspn(spec, "01234567") == strlen(spec))
		mode = (mode & ~07777) | (mode_t)strtol(spec, NULL, 8);
	else
		mode = apply_symbolic(mode, spec, path, S_ISDIR(sb.st_mode));
	if (hflag ? lchmod(path, mode) == -1 : chmod(path, mode) == -1) {
		error = errno;
		warn("%s", path);
		errno = error;
		return 1;
	}
	return 0;
}

static int
walk(const char *path, const char *spec)
{
	DIR *dir;
	struct dirent *dp;
	char *sub;
	int rc = 0;

	if (do_chmod(path, spec))
		rc = 1;
	if (!rflag)
		return rc;
	if ((dir = opendir(path)) == NULL) {
		warn("%s", path);
		return 1;
	}
	while ((dp = readdir(dir)) != NULL) {
		if (strcmp(dp->d_name, ".") == 0 || strcmp(dp->d_name, "..") == 0)
			continue;
		if (asprintf(&sub, "%s/%s", path, dp->d_name) == -1)
			err(EX_OSERR, NULL);
		rc |= walk(sub, spec);
		free(sub);
	}
	closedir(dir);
	return rc;
}

int
main(int argc, char *argv[])
{
	int ch, rc = 0, first;
	const char *spec;

	while ((ch = getopt(argc, argv, "Rfhv")) != -1) {
		switch (ch) {
		case 'R': rflag = 1; break;
		case 'h': hflag = 1; break;
		case 'v': break;	/* accepted for compatibility */
		case 'f': break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc < 2)
		usage();
	spec = argv[0];
	for (first = 1; first < argc; first++)
		rc |= walk(argv[first], spec);
	return rc;
}

static void
usage(void)
{
	fprintf(stderr, "usage: chmod [-R] [-h] mode file ...\n");
	exit(EX_USAGE);
}
