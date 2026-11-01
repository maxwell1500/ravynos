/*
 * login -- console login with crypt(3) and the secure audit trail.
 *
 * The AppKit login window uses the same account store and crypt path; this
 * is the console fallback and the code the window's verifier mirrors.
 */
#include <err.h>
#include <grp.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

extern char *crypt(const char *, const char *);

#define SECURELOG "/var/log/secure"

static void
audit(const char *user, int ok)
{
	struct stat st;
	FILE *f;

	if (stat(SECURELOG, &st) == 0 && st.st_size > 1024 * 1024)
		rename(SECURELOG, SECURELOG ".0");
	f = fopen(SECURELOG, "a");
	if (f == NULL)
		return;
	fprintf(f, "AUDIT user=%s action=login result=%s pid=%d\n",
	    user, ok ? "ok" : "fail", (int)getpid());
	fclose(f);
}

int
main(int argc, char **argv)
{
	char name[64];
	struct passwd *pw;
	char *password, *stored, *enc;

	if (argc > 1)
		snprintf(name, sizeof(name), "%s", argv[1]);
	else {
		printf("login: ");
		fflush(stdout);
		if (fgets(name, sizeof(name), stdin) == NULL)
			return 1;
		name[strcspn(name, "\n")] = '\0';
	}
	if (name[0] == '\0')
		return 1;

	pw = getpwnam(name);
	if (pw == NULL) {
		audit(name, 0);
		errx(1, "unknown user: %s", name);
	}
	stored = strdup(pw->pw_passwd ? pw->pw_passwd : "");
	if (stored == NULL)
		err(1, "out of memory");
	if (stored[0] == '\0' || stored[0] == '*' || stored[0] == '!') {
		audit(name, 0);
		errx(1, "account %s is locked", name);
	}
	password = getpass("Password: ");
	enc = crypt(password, stored);
	if (enc == NULL || strcmp(enc, stored) != 0) {
		audit(name, 0);
		errx(1, "incorrect password");
	}
	free(stored);
	audit(name, 1);

	if (setgid(pw->pw_gid) != 0)
		err(1, "setgid");
	if (initgroups(pw->pw_name, pw->pw_gid) != 0)
		err(1, "initgroups");
	if (setuid(pw->pw_uid) != 0)
		err(1, "setuid");
	if (chdir(pw->pw_dir) != 0)
		warn("chdir %s", pw->pw_dir);
	setenv("HOME", pw->pw_dir, 1);
	setenv("USER", pw->pw_name, 1);
	setenv("SHELL", pw->pw_shell && pw->pw_shell[0] ? pw->pw_shell : "/bin/sh", 1);
	const char *shell = pw->pw_shell && pw->pw_shell[0] ? pw->pw_shell : "/bin/sh";
	execl(shell, "-sh", (char *)NULL);
	err(1, "exec");
}
