/*
 * <sandbox.h> for ravynOS.
 *
 * macOS sandboxed helpers (Chrome's renderer/GPU/utility processes, XPC
 * services) call sandbox_init() before doing work and treat a failure as
 * fatal.  ravynOS has no sandbox policy engine; this library accepts the
 * profile, records it as the process's sandbox label, and lets the process
 * continue.  That is an honest "no confinement" answer: every entry point
 * reports success for setup, and sandbox_check() reports "not denied" because
 * nothing is being enforced.  It never pretends a resource was granted by a
 * token that does not exist -- extension tokens are minted by this library
 * and accepted back by it.
 */
#ifndef _SANDBOX_H_
#define _SANDBOX_H_

#include <sys/cdefs.h>
#include <sys/types.h>

__BEGIN_DECLS

extern char *sandbox_default_container_path;
extern char *sandbox_user_container_path;

extern const char *const kSBXProfileNoInternet;
extern const char *const kSBXProfileNoNetwork;
extern const char *const kSBXProfileNoWrite;
extern const char *const kSBXProfileNoWriteExceptTemporary;
extern const char *const kSBXProfilePureComputation;

extern int sandbox_init(const char *profile, uint64_t flags, char **errorbuf);
extern int sandbox_init_with_parameters(const char *profile, uint64_t flags,
                                        const char *const parameters[],
                                        char **errorbuf);
extern int sandbox_init_with_extensions(const char *profile, uint64_t flags,
                                        const char *const extensions[],
                                        char **errorbuf);
extern void sandbox_free_error(char *errorbuf);
extern int sandbox_check(pid_t pid, const char *operation, int type, ...);
extern char *sandbox_extension_issue_file(const char *extension_class,
                                          const char *path, uint32_t flags);
extern char *sandbox_extension_issue_mach(const char *extension_class,
                                          const char *name, uint32_t flags);
extern int sandbox_extension_consume(const char *extension_token);
extern int sandbox_extension_release(uint64_t handle);
extern int sandbox_extension_release_all(void);
extern int sandbox_container_path_for_pid(pid_t pid, char *buffer,
                                          size_t bufsize);
extern int sandbox_user_container_path_for_pid(pid_t pid, char *buffer,
                                               size_t bufsize);

__END_DECLS

#endif
