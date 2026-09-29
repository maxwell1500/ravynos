/* ravynOS PID-1 probe: does a byte typed on the console reach a userspace
 * read(2)?
 *
 * This isolates the KERNEL's serial receive path from the shell. The static
 * shell reaches its prompt but never echoes typed input and never wakes, and
 * a tty in canonical mode echoes on RECEIPT, before any process reads. So
 * "no echo at all" points below the shell, at the console/tty layer, and this
 * probe is the smallest thing that can tell the two apart.
 *
 * Shape is copied from init_shell.c: freestanding, raw syscalls, LC_UNIXTHREAD,
 * -nostdlib, so it inherits exactly what is already proven to boot. It opens
 * /dev/console, makes it the controlling terminal, then loops:
 *
 *     write "RX>" ; read(0, &c, 1) ; report what came back
 *
 * Every buffer is file-scope static: a local array makes clang emit
 * ___stack_chk_fail references that a -nostdlib link cannot resolve
 * (init_shell.c records the same constraint).
 */
typedef unsigned long u64;
typedef long          i64;

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
#define SYS_ioctl   54
#define SYS_dup2    90
#define SYS_setsid  147
#define O_RDWR      2
#define TIOCSCTTY   0x20007461UL

u64 strlen(const char *s) { u64 n = 0; while (s[n]) n++; return n; }

static void puts_(const char *s) { sys3(SYS_write, 1, (u64)s, strlen(s)); }

static char hexdig[24];
static char rxbuf[8];

static void puthex(u64 v) {
	static const char d[] = "0123456789abcdef";
	hexdig[0] = '0'; hexdig[1] = 'x';
	for (int i = 0; i < 16; i++) hexdig[2 + i] = d[(v >> ((15 - i) * 4)) & 0xf];
	hexdig[18] = '\n';
	sys3(SYS_write, 1, (u64)hexdig, 19);
}



void
start(void)
{
	i64 fd = (i64)sys3(SYS_open, (u64)"/dev/console", O_RDWR, 0);
	puts_("[probe] open /dev/console = ");
	puthex((u64)fd);
	if (fd < 0) {
		puts_("[probe] FATAL: no console\n");
		return;
	}
	sys2(SYS_dup2, (u64)fd, 0);
	sys2(SYS_dup2, (u64)fd, 1);
	sys2(SYS_dup2, (u64)fd, 2);
	sys1(SYS_setsid, 0);
	sys3(SYS_ioctl, (u64)fd, TIOCSCTTY, 0);
	puts_("[probe] console ready, entering RX loop\n");

	for (int i = 0; i < 500; i++) {
		puts_("[probe] RX> ");
		i64 n = (i64)sys3(SYS_read, 0, (u64)rxbuf, 4);
		puts_("[probe] read = ");
		puthex((u64)n);
		if (n > 0) {
			puts_("[probe] GOT ");
			sys3(SYS_write, 1, (u64)rxbuf, (u64)n);
			puts_("\n[probe] INPUT DELIVERED\n");
		}
	}
	puts_("[probe] loop done\n");
}
