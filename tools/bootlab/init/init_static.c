/* ravynOS persistent PID-1 init, static/raw-syscall build.
 * Same flavor as the proven static staged cat (LC_UNIXTHREAD, no dyld):
 * open /dev/console, dup2, dump /hello.txt, then tick forever. */
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
#define SYS_dup2    90
#define SYS_fsync   95
#define O_WRONLY    1
#define O_RDWR      2
#define O_NOCTTY    0x20000

static void puts_(const char *s) {
	u64 n = 0;
	while (s[n]) n++;
	sys3(SYS_write, 1, (u64)s, n);
}

void start(void) {
	int cfd = (i64)sys2(SYS_open, (u64)"/dev/console", O_WRONLY | O_NOCTTY);
	if (cfd < 0)
		cfd = (i64)sys2(SYS_open, (u64)"/dev/console", O_RDWR | O_NOCTTY);
	if (cfd >= 0) {
		sys2(SYS_dup2, (u64)cfd, 1);
		sys2(SYS_dup2, (u64)cfd, 2);
		if (cfd > 2)
			sys1(SYS_close, (u64)cfd);
	}

	puts_("\n=== RAVYNOS PERSISTENT INIT RUNNING AS PID 1 ===\n");

	int rfd = (i64)sys2(SYS_open, (u64)"/hello.txt", 0);
	if (rfd >= 0) {
		char buf[256];
		for (;;) {
			i64 n = (i64)sys3(SYS_read, (u64)rfd, (u64)buf, 256);
			if (n <= 0)
				break;
			sys3(SYS_write, 1, (u64)buf, (u64)n);
		}
		sys1(SYS_close, (u64)rfd);
		puts_("init: cat /hello.txt done\n");
	} else {
		puts_("init: open /hello.txt failed\n");
	}
	sys1(SYS_fsync, 1);

	char out[32];
	for (u64 i = 1;; i++) {
		static const char pre[] = "[init] alive tick ";
		char d[16];
		int nd = 0;
		u64 v = i;
		u64 tmp = v;
		while (tmp) { nd++; tmp /= 10; }
		if (nd == 0) nd = 1;
		for (int j = nd - 1; j >= 0; j--) {
			d[j] = (char)('0' + (v % 10));
			v /= 10;
		}
		u64 n = 0;
		for (int j = 0; j < 18; j++) out[n++] = pre[j];
		for (int j = 0; j < nd; j++) out[n++] = d[j];
		out[n++] = '\n';
		sys3(SYS_write, 1, (u64)out, n);
		sys1(SYS_fsync, 1);
		/* busy-spin delay, same technique as the proven static stub */
		for (volatile long s = 0; s < 0x2000000L; s++)
			__asm__ volatile("pause");
	}
}
