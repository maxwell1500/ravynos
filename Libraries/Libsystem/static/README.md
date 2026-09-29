# ravynOS static userspace linking

A **static** ravynOS userspace binary is a `MH_EXECUTE` Mach-O with **no
`LC_LOAD_DYLIB`** and **no undefined symbols**. dyld is not involved at
any point: no dynamic loader, no shared cache, no `DYLD_*` environment,
no `LD_LIBRARY_PATH`. Everything it needs is inside the file.

This directory holds the part of that which is not a Libsystem archive:
the residue stubs, and the criteria that decide what may be stubbed.

The link itself is driven by `tools/bootlab/link-static.sh`. The
pthread archive it consumes is built by
`Libraries/Libsystem/libsystem_pthread/static/Makefile`.

## Why this exists

ravynOS Libsystem builds as dylibs, and the dynamic loader path has open
bugs that are **not** on the critical path for getting an interactive
terminal. A static link sidesteps dyld completely: if the binary has no
`LC_LOAD_DYLIB`, there is nothing for dyld to fail to bind.

## How to link one

```sh
tools/bootlab/link-static.sh -o /tmp/hello hello.c
```

The script builds the static-variant archives if they are missing, then
links. It verifies the result and fails loudly if any of these is untrue:

* zero `LC_LOAD_DYLIB`
* zero undefined symbols (`MH_NOUNDEFS` set in the Mach header flags)
* zero duplicate-symbol errors

## Entry point

There is **no `crt1.o` anywhere in the SDK**:

```sh
find "$RAVYN_SDKROOT" -name 'crt*.o'    # (empty)
```

so a normal `clang main.c` cannot work, and does not need to. A static
ravynOS program supplies its own entry point and links with `-e _start`,
the same shape `tools/bootlab/build_init.sh` already uses for PID 1.

Because there is no `crt1.o`, there is also no `__libc_init`, and
therefore no `pthread_init`. This is not a workaround to paper over later;
it is a real constraint, and it is the reason the weak-symbol rule below
is not optional. See "The malloc trap" under `stubs.c` criteria.

## The archives

| Archive | Built by | Supplies |
|---|---|---|
| `libc.a` | `libsystem_c/libc_static` | `printf`, `puts`, `fork`, `exit`, `sigaction`, `tcgetattr`, `tcsetattr`, `isatty` |
| `libsyscalls.a` | `libsystem_kernel` | `read`, `write`, `close`, `dup2`, `getpid`, `syscall` |
| `libsystem_kernel.a` | `libsystem_kernel` | `open`, `execve`, `ioctl`, `__error` |
| `libmach.a` | `libsystem_kernel` | `mach_msg` and the mach RPCs |
| `libsystem_malloc.a` | `libsystem_malloc` | `malloc`, `free` |
| `libsystem_platform.a` | `libsystem_platform/static` | `strlen`, `memcpy`, `memset`, `bzero`, … |
| `libpthread_static.a` | `libsystem_pthread/static` | `pthread_*` |
| `libsystem_blocks.a` | `libsystem_blocks` | `Block_copy`, `Block_release` |
| `libCrashReporterClient.a` | shipped in the SDK | the crash-reporter stub |

## Criteria for a legitimate static-link stub

A residue stub in `stubs.c` is legitimate **if and only if the value it
returns is the value the real implementation would return**, for a
statically-linked, single-threaded, dyld-free Mach-O executable on
ravynOS.

It is **not** legitimate to return a value that merely makes the link
succeed. That converts a visible link failure into an invisible runtime
bug, which is strictly worse than not linking at all.

In practice that means each stub is one of:

1. **A value that is true.** `_dyld_get_image_slide()` returns 0 because
   a static binary is never slid. `dlsym()` returns NULL because there
   is no dynamic symbol table to search. `os_log_pack_*()` returns a
   zero-length record because logging is compiled out. These are not
   placeholders; they are the correct answers.

2. **A transcribed real implementation.** The five
   `mach_msg_priority_*_inline` functions are copied from
   `Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/mach/message.h` — the same
   constants, the same bit layout, the same arithmetic. They are not
   approximations.

3. **An error, with the unreachability argued in the comment.** Where the
   honest answer is "this cannot be reached in a static single-threaded
   program, and if it were the program is already broken", the function
   returns an *error*. `mach_msg2()` returns -1, never 0, precisely so
   that if the reasoning is ever wrong the program fails at the point of
   the mistake instead of acting on a fabricated success.

### Rejecting a candidate stub

Before adding a symbol, ask:

* What does the real function do?
* Does that code path exist in a static, single-threaded, dyld-free
  executable?
* If not, is returning an *error* the honest response, and does the
  comment say so?
* If the real function is pure computation, is the computation here, or
  is this a guess wearing a comment?

A stub that fails this is a gap that should be fixed in Libsystem, not
papered over here. Do not add one.

## The malloc trap

`libsystem_pthread/pthread.c` defines its own `malloc` and `free` that
forward to `_pthread_malloc` / `_pthread_free`, and it defines `memset`,
`bzero` and `memcpy` that forward to the libplatform primitives. It does
this so that dyld and launchd can link pthread **without** Libc.

A static userspace binary links Libc, which also defines all five, so
five duplicate symbols arise. Resolving them is a two-part change, and
**both parts matter**:

* `malloc` and `free` are removed by the existing
  `#if !defined(VARIANT_STATIC)` guard at `pthread.c:1700`.
* `memset`, `bzero` and `memcpy` are marked
  `__attribute__((weak))` via `PTHREAD_LIBC_SHIM`, so the real
  implementations in `libsystem_platform` win.

The weak marking must **not** be replaced with `-Wl,-U` or
`-allow_multiple_definitions`. Those pick a definition by link order, and
the two candidates are not interchangeable: pthread's `malloc` returns
`NULL` until `pthread_init()` has run, and with no `crt1.o` there is no
`__libc_init` to call it. If pthread's won, every `malloc()` in the
program would silently fail. Weak is the only marking that expresses the
actual requirement — *use the real one if it exists*.

## The dynamic build is not affected

`PTHREAD_LIBC_SHIM` expands to nothing unless `VARIANT_STATIC` is
defined, and `VARIANT_STATIC` is defined in exactly one place:
`libsystem_pthread/static/Makefile`, a subdirectory the shared dylib's
own build does not compile.

`libsystem_pthread/dyld/Makefile` also sets `VARIANT_STATIC`, and that is
not a conflict: it pairs it with `VARIANT_DYLD`, which compiles the
shims out entirely (they sit inside `#if !VARIANT_DYLD`). Correct for
dyld, which must not link Libc at all.

## Verifying a build

```sh
otool -hv /tmp/hello | tail -1     # flags column must read NOUNDEFS
otool -l  /tmp/hello | grep -c LC_LOAD_DYLIB   # must be 0
nm -u /tmp/hello                   # must be empty
```
