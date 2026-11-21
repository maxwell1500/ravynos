/*
 * printfprobe.c -- conformance for the libc printf conversion set.
 *
 * Written because WindowServer and Dock diagnostics printed
 * "<UNSUPPORTED-CONVERSION>" where a number belonged: "%zu" and "%g" in code
 * that had always worked on macOS.  A printf that silently replaces a value
 * with a marker is worse than one that fails, because the diagnostic stays
 * plausible.  Every application that logs a size_t or a double goes through
 * exactly this path, so it is worth an explicit fixture.
 *
 * Built on the development Mac against Apple's SDK so the format strings are
 * interpreted by ravynOS's libc, not the host's.
 */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stddef.h>

static int failures = 0;

static void check(const char *label, const char *got, const char *want) {
    if(strcmp(got, want) != 0) {
        printf("FAIL %s: got \"%s\" want \"%s\"\n", label, got, want);
        failures++;
        return;
    }
    printf("PASS %s\n", label);
}

int main(void) {
    char buf[128];

    snprintf(buf, sizeof(buf), "%d", -42);
    check("%d", buf, "-42");

    snprintf(buf, sizeof(buf), "%u", 42u);
    check("%u", buf, "42");

    snprintf(buf, sizeof(buf), "%zu", (size_t)9000);
    check("%zu", buf, "9000");

    snprintf(buf, sizeof(buf), "%zx", (size_t)0x1f);
    check("%zx", buf, "1f");

    snprintf(buf, sizeof(buf), "%ld", (long)123456789012345L);
    check("%ld", buf, "123456789012345");

    snprintf(buf, sizeof(buf), "%lld", (long long)-9007199254740993LL);
    check("%lld", buf, "-9007199254740993");

    snprintf(buf, sizeof(buf), "%s", "abc");
    check("%s", buf, "abc");

    snprintf(buf, sizeof(buf), "[%5s]", "ab");
    check("width %5s", buf, "[   ab]");

    snprintf(buf, sizeof(buf), "[%-5s]", "ab");
    check("left align %-5s", buf, "[ab   ]");

    snprintf(buf, sizeof(buf), "[%05d]", 42);
    check("zero pad %05d", buf, "[00042]");

    snprintf(buf, sizeof(buf), "%.3s", "abcdef");
    check("precision %.3s", buf, "abc");

    snprintf(buf, sizeof(buf), "%p", (void *)0);
    if(strcmp(buf, "0x0") != 0 && strcmp(buf, "(nil)") != 0) {
        printf("FAIL %%p: got \"%s\"\n", buf);
        failures++;
    } else {
        printf("PASS %%p\n");
    }

    /* Floating point: the formats a diagnostic printf actually uses. */
    snprintf(buf, sizeof(buf), "%f", 2.5);
    check("%f", buf, "2.500000");

    snprintf(buf, sizeof(buf), "%.2f", 2.567);
    check("%.2f", buf, "2.57");

    snprintf(buf, sizeof(buf), "%g", 2.5);
    check("%g", buf, "2.5");

    snprintf(buf, sizeof(buf), "%e", 2500.0);
    check("%e", buf, "2.500000e+03");

    /* A size_t one slot before a string: an unsupported conversion that
     * consumes no argument shifts every later one. */
    {
        size_t n = 7;
        snprintf(buf, sizeof(buf), "%zu/%s", n, "ok");
        check("%zu then %s stay aligned", buf, "7/ok");
    }

    if(strstr(buf, "UNSUPPORTED") != NULL) {
        printf("FAIL printf emitted a marker instead of a value\n");
        failures++;
    }

    /*
     * snprintf and the FILE* path are separate implementations in this libc
     * (WindowServer and Dock used to print "<UNSUPPORTED-CONVERSION>" for %zu
     * on stderr while snprintf produced the right text), so both are checked.
     * The line below is read back by tools/bootlab/verify_compat.py.
     */
    fprintf(stderr, "[PRINTF-FILE] zu=%zu g=%g f=%.2f s=%s\n",
            (size_t)9000, 2.5, 1.25, "ok");
    fflush(stderr);

    printf("%s (%d failure(s))\n", failures == 0 ? "PRINTF-OK" : "PRINTF-FAIL",
           failures);
    return failures == 0 ? 0 : 1;
}
