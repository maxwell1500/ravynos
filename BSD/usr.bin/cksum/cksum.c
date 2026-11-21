/* SPDX-License-Identifier: BSD-2-Clause */
/* cksum(1): POSIX CRC-32 checksum followed by the byte count. */
#include <err.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>

static void usage(void);

static uint32_t crctab[256];

static void
mkcrctab(void)
{
	uint32_t crc;
	int i, j;

	for (i = 0; i < 256; i++) {
		crc = (uint32_t)i << 24;
		for (j = 0; j < 8; j++)
			crc = (crc & 0x80000000U) ? (crc << 1) ^ 0x04c11db7U :
			    (crc << 1);
		crctab[i] = crc;
	}
}

static int
ckfile(const char *name, FILE *fp)
{
	uint32_t crc = 0;
	unsigned char buf[8192];
	size_t n;
	long long len = 0;

	while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
		size_t i;

		for (i = 0; i < n; i++)
			crc = (crc << 8) ^ crctab[((crc >> 24) ^ buf[i]) & 0xff];
		len += (long long)n;
	}
	if (ferror(fp)) {
		warn("%s", name);
		return 1;
	}
	{
		long long orig = len;

		for (; len != 0; len >>= 8)
			crc = (crc << 8) ^
			    crctab[((crc >> 24) ^ (len & 0xff)) & 0xff];
		crc = ~crc;
		printf("%u %lld", (unsigned)crc, orig);
	}
	if (name != NULL)
		printf(" %s", name);
	putchar('\n');
	return 0;
}

int
main(int argc, char *argv[])
{
	int ch, i, rc = 0;
	FILE *fp;

	mkcrctab();
	while ((ch = getopt(argc, argv, "")) != -1)
		usage();
	argc -= optind;
	argv += optind;
	if (argc == 0)
		return ckfile(NULL, stdin);
	for (i = 0; i < argc; i++) {
		if ((fp = fopen(argv[i], "r")) == NULL) {
			warn("%s", argv[i]);
			rc = 1;
			continue;
		}
		rc |= ckfile(argv[i], fp);
		fclose(fp);
	}
	return rc;
}

static void
usage(void)
{
	fprintf(stderr, "usage: cksum [file ...]\n");
	exit(EX_USAGE);
}
