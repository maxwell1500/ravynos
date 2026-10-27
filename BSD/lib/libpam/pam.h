/*
 * <pam/pam_appl.h> / <security/pam_appl.h> for ravynOS, plus the flat
 * <pam.h> the library is built with.  The types follow the Solaris/macOS PAM
 * ABI: pam_handle_t is opaque, the conversation callback receives
 * struct pam_message arrays and fills struct pam_response arrays.
 */
#ifndef _SECURITY_PAM_APPL_H_
#define _SECURITY_PAM_APPL_H_

#include <sys/cdefs.h>

__BEGIN_DECLS

#define PAM_SUCCESS 0
#define PAM_SERVICE 1
#define PAM_USER 2
#define PAM_TTY 3
#define PAM_RHOST 4
#define PAM_RUSER 6
#define PAM_PROMPT_ECHO_OFF 1
#define PAM_PROMPT_ECHO_ON 2
#define PAM_ERROR_MSG 3
#define PAM_TEXT_INFO 4
#define PAM_SILENT 0x8000
#define PAM_DISALLOW_NULL_AUTHTOK 0x0001
#define PAM_REPOSITORY 9

#define PAM_AUTH_ERR 7
#define PAM_PERM_DENIED 6
#define PAM_USER_UNKNOWN 10
#define PAM_MAXTRIES 11
#define PAM_AUTHINFO_UNAVAIL 9
#define PAM_CONV_ERR 19
#define PAM_SYSTEM_ERR 4

struct pam_message {
    int msg_style;
    const char *msg;
};

struct pam_response {
    char *resp;
    int resp_retcode;
};

struct pam_conv {
    int (*conv)(int num_msg, const struct pam_message **msg,
                struct pam_response **resp, void *appdata_ptr);
    void *appdata_ptr;
};

typedef struct pam_handle pam_handle_t;

extern int pam_start(const char *service_name, const char *user,
                     const struct pam_conv *pam_conversation,
                     pam_handle_t **pamh);
extern int pam_end(pam_handle_t *pamh, int pam_status);
extern int pam_set_item(pam_handle_t *pamh, int item_type, const void *item);
extern int pam_get_item(const pam_handle_t *pamh, int item_type,
                        const void **item);
extern int pam_get_user(pam_handle_t *pamh, const char **user, const char *prompt);
extern int pam_authenticate(pam_handle_t *pamh, int flags);
extern int pam_setcred(pam_handle_t *pamh, int flags);
extern int pam_acct_mgmt(pam_handle_t *pamh, int flags);
extern int pam_open_session(pam_handle_t *pamh, int flags);
extern int pam_close_session(pam_handle_t *pamh, int flags);
extern int pam_chauthtok(pam_handle_t *pamh, int flags);
extern int pam_putenv(pam_handle_t *pamh, const char *name_val);
extern const char *pam_getenv(pam_handle_t *pamh, const char *name);
extern char **pam_getenvlist(pam_handle_t *pamh);
extern const char *pam_strerror(pam_handle_t *pamh, int errnum);

__END_DECLS

#endif
