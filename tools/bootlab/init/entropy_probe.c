/*
 * entropy_probe.c -- measure syscall 500 at the kernel boundary, then measure
 * malloc(16) end to end.
 *
 * WHY A SEPARATE PROBE
 * --------------------
 * The order matters.  malloc(16) is the last thing this program does, so
 * everything before it is measured while the allocator is still untouched.
 * If malloc(16) crashes the process, the entropy answers are already on the
 * serial log; if it does not, they explain why.  malloc_probe.c cannot do
 * this -- it allocates before it has said anything about the kernel.
 *
 * WHAT IS ACTUALLY MEASURED
 * -------------------------
 * [A] A POSITIVE CONTROL FIRST.  getpid(20) proves the 64-bit Unix-class
 *     syscall path delivers a result to userland at all.  A negative result
 *     later is only meaningful because this passed; without it, "getentropy
 *     returned ENOSYS" and "syscalls do not work" are indistinguishable.
 *
 * [B] syscall 500, raw.  Issued with the same encoding Libsystem's
 *     _getentropy.s uses (0x2000000 class bit OR 500).  The carry flag is
 *     read separately, because ravynOS returns errno in %rax WITH %cf set,
 *     so %rax alone cannot distinguish "0" from "errno 0".
 *
 * [C] syscall 500 with size 512.  The real implementation caps at 256 and
 *     returns EINVAL(22); a stub or an enosys slot would return 0 or 78.
 *     This is the discriminating control: it tells the two apart.
 *
 * [D] syscall 500 twice into different buffers.  Equal bytes would mean a
 *     constant fill rather than an entropy source.
 *
 * [E] Libsystem's getentropy(3), the wrapper malloc itself uses, so the
 *     value is the one the allocator would actually have consumed.
 *
 * [F] malloc(16), write 0x5a5a5a5a, read it back.  The read-back is the
 *     acceptance test; a non-NULL pointer on its own proves only that
 *     something was returned.
 *
 * [G] errno as libsystem reports it, and a second malloc/free round trip so
 *     the write-back is not the only thing that touches the heap.
 */
#include <stdlib.h>
#include <errno.h>
/* The SDK's unistd.h does not declare getentropy; the symbol is real (it is
 * what malloc calls) so declare it here rather than pull in another header. */
extern int getentropy(void *buf, unsigned long size);


typedef unsigned long u64;
typedef long i64;

static u64 sys3(u64 n, u64 a, u64 b, u64 c) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000UL), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
	return r;
}
static u64 sys2(u64 n, u64 a, u64 b) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000UL), "D"(a), "S"(b) : "rcx", "r11", "memory");
	return r;
}

/* Syscall 500 needs the carry flag: ravynOS reports failure as
 * (errno in %rax, %cf set), so %rax == 0 is ambiguous on its own. */
static u64 sys2_cf(u64 n, u64 a, u64 b, int *cf) {
	u64 r, fl;
	__asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000UL), "D"(a), "S"(b) : "rcx", "r11", "memory");
	__asm__ volatile("pushfq; popq %0" : "=r"(fl));
	*cf = (int)((fl >> 0) & 1);
	return r;
}

static int g_fd = 1;

static void emit(const char *s) {
	u64 n = 0;
	while (s[n]) n++;
	sys3(4, (u64)g_fd, (u64)s, n);
}

static char g_hex[24];

static void emit_hex(const char *label, u64 v) {
	static const char hx[] = "0123456789abcdef";
	int n = 0, i;
	emit(label);
	emit("=0x");
	for (i = 60; i >= 0; i -= 4)
		g_hex[n++] = hx[(v >> i) & 0xf];
	g_hex[n] = 0;
	emit(g_hex);
	emit("\n");
}

/* 16 bytes as hex, so a non-printable entropy value is still legible. */
static void emit_bytes(const char *label, const unsigned char *p, int n) {
	static const char hx[] = "0123456789abcdef";
	char buf[80];
	int i, k = 0;
	buf[k++] = ' ';
	buf[k++] = ' ';
	for (i = 0; i < n; i++) {
		buf[k++] = hx[(p[i] >> 4) & 0xf];
		buf[k++] = hx[p[i] & 0xf];
		if ((i & 7) == 7 && i != n - 1) {
			buf[k++] = '\n';
			buf[k++] = ' ';
			buf[k++] = ' ';
		}
	}
	buf[k++] = '\n';
	buf[k] = 0;
	emit(label);
	emit(buf);
}

int main(void) {
	unsigned char b1[32], b2[32], big[512];
	u64 pid;
	int cf = 0, r;
	void *p, *q;
	int i, same = 1, nonzero = 0;

	i64 cfd = (i64)sys2(5, (u64)"/dev/console", 2UL | 0x20000UL);
	if (cfd >= 0) {
		g_fd = (int)cfd;
		sys2(90, (u64)cfd, 1);
		sys2(90, (u64)cfd, 2);
	}
	emit("\n=== RAVYNOS ENTROPY + MALLOC PROBE ===\n");

	/* ---- [A] positive control: the 64-bit Unix syscall path works ---- */
	pid = sys2(20, 0, 0);
	emit("[A] getpid(20) = ");
	emit_hex("", pid);
	emit(pid != 0 ? "[A]   CONTROL OK: 64-bit unix syscalls reach userland\n"
	              : "[A]   CONTROL FAILED: syscalls do not work; every "
	                "result below is meaningless\n");

	/* ---- [B] syscall 500, the one malloc depends on ------------------ */
	for (i = 0; i < 32; i++) b1[i] = 0xa5;
	r = (int)sys2_cf(500, (u64)b1, 16, &cf);
	emit("[B] getentropy(buf,16): rax=");
	emit_hex("", (u64)(i64)r);
	emit_hex("[B]   cf            = ", (u64)cf);
	emit("[B]   -> ");
	emit((r == 0 && !cf) ? "SUCCESS (errno 0)\n" : "FAILURE\n");
	emit_bytes("[B]   16 bytes:", b1, 16);

	/* ---- [C] size 512: the real implementation returns EINVAL -------- */
	for (i = 0; i < 512; i++) big[i] = 0x5a;
	r = (int)sys2_cf(500, (u64)big, 512, &cf);
	emit("[C] getentropy(buf,512) [cap is 256]: rax=");
	emit_hex("", (u64)(i64)r);
	emit_hex("[C]   cf            = ", (u64)cf);
	emit("[C]   -> ");
	emit((r == 22 && cf) ? "EINVAL(22): the size-checking implementation is live\n"
	     : (r == 78 && cf) ? "ENOSYS(78): syscall 500 is an enosys slot\n"
	     : (r == 0 && !cf) ? "0: a stub that ignores the size, not the real code\n"
	     : "UNEXPECTED\n");

	/* ---- [D] two calls must differ, and must not be all zero -------- */
	for (i = 0; i < 32; i++) { b1[i] = 0; b2[i] = 0; }
	sys2_cf(500, (u64)b1, 16, &cf);
	sys2_cf(500, (u64)b2, 16, &cf);
	emit_bytes("[D]   call #1:", b1, 16);
	emit_bytes("[D]   call #2:", b2, 16);
	for (i = 0; i < 16; i++) {
		if (b1[i] != b2[i]) same = 0;
		if (b1[i] != 0) nonzero = 1;
	}
	emit_hex("[D]   two calls identical? ", (u64)same);
	emit_hex("[D]   any nonzero byte?    ", (u64)nonzero);

	/* ---- [E] the wrapper malloc itself uses ------------------------- */
	errno = 0;
	r = getentropy(b1, 16);
	emit("[E] libsystem getentropy(b,16) = ");
	emit_hex("", (u64)(i64)r);
	emit_hex("[E]   errno = ", (u64)(i64)errno);
	emit_bytes("[E]   16 bytes:", b1, 16);

	/* ---- [F] the acceptance test ------------------------------------ */
	emit("[F] before malloc(16)\n");
	p = malloc(16);
	emit("[F] after  malloc(16)\n");
	emit_hex("[F] malloc(16) = ", (u64)p);
	emit_hex("[F] NULL? = ", (p == 0) ? 1 : 0);
	if (p != 0) {
		*(volatile unsigned int *)p = 0x5a5a5a5a;
		emit_hex("[F] wrote 0x5a5a5a5a, read back = ",
		         *(volatile unsigned int *)p);
		emit_hex("[F] READ-BACK MATCH? = ",
		         (*(volatile unsigned int *)p == 0x5a5a5a5a) ? 1 : 0);
	}

	/* ---- [G] a second allocation, so the heap is exercised twice ----- */
	q = malloc(64);
	emit_hex("[G] malloc(64) = ", (u64)q);
	if (q != 0) {
		*(volatile unsigned long *)q = 0x0123456789abcdefUL;
		emit_hex("[G] wrote 0x0123456789abcdef, read back = ",
		         *(volatile unsigned long *)q);
		emit_hex("[G] READ-BACK MATCH? = ",
		         (*(volatile unsigned long *)q == 0x0123456789abcdefUL) ? 1 : 0);
		emit_hex("[G] heap delta (q-p) = ", (u64)((char *)q - (char *)p));
	}
	free(p);
	free(q);
	emit_hex("[G] errno after free = ", (u64)(i64)errno);
	emit("[Z] probe complete\n");
	sys2(1, 0, 0);
	for (;;)
		;
}
