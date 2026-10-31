/*
 * passwd -- the ravynos account must exist and its stored password must
 * authenticate through the same path the login window uses.
 *
 * WindowServer's login window calls getpwnam(name) and then
 * crypt(password, pw_passwd); libsystem_info answers that from
 * /etc/master.passwd when the caller is root, which is exactly what this
 * fixture (running at boot as root) exercises.
 *
 * The account is ravynos / ravynos, uid 502, gid 20 (staff), home
 * /Users/ravynos.  Nothing here invents a pass: a wrong password is required
 * not to match, so a locked or ignored hash fails the fixture.
 */
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

extern char *crypt(const char *, const char *);

static int
fail(const char *what)
{
	fprintf(stderr, "passwd: FAIL %s\n", what);
	return 1;
}

int
main(void)
{
	struct passwd *pw = getpwnam("ravynos");
	char *stored, *enc;

	printf("passwd: uid=%u euid=%u\n", (unsigned)getuid(), (unsigned)geteuid());

	if (pw == NULL)
		return fail("getpwnam(\"ravynos\") found no account");

	if (pw->pw_uid != 502)
		return fail("uid is not 502");
	if (pw->pw_gid != 20)
		return fail("gid is not 20 (staff)");
	if (pw->pw_dir == NULL || strcmp(pw->pw_dir, "/Users/ravynos") != 0)
		return fail("home is not /Users/ravynos");

	struct stat st;
	if (stat(pw->pw_dir, &st) != 0 || !S_ISDIR(st.st_mode))
		return fail("home directory /Users/ravynos does not exist");

	if (pw->pw_passwd != NULL && strncmp(pw->pw_passwd, "$6$", 3) != 0) {
		fprintf(stderr, "passwd: stored hash is not SHA-512: %s\n",
		    pw->pw_passwd);
		return fail("SHA-512 crypt is not in use");
	}
	if (pw->pw_passwd == NULL || pw->pw_passwd[0] == '\0' ||
	    pw->pw_passwd[0] == '*' || pw->pw_passwd[0] == '!') {
		fprintf(stderr, "passwd: stored field is \"%s\"\n",
			pw->pw_passwd ? pw->pw_passwd : "(null)");
		return fail("password is locked (no hash in master.passwd)");
	}

	/* crypt() returns a pointer to a static buffer; comparing its result
	 * with pw->pw_passwd directly would compare the buffer with itself. */
	stored = strdup(pw->pw_passwd);
	if (stored == NULL)
		return fail("out of memory");

	enc = crypt("ravynos", stored);
	if (enc == NULL || strcmp(enc, stored) != 0)
		return fail("crypt(\"ravynos\", hash) does not verify");

	enc = crypt("definitely-not-the-password", stored);
	if (enc != NULL && strcmp(enc, stored) == 0)
		return fail("a wrong password also verifies");

	printf("passwd: ravynos uid=%u gid=%u home=%s hash=%s verified\n",
	       (unsigned)pw->pw_uid, (unsigned)pw->pw_gid, pw->pw_dir,
	       stored);
	free(stored);
	return 0;
}
