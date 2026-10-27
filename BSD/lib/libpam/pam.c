/*
 * libpam.2.dylib for ravynOS.
 *
 * No PAM stack or modules exist on this system yet, so this is the
 * structural part of PAM and nothing more: handles, items, the conversation
 * callback, and environment.  Authentication answers PAM_AUTHINFO_UNAVAIL --
 * a real error code, not success -- because claiming that a password was
 * verified when no module ran would be a security hole, and every caller
 * handles a failed authenticate.
 */
#include <stdlib.h>
#include <string.h>

#include "pam.h"

struct pam_handle {
    char *service;
    char *user;
    char *tty;
    char *rhost;
    char *ruser;
    struct pam_conv conv;
    char **env;
    int env_count;
};

static char *dup_or_null(const char *s)
{
    return s ? strdup(s) : NULL;
}

int pam_start(const char *service_name, const char *user,
              const struct pam_conv *pam_conversation, pam_handle_t **pamh)
{
    pam_handle_t *h;

    if (pamh == NULL) {
        return PAM_SYSTEM_ERR;
    }
    h = (pam_handle_t *)calloc(1, sizeof(*h));
    if (h == NULL) {
        return PAM_SYSTEM_ERR;
    }
    h->service = dup_or_null(service_name ? service_name : "other");
    h->user = dup_or_null(user);
    if (pam_conversation != NULL) {
        h->conv = *pam_conversation;
    }
    *pamh = h;
    return PAM_SUCCESS;
}

int pam_end(pam_handle_t *pamh, int pam_status)
{
    (void)pam_status;
    if (pamh == NULL) {
        return PAM_SYSTEM_ERR;
    }
    free(pamh->service);
    free(pamh->user);
    free(pamh->tty);
    free(pamh->rhost);
    free(pamh->ruser);
    for (int i = 0; i < pamh->env_count; i++) {
        free(pamh->env[i]);
    }
    free(pamh->env);
    free(pamh);
    return PAM_SUCCESS;
}

int pam_set_item(pam_handle_t *pamh, int item_type, const void *item)
{
    char **slot = NULL;

    if (pamh == NULL) {
        return PAM_SYSTEM_ERR;
    }
    switch (item_type) {
    case PAM_SERVICE: slot = &pamh->service; break;
    case PAM_USER: slot = &pamh->user; break;
    case PAM_TTY: slot = &pamh->tty; break;
    case PAM_RHOST: slot = &pamh->rhost; break;
    case PAM_RUSER: slot = &pamh->ruser; break;
    default: return PAM_SYSTEM_ERR;
    }
    free(*slot);
    *slot = dup_or_null((const char *)item);
    return PAM_SUCCESS;
}

int pam_get_item(const pam_handle_t *pamh, int item_type, const void **item)
{
    if (pamh == NULL || item == NULL) {
        return PAM_SYSTEM_ERR;
    }
    switch (item_type) {
    case PAM_SERVICE: *item = pamh->service; break;
    case PAM_USER: *item = pamh->user; break;
    case PAM_TTY: *item = pamh->tty; break;
    case PAM_RHOST: *item = pamh->rhost; break;
    case PAM_RUSER: *item = pamh->ruser; break;
    case 5 /* PAM_CONV */: *item = &pamh->conv; break;
    default: *item = NULL; break;
    }
    return PAM_SUCCESS;
}

int pam_get_user(pam_handle_t *pamh, const char **user, const char *prompt)
{
    struct pam_message msg;
    const struct pam_message *msgp = &msg;
    struct pam_response *resp = NULL;
    int status;

    if (pamh == NULL || user == NULL) {
        return PAM_SYSTEM_ERR;
    }
    if (pamh->user != NULL) {
        *user = pamh->user;
        return PAM_SUCCESS;
    }
    if (pamh->conv.conv == NULL) {
        return PAM_CONV_ERR;
    }
    msg.msg_style = PAM_PROMPT_ECHO_ON;
    msg.msg = prompt ? prompt : "login: ";
    status = pamh->conv.conv(1, &msgp, &resp, pamh->conv.appdata_ptr);
    if (status != PAM_SUCCESS || resp == NULL || resp[0].resp == NULL) {
        free(resp);
        return PAM_CONV_ERR;
    }
    pamh->user = strdup(resp[0].resp);
    free(resp[0].resp);
    free(resp);
    *user = pamh->user;
    return pamh->user ? PAM_SUCCESS : PAM_SYSTEM_ERR;
}

int pam_authenticate(pam_handle_t *pamh, int flags)
{
    (void)pamh;
    (void)flags;
    /* No module ran, so authentication did not succeed. */
    return PAM_AUTHINFO_UNAVAIL;
}

int pam_setcred(pam_handle_t *pamh, int flags)
{
    (void)pamh;
    (void)flags;
    return PAM_SUCCESS;
}

int pam_acct_mgmt(pam_handle_t *pamh, int flags)
{
    (void)pamh;
    (void)flags;
    return PAM_SUCCESS;
}

int pam_open_session(pam_handle_t *pamh, int flags)
{
    (void)pamh;
    (void)flags;
    return PAM_SUCCESS;
}

int pam_close_session(pam_handle_t *pamh, int flags)
{
    (void)pamh;
    (void)flags;
    return PAM_SUCCESS;
}

int pam_chauthtok(pam_handle_t *pamh, int flags)
{
    (void)pamh;
    (void)flags;
    return PAM_AUTHINFO_UNAVAIL;
}

int pam_putenv(pam_handle_t *pamh, const char *name_val)
{
    char **grown;
    int index = -1;

    if (pamh == NULL || name_val == NULL) {
        return PAM_SYSTEM_ERR;
    }
    for (int i = 0; i < pamh->env_count; i++) {
        size_t len = strlen(name_val);
        const char *equals = strchr(name_val, '=');
        size_t name_len = equals ? (size_t)(equals - name_val) : len;
        if (strncmp(pamh->env[i], name_val, name_len) == 0 &&
            (pamh->env[i][name_len] == '=' || pamh->env[i][name_len] == '\0')) {
            index = i;
            break;
        }
    }
    if (index >= 0) {
        char *copy = strdup(name_val);
        if (copy == NULL) {
            return PAM_SYSTEM_ERR;
        }
        free(pamh->env[index]);
        pamh->env[index] = copy;
        return PAM_SUCCESS;
    }
    grown = (char **)realloc(pamh->env, sizeof(char *) * (size_t)(pamh->env_count + 1));
    if (grown == NULL) {
        return PAM_SYSTEM_ERR;
    }
    pamh->env = grown;
    pamh->env[pamh->env_count] = strdup(name_val);
    if (pamh->env[pamh->env_count] == NULL) {
        return PAM_SYSTEM_ERR;
    }
    pamh->env_count++;
    return PAM_SUCCESS;
}

const char *pam_getenv(pam_handle_t *pamh, const char *name)
{
    size_t len;

    if (pamh == NULL || name == NULL) {
        return NULL;
    }
    len = strlen(name);
    for (int i = 0; i < pamh->env_count; i++) {
        if (strncmp(pamh->env[i], name, len) == 0 && pamh->env[i][len] == '=') {
            return pamh->env[i] + len + 1;
        }
    }
    return NULL;
}

char **pam_getenvlist(pam_handle_t *pamh)
{
    char **list;
    int count;

    if (pamh == NULL) {
        return NULL;
    }
    count = pamh->env_count;
    list = (char **)calloc((size_t)count + 1, sizeof(char *));
    if (list == NULL) {
        return NULL;
    }
    for (int i = 0; i < count; i++) {
        list[i] = strdup(pamh->env[i]);
    }
    return list;
}

const char *pam_strerror(pam_handle_t *pamh, int errnum)
{
    (void)pamh;
    switch (errnum) {
    case PAM_SUCCESS: return "Success";
    case PAM_SYSTEM_ERR: return "System error";
    case PAM_AUTH_ERR: return "Authentication failure";
    case PAM_PERM_DENIED: return "Permission denied";
    case PAM_AUTHINFO_UNAVAIL: return "Authentication information is unavailable";
    case PAM_USER_UNKNOWN: return "Unknown user";
    case PAM_MAXTRIES: return "Maximum number of tries exceeded";
    case PAM_CONV_ERR: return "Conversation error";
    default: return "Unknown PAM error";
    }
}
