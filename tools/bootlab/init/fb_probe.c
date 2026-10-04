/*
 * ravynOS framebuffer display probe -- freestanding static PID-1 payload.
 *
 * Same shape as init/init_static.c and init/mach_probe.c: an MH_EXECUTE
 * Mach-O with LC_UNIXTHREAD, no LC_LOAD_DYLIB, linked -static, entered at
 * _start.  Raw BSD syscalls only, numbers OR'd with the Unix class bit
 * (0x2000000).  No libSystem, no dyld.
 *
 * What it measures: whether /dev/fb0 opens, whether FBIOGTYPE and
 * FBIO_GETLINEWIDTH describe the live GOP scanout, whether mmap() of the
 * character device succeeds, and whether a store through the resulting
 * mapping reaches the memory QEMU's screendump captures.
 *
 * The mmap() return value is printed raw because the kernel's char-device
 * mmap path (bsd/kern/kern_mman.c, the d_mmap branch) stores the address as
 * `*retval = (int)mmap_device_addr`, so a mapping above 4 GiB comes back
 * truncated to its low 32 bits.  When the returned value is not a plausible
 * 64-bit user address, the probe scans `low32 + k*2^32` for the real
 * mapping using mprotect(), which reports mapped-vs-unmapped without ever
 * faulting on the address being tested.
 *
 * A store lands in scanout memory only if the kernel really installed a
 * MAP_SHARED alias of the framebuffer; the readback below is what proves it
 * (device memory is uncached, so the value read back is the value written).
 */

typedef unsigned long  u64;
typedef long           i64;
typedef unsigned int   u32;
typedef unsigned char  u8;

/* freestanding: clang emits these for zero-init and struct copies, and we
 * link -nostdlib, so provide them here. */
void *memset(void *d, int c, u64 n) { u8 *p = d; while (n--) *p++ = (u8)c; return d; }
void *memcpy(void *d, const void *s, u64 n) { u8 *p = d; const u8 *q = s; while (n--) *p++ = *q++; return d; }

static u64 strlen_(const char *s) { u64 n = 0; while (s[n]) n++; return n; }

/* BSD syscalls carry the Unix class bit; the kernel's sysent table is
 * indexed by the low bits (bsd/dev/i386/systemcalls.c). */
#define SC_UNIX 0x2000000UL

#define SYS_write    4
#define SYS_open     5
#define SYS_close    6
#define SYS_mprotect 74
#define SYS_dup2     90
#define SYS_ioctl    54
#define SYS_mmap     197
#define SYS_fsync    95

#define O_RDWR       2
#define O_NOCTTY     0x20000

#define PROT_READ    1
#define PROT_WRITE   2
#define MAP_SHARED   1
#define MAP_PRIVATE  2
#define MAP_ANON     0x1000

/* _IOR('f', 0, struct fbtype) and _IOWR('f', 2, unsigned int), computed from
 * bsd/sys/ioccom.h: IOC_OUT|((52&0x1fff)<<16)|('f'<<8)|0 and
 * IOC_INOUT|((4&0x1fff)<<16)|('f'<<8)|2.  Must match sys/fbio.h exactly. */
#define FBIOGTYPE         0x40346600UL
#define FBIO_GETLINEWIDTH 0xC0046602UL

/*
 * The kernel returns a BSD syscall's errno in rax with CF set; a raw caller
 * that ignores CF cannot tell a small fd from an errno.  Every helper below
 * captures CF so g_err is exact.
 */
static int g_err;

static u64 sys1(u64 n, u64 a) {
	u64 r; unsigned long cf;
	__asm__ volatile("syscall\n\tsetc %b1"
	    : "=a"(r), "=r"(cf)
	    : "a"(n | SC_UNIX), "D"(a)
	    : "rcx", "r11", "memory");
	g_err = (cf & 1) ? (int)r : 0;
	return r;
}

static u64 sys2(u64 n, u64 a, u64 b) {
	u64 r; unsigned long cf;
	__asm__ volatile("syscall\n\tsetc %b1"
	    : "=a"(r), "=r"(cf)
	    : "a"(n | SC_UNIX), "D"(a), "S"(b)
	    : "rcx", "r11", "memory");
	g_err = (cf & 1) ? (int)r : 0;
	return r;
}

static u64 sys3(u64 n, u64 a, u64 b, u64 c) {
	u64 r; unsigned long cf;
	__asm__ volatile("syscall\n\tsetc %b1"
	    : "=a"(r), "=r"(cf)
	    : "a"(n | SC_UNIX), "D"(a), "S"(b), "d"(c)
	    : "rcx", "r11", "memory");
	g_err = (cf & 1) ? (int)r : 0;
	return r;
}

/*
 * Six-argument BSD syscall.  The saved-state struct the kernel copies
 * uu_arg[] from is {rdi, rsi, rdx, r10, r8, r9} (osfmk/mach/i386/
 * thread_status.h), so arg4 goes in r10, arg5 in r8, arg6 in r9 -- the
 * standard x86_64 syscall ABI.  r10/r8/r9 are declared clobbered so the
 * compiler cannot hand an input to a register the movs overwrite.
 */
static u64 sys6(u64 n, u64 a, u64 b, u64 c, u64 d, u64 e, u64 f) {
	u64 r; unsigned long cf;
	__asm__ volatile(
	    "movq %6, %%r10\n\t"
	    "movq %7, %%r8\n\t"
	    "movq %8, %%r9\n\t"
	    "syscall\n\t"
	    "setc %b1"
	    : "=a"(r), "=r"(cf)
	    : "a"(n | SC_UNIX), "D"(a), "S"(b), "d"(c), "r"(d), "r"(e), "r"(f)
	    : "rcx", "r10", "r8", "r9", "r11", "memory");
	g_err = (cf & 1) ? (int)r : 0;
	return r;
}

static void out(const char *s) { sys3(SYS_write, 1, (u64)s, strlen_(s)); }

static void out_hex(u64 v) {
	static const char d[] = "0123456789abcdef";
	char b[19];
	b[0] = '0'; b[1] = 'x';
	for (int i = 0; i < 16; i++) {
		b[2 + i] = d[(v >> (60 - 4 * i)) & 0xf];
	}
	b[18] = 0;
	out(b);
}

static void out_dec(u64 v) {
	char b[24];
	int n = 0;
	if (v == 0) {
		b[n++] = '0';
	} else {
		char t[24];
		int m = 0;
		while (v) { t[m++] = (char)('0' + (v % 10)); v /= 10; }
		while (m) { b[n++] = t[--m]; }
	}
	b[n] = 0;
	out(b);
}

/* Flat 4.3BSD layout, exactly as sys/fbio.h declares it. */
struct fbtype {
	char           fb_name[16];
	unsigned short fb_type;
	unsigned short fb_height;
	unsigned short fb_width;
	unsigned short fb_pad1;
	unsigned int   fb_pad2;
	unsigned int   fb_memsize;
	unsigned int   fb_linebytes;
	unsigned int   fb_base;
	unsigned int   fb_sizex;
	unsigned int   fb_sizey;
	unsigned short fb_vertinc;
	unsigned short fb_depth;
};

/* Four vertical colour bars across the whole surface.  Byte order is the
 * GOP's 32bpp BGRX, but every bar is non-black in any interpretation, which
 * is all the proof needs. */
static void paint(u64 base, u32 width, u32 height, u32 stride_bytes) {
	volatile u32 *fb = (volatile u32 *)base;
	u32 stride_px = stride_bytes / 4;

	if (!width || !height || !stride_px) {
		return;
	}
	for (u32 y = 0; y < height; y++) {
		volatile u32 *row = fb + (u64)y * stride_px;
		for (u32 x = 0; x < width; x++) {
			u32 bar = (u32)(((u64)x * 4) / width);
			u32 c;
			if (bar == 0) {
				c = 0xFFFFFFFFu;
			} else if (bar == 1) {
				c = 0x00FF0000u;
			} else if (bar == 2) {
				c = 0x0000FF00u;
			} else {
				c = 0x000000FFu;
			}
			row[x] = c;
		}
	}
}

/*
 * Optional diagnostic, NOT part of the default build.
 *
 * While the kernel truncated the device-mmap return value, the only way to
 * reach the mapping was to reconstruct the real address: it must be
 * low32 + k*2^32 for some k >= 1, so walk k and ask mprotect() whether a
 * mapping of the whole framebuffer size exists there.  mprotect answers
 * mapped-vs-unmapped with an errno and never dereferences the address, so a
 * wrong candidate is harmless, and requiring the *whole* size separates the
 * 3 MiB framebuffer alias from the 8 KiB executable image.
 *
 * Build with -DFB_PROBE_WITH_SCAN to enable it.  The default build refuses
 * to scan on purpose: mmap() must return an address the caller can use
 * directly, so a silent fallback would hide exactly the regression this
 * probe exists to catch.
 */
#ifdef FB_PROBE_WITH_SCAN
static u64 scan_for_mapping(u64 trunc, u64 len) {
	u32 low = (u32)trunc;
	u64 found = 0;
	int shown = 0;

	for (u64 k = 1; k <= 0x100; k++) {
		u64 cand = (u64)low + (k << 32);
		if (cand < 0x100000000ULL || (cand & 0xfffULL)) {
			continue;
		}
		sys3(SYS_mprotect, cand, len, PROT_READ | PROT_WRITE);
		if (shown < 6) {
			out("[fb]   cand "); out_hex(cand);
			out(" mprotect errno="); out_dec((u64)g_err); out("\n");
			shown++;
		}
		if (g_err == 0) {
			found = cand;
			break;
		}
	}
	return found;
}
#endif /* FB_PROBE_WITH_SCAN */

static void idle(void) {
	for (u64 i = 1;; i++) {
		out("[fb] alive tick ");
		out_dec(i);
		out("\n");
		sys1(SYS_fsync, 1);
		for (volatile long s = 0; s < 0x2000000L; s++) {
			__asm__ volatile("pause");
		}
	}
}

void start(void) {
	int cfd = (i64)sys2(SYS_open, (u64)"/dev/console", O_RDWR | O_NOCTTY);
	if (g_err != 0) {
		cfd = (i64)sys2(SYS_open, (u64)"/dev/console", O_RDWR | O_NOCTTY);
	}
	if (g_err == 0 && cfd >= 0) {
		sys2(SYS_dup2, (u64)cfd, 1);
		sys2(SYS_dup2, (u64)cfd, 2);
		if (cfd > 2) {
			sys1(SYS_close, (u64)cfd);
		}
	}

	out("\n=== RAVYNOS FB DISPLAY PROBE (static PID-1) ===\n");

	u64 rfd = sys2(SYS_open, (u64)"/dev/fb0", O_RDWR | O_NOCTTY);
	int fd = g_err ? -1 : (int)rfd;
	out("[fb] open /dev/fb0 O_RDWR -> fd="); out_dec((u64)(i64)fd);
	out(" errno="); out_dec((u64)g_err); out("\n");
	if (fd < 0) {
		out("[fb] open failed; mmap is impossible\n");
		idle();
	}

	struct fbtype fb;
	memset(&fb, 0, sizeof(fb));
	u64 rio = sys3(SYS_ioctl, (u64)(u32)fd, FBIOGTYPE, (u64)&fb);
	int io_err = g_err;
	out("[fb] ioctl(FBIOGTYPE) ret="); out_hex(rio);
	out(" errno="); out_dec((u64)io_err); out("\n");
	out("[fb]   name="); out(fb.fb_name);
	out(" type="); out_dec(fb.fb_type);
	out(" width="); out_dec(fb.fb_width);
	out(" height="); out_dec(fb.fb_height);
	out(" depth="); out_dec(fb.fb_depth);
	out("\n");
	out("[fb]   linebytes="); out_dec(fb.fb_linebytes);
	out(" memsize="); out_dec(fb.fb_memsize);
	out(" base="); out_hex(fb.fb_base);
	out(" sizex="); out_dec(fb.fb_sizex);
	out(" sizey="); out_dec(fb.fb_sizey);
	out("\n");

	unsigned int stride = 0;
	u64 rlw = sys3(SYS_ioctl, (u64)(u32)fd, FBIO_GETLINEWIDTH, (u64)&stride);
	out("[fb] ioctl(FBIO_GETLINEWIDTH) ret="); out_hex(rlw);
	out(" errno="); out_dec((u64)g_err);
	out(" stride="); out_dec(stride); out("\n");

	u32 width = fb.fb_width ? fb.fb_width : 1024;
	u32 height = fb.fb_height ? fb.fb_height : 768;
	u32 st = stride ? stride : (fb.fb_linebytes ? fb.fb_linebytes : width * 4);

	u64 len = fb.fb_memsize ? fb.fb_memsize : (u64)st * height;
	if (!len) {
		len = 1024ULL * 768 * 4;
	}
	len = (len + 0xfffULL) & ~0xfffULL;

	u64 anon = sys6(SYS_mmap, 0, 4096, PROT_READ | PROT_WRITE,
	    MAP_ANON | MAP_PRIVATE, (u64)-1, 0);
	out("[fb] anon mmap(4096) -> "); out_hex(anon);
	out(" errno="); out_dec((u64)g_err); out("\n");

	u64 addr = sys6(SYS_mmap, 0, len, PROT_READ | PROT_WRITE,
	    MAP_SHARED, (u64)(u32)fd, 0);
	int mm_err = g_err;
	out("[fb] fb0 mmap(len="); out_dec(len);
	out(", PROT_RW, MAP_SHARED) -> "); out_hex(addr);
	out(" errno="); out_dec((u64)mm_err); out("\n");

	u64 target = 0;
	if (mm_err == 0 && addr >= 0x100000000ULL && (addr & 0xfffULL) == 0) {
		target = addr;
		out("[fb] mmap returned a directly usable 64-bit user address\n");
	} else if (mm_err == 0) {
		out("[fb] mmap succeeded but the returned address is NOT a usable "
		    "64-bit user address (low32="); out_hex((u64)(u32)addr);
		out(") -- the kernel truncated it\n");
#ifdef FB_PROBE_WITH_SCAN
		out("[fb] FB_PROBE_WITH_SCAN: scanning for the real mapping\n");
		target = scan_for_mapping(addr, len);
#else
		out("[fb] refusing to scan (default build is strict)\n");
#endif
	}

	if (!target) {
		out("[fb] RESULT: no usable mapping; cannot paint\n");
		idle();
	}

	out("[fb] mapping at "); out_hex(target);
	out("  painting "); out_dec(width); out("x"); out_dec(height);
	out(" stride="); out_dec(st); out("\n");
	paint(target, width, height, st);
	out("[fb] RESULT: PAINTED 4 colour bars\n");

	volatile u32 *p = (volatile u32 *)target;
	u32 spx = st / 4;
	u64 last = (u64)(height - 1) * spx + (width - 1);
	out("[fb] readback px[0]="); out_hex(p[0]);
	out(" px[mid]="); out_hex(p[(u64)(height / 2) * spx + width / 2]);
	out(" px[last]="); out_hex(p[last]);
	out("\n");

	idle();
}
