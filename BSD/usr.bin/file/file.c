/* SPDX-License-Identifier: BSD-2-Clause */
/* file(1) for ravynOS: identify a file from its first bytes.
 *
 * This is deliberately not libmagic: the tree has neither the library nor a
 * compiled magic database, and configure scripts only need to distinguish an
 * executable image, an archive, a shared object and text.  Formats are
 * reported with the same words file(1) uses so `case $(file -b x) in
 * *executable*)' keeps working. */
#include <sys/types.h>
#include <sys/stat.h>

#include <err.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

static int
printable(const unsigned char *buf, ssize_t n)
{
	ssize_t i;

	for (i = 0; i < n; i++)
		if (buf[i] != '\n' && buf[i] != '\t' && buf[i] != '\r' &&
		    (buf[i] < 0x20 || buf[i] > 0x7e))
			return 0;
	return 1;
}

static const char *
macho_name(uint32_t magic, const unsigned char *buf, size_t n)
{
	int is64 = (magic == 0xfeedfacf || magic == 0xcffaedfe);
	uint32_t cputype, filetype;
	/* The four magic values are the same pair read in host order and byte
	 * swapped: feedface/feedfacf mean the header is already in host (little
	 * endian) order; cefaedfe/cffaedfe mean it is big endian. */
	int le = (magic == 0xfeedface || magic == 0xfeedfacf);
	static char out[128];
	/* cputype is at the same offset in both header flavours; only the
	 * magic changes with the bitness. */
	size_t off = 4;
	const char *cpu, *type;

	if (n < off + 12)
		return "Mach-O";
	cputype = (uint32_t)buf[off] | (uint32_t)buf[off + 1] << 8 |
	    (uint32_t)buf[off + 2] << 16 | (uint32_t)buf[off + 3] << 24;
	if (!le)
		cputype = (uint32_t)buf[off] << 24 | (uint32_t)buf[off + 1] << 16 |
		    (uint32_t)buf[off + 2] << 8 | (uint32_t)buf[off + 3];
	filetype = (uint32_t)buf[off + 8] | (uint32_t)buf[off + 9] << 8 |
	    (uint32_t)buf[off + 10] << 16 | (uint32_t)buf[off + 11] << 24;
	if (!le)
		filetype = (uint32_t)buf[off + 8] << 24 |
		    (uint32_t)buf[off + 9] << 16 | (uint32_t)buf[off + 10] << 8 |
		    (uint32_t)buf[off + 11];
	cpu = cputype == 0x01000007 ? "x86_64" : cputype == 0x00000007 ?
	    "i386" : cputype == 0x0100000c ? "arm64" : "unknown";
	switch (filetype) {
	case 2: type = "executable"; break;
	case 6: type = "dynamically linked shared library"; break;
	case 8: type = "bundle"; break;
	default: type = "object"; break;
	}
	snprintf(out, sizeof(out), "Mach-O %d-bit %s %s", is64 ? 64 : 32,
	    type, cpu);
	return out;
}

static void
describe(const char *path, int fd, const struct stat *sb)
{
	unsigned char buf[4096];
	ssize_t n;
	uint32_t magic;

	n = read(fd, buf, sizeof(buf));
	if (n < 0) {
		warn("%s", path);
		return;
	}
	if (n == 0) {
		if (S_ISREG(sb->st_mode))
			puts("empty");
		return;
	}
	magic = (uint32_t)buf[0] | (uint32_t)buf[1] << 8 |
	    (uint32_t)buf[2] << 16 | (uint32_t)buf[3] << 24;
	switch (magic) {
	case 0xfeedface: case 0xfeedfacf: case 0xcefaedfe: case 0xcffaedfe:
		puts(macho_name(magic, buf, (size_t)n));
		return;
	case 0x464c457f:
		puts("ELF executable");
		return;
	case 0x213c6172:	/* !<arch> */
		puts("current ar archive");
		return;
	case 0x04034b50:
		puts("Zip archive data");
		return;
	case 0x474e5089:
		puts("PNG image data");
		return;
	case 0x25215053:	/* %!PS */
		puts("PostScript document text");
		return;
	}
	if (n >= 2 && buf[0] == 0x1f && buf[1] == 0x8b) {
		puts("gzip compressed data");
		return;
	}
	if (n >= 2 && buf[0] == 0xff && buf[1] == 0xd8) {
		puts("JPEG image data");
		return;
	}
	{
		char text[sizeof(buf) + 1];

		memcpy(text, buf, (size_t)n);
		text[n] = '\0';
		if (strstr(text, "<?xml") != NULL) {
			puts("XML 1.0 document text");
			return;
		}
	}
	if (n > 2 && buf[0] == '#' && buf[1] == '!')
		puts("POSIX shell script text executable");
	else if (printable(buf, n))
		puts("ASCII text");
	else
		puts("data");
}

int
main(int argc, char *argv[])
{
	int ch, fd, rc = 0;
	struct stat sb;
	int i, brief = 0, lflag = 0;

	while ((ch = getopt(argc, argv, "bLhi")) != -1) {
		switch (ch) {
		case 'b': brief = 1; break;
		case 'L': lflag = 1; break;
		case 'h': break;
		case 'i': break;
		default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc == 0)
		usage();
	for (i = 0; i < argc; i++) {
		if ((lflag ? stat(argv[i], &sb) : lstat(argv[i], &sb)) == -1) {
			warn("%s", argv[i]);
			rc = 1;
			continue;
		}
		if (S_ISDIR(sb.st_mode)) {
			if (!brief)
				printf("%s: ", argv[i]);
			puts("directory");
			continue;
		}
		if (S_ISLNK(sb.st_mode)) {
			char target[PATH_MAX + 1];
			ssize_t len;

			if (!brief)
				printf("%s: ", argv[i]);
			printf("symbolic link to ");
			len = readlink(argv[i], target, sizeof(target) - 1);
			if (len > 0) {
				target[len] = '\0';
				printf("%s\n", target);
			} else
				putchar('\n');
			continue;
		}
		if (!brief)
			printf("%s: ", argv[i]);
		if (S_ISFIFO(sb.st_mode)) {
			puts("fifo (named pipe)");
			continue;
		}
		if (!S_ISREG(sb.st_mode)) {
			puts("special");
			continue;
		}
		if ((fd = open(argv[i], O_RDONLY)) == -1) {
			warn("%s", argv[i]);
			rc = 1;
			continue;
		}
		describe(argv[i], fd, &sb);
		close(fd);
	}
	return rc;
}

static void
usage(void)
{
	fprintf(stderr, "usage: file [-bhL] file ...\n");
	exit(EX_USAGE);
}
