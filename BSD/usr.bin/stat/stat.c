/* SPDX-License-Identifier: BSD-2-Clause */
/* stat(1) for ravynOS.  Ports (MacPorts, configure scripts) rely on the BSD
 * -f format langauge, which Darwin's stat(1) also half-supports; this
 * implements the escapes those scripts actually use. */
#include <sys/types.h>
#include <sys/stat.h>

#include <err.h>
#include <errno.h>
#include <grp.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <time.h>
#include <unistd.h>

static int Lflag;
static int quiet;

static void usage(void);

static void
print_time(time_t t, const char *fmt)
{
	struct tm *tm = localtime(&t);
	char buf[64];

	if (tm == NULL || strftime(buf, sizeof(buf), fmt, tm) == 0)
		return;
	fputs(buf, stdout);
}

static void
print_field(const char *path, struct stat *sb, char c, char sub)
{
	struct passwd *pw;
	struct group *gr;

	switch (c) {
	case 'N': fputs(path, stdout); break;
	case 'z': printf("%lld", (long long)sb->st_size); break;
	case 'p': printf("%o", (unsigned)(sb->st_mode & 07777)); break;
	case 'f': printf("%x", (unsigned)sb->st_flags); break;
	case 'u': printf("%u", sb->st_uid); break;
	case 'g': printf("%u", sb->st_gid); break;
	case 'm': printf("%lld", (long long)sb->st_mtime); break;
	case 'a': printf("%lld", (long long)sb->st_atime); break;
	case 'c': printf("%lld", (long long)sb->st_ctime); break;
	case 'B': printf("%lld", (long long)sb->st_birthtime); break;
	case 'i': printf("%llu", (unsigned long long)sb->st_ino); break;
	case 'd': printf("%u", sb->st_dev); break;
	case 'l': printf("%u", sb->st_nlink); break;
	case 'b': printf("%lld", (long long)sb->st_blocks); break;
	case 'k': printf("%lld", (long long)(sb->st_blocks + 1) / 2); break;
	case 'r': printf("%u", sb->st_rdev); break;
	case 'S':
		switch (sub) {
		case 'u':
			printf("%s", (pw = getpwuid(sb->st_uid)) ?
			    pw->pw_name : "UNKNOWN");
			break;
		case 'g':
			printf("%s", (gr = getgrgid(sb->st_gid)) ?
			    gr->gr_name : "UNKNOWN");
			break;
		case 'a': print_time(sb->st_atime, "%b %e %H:%M:%S %Y"); break;
		case 'm': print_time(sb->st_mtime, "%b %e %H:%M:%S %Y"); break;
		case 'c': print_time(sb->st_ctime, "%b %e %H:%M:%S %Y"); break;
		case 'B': print_time(sb->st_birthtime, "%b %e %H:%M:%S %Y"); break;
		default: fputs("?", stdout); break;
		}
		break;
	case 'L':
		if (sub == 'p') {
			printf("%o", (unsigned)(sb->st_mode & 07777));
			break;
		}
		/* fall through */
	default:
		putchar('%');
		putchar(c);
		if (sub != '\0')
			putchar(sub);
		break;
	}
}

static void
print_format(const char *path, struct stat *sb, const char *fmt)
{
	const char *p;

	for (p = fmt; *p != '\0'; p++) {
		if (*p == '\\' && p[1] != '\0') {
			p++;
			switch (*p) {
			case 'n': putchar('\n'); break;
			case 't': putchar('\t'); break;
			default: putchar(*p); break;
			}
			continue;
		}
		if (*p != '%') {
			putchar(*p);
			continue;
		}
		p++;
		if (*p == '\0')
			break;
		print_field(path, sb, *p, '\0');
	}
}

static void
print_default(const char *path, struct stat *sb)
{
	struct passwd *pw;
	struct group *gr;
	const char *type;
	char mode[12];

	type = S_ISDIR(sb->st_mode) ? "Directory" :
	    S_ISREG(sb->st_mode) ? "Regular File" :
	    S_ISLNK(sb->st_mode) ? "Symbolic Link" :
	    S_ISFIFO(sb->st_mode) ? "Fifo File" :
	    S_ISSOCK(sb->st_mode) ? "Socket" : "Unknown";

	pw = getpwuid(sb->st_uid);
	gr = getgrgid(sb->st_gid);
	printf("  File: \"%s\"\n", path);
	printf("  Size: %lld\t\tType: %s\n", (long long)sb->st_size, type);
	strmode(sb->st_mode, mode);
	printf("  Mode: (%04o/%s)\t\tUid: (%u/%s)\tGid: (%u/%s)\n",
	    (unsigned)(sb->st_mode & 07777), mode,
	    sb->st_uid, pw ? pw->pw_name : "UNKNOWN",
	    sb->st_gid, gr ? gr->gr_name : "UNKNOWN");
	printf("  Links: %u\t\tBlocks: %lld\t\tIO Block: %u\n",
	    sb->st_nlink, (long long)sb->st_blocks, sb->st_blksize);
	printf("Access: %s", ctime(&sb->st_atime));
	printf("Modify: %s", ctime(&sb->st_mtime));
	printf("Change: %s", ctime(&sb->st_ctime));
}

int
main(int argc, char *argv[])
{
	struct stat sb;
	const char *fmt = NULL;
	int ch, i, rc = 0;

	while ((ch = getopt(argc, argv, "f:Llq:x")) != -1) {
		switch (ch) {
		case 'f': fmt = optarg; break;
		case 'L': Lflag = 1; break;
		case 'l': break;
		case 'q': quiet = 1; break;
		case 'x': break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc == 0)
		usage();
	for (i = 0; i < argc; i++) {
		if ((Lflag ? stat(argv[i], &sb) : lstat(argv[i], &sb)) == -1) {
			if (!quiet)
				warn("%s", argv[i]);
			rc = 1;
			continue;
		}
		if (fmt != NULL)
			print_format(argv[i], &sb, fmt);
		else
			print_default(argv[i], &sb);
		if (fmt != NULL)
			putchar('\n');
	}
	return rc;
}

static void
usage(void)
{
	fprintf(stderr, "usage: stat [-L] [-f format] file ...\n");
	exit(EX_USAGE);
}
