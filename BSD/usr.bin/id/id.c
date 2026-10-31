/*
 * id(1) for ravynOS -- the process identities as implemented by POSIX.
 *
 * This tree carries BSD/usr.bin/id's Makefile and man page but not the
 * sources, so MacPorts died at startup with
 *   couldn't execute "id": no such file or directory
 * (mportinit runs `exec id -u`).  This is the subset that matters on a
 * single-user image: -u -g -G -n -r over the current process or a named
 * user.  groups(1) and whoami(1) are the same program, as the Makefile's
 * LINKS lines declare.
 */
#include <sys/types.h>
#include <sys/param.h>

#include <err.h>
#include <grp.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int flag_u, flag_g, flag_G, flag_n, flag_r;

static const char *uid_name(uid_t uid, char *buf, size_t len) {
    struct passwd *pw = getpwuid(uid);
    if (flag_n) {
        if (pw == NULL)
            warnx("no name for uid %u", (unsigned)uid);
        return pw ? pw->pw_name : buf;
    }
    snprintf(buf, len, "%u", (unsigned)uid);
    return buf;
}

static const char *gid_name(gid_t gid, char *buf, size_t len) {
    struct group *gr = getgrgid(gid);
    if (flag_n) {
        if (gr == NULL)
            warnx("no name for gid %u", (unsigned)gid);
        return gr ? gr->gr_name : buf;
    }
    snprintf(buf, len, "%u", (unsigned)gid);
    return buf;
}

static void print_uid(uid_t uid) {
    char buf[64];
    printf("%s\n", uid_name(uid, buf, sizeof(buf)));
}

static void print_gid(gid_t gid) {
    char buf[64];
    printf("%s\n", gid_name(gid, buf, sizeof(buf)));
}

/* -G: effective gid first, then every supplementary group. */
static void print_groups(uid_t uid, gid_t gid) {
    gid_t list[NGROUPS_MAX];
    char buf[64];
    int n = 0;

    if (uid == getuid()) {
        n = getgroups((int)(sizeof(list) / sizeof(list[0])), list);
        if (n < 0)
            err(1, "getgroups");
    }

    printf("%s", gid_name(gid, buf, sizeof(buf)));
    for (int i = 0; i < n; i++)
        if (list[i] != gid)
            printf(" %s", gid_name(list[i], buf, sizeof(buf)));
    printf("\n");
}

static void print_default(uid_t uid, gid_t gid) {
    struct passwd *pw = getpwuid(uid);
    struct group *gr = getgrgid(gid);

    printf("uid=%u(%s) gid=%u(%s)", (unsigned)uid, pw ? pw->pw_name : "?",
           (unsigned)gid, gr ? gr->gr_name : "?");

    if (uid == getuid()) {
        gid_t list[NGROUPS_MAX];
        int n = getgroups((int)(sizeof(list) / sizeof(list[0])), list);
        int first = 1;
        for (int i = 0; i < n; i++) {
            if (list[i] == gid)
                continue;
            struct group *g = getgrgid(list[i]);
            printf("%s%u(%s)", first ? " groups=" : ",", (unsigned)list[i],
                   g ? g->gr_name : "?");
            first = 0;
        }
    }
    printf("\n");
}

static void usage(void) {
    fprintf(stderr, "usage: id [-Ggu] [-nr] [user]\n");
    exit(1);
}

int main(int argc, char **argv) {
    int ch;
    uid_t uid = geteuid();
    gid_t gid = getegid();

    const char *prog = strrchr(argv[0], '/');
    prog = prog ? prog + 1 : argv[0];

    if (strcmp(prog, "whoami") == 0) {
        struct passwd *pw = getpwuid(uid);
        if (pw == NULL)
            errx(1, "no name for uid %u", (unsigned)uid);
        printf("%s\n", pw->pw_name);
        return 0;
    }
    if (strcmp(prog, "groups") == 0) {
        flag_G = 1;
        flag_n = 1;
        flag_r = 1;
    }

    while ((ch = getopt(argc, argv, "Ggnru")) != -1) {
        switch (ch) {
        case 'G': flag_G = 1; break;
        case 'g': flag_g = 1; break;
        case 'n': flag_n = 1; break;
        case 'r': flag_r = 1; break;
        case 'u': flag_u = 1; break;
        default:  usage();
        }
    }
    argc -= optind;
    argv += optind;

    if (argc > 1)
        usage();

    if (argc == 1) {
        struct passwd *pw = getpwnam(argv[0]);
        if (pw == NULL) {
            char *end = NULL;
            unsigned long v = strtoul(argv[0], &end, 10);
            if (end != NULL && *end == '\0')
                pw = getpwuid((uid_t)v);
        }
        if (pw == NULL)
            errx(1, "no such user: %s", argv[0]);
        uid = pw->pw_uid;
        gid = pw->pw_gid;
    } else if (flag_r) {
        uid = getuid();
        gid = getgid();
    }

    if (flag_u) { print_uid(uid); return 0; }
    if (flag_g) { print_gid(gid); return 0; }
    if (flag_G) { print_groups(uid, gid); return 0; }
    print_default(uid, gid);
    return 0;
}
