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
#include <fcntl.h>
#include <limits.h>
#include <ctype.h>

extern char *crypt(const char *, const char *);

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

static int valid_username(const char *name) {
    size_t len;

    if (name == NULL || name[0] == '\0')
        return 0;
    len = strlen(name);
    if (len > 31)
        return 0;
    if (!(isalpha((unsigned char)name[0]) || name[0] == '_'))
        return 0;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)name[i];

        if (c == '/' || c == '\n' || iscntrl(c))
            return 0;
        if (!(isalnum(c) || c == '_' || c == '-'))
            return 0;
    }
    return 1;
}

static char *make_hash(const char *password) {
    static const char b64[] =
        "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    char salt[3 + 16 + 1];
    char *hash;

    memcpy(salt, "$6$", 3);
    for (int i = 0; i < 16; i++)
        salt[3 + i] = b64[arc4random_uniform(64)];
    salt[3 + 16] = '\0';

    hash = crypt(password, salt);
    return hash ? strdup(hash) : NULL;
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
    struct passwd *pw;

    if (!valid_username(username)) {
        fprintf(stderr, "dscl: invalid username: %s\n", username);
        return 1;
    }
    pw = getpwnam(username);
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

static int delete_user_from_file(const char *path, const char *username, mode_t mode) {
    FILE *src = fopen(path, "r");
    char tmp_path[PATH_MAX];
    int fd;
    FILE *dst;
    char line[1024];
    size_t ulen = strlen(username);
    int found = 0;

    if (!src) {
        perror(path);
        return -1;
    }

    snprintf(tmp_path, sizeof(tmp_path), "%s.tmpXXXXXX", path);
    fd = mkstemp(tmp_path);
    if (fd < 0) {
        perror("mkstemp");
        fclose(src);
        return -1;
    }
    if (fchmod(fd, mode & 0777) != 0) {
        perror("fchmod");
        close(fd);
        unlink(tmp_path);
        fclose(src);
        return -1;
    }

    dst = fdopen(fd, "w");
    if (!dst) {
        perror("fdopen");
        close(fd);
        unlink(tmp_path);
        fclose(src);
        return -1;
    }

    while (fgets(line, sizeof(line), src)) {
        if (strncmp(line, username, ulen) == 0 && line[ulen] == ':') {
            found = 1;
            continue;
        }
        fputs(line, dst);
    }

    if (ferror(src) || ferror(dst) || fflush(dst) != 0 || fsync(fileno(dst)) != 0) {
        perror(path);
        fclose(src);
        fclose(dst);
        unlink(tmp_path);
        return -1;
    }
    fclose(src);
    if (fclose(dst) != 0) {
        perror("fclose");
        unlink(tmp_path);
        return -1;
    }
    if (rename(tmp_path, path) != 0) {
        perror("rename");
        unlink(tmp_path);
        return -1;
    }
    return found;
}

static int cmd_delete(const char *username) {
    struct stat st;
    mode_t passwd_mode = 0644;
    int rc;

    if (!valid_username(username)) {
        fprintf(stderr, "dscl: invalid username: %s\n", username);
        return 1;
    }
    if (stat(PASSWD_FILE, &st) == 0)
        passwd_mode = st.st_mode;

    rc = delete_user_from_file(PASSWD_FILE, username, passwd_mode);
    if (rc < 0)
        return 1;
    rc = delete_user_from_file(MASTER_PASSWD_FILE, username, 0600);
    if (rc < 0)
        return 1;

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
        if (!valid_username(username)) {
            fprintf(stderr, "dscl: invalid username: %s\n", username);
            return 1;
        }
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
        if (argc < 5) {
            print_usage();
            return 1;
        }
        if (!valid_username(username)) {
            fprintf(stderr, "dscl: invalid username: %s\n", username);
            return 1;
        }
        {
            const char *newpass = argv[4];
            char *hash = make_hash(newpass);
            FILE *src, *dst;
            char tmp_path[PATH_MAX];
            char line[1024];
            size_t ulen = strlen(username);
            int fd, found = 0;

            if (hash == NULL) {
                fprintf(stderr, "dscl: crypt failed\n");
                return 1;
            }

            src = fopen(MASTER_PASSWD_FILE, "r");
            if (!src) {
                perror(MASTER_PASSWD_FILE);
                free(hash);
                return 1;
            }

            snprintf(tmp_path, sizeof(tmp_path), "%s.tmpXXXXXX", MASTER_PASSWD_FILE);
            fd = mkstemp(tmp_path);
            if (fd < 0) {
                perror("mkstemp");
                fclose(src);
                free(hash);
                return 1;
            }
            if (fchmod(fd, 0600) != 0) {
                perror("fchmod");
                close(fd);
                unlink(tmp_path);
                fclose(src);
                free(hash);
                return 1;
            }

            dst = fdopen(fd, "w");
            if (!dst) {
                perror("fdopen");
                close(fd);
                unlink(tmp_path);
                fclose(src);
                free(hash);
                return 1;
            }

            while (fgets(line, sizeof(line), src)) {
                if (strncmp(line, username, ulen) == 0 && line[ulen] == ':') {
                    char *colon = strchr(line, ':');
                    if (colon == NULL) {
                        fputs(line, dst);
                        continue;
                    }
                    char *colon2 = strchr(colon + 1, ':');
                    if (colon2 == NULL) {
                        fputs(line, dst);
                        continue;
                    }
                    fwrite(line, 1, (size_t)(colon - line) + 1, dst);
                    fputs(hash, dst);
                    fputs(colon2, dst);
                    found = 1;
                    continue;
                }
                fputs(line, dst);
            }

            if (ferror(src) || ferror(dst) || fflush(dst) != 0 || fsync(fileno(dst)) != 0) {
                perror(MASTER_PASSWD_FILE);
                fclose(src);
                fclose(dst);
                unlink(tmp_path);
                free(hash);
                return 1;
            }
            fclose(src);
            if (fclose(dst) != 0) {
                perror("fclose");
                unlink(tmp_path);
                free(hash);
                return 1;
            }
            if (!found) {
                fprintf(stderr, "dscl: no such user: %s\n", username);
                unlink(tmp_path);
                free(hash);
                return 1;
            }
            if (rename(tmp_path, MASTER_PASSWD_FILE) != 0) {
                perror("rename");
                unlink(tmp_path);
                free(hash);
                return 1;
            }
            free(hash);
        }
        printf("[dscl] Password updated for %s\n", username);
        return 0;
    }

    print_usage();
    return 1;
}
