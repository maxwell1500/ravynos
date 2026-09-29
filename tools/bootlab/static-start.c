/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Entry point for statically linked ravynOS userspace programs.
 *
 * Why this file exists
 * --------------------
 * The ravynOS SDK ships no crt1.o (`find $SDK -name 'crt*.o'` is empty), and
 * there is no __libc_init to call, so a static program has to supply its own
 * entry point and link with `-e _start`. tools/bootlab/link-static.sh passes
 * exactly that -e _start, and libraries/Libsystem/static/README.md records the
 * convention: "A static ravynOS program supplies its own entry point."
 *
 * Every program in a statically linked ravynOS system needs exactly this, and
 * getting it subtly wrong (wrong stack layout, wrong exit path) produces a
 * binary that links cleanly and then misbehaves, so it lives here once rather
 * than being copied into each program.
 *
 * Link it into any static ravynOS program alongside the program's own sources:
 *
 *     tools/bootlab/link-static.sh -o prog prog.c \
 *         $R/tools/bootlab/static-start.c
 *
 * The stack layout
 * ----------------
 * x86_64 LC_UNIXTHREAD enters with %rsp pointing at argc, laid out as
 *
 *     [argc][argv[0]] ... [argv[argc-1]][NULL][envp[0]] ... [NULL]
 *
 * which is the SysV process-entry layout. main()'s three arguments are loaded
 * by hand from it: rdi=argc, rsi=argv, rdx=argv+argc+1 (the first element
 * after the terminating NULL, i.e. envp).
 *
 * There is no libc startup file to return into, so main()'s return value is
 * passed straight to the exit syscall.
 *
 * The syscall number carries ravynOS's 0x2000000 class bit. That is the
 * convention used by tools/bootlab/init/init_static.c and by the shipped
 * libsyscalls.a: disassembly of ___fork.o shows `movl $0x2000002, %eax` and
 * ___open.o shows `movl $0x2000005, %eax`, i.e. syscall number ORed with
 * 0x2000000.
 *
 * The thread TSD base
 * -------------------
 * A static program gets no __libc_init, so nothing calls pthread_init, and
 * nothing else calls _pthread_set_self() for the thread that is already
 * running. The kernel does not install a user GS base on its own either --
 * pcb->cthread_self starts at 0 and only the thread_fast_set_cthread_self64
 * machdep trap ever sets it -- so the first %gs-relative TSD read the program
 * executes faults. In the shell that is os_unfair_lock_lock()'s owner
 * lookup, _os_tsd_get_direct(__TSD_MACH_THREAD_SELF) at libplatform
 * os/lock.c:300, which is the first %gs read the shell ever reaches:
 *
 *     _start -> _main -> setlocale(LC_ALL, "") -> os_unfair_lock_lock
 *             -> movl %gs:0x18, %eax          <-- EXC_BAD_ACCESS
 *
 * That is not a lock problem. os_unfair_lock is a userspace libplatform
 * primitive over ulock_wait(2); nothing is missing from the kernel, and
 * ravynOS implements sys_ulock_wait. It is a missing process-startup step,
 * and a process startup step belongs here rather than in any library the
 * program happens to call.
 *
 * So _start calls __pthread_static_init() before _main. It is provided by
 * libpthread_static.a (Libraries/Libsystem/libsystem_pthread/pthread.c,
 * VARIANT_STATIC) rather than being written here, for two reasons: libpthread
 * must own the main struct _pthread, because main_thread() in that variant
 * is _main_thread_ptr and has to name the same object whose tsd[] becomes
 * the TSD block; and the call it makes, _thread_set_tsd_base(), is the same
 * one every secondary thread takes, so the main thread's TSD block cannot
 * be set up differently from the others'. Keeping the logic in libpthread
 * and only the ordering here means the two cannot disagree about what
 * "installed" means.
 *
 * This is a fixed, two-instruction cost at process start: one __thread_selfid
 * syscall, one thread_self_trap, and one machdep trap. There is no
 * alternative that is not worse -- the GS base is a ring-0 MSR, so no amount
 * of userspace code can install it without that trap.
 */

// Implemented by libpthread_static.a; see the block comment above.

void __pthread_static_init(void);

/*
 * The allocator's initializer.
 * --------------------------------
 * __malloc_init is libsystem_malloc's one-time setup (malloc.c:266). On a
 * dyld-linked binary Libraries/Libsystem/init.c:229 calls it from
 * __libc_init. A static binary has no __libc_init, so nothing called it:
 * nm on the linked shell showed `___malloc_init' present as a global (T) and
 * called from ZERO sites, i.e. linked in and unreachable.
 *
 * What that costs is __malloc_initialize, which gates on
 * __malloc_entropy_initialized and reports "malloc was initialized without
 * entropy" when the flag is 0. The only writer of the flag is __malloc_init
 * (malloc.c:291 and :298), so on the static path it stayed 0 forever and the
 * first malloc entered the reporting path.
 *
 * The argument is the "apple" boot-arg vector. There is no such vector in a
 * static program, and NULL is the correct value rather than a guess: the
 * linked disassembly tests it before dereferencing, at
 *
 *     00000001000a702d  movq  -0x8(%rbp), %rax
 *     00000001000a703a  cmpq  $0x0, -0x420(%rbp)
 *     00000001000a7048  je    0x1000a705e
 *
 * so a NULL argument skips the scan instead of walking a null pointer. With
 * no apple string to carry `malloc_entropy', __malloc_init takes the
 * getentropy(2) branch at 0x1000a710f, which is what fills malloc_entropy and
 * what mvm_aslr_init() then reads.
 *
 * Declared here, referenced from C, for the same reason __pthread_static_init
 * is: a reference issued only from inline asm does not resolve against a .a.
 */
extern void __malloc_init(const char *apple[]);

// The reference to it is made from C on purpose, not from the __asm__ block
// below. ld64 decides which static-archive members to pull in from an
// object's relocations, and a symbol referenced only from inline asm does
// not resolve against a .a: writing `call __pthread_static_init` directly in
// the asm failed at link time with
//
//     Undefined symbols for architecture x86_64:
//       "__pthread_static_init", referenced from: _start in o0.o
//
// with the symbol present and indexed in libpthread_static.a. The same
// reference issued from C resolves and pulls pthread.o, and the resulting
// call is an ordinary global call rather than one with a name-mangling
// subtlety on the asm side. This is the same reason the asm calls _main
// and not main: asm symbol names are literal Mach-O names, so a C function
// `foo` is `_foo` there.
void ravyn_static_startup(int argc, char **argv, char **envp);

/*
 * The crt externs.
 * ---------------
 * sys/crt_externs.c compiles its non-dynamic branch to bare `extern` globals
 * with USE_VAR(x) == &x, so _NSGetArgv / _NSGetArgc / _NSGetEnviron /
 * _NSGetProgname each hand back the ADDRESS of a global that lives in BSS and
 * is therefore zero.  A dyld-linked binary has those published by
 * libc-startup through program_vars_initvars(ProgramVars).  A static binary
 * has no libc-startup, so nothing ever does, and all of them read NULL.
 *
 * The shell reaches this in setlocale(LC_ALL, "") -> __get_locale_env ->
 * getenv, which dereferences what __NSGetEnviron() returned:
 *
 *     _start -> _main -> _setlocale +0xea -> ___get_locale_env
 *             -> _getenv +0x22 -> movq (%rax), %rdx    <-- EXC_BAD_ACCESS
 *
 * This is the same class of gap as the TSD base: a process-startup step that
 * exists only in the dyld path.  It belongs here because this is the one
 * place in a static program where argc/argv/envp are actually known, and
 * _start already computes envp = &argv[argc + 1] in order to call main.
 *
 * The stores happen before _main, and before that the GS base is installed,
 * so anything reached during startup can already call getenv safely.
 */
/*
 * struct ProgramVars, as sys/crt_externs.c defines it.  It holds POINTERS TO
 * the variables, not their values: NXArgcPtr is an int *, NXArgvPtr and
 * environPtr are char **, and so on.  _program_vars_init copies those
 * pointers into the hidden NXArgc_pointer/NXArgv_pointer/environ_pointer/
 * __progname_pointer/mh_execute_header_pointer statics that _NSGetArgc,
 * _NSGetArgv, _NSGetEnviron, _NSGetProgname and _NSGetMachExecuteHeader
 * return.
 */
struct ravyn_program_vars {
	void	*mh;
	int	*NXArgcPtr;
	char	***NXArgvPtr;
	char	***environPtr;
	char	**__prognamePtr;
};

/*
 * Weak because sys/crt_externs.c only compiles _program_vars_init in its
 * __DYNAMIC__ branch, which is how the shipped Libsystem happens to be built.
 * If that ever changes this must fail to link rather than silently stop
 * publishing, so the NULL check here is a guard, not a supported path.
 */
extern void _program_vars_init(const struct ravyn_program_vars *vars)
	__attribute__((weak));

/*
 * The cached task self port.
 * ---------------------------
 * mach/mach_init.h:76-78 declares
 *
 *     extern mach_port_t mach_task_self_;
 *     #define mach_task_self() mach_task_self_
 *     #define current_task()  mach_task_self()
 *
 * so mach_task_self() is a MACRO that reads a global. It does not call a
 * trap. The global is defined at libsyscall/mach/mach_init.c:66 as
 * MACH_PORT_NULL and has exactly one writer, mach_init.c:135:
 *
 *     mach_task_self_ = task_self_trap();
 *
 * and that is inside the libc-startup path a static binary never runs. So
 * every static program saw mach_task_self() == MACH_PORT_NULL, and that one
 * uninitialised cache is the root of the shell's failure:
 *
 *   mach_port_allocate(0,...)  -> trap -> port_name_to_current_task_noref(0)
 *   fails MACH_PORT_VALID(0)   -> handler returns its MACH_SEND_INVALID_DEST
 *   default                    -> libsyscall/mach/mach_port.c:666 reads that as
 *   "no fast trap available" and falls back to full MIG -> which needs a reply
 *   port -> mig_get_reply_port() -> mach_port_construct(0, ...) -> and round
 *   it goes, unboundedly.
 *
 * The recursion was never the bug; it is the amplifier. The kernel was never
 * at fault: a freestanding probe calling task_self_trap() and
 * mach_port_construct() directly returned a real task port (0x203) and
 * KERN_SUCCESS with a constructed port (0x303), from the same kernel, in the
 * same boot. That probe is tools/bootlab/init/mach_probe.c and it is the
 * control every one of these conclusions rests on.
 *
 * The trap is issued inline rather than by calling task_self_trap() so this
 * file keeps no header dependency on <mach/...> and cannot be broken by an
 * include change; the sequence is byte-identical to the one libsyscall's own
 * generated stub uses.
 */
extern unsigned int mach_task_self_;	/* mach_port_name_t */

static unsigned int
ravyn_task_self_trap(void)
{
	unsigned int r;
	__asm__ volatile(
		"movq	%%rcx, %%r10\n"
		"movl	$0x100001C, %%eax\n"	/* mach trap 28, MACH class */
		"syscall"
		: "=a"(r)
		:
		: "r10", "rcx", "r11", "memory");
	return r;
}

/*
 * The MIG reply port (TSD slot 2, %gs:0x10).
 * ------------------------------------------
 * __TSD_MIG_REPLY is the one TSD slot that is read on EVERY MIG RPC and has
 * no writer anywhere in this tree. mig_get_reply_port() is the function that
 * would lazily create it, but reaching it is itself a MIG call, so a program
 * whose first MIG call happens inside malloc initialisation cannot get there:
 *
 *   _malloc -> __malloc_initialize -> _malloc_report -> _malloc_vreport
 *     -> _simple_asl_log -> _simple_asl_get_context -> __os_alloc_once
 *     -> __os_once on a token already in progress -> recursion
 *
 * Measured, not assumed: a probe reading TSD slots 0..8 before any allocation
 * (tools/bootlab/init/malloc_probe.c) showed slots 0, 1 and 3 holding real
 * values and slot 2 the only meaningful zero, then died on the very first
 * malloc(16) with the same subcode the shell dies with.
 *
 * So the port is created here, directly, before any library can need it. This
 * is safe at _start time because the task already exists and its IPC space is
 * live -- the freestanding control called this exact trap and got KERN_SUCCESS
 * and a constructed port from a freestanding binary with no Libsystem at all.
 *
 * mach_port_construct needs mach_task_self(), so this must come after that is
 * published above. mach_port_options_t is 24 bytes on LP64
 * (uint32 flags @0, mach_port_limits_t mpl @4, uint64 reserved[2] @8).
 */
#define RAVYN_MPO_REPLY_PORT 0x1000

static unsigned int
ravyn_mach_port_construct_reply(unsigned int task)
{
	unsigned long opts[3];		/* 24 bytes, zeroed */
	unsigned int name = 0, r;

	opts[0] = RAVYN_MPO_REPLY_PORT;
	__asm__ volatile(
		"movq	%4, %%rcx\n"		/* arg4, as libsyscall's stub sets it */
		"movq	%4, %%r10\n"
		"movl	$0x1000018, %%eax\n"	/* mach trap 24, MACH class */
		"syscall"
		: "=a"(r)
		: "D"(task), "S"(opts), "d"(0UL), "r"(&name)
		: "rcx", "r10", "r11", "memory");
	return name;
}

/* %gs: needs an absolute displacement; a register operand does not assemble. */
#define RAVYN_TSD_SET(slot_off, val)					\
	__asm__ volatile("movq %0, %%gs:" #slot_off			\
			     : : "r"((unsigned long)(val)) : "memory")

/*
 * Static storage for the published crt externs.
 * -------------------------------------------
 * _program_vars_init stores the POINTERS it is handed, not the values
 * behind them, so every one of them has to be the address of an object
 * that still exists after this function returns.
 *
 * Publishing `&argc`, `&argv`, `&envp` and `&progname` published the
 * addresses of this function's PARAMETERS. That is a pointer into a stack
 * frame that _start has already popped by the time _main runs, and main's
 * own frame lands on top of it. Measured on the target, not argued:
 *
 *     __NSGetEnviron()   = 0x00007ff7bfeffe48   <- a stack address
 *     live &local in main= 0x00007ff7bfeffd98
 *     difference         = 0xb0                   <- already reclaimed
 *     *__NSGetEnviron()  = 0x0000000000000000
 *
 * That is worse than returning NULL, because it is not NULL: it is a
 * pointer that looks usable, so every caller dereferences it. _NSGetEnviron
 * returned a non-NULL pointer whose target had been overwritten with zero,
 * and getenv() and malloc's _set_flags_from_environment both faulted on it.
 *
 * Copying the ARGUMENT VECTORS is not enough on its own either. `envp` is
 * itself an array of pointers living on the same dead stack, so publishing
 * a static `char **` that merely holds the old `envp` address would move
 * the problem one level down, into getenv's walk of the strings. So the
 * strings are copied too, into storage here.
 *
 * The bounds are real bounds, not decoration: the copy stops at the cap and
 * leaves the vector NULL-terminated there, so an argv/envp longer than the
 * cap is truncated rather than walked off the end of the array.
 */
#define RAVYN_MAX_VEC	256		/* entries in argv[] / envp[] */
#define RAVYN_MAX_STR	1024		/* bytes per entry, NUL included */

static int	ravyn_argc_storage;		/* backs NXArgc_pointer */
static char	*ravyn_argv_vec[RAVYN_MAX_VEC + 1];
static char	*ravyn_env_vec[RAVYN_MAX_VEC + 1];
static char	ravyn_argv_store[RAVYN_MAX_VEC][RAVYN_MAX_STR];
static char	ravyn_env_store[RAVYN_MAX_VEC][RAVYN_MAX_STR];

/*
 * The two `char **` VARIABLES, as opposed to the arrays above.
 *
 * NXArgv_pointer/environ_pointer are `char ***` and callers do
 * `*_NSGetArgv()`, so what gets stored must be the address of a `char **`
 * object. An array name decays to `char **` and `&array` is `char ***`, and
 * BOTH compile to the identical `leaq`, so `pv.environPtr = ravyn_env_vec`
 * and `pv.environPtr = &ravyn_env_vec` produce the same machine code and the
 * same wrong answer: the caller gets the first *string* where it expected
 * the *array*, and then dereferences NULL inside malloc. Only a real
 * `char **` variable makes `&var` and `var` different.
 */
static struct ravyn_program_vars ravyn_vars;
static char **ravyn_argv_slot;
static char **ravyn_environ_slot;


/*
 * The Mach/VM page-size globals.
 * --------------------------------
 * The fifth instance of the startup class, and the one that stops malloc.
 *
 * mach_init() is what a normal Mach startup runs. It is a once-only
 * wrapper (test mach_init_inited, call _mach_init_doit, set the flag),
 * and _mach_init_doit is a `static` function inside libsyscall, so
 * mach_init is the only thing an outside object can call. It publishes
 * exactly four globals -- read off the linked image, not off the source:
 *
 *     000000010003ca7d  movq %rax, _vm_kernel_page_size(%rip)
 *     000000010003ca8f  movq %rax, _vm_kernel_page_mask(%rip)
 *     000000010003cae6  movq %rax, _vm_page_size(%rip)
 *     000000010003caf8  movq %rax, _vm_page_mask(%rip)
 *
 * 0x10003cae6 is the ONLY write to _vm_page_size in the whole image --
 * every other reference is a `leaq` taking its address. So on a static
 * binary, where nothing calls mach_init(), _vm_page_size stays at its
 * zero-initialised value.
 *
 * That is fatal to the allocator, and the arithmetic is worth showing
 * because it is not obvious. _malloc_zone_register_while_locked rounds the
 * zone table size up to a page:
 *
 *     rax  = _malloc_num_zones * 8
 *     rax += _vm_page_size
 *     rax += _vm_page_size - 1
 *     rax &= ~(_vm_page_size - 1)
 *
 * With _vm_page_size == 0 that is `0 + 0 + (0-1)` masked by `~(-1)`, i.e.
 * 0. So mach_vm_allocate is asked for ZERO bytes, _malloc_zones is assigned
 * 0, and the function's final
 *
 *     movq %rdx, (%rax,%rcx,8)      <- rax = _malloc_zones = 0
 *
 * is a NULL store at address 0. That is the observed fault exactly: the
 * panic register dump has RAX = 0 and RCX = 0 at RIP ...+0x1d4.
 *
 * This is NOT a missing kernel API. mach_vm_allocate is present and
 * implemented (T _mach_vm_allocate, with __kernelrpc_mach_vm_allocate_trap
 * behind it); the page size was simply never asked for. So the fix is to
 * run the function that asks, not to invent a substitute.
 */
extern void mach_init(void);

/*
 * The Libc atfork handler table.
 * ------------------------------
 * The seventh instance of the startup class, and the first where the
 * unpublished thing is a FUNCTION POINTER rather than a port or a size.
 *
 * _fork() dispatches through three globals:
 *
 *     00000001000247c8  callq *__libSystem_atfork_prepare(%rip)
 *     00000001000247e0  callq *__libSystem_atfork_parent(%rip)
 *     00000001000247f5  callq *__libSystem_atfork_child(%rip)
 *     0000000100024804  callq *__libSystem_atfork_parent(%rip)
 *
 * and all three are BSS with no initialiser. Their publisher is
 * Libraries/Libsystem/init.c:196-201, which builds
 *
 *     static const struct _libc_functions libc_funcs = {
 *             .version = 1,
 *             .atfork_prepare = libSystem_atfork_prepare,
 *             .atfork_parent  = libSystem_atfork_parent,
 *             .atfork_child   = libSystem_atfork_child,
 *     };
 *
 * and hands it to _libc_initializer(&libc_funcs, envp, apple, vars) at
 * init.c:225 -- which runs only from __libc_init. A static binary has no
 * __libc_init, so the table stays NULL and fork() calls through it.
 *
 * NOT __libkernel_init: that was my first guess and it is wrong. init.c:216
 * passes a `struct _libkernel_functions` whose fields are dlsym, malloc,
 * free, realloc, _pthread_exit_if_canceled, pthread_clear_qos_tsd and
 * pthread_current_stack_contains_np. It carries no atfork slot at all, so
 * calling it would not publish these and would be the wrong function.
 */
extern void _pthread_atfork_prepare(void);
extern void _pthread_atfork_parent(void);
extern void _pthread_atfork_child(void);


/*
 * The Libc locale TSD key.
 * ---------------------------
 * The sixth instance of the startup class, and the second where the
 * unpublished value is a KEY rather than a port.
 *
 * Libc reaches the current locale through a pthread key. The fast path is
 *
 *     movq __locale_key(%rip), %rax
 *     movq %gs:(,%rax,8), %rax          <- the key IS the %gs index
 *
 * and the slow path is pthread_getspecific(__locale_key). So the key is
 * used directly as a thread-specific index, and it is created by
 * pthread_key_create() during Libc startup -- which a static binary never
 * runs.
 *
 * Measured, not assumed. Reading the raw bytes of the global out of the
 * linked image:
 *
 *     __locale_key    @ 0x1001466a8  bytes ffffffffffffffff  -> (pthread_key_t)-1
 *     __global_locale @ 0x1001460e0  bytes 0000000000000000  -> NULL
 *
 * and a census of the whole image finds ZERO writes to either:
 *
 *     writes to __locale_key    : 0
 *     writes to __global_locale : 0
 *     _pthread_key_create reachable from _start : NO
 *
 * With the key at (pthread_key_t)-1 the fast path indexes %gs:-8, i.e. it
 * reads memory BELOW the TSD block, and whatever is there becomes the
 * locale pointer. On the shell that read produced 0x99, and _querylocale
 * then dereferenced it at +0x518, faulting at address 0x5B1. The panic
 * register dump shows RAX = 0x99 -- a small integer used as a pointer.
 *
 * The fix is publication, not tolerance: create the key so the slot reads
 * as unset (0), which sends the existing code down its OWN documented
 * fallback to &__global_locale. No locale value is invented here, and
 * setlocale/_querylocale are not modified.
 */
extern unsigned int __locale_key;
extern int pthread_key_create(unsigned int *key, void (*destructor)(void *));

/*
 * The Libc fork handlers.
 * -----------------------
 * The seventh instance of the startup class.
 *
 * Libsystem's fork() wrapper (libsystem_c/sys/fork.c) calls three function
 * pointers: _libSystem_atfork_prepare, _libSystem_atfork_parent, and
 * _libSystem_atfork_child. In a dynamic binary, libSystem_initializer()
 * populates them via _libc_initializer() -> _libc_fork_init().
 * In a static binary, _libc_fork_init() is never called, leaving the three
 * function pointers at NULL in BSS. The very first instruction of fork():
 *
 *     callq *__libSystem_atfork_prepare(%rip)
 *
 * dereferences NULL and jumps to address 0x0. The fork syscall is never
 * reached.
 *
 * The fix is publication: provide real static atfork handlers and register
 * them via _libc_fork_init(). In the child, the Mach task self port and reply
 * port must also be re-acquired for the new task.
 */
struct ravyn_libc_functions {
	unsigned long version;
	void (*atfork_prepare)(void);
	void (*atfork_parent)(void);
	void (*atfork_child)(void);
	char *(*dirhelper)(int, char *, unsigned long);
};

extern void _libc_fork_init(const struct ravyn_libc_functions *funcs)
	__attribute__((weak));

extern void _malloc_fork_prepare(void) __attribute__((weak));
extern void _malloc_fork_parent(void) __attribute__((weak));
extern void _malloc_fork_child(void) __attribute__((weak));

extern void _pthread_atfork_prepare(void) __attribute__((weak));
extern void _pthread_atfork_parent(void) __attribute__((weak));
extern void _pthread_atfork_child(void) __attribute__((weak));
extern void _pthread_atfork_prepare_handlers(void) __attribute__((weak));
extern void _pthread_atfork_parent_handlers(void) __attribute__((weak));
extern void _pthread_atfork_child_handlers(void) __attribute__((weak));

extern int _mach_fork_child(void) __attribute__((weak));

static void
ravyn_atfork_prepare(void)
{
	if (_pthread_atfork_prepare_handlers) _pthread_atfork_prepare_handlers();
	if (_malloc_fork_prepare) _malloc_fork_prepare();
	if (_pthread_atfork_prepare) _pthread_atfork_prepare();
}

static void
ravyn_atfork_parent(void)
{
	if (_pthread_atfork_parent) _pthread_atfork_parent();
	if (_malloc_fork_parent) _malloc_fork_parent();
	if (_pthread_atfork_parent_handlers) _pthread_atfork_parent_handlers();
}

static void
ravyn_atfork_child(void)
{
	/* Re-acquire Mach task port and reply port for the new task */
	mach_task_self_ = ravyn_task_self_trap();
	RAVYN_TSD_SET(0x10, ravyn_mach_port_construct_reply(mach_task_self_));
	if (_mach_fork_child) _mach_fork_child();
	if (_pthread_atfork_child) _pthread_atfork_child();
	if (_malloc_fork_child) _malloc_fork_child();
	if (_pthread_atfork_child_handlers) _pthread_atfork_child_handlers();
}

static const struct ravyn_libc_functions ravyn_libc_fork_funcs = {
	.version = 1,
	.atfork_prepare = ravyn_atfork_prepare,
	.atfork_parent = ravyn_atfork_parent,
	.atfork_child = ravyn_atfork_child,
	.dirhelper = 0,
};



/*
 * Copy a NULL-terminated char *vector and its strings into static storage.
 * Returns the count copied, excluding the terminator. Truncates at the cap.
 */
static int
ravyn_copy_vector(char *const *src, char **vec, char store[][RAVYN_MAX_STR])
{
	int n = 0;

	vec[0] = 0;				/* empty vector is still valid */
	if (src == 0)
		return 0;
	for (; src[n] != 0 && n < RAVYN_MAX_VEC; n++) {
		const char *s = src[n];
		int i = 0;

		while (s[i] != 0 && i < RAVYN_MAX_STR - 1) {
			store[n][i] = s[i];
			i++;
		}
		store[n][i] = '\0';		/* terminates even if truncated */
		vec[n] = store[n];
	}
	vec[n] = 0;				/* NULL-terminate at the cap too */
	return n;
}

void
ravyn_static_startup(int argc, char **argv, char **envp)
{
	__pthread_static_init();		/* GS base: see the block comment above */

	/* Copy both vectors and their strings into storage that outlives this
	 * frame BEFORE taking the addresses below. Publishing &argv or &envp
	 * would publish this function's own parameters; see the block comment
	 * on ravyn_copy_vector for what that cost. */
	ravyn_argc_storage = argc;
	ravyn_copy_vector(argv, ravyn_argv_vec, ravyn_argv_store);
	ravyn_copy_vector(envp, ravyn_env_vec, ravyn_env_store);
	/* What the published `char **` VARIABLES hold. &var, not var: that is
	 * the whole difference between handing a caller the array and handing
	 * it argv[0]. See the block comment on ravyn_argv_slot. */
	ravyn_argv_slot = ravyn_argv_vec;
	ravyn_environ_slot = ravyn_env_vec;

	ravyn_vars.mh = 0;				/* no MH_EXECUTE header exists
						 * to publish for a static image */
	ravyn_vars.NXArgcPtr = &ravyn_argc_storage;	/* int *: address of the int */
	ravyn_vars.NXArgvPtr = &ravyn_argv_slot;	/* char ***: &the char ** var */
	ravyn_vars.environPtr = &ravyn_environ_slot;	/* char ***: &the char ** var */
	/* argv[0] of the COPY, not of the incoming vector, and the slot
	 * holding it is itself static. Same defect, same fix. */
	ravyn_vars.__prognamePtr = &ravyn_argv_vec[0];	/* char **: &the char * */
	/* After the GS base, so the trap runs with a usable %gs. */
	mach_task_self_ = ravyn_task_self_trap();
	/* Must follow mach_task_self_: mach_port_construct needs the task port.
	 * Must precede _program_vars_init and above all main(), because the
	 * first MIG call in a static program otherwise happens from inside
	 * malloc initialisation, where it recurses. */
	RAVYN_TSD_SET(0x10, ravyn_mach_port_construct_reply(mach_task_self_));
	/* The Mach/VM page-size globals. Must follow the reply-port
	 * publication above, because _mach_init_doit calls mach_reply_port(),
	 * which is a MIG call; and it must precede __malloc_init below,
	 * because the allocator's first zone registration rounds its table up
	 * to _vm_page_size, and with that still zero it asks the kernel for a
	 * zero-byte mapping and stores through a NULL table pointer.
	 *
	 * Upstream mach_init.c says of this call: "mach_init() must be called
	 * explicitly in static executables (including dyld)" -- it is a
	 * PRE-libpthread initializer, which is exactly the situation here.
	 *
	 * The one thing that had to change for a STATIC link is upstream's
	 * trailing _pthread_set_self(0), which is only safe while
	 * _pthread_set_self is still Libc's no-op stub. See the block comment
	 * on the declaration and Libraries/Libsystem/libsystem_kernel/static/,
	 * where the scoped variant lives. The dynamic build is untouched. */
	mach_init();

/*
 * Libsystem's static-link initializer. Not in any public header -- it is
 * declared in the .c that defines it and exported for exactly this caller.
 * See the block comment at the call site for why the dynamic __libc_init
 * is the wrong entry point here.
 */
extern void __ravyn_static_libc_init(const struct ProgramVars *vars,
    void (*atfork_prepare)(void), void (*atfork_parent)(void),
    void (*atfork_child)(void), const char *apple[]);

	/*
	 * Libc's own initializer, at last reachable.
	 *
	 * This calls __ravyn_static_libc_init, NOT the dynamic __libc_init.
	 * The two take the same five arguments; they differ in exactly one
	 * entry of the initializer list. __libc_initializer() runs
	 *
	 *     _program_vars_init(vars)   <- Fix 2 publishes the crt externs
	 *     _libc_fork_init(funcs)     <- publishes the atfork table
	 *     __confstr_init, __atexit_init, _init_clock_port, __chk_init
	 *     __xlocale_init()           <- Fix 4's locale key
	 *     __guard_setup(apple)
	 *
	 * and _init_clock_port() is the one entry that cannot run on ravynOS:
	 * it calls host_get_clock_service(), which osfmk/kern/clock_oldops.c
	 * implements and osfmk/mach/mach_host.defs declares but never gives a
	 * mach trap, so the trap the stub issues returns failure and the
	 * function's own abort() fires. Measured, not assumed:
	 *
	 *   ___pthread_kill <- _abort <- __init_clock_port <- __libc_initializer
	 *   <- ___libc_init <- _ravyn_static_startup
	 *   pid 1 exited -- exit reason namespace 2 subcode 0x6
	 *
	 * No value can be published to make that check pass: it is a SERVICE
	 * the kernel must hand out, not a startup value. The gap is filed
	 * against the Kernel/xnu workstream. Meanwhile clock_port stays
	 * MACH_PORT_NULL, so nanosleep()/sleep() are unavailable -- which is
	 * the state the system was already in; omitting the call stops
	 * aborting about it rather than breaking a working sleep.
	 *
	 * __ravyn_static_libc_init is Libsystem's own file for this
	 * (Libraries/Libsystem/libsystem_c/sys/_libc_init_static.c), compiled
	 * into libc_static.a, and it is the whole of __libc_initializer() with
	 * that one line deleted. Every other entry above still runs, in the
	 * same order. The dynamic path is untouched: dyld still calls the real
	 * __libc_init, and a dynamic binary on a kernel that does wire the
	 * trap needs the call.
	 *
	 * apple is NULL and that is safe by the code, not by convenience:
	 * __guard_setup does `for (p = apple; p && *p; p++)`, which
	 * short-circuits on NULL, and a static binary has no apple= vector.
	 */
	__libc_init(&ravyn_vars, _pthread_atfork_prepare,
	    _pthread_atfork_parent, _pthread_atfork_child, 0);

	/* The atfork table, before anything can fork. See the block comment on
	 * the declaration: fork() calls through these three pointers, they are
	 * BSS, and their only publisher is __libc_init, which a static binary
	 * never runs. Publishing them from Libsystem's own handlers is the
	 * seventh instance of the startup class, same shape as the six above. */

	/* The Libc locale TSD key, created the way Libc startup would. Must
	 * follow __pthread_static_init, which installs the %gs base that
	 * pthread_key_create needs, and it must precede main() because the
	 * shell's very first setlocale reads the key. See the block comment on
	 * the declaration: with the key left at its (pthread_key_t)-1
	 * sentinel the code indexes %gs:-8 and dereferences garbage.
	 *
	 * The library route to this key was considered and rejected on COST.
	 * __xlocale_init (libBase.a:locale/xlocale.o) is the real initializer
	 * and would genuinely replace this call, but xlocale.o arrives with 25
	 * undefined symbols (nm -u): ___collate_load_tables,
	 * ___messages_load_locale, ___monetary_load_locale,
	 * ___numeric_load_locale, ___time_load_locale, ___detect_path_locale,
	 * ___get_locale_env, ___error, __setrunelocale, __DefaultRuneXLocale,
	 * _pthread_key_init_np and the standard C set. That is the entire
	 * locale-database loader. ravynOS has no locale data for it to load,
	 * so linking the code that loads locale tables in order to obtain one
	 * thread key is a poor trade. */
	pthread_key_create(&__locale_key, 0);

	/* Initialize Libc fork handlers so fork() does not jump through NULL. */
	if (_libc_fork_init != 0)
		_libc_fork_init(&ravyn_libc_fork_funcs);

	/* Publish the crt externs BEFORE the allocator, not after. It used to
	 * be last, and that was survivable only because nothing reachable
	 * from __malloc_init consulted them. That is not a safe assumption
	 * to leave standing: __malloc_initialize calls getenv (through
	 * _set_flags_from_environment) and __malloc_init can reach
	 * __malloc_initialize, via __malloc_init_from_bootargs' malloc_report
	 * on a malformed bootarg. Publishing first costs five pointer stores
	 * and removes the ordering hazard entirely. */
	if (_program_vars_init != 0)
		_program_vars_init(&ravyn_vars);

	/* The allocator. Last of the startup steps, and for the same reason the
	 * two above are ordered this way: __malloc_init is the first thing in
	 * this process that can fail into malloc_report, so everything that
	 * report might need -- a %gs base for errno, a task port, a reply
	 * port, a valid environ -- has to already be published. NULL is the
	 * "apple" vector; see the block comment on the declaration for the
	 * disassembly that shows NULL is tested before it is walked. */
	__malloc_init(0);
}

__asm__(
	".text\n"
	".globl _start\n"
	".p2align 4\n"
"_start:\n"
	"	xorl	%ebp, %ebp\n"		/* deepest frame: no caller to unwind to */
	"	movq	(%rsp), %rdi\n"		/* argc */
	"	leaq	8(%rsp), %rsi\n"		/* argv */
	"	leaq	8(%rsp,%rdi,8), %rdx\n"	/* envp = &argv[argc + 1] */
	/* Park argc/argv in callee-saved registers BEFORE the call below.
	 * %rdi and %rsi are caller-saved and the callee is entitled to
	 * clobber both -- and this one does, because ravyn_static_startup
	 * now calls mach_init, pthread_key_create, __program_vars_init and
	 * __malloc_init. Setting them once here and then calling _main
	 * without reloading handed main() whatever the startup happened to
	 * leave behind. It reached the shell as argc == 0, and ash's
	 * procargs() reads argptr[0] BEFORE its argc guard: options.c:85 is
	 * `argptr = argv;`, :86 is
	 * `login = argptr[0] != NULL && argptr[0][0] == '-';` and the guard
	 * `if (argc > 0)` is :87 -- one line too late, because :86 has already
	 * dereferenced argv[0]. With argc == 0 that deref took the value
	 * 0x6d5f636f6c6c616d -- the ASCII "m_collam" -- and used it as a char *.
	 * %rbx and %r12 are callee-saved, so the values survive the call. */
	"	movq	%rdi, %rbx\n"		/* argc -> callee-saved */
	"	movq	%rsi, %r12\n"		/* argv -> callee-saved */
	"	andq	$-16, %rsp\n"		/* SysV wants rsp % 16 == 8 at entry */
	"	call	_ravyn_static_startup\n"	/* GS base + crt externs, before _main */
	"	movq	%rbx, %rdi\n"		/* reload: startup clobbers rdi/rsi */
	"	movq	%r12, %rsi\n"
	"	call	_main\n"
	"	movl	%eax, %edi\n"
	"	movl	$0x2000001, %eax\n"		/* SYS_exit | class bit */
	"	syscall\n"
	"	hlt\n");
