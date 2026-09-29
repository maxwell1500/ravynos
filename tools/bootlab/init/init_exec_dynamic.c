/* ravynOS dynamic-userland gate: static PID 1 that execve()s a DYNAMIC binary.
 *
 * WHY THIS EXISTS
 *   `run.sh full` cannot see the dynamic-userland path at all. Its PID 1 is
 *   init_static.c, which execs nothing: the boot reaches userland, ticks
 *   forever, and reports a clean result while every dyld-linked binary is
 *   untested. That blind spot is an instrument defect, not a kernel fact.
 *   This binary closes it. Staged as /sbin/launchd (manifest_dynamic.json)
 *   it forces the kernel to load dyld, resolve the libSystem closure and run
 *   a dylib-linked main() -- the path where the Sep-2026 faults lived.
 *
 *   It is deliberately static and freestanding (LC_UNIXTHREAD, no dyld), so
 *   the ONLY dynamic thing in the boot is the process it execs. If this
 *   binary were dyld-linked it could not distinguish its own loader failure
 *   from the target's.
 *
 * The Sep-26 MINI-SHELL used to fill this role by running /etc/rc. That
 * source is gone from the tree (only its serial log survives, in gitignored
 * work/), so the capability is re-established here from source rather than
 * left to be rediscovered as a mystery.
 */
typedef unsigned long u64;
typedef long i64;

/* freestanding: clang emits memset/memcpy for zero-init and struct copies
 * and we link -nostdlib, so they are provided here. */
void *memset(void *d, int c, u64 n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, u64 n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return p; }

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

#define SYS_exit    1
#define SYS_write   4
#define SYS_open    5
#define SYS_close   6
#define SYS_execve 59
#define SYS_dup2    90
#define SYS_fsync   95
#define O_WRONLY    1
#define O_NOCTTY    0x20000

/* The gate's success signature. run_dynamic_gate.sh greps for this exact
 * line, so it must be emitted only by the exec'd binary reaching main(). */
#define PASS_SIG "RAVYN-DYNAMIC-USERLAND-OK"

static void puts_(const char *s) {
	u64 n = 0;
	while (s[n]) n++;
	sys3(SYS_write, 1, (u64)s, n);
}

void start(void) {
	int cfd = (i64)sys2(SYS_open, (u64)"/dev/console", O_WRONLY | O_NOCTTY);
	if (cfd < 0)
		cfd = (i64)sys2(SYS_open, (u64)"/dev/console", 2 /* O_RDWR */ | O_NOCTTY);
	if (cfd >= 0) {
		sys2(SYS_dup2, (u64)cfd, 1);
		sys2(SYS_dup2, (u64)cfd, 2);
		if (cfd > 2)
			sys1(SYS_close, (u64)cfd);
	}

	puts_("\n=== RAVYNOS DYNAMIC-USERLAND GATE: execve /bin/echo ===\n");
	sys1(SYS_fsync, 1);

	u64 argv[3];
	argv[0] = (u64)"/bin/echo";
	argv[1] = (u64)PASS_SIG;
	argv[2] = 0;
	u64 envp[1];
	envp[0] = 0;

	i64 r = (i64)sys3(SYS_execve, (u64)"/bin/echo", (u64)argv, (u64)envp);
	/* Reaching here means the exec itself failed: no dyld, no dylib chain. */
	puts_("\nDYNAMIC-GATE-FAIL: execve /bin/echo returned nonzero (no dynamic run)\n");
	sys1(SYS_fsync, 1);
	for (;;) {
		for (volatile long s = 0; s < 0x2000000L; s++)
			__asm__ volatile("pause");
	}
}
