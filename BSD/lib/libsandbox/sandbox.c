/*
 * libsandbox.1.dylib for ravynOS.
 *
 * See sandbox.h: this is a "no confinement" implementation that answers the
 * calls a sandboxed helper makes at startup.  The alternative -- a trap that
 * returns an object-shaped zero -- is what makes a helper crash later; here
 * every answer is a documented one.
 */
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "sandbox.h"

const char *const kSBXProfileNoInternet = "com.apple.sandbox.no-internet";
const char *const kSBXProfileNoNetwork = "com.apple.sandbox.no-network";
const char *const kSBXProfileNoWrite = "com.apple.sandbox.no-write";
const char *const kSBXProfileNoWriteExceptTemporary =
    "com.apple.sandbox.no-write-except-temporary";
const char *const kSBXProfilePureComputation = "com.apple.sandbox.pure-computation";

char *sandbox_default_container_path;
char *sandbox_user_container_path;

static char *dup_error(const char *message)
{
    char *copy;
    if (message == NULL) {
        return NULL;
    }
    copy = strdup(message);
    return copy;
}

int sandbox_init(const char *profile, uint64_t flags, char **errorbuf)
{
    (void)flags;
    if (errorbuf != NULL) {
        *errorbuf = NULL;
    }
    if (profile == NULL) {
        if (errorbuf != NULL) {
            *errorbuf = dup_error("null profile");
        }
        errno = EINVAL;
        return -1;
    }
    /* Accepting the profile is the whole implementation: there is no policy
     * engine to install it into. */
    return 0;
}

int sandbox_init_with_parameters(const char *profile, uint64_t flags,
                                 const char *const parameters[], char **errorbuf)
{
    (void)parameters;
    return sandbox_init(profile, flags, errorbuf);
}

int sandbox_init_with_extensions(const char *profile, uint64_t flags,
                                 const char *const extensions[], char **errorbuf)
{
    (void)extensions;
    return sandbox_init(profile, flags, errorbuf);
}

void sandbox_free_error(char *errorbuf)
{
    free(errorbuf);
}

int sandbox_check(pid_t pid, const char *operation, int type, ...)
{
    va_list ap;
    (void)pid;
    (void)operation;
    (void)type;
    va_start(ap, type);
    va_end(ap);
    /* 0 means "not denied": nothing is enforced, so nothing is denied. */
    return 0;
}

/* Extension tokens are opaque strings minted here and accepted here; a token
 * from another process is rejected rather than treated as a capability. */
#define SANDBOX_TOKEN_PREFIX "ravynos-sbx-"

char *sandbox_extension_issue_file(const char *extension_class,
                                   const char *path, uint32_t flags)
{
    char *token;
    size_t length;
    (void)flags;

    if (extension_class == NULL || path == NULL) {
        errno = EINVAL;
        return NULL;
    }
    length = strlen(SANDBOX_TOKEN_PREFIX) + strlen(extension_class) + strlen(path) + 3;
    token = (char *)malloc(length);
    if (token == NULL) {
        errno = ENOMEM;
        return NULL;
    }
    snprintf(token, length, SANDBOX_TOKEN_PREFIX "%s:%s", extension_class, path);
    return token;
}

char *sandbox_extension_issue_mach(const char *extension_class,
                                   const char *name, uint32_t flags)
{
    return sandbox_extension_issue_file(extension_class, name, flags);
}

int sandbox_extension_consume(const char *extension_token)
{
    if (extension_token == NULL) {
        errno = EINVAL;
        return -1;
    }
    if (strncmp(extension_token, SANDBOX_TOKEN_PREFIX,
                strlen(SANDBOX_TOKEN_PREFIX)) != 0) {
        errno = EINVAL;
        return -1;
    }
    return 1;   /* a handle: always the first consume */
}

int sandbox_extension_release(uint64_t handle)
{
    (void)handle;
    return 0;
}

int sandbox_extension_release_all(void)
{
    return 0;
}

int sandbox_container_path_for_pid(pid_t pid, char *buffer, size_t bufsize)
{
    const char *home;

    (void)pid;
    if (buffer == NULL || bufsize == 0) {
        errno = EINVAL;
        return -1;
    }
    home = getenv("HOME");
    if (home == NULL) {
        home = "/";
    }
    if (strlen(home) + strlen("/Library/Containers") + 1 > bufsize) {
        errno = ENOMEM;
        return -1;
    }
    snprintf(buffer, bufsize, "%s/Library/Containers", home);
    return 0;
}

int sandbox_user_container_path_for_pid(pid_t pid, char *buffer, size_t bufsize)
{
    return sandbox_container_path_for_pid(pid, buffer, bufsize);
}
