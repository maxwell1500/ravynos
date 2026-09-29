/*
 * Libsystem-linked Mach IPC bisection probe.
 *
 * WHAT THIS IS FOR
 * ----------------
 * The freestanding probe (init/mach_probe.c, kept unmodified as the control)
 * proved that ravynOS's Mach IPC primitives work: task_self_trap() returns
 * 0x203 and mach_port_construct() returns KERN_SUCCESS constructing port
 * 0x303, twice, under two different arg4 register conventions. The shell,
 * which goes through Libsystem and then mig_get_reply_port(), recurses.
 *
 * Nobody has established WHICH Libsystem call first diverges. That is what
 * this measures. It calls things in escalating order and the first one that
 * diverges from the control's result is the answer, localising the defect to
 * a single call rather than to "the MIG path" as a region.
 *
 *   [1] mach_task_self()            via Libsystem  -- vs control 0x203
 *   [2] mach_port_allocate(..., 0)  via Libsystem  -- 3-arg path, RIGHT_SEND
 *   [3] mach_port_construct(...)    via Libsystem  -- vs control KERN_SUCCESS
 *   [4] mig_get_reply_port()        the first call that pulls in the MIG
 *                                     reply-port bootstrap
 *
 * NOT FREESTANDING, AND THAT IS THE POINT
 * ----------------------------------------
 * This links Libsystem, so unlike the control it DEPENDS ON the static-start
 * fixes: the TSD base (libpthread) and the crt externs. Without those, Libsystem
 * faults in setlocale before it can be measured at all. That dependence is
 * inherent to bisecting Libsystem and is exactly what makes the control
 * necessary: the control measures the kernel with none of this present.
 *
 * Every stage prints a "before" and an "after" marker around its call, so a
 * hang is distinguishable from a failure: if a stage's "after" is missing,
 * that call is where execution stopped. (It does not exit(0) between
 * stages, because exiting would end the bisection; the before/after markers
 * give the same distinguishability without that cost.)
 *
 * Output is raw write(2) to /dev/console, so nothing depends on stdio
 * flushing at the moment of a fault.
 */
#include <mach/mach.h>
#include <mach/port.h>
#include <mach/mig.h>

typedef unsigned long u64;
typedef long i64;

/* No memset/memcpy/strlen here, unlike the freestanding control: this links
 * Libsystem, which provides them.  Redefining them collides with clang's
 * __builtin___memcpy_chk -- which is what the first build of this file hit. */

static u64 sys3(u64 n, u64 a, u64 b, u64 c) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000UL), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
	return r;
}
static u64 sys1(u64 n, u64 a) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000UL), "D"(a) : "rcx", "r11", "memory");
	return r;
}
static u64 sys2(u64 n, u64 a, u64 b) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000UL), "D"(a), "S"(b) : "rcx", "r11", "memory");
	return r;
}

#define SYS_exit  1
#define SYS_write 4
#define SYS_open  5
#define SYS_dup2  90
#define O_RDWR    2
#define O_NOCTTY  0x20000

static int g_fd = 1;
static void emit(const char *s) { sys3(SYS_write, (u64)g_fd, (u64)s, strlen(s)); }

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

/* The raw trap, byte-for-byte the same sequence the freestanding control
 * uses: movq %rcx,%r10 ; movl $0x100001c,%eax ; syscall. */
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

void main(void) {
	mach_port_options_t opts;
	mach_port_name_t name = 0;
	mach_port_t task, reply;
	u64 raw_task;
	kern_return_t kr;

	i64 cfd = (i64)sys2(SYS_open, (u64)"/dev/console", O_RDWR | O_NOCTTY);
	if (cfd >= 0) {
		g_fd = (int)cfd;
		sys2(SYS_dup2, (u64)cfd, 1);
		sys2(SYS_dup2, (u64)cfd, 2);
	}
	emit("\n=== RAVYNOS LIBSYSTEM MACH BISECTION ===\n");
	emit("(control, freestanding: task=0x203 construct=KERN_SUCCESS port=0x303)\n");

	/*
	 * STAGE 0 vs STAGE 1, back to back in the SAME process.
	 *
	 * The freestanding control returned 0x203 from this exact trap and the
	 * Libsystem wrapper returned 0, but those were two different processes.
	 * This is the comparison those two runs could not make: identical
	 * instant, identical register state, one instruction apart. It is the
	 * discriminator between "the wrapper transforms it" and "the state
	 * this process is in changed the answer".
	 */
	emit("[0] before task_self_trap (raw inline asm)\n");
	raw_task = task_self_trap_raw();
	emit("[0] after  task_self_trap (raw inline asm)\n");
	emit_hex("[0] raw task_self_trap = ", (u64)raw_task);
	emit_hex("[0] matches control 0x203? ", (raw_task == 0x203) ? 1 : 0);

	/* ---- [1] mach_task_self via Libsystem, immediately after ---------- */
	emit("[1] before mach_task_self()\n");
	task = mach_task_self();
	emit("[1] after  mach_task_self()\n");
	emit_hex("[1] mach_task_self() = ", (u64)task);
	emit_hex("[1] matches control 0x203? ", (task == 0x203) ? 1 : 0);
	emit_hex("[1] raw vs Libsystem agree? ", (raw_task == (u64)task) ? 1 : 0);

	/* ---- [2] mach_port_allocate, 3-arg --------------------------------
	 * MACH_PORT_RIGHT_SEND is 0 in this tree (osfmk/mach/port.h:284).
	 * The freestanding control passed 1 by mistake, which is
	 * MACH_PORT_RIGHT_RECEIVE and is why that step returned
	 * KERN_INVALID_VALUE.  This one passes the correct 0. */
	emit("[2] before mach_port_allocate(task, &name, RIGHT_SEND=0)\n");
	kr = mach_port_allocate(task, MACH_PORT_RIGHT_SEND, &name);
	emit("[2] after  mach_port_allocate\n");
	emit_hex("[2] mach_port_allocate() kr = ", (u64)kr);
	emit_hex("[2] KERN_SUCCESS(0)? ", (kr == KERN_SUCCESS) ? 1 : 0);
	emit_hex("[2] allocated port name = ", (u64)name);

	/* ---- [3] mach_port_construct via Libsystem ------------------------ */
	memset(&opts, 0, sizeof(opts));
	opts.flags = MPO_REPLY_PORT;
	emit("[3] before mach_port_construct (MPO_REPLY_PORT)\n");
	kr = mach_port_construct(task, &opts, 0, &name);
	emit("[3] after  mach_port_construct\n");
	emit_hex("[3] mach_port_construct() kr = ", (u64)kr);
	emit_hex("[3] KERN_SUCCESS(0)? ", (kr == KERN_SUCCESS) ? 1 : 0);
	emit_hex("[3] MACH_SEND_INVALID_DEST(0x10000003)? ", (kr == 0x10000003UL) ? 1 : 0);
	emit_hex("[3] constructed port name = ", (u64)name);

	/* ---- [4] mig_get_reply_port: the first MIG bootstrap call --------- */
	emit("[4] before mig_get_reply_port()  <-- if [4] 'after' is missing, this is the hang\n");
	reply = mig_get_reply_port();
	emit("[4] after  mig_get_reply_port()\n");
	emit_hex("[4] mig_get_reply_port() = ", (u64)reply);
	emit_hex("[4] MACH_PORT_NULL(0)? ", (reply == 0) ? 1 : 0);

	emit("[5] bisection complete, all four stages returned\n");
	sys1(SYS_exit, 0);
	for (;;)
		;
}
