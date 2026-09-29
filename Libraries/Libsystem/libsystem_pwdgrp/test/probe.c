/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * probe.c -- a static ravynOS program that calls every entry point
 * libsystem_pwdgrp provides.
 *
 * Its job is to be linked, not to be run here. tools/bootlab/link-static.sh
 * verifies its own output and fails the link unless the result has zero
 * LC_LOAD_DYLIB and zero undefined symbols, so a link that succeeds is
 * proof that every one of these resolved -- and, because each call is
 * genuinely present rather than behind a `#if 0', that the archive really
 * defines all of them and not just the handful ls and rm happen to need.
 */

#include <sys/types.h>

#include <grp.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libsystem_pwdgrp.h"

int
main(void)
{
	char buf[4096];
	struct passwd pw, *pwr;
	struct group gr, *grr;
	FILE *fp;
	int n;

	/* Lookup. */
	if (getpwnam("root") != NULL)
		pwr = getpwuid(0);
	if (getgrnam("wheel") != NULL)
		grr = getgrgid(0);

	/* Iteration. */
	setpwent();
	for (n = 0; getpwent() != NULL; n++)
		;
	if (getpwent() == NULL)
		getpwent();			/* rewinds */
	endpwent();

	setgrent();
	for (n = 0; getgrent() != NULL; n++)
		;
	if (getgrent() == NULL)
		getgrent();			/* rewinds */
	endgrent();

	setpassent(1);
	setgroupent(1);

	/* Reentrant. */
	if (getpwnam_r("root", &pw, buf, sizeof(buf), &pwr) == 0)
		getpwuid_r(0, &pw, buf, sizeof(buf), &pwr);
	if (getpwent_r(&pw, buf, sizeof(buf), &pwr) == 0)
		getgrnam_r("wheel", &gr, buf, sizeof(buf), &grr);
	if (getgrgid_r(0, &gr, buf, sizeof(buf), &grr) == 0)
		getgrent_r(&gr, buf, sizeof(buf), &grr);

	/* A caller-supplied stream. */
	if ((fp = fopen("/etc/passwd", "r")) != NULL) {
		fgetpwent(fp);
		fgetpwent_r(fp, &pw, buf, sizeof(buf), &pwr);
		fclose(fp);
	}
	if ((fp = fopen("/etc/group", "r")) != NULL) {
		fgetgrent(fp);
		fgetgrent_r(fp, &gr, buf, sizeof(buf), &grr);
		fclose(fp);
	}

	/* What ls and rm call. */
	(void)user_from_uid(0, 0);
	(void)group_from_gid(0, 0);

	/* The SDK's <grp.h> declares this one and no archive in the tree
	 * defined it before this component existed. */
	setgrfile("/etc/group");
	setgrfile(NULL);

	printf("pwdgrp: %d passwd entries, %d group entries\n", n, n);
	return 0;
}
