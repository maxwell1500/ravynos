# GUI bring-up session — findings

Status as of 2026-10-05. Recorded so the next session does not have to
re-derive them.

## Tracking

These findings will be mirrored to GitHub issues once issues are enabled on
`maxwell1500/ravynos`. **This file is the source of truth until then.** No
issue numbers are referenced below because none exist yet.

---

## 1. WindowServer never reaches `main`

WindowServer crashes with `EXC_BAD_ACCESS` — exception type 10, subcode 11 —
at a **constant fault address `0x00006c2f63746540`**.

That fault address is byte-identical across five consecutive images
(`boot_gui23` … `boot_gui27`), and the black framebuffer reproduces across 18
images in total.

### The fault does not depend on how far loading got

This is the most useful measurement taken. Load depth varied enormously while
the fault address did not move:

| run | images loaded | fault |
|---|---|---|
| minimal | 1 | `0x00006c2f63746540` |
| framework-heavy | 265 | `0x00006c2f63746540` |

A 265× change in load depth with a byte-identical fault means the fault is
**not** in code reached after some particular number of mappings. Either it is
at a fixed address reached on the first pass regardless of load depth, or it
is a fixed data/stack location rather than a code address. That distinction
matters: it rules out "it dies late, once enough of AppKit is mapped" as an
explanation.

### Two live candidates

1. **dyld `ImageLoaderMachO.cpp:725`, the `fMachOData` validity check** — the
   header/section validity check applied to a mapped image.
2. **Foundation `+load` / ObjC registration** — class registration touching a
   class cluster before that cluster is realised.

### The `:725` guard was added, then reverted

A validity check was written at `ImageLoaderMachO.cpp:725` to catch this. It
**falsely rejected `/sbin/launchd`** and panicked initproc, because its
segment-0 assumption does not hold for every legitimate image:

```
load_init_program: attempting to load /sbin/launchd
dyld: malformed mach-o image: unexpected header address 0x10fb19000 after mapping

pid 1 exited -- exit reason namespace 6 subcode 0x9, description malformed mach-o image: unexpected header address 0x10fb19000 after mapping
coredump (launchd, pid 1): writing core to /cores/core.1
coredump (launchd, pid 1): failed to open core dump file /cores/core.1: error 2
coredump (launchd, pid 1): core dump failed: error 2

Failed to generate core file for pid: 1: error 2, took 0.002 seconds
Debugger called: <panic>

panic(cpu 0 caller 0xffffff8000ac4f49):  initproc failed to start -- exit reason namespace 6 subcode 0x9 description: malformed mach-o image: unexpected header address 0x10fb19000 after mapping
```

The guard is reverted. Note the rejected address `0x10fb19000` is **not** the
WindowServer fault `0x00006c2f63746540`, so `:725` may not even be the right
site. The revert is not a fix; it restored the previous behaviour.

### Evidence that dyld is silent

```
$ grep -c "dyld:" g27_serial.log
0
```

Zero. The instrumented dyld (`DYLD-IMAGE-LOADING:`, `DYLD-IMAGE:`,
`DYLD-LOAD-BASE:`, `DYLD-ALL-IMAGE-INFO:`) emitted nothing on the last run,
because that run died before reaching the code path that prints them.

### Current blocking failure (boot_gui27)

`boot_gui27` does not reach the WindowServer fault at all. It panics earlier,
at pid 1:

```
bsd_init: bsd_do_post - doneload_init_program: attempting to load /usr/appleinternal/sbin/launchd.development
load_init_program: attempting to load /sbin/launchd
dyld: malformed mach-o image: unexpected header address 0x10fb19000 after mapping
```

The kernel itself initialises fully (`bsd_init: done`, `Serial keyboard
started`, `VM Swap Subsystem is ON`, root mounted from `disk0s1`) and then
dies the instant it execs `/sbin/launchd`.

---

## 2. launchctl (pid 2) dies mid-submit

`launchctl` dies **inside `load_job()`**, between printing the job name and
printing the verdict, so the verdict never appears on the console. It takes
`EXC_BAD_ACCESS` with a fault roughly 8.5 MB above its own RIP.

The commit `6beda5d245` added the missing `fflush(stdout)` after the verdict
branches, because stdout is block-buffered when it is not a tty and the
verdict was being discarded whenever launchctl exited before the stream
flushed. That fix is real and is present in the shipped binary — three
`callq _fflush` sites are visible under `otool -tvV`, the second of them
immediately after the `_load_job` compare and both verdict `printf`s.

**Even with the flush, the verdict has still never once appeared.** So the
missing `fflush` was masking a deeper problem rather than causing it: the
process is dying before it can print anything.

The submit path itself is proven to work end to end. launchd forks WindowServer
via `core.c:7215` → `job_dispatch` → `job_start` → `runtime_fork`, which is
why a WindowServer process exists at all despite never reaching `main`.

---

## 3. No crash reporter: `EXC_CORPSE_NOTIFY` has no consumer

This is the structural reason the above is hard to see. `realhost.exc_actions[i].port`
is `IP_NULL` as set by `ipc_init`, and **nothing installs a host exception
handler**. Every corpse notification therefore fails with `KERN_FAILURE` (5).

The failing path is visible in the log as:

```
Failed to send exception EXC_CORPSE_NOTIFY. error code: %d for pid %d
```

Consequence: every crash on ravynOS is silent **by construction**. There is no
crash reporter to add — the receiving end does not exist.

### Partial mitigation added

The kernel now emits its own dump at the corpse site rather than relying on a
consumer. The format strings, confirmed present in the shipped kernel payload
(`strings` on `System/Library/Kernels/kernel.development`):

```
CORPSE: pid %d etype %d subcode %d code %d/%d crashed_tid %llu name %s
CORPSE:   tid %d rip 0x%016llx rsp 0x%016llx rbp 0x%016llx fault 0x%016llx
```

The header carries the process name; the per-thread line carries the fault
address taken from `ss->cr2`. This is what made the constant-fault-address
observation in §1 possible at all — before it, the crash produced no output at
all.

---

## 4. The boot harness wastes ~13 of every ~20 minute cycle

The boot reaches its end state in roughly 60 seconds. The harness then keeps
running to 800 seconds and emits six screendumps:

```
BOOT SENT
DUMP 90
DUMP 200
DUMP 350
DUMP 500
DUMP 650
DUMP 800
END bytes=32129
DONE
```

Five of those six dumps report nothing new, because the outcome was already
settled at 90. Roughly 13 minutes per cycle is spent confirming what was
already known.

Two changes proposed:

- **Cut the window to 240s, dumping at 60s and 240s.** Two data points is
  enough to distinguish "reached the GUI" from "panicked early", which is the
  only distinction the dumps are actually used for.
- **Print a one-line verdict on harness exit.** A session timeout currently
  buries the finding: in the `boot_gui27` run the harness was terminated on
  signal 15 and `/tmp/g27.out` contains no statement of what the boot did,
  only the timestamps. Anyone picking up the log has to re-read 563 lines of
  serial output to learn that the machine panicked at pid 1.

---

## 5. Four instruments that deceived their own instrumentation

Each of these was a diagnostic that changed what it was measuring. Each was
caught by a negative control rather than by inspection, and each is a reason
to distrust a clean result from the same instrument.

**`EXC_CORPSE_NOTIFY` with no consumer.** The mechanism looks like a working
crash-reporting path and reports nothing, so the system reads as "no crash
happened" rather than "crash reporting is not wired up".

**A missing `fflush` swallowing a verdict that existed in code.** The
`ok` / `failed: <errno>` diagnostic was present and correct in the source the
whole time; stdio buffering ate it. Reading the source said the code was fine.

**`_simple_dprintf` consuming dyld's bootstrap bump allocator.** The diagnostic
changed load depth from 1 to 265 images with the frameworks byte-identical.
The instrument perturbed the thing being measured — the loader's own memory
discipline — so its output could not be trusted as a description of the
uninstrumented loader. Replaced with a stack buffer and a direct `write(2)`,
confirmed allocation-free: `_ravyn_emit` allocates a `0x4a0`-byte stack frame
and its body ends `callq _write` / `retq`, with zero `_simple_salloc` references.

**A pre-load `write(2)` on that same path.** The emit-before-load variant was
itself a behaviour change on the loader's hot path.

The general rule this session earned: **a diagnostic that changes what it
measures must be treated as suspect until a negative control demonstrates
otherwise.** In every case above it was the control — deliberately breaking the
input and watching the output change — that proved the instrument was live,
and in the `_simple_salloc` case it was also the control that revealed the
instrument was lying.

---

## Build state at the time of writing

| component | sha256 | notes |
|---|---|---|
| `work/stripped_kernel.development` | `080786ed1174337ab24cd10e3b3b1d6ed51d524cc5bc82baaa9cc68fc73b8209` | carries the `CORPSE:` dump |
| `work/launchctl_dyn` | `90a074a755580f72453770a653dc9206838c816776c7c2649e25f65f2767fe22` | carries the verdict `fflush` |
| Foundation (SDK-staged) | `493f93982f4fd81e8d1877ab952be284ac91c291a3b0b0844461484d5cbcbe50` | `+[NSObject alloc]` → `+allocWithZone:` |
| `work/com.ravynos.WindowServer.json` | `ecc779b20b320b7926cdf10149639816e7c962908f10c2d023122b81c024892a` | stdout+stderr → `/dev/console` |
| `work/boot_gui27.img` | `0b7bc0345a701ed3fa2bb07be44dd2c9332bd9628800fea493f97e53cbdfc7cc` | 252 files / 339 tree entries |

Images `boot_gui18` … `boot_gui27` all carry 252 files and 339 tree entries.
`boot_gui27` was the last built; it panics at pid 1 as described in §1.