/*
 * ravynOS Mach IPC probe: is the failure in task-port resolution, or in the
 * MIG reply-port path?
 *
 * DELIBERATELY FREESTANDING
 * ------------------------
 * This links with -nostdlib -nostdlibinc and defines no libc at all: no
 * Libsystem, no libpthread, no libsyscall, no dyld, and NOT the
 * tools/bootlab/static-start.c that the shell and every staged utility use.
 * That is the whole point. The static-start changes are what the TSD base and
 * the crt externs needed, and if this probe pulled them in it would be
 * testing the thing under suspicion. Nothing here depends on a startup fix.
 *
 * It calls the two Mach traps by hand through the raw syscall instruction, so
 * the observations are of the kernel, not of Libsystem's wrappers.
 *
 * In particular mach_port_construct() is called DIRECTLY, never through
 * mig_get_reply_port().  That is the experiment: the recursion under
 * investigation only exists because Libsystem's wrapper falls back to full MIG
 * on a MACH_SEND_INVALID_DEST return, and full MIG needs a reply port, which
 * calls this same function.  Calling it directly removes that path entirely,
 * so a hang cannot be this recursion and a return value is a real kernel
 * answer.
 *
 * Output is raw write(2) to /dev/console -- no printf, because libc is
 * precisely what is in question.
 *
 * A marker is printed BEFORE and AFTER every call, so a hang is
 * distinguishable from a failure: if the "after" marker is missing and the
 * serial log stops, the kernel trapped or looped; if it is present, the call
 * returned and the value is real.
 */
typedef unsigned long u64;
typedef long i64;

/* Freestanding: clang emits these for zero-init and struct copies. */
void *memset(void *d, int c, u64 n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
void *memcpy(void *d, const void *s, u64 n) { unsigned char *p = d; const unsigned char *q = s; while (n--) *p++ = *q++; return d; }
u64 strlen(const char *s) { u64 n = 0; while (s[n]) n++; return n; }

/* BSD/Unix syscalls: number | 0x2000000 (the Unix class bit, as used by
 * tools/bootlab/init/init_static.c and libsyscalls.a). */
#define SC_UNIX 0x2000000UL
static u64 sys3(u64 n, u64 a, u64 b, u64 c) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | SC_UNIX), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
	return r;
}
static u64 sys1(u64 n, u64 a) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | SC_UNIX), "D"(a) : "rcx", "r11", "memory");
	return r;
}
static u64 sys2(u64 n, u64 a, u64 b) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | SC_UNIX), "D"(a), "S"(b) : "rcx", "r11", "memory");
	return r;
}

#define SYS_exit   1
#define SYS_write  4
#define SYS_open   5
#define SYS_close  6
#define SYS_dup2   90
#define O_RDWR     2
#define O_NOCTTY   0x20000

/* Mach traps: class 0x1000000, numbers from mach_trap_table. */
#define SC_MACH 0x1000000UL
#define TRAP_TASK_SELF            28	/* mach_trap_table[28] task_self_trap */
#define TRAP_MACH_PORT_CONSTRUCT  24	/* mach_trap_table[24] ..._trap */

/*
 * CONFIRMATION VARIANT. The first run of this probe passed arg4 in BOTH rcx
 * and r10 and mach_port_construct returned KERN_SUCCESS. That may have been
 * luck: Libsystem's generated stub passes arg4 in r10 ONLY, because `syscall`
 * clobbers rcx, while this kernel's mach_call_munger64 copies argument slots
 * from rdi/rsi/rdx/rcx/r8/r9 -- i.e. it reads arg4 from rcx. For a 4-argument
 * trap the two conventions disagree.
 *
 * So this version drops the `movq %4, %%rcx` and matches Libsystem exactly,
 * and adds a THREE-argument control: mach_port_allocate (trap 16), whose
 * handler is structurally identical to mach_port_construct's --
 * port_name_to_current_task_noref first, MACH_SEND_INVALID_DEST as the
 * default, mach_copyout of the result -- but which never reads arg4.
 *
 *   3-arg succeeds + 4-arg fails  -> the boundary is exactly at arg4.
 *   both fail                    -> arg4 is not the explanation.
 *   both succeed                 -> arg4 is not the explanation either.
 */
static u64 mach_port_construct_raw(u64 task, u64 opts, u64 context, u64 name) {
	u64 r;
	__asm__ volatile(
		"movq	%4, %%r10\n"		/* r10 ONLY, exactly as libsyscall does */
		"movl	$0x1000018, %%eax\n"
		"syscall"
		: "=a"(r)
		: "D"(task), "S"(opts), "d"(context), "r"(name)
		: "rcx", "r10", "r11", "memory");
	return r;
}

/* mach_port_allocate(task, name, right) -- 3 args, trap 16, never reads arg4. */
static u64 mach_port_allocate_raw(u64 task, u64 name, u64 right) {
	u64 r;
	__asm__ volatile(
		"movl	$0x1000010, %%eax\n"
		"syscall"
		: "=a"(r)
		: "D"(task), "S"(name), "d"(right)
		: "rcx", "r10", "r11", "memory");
	return r;
}

static u64 task_self_trap_raw(void) {
	u64 r;
	__asm__ volatile(
		"movq	%%rcx, %%r10\n"
		"movl	$0x100001C, %%eax\n"
		"syscall"
		: "=a"(r)
		:
		: "r10", "rcx", "r11", "memory");
	return r;
}

static int g_fd = 1;

static void emit(const char *s) { sys3(SYS_write, (u64)g_fd, (u64)s, strlen(s)); }

static void emit_hex(const char *label, u64 v) {
	/* static, not on the stack: a local array makes the compiler emit
	 * __stack_chk_fail references, and this image has no runtime for them. */
	static const char hx[] = "0123456789abcdef";
	static char out[24];
	int n = 0, i;
	emit(label);
	emit("=0x");
	for (i = 60; i >= 0; i -= 4)
		out[n++] = hx[(v >> i) & 0xf];
	out[n] = 0;
	emit(out);
	emit("\n");
}

void start(void) {
	/* mach_port_options_t, 24 bytes on LP64:
	 *   uint32 flags @0, mach_port_limits_t mpl @4, union{uint64[2]} @8 */
	static unsigned char opts[24];
	u64 task, kr, name = 0;

	i64 cfd = (i64)sys2(SYS_open, (u64)"/dev/console", O_RDWR | O_NOCTTY);
	if (cfd >= 0) {
		g_fd = (int)cfd;
		sys2(SYS_dup2, (u64)cfd, 1);
		sys2(SYS_dup2, (u64)cfd, 2);
	}
	emit("\n=== RAVYNOS MACH IPC PROBE (freestanding, no Libsystem) ===\n");

	/* ---- step 1: task_self_trap -------------------------------------- */
	emit("[1] before task_self_trap\n");
	task = task_self_trap_raw();
	emit("[1] after  task_self_trap\n");
	emit_hex("[1] task_self_trap() = ", task);
	emit_hex("[1] MACH_PORT_NULL(0) compare: ", (task == 0) ? 1 : 0);
	/* A kernel task port name is small and odd; a return address or garbage
	 * is huge. Print it so the reader can judge plausibility, not just
	 * pass/fail. */
	emit_hex("[1] plausible (<0x10000)? ", (task != 0 && task < 0x10000) ? 1 : 0);

	/* ---- step 2: THREE-argument control, arg4 never read -------------- */
	emit("[2] before mach_port_allocate (3-arg trap 16, RIGHT_SEND=1)\n");
	/*
	 * KNOWN BUG IN THIS CONTROL, left in deliberately so the control stays
	 * byte-for-byte what produced the original result -- but do NOT copy
	 * it.  MACH_PORT_RIGHT_SEND is 0 in this tree
	 * (osfmk/mach/port.h:284); 1 is MACH_PORT_RIGHT_RECEIVE
	 * (port.h:285).  Passing 1 to mach_port_allocate is why this step
	 * returns kr=0x12 (KERN_INVALID_VALUE) and port name 0.  The step
	 * therefore proved nothing about 3-arg traps and must not be read as
	 * evidence either way.  The Libsystem bisection probe passes 0.
	 */
	kr = mach_port_allocate_raw(task, (u64)&name, 1);
	emit("[2] after  mach_port_allocate\n");
	emit_hex("[2] mach_port_allocate() kr = ", kr);
	emit_hex("[2] allocated port name = ", name);

	/* ---- step 3: FOUR-argument trap, arg4 in r10 ONLY ---------------- */
	memset(opts, 0, sizeof(opts));
	opts[0] = 0x00; opts[1] = 0x10;	/* flags = MPO_REPLY_PORT 0x1000, LE */
	emit("[3] before mach_port_construct (4-arg trap 24, arg4 in r10 ONLY)\n");
	kr = mach_port_construct_raw(task, (u64)opts, 0, (u64)&name);
	emit("[3] after  mach_port_construct\n");
	emit_hex("[3] mach_port_construct() kr = ", kr);
	emit_hex("[3] MACH_SEND_INVALID_DEST(0x10000003) compare: ",
	         (kr == 0x10000003UL) ? 1 : 0);
	emit_hex("[3] KERN_SUCCESS(0) compare: ", (kr == 0) ? 1 : 0);
	emit_hex("[3] constructed port name = ", name);

	emit("[4] probe complete, no recursion occurred\n");
	sys1(SYS_exit, 0);

	/* If anything above traps, execution never reaches here and the last
	 * marker printed is the diagnostic. */
	for (;;)
		;
}
