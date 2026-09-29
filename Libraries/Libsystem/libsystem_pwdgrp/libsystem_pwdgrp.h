/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * libsystem_pwdgrp.h -- the passwd/group entry points that neither the
 * ravynOS SDK's headers nor any archive in this tree declares or defines.
 *
 * <pwd.h> and <grp.h> cover the POSIX surface. What is here is the rest:
 * the historical BSD file-descriptor forms (fgetpwent and friends), which
 * the SDK does not declare at all, and setgrfile(), which the SDK's own
 * <grp.h> declares but no archive here defines. Including this header is
 * what turns those from link failures into calls.
 *
 * Nothing here conflicts with the SDK's <pwd.h> or <grp.h>; the POSIX names
 * are deliberately not repeated, so a program includes both and gets one
 * declaration of each.
 */

#ifndef	_LIBSYSTEM_PWDGRP_H
#define	_LIBSYSTEM_PWDGRP_H

#include <sys/types.h>

#include <stdio.h>

#include <grp.h>
#include <pwd.h>

/*
 * No feature-test guard around these. They are extensions, and a program
 * that wants them says so by including this header; one that does not want
 * them does not include it. Guarding the declarations would mean the header
 * silently declared nothing depending on which feature macros some earlier
 * include happened to have defined, which is a worse failure than the one
 * it prevents.
 */
__BEGIN_DECLS

/* Historical BSD: the same parse over a caller-supplied stream. */
struct passwd *fgetpwent(FILE *);
struct group  *fgetgrent(FILE *);

int fgetpwent_r(FILE *, struct passwd *, char *, size_t, struct passwd **);
int fgetgrent_r(FILE *, struct group *, char *, size_t, struct group **);

int getpwent_r(struct passwd *, char *, size_t, struct passwd **);
int getgrent_r(struct group *, char *, size_t, struct group **);

__END_DECLS

#endif	/* _LIBSYSTEM_PWDGRP_H */
