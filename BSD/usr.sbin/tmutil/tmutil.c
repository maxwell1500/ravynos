/*
 * tmutil -- copy and verify a directory tree.
 *
 * ravynOS has no snapshot filesystem yet, so a backup is a verified copy:
 * backup/restore copy the tree, verify walks both trees and compares every
 * regular file byte for byte.  A missing or different file is an error, not
 * a warning.
 */
#include <dirent.h>
#include <errno.h>
#include <err.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int
copy_file(const char *src, const char *dst, mode_t mode)
{
	char buf[65536];
	int in = open(src, O_RDONLY);
	int out;
	ssize_t n;

	if (in < 0)
		return -1;
	out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, mode & 0777);
	if (out < 0) {
		close(in);
		return -1;
	}
	while ((n = read(in, buf, sizeof(buf))) > 0) {
		ssize_t off = 0;
		while (off < n) {
			ssize_t w = write(out, buf + off, (size_t)(n - off));
			if (w <= 0) {
				close(in);
				close(out);
				return -1;
			}
			off += w;
		}
	}
	close(in);
	if (close(out) != 0)
		return -1;
	return n < 0 ? -1 : 0;
}

static int
copy_tree(const char *src, const char *dst)
{
	struct stat st;
	DIR *dir;
	struct dirent *de;
	int rc = 0;

	if (lstat(src, &st) != 0)
		return -1;

	if (S_ISDIR(st.st_mode)) {
		if (mkdir(dst, st.st_mode & 0777) != 0 && errno != EEXIST)
			return -1;
		dir = opendir(src);
		if (dir == NULL)
			return -1;
		while ((de = readdir(dir)) != NULL) {
			char sp[PATH_MAX], dp[PATH_MAX];
			if (strcmp(de->d_name, ".") == 0 ||
			    strcmp(de->d_name, "..") == 0)
				continue;
			snprintf(sp, sizeof(sp), "%s/%s", src, de->d_name);
			snprintf(dp, sizeof(dp), "%s/%s", dst, de->d_name);
			if (copy_tree(sp, dp) != 0)
				rc = -1;
		}
		closedir(dir);
		return rc;
	}

	if (S_ISLNK(st.st_mode)) {
		char target[PATH_MAX];
		ssize_t n = readlink(src, target, sizeof(target) - 1);
		if (n < 0)
			return -1;
		target[n] = '\0';
		unlink(dst);
		return symlink(target, dst);
	}

	if (S_ISREG(st.st_mode))
		return copy_file(src, dst, st.st_mode);

	return 0;
}

static int
verify_tree(const char *src, const char *dst)
{
	struct stat ss, ds;
	DIR *dir;
	struct dirent *de;
	int rc = 0;

	if (lstat(src, &ss) != 0) {
		warn("lstat %s", src);
		return -1;
	}
	if (lstat(dst, &ds) != 0) {
		warn("missing in backup: %s", dst);
		return -1;
	}
	if ((ss.st_mode & S_IFMT) != (ds.st_mode & S_IFMT)) {
		warnx("type differs: %s", dst);
		return -1;
	}

	if (S_ISDIR(ss.st_mode)) {
		dir = opendir(src);
		if (dir == NULL)
			return -1;
		while ((de = readdir(dir)) != NULL) {
			char sp[PATH_MAX], dp[PATH_MAX];
			if (strcmp(de->d_name, ".") == 0 ||
			    strcmp(de->d_name, "..") == 0)
				continue;
			snprintf(sp, sizeof(sp), "%s/%s", src, de->d_name);
			snprintf(dp, sizeof(dp), "%s/%s", dst, de->d_name);
			if (verify_tree(sp, dp) != 0)
				rc = -1;
		}
		closedir(dir);
		return rc;
	}

	if (S_ISREG(ss.st_mode)) {
		char a[65536], b[65536];
		int fa = open(src, O_RDONLY);
		int fb = open(dst, O_RDONLY);
		ssize_t na, nb;
		if (fa < 0 || fb < 0) {
			if (fa >= 0) close(fa);
			if (fb >= 0) close(fb);
			return -1;
		}
		do {
			na = read(fa, a, sizeof(a));
			nb = read(fb, b, sizeof(b));
			if (na != nb || (na > 0 && memcmp(a, b, (size_t)na) != 0)) {
				warnx("contents differ: %s", dst);
				rc = -1;
				break;
			}
		} while (na > 0);
		close(fa);
		close(fb);
	}
	return rc;
}

int
main(int argc, char **argv)
{
	if (argc != 4) {
		fprintf(stderr, "usage: tmutil backup|restore|verify <source> <destination>\n");
		return 2;
	}
	if (strcmp(argv[1], "backup") == 0 || strcmp(argv[1], "restore") == 0) {
		if (copy_tree(argv[2], argv[3]) != 0)
			err(1, "copy %s -> %s", argv[2], argv[3]);
		return 0;
	}
	if (strcmp(argv[1], "verify") == 0)
		return verify_tree(argv[2], argv[3]) == 0 ? 0 : 1;
	fprintf(stderr, "tmutil: unknown command %s\n", argv[1]);
	return 2;
}
