# ravynOS userspace bring-up — findings and state

Written 2026-09-29. This is the record of how a static ravynOS userland program
goes from "does not start" through "cannot yet allocate" to "allocates, and is
then handed a bad `argc`", and what is proven versus open. Every claim below is
backed by a preserved log; nothing here is inferred from plausibility. The
shell does **not** boot to an interactive shell and nothing in this document
should be read as saying it does.

**Companion document.** `PROVENANCE-PLAN.md` answers the separate question of
where every binary comes from: what is ours, what is Apple's open-source
Darwin, and what was lifted out of the host Mac. The rule that governs it is
in **PROVENANCE-PLAN §4 P7** — borrowing Apple's *source* is the project,
borrowing Apple's *built binaries* is the defect — and the mechanical gate that
enforces it is described in `README.md` ("The build gate"). The short version:
host **build tools** are acceptable and unavoidable; **vendored Apple OSS** is
the intended path; host **runtime binaries** in a staged image are never
acceptable.

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

**Both of those open questions were wrong, and the kernel was not at fault in
the way the evidence suggested. Two independent causes, both in how the system
is configured and built.**

### Cause 1: the boot argument, not the receive path

`serialmode` is parsed as a hex boot argument (`osfmk/i386/i386_init.c:928`).
`serial=1` is `SERIALMODE_OUTPUT` only; `SERIALMODE_INPUT` is `0x02`
(`osfmk/console/serial_protos.h:52-55`). Every image in this investigation was
booted with `serial=1`, and the log confirms it: `Serial mode specified:
00000001`.

`serial_keyboard_init()` returns immediately unless that bit is set
(`osfmk/console/serial_general.c:57-59`), so the poller thread that is the
*only* consumer of `serial_getc()` was never created. Nothing in the kernel
ever called `uart_getc()` during normal operation -- output used
`pal_serial_putc` only -- which is why the missing input looked like a kernel
defect. `serial=3` is OUTPUT|INPUT; the log then shows `Serial keyboard
started`, and the RX probe reports `INPUT DELIVERED` with `read = 3` and the
bytes it typed.

The path is polled, not interrupt-driven: `serial_keyboard_poll` ->
`_serial_getc` -> `serial_getc` -> `uart_getc` -> `cons_cinput` -> the km tty
line discipline -> `ttyinput` -> `t_rawq`/`t_canq` -> a waiting `read(2)`.
`boot.py` and `README.md` hardcoded `serial=1` and now use `serial=3`.

### Cause 2: a stale `kern_exit.o` in the build tree

With input working, builtins returned to the prompt but the first *forked*
command produced correct output and then hung the shell forever. The child ran
fine; the parent never reaped it.

`kernel_build.py` recompiles an explicit allowlist of objects that carry ravynOS
fixes, and `bsd/DEVELOPMENT/kern_exit.o.json` was **not** in it. So the
exec-shadow parent-wakeup fix that is already in the source
(`bsd/kern/kern_exit.c:2571-2582`) was never compiled into the kernel -- the
build tree kept an older object, and every relink produced a "successful"
kernel with the fix missing. This is the same failure class as the stale
`libc_static` fortify objects, and exactly the trap the allowlist comment
describes: a green build that changed nothing.

Adding `kern_exit.o` to the allowlist fixed it. Temporary `RVDBG` tracing
confirmed the intended sequence end to end, and was then removed:

```
RVDBG wait4 enter q=1 want=-1
RVDBG wait4 child=2 stat=2 waiting=0
RVDBG wait4 SLEEP on parent q=1 nfound=1
RVDBG exit pid=2 pp=1 shadow=1 inum=2     <- exec shadow
RVDBG exit pid=2 pp=1 shadow=0 inum=2     <- real proc exiting
RVDBG exit MARK ZOMBIE pid=2 pp=1
RVDBG exit WAKE parent pp=1
RVDBG wait4 child=2 stat=5 waiting=0      <- SZOMB
RVDBG wait4 REAP zombie child=2
RVDBG wait4 no children -> ECHILD (q=1)
```

### Verified working

On the clean, uninstrumented kernel (`work/shell_final.img`, kernel
`babb292ce3ffbcf4…`), 4/4 commands returned to the prompt, and an earlier run
gave 6/6 and 7/7:

- builtins (`echo`) -- output plus prompt
- external commands (`/bin/ls /`, `cat /hello.txt`) -- correct output plus prompt
- single-stage pipeline (`echo x | cat`) -- `x` plus prompt
- redirections (`echo x > /f1`) -- the open is attempted and the failure is
  reported (`Read-only file system`), then the prompt returns
- the shell survives a child dying of SIGILL or SIGSEGV and keeps accepting
  input

### Writable root filesystem (2026-09-29)

The read-only root is fixed. Three separate defects were involved.

**1. Root mounts are seeded read-only and msdosfs never clears the flag.**
`vfs_rootmountalloc_internal()` sets `mp->mnt_flag = MNT_RDONLY | MNT_ROOTFS`
(`bsd/vfs/vfs_subr.c:1146`) as a default, expecting the filesystem to clear it
if the device is writable. msdosfs derived `MSDOSFSMNT_RONLY` from that bit
alone and never queried the device, so the root was permanently read-only and
every write failed with `EROFS`.

The block layer is genuinely writable, so this was safe to fix rather than a
mask: `ahci_block.c` is the built-in q35 AHCI bdevsw driver, its `ahci_strategy`
calls `ahci_transfer_sectors()`, which issues real ATA `WRITE DMA EXT` (0x35)
through the PRDT with a W-bit command header, and `ahci_ioctl()` answers
`DKIOCISWRITABLE` with 1. `msdosfs_vfs_mount()` now queries `DKIOCISWRITABLE` and
clears `MNT_RDONLY` via `vfs_clearflags()` for the root mount only, so an
explicitly read-only mount elsewhere is still honoured.

**2. A fatal fortify trap on every file creation.** With the root writable, the
create path panicked in `msdosfs_createde`. The backtrace was symbolised
misleadingly as `msdosfs_chainalloc` (that function was never entered), so the
real owner was resolved with a linker map plus DWARF: it is
`msdosfs_createde.cold.2`, and the trap is `__xnu_fortify_trap_write()` --
`ml_fatal_trap(0xbffe)`, i.e. `XNU_HARD_TRAP_STRING_CHK` from
`osfmk/libsa/string.h`.

`string.h` selects `__XNU_FORTIFY_SOURCE=2` when `XNU_KERNEL_PRIVATE` is
defined, and level 2 turns a fortified object-size check into a *fatal* trap.
`msdosfs_compile.sh` clones the *kernel's* flags, which include
`-D XNU_KERNEL_PRIVATE`, onto a *kext*. msdosfs is a kext and should build at
level 1, so the script now passes `-D_FORTIFY_SOURCE=0`. This is the same family
as the earlier `libc_static` fortify self-loop.

**3. Correction: the `pe_serial` change is required, not optional.** The earlier
conclusion in this document -- that `serial=3` alone was the whole fix and the
local `pe_serial.c` edit was unnecessary -- was wrong. It rested on seeing
"Serial keyboard started" in the log, which only proves the poller thread was
created. Instrumenting `uart_getc()` showed the guard failing on every poll with
`initted=0 legacy=0 lpss=0 pcie=0 gPESF=0`: nothing in the pristine file binds
`gPESF`, so `uart_getc()` always returned -1. Output worked only because
`uart_putc()` writes the transmit register directly. `serial_init()` is not
reached on this path either (`pal_serial_init()` has no live caller), so the fix
binds the legacy 16550 function table on first use inside `uart_getc()`. No
register programming is needed: the firmware already set the UART up, which is
why output worked with no kernel init at all.

Both the boot argument and this binding are required; neither alone delivers
input.

### 2026-09-30 correction: A–F shell acceptance passed

The `_init_clock_port` failure was a stale-binary selection, not the current
static-shell initializer path. The failed run used `tools/bootlab/staged/bin/sh`
(SHA prefix `82d3b51e`) from `manifest_shellpid1.json`; it called
`___libc_init` and reached `_init_clock_port`. The successful A–F run used
`work/sh.static_init` (SHA-256
`a954602d55653555754562089ece49eb4888d0607120ced5980921254268dbf3`), which
calls `__ravyn_static_libc_init`.

The serial RX probe separately received `PING1234` with the `serial=3` loader
(`work/serial_RX_full_35347_1790823100539190000.log` and
`work/input_RX_full_35347_1790823100539190000.log`). The shell PID-1 banner was
moved until after console descriptors were duplicated, making it visible on
the serial console.

One-QEMU A–F verification passed with `-smp 2` and kernel `cpus=1`:
`work/KEEP_af_run2_ALL-PASS_report.txt` and
`work/KEEP_af_run2_ALL-PASS_serial.log` record A, banner plus initial prompt;
B, builtin `echo hello` → `hello`; C, external `/bin/echo external-ok` →
`external-ok`; D, `echo hi | /bin/cat` → `hi`; E1, redirection to `/tmp/f`
returned to prompt without error; E2, `/bin/cat /tmp/f` →
`redirected-content`; and F, `echo second-still-alive` →
`second-still-alive`, with prompt return. No kernel edits were made.

### Verified writable

On a clean kernel, 7/7 commands returned to the prompt and the host-side image
changed, so writes reach the FAT rather than a buffer cache:

- `echo A > /f1` then `cat /f1` -> `A`
- `echo B >> /f1` then `cat /f1` -> `A` / `B`
- `/bin/mkdir /d1` -> succeeds, and `ls /` shows `d1`
- `ls /` also shows `f1` and `.sh_history`
- `echo pipe-ok | cat` -> still works

Cross-boot persistence was then confirmed by re-booting the *same* image without
rebuilding it: `cat /f1` returned the previously written `A` / `B`, and `d1`
was still present.

### Unsynchronised AHCI I/O (2026-09-29)

The intermittent child crash is fixed, and it was never really a shell or
pipeline problem. What looked like a pipeline bug -- `echo a | cat | cat`
dying, children dying of SIGSEGV, sometimes plain `cat /f1` dying, and
sometimes a run where everything worked -- was corrupted disk reads.

`bsd/dev/i386/ahci_block.c` programs the port through a single command list
(`ahci_clb`), a single command table entry (`ahci_ct`) and a single 64 KB
bounce buffer (`ahci_bounce`). All three are file-scope globals, and
`ahci_transfer_sectors()` busy-waits on the port's PxCI/TFD registers. With
no lock anywhere in the path, two threads doing I/O concurrently overwrite each
other's FIS, PRDT and data and then race on PxCI. The failure mode is silently
wrong data, not an I/O error, so a corrupted read surfaces much later as a
child that dies loading a mangled image.

This was invisible while the root was read-only. Making it writable changed the
I/O pattern completely -- `msdosfs_markvoldirty()` at mount, real writes, and
FAT syncing -- so the buf cache, msdosfs and the sync threads started to
overlap. That is why the crash appeared only after the read-only fix.

`ahci_strategy()` now holds an `LCK_MTX_DECLARE`d mutex around
`ahci_transfer_sectors()`. The lock deliberately does not cover
`buf_biodone()`, which can re-enter the I/O path.

Verified on two consecutive boots of the same image, 6/6 and 5/5 commands
returning to the prompt with zero child faults:

- `echo t1 | cat | cat` -> `t1` (two-stage)
- `echo t2 | cat | cat | cat` -> `t2` (three-stage)
- `echo t3 > /g1` then `cat /g1` -> `t3`
- `ls /` shows `g1`, and it is still there on the next boot

### `random_init` cold-boot panic — root-caused to a small kernel slide (2026-09-29)

The intermittent `random_init: failed to allocate a major number` panic is
**not** a BSD bug, and it is not the `cdevsw` free-slot scan. It is a symptom of
the kernel image's writable data not being loaded.

Reproduced at roughly 1 boot in 12. The cheap detector is one line earlier in
the same boot:

```
AHCI: Port 0 ready, bdevsw registered at major -1     <- bad boot
AHCI: Port 0 ready, bdevsw registered at major 1      <- good boot
```

In a bad boot both `bdevsw_add` and `cdevsw_add` fail, and they are adjacent in
`__DATA` (`_bdevsw` is 0x540 bytes at 0xffffff8000e990d0, `_cdevsw` is 0x1c00
immediately after it) — a contiguous ~8.5 KB, i.e. two or more pages. The
reproduction loop only had to run to the `ahci_init` line, not to the panic,
which cut the cycle roughly in half.

Instrumenting `cdevsw_isfree` showed every slot holding the same foreign data
(`d_open = d_ttys = 0x3000000000000`, `d_type = -1`) while `nocdev` itself was
perfectly initialised. A canary added at four points in `bsd_init` then proved
the decisive part: in a bad boot `cdevsw` is *already* wrong at the very first
canary, immediately after `printf(copyright)`, and never changes. In a good
boot it holds valid `__TEXT` pointers from that point on. So the static
initialisers were never applied; the memory is holding stale physical
contents, and the values look like leftover 32-bit firmware code
(`0x8007_0742`, `0x8007_06bf`) — the classic 0xffffff80... kernel pointers are
simply absent.

The correlation with the kernel slide is exact:

| boot | slide | `cdevsw` |
| --- | --- | --- |
| good | 0x7400000 ... 0x1fe00000 (116–510 MB) | valid |
| bad | 0x2200000, 0x2400000, 0x2e00000 (34–46 MB) | corrupt |

`vm_kernel_slide` is not chosen by the kernel: `i386_vm_init` computes
`base_address = ml_static_ptovirt(args->kaddr)` and
`vm_kernel_slide = base_address - static_base_address`, and `args->kaddr`
comes from the EFI loader (`tools/bootlab/assets/boot.efi`), which randomises
it. Note the boot args request `slide=0` and a slide is applied anyway.

So: a low `kaddr` leaves the `__DATA` pages for these two tables unmapped or
overlaid. The fix belongs in the EFI loader's KASLR — it should not emit an
`args->kaddr` that low — not in BSD. The loader is a prebuilt binary here, so
this is not yet fixed. The fastest way to confirm a candidate fix is the
`bdevsw registered at major -1` detector above.

### Still broken

- UEFI intermittently reports `Can't find image information`. This is a
  separate firmware-level failure; those runs never reach `bsd_init`.

`kernel_build.py` now emits `work/kernel_link.map`. The panic backtrace
symboliser mislabelled the faulting frame, and the map is what made the real
function recoverable; it is worth keeping for future kernel debugging.

---

## 12. Apple-free boot path — the loader now reaches the kernel (2026-09-30)

`tools/efiloader/src/loader.c` (our own EFI loader, staged by
`manifest_applefree.json` as `System/Library/CoreServices/BOOT.EFI`) previously
could not load the kernel at all. Seven real defects were found and fixed, each
confirmed by the boot log. With all of them in, the kernel boots from power-on
through `i386_vm_init`, `pmap_bootstrap`, `kernel_bootstrap`,
`vm_page_bootstrap`, `zone_bootstrap`, `kmem_init` and into `efi_init`.

### The fixes, in the order the boot exposed them

1. **The SimpleFS protocol GUID was wrong.** `GUID_SIMPLE_FS` used
   `...-11D2-8E3F-...`; the real
   `EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID` is
   `964E5B22-6459-11D2-8E39-00A0C969723B`. `0x3F` is the *LoadedImage* GUID's
   tail, copied in by mistake. Every `HandleProtocol`/`LocateHandle` for
   SimpleFS therefore failed, and the loader's long "this firmware is broken"
   fallback chain was a misdiagnosis of one wrong byte. Fixing it produced
   `HP(SimpleFS)=0` and made the whole chain dead code (deleted). The same
   byte was wrong in `mini.c` and `hostsim.py`, which is why the host
   simulator agreed with the bug.

2. **`EFI_FILE_PROTOCOL.Open` was called with `OpenMode = 0`.** UEFI requires
   `EFI_FILE_MODE_READ`; `0` is not a valid mode, EDK2 rejects it, and
   `root->Open` always failed.

3. **`EFI_BUFFER_TOO_SMALL` was defined as `ERR(4)`.** It is status code **5**
   (`ERR(4)` is `EFI_BAD_BUFFER_SIZE`), so the `GetMemoryMap(size)` success
   path was unreachable.

4. **EFI status values were truncated to `int`.** `int st2` lost the top half
   of every 64-bit `EFI_STATUS`, so `(u64)st2 != EFI_BUFFER_TOO_SMALL` could
   never be true and `return (u64)st2` returned nonsense.

5. **The memory map was strided by `sizeof(EFI_MEMORY_DESCRIPTOR)`.** The spec
   forbids assuming the firmware's `DescriptorSize` equals the struct size, and
   OVMF reports **48** against our 40. `find_block`, the `ram_top` scan and
   `A->MemoryMapDescriptorSize` now use the reported stride.

6. **The 64-bit -> 32-bit handoff never worked.** The old design wrote its
   far-return frame *on top of* its own 32-bit stub and far-returned to a
   hard-coded `0x20080`, valid only when the handoff page is `0x20000` — the
   gate's fixed page, never the real one. The gate's probe had never printed
   anything, i.e. it had never once run. The handoff now follows Apple
   boot.efi's sequence byte for byte
   (`tools/efiloader/ref/apple-boot32-modeswitch.S`): `lgdt`, flat data
   selectors, clear `CR0.PG`, clear `EFER.LME`, then a **near jump** with
   `eax = boot_args`. No far return, no CS reload. The GDT base moved to
   `g_hoff_page + 0x10` so data is selector `0x10`, as in Apple's table. The
   kernel's first instruction is 32-bit `pushal` into a COM1 routine printing
   `EAX=<boot_args>`; the log now shows `EAX=01781000` then
   `i386_init(0x1781000)`.

7. **Two things the kernel needs in LOW memory, plus a real device tree.**
   - `PE_state.deviceTreeHead = ml_static_ptovirt(args->deviceTreeP)`, and
     `ml_static_ptovirt(0)` is the **physmap base**, not NULL. Passing
     `deviceTreeP = 0` made the kernel `SecureDTInit()` a bogus tree at
     `0xffffff8000000000`, and the first `SecureDTLookupEntry` walked garbage
     (`#PF`, `#DF`, triple fault).
   - `i386_vm_init` reads `args->MemoryMap` through the kernel's early
     **static** physmap window, which does not reach the loader's own `.bss` at
     ~2 GiB (`#PF` at `0xffffff807de14d28` = static base + the loader's
     `g_memmap`).

   The loader now builds a real device tree in its low handoff block and copies
   the memory map there too. The tree is
   `root{name="device-tree"} -> /chosen{name, random-seed(256 bytes)}`.
   `random-seed` is required: `bootseed_init()` panics without it, and
   `PE_get_random_seed` must return at least `SEED_SIZE` (192) bytes. Note
   `skipProperties()` returns NULL for a node with **no** properties, so the
   root must carry one.

### Still broken

- **The last blocker is the EFI runtime region, and it is now fully
  characterised.** `efi_init` maps every `EFI_MEMORY_RUNTIME` range at
  `VirtualStart | VM_MIN_KERNEL_ADDRESS`, and `pmap_map_bd` panics unless that
  VA's page table entry already exists. The kernel preallocates nothing for
  these ranges — the window is exactly `[0, physfree)`, where
  `physfree = kaddr + ksize`, and **`ksize` is ours to set**. That is the load-
  bearing discovery, and it is now exploited: the loader gives the five ranges
  `VirtualStart` 0x2000000, 0x3000000, 0x4000000, 0x5000000, 0x6000000 and
  extends `ksize` to a 128 MiB floor, so all five map and the kernel reaches
  `Boot args version 2 revision 0 mode 64`.

  The window is narrow, and all four edges are now measured — not guessed:

  | `physfree` | result |
  | --- | --- |
  | 24 MiB (old) | `percpu: max_cpus_from_firmware not yet initialized`, before `efi_init` |
  | **128 MiB** | **all five ranges map; reaches `Boot args version 2 revision 0 mode 64`** |
  | 2 GiB | dies in `vm_page_bootstrap` ("Allocating hash buckets...") |
  | 4 GiB | dies in `Idle_PTs_init` |

  Two ways of covering the system table were tried and **both fail**, so neither
  is in the tree:

  - *Identity `VirtualStart`s.* The obvious choice, because
    `efi_set_tables_64()` reads the system table through `ml_static_ptovirt()` —
    `0xffffff8000000000 + physical` — and the runtime service pointers inside
    that table are absolute physical addresses too. It drags `physfree` out to
    the ranges' own addresses near 2 GiB, which is exactly the 2 GiB row above.
    Clearing `EFI_MEMORY_RUNTIME` above a 2 GiB limit was also tried; the
    remaining ranges still sit too high, so it does not help either.
  - *Retargeting `A->efiSystemTable`* at the range's new VA. **Regressed** the
    boot to the same earlier `percpu` panic, so it is out.

  So the last blocker is one page: the system table's range (phys
  `0x7f8ed000`) is now at `0xffffff8003000000`, but the kernel reads the table
  at `0xffffff807f9ec018`, which is unmapped, and `#PF`s there.

  The architecturally right fix is `EFI_RUNTIME_SERVICES.SetVirtualAddressMap`
  before `ExitBootServices`, as Apple's loader does — the firmware moves the
  runtime code to low VAs and fixes up the pointers inside the system table
  together, which is the part we cannot do by hand. **It was implemented and
  tried, and it hangs the firmware**: EDK2 dumps its registers and the guest
  never returns, with no `SetVirtualAddressMap ->` status line ever printed.
  So EDK2 rejects the map we hand it — most likely because it validates the
  argument against its own live map, and we pass our *copy* with `VirtualStart`
  already rewritten, at a `MemoryMapSize`/`DescriptorSize` taken from the
  earlier query. Reverted; the tree is back at the `765d33a9` build.

  Doing this properly means: take the runtime-services pointer as `efi_main`'s
  third argument (it is not reachable from `ST`), re-fetch the map immediately
  before the call so the key is current, pass the firmware's own expectations
  for the `VirtualStart` values, and only then copy the system table into the
  low handoff block — the system table is not runtime code, so the firmware
  leaves it at its high physical address and `ml_static_ptovirt` still cannot
  reach it.
- The UEFI `Can't find image information` failure is unchanged and separate.

### Corrections to earlier sections

- `fatread.c`'s claim that the UEFI spec puts `NumberOfPartitionEntries` at
  0x50 as a UINT64 is wrong: it is a UINT32 at 0x50 and `SizeOfPartitionEntry`
  a UINT32 at 0x54, which is exactly what the image stores.
- `work/kernel_link.map` describes `work/stripped_kernel.development`
  (2026-09-29), **not** `assets/kernel.development` (2026-09-28). They are
  different builds, so the map is stale for that asset.

## 13. The system table blocker is resolved (2026-09-30)

The kernel now boots from the apple-free loader all the way to
`bsd_init: done`, mounts the root filesystem, and execs `/bin/echo` as PID 1.
Log: `work/serial_applefree.full.log`, kernel sha256 `e5f59b2b…`.

### The fix: the physmap, not the static window

`efi_set_tables_64()` reached the EFI system table with `ml_static_ptovirt()`,
which is `paddr | VM_MIN_KERNEL_ADDRESS` and can only produce an address in the
early identity window. OVMF places the table at physical `0x7f9ec018`
(~2041 MiB), so it faulted.

That window cannot be grown to reach it, and the reasons are structural:

- It is hard-capped at `NKPT (500) * PTE_PER_PAGE (512) * 4096` = **1000 MiB**
  of preallocated level-1 tables. The target is 2.04x that. `fillkpt()`
  (`i386_init.c:410`) has **no clamp**, so an oversized `ksize` silently
  overwrites `IdlePTD`/`IdlePDPT`/`IdlePML4`. `Idle_PTs_release()`
  (`i386_init.c:480-482`) clamps the same limit, so the cap is deliberate.
- It costs 1:1 real RAM: `physfree` -> `first_avail` (`i386_init.c:799`) ->
  `avail_start` (`i386_vm_init.c:736`).
- `i386_vm_init.c:707` adds `pmptr->end - pmptr->base` into `avail_remaining`
  unconditionally, including the branch at 628-659 that just marked the range
  fully allocated. `pmap_free_pages()` therefore over-reports, the hash-bucket
  array is oversized (`vm_resident.c:1098-1104`), and `pmap_steal_memory()`
  exhausts `pmap_next_page_hi()` and panics. This is the real 2 GiB failure.

The physmap is the window built for exactly this. `physmap_init()` sizes it
from `PhysicalMemorySize + 4 GB`, and `PHYSMAP_PTOV(x)` is `x + physmap_base`
with a bounds check. It scales with installed RAM, so this is the correct
primitive on a >4 GB machine and the 128 MiB `ksize` floor is no longer needed
for the system table (dropping it is still to be verified).

Three sites changed in `osfmk/i386/AT386/model_dep.c`:
- `efi_init()`: `PHYSMAP_PTOV(args->efiSystemTable)`.
- `hibernate_newruntime_map()`: same. There are two copies of this code and the
  second one is the one that actually faulted.
- `efi_set_tables_64()`: `PHYSMAP_PTOV(system_table->RuntimeServices)`. That
  field is a *physical* pointer into firmware data, so it needs the same
  translation; without it the fault just moved one line down.

### Dead end: SetVirtualAddressMap on OVMF

Apple's loader calls it, so it was implemented in full (third `efi_main`
argument, runtime-services struct, low `VirtualStart` values). It **double-faults
inside OVMF** (`check_exception old: 0xffffffff new: 0xd`, IP in firmware,
CR3 = firmware tables) regardless of whether the map is the firmware's own or a
freshly re-fetched one with a current key. Reverted; it is also now unnecessary.

### Three harness bugs that invalidated boots in this session

1. `model_dep.o` was not on the `kernel_build.py` rebuild allowlist, so edits to
   it produced an unchanged kernel. Added, with a comment matching the existing
   entries.
2. `run_applefree.sh` pins `KERNEL` to `assets/kernel.development` and only
   falls back to `work/stripped_kernel.development` if that file is *missing*.
   Every "full" boot silently used the 2026-09-28 asset, so three kernel fixes
   appeared to do nothing. The pin is deliberate ("so a rebuild by another
   worker cannot change what this run is a test OF") and is kept, but it now
   warns loudly when the asset is older than the local build. Use
   `RAVYN_KERNEL=work/stripped_kernel.development` to test a local build.
3. `python3 kernel_build.py | grep ... | head -5` SIGPIPE-killed the build
   before it reached `model_dep` and the link. Do not page a build pipeline.

### Next blocker (userspace)

PID 1 (`/bin/echo`) reaches dyld, which reports:
`dyld: UNBINDABLE chained fixup: bind ordinal 0 is out of range,
bindTargets.count() is 0`. That is the staged-userland dyld work, not the
loader or the kernel.

## 14. The random_init panic is gone — verified over 4 cold boots (2026-09-30)

This item had been blocked for the whole session, because it could not be
tested until the kernel reached `bsd_init`. It can now. Harness:

    RAVYN_KERNEL=work/stripped_kernel.development ./run_applefree.sh full 150

`work/boot.img` is NOT the image for this harness — `run.sh full` drives a
different manifest and its loader reports `sweep found 0 volumes` /
`RL: no SimpleFS`. Do not read that as a kernel regression; use
`run_applefree.sh`, which is the path that reaches the kernel.

Rebuild the image first: `python3 mkimage.py` (verified 61 files,
`all content hashes match`, kernel sha256
`e8895819a27f1be0175531ac60e0c57e1fc22c3c8ff4bfe7d6797663c4a876cd`).

Four consecutive cold boots, counting markers in each run's own serial log:

| run | early_random_init: done | bsd_init: done | random_init major-number panic | execve /bin/echo | dyld UNBINDABLE |
|-----|------------------------|----------------|-------------------------------|------------------|-----------------|
| 1   | yes | yes | **0** | yes | yes |
| 2   | yes | yes | **0** | yes | yes |
| 3   | yes | yes | **0** | yes | yes |
| 4   | yes | yes | **0** | yes | yes |

The failure that used to end these boots —

    panic(cpu 0 caller ...): random_init: failed to allocate a major number!
        @randomdev.c:106

— does not occur in any of them. That was the intermittent cold-boot panic
fixed in 466017b4b4 (small kernel slide); it is confirmed gone, not merely
absent from one lucky run.

### What is now the first failure

Each boot runs to completion and then dies in userspace:

    bsd_init: done
    bsd_init: bsd_do_post - doneload_init_program: /usr/appleinternal/sbin/launchd.development
    load_init_program: attempting to load /sbin/launchd
    === RAVYNOS DYNAMIC-USERLAND GATE: execve /bin/echo ===
    DYLD-LOAD-BASE: 0x114fd1000
    dyld: UNBINDABLE chained fixup: bind ordinal 0 is out of range,
          bindTargets.count() is 0, fixups walked so far 3
    panic(...): initproc failed to start -- exit reason namespace 2 subcode 0xb

So the ordering has changed, and it matters when reading older logs: the
kernel is healthy well past `random_init`, and this is now a pure
staged-userland/dyld defect. Note the panic text is `initproc failed to
start`, NOT `random_init` — do not grep for the old signature and conclude
the fix regressed.

The dyld defect is deterministic (4/4), not intermittent, so it is safe to
iterate on. `/bin/echo`'s chained-fixups blob validates on the host
(imports_count=10, imports_format=1, seg_info_offset[4] = [0,0,0x18,0],
page_size=0x4000, pointer_format=0x0c DYLD_CHAINED_PTR_64_CACHE on
__DATA_CONST, __got size 0x50 = 10 pointers), so the Mach-O on disk is not
malformed — dyld is not finding bind targets for it at all.

### Why this cannot be fixed by rebuilding dyld here

Relinking dyld from source needs `libSystem.B`, and `libSystem.B` needs
`libsystem_trace`, which needs a userspace `<os/log.h>` + `<os/log_mem.h>`
that this tree does not have:

- `log.c` uses `os_log_buffer_s`, `os_log_buffer_context_t`, and
  `os_log_context_s.log` / `.buffer`. None of those exist in
  `Libraries/Libsystem/private/os/log.h`, whose provisional layout has five
  fields and no buffer at all.
- `Kernel/xnu/libkern/os/log_mem.h:36` needs `lck_spin_t`, and there is no
  `lck.h` anywhere in the tree (upstream xnu has `libkern/lck.h`; this copy
  does not). `lck_spin_t` is only defined in kernel-only osfmk headers.

That is a reconstruction of Apple's logging subsystem — buffers, contexts,
queues, signposts — not a header import, and inventing its layout would
repeat exactly the ABI risk that file's header comment warns about. It is
left undone deliberately, not overlooked.

---

## 15. Correcting the dyld attribution, and what actually blocks the loader (2026-10-01)

### The attribution in section 13/14 is wrong

Section 13 ends by naming

    dyld: UNBINDABLE chained fixup: bind ordinal 0 is out of range,
    bindTargets.count() is 0

as "staged-userland dyld work", and commit c2c18857cc goes further: "the
UNBINDABLE ... defect belonged to the Apple-derived dyld specifically".
Both are wrong. That error is emitted by **our own** MH_DYLINKER, and it is a
true positive rather than a probe artifact. Three measurements:

1. `reportUnbindableBind()` (dyld3/MachOLoaded.cpp:1133) is called from exactly
   two lines, both inside `fixupAllChainedFixups`. Three call sites exist:
   dyldInitialization.cpp:144 passes an EMPTY `Array<const void*>()`;
   Loading.cpp:735 and ImageLoaderMachOCompressed.cpp:1019 pass a FILLED
   `targetAddrs`. Only the first can print `count() is 0`.
2. That site walks `dyldsMachHeader` -- dyld's own image -- before `dyld::_main`,
   so no client image has been loaded yet.
3. Resolving each `## symbol stub for:` site to its enclosing function shows all
   six are ordinary non-probe code: `mapCacheSystemWide`,
   `UnwindCursor<...>::jumpto`, `__Unwind_RaiseException`, `__Unwind_Resume`,
   `_mach_msg_overwrite`.

Probe interference was tested and refuted. The empty `bindTargets` is correct
design: a bootstrap dylinker is mapped before anything is bound, so it must
carry ZERO imports (Apple's /usr/lib/dyld has zero imports, zero
LC_LOAD_DYLIB, zero __stubs). `git show 6e14ace62a` confirms the empty array
predates the CHAINPROBE instrumentation, so there is no production path to
restore. Deleting the probe would remove the diagnostic and leave the same
slots unresolvable.

### The real blocker: the dylinker had 4 imports where it must have 0

`dyld_info -imports` on the built image listed 4, and `dyld_info -fixups`
showed the 3rd fixup walked is the first bind -- exactly the log's "fixups
walked so far 3". `__stubs` was 0x18 bytes = 4 stubs, one per import.

Two are now fixed and verified:

- **`__unw_getcontext` and `__libunwind_Registers_x86_64_jumpto`.** One cause:
  `Developer/Default.xctoolchain/llvm/libunwind/CMakeLists.txt` has no
  `project()` call, so CMake enables C/CXX implicitly but not ASM, and the
  assembler sources listed at `src/CMakeLists.txt:24-26` are SILENTLY DROPPED.
  Measured: `grep -c UnwindRegisters build.ninja` = 0, and no `.S.o` existed.
  Those two files are the only definitions (`UnwindRegistersSave.S:76`,
  `UnwindRegistersRestore.S:71`). Fixed with `enable_language(ASM)` plus
  `-DCMAKE_ASM_COMPILER` in `Libraries/Makefile`. A link test in the exact
  MH_DYLINKER filetype reproduces the defect against the old archive (both
  symbols undefined) and clears it against the new one (zero undefined).

- **`__shared_region_map_and_slide_np`.** No provider exists: syscall 438 is
  `{ int nosys(void); }` at `bsd/kern/syscalls.master:664`, and only the
  differently-shaped `__shared_region_map_and_slide_2_np` is implemented. No
  manifest stages a `dyld_shared_cache`. `mapCacheSystemWide` is now compiled
  out under `__RAVYNOS__` with an explicit "unsupported" error, rather than
  stubbed. `mapCachePrivate` (no syscall) is untouched, so a per-process cache
  would still load. Note `__shared_region_check_np` (syscall 294) IS
  implemented and already resolves from `libkernel.a`, so it correctly stays.

### isysroot-cc was hiding the rest of the problem

`isysroot-cc` classified `-dylinker` as a dylib and injected
`-undefined dynamic_lookup` into the loader link. That both trips ld64
("Shared cache eligible dylibs cannot use '-undefined dynamic_lookup'") and,
where accepted, allows the one image that must defer nothing to defer it. It is
now tracked separately (`dylinker=yes`) and gets the link hygiene WITHOUT
`-undefined dynamic_lookup`.

Removing that flag is what made the invariant honest, and it immediately
exposed **8 further imports that the old link had silently deferred to
runtime**: `_close$UNIX2003`, `_fcntl$UNIX2003`, `_mmap$UNIX2003`,
`_mprotect$UNIX2003`, `_munmap$UNIX2003`, `_open$UNIX2003`, `_pread$UNIX2003`,
`_fwrite`. Seven are TWOLEVEL-namespace aliases that no archive in the SDK
defines (`nm` finds `_close` etc. in `libkernel.a`, never the `$UNIX2003`
form); `_fwrite` is absent from the `usr/local/lib/dyld/libc.a` the loader
links. These are pre-existing latent failures that the permissive flag was
concealing -- not regressions introduced by these fixes.

### Current measured state

Built image: MH_DYLINKER, LC_ID_DYLINKER, LC_UNIXTHREAD entry, 0
LC_LOAD_DYLIB. **9 undefined symbols, 9 chained BIND fixups.** Down from 4
imports + 8 masked = 12, but still not zero, so `/bin/echo` still cannot be
accepted and **no dynamic gate run has been performed**.

Remaining work, in order:

1. The 8 libc symbols. Needs `$UNIX2003` alias definitions plus `fwrite` in
   the archive set the MH_DYLINKER links (`usr/local/lib/dyld/libc.a`).
2. `_mach_msg2`. No compatible wrapper exists. It is emitted from
   `libsyscall/mach/mach_msg.c` calling `mach_msg2_trap` with 8 args; the
   kernel trap is 47 with that ABI. The SDK's
   `Developer/ravynOS.sdk/usr/include/mach/syscall_sw.h:125-131` jumps from -46
   straight to -48, so the mapping is simply missing. That header is a
   user-space SDK input (not `Kernel/xnu`), and adding `kernel_trap(...
   -47, 8)` there is the candidate. The old -31 is a different ABI and must
   not be substituted, and `mach_msg2` must not be renamed or stubbed: a stub
   returning -1 would break dyld's messaging, which the recorded boot trace
   shows is on the live `_mig_get_reply_port` -> `_mach_msg` path.

Verification is `/tmp/zeroimport.sh` (0 undefined, 0 binds) plus one
`run_dynamic_gate.sh` PASS (`RAVYN-DYNAMIC-USERLAND-OK`) once it reads zero.
Neither the disappearance of the UNBINDABLE line nor a probe edit counts as
acceptance.

### 15.1 Progress on the remaining imports (2026-10-01, later)

**mach_msg2 trap: the veneer now emits.** `mach_msg2_trap` had no
user-space veneer because the trap table skipped it: both
`Developer/ravynOS.sdk/usr/include/mach/syscall_sw.h` and the
`System.framework/.../PrivateHeaders/mach/syscall_sw.h` copy jumped from
`kernel_trap(pid_for_task,-46,2)` straight to `kernel_trap(macx_swapon,-48,4)`.
`kernel_trap(mach_msg2_trap,-47,8)` is now present in both copies in the repo
SDK, guarded by `#if defined(__LP64__)` to match the kernel registration
(`osfmk/kern/syscall_sw.c`: `MACH_TRAP(mach_msg2_trap, 8, 16, munge_llllllll)`
under `__LP64__ || __arm64__`, `kern_invalid` otherwise). 8 is the kernel's
`munge_llllllll`; the older -31 is a different ABI and must not be substituted.

**Two copies are not enough -- there are three trees.** The build does not
compile against `Developer/ravynOS.sdk` in the repo. `Libraries/Makefile` and
`build_all_libsystem.sh:39` both set
`SDK="$BUILD/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk"`,
a SEPARATE tree under `/Users/max/Projects/build`. Adding -47 to the repo
copies changed nothing observable: the assembled object still emitted only
`_macx_swapon`. Patching the two build-SDK copies made the veneer appear, with
the correct immediate:

    _mach_msg2_trap:
      movq %rcx, %r10
      movl $0x100002f, %eax        ## 0x1000000 | 47 = SYSCALL_CONSTRUCT_MACH(47)
      syscall

Both copies of `mach/syscall_sw.h` must carry the entry: they share an
include guard, so which one wins depends on include order.

**Still outstanding: `mach_msg2` ITSELF.** `libsyscall/mach/mach_msg.c` CALLS
`mach_msg2()` at :302 (vector form) and :305 (scalar form) from
`mach_msg_overwrite`, but `mach_msg2` is DEFINED nowhere in this tree -- only
`mach_msg2_internal` (a 7-argument function that packs into `mach_msg2_trap`)
exists. So the gap is now precisely: the trap veneer is available, but the
`mach_msg2` wrapper that packs (msgh_bits|send_size), (msgh_remote|msgh_local),
(msgh_voucher|msgh_id), (desc_count|rcv_name), (rcv_size|priority) into the
trap's five packed uint64s has no implementation. Writing that packing means
reproducing an Apple bit layout that is not available in this tree, and it must
NOT be guessed. Not stubbed: a `-1` stub would break dyld, which reaches this
through `_mach_msg_overwrite` -> `__kernelrpc_*` on the live MIG path.

**The 8 libc imports are still unresolved** (7 x `$UNIX2003` + `_fwrite`).
Audit noted the `$UNIX2003` suffix is LP64-gated in `sys/cdefs.h:586-592` and
that `__LP64__` IS defined for `--target=x86_64-apple-darwin` (verified:
`clang -dM` reports it). So the suffix should be EMPTY and these references
should not exist -- which points at the header tree actually being compiled
against, i.e. the same stale-build-SDK problem above, rather than at a missing
provider. `libkernel.a` defines `_close`, `_open`, `_mmap`, ... but never the
`$UNIX2003` forms. `_fwrite` has a real provider at
`libsystem_c/stdio/FreeBSD/fwrite.c` in the `libFreeBSD` archive
(`libFreeBSD/Makefile:261`), which full libsystem_c links but `libc_dyld.a`
deliberately excludes.

**State: 9 undefined, 9 binds. No QEMU run.** The invariant is not met, so
`/bin/echo` still cannot be accepted and the single authorized dynamic gate
attempt remains unspent.

### 15.2 mach_msg2: the trap and the packing were authoritative; the wrapper was NOT missing (SUPERSEDED by §15.7)

> **STATUS: SUPERSEDED / INTERMEDIATE.** The wrapper this section once called
> "the exact missing prerequisite" was found in-tree and has been ported. The
> MH_DYLINKER is now at **0 undefined / 0 binds** (§15.7). Nothing here describes
> the current blocker, because there is no longer one. What remains below is
> provenance only: the trap work and the packing derivation were both correct,
> and the *reason* the wrapper looked missing is worth keeping.

**The trap is done.** `kernel_trap(mach_msg2_trap,-47,8)` is in all four copies
of `mach/syscall_sw.h` (two in the repo SDK, two in the build SDK) and the
veneer assembles with the correct immediate:

    _mach_msg2_trap:  movq %rcx,%r10 ; movl $0x100002f,%eax ; syscall
                                            0x1000000|47 = MACH class, 47

**The bit packing IS authoritative and in-tree.** It is the inverse of the
kernel's own unpacking at `Kernel/xnu/osfmk/ipc/mach_msg.c:934-990`:

    uint64_t mb_ss = args->msgh_bits_and_send_size;   /* LO bits, HI send_size */
    uint64_t mr_lp = args->msgh_remote_and_local_port;/* LO remote,  HI local   */
    uint64_t mv_id = args->msgh_voucher_and_id;       /* LO voucher, HI id      */
    uint64_t dc_rn = args->desc_count_and_rcv_name;   /* LO dsc_cnt, HI rcv_name*/
    uint64_t rs_pr = args->rcv_size_and_priority;     /* LO rcv_size, HI prio   */
    timeout = args->timeout;                          /* passed through        */

kernel reads `msgh_bits = (mach_msg_bits_t)(mb_ss)`,
`send_size = (mach_msg_size_t)(mb_ss >> 32)`,
`msgh_remote_port = (mach_port_name_t)(mr_lp)`, `msgh_local_port = (mr_lp >> 32)`,
`msgh_voucher_port = (mach_port_name_t)(mv_id)`, `msgh_id = (mach_msg_id_t)(mv_id >> 32)`,
`send_dsc_count = (mach_msg_size_t)dc_rn`, `rcv_name = (mach_port_name_t)(dc_rn >> 32)`,
`priority = (mach_msg_priority_t)(rs_pr >> 32)`. So the packing is fully
determined by LO/HI halves -- no inference needed for THAT part.

**RETRACTED 2026-10-01: `mach_msg2()` was never closed-source, and this section
was wrong about where it lives.** It is a userspace `static inline` in
`osfmk/mach/message.h`, shipped in-tree at
**`Kernel/xnu/osfmk/mach/message.h:1477-1530`**, and byte-identical to upstream
`apple-oss-distributions/xnu` `main`
`osfmk/mach/message.h:1461-1514` (fetched and compared directly). The earlier
search only looked in `libsyscall/`, where the two CALL sites live and the
definition genuinely is not -- so the absence was a search-scope artifact, the
same class of error §4 records.

The real defect was that this project's SDK `mach/message.h` did not carry it.
`build-libraries.sh` had already SOURCED `mach_msg_option64_t`, every
`MACH64_*` bit and `mach_msg_vector_t` into the SDK copy (osfmk:1042-1161 and
:605-624) but not this `#if PRIVATE` region, so `mach_msg.c` compiled with no
`mach_msg2` in scope even though `-DPRIVATE` was set.

**The descriptor-count rule, which this section called underivable, is now
determined:**

    base = (MACH64_MSG_VECTOR set) ? ((mach_msg_vector_t *)data)->msgv_data
                                    : (mach_msg_base_t *)data;
    descriptors = ((option64 & MACH64_SEND_MSG) &&
                   (base->header.msgh_bits & MACH_MSGH_BITS_COMPLEX))
                ? base->body.msgh_descriptor_count : 0;

so the low half of `desc_count_and_rcv_name` is neither "0 for scalar and 2 for
vector" nor taken from the call arguments: it is read out of the message body,
and for the VECTOR path out of `vecs[MACH_MSGV_IDX_MSG].msgv_data` -- which is
precisely why that call site passes the `vecs` array as `data` and the literal
`2, 2` as `send_size`/`rcv_size`. The literal `2, 2` are the vector element
counts (they land in `mb_ss>>32` and `rs_pr`), not a descriptor count.

### 15.3 The 8 libc imports: root-caused, and 7 of 8 fixed (2026-10-01, later)

**The 7 `$UNIX2003` imports were a build-flag defect, not missing providers.**
Root cause chain, each step measured:

1. `bmake -n src/glue.o` emitted **0** occurrences of `XNU_PLATFORM_MacOSX`.
   The build exports `EXTRA_DEFINES="-DXNU_PLATFORM_MacOSX"` (build-libraries.sh)
   and bsd.sys.mk folds it into CFLAGS, but `Libraries/dyld/dyld/makefile`
   assigns `CFLAGS = ${COMMONFLAGS} ${CFLAGS.${.TARGET:T}}`, REBUILDING CFLAGS
   from COMMONFLAGS and discarding what bsd.sys.mk computed.
2. That matters because this component compiles with
   `-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd` ahead of the SDK, so `<sys/cdefs.h>`
   is the KERNEL's header. That header picks its per-product values from
   `XNU_PLATFORM_*` (Kernel/xnu/bsd/sys/cdefs.h:731-746); the MacOSX + x86_64
   arm defines `__DARWIN_ONLY_UNIX_CONFORMANCE 1`.
3. With the macro missing, no `XNU_PLATFORM_*` block matched, so
   `__DARWIN_ONLY_UNIX_CONFORMANCE` stayed UNDEFINED, `#if` treated it as 0
   (cdefs.h:667-672), `__DARWIN_SUF_UNIX03` became `"$UNIX2003"`, and
   `__DARWIN_ALIAS_C()` (cdefs.h:713) appended that suffix to every aliased
   libc name.

Verified directly: with `-I Kernel/xnu/bsd -DXNU_PLATFORM_MacOSX` the same probe
prints `SUF=[] ONLY=1`; the `XNU_PLATFORM_MacOSX` block is also what makes
`__DARWIN_64_BIT_INO_T` come out 1. Fix: thread `${EXTRA_DEFINES}` through
CFLAGS/CXXFLAGS/ACFLAGS explicitly. After it, `bmake -n src/glue.o` shows 1
occurrence and **all seven** `_close/_open/_mmap/_fcntl/_mprotect/_munmap/
_pread$UNIX2003` imports are gone -- the unsuffixed providers in `libkernel.a`
now match.

**`_fwrite` also resolved** by the same rebuild; it needed no new provider.

### Interim state at this point in the workstream: 1 undefined, down from 9 (SUPERSEDED by §15.7 -- now 0/0)

The single remaining link error is:

    "__dyld_debugger_notification"

referenced by `src/dyld_debugger.o`. A real provider EXISTS --
`$SDK/usr/lib/system/libdyld.a` defines it as `T` -- but that archive is not
on the dylinker's link line. Adding `-ldyld` fixes this symbol and immediately
surfaces `___strcpy_chk`, which libdyld's member calls. `___strcpy_chk` also
has a real, ABI-correct provider in the tree
(`Libraries/Libsystem/libsystem_c/secure/strcpy_chk.c`, built into
`libsystem_c/libFortifySource/libFortifySource.a`), but linking that archive
WHolesale makes the link much worse (27 undefined: it drags in the libc++
exception runtime and `__os_crash`), and passing a single archive member
(`libFortifySource.a(strcpy_chk.o)`) does not survive bmake. So the correct
next step is to build and link just `strcpy_chk.o`, not the archive.

**CORRECTION to 15.1 and 15.2, per review:**

- `mach_msg2_internal` has **8** parameters, not 7 (data, options, five packed
  uint64s, timeout) -- see Kernel/xnu/libsyscall/mach/mach_msg.c:93-101.
- The packing IS authoritative, not unavailable. 15.2 overstated the gap. The
  kernel's own unpacking at Kernel/xnu/osfmk/ipc/mach_msg.c:934-990 fixes every
  field and half: `mb_ss` = bits|send_size, `mr_lp` = remote|local,
  `mv_id` = voucher|id, `dc_rn` = desc_count|rcv_name, `rs_pr` = rcv_size|
  priority, timeout passed through.
- **THIS THIRD BULLET WAS ALSO WRONG, and is retracted by §15.2/§15.7.** The
  `mach_msg2()` prototype/body was never "closed-source libsystem" and never an
  outstanding prerequisite: it is an in-tree userspace `static inline` at
  `Kernel/xnu/osfmk/mach/message.h:1477-1530`, and its descriptor-count rule is
  now ported and ABI-tested. The MH_DYLINKER is at **0 undefined / 0 binds**.

**No QEMU at this point in the workstream** (`_mach_msg2` was still an import,
so the invariant was not met). QEMU has since been run once with no verdict and
is recorded in §15.8.

### 15.4 The stray `glue.c` shadow and the 1-import state that followed (SUPERSEDED by §15.7 -- now 0/0)

> **STATUS: SUPERSEDED / INTERMEDIATE.** The counts and the "ONE import" claim
> below describe an intermediate state that has since passed. The MH_DYLINKER is
> now **0 undefined / 0 binds** (§15.7). The `glue.c` root-cause analysis in this
> section is sound and is kept as provenance; the residual-import framing is not
> current, and "closed-source" was never the right answer (see §15.2).

**At this point in the workstream** `__dyld_debugger_notification` was resolved
and the build had exactly ONE import: `_mach_msg2`.

The cause was not a source or flag defect and not a missing provider. A stray
**0-byte `Libraries/dyld/dyld/src/glue.c`** was shadowing the real source at
`Libraries/dyld/src/glue.c` (45265 bytes). The dylinker makefile lists
`src/glue.c` in SRCS with `.PATH: ${.CURDIR}/..`, and bmake resolves the local
`src/` directory first, so the empty file won. `glue.o` compiled to a 208-byte
object whose `__TEXT` segment was **size 0x0** -- the entire glue layer,
including the no-op debugger-notification hook, silently absent. Preprocessing
`src/glue.c` with the real build flags produced only line markers and no code,
which is what identified it.

Confirmed fixed: `glue.o` is now 25456 bytes and defines
`__dyld_debugger_notification` as `T`. No stub, no new provider, no guard
changed -- the correct source was simply being shadowed by an empty file, and
the file is gone.

Counts across this workstream (all `nm -u` / `dyld_info -fixups` on the built
MH_DYLINKER, which remains filetype DYLINKER, LC_ID_DYLINKER, LC_UNIXTHREAD
entry, 0 LC_LOAD_DYLIB):

| stage                                   | undefined | binds |
|-----------------------------------------|-----------|-------|
| start of this workstream                | 12        | 12    |
| after libunwind ASM fix + shared-cache scoping | 9  | 9     |
| after EXTRA_DEFINES fix (7 `$UNIX2003` + `_fwrite`) | 2 | 2 |
| after removing the stray glue.c shadow | 1     | 1     |
| **after porting the `mach_msg2()` inline (§15.7)** | **0** | **0** |

The last row is the current state; the rows above it are history.

The single remaining import was `_mach_msg2`. Its "closed-source wrapper"
explanation was WRONG -- see §15.2; it is an in-tree userspace `static inline`
in `osfmk/mach/message.h` that this project's SDK header simply did not carry.
Resolved in §15.7, which also records the zero-import measurement that
supersedes this table.

QEMU has since been run against the 0/0 image and recorded in §15.8 (no
verdict). It was not run while this section's 1-import state was still true.

### 15.5 What actually changed for `__dyld_debugger_notification` (evidence)

The fast audit's reading is right and my first report's framing was not:
`glue.c` has **no whole-TU guard**. It opens with `#if TARGET_OS_SIMULATOR`
(line 51) and the hook is at line 1211 under `#if ! TARGET_OS_SIMULATOR`, and
neither macro is set on the command line.

Measured:

- `grep TARGET_OS_SIMULATOR Libraries/dyld/dyld/makefile` -> **no match**. No
  flag change was involved.
- `clang -dM -E` over `<TargetConditionals.h>` for the dylinker's target gives
  `#define TARGET_OS_SIMULATOR 0` and `#define TARGET_OS_OSX 1`. So
  `#if ! TARGET_OS_SIMULATOR` is TRUE and the definition was always meant to be
  compiled in. The guard is not the defect.
- Nothing about `TargetConditionals.h`, the source, or the flags changed
  between the empty object and the good one.

**What did change: a 0-byte file shadowing the source.** A stray
`Libraries/dyld/dyld/src/glue.c` (0 bytes) existed alongside the real
`Libraries/dyld/src/glue.c` (45265 bytes). The makefile lists `src/glue.c` in
SRCS and sets `.PATH: ${.CURDIR}/..`, so bmake resolved the **local** `src/`
directory first and the empty file won.

Preprocessor evidence at the time of failure: running the exact build command
with `-E` produced only line markers and no code --

    # 1 "src/glue.c"
    # 1 "src/glue.c" 2

- i.e. the TU genuinely had no content. And `otool -l src/glue.o` showed
  `__TEXT` with `size 0x0000000000000000`, offset 208.

Causation then proved by a controlled two-sided experiment, same flags,
same environment:

| control | stray 0-byte `dyld/src/glue.c` | `src/glue.o` size | defines notification |
|---------|-------------------------------|-------------------|----------------------|
| A       | present                        | 208               | no                   |
| B       | removed                        | 25456             | yes, `T` at 0x8c0   |

Control A reproduces the empty object on demand; control B removes it. That
is the positive control this project insists on: the file's presence is the
cause, not the guard, the flags, or the header.

After a clean rebuild the built image has **exactly 1 undefined symbol and 1
chained BIND**: `_mach_msg2`. The link now exits non-zero precisely because
that one symbol has no provider -- which is the correct, honest behaviour now
that `isysroot-cc` no longer injects `-undefined dynamic_lookup` for
`-dylinker`. The installed image is MH_DYLINKER / LC_ID_DYLINKER /
LC_UNIXTHREAD entry / 0 LC_LOAD_DYLIB.

### 15.6 Staging readiness: the built MH_DYLINKER can be staged (throwaway probe)

The gate as configured cannot work yet for a reason independent of the imports:
`manifest_dynamic.json` stages `/usr/lib/dyld` from
`{"asset": "usr/lib/dyld"}`, and `assets/usr/lib/dyld` is a **DYLIB**
(988088 bytes, sha256 d3749b24...). The kernel rejects that before dyld runs,
with `OS_REASON_EXEC` / `EXEC_EXIT_REASON_BAD_MACHO` (namespace 9 code 0x1).

A throwaway manifest was built to prove the correct artifact CAN be staged,
without touching anything protected:

- `tools/bootlab/work/manifest_mhdylinker_probe.json` (work/ is gitignored).
  Generated from `manifest_dynamic.json`; a diff of the two `files` arrays
  shows **exactly one** differing entry:

      FROM {"path": "usr/lib/dyld", "asset": "usr/lib/dyld"}
      TO   {"path": "usr/lib/dyld", "file": "<abs path to built MH_DYLINKER>"}

  `mkimage.py`'s `"file"` key is read-only (`open(p,"rb").read()`) and accepts
  an absolute path, so nothing under `assets/` is written, replaced, or even
  opened for writing. `grep` for writes into `assets/` in mkimage.py returns
  only two `"rb"` reads (template_head.bin / template_tail.bin).

- Built to `work/probe_mhdylinker.img` with the kernel pinned to the read-only
  `assets/kernel.development`. mkimage self-verified:
  `verify OK: 61 files, 75 tree entries, all content hashes match`.

Verified by reading the bytes back OUT of the image independently of mkimage
(`fat32img.Fat32Img.read_path("/usr/lib/dyld")`):

| check | result |
|-------|--------|
| staged bytes | 1725400, sha256 `67e15a6d...` |
| built MH_DYLINKER bytes | 1725400, sha256 `67e15a6d...` |
| **byte-identical** | **True** |
| filetype | `MH_MAGIC_64 X86_64 ALL 0x00 DYLINKER 15 1944` |
| LC_ID_DYLINKER / LC_UNIXTHREAD | 1 / 1 |
| LC_LOAD_DYLIB | 0 |
| chained BIND fixups | 1 — `__DATA_CONST __got 0x000D4010 bind _mach_msg2` |
| `nm -u` | `_mach_msg2` |

Note the staged sha differs from the asset's (`d3749b24...`), so this is
demonstrably not the DYLIB.

**Status: staging-READY, NOT acceptance-READY.** The image stages correctly,
but it still carries the single `_mach_msg2` bind, so the MH_DYLINKER's
self-rebase will still stop at `__got[2]` with the UNBINDABLE message. This
probe exists to prove the staging path, nothing more. **No QEMU was run.**

### 15.7 The zero-import invariant is MET (2026-10-01)

**Change made: two SDK header copies only.** `Developer/ravynOS.sdk/usr/include/
mach/message.h` and `.../System.framework/Versions/B/PrivateHeaders/mach/
message.h` now carry `Kernel/xnu/osfmk/mach/message.h:1477-1530` verbatim --
the `mach_msg2_internal()` declaration plus the `mach_msg2()` `static inline`
under `#if PRIVATE` + `(defined(__LP64__) || defined(__arm64__))`. `diff` of
the ported block against the osfmk source is empty.

**Placement is load-bearing and is NOT the upstream-adjacent one.** The block
goes *after* the sourced `MACH64_*` / `mach_msg_vector_t` block, because this
SDK file carries those later than osfmk does. Inserting it after the `mach_msg`
declaration (i.e. where it sits upstream) fails:

    error: unknown type name 'mach_msg_option64_t'
    error: use of undeclared identifier 'MACH64_MSG_VECTOR'
    error: use of undeclared identifier 'mach_msg_vector_t'

**Where it is selected.** `libsystem_kernel`'s CFLAGS carry `-DPRIVATE` and put
the framework `PrivateHeaders` ahead of the SDK's `usr/include`, and the
generated `.depend.mach_msg.o:102` names the framework copy. Both copies were
updated and both are synced into the build SDK by `build-libraries.sh`.

**Focused ABI test** (throwaway, `/tmp/mm2test.c`) stubs `mach_msg2_internal`
and captures all 8 packed arguments. 27/27 assertions pass on **both** selected
include paths, and they pin the two rules 15.2 could not derive:

| case | `desc_count_and_rcv_name` low half |
|---|---|
| scalar, COMPLEX, sending | `base->body.msgh_descriptor_count` (3 in the test) |
| scalar, COMPLEX, receive-only | 0 |
| scalar, simple, sending | 0 even with a stale count in the body |
| **vector**, COMPLEX, sending | **5** -- read through `vecs[0].msgv_data`, *not* the decoy count in the header passed as arg3 |
| vector, receive-only | 0 |

and that the vector path puts the literal `2, 2` into `mb_ss>>32` / `rs_pr`
(the vector element counts) while every header field still comes from arg3.

Three assertions failed on the first run. They were a defect in the TEST, not
the port: this SDK's `MACH_MSGH_BITS(remote, local)` is the legacy 2-arg form
and does **not** OR in `MACH_MSGH_BITS_COMPLEX`, so the test was never marking
the message complex. Recorded because it is the §4 failure shape -- a test that
fails for a reason unrelated to what it claims to measure.

**Measurements after the rebuild** (strict link; `isysroot-cc` no longer
injects `-undefined dynamic_lookup` for `-dylinker`):

| stage | undefined | binds |
|---|---|---|
| after removing the stray `glue.c` shadow (15.4) | 1 | 1 |
| **after porting the `mach_msg2()` inline** | **0** | **0** |

- `libkernel.a` `mach_msg.o`: 0 references to `_mach_msg2`, 117 `callq` sites
  to `_mach_msg2_internal`. Only mach undefined left is `_mach_msg2_trap`,
  supplied by the existing trap-47 veneer.
- built MH_DYLINKER: `nm -u` = 0; `dyld_info -fixups` shows rebases only, 0
  binds. `LC_ID_DYLINKER` 1, `LC_UNIXTHREAD` 1, `LC_DYLD_CHAINED_FIXUPS` 1,
  `LC_LOAD_DYLIB` 0.
- no regression: `___unw_getcontext` and `___libunwind_Registers_x86_64_jumpto`
  still defined; `_mach_msg2`, `___dyld_debugger_notification`, `_close$UNIX2003`,
  `_mmap$UNIX2003`, `_munmap$UNIX2003` all `U=0`.

**Image.** `work/probe_mhdylinker.img` from `work/manifest_mhdylinker_probe.json`,
kernel pinned to the read-only `assets/kernel.development`:
536870912 bytes, sha256 `b4ca1273250b05d7745ddf86db99420aa513c89599bd40a0b22b87ff40ad9e46`;
mkimage `verify OK: 61 files, 75 tree entries`. The staged `/usr/lib/dyld` read
back **out** of the image is `cdf7acb0762b0f8d9d83118ea145257e9f6a959d10c67ce9225aff277a149ec2`
-- byte-identical to the built MH_DYLINKER, distinct from the 988088-byte
`assets/usr/lib/dyld` DYLIB, 0 undefined and 0 binds read back from the image.

### 15.8 First authorized boot produced NO verdict (harness, not kernel) -- see also §15.8b

The gate was launched once, as authorized, after both counts reached zero:

    python3 boot.py --img work/probe_mhdylinker.img --mode full --window 600 \
        --out work/serial_MHDYLINKER_GATE.log

Gates checked in the **live command line** before boot: no QEMU running;
exactly one `qemu-system-x86_64`; `-smp 2`; kernel `cpus=1 quiet_boot=1`
(`boot.py:74` / `boot.py:31`); fresh per-run `vars_full.fd` copied from
`assets/vars.fd` (`boot.py:63`). Boot command sent at 11.9s.

**Outcome: no serial log was produced, so there is no PASS and no BLOCKED.**
`boot.py` writes its serial log only on the normal exit path (`boot.py:178`,
after the print of `serial bytes: N -> path`). That print never happened and
`work/serial_MHDYLINKER_GATE.log` does not exist. QEMU was terminated by
`signal 15` from the harness at roughly 2 minutes -- long before the 600s
kernel budget expired -- so this is **not** the documented firmware
Shell-prompt-latency or `#UD-at-0xB0000` HARNESS case either; the run was cut
short externally. The last CPU samples in `work/qemu_full.log` are in firmware
address range (`RIP=...7ef5844f`, `...7ddf5464`), i.e. the guest was still in
UEFI when it was killed, and the log contains 0 reset records.

**Nothing about dyld was therefore tested.** The zero-import invariant is
established statically and conclusively; whether `/bin/echo` now reaches `main`
is **still unmeasured**. Do not read this run as evidence in either direction.
Evidence kept from THIS run: `work/qemu_full.log` (4111586 B), `work/vars_full.fd`,
`work/probe_mhdylinker.img{,.digests}`, plus `/tmp/gate_stdout.log` and the two
build logs `/tmp/lsk_build.log` and `/tmp/dyld_build.log`. `work/serial_dynamic_PRIOR.log`
is a copy of a PRE-EXISTING log, kept only for comparison; it is not from this run.
No QEMU left running; `boot.py` removed its own `serial_full.sock`/`mon_full.sock`.

⚠️ **A PREVIOUS LOG WAS LOST, and "all logs preserved" would be false.**
`boot.py` writes its QEMU trace to a name derived from the MODE ALONE --
`qemu_log = os.path.join(work, "qemu_%s.log" % args.mode)` (`boot.py:61`), no pid
and no timestamp -- passed as `-D` (`boot.py:85`) and truncated every run. This
run left 4111586 B / 3.9 MB there, whereas the directory inventory taken before
this run recorded that same path at **52.0 MB**. The earlier `qemu_full.log` was
therefore **overwritten and NOT preserved**, and it cannot be recovered.
It is lost because `boot.py` gives
that log a run-independent name, not because it was deleted here. Any earlier
analysis that referred to the 52.0 MB `qemu_full.log` no longer has its
underlying evidence on disk -- `boot.py`'s QEMU log needs a per-run name
(`qemu_<mode>_<pid>_<ns>.log`, as the RX/shell runs already use) before a boot
can be said to preserve prior evidence.

### 15.8b Second authorized attempt: PRE-KERNEL FAILURE, still no dyld verdict (2026-10-01)

Run on a durable background service so the ~2-minute command-wrapper limit
could not kill QEMU -- the suspected cause of the first attempt's truncated
verdict. Same already-built `work/probe_mhdylinker.img`
(`b4ca1273250b05d7745ddf86db99420aa513c89599bd40a0b22b87ff40ad9e46`), no
rebuild, **no `stage_dynamic_libs.sh`, no asset writes**. Verified before
launch: no QEMU running; exactly one QEMU, `-smp 2`; `cpus=1 quiet_boot=1`;
fresh per-run `vars_full.fd` copied from pristine `assets/vars.fd`
(`53dd8277...`). The first attempt's 3.9 MB trace was preserved to
`work/qemu_full.ATTEMPT1-first.log` before this run truncated the fixed-name path
again.

This time `boot.py` ran to completion and **wrote a serial log**
(`work/serial_ATTEMPT2.log`, 6209 bytes), after `kernel boot budget (600s from
the boot command) expired`, `BOOT_EXIT=1`, `alive-tick lines: 0  panic/trap
lines: 0`.

**Verdict: NOT a PASS.** `RAVYN-DYNAMIC-USERLAND-OK` does not appear (count 0),
and the PID-1 banner does not either (count 0).

**It is also not a kernel or dyld verdict, and the reason is decisive.** The
serial output stops inside the ravynOS EFI loader, before any kernel output
whatsoever -- there is no `Darwin Kernel` banner, no `bsd_init`, no panic:

    RL: census(NULL) -> 00000000 n=1976
    RL: LocateHandle -> 00000000 n=1976
    RL: sweep found 0 volumes
    RL: no SimpleFS
    Shell>

The loader came back with `sweep found 0 volumes` / `no SimpleFS`, returned to
the UEFI shell, and never loaded the kernel. **The MH_DYLINKER never executed**,
so `mach_msg2()`, dyld's self-rebase and `/bin/echo` were not exercised at all.
This is a pre-kernel EFI volume-discovery failure, and it is consistent with
attempt 1 also dying inside UEFI.

**SUPERSEDED by sec. 15.10.** The open question below is now answered: it was
neither the throwaway probe image nor the firmware. The image carried a stale
loader binary, and the "1976 handles / census" measurements are artifacts of
that retired build. Do not re-derive a firmware anomaly from this log.

> (originally: "Not yet distinguished: whether this is specific to the throwaway
> probe image or a property of the current EFI loader build. The MBR sector is
> byte-identical to the known-good `work/boot_dynamic.img` (both first-512-byte
> sha256 prefix `4b071b2a9d829f86`), so it is **not** a partition-geometry
> difference. A third boot is required to separate them and was NOT authorised,
> so the question stays open.")

Logs preserved: `work/serial_ATTEMPT2.log` (6209 B),
`work/qemu_full.ATTEMPT2-second.log`, `work/qemu_full.ATTEMPT1-first.log`
(4111586 B), `work/boot_ATTEMPT2_stdout.log`, `work/vars_full.fd`,
`work/probe_mhdylinker.img{,.digests}`. No QEMU left running; `boot.py` removed
`serial_full.sock` and `mon_full.sock`. No asset file was written this attempt.

### 15.9 Two gitignored files under `tools/bootlab/assets/` were rewritten

`stage_dynamic_libs.sh`, run to refresh the dylib closure before rebuilding the
image, wrote:

    assets/usr/lib/libobjc.A.dylib        <- $SDK/usr/lib/libobjc.A.dylib
    assets/usr/lib/system/libobjc.dylib   <- $SDK/usr/lib/libobjc.A.dylib

Both are **untracked and gitignored**, so `git status -- tools/bootlab/assets`
is clean and no *tracked* asset was modified -- but they are files under a path
this workstream's constraints place off-limits, and they are now inside the
built image. Content is a refresh of the same 1608088-byte SDK artifact (the
script verifies `_objc_msgSend` is present among 2145 defined symbols), so this
is very likely a no-op in content terms. **No rollback or restoration has been
attempted, pending approval.**

### 15.10 Root cause of the sec. 15.8b pre-kernel failure: a stale image binary (2026-10-01)

`serial_ATTEMPT2.log` is **not reproducible from current source**, and the cause
is the IMAGE, not the loader code and not the firmware. Three independent
pieces of evidence, each checked offline:

1. **Which binary ran.** `work/probe_mhdylinker.img.digests` records
   `System/Library/CoreServices/BOOT.EFI` =
   `a87c7faa098c4c5bc449abc39cb2d8e0ae7255c2b2c8c982b1d15e407705ea5d`, which is
   byte-identical to `tools/bootlab/assets/boot.efi` (177152 B, mtime
   2026-09-30 05:37). The log's line 17 prints `size=0x000000000002c000`;
   parsing the PE header of each loader copy gives `assets/boot.efi`
   SizeOfImage `0x2c000`, `assets/BOOTX64.EFI` `0x17e2c0`, and the current
   `work/efi/BOOTX64.EFI` `0x2d000`. Only `assets/boot.efi` matches.
2. **That binary predates the current code.** `assets/boot.efi` contains the
   strings `census(NULL)`, `sweep found` and `no SimpleFS`, and no `serial=`
   at all. Current `loader.c` contains none of the census/sweep code (nor do
   commits `ad52635ab2` or `27e1f4b7e9`): volume discovery today is a single
   `HandleProtocol(li->DeviceHandle, SimpleFS)`.
3. **It could not have succeeded.** `assets/boot.efi` contains the
   EFI_LOADED_IMAGE GUID at `0x141c` but the
   EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID is **ABSENT** — neither the correct
   `964E5B22-...-8E39-...` form nor the old buggy `8E3F` form. The current
   `work/efi/BOOTX64.EFI` has it correctly at `0x243c`. A binary with no
   SimpleFS GUID in its packed bytes cannot return that protocol, which is
   exactly `HP(SimpleFS)=00000003` followed by `RL: no SimpleFS`.

**Control proving the firmware is fine.** `work/serial_applefree.full.log`, same
OVMF build and same pristine `vars.fd`, shows the *identical* `DeviceHandle`
`0x000000007e5a8d18` returning `HP(SimpleFS)=00000000` with
`fs=0x000000007e479030`, then `RL: opened kernel` and a full boot. Same handle,
same firmware, different binary. So there is **no current firmware failure**,
and the "measured firmware anomaly" prose that stood in the `loader.c` header
has been corrected.

**The defect was in the manifest.** `manifest_dynamic.json` staged
`System/Library/CoreServices/BOOT.EFI` from `{"asset": "boot.efi"}` and
`EFI/BOOT/BOOTX64.EFI` from `{"asset": "BOOTX64.EFI"}` — both gitignored
copies under `assets/`. The second was not even our loader (SizeOfImage
`0x17e2c0`, 1.5 MB, no `RL:` strings). `manifest_control.json` and
`manifest_applefree.json` already staged `{"file": "work/efi/BOOTX64.EFI"}`,
the live build. Both entries in `manifest_dynamic.json` now use that `file:`
key, so the dynamic gate stages the loader that `build_applefree.sh` actually
produced. `manifest.json` was not touched.

**STILL UNVERIFIED:** whether a dynamic-gate image on the current loader now
reaches the kernel, and whether the MH_DYLINKER ever executes. That needs the
next authorised QEMU boot, which was withheld here. Everything above is
offline-verified from PE bytes, image digests and preserved logs; no QEMU was
run, no file under `assets/` was written, and no existing image was
overwritten.

### 15.11 libslc_builder: CXXSTD none -> c++20 (2026-10-01)

Reported by the independent build-error workstream and fixed there. Recorded
here so the next session does not re-derive it.

**The error.** `Libraries/dyld/libslc_builder` failed to compile on
`Libraries/dyld/dyld3/ClosureBuilder.h:286`:

    std::optional<uint64_t>    methodNameVMOffset;

`std::optional` is a C++17 type. The build was compiling as pre-C++17, so the
name was unknown.

**The fix.** One line in `Libraries/dyld/libslc_builder/Makefile`:

    -CXXSTD = none
    +CXXSTD = c++20

`c++20` rather than the bare minimum `c++17`, which is what the header alone
would require. That choice was made by the build-error workstream; this section
does not claim an audited reason for it, because no C++20-only construct was
found in the target's own sources when checked here.

**Verified.** The full `libslc_builder` target builds: `ClosureBuilder.o`
compiles, and the complete archive is produced at 35,354,288 bytes with 329
warnings and **0 errors**. The direct `bmake` invocation needed
`AR=/usr/bin/ar ARFLAGS=-crs`, because Darwin's `ar` and bmake's defaults
disagree; that is a host-tooling detail, not a source problem.

**NOT verified, and stated rather than glossed:** this covers the full
`libslc_builder` target **only**. There was no full dyld link, so nothing here
shows that `libslc_builder` links cleanly against the rest of dyld, and no
QEMU run means nothing here shows a shared cache is produced or consumed. Those
remain open and belong to whoever runs the dyld link.

No Makefile or other source file was modified in this workstream; this section
is documentation of work done elsewhere.

### 15.12 The full dyld target builds (2026-10-01)

Closes the "no full dyld link" gap left open by 15.11. One new host-tooling
failure, one symlink, and the whole target now links.

**The error, reproduced.** With the 15.11 fix in place the full target got
past `libslc_builder` and died in the last SUBDIR, `chroot_util`:

    /Users/max/Projects/build/Tools/bin/llvm-objcopy --only-keep-debug chroot_util.full chroot_util.debug
    bmake[1]: exec(/Users/max/Projects/build/Tools/bin/llvm-objcopy): No such file or directory
    *** Error code 1

The shape is misleading and worth stating plainly: `chroot_util.cpp` compiled
clean and `chroot_util` **had already linked**. The failure is the
`${OBJCOPY} --only-keep-debug` step that runs last, so a reader skimming for
link errors will find none and conclude the link is broken. It is not.

**Root cause.** `BSD/share/mk/sys.mk:266` sets `OBJCOPY ?= ${TOOLS}/llvm-objcopy`,
and `bsd.prog.mk:205` / `bsd.lib.mk:275` run it as the final step of a
successful link. `TOOLS` is `$BUILD/Tools/bin`, which `build-libraries.sh`
assembles as a small directory of symlinks. It carried `llvm-libtool-darwin`
and `xcrun` -- both documented there for exactly this reason -- but **not**
`llvm-objcopy`. The host Command Line Tools ship `llvm-objdump` and no
`llvm-objcopy`, so `xcrun -f` cannot find one, while the peer-built ravynOS
toolchain has had one all along:

    $BUILD/Developer/Platforms/ravynOS.platform/Developer/Toolchains/Default.xctoolchain/usr/bin/llvm-objcopy
    4804560 bytes, LLVM 17.0.6

**The fix.** One symlink in the existing `TOOLS_DIR` block of
`tools/bootlab/build-libraries.sh` (+13 lines: 11 comment lines recording the
above, 2 lines of symlink), next to the two links already there. Not a source
change, not an mk-file change, and not a change to any dyld source: this is
the same class of gap as `llvm-libtool-darwin`, one tool later in the build.

**The full target, and the command that builds it.** The existing wrapper is
the only documented bmake path, because `-m BSD/share/mk` and the
`isysroot-cc` / `macar` / `xcrun`-shim environment it sets up are all
load-bearing:

    tools/bootlab/build-libraries.sh dyld > /tmp/full_dyld_build2.log 2>&1

The `dyld` argument is the whole component, not a subset: the top-level
Libraries/dyld bmake builds `libdyld.dylib` **and** descends into
`SUBDIR = dyld libdsc libslc_builder chroot_util`. The direct-`bmake` route
15.11 used needed explicit `AR=/usr/bin/ar ARFLAGS=-crs` precisely because it
bypasses this wrapper, which already exports `AR=$HERE/macar`.

**Result: exit 0, 0 errors, all four SUBDIRs reached.** Six artifacts, all
rebuilt in one run:

| artifact | bytes |
|---|---|
| `Libraries/dyld/libdyld.dylib` | 988,088 |
| `Libraries/dyld/libdyld.a` | 4,167,832 |
| `Libraries/dyld/dyld/dyld` (MH_DYLINKER) | 1,725,768 |
| `Libraries/dyld/libdsc/libdsc.a` | 1,937,336 |
| `Libraries/dyld/libslc_builder/libslc_builder.a` | 35,354,288 |
| `Libraries/dyld/chroot_util/chroot_util` | 308,500 |

`libslc_builder.a` lands on exactly the 35,354,288 bytes 15.11 recorded, so
the `CXXSTD` change did not perturb it. `chroot_util` is the first successful
link of that target and is a real binary, not just a link artifact: it is
MH_EXEC and run from the tree it prints `No -chroot <dir>`, exiting 255
(its usage error -- it was invoked with no `-chroot` argument).

**Reproducible.** The identical command was run a second time: exit 0, 0
errors, the same 32 compiler invocations, and the MH_DYLINKER byte-identical
across runs:

    sha256 0791f82781b268a9791d6e37fe291d8daccfed0ffb234c19f1ec4fda2ad295b9

**The 15.7 zero-import invariant still holds** on the freshly rebuilt
MH_DYLINKER, so this rebuild did not regress the loader the gate depends on:

| check | result |
|---|---|
| `nm -u` | 0 |
| chained BIND fixups | 0 |
| `LC_ID_DYLINKER` / `LC_UNIXTHREAD` | 1 / 1 |
| `LC_DYLD_CHAINED_FIXUPS` | 1 |
| `LC_LOAD_DYLIB` | 0 |
| filetype | `MH_MAGIC_64 X86_64 ALL 0x00 DYLINKER 15` |

**What this does and does not establish. Read the limits before citing it.**

- **Build only.** This is a link-and-static-analysis result. No QEMU was run
  and **no runtime or boot behaviour is claimed** -- not for dyld, not for
  `/bin/echo`, not for a shared cache. A target that links is not a target
  that works.
- **The manifest blocker is now RESOLVED and the staged image is verified
  offline.** (This paragraph was written before the manifest was corrected and
  has been updated against the verified result; the correction and the
  validation were done by another workstream, not by this build task.)
  `manifest_dynamic.json` no longer stages `usr/lib/dyld` from
  `{"asset": "usr/lib/dyld"}` -- the 988,088-byte DYLIB that per 15.6 the kernel
  rejects with `OS_REASON_EXEC` / `EXEC_EXIT_REASON_BAD_MACHO` before dyld runs.
  It now stages it from the built loader via the read-only `"file"` key:

      { "path": "usr/lib/dyld", "file": "../../Libraries/dyld/dyld/dyld", ... }

  which is the artifact built in this section, and both EFI paths were moved off
  the stale `assets/` copies at the same time (the 15.10 cause).

  `python3 mkimage.py work/dyldgate_20261001_1209.img --manifest
  manifest_dynamic.json` then returned `verify OK: 61 files, 75 tree entries`,
  exit 0, and the bytes read back **out** of the finished image with
  `fat32img.Fat32Img.read_path` are:

  | check | result |
  |---|---|
  | `/usr/lib/dyld` bytes / sha256 | 1,725,768 / `0791f827...` -- **identical to the `Libraries/dyld/dyld/dyld` built above** |
  | staged dylinker filetype | MH_DYLINKER, `LC_ID_DYLINKER=/usr/lib/dyld`, `LC_UNIXTHREAD` 1, `LC_DYLD_CHAINED_FIXUPS` 1, `LC_LOAD_DYLIB` 0, `nm -u` 0, chained binds 0 |
  | both EFI paths | the live `work/efi/BOOTX64.EFI` (sha256 `4f7c8da5...`) |
  | negative controls | `assets/usr/lib/dyld` (`d3749b24`, DYLIB) and `assets/boot.efi` (`a87c7faa`) **absent** from the image |

  The zero-import invariant therefore holds not only on the build product but
  on the bytes actually inside the image. That image was then **deleted**; the
  evidence is the preserved record
  `tools/bootlab/work/KEEP_dyldgate_20261001_offline_proof.txt` (per-file
  sha256 list plus the read-back measurements), not a retained `.img`.

  **None of this is a runtime result.** It is staging and static structure only.
  It does not show the kernel accepting the image, dyld executing, or
  `/bin/echo` reaching `main`; the next bullet is why that cannot be claimed.
- **A third boot WAS explicitly authorized and run on 2026-10-01. Outcome:
  still NO verdict, but the failure boundary moved a long way downstream.**
  The user explicitly authorized exactly one controlled QEMU boot for this
  gate; the earlier "no third boot" constraint was superseded by that
  authorization and by nothing else. The run used a uniquely named image
  built fresh for it, so no result below depends on a reused artifact:

      python3 mkimage.py work/dyldgate_G1_20261001_125254.img \
          --manifest manifest_dynamic.json \
          --kernel work/stripped_kernel.development
      python3 /tmp/dyldgate_G1_20261001_125254/boot.py \
          --img .../work/dyldgate_G1_20261001_125254.img --mode full \
          --window 600 --out .../work/serial_dyldgate_G1_20261001_125254.log

  `run_dynamic_gate.sh` was deliberately **not** used: lines 88-103 always run
  `stage_dynamic_libs.sh`, which writes the protected gitignored
  `assets/usr/lib/libobjc.A.dylib` and `assets/usr/lib/system/libobjc.dylib`,
  and it hardcodes `work/boot_dynamic.img` / `work/serial_dynamic.log`. `boot.py`
  itself was **not edited**; a byte-identical copy (sha256 `e652aa57...`) was
  run from a temp dir holding a symlink to `assets` and a fresh `work/`, because
  `boot.py` resolves both relative to its own directory (`boot.py:52`, `:63`).
  That is what kept this run from truncating `work/qemu_full.log` a third time
  — the exact data loss documented at 15.8b.

  **Staging, re-verified against the live loader (an audit claimed the loader
  had drifted; it had not).** `work/efi/BOOTX64.EFI` is still
  sha256 `4f7c8da567574af6fbe02e55a4b19d161c0fbb6b0a2ebf341ec4f3481d0a6897`,
  mtime `Oct 1 11:02`, which **predates** the 12:12 offline proof — a file
  cannot have changed after a record that postdates it. Three consecutive
  reads returned the same digest. Provenance is
  `tools/efiloader/src/loader.c` (`d7731bf9...`, 11:01) →
  `work/efi/loader.FULL.obj` (`ca785303...`, 11:02) →
  `work/efi/BOOTX64.EFI`, i.e. the **full** variant, distinct from
  `BOOTX64.TRAMPOLINE.EFI` (`0caf37f7...`). Bytes read back **out** of the
  finished image match at both EFI paths, and the stale `assets/boot.efi`
  (`a87c7faa...`) and the 988,088-byte `assets/usr/lib/dyld` DYLIB
  (`d3749b24...`) are both **absent**. `mkimage` reported
  `verify OK: 61 files, 75 tree entries`, exit 0.

  | attempt | outcome | verdict |
  |---|---|---|
  | 1 (15.8) | boot budget expired, `boot.py` wrote no serial log, so the run's boundary and marker count are **unrecorded** | none -- harness failure, dyld untested |
  | 2 (15.8b) | ran to completion, stopped inside the ravynOS EFI loader at `sweep found 0 volumes` / `no SimpleFS`, returned to `Shell>` | none -- pre-kernel failure, MH_DYLINKER never executed |
  | 3 (this one) | `RAVYN-DYNAMIC-USERLAND-OK` **unrecorded** (serial log never written); trace shows `CPL=0`/`CPL=3` | none -- see below |

  **Why still no verdict, stated precisely so it is not mistaken for one.**
  `boot.py` accumulates the serial stream in memory and writes the log only on
  its normal exit path (`boot.py:175-176`). The harness process was SIGTERM'd
  at 13:01:48 and never reached that write, so
  `work/serial_dyldgate_G1_20261001_125254.log` **does not exist**. There is no
  serial evidence for this run anywhere; it was not lost by being overwritten,
  it was never written. **No runtime acceptance is claimed.** QEMU ran 266s of
  the 600s kernel budget (44%), so this is not budget exhaustion.

  **What the surviving QEMU `-d cpu_reset,int` trace does establish** (kept at
  `work/KEEP_qemu_trace_dyldgate_G1_20261001_125254.log`, 21,312,822 B, plus
  `work/KEEP_vars_used_dyldgate_G1_20261001_125254.fd`). This is a
  `-d cpu_reset,int` trace: it records **raw addresses and register state
  only**, with no symbol names and no process or image attribution. Only what
  the raw records show is claimed below:
  - Kernel-mode execution is reached and sustained: records at `CPL=0` with
    kernel-range RIPs (`0xffffff80...`) appear from trace line 67,232 onward.
    This run is the first with trace evidence of `CPL=0` and `CPL=3`. Attempt 2
    is known to have stopped in EFI, before handoff; attempt 1 has no serial
    record at all, so its boundary is unknown.
  - **Execution at `CPL=3` occurs**: 226 records carry `CPL=3`, with RIPs from
    `0x000000010561f1d0` to `0x00000001056dd2d6`. That span is `0xBE106`
    (778,502 bytes), which **crosses ~190 distinct 4 KiB pages** but lies wholly
    inside the single 1 MiB-aligned region `0x105600000`–`0x1056fffff`. These
    records run from about 65% through the trace to 99.9% of it.
  - `CR2` records non-zero fault addresses in that same low address range
    alongside the `CPL=3` records.
  - The **final raw record** is line 350,852: `v=03 e=0000 i=1 cpl=0` at
    `IP=0008:ffffff8000249319`, followed by a register dump ending
    `RIP=ffffff8000249319 ... CPL=0`. This is a **kernel-mode
    breakpoint/debug event**, and it is the only `v=03` in the whole trace.
    Its cause, and its relationship to the SIGTERM at 13:01:48, are **unknown**.

  **What that does NOT establish, and must not be read as establishing it.**
  Whether `/bin/echo` reached `main` is still **unmeasured**: the required
  marker was never seen, because the serial log was never written. The 226
  `CPL=3` records prove only that code executed at user privilege level; the
  trace carries **no process identity, no image base and no mapping
  information**, so nothing in it can attribute that execution to
  `/bin/echo`, to the static exec-runner, or to any other staged binary.
  Consequently it establishes **nothing** about dyld being mapped, the
  libSystem closure resolving, or `main()` executing. An earlier draft of this
  bullet named `_unix_syscall64`, `_hndl_unix_scall64`,
  `_build_userspace_exit_reason`, `_DebuggerTrapWithState` and
  `_serial_putc_options` as the final kernel activity; **those claims are
  withdrawn** — they came from resolving raw RIPs through an `nm` symbol table
  under an **assumed `vm_kernel_slide == 0`**, which was never verified, and the
  trace itself contains none of those names (0 occurrences of each). An
  unverified slide makes such attribution unsound. Likewise the claim that the
  `CPL=3` addresses "include the exec-runner's own text" is withdrawn: nothing
  identifies which image, if any, was mapped there.

  The next run must therefore be instrumented so that serial output is written
  **incrementally**, not accumulated in memory: `boot.py`'s buffer-then-write
  design (`boot.py:175-176`) is what destroyed this run's only real evidence,
  and it is the single highest-value fix before another attempt.

  The zero-import invariant remains verified statically and is unchanged. The
  accepted-verdict criteria in 15.7 are still **unmet**: `/tmp/zeroimport.sh`
  plus one gate PASS remains the acceptance, and there is still no PASS.
- **A fourth boot WAS authorized and run on 2026-10-01, and it produced the
  first attributed failure boundary in this gate. Outcome: `DYNAMIC GATE:
  BLOCKED` (gate exit 1). Full detail in **15.13**; the summary is here
  because it corrects the conclusion the attempt-3 bullets above leave
  open.** 15.12's last word above was "the next run must be instrumented so
  that serial output is written incrementally" -- that is exactly what was
  done, and it is why this run has a log at all. The protected `boot.py`
  (`e652aa57...`) was **not** edited; a copy in an isolated temp dir
  (`2cb126ff...`) was patched to open the log **before** `Popen` with
  `buffering=0`, write every chunk from both recv sites on arrival, keep the
  in-memory `output` mirror that gates the `Shell>` boot command, and drop
  the final `open(out,"wb")` truncating rewrite -- the rewrite that destroyed
  attempt 3's evidence. It was validated first against a fake-QEMU `PATH`
  shim, including a `SIGKILL` case (unpatched `boot.py` reads `live=0 bytes`
  under the same test, so the test is red-capable).

  **Provenance.** Fresh unique image `dyldgate_G2_20261001_133604.img`
  (536,870,912 B) built by the **unchanged** repo `mkimage.py` (`7d95c429...`)
  run from `tools/bootlab` with `--manifest manifest_dynamic.json`, an
  absolute `--kernel`, no `--gpt-conform`; `verify OK: 61 files, 75 tree
  entries`, exit 0. Bytes read back **out** of the image match their sources:
  both EFI paths `4f7c8da5...`, the MH_DYLINKER `/usr/lib/dyld`
  `0791f827...` (`LC_ID_DYLINKER name = /usr/lib/dyld`, `LC_UNIXTHREAD` 1,
  `LC_DYLD_CHAINED_FIXUPS` 1, `LC_LOAD_DYLIB` 0, `nm -u` 0), `sbin/launchd`
  `61b16d1b...`, the kernel `e8895819...`, `/bin/echo` `d2d4d70e...`; the
  stale `assets/usr/lib/dyld` DYLIB and `assets/boot.efi` are absent.
  macOS has no `setsid(1)`, so the runner was started through a 20-line
  `launch_detached.py` calling `Popen(..., start_new_session=True)`, giving
  it its own session (`PID 3890 PGID 3890 SID 3890`) so no external
  process-group signal can take the log writer down again. QEMU count was 0
  before and exactly 1 after (PID 3893); one launch, no retry.

  **The full 600 s kernel budget was spent**, from the boot command at
  12.84 s to expiry at 612.95 s, runner exit 612.97 s, **QEMU exit code 0**.
  The failure itself happened early and is not budget exhaustion: 38,089
  serial bytes, equal captured and on disk, sha256 `95cb7c35...`. Incremental
  capture is proven at runtime, not only in the shim -- the t=30.00 s
  heartbeat reads `5403 bytes captured, 5403 on disk` while the runner was
  still alive.

  **Verbatim fault signature** (`KEEP_serial_dyldgate_G2_20261001_133604.log`,
  lines 568-576, ordering verified 521 < 571 < 576 < 590):

      === RAVYNOS DYNAMIC-USERLAND GATE: execve /bin/echo ===      (line 521)
      DYLD-LOAD-BASE: 0x10e2bd000                                  (line 540)
      CHAINPROBE: block FIRED, starts=0x10e3cd020 seg_count=4 ...   (line 546)
      CHAINPROBE: 0 of 0 bind slots still unbound after the fixup pass (line 550)
      dyld: Library not loaded: /usr/lib/libSystem.B.dylib          (line 568)
        Referenced from: /bin/echo
        Reason: no suitable image found.  Did find:
          /usr/lib/libSystem.B.dylib: malformed mach-o image: dyld chained fixups info underruns __LINKEDIT
          /usr/lib/libSystem.B.dylib: stat() failed with errno=1
      pid 1 exited -- exit reason namespace 6 subcode 0x7, description Library not loaded: /usr/lib/libSystem.B.dylib   (line 576)
      panic(cpu 0 caller 0xffffff8000abcca9):  initproc failed to start -- exit reason namespace 6 subcode 0x7 ...  (line 590)

  `RAVYN-DYNAMIC-USERLAND-OK` occurrences: **0**. `DYLD-LOAD-BASE` and the
  `CHAINPROBE` lines are the load-bearing new facts: **our built dyld was
  mapped and executed**, and its chained-fixup pass completed with zero bind
  slots left unbound. **The corrected conclusion: `/bin/echo` was reached --
  PID 1 exec'd it and dyld took over -- and dyld then rejected the staged
  `/usr/lib/libSystem.B.dylib`.** That is a different failure from all three
  earlier attempts (none; pre-kernel EFI death; unattributable CPL=3
  records), and it is still **not** a PASS: `/bin/echo`'s `main()` remains
  unmeasured and the libSystem closure remains unresolved. Note the fault
  string says "chained fixups" but is thrown from the **exports trie** check
  at `Libraries/dyld/src/ImageLoaderMachO.cpp:488` (the real chained-fixups
  check is lines 479-480, and the staged file has no
  `LC_DYLD_CHAINED_FIXUPS`); one of the five candidates also fails `stat()`
  with `errno=1` (EPERM), not ENOENT.
- **Reusable by image creation: proven, not just permitted.** The MH_DYLINKER
  built in this section was staged into a real image by the `"file"` key and
  read back byte-identical, so this is no longer a prediction. The archives
  (`libdsc.a`, `libslc_builder.a`, `libdyld.a`) remain host build products that
  do not feed the image, and `chroot_util` is a host-side x86_64 utility that
  must **not** be staged.

One housekeeping note, not acted on: `chroot_util`'s outputs
(`chroot_util`, `.debug`, `.full`, `.depend`) are untracked and **not matched by
any `.gitignore`**. `Libraries/.gitignore` covers `/dyld/*.o` and
`/dyld/*.dylib` and the root `.gitignore` covers `/Libraries/dyld/dyld/dyld`,
but nothing covers `Libraries/dyld/chroot_util/`.

### 15.13 Fourth attempt: dyld RAN. The blocker moved into libSystem.B.dylib (2026-10-01)

One authorized QEMU attempt. **Verdict: `DYNAMIC GATE: BLOCKED` (gate exit 1)
— not a PASS, and not a harness failure either.** For the first time in this
gate the boundary is measured *inside dyld*: the kernel booted, PID 1 ran and
announced itself, `/bin/echo` was exec'd, and **the dynamic linker itself was
mapped and executed**. 15.12 closed with "the next run must be instrumented so
that serial output is written incrementally"; that is what made this result
possible, and it is recorded here first because every other fact below depends
on having a log at all.

**The harness fix, and its falsification test.** The protected
`tools/bootlab/boot.py` (`e652aa57...`, sha256 unchanged before and after this
run) was **not edited**. A copy was made in an isolated temp dir and patched
there; the patch is four changes and nothing else:

1. the serial log is `open()`ed **before** `Popen`, with `buffering=0`, and
   every chunk from **both** recv sites (the main loop and the early-QEMU-exit
   drain) is written the instant it arrives;
2. the in-memory `output` mirror is **kept** (now `Capture.buf`) — it is what
   gates sending the boot command on `b"Shell>"` and what the tick/trap summary
   reads, so a file-only patch would silently never send the boot command and
   the boot would "pass" as a firmware no-op;
3. the final `open(out,"wb")` truncating rewrite is **gone** — the log is
   closed, never rewritten, because that rewrite *is* the 15.12 data loss;
4. `start_new_session=True` on `Popen`, plus SIGTERM/SIGINT handlers that
   record and exit without touching the log.

Runner: `/tmp/dyldgate_G2_20261001_132923/boot.py`, sha256 `2cb126ff...`.
`BOOT_BASE` and `boot_cmd()` are byte-identical to the repo's, so the kernel
command line is unchanged from every prior attempt.

The patch was tested against a **fake QEMU shim on `PATH`** (`boot.py:25`
invokes the bare name `qemu-system-x86_64`, so a shim substitutes the VM with
zero edits) before any real boot. All three cases pass, and the test is
provably red-capable: run against the *unpatched* repo `boot.py` the same T1
case reports `live=0 bytes` and no log file — the exact G1 failure.

| case | assertion | result |
|---|---|---|
| T1 | file has bytes and prefix-matches **while the runner is alive**, then `SIGKILL` (not SIGTERM — only a hard kill skips unwinding) and on-disk size still equals bytes sent | 65 B live → 722 B, `disk=722 sent=722`, exact match |
| T2 | on the **normal** exit path final size equals bytes sent exactly (catches incremental write + a truncating final rewrite) | `disk=722 sent=722`, exact match |
| T3 | a pre-seeded sentinel log is zeroed, and pre-`Shell>` bytes are captured | sentinel gone, `PRE-SHELL-BYTES` present |
| T4 | the `Shell>` gate still fires off the mirror and the boot command is really sent | `boot.efi` present in what the shim received |

**Staging, re-verified.** A **fresh unique** image was built by the
**unchanged repo `mkimage.py`** (`7d95c429...`) run *from* `tools/bootlab`
with `--manifest manifest_dynamic.json`, an absolute `--kernel`, and **no**
`--gpt-conform` (that flag writes into repo `work/`). No copy of `mkimage.py`
was made: it resolves every `"file"` entry against its own `HERE`, so a copy
in `/tmp` would have turned `../../Libraries/dyld/dyld/dyld` into a missing
path. `run_dynamic_gate.sh` was **not** used (lines 90/101 run
`stage_dynamic_libs.sh`, which writes protected gitignored assets).

    work/dyldgate_G2_20261001_133604.img   536,870,912 B
    mkimage: "verify OK: 61 files, 75 tree entries", exit 0

Bytes read back **out** of the finished image (`KEEP_readback_G2.txt`):

| path | bytes | sha256 | matches source |
|---|---|---|---|
| `EFI/BOOT/BOOTX64.EFI` | 181,248 | `4f7c8da5...` | YES |
| `System/Library/CoreServices/BOOT.EFI` | 181,248 | `4f7c8da5...` | YES (both EFI paths, one loader) |
| `usr/lib/dyld` | 1,725,768 | `0791f827...` | YES |
| `sbin/launchd` | 4,208 | `61b16d1b...` | YES |
| `System/Library/Kernels/kernel.development` | 20,043,952 | `e8895819...` | YES |
| `bin/echo` | 100,944 | `d2d4d70e...` | YES |

The staged loader is `MH_MAGIC_64 X86_64 ALL DYLINKER ncmds=15`, with
`LC_ID_DYLINKER name = /usr/lib/dyld`, `LC_UNIXTHREAD 1`,
`LC_DYLD_CHAINED_FIXUPS 1`, `LC_LOAD_DYLIB 0` and `nm -u` = **0** — the
15.7 zero-import invariant, confirmed on the bytes inside the image. Negative
controls hold: the stale `assets/usr/lib/dyld` (988,088 B, **DYLIB**,
`d3749b24...`) and `assets/boot.efi` (`a87c7faa...`) are **absent**.

**The run.** macOS has no `setsid(1)`, so a 20-line `launch_detached.py`
calls `subprocess.Popen(..., start_new_session=True)`, which is `setsid(2)`.
The runner therefore had its **own session** (`PID 3890 PGID 3890 SID 3890`),
which is the point: in attempt 3 the whole process group was signalled and the
log died with it.

    python3 /tmp/dyldgate_G2_20261001_132923/boot.py \
      --img /tmp/dyldgate_G2_20261001_132923/work/dyldgate_G2_20261001_133604.img \
      --mode full --window 600 \
      --out   /tmp/dyldgate_G2_20261001_132923/work/serial_dyldgate_G2_20261001_133604.log \
      --status /tmp/dyldgate_G2_20261001_132923/work/runner_dyldgate_G2_20261001_133604.status \
      --stop-marker RAVYN-DYNAMIC-USERLAND-OK

`command -v qemu-system-x86_64` resolved to `/usr/local/bin` (the real
11.0.1 Mach-O) with the shim absent; QEMU process count was **0 before** and
**exactly 1 after** (PID 3893). One launch, no retry.

| measurement | value |
|---|---|
| boot command sent | 12.84 s |
| kernel budget expiry | 612.95 s (600 s from the command) |
| runner exit | 612.97 s, QEMU exit code **0** |
| serial captured / on disk | 38,089 / 38,089 bytes (equal — nothing buffered) |
| serial log sha256 | `95cb7c35...` |
| QEMU `-d cpu_reset,int` trace | 26,343,467 B |

Incremental capture is **proven at runtime, not just in the shim**: the
heartbeat at t=30.00 s reads `5403 bytes captured, 5403 on disk` while the
runner was still alive and mid-run.

**The verdict, from the log.** Replicating `run_dynamic_gate.sh:111-141`
(`KEEP_gate_verdict_dyldgate_G2.txt`) gives banner **1**, marker **0**, three
fault-signature hits, and **HARNESS-first ordering holds** — the banner is at
byte 30,688 and the first fault is at line 568:

    === RAVYNOS DYNAMIC-USERLAND GATE: execve /bin/echo ===
    DYLD-LOAD-BASE: 0x10e2bd000
    CHAINPROBE: block FIRED, starts=0x10e3cd020 seg_count=4 off0=0 off1=0x18 off2=0x38 off3=0
    CHAINPROBE: 0 of 0 bind slots still unbound after the fixup pass
    dyld: Library not loaded: /usr/lib/libSystem.B.dylib
      Referenced from: /bin/echo
      Reason: no suitable image found.  Did find:
        /usr/lib/libSystem.B.dylib: malformed mach-o image: dyld chained fixups info underruns __LINKEDIT
        /usr/lib/libSystem.B.dylib: stat() failed with errno=1
    pid 1 exited -- exit reason namespace 6 subcode 0x7
    panic: initproc failed to start -- exit reason namespace 6 subcode 0x7

`DYLD-LOAD-BASE` and the `CHAINPROBE` lines are the load-bearing new
evidence: **dyld was mapped and ran**, and its chained-fixup pass completed
with zero bind slots left unbound. That is a different order of magnitude
from attempts 1-3 (no serial; died in EFI; unattributable CPL=3 records).

**Root cause of the new blocker, located in source and confirmed in bytes.**
The staged `/usr/lib/libSystem.B.dylib` is the `assets/` copy (71,948 B,
`de05e04b...`): a 39-`LC_REEXPORT_DYLIB` facade over `/usr/lib/system/*` with
a 1,745-byte `__text` and 27 global symbols. It carries **no
`LC_DYLD_CHAINED_FIXUPS` at all**, and its single `LC_DYLD_EXPORTS_TRIE` has
`dataoff=0 datasize=0` while `__LINKEDIT` starts at `fileoff=0x10000`. So:

    Libraries/dyld/src/ImageLoaderMachO.cpp:488
        if ( exportsTrieCmd->dataoff < linkeditFileOffsetStart )
            throw "malformed mach-o image: dyld chained fixups info underruns __LINKEDIT";

`0 < 65536` fires. Two things are worth stating because both are easy to get
wrong: the message says *"chained fixups"* but line 488 is the **exports
trie** check (the genuine chained-fixups check is lines 479-480, and this
file has no such command), and one of the five "did find" candidates is a
`stat()` failing with `errno=1` (EPERM), not ENOENT.

**What this does not establish.** No PASS: `RAVYN-DYNAMIC-USERLAND-OK` never
appears, so `/bin/echo`'s `main()` is **still unmeasured** and the libSystem
closure is still unresolved — the gate now fails one step later than it ever
has, not differently. The accepted-verdict criteria in 15.7 remain unmet.

Evidence: `tools/bootlab/work/KEEP_serial_dyldgate_G2_20261001_133604.log`,
`KEEP_gate_verdict_dyldgate_G2.txt`, `KEEP_runner_dyldgate_G2_20261001_133604.status`
(+`.stdout`), `KEEP_qemu_trace_dyldgate_G2_20261001_133604.log`,
`KEEP_vars_used_dyldgate_G2_20261001_133604.fd`, `KEEP_readback_G2.txt`,
`PREBOOT_G2_20261001_protected_baseline.txt`. The image and its `.digests`
are kept at `/tmp/dyldgate_G2_20261001_132923/work/`. Protected paths are
unchanged: `boot.py` `e652aa57...`, `mkimage.py` `7d95c429...`,
`manifest.json` `b8b7bed3...`, `fat32img.py` `cefa9110...`, the whole of
`assets/` (84 files, aggregate `4c41b52c...`) byte-identical before and after,
`Kernel/xnu` clean, `Libraries/Libsystem/private/` carrying only the
pre-existing untracked `os/assumes.h`.

Two honest caveats on the tooling. The runner's 30 s heartbeat only advances
when a chunk arrives, so it stops at the panic — cosmetic, but it means a
silent period is not visible in the status sidecar. And the red-control run
against the unpatched `boot.py` **leaked its fake-QEMU child**: `boot.py` has
no child cleanup on `SIGKILL`, and neither does the patched runner, so a hard
kill of the runner orphans QEMU and someone must kill it by hand. That is a
real gap in the harness for any future forced termination.

### 15.14 Corrected dyld closure diagnosis and offline validation (2026-10-01)

This corrects and extends the attempt-4 boundary in 15.13. The preserved run
(`work/KEEP_serial_dyldgate_G2_20261001_133604.log`, 38,089 bytes, sha256
`95cb7c35ed098762d3b0ba77118f5da7a62c773406e1933e0d343ab8c85675e7`; verdict:
`work/KEEP_gate_verdict_dyldgate_G2.txt`) proves the repo-built MH_DYLINKER
loaded and executed, PID 1 execve'd `/bin/echo`, and dyld rejected
`libSystem.B.dylib` at `ImageLoaderMachO.cpp:488`. No QEMU run is part of this
offline correction.

**`.orig` staging is not a fix.** A manifest change to stage
`assets/usr/lib/libSystem.B.dylib.orig` was built into
`work/dyn_libsystem_orig_20261001.img`, then reverted. Parser-validated
inspection of all 49 staged dylibs finds 28 rejected at line 488: each has
`LC_DYLD_EXPORTS_TRIE dataoff=0 datasize=0` against nonzero
`__LINKEDIT.fileoff`. Of the 39 `LC_REEXPORT_DYLIB` targets named by `.orig`,
27 reject and only 12 pass. `.orig` therefore moves the same failure from
depth 0 to depth 1; it does not unblock the gate. `manifest_dynamic.json`
was restored to pre-edit sha256
`6f30473c0d07462191f5ffeaf43029fda3e81049e7892a122b7edd3893beea23`.

**Offline tooling.** `tools/bootlab/closure_check.py` parses raw Mach-O 64-bit
bytes, resolves the manifest's transitive dylib closure, extracts defined and
undefined symbols with weak classification, and replays dyld2's
`ImageLoaderMachO.cpp` checks at lines 479/481/487/489. Run:

    cd tools/bootlab && python3 closure_check.py [manifest.json]

It exits 0 only when the closure is complete, no non-weak undefined symbols
remain unresolved, and every staged dylib passes validation. On the current
`manifest_dynamic.json`: 28 rejects and 99 unresolved non-weak symbols; 99
overcounts because it scans the whole `LC_SYMTAB` (the repo-built closure's
true count is 34). A test manifest staging the repo-built Libsystem closure
reports 0 rejects, 0 unstaged dependencies, and 34 unresolved non-weak symbols.
Thus the repo-built closure (`Libraries/Libsystem/libSystem.B.dylib` plus 28
transitive dependencies) is Mach-O-valid (29/29 dyld2 checks pass), but not
symbol-complete; those 34 unresolved symbols are link defects, being fixed
separately.

The 28 rejecting files are shared-cache extractions with `__TEXT vmaddr` in
`0x7ff8...` and `__LINKEDIT vmaddr=0x7ff880000000`; even with a valid trie,
each colliding image would additionally force multi-GB `vm_alloc`. The line-488
check is byte-identical to upstream Apple dyld-832.7.3 (diffed against
`/tmp/dyldup`), not a local regression; do not relax it.

Other log interpretations: the `stat() failed with errno=1` line is a
reporting artifact. `dyld2.cpp:3484` reads errno after `my_stat` without any
errno reset in `src/`, so stale EPERM residue is printed at line 3510; it is
not a second fault. The tty is not on the critical path: `serial=3` enables
serial keyboard input (`osfmk/i386/i386_init.c:928`), and the A-F shell
acceptance already proved the path. `assets/bin/sh` is a 4,280-byte
`LC_UNIXTHREAD` tick stub, not a shell. `sh.static_init` (1,807,864 bytes,
sha256 `a954602d55653555754562089ece49eb4888d0607120ced5980921254268dbf3`)
produced the `# ` prompt. A dynamic `/bin/sh` needs a new build target.

### 15.15 Repo-built closure boot: dyld completes; pthread host query fails (2026-10-01)

Building on 15.13–15.14, the repo-built `Libraries/Libsystem/libSystem.B.dylib`
and its 28 transitive dependencies form a Mach-O-valid closure: **29/29 pass
dyld2 checks**. Of the original 34 unresolved non-weak symbols, 25 were fixed
by the concurrent Libsystem work (libcorecrypto SRCS omissions,
`$UNIX2003`/`$NOCANCEL` aliases, `_mach_msg_priority_*_inline` exports,
`_ml_fatal_trap` definition, and the `libsystem_pthread` `VARIANT_STATIC`
guard). The remaining **9** are only in code paths `/bin/echo` does not
exercise.

The incremental serial runner captured **51,167 bytes (796 lines)** from
`work/dyn_repo_closure_20261001.img` (manifest
`/tmp/manifest_repo_closure.json`). The full 29-node closure mapped and bound
with **0 unbound slots**; dyld is fully working. PID 1 then exited with exit
reason namespace 2, subcode `0x4` (SIGILL). RIP `0x000000010cab83fa` maps to
`libsystem_pthread.dylib` offset `0x53fa`, inside `___pthread_init`. Its
disassembly branches to `ud2` when `kr != KERN_SUCCESS`: this is the
`PTHREAD_INTERNAL_CRASH(kr, "host_info() failed")` path after
`host_info(mach_host_self(), HOST_PRIORITY_INFO, &priority_info, &count)`.
The kernel likely does not implement `HOST_PRIORITY_INFO`, causing the MIG
call to fail; a worker is changing libpthread to tolerate that failure.

Evidence: `tools/bootlab/work/KEEP_serial_repo_closure_20261001.log`,
`KEEP_runner_repo_closure_20261001.status`,
`KEEP_verdict_repo_closure_20261001.txt`,
`KEEP_closure_list_repo_closure_20261001.txt`, and
`KEEP_closure_check_repo_closure_20261001.txt`.

### 15.16 Dynamic-userland gate PASS: `/bin/echo` completed (2026-10-01)

The repo-built Libsystem closure now passes the dynamic-userland gate, closing
the boundary left open in 15.13–15.15. The stop marker
`RAVYN-DYNAMIC-USERLAND-OK` appeared at serial line 797, 39.28 s after the
boot command. `init_exec` prints that marker only after `execve` returns;
therefore `/bin/echo`'s `main()` ran and completed. The full 29-node Libsystem
closure mapped and bound successfully. dyld reported:

    DYLD-LOAD-BASE: 0x10978d000
    CHAINPROBE: block FIRED
    0 of 0 bind slots still unbound after the fixup pass

The run had 0 panic/trap lines and QEMU exited 0. Two remaining unresolved
symbols reported from `libobjc.dylib`—`___libunwind_Registers_x86_64_jumpto`
and `___unw_getcontext`—are non-blocking: they are lazy-bound and used only
for DWARF unwinding, which `/bin/echo` did not execute.

Seven blockers were fixed in sequence: dyld rejecting libSystem (stage the
repo-built closure rather than Apple shared-cache extractions); libpthread
`host_info` crash (tolerate failure in `pthread.c`); libc clock-service abort
(tolerate `host_get_clock_service` and `semaphore_create` failures in
`nanosleep.c`); missing libobjc `task_restartable_ranges_register` (generate
the MIG client stub in libsystem_kernel); missing libSystem
`___cxa_guard_acquire` (add `cxa_guard.c` to libsystem_c); missing
`___libcxx_exp_memrsc_init` (compile the real LLVM
`experimental/memory_resource.cpp`); and missing unwind symbols (compile the
real `UnwindRegistersSave.S` and `UnwindRegistersRestore.S` from libunwind).
No assembly was hand-written. The only file modified was
`Libraries/Libsystem/Makefile` (81 insertions, 3 deletions, purely additive).

Evidence: `work/KEEP_serial_repo_closure7_20261001.log` (54,413 bytes),
`work/KEEP_runner_repo_closure7_20261001.status`, and
`work/KEEP_closure_check_repo_closure7_20261001.txt`.
### 15.17 Dynamic shell PASS: `/bin/sh` reaches an interactive prompt (2026-10-01)

Building on 15.16, the first dynamic shell reached a terminal prompt on
ravynOS. The `# ` prompt appeared at serial line 824, the final line of the
824-line log, 39.12 s after the boot command. This proves startup to the prompt
only; the harness sends no serial input, so the read/eval/print loop is not
yet proven end-to-end.

The dynamic `sh_dyn` is 177,416 bytes: FreeBSD ash (`dash`) linked against
`libSystem.B.dylib` and `libedit.dylib`. It is `MH_EXECUTE` with `LC_MAIN`
(not `LC_UNIXTHREAD` or `MH_DYLINKER`) and exactly two `LC_LOAD_DYLIB`
commands: `/usr/lib/libSystem.B.dylib` and `/usr/lib/libedit.dylib`.
`init_shell` is a static PID 1 binary (8,456 bytes): it opens
`/dev/console`, duplicates it to fds 0/1/2, calls `setsid` and `TIOCSCTTY`,
then execs `/bin/sh` with `{"sh", "-i"}` and environment
`PATH=/bin:/usr/bin`, `TERM=dumb`, `HOME=/`.

dyld loaded successfully:

    DYLD-LOAD-BASE: 0x11286c000
    CHAINPROBE: block FIRED
    0 of 0 bind slots still unbound

There were 0 panic/trap lines and QEMU exited 0. `closure_check` reported 39
staged entries, 34 Mach-O nodes, 0 unstaged dependencies, and 30/30 dylibs
passing dyld2 validation. The only findings were the two pre-existing,
non-blocking libobjc unwind symbols noted in 15.16.

Build: `libedit.dylib` (247,072 bytes) was built from
`BSD/lib/libedit/` after dropping `-lncurses` (a 0-byte stub) and adding
`-L${RAVYN_SDKROOT}/usr/lib -lSystem` to its Makefile. The 28 FreeBSD ash
objects from `BSD/bin/sh/` were compiled with `-fPIC` and linked using
`xcrun clang -nostdlib -nostdlibinc -nodefaultlibs -Wl,-no_uuid -Wl,-e,_main
-L$SDK/usr/lib -lSystem -ledit`. No `crt1.o` was needed: `LC_MAIN` makes
dyld call `main` directly. `/tmp/manifest_dynsh.json` stages `sh_dyn` as
`bin/sh`, `libedit.dylib` as `usr/lib/libedit.dylib`, and `init_shell` as
`sbin/launchd`.

Evidence: `work/KEEP_serial_dynsh_20261001.log` (56,551 bytes, 824 lines) and
`work/KEEP_runner_dynsh_20261001.status`.
### 15.18 Dynamic core utilities PASS: six binaries built, linked, and staged (2026-10-01)

Building on 15.17, six FreeBSD userland utilities from `BSD/bin/`—`ls`, `cat`,
`echo`, `mkdir`, `rm`, and `test`—were compiled with `-fPIC` and linked as
`LC_MAIN` dylib executables against `libSystem.B.dylib`. Each has exactly one
`LC_LOAD_DYLIB` (`/usr/lib/libSystem.B.dylib`) and `LC_MAIN` (not
`LC_UNIXTHREAD`). Sizes: `ls` 39,816 B, `cat` 14,784 B, `echo` 8,616 B,
`mkdir` 9,256 B, `rm` 15,680 B, `test` 13,968 B. The manifest
`/tmp/manifest_dynsh2.json` stages them at `bin/{ls,cat,echo,mkdir,rm,test}`.

`closure_check` reported 38 nodes, 0 unstaged dependencies, and 30/30 dylibs
passing; the only findings were the two pre-existing libobjc unwind symbols,
non-blocking as described in 15.16. `mkimage` processed 44 files and 57 tree
entries; verification passed. Boot reached the `# ` prompt at serial line 824,
41.94 s after the boot command, with 0 panic/trap lines; QEMU exited 0. This
verifies the utilities are built, linked, and staged, **not that they run**:
`--stop-marker '# '` stops at the shell prompt, and PID 1 only execs `/bin/sh`.
Runtime proof requires a follow-up boot sending commands over serial.

Compile command pattern:

    xcrun clang -c -arch x86_64 -isysroot $SDK -mmacos-version-min=15.0 -fno-builtin -std=gnu11 -fPIC -D__unused= -Wall -Wno-unused-parameter -isystem $SDK/usr/include -isystem BSD/bin/<util> -o /tmp/dynutil_build/obj/<util>_<src>.o BSD/bin/<util>/<src>.c

Link command pattern:

    xcrun clang -nostdlib -nostdlibinc -nodefaultlibs -Wl,-no_uuid -Wl,-e,_main -arch x86_64 -L$SDK/usr/lib -lSystem -o work/<u>_dyn <objs>

`cp` and `mv` remain blocked by missing FreeBSD macros (`AT_RESOLVE_BENEATH`,
`O_RESOLVE_BENEATH`, `_PC_ACL_NFS4`, `_PC_ACL_EXTENDED`, `_PC_TYPE_NFS4`,
`_PC_TIMESPEC`, `_PC_UF`, `_PATH_CP`, `_PATH_RM`, `_PATH_RSH`, `_PATH_DUM`,
`_PATH_RARCHIVE`) and unimplemented `acl_is_trivial_np`, `chflagsat`, and
`copy_file_range`.

The dynamic shell work is covered by commit `03da2e863b` (21 files, 3,298
insertions). Evidence: `work/KEEP_serial_dynsh2_20261001.log` (56,553 bytes,
824 lines), `work/KEEP_runner_dynsh2_20261001.status`,
`work/KEEP_manifest_dynsh2.json`, and
`work/KEEP_dynutils_20261001_build_closure.txt`.
### 15.19 Runtime proof: dynamic userland executes commands (2026-10-01)

The BUILD/STAGE gate in 15.18 is now closed by interactive runtime proof. A
modified copy of the incremental harness at
`work/KEEP_harness_runtimeproof_boot_20261001.py` left protected
`tools/bootlab/boot.py` untouched. It preserves incremental flushed logging
and copies fresh `assets/vars.fd` each run; stale vars can cause an unrelated
UEFI handoff `#UD` before kernel output. Its data-driven schedule supports
marker/send/timeout steps, CR termination, delays, quiescence, and traces
recording the matched prompt's byte offset. Marker searches advance, so each
step waits for the next prompt. Existing bidirectional Unix serial transport
on COM1 required no new QEMU plumbing. CR is the line terminator: TTY ICRNL
maps it to NL, and ECHO returns typed bytes to serial.

Run2 is the main evidence: 14/14 steps, zero strict panic/trap hits. Commands
proved echo, `ls /`, `ls /bin`, `cat /hello.txt`, test true/false and status
propagation, `&&`/`||`, mkdir, removal, redirection, and `ls /bin | cat`.
The pipeline emitted two DYLD-LOAD-BASE blocks, proving two live dynamic
processes connected by a pipe; its one-entry-per-line output also reflects
`ls`'s non-tty behavior. Run2 had 13/13 dynamic launches and run3 10/10; each
emitted the load-base and chain-probe markers and reported zero unbound slots.
`/hello.txt` and `/tmp` were created by command redirection before use; they
were not initially on the image. Run3 also tested `exit`: PID 1 exiting
correctly panicked the kernel, so main runs omit exit and quiesce. This is a
test artifact, not a userland defect. Its core dump failed because `/cores`
does not exist.

See 15.20 for the source-grounded `rm` and MIG findings, including the
source-derived time API impact.

Operational notes: the image persists read-write across runs and is no longer
pristine; it now contains `/hello.txt`, `/rp3.txt`, `/tmp/dir1`, `/tmp/f1`,
and `/tmp/rt3`. Rebuild it for a clean tree. Existing id=206/id=3418 messages
and `vm_map_get_range` spam precede commands and are non-panicking. In the
recv-driven harness, deadline checks must run on both received-data and
socket-timeout/idle paths; otherwise an idle shell can prevent self-termination.

Evidence: `work/KEEP_serial_runtimeproof_run1_20261001.log`,
`KEEP_serial_runtimeproof_run2_20261001.log`,
`KEEP_serial_runtimeproof_run3_20261001.log`, runner status and trace files,
the preserved harness and schedules, and
`KEEP_verdict_runtimeproof_20261001.txt`. This records the completed proof; no
new QEMU run was made for this documentation change.

### 15.20 Runtime findings: rm semantics and missing MIG dispatch

The `rm` behavior and MIG gap above are grounded in source. `rm.c` only sets
its directory-removal flag for `-d`; its man page documents the historical
deviation from POSIX, and the available rmdir path reaches the msdosfs vnode
operation. For MIG, the absent hash entries cause the bogus-message log and
`MIG_BAD_ID` reply despite existing routines and subsystem entries; the
insertion code deliberately skips NULL kstubs. The observed boot banner
(`mig_table_max_displ = 2 mach_kobj_count = 241`) is consistent with this
direct-index lookup behavior. [INFERENCE] No cause for the NULL kstubs was
established; differing objroot timestamps do not establish booted-kernel
provenance.

Keep the scope distinction: runtime evidence establishes the dispatch
failures; the time API blast radius is source-derived, not runtime-tested.
`clock_gettime()` and mach timebase/absolute-time use other calls, while
`nanosleep()` fails through the null host clock-service port. The kernel
implementation is protected/out of scope.
### 15.21 `cp` and `mv`: final utility gaps closed (2026-10-01)

Building on 15.18 and the runtime harness in 15.19, `cp` and `mv` now build as
`LC_MAIN` dylib executables and have both been proven to execute. The missing
pieces were genuine Libsystem gaps, not defects in the utilities. This closes
the last two requested utilities; 15.19/15.20 describe the harness and related
runtime findings.

Three real Libsystem functions were added. `copy_file_range` is emulated with
`SYS_pread`/`SYS_pwrite`; there is no kernel syscall by that name
(`bsd/kern/syscalls.master` has zero matches), so no syscall number was
invented. It preserves the NULL-versus-explicit offset contract on every exit,
returns a short count at EOF, propagates read `EINTR`, drains short writes,
and rejects nonzero flags with `EINVAL`. `chflagsat` uses
`SYS_setattrlistat` (524), whose kernel path resolves `dirfd` through
`nameiat()`; errors, including `ENOTSUP` for unsupported vnode flags,
propagate. `acl_is_trivial_np` walks ACL entries and computes POSIX.1e
triviality rather than hardcoding it. ravynOS has no ACL support, and the
utility's `_PC_ACL_*` probes return `ENOTSUP`, so `cp`/`mv` do not reach it.

The macro decision preserves enforcement rather than defining unsupported
features to zero: `AT_RESOLVE_BENEATH` maps to `AT_SYMLINK_NOFOLLOW_ANY` and
`O_RESOLVE_BENEATH` to `O_NOFOLLOW_ANY`. Kernel namei rejects symlinks under
these flags, including symlinks that would not escape the starting directory;
this is stricter than FreeBSD's resolve-beneath semantics, in the safer
direction. Other compatibility aliases are `st_atim`/`st_mtim` to
`st_atimespec`/`st_mtimespec` (same layout) and `UF_ARCHIVE` to the reserved,
unimplemented `0x00000010` bit. Since `sys/stat.h` is generated from kernel
headers, these aliases are in editable `unistd.h`. Header changes also cover
`fcntl.h`, `paths.h`, `sys/acl.h`, and `fts.h`; only `_PATH_CP` and `_PATH_RM`
were referenced among the listed path macros. The `fts_open` comparator
prototype now matches FreeBSD's `const FTSENT * const *`; its unprototyped
`fts_compar` field means this does not change generated call code. The sole
in-repo caller was updated, and both SDK dylibs binding `_fts_open$INODE64`
were rebuilt.

`mv` exposed a fourth gap: it references `vfork()` only to exec `cp` or `rm`,
but the kernel's `CONFIG_VFORK`-guarded syscall slot is a null placeholder and
no kernel implementation exists. `Libraries/Libsystem/libsystem_c/sys/vfork.c`
therefore supplies a fork-based fallback by calling `__fork()`. This is not
real `vfork`: it provides neither address-space sharing nor an exec/`_exit`
restriction. Ordinary copy-on-write isolation avoids the classic shared-state
hazard; correctness relies on fork isolation and caller discipline. The cost
is a page-table copy. Calling `__fork()` avoids the pthread atfork callbacks
that `fork()` would run, unnecessary overhead for this exec trampoline.

`closure_check` reported 38 nodes, dependency edges increasing from 150 to
175, four additional exported symbols (10,761 to 10,765), no unstaged
dependencies, no dangling `N_INDR`, 30/30 dylibs passing, and no weak
unresolved symbols. The only unresolved non-weak symbols remain the two
pre-existing libobjc unwind symbols. `nm` confirmed all four additions as
defined `T` symbols in `libsystem_c.dylib`, and `___fork` as `T` in
`libsystem_kernel.dylib`. `mkimage` verified 46 files with matching content
hashes.

Runtime proof used a fresh image path and the serial-input harness described
in 15.19. It created `/d.txt` containing `second-line`, copied it to `/c.txt`,
and `cat /c.txt` returned `second-line`. It then renamed `/c.txt` to `/a.txt`;
`ls -l /` showed `/a.txt` at 12 bytes and `/c.txt` absent. `/bin` listed
`cat cp echo ls mkdir mv rm sh test`. The strict panic scan was clean; the
only “panic” strings were the benign `panic_init` banner noted in 15.19.
`/tmp` is absent on this FAT32 volume, so the successful commands used
root-level paths. No new QEMU run was made for this documentation change.

Evidence: `work/KEEP_serial_cpmv_runtime_20261001.log`,
`KEEP_verdict_cpmv_runtime_20261001.txt`,
`KEEP_closure_check_cpmv_20261001.txt`,
`KEEP_img_digests_cpmv_20261001.txt`, `KEEP_mkimage_cpmv_20261001.log`,
`KEEP_schedule_cpmv_runtime_20261001.json`,
`KEEP_bootrun_cpmv_runtime_20261001.log`,
`KEEP_status_cpmv_runtime_20261001.txt`, `KEEP_trace_cpmv_runtime_20261001.log`,
and `work/cp_dyn`, `work/mv_dyn`.
