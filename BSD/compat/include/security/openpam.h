/* FreeBSD applications include <security/openpam.h> for the PAM application
 * API; this SDK ships the same declarations in <security/pam_appl.h> but no
 * openpam.h, and libpam does not export the tty conversation helper, so it is
 * provided by the program that needs it (passwd(1)).
 */
#ifndef _RAVYN_COMPAT_OPENPAM_H_
#define _RAVYN_COMPAT_OPENPAM_H_

#include <security/pam_appl.h>

/* OpenPAM distinguishes "recovery failed" from a bad token; the base PAM
 * constants have no such code, and passwd(1) treats both the same way. */
#ifndef PAM_BUF_ERR
#define PAM_BUF_ERR 5
#endif

#ifndef PAM_AUTHTOK_RECOVERY_ERR
#define PAM_AUTHTOK_RECOVERY_ERR PAM_AUTH_ERR
#endif

#ifdef __cplusplus
extern "C" {
#endif
int openpam_ttyconv(int, const struct pam_message **,
    struct pam_response **, void *);
#ifdef __cplusplus
}
#endif

#endif
