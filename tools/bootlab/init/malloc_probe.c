/*
 * Minimal reproducer for the first-malloc failure, with the TSD picture taken
 * FIRST so it survives even if allocation dies.
 *
 * THE TSD DUMP
 * ------------
 * __TSD_MIG_REPLY is direct slot 2 (%gs:0x10) and the census established it is
 * never assigned anywhere in this tree, making it the outstanding member of the
 * startup class. Reading it is one instruction and makes NO MIG call, so unlike
 * calling mig_get_reply_port() it cannot recurse -- which is why it is safe
 * here where the MIG path would hang.
 *
 * Slot map (libsystem_pthread/private/tsd_private.h and os/tsd.h):
 *   0 thread_self   1 errno   2 MIG_REPLY   3 MACH_THREAD_SELF
 *   4 QOS_CLASS     5 RETURN_TO_KERNEL   6 reserved   7 PTR_MUNGE
 *   8 MACH_SPECIAL_REPLY
 * Each slot is one pointer, 8 bytes, so slot N lives at %gs:(N*8).
 *
 * READING THIS
 * ------------
 * The three outcomes the TSD dump distinguishes for the malloc failure:
 *   slot 2 != 0 and malloc(16) != NULL  -> allocator works; the shell's
 *       failure is specific to setlocale -> currentlocale -> malloc.
 *   slot 2 == 0 and malloc(16) == NULL  -> __malloc_initialize needs a MIG
 *       reply port: the sixth instance of the startup class.
 *   slot 2 == 0 and malloc(16) != NULL  -> the reply port is a real gap but not
 *       this one.
 *
 * CONSTRAINTS OF THIS LIBSYSTEM, worth knowing so they are not re-derived:
 * sbrk is absent from the static archives entirely, and the SDK's vm_map.h
 * declares the vm_allocate family but not mach_vm_allocate, so the heap cannot
 * be probed either way. malloc itself is the only instrument available.
 */
#include <stdlib.h>

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
static u64 sys1(u64 n, u64 a) {
	u64 r; __asm__ volatile("syscall" : "=a"(r) : "a"(n | 0x2000000UL), "D"(a) : "rcx", "r11", "memory");
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

/* Direct TSD read. %gs: requires an ABSOLUTE displacement -- a register
 * operand gives "expected relocatable expression" -- so the offset is a
 * literal baked in by the macro rather than a loop variable. */
#define TSD(off) ({ unsigned long _v; \
	__asm__ volatile("movq %%gs:" #off ", %0" : "=r"(_v) :: "memory"); _v; })

/*
 * MEASUREMENT ADDED 2026-09-29, after Fix 1 moved the first-malloc crash.
 *
 * The crash moved to _set_flags_from_environment, which does exactly what
 * getenv does: call __NSGetEnviron() and dereference its result. The
 * hypothesis is a LIFETIME bug in ravyn_static_startup, not a missing
 * writer: it publishes pv.environPtr = &envp, and `envp` is a function
 * PARAMETER -- a stack local whose frame is gone by the time main runs.
 * _program_vars_init copies that address into the environ_pointer global,
 * so __NSGetEnviron() hands out a pointer into a dead frame.
 *
 * That is a claim, so it is measured here rather than argued:
 *   [E1] __NSGetEnviron() itself   -- if this is a stack address, it is
 *        a dead frame, not a real environ vector
 *   [E2] *__NSGetEnviron()        -- what the deref would actually load
 *   [E3] a stack address from THIS frame, to show the same stack region
 *        is already in use by something else
 *   [E4] %rsp here                -- the live stack pointer at measurement
 * If [E1] lands in the same region as [E3] and [E2] is 0 while [E4] has
 * moved far away from it, the frame is dead and reused: confirmed.
 */
extern char **_NSGetEnviron(void);
extern char **_NSGetArgv(void);
extern int   *_NSGetArgc(void);
extern char **_NSGetProgname(void);

/* Where does this address live?
 *
 * 1 = static/data  (in the image; outlives any frame)
 * 2 = stack        (a frame that may already be gone)
 * 0 = NULL
 *
 * The point of naming these is that "non-NULL" and "usable" are different
 * questions, and the crash being chased here was caused by a pointer that
 * answered "non-NULL" while living in a frame that had been reclaimed.
 */
#define ADDR_STACK_LO	0x00007f0000000000UL
#define ADDR_STACK_HI	0x00007fffffffffffUL

static u64 classify(u64 p) {
	if (p == 0)
		return 0;
	if (p >= ADDR_STACK_LO && p <= ADDR_STACK_HI)
		return 2;
	return 1;
}

static u64 here_on_stack(void) {
	u64 v;
	__asm__ volatile("movq %%rsp, %0" : "=r"(v));
	return v;
}

void main(int argc, char **argv) {
	void *p, *b;

	i64 cfd = (i64)sys2(5, (u64)"/dev/console", 2UL | 0x20000UL);
	if (cfd >= 0) {
		g_fd = (int)cfd;
		sys2(90, (u64)cfd, 1);
		sys2(90, (u64)cfd, 2);
	}
	emit("\n=== RAVYNOS MINIMAL MALLOC PROBE (TSD first) ===\n");

	/* --- [A] the arguments main() actually received -------------------
	 * Discriminator for the argc==0 fault: does the startup hand main a
	 * sane argc/argv, or not? argv[0] is classified, not merely tested for
	 * NULL, because "non-NULL" was the check that passed while the value
	 * was unusable. */
	emit("[A] arguments main() received:\n");
	emit_hex("[A]   argc             = ", (u64)(unsigned long)argc);
	emit_hex("[A]   argv             = ", (u64)(unsigned long)argv);
	emit_hex("[A]   argv == 0 ?      = ", (argv == 0) ? 1 : 0);
	if (argv != 0) {
		emit_hex("[A]   argv[0]          = ", (u64)(unsigned long)argv[0]);
		emit_hex("[A]   classify(argv[0]) = ", classify((u64)(unsigned long)argv[0]));
		if (argv[0] != 0)
			emit_hex("[A]   argv[0][0]       = ",
			    (u64)(unsigned char)argv[0][0]);
	}

	/* --- [0] TSD slots 0..8, BEFORE any allocation ------------------- */
	emit("[0] TSD slots, read before malloc:\n");
	emit_hex("[0]   slot 0 (thread_self)   = ", TSD(0x00));
	emit_hex("[0]   slot 1 (errno)        = ", TSD(0x08));
	emit_hex("[0]   slot 2 (MIG_REPLY)    = ", TSD(0x10));
	emit_hex("[0]   slot 3 (MACH_THREAD)  = ", TSD(0x18));
	emit_hex("[0]   slot 4 (QOS_CLASS)    = ", TSD(0x20));
	emit_hex("[0]   slot 5 (RETURN_KERN)  = ", TSD(0x28));
	emit_hex("[0]   slot 6 (reserved)     = ", TSD(0x30));
	emit_hex("[0]   slot 7 (PTR_MUNGE)    = ", TSD(0x38));
	emit_hex("[0]   slot 8 (MACH_SPECIAL) = ", TSD(0x40));
	emit("[0] slot 2 is __TSD_MIG_REPLY (%gs:0x10)\n");

	/* --- [E] each published crt extern, checked individually ----------
	 *
	 * The rule being tested: a published pointer must point at storage
	 * that is still there when something else derefs it. "Non-NULL" is
	 * NOT the test -- that is the check that passed for the whole time
	 * the pointer was dangling in a reclaimed stack frame. So each one
	 * is dereferenced, the value is printed, and the value is classified:
	 * stack-range means the frame is gone, static/data range means the
	 * storage outlived startup, NULL means there is nothing to walk.
	 *
	 * [E9] is the POSITIVE CONTROL: a pointer whose liveness this code
	 * can vouch for (a local of main, and a file-scope static) is put
	 * through the identical classifier. If the classifier cannot report
	 * those two as live, it is not a check and its verdicts below are
	 * not evidence.
	 */
	emit("[E] crt externs, dereferenced and classified:\n");
	{
		static char probe_static_live = 0x5e;
		char probe_local_live = 0x5e;
		char **ep = _NSGetEnviron();
		char **ap = _NSGetArgv();
		int   *ac = _NSGetArgc();
		char **pn = _NSGetProgname();
		u64 live_local = (u64)&probe_local_live;
		u64 live_static = (u64)&probe_static_live;

		emit_hex("[E]   rsp (live frame)          = ", here_on_stack());
		emit_hex("[E]   &main local  (control)   = ", live_local);
		emit_hex("[E]   &static var  (control)   = ", live_static);
		emit_hex("[E]   classify(&main local)    = ", classify(live_local));
		emit_hex("[E]   classify(&static var)    = ", classify(live_static));

		emit_hex("[E]   __NSGetArgc()            = ", (u64)ac);
		emit_hex("[E]     *__NSGetArgc()          = ",
		    (ac != 0) ? (u64)(*ac) : 0xffffffffffffffffUL);
		emit_hex("[E]   __NSGetArgv()            = ", (u64)ap);
		emit_hex("[E]     argv[0]                = ",
		    (ap != 0 && ap[0] != 0) ? (u64)ap[0] : 0);
		emit_hex("[E]     classify(argv[0])      = ",
		    (ap != 0 && ap[0] != 0) ? classify((u64)ap[0]) : 0);
		emit_hex("[E]   __NSGetEnviron()         = ", (u64)ep);
		emit_hex("[E]     env[0]                 = ",
		    (ep != 0 && ep[0] != 0) ? (u64)ep[0] : 0);
		emit_hex("[E]     classify(env[0])       = ",
		    (ep != 0 && ep[0] != 0) ? classify((u64)ep[0]) : 0);
		emit_hex("[E]   __NSGetProgname()        = ", (u64)pn);
		emit_hex("[E]     *progname              = ",
		    (pn != 0 && pn[0] != 0) ? (u64)pn[0] : 0);
		emit_hex("[E]     classify(progname)     = ",
		    (pn != 0 && pn[0] != 0) ? classify((u64)pn[0]) : 0);
		emit_hex("[E]   _progname[0] first char = ",
		    (pn != 0 && pn[0] != 0) ? (u64)(*pn[0] & 0xff) : 0);
	}

	/* --- [P] the Mach/VM page-size globals, measured ---------------
	 * The zone table in malloc is rounded up to _vm_page_size. If that is
	 * 0 the rounding yields 0, mach_vm_allocate is asked for zero bytes,
	 * and the allocator stores through a NULL table pointer. Print the
	 * value the allocator will actually use, rather than inferring it. */
	extern unsigned long vm_page_size;
	emit("[P] Mach/VM page-size globals, before malloc:\n");
	emit_hex("[P]   _vm_page_size   = ", vm_page_size);
	emit_hex("[P]   non-zero?       = ", (vm_page_size != 0) ? 1 : 0);

	/* --- [1] the first allocation; this killed the shell -------------- */
	emit("[1] before malloc(16)\n");
	p = malloc(16);
	emit("[1] after  malloc(16)\n");
	emit_hex("[1] malloc(16) = ", (u64)p);
	emit_hex("[1] NULL? ", (p == 0) ? 1 : 0);
	if (p != 0) {
		*(volatile unsigned int *)p = 0x5a5a5a5a;
		emit_hex("[1] wrote and read back = ", *(volatile unsigned int *)p);
	}

	/* --- [2] does size matter ---------------------------------------- */
	emit("[2] before malloc(65536)\n");
	b = malloc(65536);
	emit("[2] after  malloc(65536)\n");
	emit_hex("[2] malloc(65536) = ", (u64)b);
	emit_hex("[2] NULL? ", (b == 0) ? 1 : 0);

	emit("[3] probe complete\n");
	sys1(1, 0);
	for (;;)
		;
}
