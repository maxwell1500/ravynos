/* ravynOS PID-1 init that hands the console to /bin/sh.
 *
 * Same build shape as init_static.c (freestanding, raw syscalls, LC_UNIXTHREAD,
 * no dyld) so it inherits everything that is already proven to boot.  The only
 * thing it adds is: put /dev/console on fd 0/1/2, acquire it as the controlling
 * terminal, and exec the shell.
 *
 * Why the ordering is the way it is
 * ---------------------------------
 * setsid() creates a new session with no controlling terminal.  TIOCSCTTY can
 * then be granted.  The reverse order cannot work: a process that already has
 * a controlling terminal cannot be given a second one.
 *
 * Neither call is allowed to be fatal.  setsid() returns EPERM when the caller
 * is already a process group leader -- and PID 1 is very often exactly that --
 * but in that case the caller is already a session leader, which is precisely
 * the precondition TIOCSCTTY wants, so the ioctl alone is sufficient.  A shell
 * without a controlling terminal still reads and writes fd 0/1/2 correctly;
 * only job control is unavailable.  So a failure here costs job control, not
 * the shell, and must not stop the boot.
 *
 * Every step announces itself before the exec, because after a successful
 * execve this process is gone and any later failure would be silent.
 */
typedef unsigned long u64;
typedef long          i64;

/* freestanding: clang emits memset/memcpy calls (zero-init / struct copies)
 * and we link -nostdlib, so provide them here. */
void *memset(void *d, int c, u64 n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, u64 n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }

static u64 sys1(u64 n, u64 a) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000), "D"(a) : "rcx", "r11", "memory");
	return r;
}
static u64 sys2(u64 n, u64 a, u64 b) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000), "D"(a), "S"(b) : "rcx", "r11", "memory");
	return r;
}
static u64 sys3(u64 n, u64 a, u64 b, u64 c) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
	return r;
}

#define SYS_read    3
#define SYS_write   4
#define SYS_open    5
#define SYS_close   6
#define SYS_ioctl   54
#define SYS_execve  59
#define SYS_dup2    90
#define SYS_fsync   95
#define SYS_setsid  147
#define O_WRONLY    1
#define O_RDWR      2
#define O_NOCTTY    0x20000

/* _IO('t', 97) from bsd/sys/ttycom.h: _IOC(IOC_VOID,'t',97,0) */
#define TIOCSCTTY   0x20007461UL

/*
 * clang's loop-idiom recogniser rewrites simple walks into calls to strlen,
 * and puts_() below is exactly such a walk.  This image is linked
 * -nostdlib, so the symbol has to exist here; defining it is the same deal
 * as the memset/memcpy above, not a shortcut.
 */
u64 strlen(const char *s) { u64 n = 0; while (s[n]) n++; return n; }

#define my_strlen strlen

static void puts_(const char *s) {
	sys3(SYS_write, 1, (u64)s, my_strlen(s));
}

/*
 * errno reporting uses static storage, not stack arrays: this is a
 * freestanding image with no stack-protector runtime, and a local array is
 * enough to make the compiler emit ___stack_chk_fail references that cannot
 * be resolved here.  init_static.c avoids locals for the same reason.
 */
static char errdig[24];
static char errout[24];

static void puterr(const char *what, i64 e) {
	puts_(what);
	/* the kernel returns -errno, so print the sign explicitly */
	puts_(" errno=");
	if (e < 0) { puts_("-"); e = -e; }
	int nd = 0;
	u64 v = (u64)e;
	if (v == 0) errdig[nd++] = '0';
	while (v) { errdig[nd++] = (char)('0' + (v % 10)); v /= 10; }
	int n = 0;
	for (int j = nd - 1; j >= 0; j--) errout[n++] = errdig[j];
	errout[n] = 0;
	puts_(errout);
	puts_("\n");
}

void start(void) {
	puts_("\n=== RAVYNOS SHELL PID 1 ===\n");

	/*
	 * O_NOCTTY here: the open must not silently grab a controlling
	 * terminal, because the explicit setsid()+TIOCSCTTY sequence below is
	 * what establishes one, and doing both would make the order matter.
	 */
	i64 cfd = (i64)sys2(SYS_open, (u64)"/dev/console", O_RDWR | O_NOCTTY);
	if (cfd < 0) {
		puterr("init: open /dev/console failed errno", cfd);
		cfd = (i64)sys2(SYS_open, (u64)"/dev/console", O_WRONLY | O_NOCTTY);
	}
	if (cfd < 0) {
		puterr("init: open /dev/console ro failed errno", cfd);
		/* no console: still try to exec, so the failure is legible */
	} else {
		/* fd 0 as well as 1 and 2: the shell must be able to READ the
		 * console, which is the whole point of this change. */
		sys2(SYS_dup2, (u64)cfd, 0);
		sys2(SYS_dup2, (u64)cfd, 1);
		sys2(SYS_dup2, (u64)cfd, 2);
		if (cfd > 2)
			sys1(SYS_close, (u64)cfd);
		puts_("init: console on fd 0/1/2\n");
	}

	i64 sid = (i64)sys1(SYS_setsid, 0);
	if (sid < 0)
		puterr("init: setsid errno (continuing, job control only)", sid);
	else
		puts_("init: setsid ok, new session\n");

	i64 ct = (i64)sys3(SYS_ioctl, 0, TIOCSCTTY, 0);
	if (ct < 0)
		puterr("init: ioctl TIOCSCTTY errno (shell still runs)", ct);
	else
		puts_("init: TIOCSCTTY ok, console is controlling terminal\n");

	static char *argv[] = { (char *)"sh", (char *)"-i", 0 };
	static char *envp[] = { (char *)"PATH=/bin:/usr/bin", (char *)"TERM=dumb", (char *)"HOME=/", 0 };

	puts_("init: execve /bin/sh\n");
	sys3(SYS_fsync, 1, 0, 0);

	/* execve only returns on failure.  Keep the errno: after this the old
	 * image is gone and a failure would otherwise be silent. */
	i64 r = (i64)sys3(SYS_execve, (u64)"/bin/sh", (u64)argv, (u64)envp);

	/* Only reached if execve failed.  Say so loudly, then keep PID 1
	 * alive so the machine does not panic on init exit. */
	puterr("init: execve /bin/sh failed errno", r);

	for (u64 i = 1;; i++) {
		puts_("[init] SHELL FAILED TO START, alive tick\n");
		sys1(SYS_fsync, 1);
		for (volatile long s = 0; s < 0x2000000L; s++)
			__asm__ volatile("pause");
	}
}
