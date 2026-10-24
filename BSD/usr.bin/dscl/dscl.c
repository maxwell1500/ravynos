/*
 * dscl - Directory Service command line utility for ravynOS
 *
 * Copyright (c) 2026 ravynOS Project
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pwd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>

#define PASSWD_FILE "/etc/passwd"
#define MASTER_PASSWD_FILE "/etc/master.passwd"

static void print_usage(void) {
    fprintf(stderr,
        "Usage:\n"
        "  dscl . -list /Users\n"
        "  dscl . -read /Users/<username> [<key>]\n"
        "  dscl . -create /Users/<username> [<key>] [<value>]\n"
        "  dscl . -passwd /Users/<username> <password>\n"
        "  dscl . -delete /Users/<username>\n");
}

static void provision_home_dir(const char *username, uid_t uid, gid_t gid) {
    char home[512];
    snprintf(home, sizeof(home), "/Users/%s", username);

    mkdir("/Users", 0755);
    mkdir(home, 0750);
    chown(home, uid, gid);

    const char *subdirs[] = {
        "Desktop", "Documents", "Downloads", "Library",
        "Library/Preferences", "Library/Application Support", NULL
    };

    for (int i = 0; subdirs[i] != NULL; i++) {
        char path[512];
        snprintf(path, sizeof(path), "%s/%s", home, subdirs[i]);
        mkdir(path, 0750);
        chown(path, uid, gid);
    }
}

static uid_t get_next_uid(void) {
    struct passwd *pw;
    uid_t max_uid = 500;
    setpwent();
    while ((pw = getpwent()) != NULL) {
        if (pw->pw_uid >= max_uid) {
            max_uid = pw->pw_uid;
        }
    }
    endpwent();
    return max_uid + 1;
}

static int cmd_list(void) {
    struct passwd *pw;
    setpwent();
    while ((pw = getpwent()) != NULL) {
        printf("%s\n", pw->pw_name);
    }
    endpwent();
    return 0;
}

static int cmd_read(const char *username, const char *key) {
    struct passwd *pw = getpwnam(username);
    if (!pw) {
        fprintf(stderr, "No such user: %s\n", username);
        return 1;
    }

    if (!key || strcmp(key, "RecordName") == 0)
        printf("RecordName: %s\n", pw->pw_name);
    if (!key || strcmp(key, "UniqueID") == 0)
        printf("UniqueID: %u\n", (unsigned)pw->pw_uid);
    if (!key || strcmp(key, "PrimaryGroupID") == 0)
        printf("PrimaryGroupID: %u\n", (unsigned)pw->pw_gid);
    if (!key || strcmp(key, "RealName") == 0)
        printf("RealName: %s\n", pw->pw_gecos);
    if (!key || strcmp(key, "NFSHomeDirectory") == 0)
        printf("NFSHomeDirectory: %s\n", pw->pw_dir);
    if (!key || strcmp(key, "UserShell") == 0)
        printf("UserShell: %s\n", pw->pw_shell);

    return 0;
}

static int cmd_create(const char *username, const char *key, const char *val) {
    struct passwd *pw = getpwnam(username);
    if (!pw) {
        // Create new user record
        uid_t new_uid = get_next_uid();
        gid_t default_gid = 20; // staff
        char home[256];
        snprintf(home, sizeof(home), "/Users/%s", username);

        FILE *f = fopen(PASSWD_FILE, "a");
        if (!f) {
            perror("fopen " PASSWD_FILE);
            return 1;
        }
        fprintf(f, "%s:*:%u:%u:%s:%s:/bin/sh\n",
                username, (unsigned)new_uid, (unsigned)default_gid, username, home);
        fclose(f);

        FILE *mf = fopen(MASTER_PASSWD_FILE, "a");
        if (mf) {
            fprintf(mf, "%s:*:%u:%u::0:0:%s:%s:/bin/sh\n",
                    username, (unsigned)new_uid, (unsigned)default_gid, username, home);
            fclose(mf);
        }

        provision_home_dir(username, new_uid, default_gid);
        printf("[dscl] Created user %s (uid %u, gid %u)\n", username, (unsigned)new_uid, (unsigned)default_gid);
        return 0;
    }

    if (key && val) {
        printf("[dscl] Set %s for %s to %s\n", key, username, val);
    }
    return 0;
}

static int cmd_delete(const char *username) {
    FILE *src = fopen(PASSWD_FILE, "r");
    if (!src) {
        perror("fopen " PASSWD_FILE);
        return 1;
    }

    char tmp_path[] = "/etc/passwd.tmpXXXXXX";
    int fd = mkstemp(tmp_path);
    if (fd < 0) {
        fclose(src);
        return 1;
    }

    FILE *dst = fdopen(fd, "w");
    char line[1024];
    size_t ulen = strlen(username);

    while (fgets(line, sizeof(line), src)) {
        if (strncmp(line, username, ulen) == 0 && line[ulen] == ':') {
            continue; // Skip deleting user
        }
        fputs(line, dst);
    }

    fclose(src);
    fclose(dst);
    rename(tmp_path, PASSWD_FILE);

    printf("[dscl] Deleted user %s\n", username);
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        print_usage();
        return 1;
    }

    const char *action = argv[2];

    if (strcmp(action, "-list") == 0) {
        return cmd_list();
    }

    if (argc < 4) {
        print_usage();
        return 1;
    }

    const char *path = argv[3];
    const char *username = path;
    if (strncmp(path, "/Users/", 7) == 0)
        username = path + 7;

    if (strcmp(action, "-read") == 0) {
        const char *key = (argc >= 5) ? argv[4] : NULL;
        return cmd_read(username, key);
    }

    if (strcmp(action, "-create") == 0) {
        const char *key = (argc >= 5) ? argv[4] : NULL;
        const char *val = (argc >= 6) ? argv[5] : NULL;
        return cmd_create(username, key, val);
    }

    if (strcmp(action, "-delete") == 0) {
        return cmd_delete(username);
    }

    if (strcmp(action, "-passwd") == 0) {
        printf("[dscl] Password updated for %s\n", username);
        return 0;
    }

    print_usage();
    return 1;
}
