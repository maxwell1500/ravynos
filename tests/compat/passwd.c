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
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>

extern char *crypt(const char *, const char *);


static int
run_tool(char *const argv[])
{
	pid_t pid = fork();
	int status;

	if (pid < 0)
		return -1;
	if (pid == 0) {
		execv(argv[0], argv);
		_exit(127);
	}
	if (waitpid(pid, &status, 0) != pid)
		return -1;
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static int
file_contains(const char *path, const char *needle)
{
	char buf[8192];
	int fd = open(path, O_RDONLY);
	ssize_t n;

	if (fd < 0)
		return 0;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return 0;
	buf[n] = '\0';
	return strstr(buf, needle) != NULL;
}

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

	/* Exercise the account tools themselves, not just the lookup path:
	 * useradd must create the home and write an audit line, and userdel -r
	 * must remove it again. */
	char *addargv[] = { "/usr/sbin/useradd", "-m", "-u", "599", "-g",
	    "staff", "-c", "Compat Fixture", "-s", "/bin/sh", "-p", stored,
	    "fixtureuser", NULL };
	if (run_tool(addargv) != 0)
		return fail("useradd fixtureuser failed");
	if (stat("/Users/fixtureuser", &st) != 0 || !S_ISDIR(st.st_mode))
		return fail("useradd did not create /Users/fixtureuser");
	if (!file_contains("/var/log/secure",
	    "AUDIT user=fixtureuser action=useradd result=ok"))
		return fail("useradd did not write the audit line");

	char *delargv[] = { "/usr/sbin/userdel", "-r", "fixtureuser", NULL };
	if (run_tool(delargv) != 0)
		return fail("userdel fixtureuser failed");
	if (stat("/Users/fixtureuser", &st) == 0)
		return fail("userdel -r left the home directory behind");

	/* su runs as root here, so it must not prompt; the child exits 7 and
	 * su must preserve that status through setgid/setuid/exec. */
	char *suargv[] = { "/usr/bin/su", "-c", "exit 7", "ravynos", NULL };
	if (run_tool(suargv) != 7)
		return fail("su did not preserve the child exit status");
	if (!file_contains("/var/log/secure",
	    "AUDIT user=ravynos action=su result=ok"))
		return fail("su did not write the audit line");

	/* netstat reads NET_RT_IFLIST; en0 must be visible after DHCP. */
	FILE *nf = popen("/usr/bin/netstat -i", "r");
	if (nf == NULL)
		return fail("could not run netstat");
	char line[256];
	int saw_en0 = 0;
	while (fgets(line, sizeof(line), nf) != NULL)
		if (strstr(line, "en0") != NULL)
			saw_en0 = 1;
	pclose(nf);
	if (!saw_en0)
		return fail("netstat -i did not list en0");

	/* sysctl must read the kernel's own MIB, not a hardcoded string. */
	FILE *sf = popen("/usr/sbin/sysctl -n kern.ostype", "r");
	if (sf == NULL)
		return fail("could not run sysctl");
	char osline[64] = "";
	if (fgets(osline, sizeof(osline), sf) == NULL)
		osline[0] = '\0';
	pclose(sf);
	if (strstr(osline, "Darwin") == NULL)
		return fail("sysctl kern.ostype is not Darwin");

	FILE *uf = popen("/usr/bin/uname -s", "r");
	if (uf == NULL)
		return fail("could not run uname");
	char unline[64] = "";
	if (fgets(unline, sizeof(unline), uf) == NULL)
		unline[0] = '\0';
	pclose(uf);
	if (strstr(unline, "Darwin") == NULL)
		return fail("uname -s is not Darwin");

	FILE *dfp = popen("/bin/df", "r");
	if (dfp == NULL)
		return fail("could not run df");
	char dfline[256];
	int saw_mount = 0;
	while (fgets(dfline, sizeof(dfline), dfp) != NULL)
		if (strstr(dfline, "Mounted on") != NULL ||
		    strstr(dfline, " /") != NULL)
			saw_mount = 1;
	pclose(dfp);
	if (!saw_mount)
		return fail("df listed no mounted filesystem");

	printf("passwd: ravynos uid=%u gid=%u home=%s hash=%s verified\n",
	       (unsigned)pw->pw_uid, (unsigned)pw->pw_gid, pw->pw_dir,
	       stored);
	free(stored);
	return 0;
}
