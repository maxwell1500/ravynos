/*
 * ReportCrash -- generate diagnostic crash report for ravynOS.
 *
 * Implements crash reporting for Phase 7.2.
 * Writes ~/Library/Logs/DiagnosticReports/<app>-<date>.crash and
 * /var/log/DiagnosticReports/<app>-<date>.crash, and logs to syslog.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <syslog.h>

int main(int argc, char *argv[]) {
    const char *name = (argc > 1) ? argv[1] : "unknown";
    int pid = (argc > 2) ? atoi(argv[2]) : getpid();
    int sig = (argc > 3) ? atoi(argv[3]) : 11;

    time_t now = time(NULL);
    struct tm tm_buf;
    char time_str[64];
    localtime_r(&now, &tm_buf);
    strftime(time_str, sizeof(time_str), "%Y-%m-%d-%H%M%S", &tm_buf);

    char path[1024];
    const char *dirs[] = {
        "/var/log/DiagnosticReports",
        "/Users/ravyn/Library/Logs/DiagnosticReports",
        NULL
    };

    mkdir("/Users", 0755);
    mkdir("/Users/ravyn", 0755);
    mkdir("/Users/ravyn/Library", 0755);
    mkdir("/Users/ravyn/Library/Logs", 0755);
    mkdir("/Users/ravyn/Library/Logs/DiagnosticReports", 0755);
    mkdir("/var/log/DiagnosticReports", 0755);

    for (int i = 0; dirs[i] != NULL; i++) {
        snprintf(path, sizeof(path), "%s/%s-%s.crash", dirs[i], name, time_str);
        FILE *f = fopen(path, "w");
        if (f != NULL) {
            fprintf(f, "Process:         %s [%d]\n", name, pid);
            fprintf(f, "Identifier:      %s\n", name);
            fprintf(f, "Date/Time:       %ld\n", (long)now);
            fprintf(f, "OS Version:      ravynOS 0.7.0 (Darwin 24.3.0)\n");
            fprintf(f, "Report Version:  12\n\n");
            fprintf(f, "Exception Type:  EXC_BAD_ACCESS (SIG%s)\n", strsignal(sig));
            fprintf(f, "Termination Signal: %d (%s)\n", sig, strsignal(sig));
            fclose(f);
        }
    }

    openlog("ReportCrash", LOG_PID, LOG_DAEMON);
    syslog(LOG_ERR, "Process %s [%d] crashed (%s)", name, pid, strsignal(sig));
    closelog();

    return 0;
}
