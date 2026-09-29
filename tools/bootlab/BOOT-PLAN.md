# ravynOS userspace bring-up — findings and state

Written 2026-09-29. This is the record of how a static ravynOS userland program
goes from "does not start" through "cannot yet allocate" to "allocates, and is
then handed a bad `argc`", and what is proven versus open. Every claim below is
backed by a preserved log; nothing here is inferred from plausibility. The
shell does **not** boot to an interactive shell and nothing in this document
should be read as saying it does.

---

## 1. The control that makes everything else trustworthy

**`tools/bootlab/init/mach_probe.c`** — a freestanding, static, `LC_UNIXTHREAD`
probe with **zero** Libsystem, libpthread or libsyscall symbols. It calls Mach
traps by raw `syscall` and writes results with raw `write(2)`.

It is the control because it measures the **kernel** with none of the
userspace startup machinery present. Its binary is preserved unmodified
(`/tmp/mach_probe_CONTROL.bin`, verified by `cmp`).

```
[1] task_self_trap() = 0x203                 a real task port
[2] mach_port_construct() kr = 0x0           KERN_SUCCESS
[2] constructed port name = 0x303            a real reply port
[3] probe complete, no recursion occurred
```

**ravynOS's Mach IPC works.** Task-port resolution, `ipc_port_translate_send`,
`mach_copyin`/`mach_copyout` and port construction all behave. This was
re-measured twice, under two different arg4 register conventions, with
identical results — which is what exonerated `mach_call_munger64`.

This control is why every conclusion below is a measurement rather than a story.

---

## 2. The startup class

State that a normal startup path installs and a static ravynOS binary does
not. Six instances, all now closed and proven.

| # | State | Where it was going unread | Fix |
|---|---|---|---|
| 1 | Thread TSD base (`GS.base`) | first `%gs:` read faulted in `os_unfair_lock_lock` | `__pthread_static_init()` |
| 2 | crt externs (`environ`, `__argc`, `__argv`, `__progname`) | `*_NSGetEnviron()` returned a **non-NULL pointer into a reclaimed stack frame**; `_getenv` and malloc's `_set_flags_from_environment` both faulted dereferencing it | argv/envp **and their strings** copied into file-scope statics, then published through `char **` variables |
| 3 | `mach_task_self_` | `mach_port_construct(0, …)` → trap returns `MACH_SEND_INVALID_DEST` → MIG fallback → recursion | `task_self_trap()` stored to the global |
| 4 | `__TSD_MIG_REPLY` (slot 2, `%gs:0x10`) | read on every MIG RPC, no writer anywhere in the tree | `mach_port_construct(MPO_REPLY_PORT)` stored to slot 2 |
| 5 | `_vm_page_size` / `_vm_page_mask` (+ the two `vm_kernel_page_*`) | `0` — the page rounding in `_malloc_zone_register_while_locked` collapsed to 0, so `mach_vm_allocate` was asked for a zero-byte mapping and the zone table pointer stayed NULL → NULL store at `+0x1d4` | `mach_init()`, which is what Libc startup runs, via the scoped static variant below |
| 6 | `__locale_key` (Libc's locale TSD key) | `(pthread_key_t)-1` — never created, so the fast path indexed `%gs:-8`, read 0x99, and used it as a `struct loc *` → fault in `_querylocale` at `0x518(%rax)` | `pthread_key_create(&__locale_key, 0)`, which makes the slot read as unset and sends the existing code down its own `&__global_locale` fallback |

All six are published from one function, `ravyn_static_startup()` in
**`tools/bootlab/static-start.c`**. It is the right home: it is the one place
in a static program where the pre-dyld state is actually known. `libpthread`
keeps the TSD struct because it owns `_pthread`; the ordering lives here so the
two cannot disagree about what "installed" means.

### Why #3 was so hard, and what it cost

`mach_task_self()` is a **macro**, not a call (`mach/mach_init.h:76-78`):

```c
extern mach_port_t mach_task_self_;
#define mach_task_self() mach_task_self_
```

Its only writer is `mach_init.c:135`, inside a libc-startup path a static
binary never runs. I disassembled `_mach_task_self`, found a two-instruction
passthrough to `_task_self_trap`, and concluded the wrapper was harmless —
**that was reading a function nobody calls**, because the macro expands to a
global read at every call site. The error was caught only by a probe that
called the raw trap and the Libsystem wrapper **in the same process, one
instruction apart**, which is a comparison two separate runs cannot make.

### A refuted hypothesis, recorded so it is not retried

`__TSD_MIG_REPLY` being zero is a real gap, and it is now published and
verified (`0x303`). But publishing it **did not fix the malloc failure** —
that was measured, with the counterfactual run, and the answer was no. It is a
correct fix on its own merits, not the cause of that bug.

Also refuted, with a control: the theory that `mach_call_munger64` reads arg4
from `rcx` while libsyscall's stubs supply it in `r10`, which would corrupt
every mach trap with ≥4 arguments. Run 1 (arg4 in `rcx` and `r10`) and run 2
(arg4 in `r10` only) both returned `KERN_SUCCESS` and port `0x303`. Dead.

---

## 3. The initializer census: what the static link does not contain

`Libraries/Libsystem/init.c`'s `__libc_init` calls **fourteen** initializers,
and the `enum init_func` immediately above it — `INIT_SYSTEM` …
`INIT_DARWIN`, fourteen entries — is the same list under a second name:

```
__libkernel_init         __libplatform_init    __pthread_init
__libc_initializer       __malloc_init         __keymgr_initializer
_dyld_initializer        libdispatch_init      _libxpc_initializer
_libtrace_init           _libsecinit_initializer   _container_init
__libdarwin_init         __libcxx_init
```

**Twelve of the fourteen are absent from the linked static shell.** Not
unreachable: *not linked in at all*. The static link never asks the archive
that holds them for anything, so ld64 never pulls the member and the symbol
never reaches the image. `nm` on the staged `tools/bootlab/staged/bin/sh`:

```
00000001000b8f90 T ___pthread_init      <- linked, and never called
00000001000a6fc0 T ___malloc_init       <- linked, and called by US
(nothing)          __libc_initializer    <- T in libBase.a AND in libc.a
(nothing)          __libkernel_init      <- not in any archive on the line
(nothing)          __libplatform_init    <- T in libsystem_platform.a
(nothing)          __keymgr_initializer
(nothing)          _dyld_initializer
... seven more absent
```

`__libc_init` is the sharpest instance. It is a `T` in `libBase.a` and in
`libc.a`, both of which are already on `link-static.sh`'s `LIBS` line, and it
is still not in the binary — nothing references it, so no member is pulled.
The entire libc startup contract is sitting in an archive the linker is
already holding.

That reframes section 2. Each of the six crashes was the static path reaching
for a value that a component the static link does not include was supposed to
have published. There was never a seventh missing write hiding in shell code.

### Four states, not two

"Missing" collapses three different bugs under one word, and they have
different fixes:

| state | exemplar |
|---|---|
| present and reachable | `_mach_init_doit`, `__init_cpu_capabilities` — in the image, on our path, called |
| **present, linked, but NOT reachable** | `___pthread_init` — the linker pulls whole archive **members**, not symbols, so `pthread.o` arrived for `__pthread_static_init` and brought `___pthread_init` along uncalled. `otool -tvV` over the whole image finds **zero** references to its address |
| present but unreachable (zero writers) | `__locale_key` before fix 6 — in the image, correctly typed, and a whole-image census finds **zero** writes to it |
| absent from the link entirely | `__libc_initializer`, `__libplatform_init` (a `T` in `libsystem_platform.a`, which *is* on the `LIBS` line, but no member references it), `__keymgr_initializer`, `__libkernel_init` — not in the image at all |

Row 1 and row 2 differ by one `call` instruction that nobody emits. Row 2 and
row 3 differ by whether the linker was ever asked. A symbol table cannot tell
them apart, and neither can a grep for assignments — which is exactly the
limitation section 9 records against `find_dyld_only_state.py`. Note that
`___xlocale_init` is presently in row 2 as well: linked, for the same
member-granularity reason, and never called.

### What must **not** be linked

The census is equally an argument for what to keep out, and it is written
down here so that nobody helpfully adds it back:

- **`_dyld_initializer`** — there is no dyld in a static binary. Nothing to
  initialize, and `libdyld.a` is not on the link line.
- **`_libxpc_initializer`, `_libsecinit_initializer`, `_container_init`,
  `__libcxx_init`, `_libtrace_init`** — none of them is on the shell's path.
  Each is a component with its own licensing and provenance questions, and
  the cost of acquiring one is never the symbol you wanted; it is the tree
  that arrives with it. That is the same reasoning, applied to
  `libBase.a`'s `xlocale.o`, that is recorded at the
  `pthread_key_create(&__locale_key, 0)` call in `static-start.c`.

---

## 4. Positive controls: what a negative result is worth

Every incorrect result in this investigation was caught before it reached a
report, and in every single case it was **the positive control that caught
it** — not care, not experience, not reading carefully.

> **A negative result is only worth what its control is worth, and a control
> that has never been shown to fire should be treated as ABSENT rather than
> as reassurance.**

| wrong turn | what a firing control would have said |
|---|---|
| `grep -c enosys bsd/kern/syscalls.master` = 42, read as a count of runtime `enosys` slots | 29 of those lines are inside `#if` arms this configuration does not compile; only 13 are real slots, and syscall **500 is not among them — 501 is.** The original diagnosis read the neighbouring line. |
| a search for `sys_getentropy` returned nothing, and the absence was read as "not implemented" | the function is spelled **`getentropy`**; the search returned nothing *because the name was wrong* |
| `grep Libraries/` for `mach_init.c` concluded the source did not exist | the file was at `Kernel/xnu/libsyscall/mach/mach_init.c`; the search was scoped and the conclusion was global |
| `__pthread_init` reported "ABSENT from linked shell" | Mach-O spells it `___pthread_init` (three underscores); the archive member was linked the whole time, brought in for `__pthread_static_init` |
| three `nm` archive sweeps concluded `_procargs` was not in any archive | the sweeps **failed to find `_malloc` in `libc.a` on three separate attempts** — the pattern itself was invalid, so a "not found" would have been an artifact of the instrument. `_procargs` is in fact `BSD/bin/sh/options.c:80`, in the shell's own sources |

The first two cost roughly a day of planning each, around a kernel change
that turned out to be unnecessary. The rule that falls out of the table is
the only part worth carrying forward:

> **When a negative result is load-bearing, prove the instrument finds a
> known positive in the same invocation before believing it.**

### The same failure in a test rather than a search

`init/malloc_probe.c`'s `main` ignored its arguments, so the `argc == 0` that
`ravyn_static_startup` was handing the shell went unseen across **six**
crashes. The probe was standing in for the shell, and it could not report the
one thing that differed. A test that ignores the thing under test is a
control with a blind spot, and it is worse than no test at all, because it
still produces output.

---

## 5. The amplification bug: `mach_port.c:666`

`libsyscall/mach/mach_port.c:666` treats **any** `MACH_SEND_INVALID_DEST`
(0x10000003) from the fast trap as "this kernel has no such trap", and falls
back to full MIG — which needs a reply port, which calls the same function.
One bad task port therefore became unbounded recursion.

The sentinel is not a verdict. In `osfmk/ipc/mach_kernelrpc.c:339` it is the
**pre-initialised failure default** of the handler.

The recursion was never the bug; it is the amplifier. The trap is correctly
wired — `syscall_sw.c:105` has
`MACH_TRAP(_kernelrpc_mach_port_construct_trap, 4, 5, munge_wwlw)` at the right
index, and `MACH_TRAP(name, arg_count=4, …)` with arg_count matching the
4-field args struct, and `MACH_TRAP_MUNGE` expands to nothing on x86_64.

---

## 6. OPEN: the first `malloc` fails, and the amplifier that hides it

### The original claim — since disproved, kept for the record

> Everything from here to the RETRACTION below is the 2026-09-29 *original*
> diagnosis. It named syscall 500 as the cause. That was wrong. Read the
> retraction, not this.

`__malloc_initialize` fails on this condition, read from the binary:

```
00000001000863dd   testb   $0x1, __malloc_entropy_initialized(%rip)
00000001000863e4   jne     0x1000863f9
00000001000863eb   leaq    0x2aaac(%rip), %rsi   ; "*** malloc was initialized without entropy"
00000001000863f4   callq   _malloc_report
```

`__malloc_entropy_initialized` is in BSS (`nm`: `b` at `0x1000d3d18`) and never
set. The chain, from the binary:

```
_getentropy:        movl $0x20001f4, %eax   ->  syscall 500, Unix class
__entropy_from_kernel -> __malloc_common_value_for_key_copy
```


**`getentropy` is syscall 500. This diagnosis was WRONG and is retracted
below.** The error was a name-level search: the kernel function is spelled
`getentropy`, not `sys_getentropy`, and `grep sys_getentropy` over
`Kernel/xnu` returns nothing while returning "no such function" is the wrong
conclusion. The 42 is real — it is `grep -c enosys bsd/kern/syscalls.master`
— but 500 is not among them; 501 is, and the two sit on adjacent lines.

### RETRACTION: syscall 500 is implemented, wired, and working (2026-09-29)

Measured three ways, all from bytes rather than from source reading.

**1. The dispatch table, read out of the linked kernel.**
`bsd/dev/i386/systemcalls.c:unix_syscall64` computes its entry as
`add rdx, [rip+0x88dc82]` over `nsysent`; that load is GOT-indirect, and the
GOT slot holds `0xffffff80010ec220` = `&sysent`. Reading 24 bytes per entry
(`struct sysent` is 24 bytes on LP64: two pointers, an int32, an int16, a
uint16) at `sysent + 500*24`:

```
sysent[500] = { sy_call = 0xffffff8000469140,   <- _getentropy
                sy_arg_munge32 = 0xffffff8000469f60,
                sy_return_type = 1, sy_narg = 2, sy_arg_bytes = 8 }
```

`0xffffff8000469140` is `_getentropy` in the symbol table. The only
`sysent` entries pointing at `_enosys` (`0xffffff80007c2800`) are
**13**, not 42: `{8, 11, 17, 19, 21, 22, 275, 276, 391, 392, 393, 495, 519}`.
The other 29 master lines sit in `#if` arms this configuration does not
compile. 500 is not in the set. `git diff` of the master against the build
tree's `bsd/bsd.syscalls.master` is empty, and
`bsd/DEVELOPMENT/init_sysent.c:3126` reads
`{ ...getentropy, munge_ww, _SYSCALL_RET_INT_T, AC(getentropy_args), 8}, /* 500 = getentropy */`.

**2. The implementation, disassembled.** `Kernel/xnu/bsd/dev/random/randomdev.c:242`
is the real thing — `size > 256` returns `EINVAL`, then `blkclr` 256,
`read_random`, `copyout`, and the return value is `copyout`'s. Not a stub.

**3. At runtime, with a positive control and a discriminating control.**
`init/entropy_probe.c` as PID 1, `work/entropy.img`,
`work/serial_ENTROPY-03.log`:

```
[A] getpid(20) = 0x1                    CONTROL OK: unix syscalls reach userland
[B] getentropy(buf,16): rax=0  cf=0     SUCCESS
[B]   16 bytes:  bc c1 4f 04 61 dd 2f 46  cd 39 c8 6f 24 8e 63 01
[C] getentropy(buf,512): rax=0x16 cf=1  EINVAL(22) -- the size cap is enforced
[D]   call #1:  5a ae be fd 66 ac 25 84  24 bb 9c f7 ce 39 22 8e
[D]   call #2:  c4 10 13 43 8f 35 44 eb  e9 d9 2b c9 0c 27 ec 10
[D]   two calls identical? =0   any nonzero byte? =1
```

`[C]` is the control that matters: a stub or an `enosys` slot cannot return
`EINVAL(22)` for an over-long request. `[D]` rules out a constant fill.
`[A]` is the positive control, without which "syscall 500 returned 0" and
"syscalls do not work" would be indistinguishable.

### What the entropy check is actually gated on

Not on syscall 500. In the linked Libsystem, `__malloc_init` is:

```
0000000100081b16   testb   $0x1, __malloc_entropy_initialized(%rip)
0000000100081b1d   jne     0x100081b37
0000000100081b26   movl    $0x10, %esi
0000000100081b2b   callq   _getentropy
0000000100081b30   movb    $0x1, __malloc_entropy_initialized(%rip)   ; unconditional
```

so the flag is set whatever `getentropy` returns — and it is only ever set
there. `__malloc_init` has exactly one caller in the tree,
`Libraries/Libsystem/init.c:229` inside `__libc_init`. A static binary
(`-e _start`, `tools/bootlab/static-start.c`) never runs `__libc_init`, and
`ravyn_static_startup()` does not call `__malloc_init`. **The flag is 0
because nothing in the static startup path calls `__malloc_init` — a
Libraries/startup gap, not a kernel gap.** Confirmed from the crash: the
return address on the `_malloc_report` frame is `0x1000868e9`, which is the
instruction immediately after that `callq _malloc_report`, i.e. the
entropy-false branch was taken.

Note the caveat this project has already recorded: *a syscall in the master is
not proof the running kernel dispatches it.* That caveat was right and it was
applied the wrong way round — it was used to conclude the syscall was absent
without reading the table.

### The amplifier — independent, confirmed from two runs, deliberately unfixed

```
_malloc -> _malloc_zone_malloc -> _default_zone_malloc
        -> __os_once -> __os_once_callout -> __malloc_initialize   (fails)
        -> _malloc_report -> _malloc_vreport -> _simple_asl_log
        -> _simple_asl_get_context -> __os_alloc_once
        -> __os_once on a token ALREADY IN PROGRESS -> recursion
```

`__os_once` re-entering an in-progress token must return, not recurse. This is
a real, independent defect that survives whatever happens to the entropy bug.

**It is deliberately not fixed yet.** Fixing it in front of the unresolved
`__malloc_initialize` failure would turn a loud stack overflow into a silent
`malloc` returning NULL, and every process that then dereferences it would die
somewhere less informative. Cause first, then the amplifier — same reasoning
that correctly deferred the `mach_port.c` fallback change.

Update 2026-09-29: the "unresolved `__malloc_initialize` failure" is now
resolved, and it is not a kernel failure. `__malloc_init` is never called on
the static startup path, so the flag is 0 and the report is entered. With
syscall 500 proven working, the honest next step is to call
`__malloc_init(apple)` from `ravyn_static_startup()` — a `Libraries/` +
`static-start.c` change, outside the boundary that was set for the syscall
work. Note also that in the run above the crash landed in
`__platform_strlen` (RIP `0x10008b897`, `movsx eax, byte ptr [rax]` with
`rax = 0x10ec270cc92bd9e9`), i.e. inside `malloc_report`'s own formatting
via `__simple_vesprintf` — a third defect, distinct from the `__os_once`
recursion recorded above, and also in `Libraries/`.


---

## 7. Where the shell stands

**The allocator is no longer the frontier.** After the six startup-class
fixes, measured on a real boot:

```
malloc(16)                        = 0x00000001002040a0
*p = 0x5a5a5a5a; read back *p     = 0x000000005a5a5a5a   (survives)
_vm_page_size                     = 0x1000               (read at runtime)
```

and there has been **no allocator frame in the shell's backtrace since fix 1**
(`__malloc_init(apple)`). Earlier in this record, with fixes 1–4,
`work/init_shell` opened `/dev/console` on fd 0/1/2, `setsid` and `TIOCSCTTY`
both succeeded, `execve /bin/sh` succeeded and the shell reached `_main`,
with exit subcode moved `0xb` → `0x4`. The crash that remained then was
inside the allocator, above; that is what the last two fixes retired.

**No prompt yet.** The shell does not reach an interactive shell, and nothing
in this document should be read as saying that it does. The demonstration
commands are still scripted in `/tmp/sterm.py` (`PS1`, a typed command,
`echo hi | cat`, redirection) and still wait for the first boot where the
shell survives past `main`.

### OPEN: `main` is handed `argc == 0`

The crt externs (`__argc`, `__argv`, `environ`, `__progname`) are published
correctly — that was fix 2 and it is not in question. What is wrong is the
`argc`/`argv` pair handed to the shell's `main` **as arguments**, and that is
a different value on a different path: `_start` reads them off the stack,
passes them to `ravyn_static_startup()`, and then has to pass them *again* to
`_main`.

Observed, from the panic register dump at the fault inside ash's
`procargs()`:

```
RDI = 0x0000000000000000     <- argc, ZERO
RSI = 0x000000010011c570     <- argv, a valid image address
RAX = 0x6d5f636f6c6c616d     <- argv[0], decoding as ASCII "m_collam"
```

`argv` is a valid pointer; the **count** is zero. `argv[0]` is therefore not
an argument at all but whatever bytes sit at that address, and the
`argptr[0] != NULL` guard passes precisely because those bytes are non-zero
— so `argptr[0][0]` goes on to dereference a **plausible-looking** string
value as a pointer.

This is a fourth fault classification in this investigation, and the first
where the bad value is *plausible* rather than wild. Every other fault in
this record was caught by a value that was obviously not a pointer: 0,
`(pthread_key_t)-1`, `0x99`, a truncated kernel address. `0x6d5f636f6c6c616d`
is ASCII, it is non-NULL, and it has exactly the shape of a pointer to a
string. A plausibility filter — the instinct that correctly dismisses the
first three — is useless here, which is also why the guard that was supposed
to protect the read is on the wrong side of it.

The mechanism, `BSD/bin/sh/options.c:80-81`:

```c
        argptr = argv;
        login = argptr[0] != NULL && argptr[0][0] == '-';   /* reads argv[0] */
        if (argc > 0)                                        /* too late */
                argptr++;
```

The `argc > 0` guard protects only the **increment**, not the **read** one
line above it.

**Patching `options.c` to move the read inside the guard was explicitly
rejected.** It would make the crash disappear while leaving the shell
operating on a fiction: `scriptname` and the option loop would then read
from garbage, and the failure would surface later as a shell that starts and
misparses its own arguments. A crash is honest about the boundary; a fiction
hides it.

The value is lost in `_start`, not in the shell. `ravyn_static_startup` now
calls `mach_init`, `pthread_key_create`, `_program_vars_init` and
`__malloc_init`, every one of which may clobber the caller-saved `%rdi` and
`%rsi` that hold the arguments. The `_start` stub in `static-start.c` now
parks them in `%rbx`/`%r12` and reloads them before `callq _main`. That
change is in the source and is **not yet measured** — the binary these dumps
come from still goes straight from `callq _ravyn_static_startup` to
`callq _main` with no reload, and the fault above is open until a boot shows
otherwise.

---

## 8. Constraints of this Libsystem, so they are not re-derived

- **`sbrk` is absent from the static archives entirely.** The heap cannot be
  probed that way.
- **The SDK's `vm_map.h` declares the `vm_allocate` family but not
  `mach_vm_allocate`.** The heap cannot be probed that way either. Together
  these mean `malloc` itself is the only available instrument.
- **`%gs:` requires an absolute displacement.** A register operand gives
  `expected relocatable expression`; TSD slot reads must bake in literals.
- **The SDK is not a reliable index to the kernel.** It misled twice:
  `mach_vm_allocate` "undeclared", and a struct field (`mpo_flags` vs `flags`).
  Read the kernel sources, or the linked binary.

---

## 9. Tools left behind

| File | Purpose |
|---|---|
| `init/mach_probe.c` | freestanding kernel control — **keep unmodified** |
| `init/mach_bisect.c` | Libsystem bisection; found the `mach_task_self` macro |
| `init/malloc_probe.c` | TSD slots 0–8 then `malloc(16)`; reproduced in 3 lines |
| `init/init_shell.c` | PID 1: console, setsid, TIOCSCTTY, exec `/bin/sh` |
| `static-start.c` | publishes all six startup-class gaps |
| `make_shell_manifest.py` | generates the all-ours manifest; hard-errors on an Apple userland binary or a **stale** one |
| `find_dyld_only_state.py` | sound for the `*_pointer` BSS class; **not** sound for reachability — see below |

### The census and its honest limitation

Sound for hidden `*_pointer` BSS symbols written only under `#if __DYNAMIC__`
— 5 such symbols, all crt externs, all fixed.

**Not** sound for the question that actually matters: *is this write reachable
from a static startup path?* It answers "is this identifier assigned
somewhere", which reports `ok` on `__TSD_MIG_REPLY` and would have reported
`ok` on `mach_task_self_` too. Both are known-false positives. A real
reachability analysis has not been done, and the tool is left in that state
rather than tuned until it looks better — a detector that reports "ok" on a
known-false case is worse than no detector.

---

## 10. Logs

All under `/tmp/serial-diag-evidence/`:

| Log | What it shows |
|---|---|
| `probe_RUN.log` | control: kernel IPC works (arg4 in `rcx` and `r10`) |
| `probe2_RUN.log` | control again, arg4 in `r10` only — hypothesis refused |
| `bisect_RUN.log` | Libsystem wrapper returns 0 where the trap returns `0x203` |
| `disc_RUN.log` | both in one process: raw `0x203`, Libsystem `0x0` |
| `MP2.log` | TSD slots before malloc: slot 2 the only meaningful zero |
| `MP3.log` | slot 2 published to `0x303`; malloc still fails — refused |
| `DEMO.log` | shell reaches `_main`; crash is in malloc, not MIG |

Images: `work/boot_*.img`. The static-init probe entry point is selectable
with `make_shell_manifest.py --init-file=work/<probe>`.

---

## 11. Next step

**Superseded 2026-09-29.** `getentropy` (syscall 500) needed no
implementation: it is `bsd/dev/random/randomdev.c:242`, it is in `sysent[500]`
in the linked kernel, and it returns real entropy at runtime. See the
retraction in section 6.

None of the next steps is in `Kernel/xnu`:

1. ~~Call `__malloc_init(apple)` from `ravyn_static_startup()` in
   `tools/bootlab/static-start.c`~~ — **done 2026-09-29.** See section 7: the
   allocator returns a real address and has had no frame in a backtrace since.
2. Fix the `malloc_report` formatting path, where `__simple_vesprintf` hands
   `__platform_strlen` a kernel address. Still a real defect, no longer on
   the startup path: with `__malloc_init` called, the report is not entered.
3. The `argc == 0` fault in section 7, at `options.c:80`.
4. Then fix `__os_once` re-entrancy.
5. Then run `/tmp/sterm.py` for the terminal demonstration.

### 2026-09-29 update: static initializer regression and prompt blocker

The older `serial_SHELL-FIX5.log` records the static shell reaching `# ` at
line 638. Its manifest selected `work/sh.fix5` (SHA-256
`4a3adea4ca563167731c91b5a638ebe4dd1b5de24da2da818dfa622ae019347a`) and
the launchd stub `work/init_shell`. The image itself was overwritten, so this
is log evidence, not a recoverable disk image; the archived shell binary and
the matching input image recipe remain in `work/` and `manifest_shell_fix5.json`.

The subsequent `serial_D2.log` did **not** run that shell. Its manifest was
`manifest_fix6.json`, whose `/bin/sh` is `work/sh.fix6` (SHA-256
`6e0d01d1f16d46ce91eae7557da9d00bfcdf9d1fb0c62552e83d037bf53bf8be`).
Symbolicating its exit registers against that exact binary gives:

```
__pthread_kill -> abort -> _init_clock_port -> _libc_initializer
-> __libc_init -> ravyn_static_startup
```

The regression was the static startup's call to dynamic `__libc_init`, which
invokes the unavailable `host_get_clock_service` and aborts. The source already
had `__ravyn_static_libc_init` in `Libraries/Libsystem/libsystem_c/sys/_libc_init_static.c`
to omit only `_init_clock_port`; `tools/bootlab/static-start.c` now calls that
static-safe initializer instead. Rebuilt `/tmp/ravyn-sh-build/sh` has zero
undefined symbols, zero `LC_LOAD_DYLIB`, and contains `___ravyn_static_libc_init`
but not `___libc_init`.

That fix removed the abort but did **not** restore the prompt, so the next
blocker had to be measured rather than assumed. Holding the guest at the
post-`execve` point and sampling `info registers` through the QEMU gdbstub gave
a single user-space RIP in 9 of 9 samples: `0x1000203c0`.

It is a **self-referential jump**, not a hang in shell code:

```
___vsnprintf_chk:                ; work/sh.static-safe, +0x10
    cmpq %rsi, %rcx
    jb   ___chk_fail_overflow
    jmp  .                        ; <- RIP pinned here, spinning forever
```

The function's *normal* path is an infinite loop, so any `vsnprintf` call never
returns. The shell hit one during startup and burned a core on `jmp .`; that is
why the prompt never appeared and why `wait4` was never reached.

The cause is a **build artifact, not a source defect**. `secure/vsnprintf_chk.c`
and its 15 siblings are always correct; recompiling `vsnprintf_chk.c` with the
current flags (`-D_FORTIFY_SOURCE=0`, with and without `-fno-builtin`) produces
a normal prologue and a real call in every case. The bad members came from a
10:11 incremental build made during the earlier `-I${.CURDIR:H}` include-path
experiment, and they had an unresolved `callq` relocation:

```
broken  libc_static.a/vsnprintf_chk.o   : jmp .        (self-loop)
correct libFortifySource.a/vsnprintf_chk.o: normal prologue
```

Identical source, two archives, opposite results -- that comparison is what
makes this the cause rather than a coincidence. Rebuilding all 16 fortify
members with the `libFortifySource/Makefile:23` flag set, re-archiving
`libc_static.a`, re-merging `libc.a` and relinking the shell removed it: a
whole-image scan for `jmp`-to-own-address traps in the linked shell now reports
**0**, where the previous binary had them. No source change was needed or made;
`libc_static/Makefile` is byte-identical to its committed state.

**Result: the prompt is back.** `work/shell_fortify_fixed.img` reaches `# `
(`serial_test_ext.log` line 639, image digests in
`work/shell_fortify_fixed.img.digests`, shell SHA-256
`f18212b682e48c8d...`, built from `manifest_shell_fortify_fixed.json`).

What is still broken is narrower, and it is now isolated by experiment: **the
shell prints the prompt but does not respond to input.** Sending `echo hi`
terminated by `\r` and by `\n` both produced zero bytes back. `pgetc` only
completes a line on `'\n'` (`input.c:220`, `:237`), so `\r` was expected to
fail, but neither worked.

The shell is not spinning. With the VM held at the prompt, no CPL=3 register
sample was taken in 30 attempts, so it is blocked in a syscall rather than
burning CPU.

**Where the input is lost: below the shell, in the console receive path.**
`tools/bootlab/init/tty_rx_probe.c` is a freestanding `LC_UNIXTHREAD` PID 1,
built exactly like `init_shell.c` (0 undefined symbols, 0 `LC_LOAD_DYLIB`), that
opens `/dev/console`, makes it the controlling terminal, and then loops
`write "RX> " ; read(0, buf, 4)`. Staged as `/sbin/launchd` in
`work/tty_rx.img` (`manifest_tty_rx.json`), it reaches the loop and
`read(2)` **never returns**: four lines of `hi\n` written to the one serial
client produced no `read =`, no `GOT`, and no `INPUT DELIVERED`.

Nothing echoed either, and that is the part that locates the fault. In
canonical mode the tty line discipline echoes on **receipt**, before any
process reads. So a byte that reaches the kernel would be echoed even with no
reader attached. Silence therefore means the byte never reaches the tty at
all -- the failure is upstream of `read(2)`, in the kernel's console/serial
receive path. It is not the shell, not libedit line editing, and not `wait4`.

This supersedes the earlier assumption that the missing `wait4` fix was the
remaining blocker. The child-wait path still has no evidence either way,
because the shell has never executed a command.

No external `echo`/`cat`, pipeline, or redirection has been observed running.

`Kernel/xnu` DOES need work for this one, and it is a different workstream from
the userland bring-up above.

**The experiment above has now been run, and the answer is: the pe_serial fix
is necessary but NOT sufficient.**

`Kernel/xnu/pexpert/i386/pe_serial.c` carries an uncommitted fix (bind `gPESF`
to the legacy 16550 table and call `serial_init()` on first `uart_putc`,
because `uart_getc()` gates on `uart_initted`/`legacy_uart_enabled`/`gPESF` and
none was ever set on x86). Whether the booted image carried it was previously
unverifiable: the image is stripped, `legacy_uart_probe` is static, and
`strings` finds no marker.

`kernel_build.py` was re-run from current source. The rebuilt kernel is a
**different binary** -- `dafedea66e67ab36a…`, where every earlier image
carried `dcf028fce3f9670c…` -- so the earlier images did **not** contain the
change, and `pe_serial.o` in the build tree now carries `_legacy_uart_enabled`.

Rebuilt images on that kernel (`work/tty_rx2.img`, `work/shell_kx.img`):

- The probe still prints `RX> ` once and its `read(2)` still never returns
  after four `hi\n` lines; the harness confirms it sent them
  (`RX PROMPT OK -- sending b'hi'`). No echo, no `read =`, no `GOT`.
- The shell still reaches `# `, and `echo hi` still produces no CPL=3 sample
  and no response.

So the fault is confirmed to sit in the kernel console receive path, and the
existing pe_serial fix does not close it. What remains open on the kernel side
is whether the tty is actually attached to the serial driver that
`uart_getc()` reads from, and whether the receive path is polled at all on this
path. That is the next thing to instrument, and it is kernel work -- it needs
its own authorisation, since `Kernel/xnu` has not been touched beyond the
already-present local `pe_serial.c` edit.

Until input is delivered, external `echo`/`cat`, pipelines, redirection and
`wait4` all remain unverified: the shell has never executed a command.
