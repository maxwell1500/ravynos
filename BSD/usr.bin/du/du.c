/* SPDX-License-Identifier: BSD-2-Clause */
/* du(1) for ravynOS: summarise disk usage.  Installer scripts run it to size
 * a tree; -s, -k, -h and -x cover what they use.  Sizes are allocated bytes
 * (st_blocks * 512), raised to the file size for filesystems that report no
 * blocks, which is what du reports on UFS/HFS+. */
#include <sys/types.h>
#include <sys/stat.h>

#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static int hflag, kflag, sflag, xflag;
static int rc;

static void
print_size(long long n)
{
	static const char *units = "BKMGTPE";
	double v;
	int u;

	if (hflag) {
		v = (double)n;
		u = 0;
		while (v >= 1024.0 && units[u + 1] != '\0') {
			v /= 1024.0;
			u++;
		}
		if (u == 0)
			printf("%lldB", n);
		else
			printf("%.1f%c", v, units[u]);
	} else if (kflag)
		printf("%lld", (n + 1023) / 1024);
	else
		printf("%lld", (n + 511) / 512);
}

static long long
blocks_of(const struct stat *sb)
{
	long long size = (long long)sb->st_blocks * 512;

	if (size < (long long)sb->st_size)
		size = sb->st_size;
	return size;
}

static long long
usage(const char *path, dev_t dev, int top)
{
	struct stat sb;
	DIR *dir;
	struct dirent *dp;
	char *sub;
	long long total;

	if (lstat(path, &sb) == -1) {
		warn("%s", path);
		rc = 1;
		return 0;
	}
	total = blocks_of(&sb);
	if (S_ISDIR(sb.st_mode) && (!xflag || sb.st_dev == dev)) {
		if ((dir = opendir(path)) == NULL) {
			warn("%s", path);
			rc = 1;
			return total;
		}
		while ((dp = readdir(dir)) != NULL) {
			if (strcmp(dp->d_name, ".") == 0 ||
			    strcmp(dp->d_name, "..") == 0)
				continue;
			if (asprintf(&sub, "%s/%s", path, dp->d_name) == -1)
				err(EX_OSERR, NULL);
			total += usage(sub, dev, 0);
			free(sub);
		}
		closedir(dir);
	}
	if (!sflag || top) {
		print_size(total);
		printf("\t%s\n", path);
	}
	return total;
}

int
main(int argc, char *argv[])
{
	struct stat sb;
	int ch, i;

	while ((ch = getopt(argc, argv, "hksx")) != -1) {
		switch (ch) {
		case 'h': hflag = 1; break;
		case 'k': kflag = 1; break;
		case 's': sflag = 1; break;
		case 'x': xflag = 1; break;
		default:
			fprintf(stderr, "usage: du [-hksx] [file ...]\n");
			exit(EX_USAGE);
		}
	}
	argc -= optind;
	argv += optind;
	if (argc == 0) {
		static char dotpath[] = ".";
		static char *dot[] = { dotpath, NULL };

		argv = dot;
		argc = 1;
	}
	for (i = 0; i < argc; i++) {
		dev_t dev = 0;

		if (stat(argv[i], &sb) == 0)
			dev = sb.st_dev;
		(void)usage(argv[i], dev, 1);
	}
	return rc;
}
