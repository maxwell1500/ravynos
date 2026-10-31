/*
 * posix.c -- ABI conformance fixture for ravynOS.
 *
 * Built on the host by Apple's toolchain against Apple's macOS SDK
 * (see build-fixtures.sh), so a passing run proves that the ravynOS
 * libSystem/BSD layer satisfies the same ABI a stock macOS binary was
 * compiled against.  Nothing here is ravynOS-specific: every call is
 * plain POSIX that any macOS command-line tool may use.
 *
 * Each check prints "PASS <name>" or "FAIL <name>: <detail>", and the last
 * line is "FIXTURE posix rc=<failures>".
 */

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>

static int failures;

static void
check(const char *name, int ok, const char *detail)
{
    if (ok) {
        printf("PASS %s\n", name);
    } else {
        printf("FAIL %s: %s\n", name, detail ? detail : "failed");
        failures++;
    }
    fflush(stdout);
}

/* --- pthreads ------------------------------------------------------- */

struct shared {
    pthread_mutex_t lock;
    pthread_cond_t  cond;
    int             value;
    int             done;
};

static void *
thread_main(void *arg)
{
    struct shared *s = arg;

    pthread_mutex_lock(&s->lock);
    s->value = 42;
    s->done = 1;
    pthread_cond_signal(&s->cond);
    pthread_mutex_unlock(&s->lock);
    return (void *)(intptr_t)7;
}

static void
test_pthreads(void)
{
    pthread_t t;
    struct shared s;
    void *ret = NULL;
    struct timespec ts;
    int rc;

    memset(&s, 0, sizeof(s));
    pthread_mutex_init(&s.lock, NULL);
    pthread_cond_init(&s.cond, NULL);

    rc = pthread_create(&t, NULL, thread_main, &s);
    check("pthread_create", rc == 0, strerror(rc));

    pthread_mutex_lock(&s.lock);
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += 5;
    while (!s.done) {
        rc = pthread_cond_timedwait(&s.cond, &s.lock, &ts);
        if (rc == ETIMEDOUT) {
            break;
        }
    }
    check("pthread_cond_timedwait", s.done, "thread did not signal");
    check("pthread_mutex_data", s.value == 42, "value was not published");
    pthread_mutex_unlock(&s.lock);

    rc = pthread_join(t, &ret);
    check("pthread_join", rc == 0 && ret == (void *)(intptr_t)7,
        "join failed or return value lost");

    pthread_cond_destroy(&s.cond);
    pthread_mutex_destroy(&s.lock);
}

/* --- memory --------------------------------------------------------- */

static void
test_mmap(void)
{
    size_t len = 1 << 20;
    char *p = mmap(NULL, len, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANON, -1, 0);

    if (p == MAP_FAILED) {
        check("mmap", 0, strerror(errno));
        return;
    }
    memset(p, 0xa5, len);
    check("mmap", p[0] == (char)0xa5 && p[len - 1] == (char)0xa5,
        "mapping did not hold written bytes");

    int rc = munmap(p, len);
    check("munmap", rc == 0, strerror(errno));
}

/* --- sockets -------------------------------------------------------- */

static void
test_socket(void)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa;
    int rc;

    check("socket", fd >= 0, strerror(errno));
    if (fd < 0) {
        return;
    }

    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(1);
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    rc = connect(fd, (struct sockaddr *)&sa, sizeof(sa));
    /* Either the connection succeeds or the stack refuses it.  What must
     * not happen is a missing syscall: ENOSYS, EBADF or a crash. */
    check("connect-loopback",
        rc == 0 || errno == ECONNREFUSED, strerror(errno));

    close(fd);
}

/* --- fork/exec ------------------------------------------------------ */

static void
test_fork_exec(void)
{
    pid_t pid = fork();
    int status = 0;

    if (pid == 0) {
        char *argv[] = { (char *)"/bin/echo", (char *)"compat-child", NULL };
        extern char **environ;
        execve("/bin/echo", argv, environ);
        _exit(127);
    }
    check("fork", pid > 0, strerror(errno));
    if (pid <= 0) {
        return;
    }
    if (waitpid(pid, &status, 0) != pid) {
        check("waitpid", 0, strerror(errno));
        return;
    }
    check("execve/echo", WIFEXITED(status) && WEXITSTATUS(status) == 0,
        "child did not exit 0");
}

/* --- signals -------------------------------------------------------- */

static volatile sig_atomic_t got_signal;

static void
sig_handler(int sig)
{
    (void)sig;
    got_signal = 1;
}

static void
test_signals(void)
{
    struct sigaction sa;

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sig_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    raise(SIGUSR1);
    check("sigaction", got_signal == 1, "handler did not run");
}

/* --- time ----------------------------------------------------------- */

static void
test_nanosleep(void)
{
    struct timespec ts = { 0, 10 * 1000 * 1000 };   /* 10 ms */
    int rc = nanosleep(&ts, NULL);

    check("nanosleep", rc == 0, strerror(errno));
}

/* --- filesystem ----------------------------------------------------- */

static void
test_filesystem(void)
{
    DIR *d = opendir("/");
    struct dirent *e;
    int count = 0;
    struct stat st;

    check("opendir", d != NULL, strerror(errno));
    if (d == NULL) {
        return;
    }
    while ((e = readdir(d)) != NULL) {
        count++;
    }
    closedir(d);
    check("readdir", count > 2, "root directory looks empty");

    check("stat-root", stat("/", &st) == 0 && S_ISDIR(st.st_mode),
        strerror(errno));

    /* Create, write, read back, unlink: the path a browser profile needs. */
    const char *path = "/tmp/ravyn-compat-posix";
    int fd = open(path, O_CREAT | O_TRUNC | O_RDWR, 0600);
    if (fd < 0) {
        check("open-create", 0, strerror(errno));
        return;
    }
    check("write", write(fd, "compat", 6) == 6, strerror(errno));
    lseek(fd, 0, SEEK_SET);
    char buf[8] = { 0 };
    check("read-back", read(fd, buf, 6) == 6 && memcmp(buf, "compat", 6) == 0,
        "content did not round-trip");
    close(fd);
    check("unlink", unlink(path) == 0, strerror(errno));
}

int
main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);

    test_pthreads();
    test_mmap();
    test_socket();
    test_fork_exec();
    test_signals();
    test_nanosleep();
    test_filesystem();

    printf("FIXTURE posix rc=%d\n", failures);
    return failures == 0 ? 0 : 1;
}
