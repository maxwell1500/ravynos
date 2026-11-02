/*
 * sandbox_init must accept a named profile and leave an audit record.
 * Enforcement is intentionally absent in this phase; a silent no-op is not
 * acceptable, because then there is no evidence the application asked.
 */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int
main(void)
{
    char *error = NULL;
    char needle[128];
    void *lib;
    int (*sandbox_init_fn)(const char *, uint64_t, char **);
    void (*sandbox_free_error_fn)(char *);
    char line[512];
    FILE *f;
    int found = 0;

    /* Load by path: a test binary must not depend on the host linker's
     * sandbox library ordinal, and the guest library is the thing under test. */
    lib = dlopen("/usr/lib/libsandbox.1.dylib", RTLD_NOW | RTLD_GLOBAL);
    if (lib == NULL) {
        fprintf(stderr, "dlopen libsandbox: %s\n", dlerror());
        return 1;
    }
    sandbox_init_fn = (int (*)(const char *, uint64_t, char **))
        dlsym(lib, "sandbox_init");
    sandbox_free_error_fn = (void (*)(char *))dlsym(lib, "sandbox_free_error");
    if (sandbox_init_fn == NULL || sandbox_free_error_fn == NULL) {
        fprintf(stderr, "libsandbox is missing sandbox_init\n");
        return 1;
    }
    if (sandbox_init_fn("com.ravynos.compat.sandbox", 0, &error) != 0) {
        fprintf(stderr, "sandbox_init failed: %s\n", error ? error : "?");
        sandbox_free_error_fn(error);
        return 1;
    }
    sandbox_free_error_fn(error);

    snprintf(needle, sizeof(needle),
        "action=sandbox profile=com.ravynos.compat.sandbox result=ok pid=%d",
        (int)getpid());
    f = fopen("/var/log/secure", "r");
    if (f == NULL) {
        perror("open /var/log/secure");
        return 1;
    }
    while (fgets(line, sizeof(line), f) != NULL) {
        if (strstr(line, needle) != NULL) {
            found = 1;
            break;
        }
    }
    fclose(f);
    if (!found) {
        fprintf(stderr, "no audit record for %s\n", needle);
        return 1;
    }
    printf("PASS sandbox\n");
    return 0;
}
