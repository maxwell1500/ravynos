/*
 * Ordinary Unix permission bits must be enforced for a non-root uid.
 * This is the enforcement half of Phase 5.4: sandbox profiles are audited
 * no-ops, but file mode bits are not.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static int
child_checks(const char *file, const char *dir)
{
    int fd = open(file, O_WRONLY);
    if (fd >= 0) {
        close(fd);
        return 1;               /* a 0600 file must not be writable by 501 */
    }
    if (errno != EACCES && errno != EPERM)
        return 2;

    if (unlink(file) == 0)
        return 3;               /* a 0700 directory must not be writable */
    if (errno != EACCES && errno != EPERM)
        return 4;
    return 0;
}

int
main(void)
{
    const char *dir = "/tmp/ravyn-perms";
    const char *file = "/tmp/ravyn-perms/secret";
    char buf[8];
    int fd, status, rc;
    pid_t pid;

    (void)mkdir(dir, 0700);
    fd = open(file, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        perror("create");
        return 1;
    }
    if (write(fd, "secret\n", 7) != 7) {
        perror("write");
        close(fd);
        return 1;
    }
    close(fd);
    chmod(dir, 0700);
    chmod(file, 0600);

    /* Root can still read it; the test is about the non-root uid. */
    fd = open(file, O_RDONLY);
    if (fd < 0) {
        perror("root read");
        return 1;
    }
    close(fd);

    pid = fork();
    if (pid == 0) {
        if (setgid(20) != 0 || setuid(501) != 0)
            _exit(10);
        _exit(child_checks(file, dir));
    }
    if (pid < 0) {
        perror("fork");
        return 1;
    }
    if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status)) {
        fprintf(stderr, "child did not exit\n");
        return 1;
    }
    rc = WEXITSTATUS(status);
    if (rc != 0) {
        fprintf(stderr, "permission check failed rc=%d\n", rc);
        return 1;
    }

    /* The same uid may read a world-readable file. */
    chmod(file, 0644);
    pid = fork();
    if (pid == 0) {
        if (setgid(20) != 0 || setuid(501) != 0)
            _exit(10);
        fd = open(file, O_RDONLY);
        if (fd < 0)
            _exit(11);
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        _exit(n == 7 ? 0 : 12);
    }
    if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status) ||
        WEXITSTATUS(status) != 0) {
        fprintf(stderr, "world-readable check failed\n");
        return 1;
    }

    unlink(file);
    rmdir(dir);
    printf("PASS perms\n");
    return 0;
}
