# bootlab

Reproducible build → disk-image → QEMU-boot pipeline for the ravynOS bringup
kernel (Darwin 24 / xnu-11215 x86_64). Everything the boot test needs lives
here; `work/` is scratch and gitignored. The disk tree is defined by the
manifests — `manifest_cpmv.json` is the default — and `assets/` holds only
non-binary configuration. See "The build gate" for the rules that keep it
that way.

## Quick start

```sh
tools/bootlab/run.sh full      # build kernel + init + image, boot, watch serial
```

Exit test: serial log shows the PID1 banner and `alive tick N` lines with zero
traps/panics. Log: `work/serial_full.log`.

**Current status (2026-10-02).** The kernel's PID 1 zero-RSP double fault is
**fixed**: the handoff now enters `load_init_program` and attempts to exec
`/sbin/launchd`. That binary is real — built from the vendored
`BSD/sXin/launchd` sources by `build_launchd.sh`, `MH_EXECUTE` + `LC_MAIN` +
`DYLDLINK`, one `LC_LOAD_DYLIB` (`/usr/lib/libSystem.B.dylib`) — and staged at
`sbin/launchd` by `manifest_cpmv.json`. PID 1 then dies:

    load_init_program: attempting to load /sbin/launchd
    pid 1 exited -- exit reason namespace 2 subcode 0xb, description none
    panic(cpu 0 caller 0xffffff8000abccb9):  initproc failed to start --
      exit reason namespace 2 subcode 0xb description: none

Read that reason correctly: **namespace 2 is `OS_REASON_SIGNAL`, not
`OS_REASON_DYLD`** (`Kernel/xnu/bsd/sys/reason.h:113` vs `:117`), and **subcode
`0xb` is `11` = `SIGSEGV`** (`Kernel/xnu/bsd/sys/signal.h:99`). So this is a
segfault inside the loader, not a `DYLD_EXIT_REASON_*` code — those live in
`Libraries/dyld/include/mach-o/dyld_priv.h:433-440` and top out at 9, so `0xb`
cannot be one. Symbolizing against the loader at base `0x10ec6b000`, the crash
is `_cerror_nocancel+0x20` = `movq %gs:__framesize(,%rax,8), %rax`, a
`%gs:`-relative load with **GS base still 0** (CR2 = `0x8` = `gs:0 + 8`). It is
reached from the `DYLD-LOAD-BASE` print in `dyldbootstrap::start`, which runs
*before* `rebaseDyld()` installs the TSD base that `%gs` needs — a correct
mechanism in the wrong place, one call earlier than the same defect already
documented at `Libraries/dyld/src/dyldInitialization.cpp:98-119`. Full write-up:
`PROVENANCE-PLAN.md` §5 "Roadmap forward", Phase 3.

```sh
tools/bootlab/run.sh dynamic   # dynamic-userland gate: execve a dylib-linked binary
```

`run.sh full` is **not** a userland gate. It reaches PID 1 and the loader now,
but it does not judge on a dylib-linked `main()` running to completion — it
currently stops in dyld (see "Current status" above). `run.sh dynamic` is the
instrument for that verdict: it stages a static exec-runner as PID 1 which
`execve()`s the dylib-linked `/bin/echo`, and judges on whether that binary
reached `main()`. Wired into `build_all_libsystem.sh` as a **known-blocked
stage** (`dynamic_userland`), so its fault signature appears in the standard
driver run and any change in that signature is visible. Log:
`work/serial_dynamic.log`.

## Steps (each idempotent)

| command | what it does |
|---|---|
| `run.sh build` | `kernel_build.py`: recompiles the boot-critical objects (via committed `templates/*.json` + build-tree `<obj>.o.json` clones), compiles `msdosfs` (`msdosfs_compile.sh`), relinks with the build tree's `.LDFLAGS`, strips → `work/new_kernel.development`, `work/stripped_kernel.development`. Requires one completed full xnu build tree (`RAVYN_BUILD_DIR`, default `/Users/max/Projects/build/DEVELOPMENT_X86_64`). |
| `run.sh init` | `build_init.sh`: static no-libc PID1 (`init/init_static.c`) → `work/init` (banner + busy-spin tick loop). |
| `run.sh mkimage [img]` | Runs `closure_gate.py` on the manifest it is about to build, then `mkimage.py`: builds a 512 MiB FAT32 image. **Default manifest `manifest_cpmv.json`** — pass `--manifest M` to override; the manifest is gated and built as one value, so they cannot diverge. Head (MBR+GPT+BPB+FSInfo+reserved) and tail (backup GPT) are verbatim golden bytes (`assets/template_{head,tail}.bin`), so firmware-visible geometry is bit-identical to the proven golden disk. Kernel payload: newest of `--kernel`, `work/stripped_kernel.development`, `assets/kernel.development`. Verifies by reopening the image and re-hashing every file. Default output `work/boot.img`. See "The build gate" below. |
| `run.sh boot [mode]` | `boot.py`: QEMU q35 + OVMF (`-pflash` code from `/usr/local/share/qemu`, vars freshly copied from `assets/vars.fd` every run — stale vars fault at handoff). Waits for `Shell>`, types the canonical boot.efi command. Modes: `full` (shared CR3), `split` (`-s`), `fallback` (`-s -no_shared_cr3`). |
| `run.sh dynamic` | `run_dynamic_gate.sh`: stages `init/init_exec_dynamic.c` as PID 1 via `manifest_dynamic.json`, boots, and returns 0 = `/bin/echo` reached `main()`, 1 = blocked (dyld/kernel fault, signature printed), 2 = harness problem (kernel never booted). |

Kernel is installed at BOTH `System/Library/KernelCollections/BootKernelExtensions.kc`
and `System/Library/Kernels/kernel.development` (boot.efi with
`kcsuffix=development` loads the KC path).

## The build gate

Every **unprotected** runner that constructs a disk first runs
`python3 closure_gate.py <the same manifest it hands mkimage.py>`, and refuses
to continue on a nonzero exit — `run.sh mkimage`/`full`,
`run_dynamic_gate.sh`, `run_gated_loader.sh`, `run_minxfer.sh`,
`run_applefree.sh`. A bare `python3 mkimage.py --manifest M` bypasses it.
`closure_gate.py` is a thin wrapper around `closure_check.py`, which answers
these questions offline about the bytes that will be staged:

- does every `LC_LOAD_DYLIB` / `LC_REEXPORT_DYLIB` / `LC_LOAD_UPWARD_DYLIB`
  name something the tree stages (unstaged dependencies);
- does every non-weak undefined symbol resolve against the staged closure;
- does every staged dylib pass dyld2's `__LINKEDIT` validation, the check
  behind `malformed mach-o image: dyld chained fixups info underruns
  __LINKEDIT`;
- and, separately, is any staged binary one that came out of the **host Mac's
  dyld shared cache** (`provenance_scan.py`: an `LC_UUID` the host cache also
  records can only have come out of that Apple build).

The provenance verdict **fails closed**: a host without a readable dyld
shared cache is a FAIL, not a pass. There is no quiet mode and no waiver on
this path.

**What is gated, precisely.** The runners gate the **sources** that are about
to be staged — before any image exists. That is where a borrow can still be
*prevented*. Only `run_dynamic_gate.sh --no-build` gates a **finished
image**, because in that mode there is no build step to precede. A normal run
does **not** re-gate the image it just built; that would cost a second full
pass over a 512 MiB image (~60 s), and it is available by hand:

```
python3 closure_gate.py manifest_cpmv.json --image work/boot.img
```

`--image` judges the bytes read back **out of** a built image
(`fat32img.Fat32Img.read_path`) rather than the files the manifest names. It
is the only form of the question that is about the artifact instead of the
build tree, and it is verified to differ: an image with 16 bytes changed in
one `LC_UUID` passes the source check and fails the image check.

**Relocatability preflight.** Before running `closure_check.py`, the gate
lists every manifest entry that resolves **outside** the repository and
names `RAVYN_BUILD_DIR` and its default. **Any** such entry is fatal: the gate
exits 1 with `REFUSED (relocatability preflight)` whether or not the path
exists on this machine, instead of letting `mkimage.py` report a bare
`missing file source`. Existence is not a pass — an out-of-repo path that
happens to be populated on the machine running the gate proves only that
*this* checkout's sibling layout exists, which is exactly how a repo-relative
manifest can look clean here and fail on a fresh checkout. Malformed and
unreadable manifests fail closed too. `manifest_cpmv.json` has none — all 46
of its entries resolve inside the repository.

### What currently passes — all of it

| manifest | gate | why |
|---|---|---|
| `manifest_cpmv.json` | **PASS** | the default. The durable clean closure: 46 explicit relative entries, no glob, no host-extracted binary, **0 absolute paths and 0 entries that leave the repository** — relocation-clean, not merely relative. `libunwind.dylib` and `libcompiler_rt.dylib` are both repo-built by `Libraries/Libsystem/Makefile` targets that link into `${.CURDIR}`; neither is staged out of the sibling `build/` tree. |
| `manifest_dynamic.json` | **PASS** | the same repo-built closure, with `bin/sh` and `bin/echo` repointed at `work/{sh,echo}_dyn` (they were `assets/bin/{sh,echo}`, the latter an Apple product binary) and `usr/lib/libedit.dylib` added, which `sh_dyn` needs. |
| `manifest.json` | **PASS** | was **REFUSED**: it staged `usr/lib/libSystem.B.dylib` and a `glob` over `assets/usr/lib/system/` — 32 host-extracted binaries, 28 dylibs dyld2 rejects, 84 unresolved symbols — and was protected. It was authorized and de-globbed on 2026-10-02, and now names the same explicit closure as the default. |
| `manifest_minxfer.json`, `manifest_applefree.json` | **REFUSED** | per-experiment manifests, not migrated. They still name moved files, so `closure_gate.py manifest_minxfer.json` fails at *stage* time (`missing asset: assets/bin/cat`), not on closure. Use `manifest_cpmv.json`. |

**All three real manifests pass with `HOST-EXTRACTED: 0`**, and so does the tree:

```
$ python3 provenance_scan.py --target assets
HOST-EXTRACTED: 0
NOT-IN-HOST-CACHE: 18
provenance_scan: PASS
```

That is the number P1 moved: it was **34** before. The host binaries are in
`assets-quarantine/`, gitignored, byte-identical, and inventoried — see below.

### No host binaries in `assets/` (P1, 2026-10-02)

**Every Apple binary has been moved out of `assets/` into
`tools/bootlab/assets-quarantine/` — 57 files, nothing deleted.** The
quarantine is gitignored, so quarantining is also de-publishing: these bytes
are in neither the repository nor the push queue.

`assets-quarantine/QUARANTINE_INVENTORY.txt` records, for every file: sha256,
byte size, filetype, `LC_UUID`, `__TEXT` vmaddr, mtime, and a prose identity.
The 17 `dyld.PRE-*` / `dyld.PREV-*` snapshots get an individual entry each,
naming the milestone they encode (BINDBINDGUARD, CHAINPROBE, NOALLOC,
VOUCHERS-FIXED, COMPAT-FIXED, CHKSTK-LOCAL, TRAP-BOUND, PUTC-PROBE,
BASELINE-CLEAN, WALK-BOUNDED, CONTROL-PERTURB, CONTROL-PERTURB2) with the probe
strings actually found in each image, so the identity is checkable rather than
asserted.

| what | count | note |
|---|---|---|
| host-extracted dylibs from `assets/usr/lib/system/` | 31 | plus `dyld.orig`, `libSystem.B.dylib`, `libSystem.B.dylib.orig` = **34 host-extracted** by `LC_UUID` |
| host **disk** product: `assets/bin/{cat,echo,ls}` | 3 | **invisible to the `LC_UUID` test** — see below |
| host frameworks: `CoreFoundation`, `XPCSupport` | 2 | |
| `assets/usr/lib/dyld` | 1 | **not** host-extracted: a superseded build of *our own* dyld, and `MH_DYLIB`, which the kernel rejects as a dylinker |
| dyld debug snapshots | 17 | project-built, archived for their history |
| **total** | **57** | |

**The three `/bin` copies are the interesting ones.** They were byte-for-byte
copies of this host's `/bin/{cat,echo,ls}` — universal `x86_64`+`arm64e`, with
`LC_CODE_SIGNATURE` — and §2's provenance test reported **0** host-extracted
across `assets/bin` and `assets/System`, before and after the quarantine. They
came off the *filesystem*, not out of the shared cache, and the UUID test
cannot see that. Two consequences, both recorded in `PROVENANCE-PLAN.md` §4 P7:
the borrowing rule is now stated by **what a file is**, not only by how it was
obtained, and a future scanner should treat an `arm64e` slice or a present
`LC_CODE_SIGNATURE` as host-origin signals in their own right.

**Not quarantined, deliberately:** `assets/bin/sh` (4,280 B, single-arch,
`LC_UNIXTHREAD`, no `LC_LOAD_DYLIB` — a freestanding static image this
repository built) and 15 of the 46 `assets/usr/lib/system/` dylibs, which are
vendored Apple OSS built from `Libraries/`. Both are recorded as ours in
`assets/.gitignore`.

**One consumer no longer works:** `run_gated_loader.sh` stages into
`assets/usr/lib/dyld`, which no longer exists, so the loader-swap experiment
must be repointed at a repo-built dyld before it is used again. This is
recorded in the inventory.

**Restoring anything** is a plain `mv` back to its former path; nothing in the
clean closure depends on a restore, and `git` tracks none of it.

`run.sh mkimage --manifest M` gates `M` and builds `M`. `run.sh full` takes no
mkimage arguments (`boot.py` then boots `work/boot.img`), so it takes the
manifest from `${RAVYN_MANIFEST:-manifest_cpmv.json}` instead.

**None of this is committed.** `manifest_cpmv.json`, `closure_gate.py` and
`provenance_scan.py` are prepared in the working tree and untracked;
`manifest.json`, `manifest_dynamic.json`, `closure_check.py`, `README.md` and
the runner scripts are modified but unstaged. Committing is your call.

## Acceptable borrowing (the rule, in short)

**Borrowing Apple's _source_ is the project. Borrowing Apple's _built
binaries_ is the defect.** For shared-cache extracts the line between them is
one test: a Mach-O whose `LC_UUID` also appears in the host Mac's dyld shared
cache came out of that Apple build, and cannot have come from this repository.

**That test has a blind spot, and P1 found it.** It cannot see a binary copied
off the running host *disk* rather than out of the shared cache — which is
exactly what `assets/bin/{cat,echo,ls}` were, and every scan reported them as
clean. So the rule is stated by **what a file is**, not only by how it was
obtained: a universal binary with an `arm64e` slice, or any image carrying
`LC_CODE_SIGNATURE`, is Apple's — this repository targets x86_64 and does not
sign.

| Class | Verdict |
|---|---|
| Host **build tools** (`clang`, `ar`, `ld`, `strip`, `llvm-libtool-darwin`, …) | **Acceptable, unavoidable.** `Developer/Default.xctoolchain` is source-only with no built tools. They build; they are never staged. |
| **Vendored Apple open-source** (`Libraries/*`, `BSD/`, `Kernel/xnu`, `Developer/Default.xctoolchain/llvm`) | **The intended path.** Each import records its upstream repo and tag in a `_PROVENANCE` file. |
| Host **headers** | **Mild, case by case.** Currently one transcription, the `__DARWIN_ONLY_*` block in `libsystem_c/include/sys/cdefs.h`. |
| Host Mac **runtime binaries** in a staged image | **Never acceptable.** |

**None of these are in `assets/` any more.** P1 (2026-10-02) moved all 57
affected files to the gitignored `tools/bootlab/assets-quarantine/`, byte for
byte, and recorded every sha256, filetype and historical identity in
`assets-quarantine/QUARANTINE_INVENTORY.txt`. The section above documents it in
full; the short form is that `provenance_scan.py --target assets` returns
**`HOST-EXTRACTED: 0`** where it used to return 34, and that a scan of
`assets-quarantine/` still returns 34 — which is the control showing the
scanner would have found them and is not merely reporting zero.

`assets/` remains a path provenance work reads and stages from; the
quarantine directory is one it does not edit or republish.

What "enforced" means today, precisely: **the policy is enforced by absence.**
It used to be enforced by refusal — the default manifest staged the borrowed
region, so `run.sh full` and `run.sh mkimage` stopped and a clean verdict was
reached only by naming a clean manifest explicitly. That is no longer the
position. `assets/` contains no host binary to refuse, `manifest.json` was
de-globbed, and the default is `manifest_cpmv.json`, which passes. The gate
stays on every runner because it is what protects the next clone and the next
contributor, and because its relocatability preflight still catches a manifest
that reaches outside the repository — a failure mode P1 cannot address.

Relocatability of the clean manifest: `manifest_cpmv.json` uses **explicit
relative references, and all 46 of them resolve inside the repository** —
0 absolute paths, 0 entries that depend on a sibling `build/` tree. The two
entries that used to be the exception now have in-repo producers:

| entry | producer | where the product lands |
|---|---|---|
| `usr/lib/system/libunwind.dylib` | **Repo-built.** `Libraries/Libsystem/Makefile:201` (`libunwind.dylib` target) links it from the tracked `libunwind` sources. | It now links into `${.CURDIR}` — `Libraries/Libsystem/libunwind.dylib` — and is installed to the SDK, so it is an in-repo build product like every other closure member. |
| `usr/lib/system/libcompiler_rt.dylib` | **Repo-built, new target.** `Libraries/Libsystem/Makefile:405` (`libcompiler_rt.dylib: ${COMPILER_RT_OBJS}`) links `-Wl,-force_load` over **170 vendored compiler-rt translation units** (`COMPILER_RT_SOURCES`, the exact x86_64/macOS set derived from upstream's `lib/builtins/CMakeLists.txt`, not a naive glob). | Also `${.CURDIR}` → `Libraries/Libsystem/libcompiler_rt.dylib`, then copied to the SDK. The rebuilt dylib reproduces the previous export trie exactly — **529 names, identical set** — with `LC_ID_DYLIB /usr/lib/system/libcompiler_rt.dylib` at 1.0.0/1.0.0 and 0 `LC_LOAD_DYLIB`. |

Before this, `libcompiler_rt.dylib` had **no producer at all**: `Libraries/Makefile:140-142` only ran `require_real_archive.sh`, which verifies a prebuilt `libclang_rt.osx.a` and fails loudly if absent, and nothing linked the dylib — so the staged binary was an **unrecorded artifact** (LLVM version known, 17.0.6; origin UNKNOWN). It could not simply be dropped either: `libSystem.B.dylib` re-exports it and `liblaunch`, `libsystem_pthread` and `libunwind` all link `-lcompiler_rt`, so the closure was incomplete without it.

**P0 (the portable clean manifest) is closed**: every source entry in all
three manifests resolves inside the repository, so the closure no longer depends
on this machine's layout. The **default boot path is no longer blocked either**:
`run.sh` defaults to `manifest_cpmv.json` and injects it explicitly, so the
gate and `mkimage.py` are handed the same manifest rather than inheriting
`mkimage.py`'s own default.

The full policy, including the exceptions and their exact terms, is
PROVENANCE-PLAN §4 P7.

## Files

- `fat32img.py` — FAT32 reader/writer library (cluster chains, LFN + 8.3
  entries, FSInfo, template-head builder, walk/verify).
- `manifest_cpmv.json` — **the default.** The durable clean closure: 46 explicit
  entries, none under `assets/` except one plist, 0 absolute paths, and 0 entries
  resolving outside the repo — relocation-clean. Builds an image with a passing
  gate. **Untracked** (no commit was made).
- `manifest_dynamic.json` — same tree, but `/sbin/launchd` is the *static*
  exec-runner rather than the real launchd the default manifest stages.
  Selected by `mkimage.py --manifest`.
  Cleaned in P0: the `assets/usr/lib/system/` glob and the host-extracted
  `libSystem.B.dylib` were replaced by the repo-built closure. Repointed in P1:
 `bin/sh` and `bin/echo` are now `work/{sh,echo}_dyn` (they were `assets/bin/…`,
  and `bin/echo` was an Apple product binary), with `usr/lib/libedit.dylib`
  added because `sh_dyn` needs it.
- `manifest.json` — disk tree: files, assets. **Used to** be the default and to
  carry a `glob` over `assets/usr/lib/system/` staging 32 host-extracted
  binaries, which is why it was REFUSED. De-globbed and repointed in P1; it now
  passes and names the same explicit closure as the default.
- `assets-quarantine/QUARANTINE_INVENTORY.txt` — the P1 record: 57 files, each
  with sha256, size, filetype, `LC_UUID`, `__TEXT` vmaddr, mtime and historical
  identity. The directory itself is gitignored.
- `closure_check.py` — offline closure + Mach-O validity checker; carries the
  provenance verdict and can read a built image back (`--image`).
- `provenance_scan.py` — flags Mach-O binaries lifted out of the host's dyld
  shared cache. Fails closed when the cache cannot be read.
- `closure_gate.py` — the one helper every runner calls before building; a
  thin wrapper over `closure_check.py` that propagates its exit status.
- `extract_assets.py` — one-time harvest of userland/boot assets from the
  golden image into `assets/` (already run; rerun only to refresh payloads).
- `kernel_build.py` + `templates/` — incremental kernel recompile/relink.
- `msdosfs_compile.sh` — in-kernel msdosfs objects (`work/msdosfs_objs`).
- `boot.py` — QEMU harness; boot command sent over the serial unix socket.
- `init/init_static.c` + `build_init.sh` — static PID1 proof-of-life binary.
- `init/init_exec_dynamic.c` + `build_init_exec.sh` — static PID1 that
  `execve()`s `/bin/echo`; the dynamic-userland gate's instrument.
- `build_launchd.sh` — builds the **real** `/sbin/launchd` as a dynamic
  `MH_EXECUTE` from the vendored `BSD/sbin/launchd` sources (its `Makefile`'s
  `SRCS` list is the single source of truth; the compile/link lines are ours,
  because the `bsd.prog.mk` target links FreeBSD `libc.a`, not `-lSystem`, and
  its `mig` include path shadows the SDK's `mach/`). Links `-lSystem` only, plus
  the vendored OpenBSM objects, because the SDK ships no `libbsm`/`libauditd`
  at all. This is the PID 1 the default manifest stages.
- `stage_dynamic_libs.sh` — copies the **real** `libobjc.A.dylib` (our objc4
  build product, 1,608,088 B, ~2,100 exports) out of the generated SDK into
  `assets/usr/lib/`, and refuses to proceed if what is staged is a stub. Run
  by `build_all_libsystem.sh` and by the dynamic gate; idempotent.
- `run_dynamic_gate.sh` — the gate itself; verdict read from the serial log
  only after the boot process exits.

## Known-good boot command

```
fs0:\System\Library\CoreServices\boot.efi -v serial=3 debug=0x14e keepsyms=1 \
  slide=0 kcsuffix=development rd=disk0s1 rootdev=disk0s1 npci=0x2000 dart=0 \
  -no_compat_check cpus=1 quiet_boot=1
```

## Gotchas

- EDK2's FAT driver validates LFN checksums (spec byte 13) — a wrong checksum
  makes `ls`/load fail with "File Not Found" even though the bytes are there.
- 8.3 collision suffixes must fit 8 chars (`stem[:8-len(~n)] + ~n`); a 9-char
  stem silently shifts every following directory entry by one byte.
- `startup.nsh` never auto-runs with these OVMF vars; the harness types the
  boot command after `Shell>` appears.
- Dynamic (dyld) binaries need `usr/lib/libobjc.A.dylib` staged, because
  `libsystem_symptoms.dylib` references it. It is now staged from the SDK by
  `stage_dynamic_libs.sh`.

  > **Never stage the 6,856-byte `build_stubs.sh` placeholder. This is the
  > argument for checking EXPORTS rather than SIZE.** The stub *does* define
  > `_objc_msgSend` and `_objc_msgSendSuper2` — as no-ops at `0x540`/`0x550` —
  > while lacking ~2,100 of the real artifact's 2,145 exports. So it is a valid
  > Mach-O, correctly named, at the right path, and 0.4% of the right size:
  > **every size-based check passes it.** Shipping it converts a **loud dyld
  > abort into a silent wrong answer** — the first Objective-C call returns
  > whatever an empty stub returns, with no error anywhere. That is exactly the
  > class `Libraries/check_sdk_stubs.sh` exists to prevent.
  >
  > Real: 1,608,088 B / 2,145 defined symbols. Stub: 6,856 B / 45.
  > `stage_dynamic_libs.sh` checks size, export count *and* `_objc_msgSend`, and
  > **was negative-tested** (a 4,200-byte fake was planted and the gate was
  > confirmed to reject it) — a gate never seen red is the same defect as the
  > derived artifact gate's 19 false reds.
>
> **With `libobjc` staged, the next fault is CoreFoundation, referenced from
> `libxpc.dylib` — and it is inherited, not ours.** Our own
> `Libraries/Libsystem/libxpc` (8 `.c` files) has **0** `CoreFoundation`
> includes and **0** `CF*` symbols, and its `Makefile` links no framework. The
> edge is a non-weak load command in `assets/usr/lib/system/libxpc.dylib`, an
> **Apple shared-cache extract**. `Frameworks/CoreFoundation` source does exist
> in the tree (5.5 MB, 87,013 lines, 44 public headers) and there is no CF
> binary in the SDK, but **do not build it to satisfy a dependency our own
> `libxpc` does not have** — replace the extract with our `libxpc.dylib` (whose
> default target is already `all: libxpc.dylib`) and the edge disappears.
> Full assessment: `Libraries/Libsystem/REMEDIATION_PLAN.md`, section
> "2026-09-27".
- **The `/etc/rc` path is currently DEAD.** Until 2026-09-26 a "MINI-SHELL"
  PID 1 ran `/etc/rc`, which is what executed `/bin/echo` and `/bin/cat`. That
  program's source is **not in the tree** — only its serial output survives, in
  gitignored `work/`, so it is not recoverable. `run.sh dynamic` replaces the
  capability deliberately, from source; do not assume `/etc/rc` is exercised.
- **UNEXPLAINED: the UEFI `#UD` at handoff is not always a stale pflash.**
  `boot.py` re-copies `assets/vars.fd` on every run, yet on 2026-09-27 a boot
  still died before the kernel with
  `!!!! X64 Exception Type - 06(#UD - Invalid Opcode) !!!!`,
  `RIP - 00000000000B0000`, `!!!! Can't find image information. !!!!`
  (efiboot, `#[EB|MMD]` memory-map dump, no `bsd_init`, no PID 1 banner). A
  re-run with an identical image booted normally. So the "always copy fresh
  vars" workaround is **necessary but not sufficient**, and this occurrence is
  recorded as unexplained rather than filed under the known cause. The dynamic
  gate treats a missing PID 1 banner as a harness fault (exit 2), never as a
  kernel verdict.
- `boot.py`'s exit code is 0 only if the log contains `alive tick`; the dynamic
  gate's PID 1 execs instead of ticking, so that code is meaningless there and
  the gate judges on the log.
- Commits are local-only; never push.


## Cost of the dynamic gate, and the baseline of record

- The gate costs **205 s–358 s across two full runs — 40–55% of the loop**,
  and the spread is build caching, not variance in the gate. It is the only
  stage that boots anything, and the only one that can catch a dyld
  regression. `BOOTLAB_SKIP_DYNAMIC=1` keeps it out of the fast path; a
  driver run without it is **not** a baseline, for the same reason a `--quick`
  run is not (it skips stages, one of which does not build).
  Measured: run 1 = 358 s of 654 s; run 2 (serial, clean tree) = 205 s of 511 s.
  The *signature* is stable across both runs; only the panic **caller address**
  moves (`0xffffff80184cc739` / `0xffffff8018ecc739` / `0xffffff80108cc739`),
  which is kernel slide, not a change in fault. Compare the signature, never
  the address.
- **Baseline of record (full run, nothing else touching the tree):**

      stages passed 23   known-blocked 3   skipped 0   UNEXPECTED failures 2
      unexpected: libdispatch, libsystem_darwin
      check_sdk_stubs.sh  PASS
      RESULT: FAIL

  The two unexpected failures are **pre-existing and recorded**, not regressions
  — see "Neither failure is a regression from this session's work" in
  `Libraries/Libsystem/REMEDIATION_PLAN.md`. The delta from the previous
  baseline (22/2/0/2) is exactly `+1 passed` (`stage_dynamic_libs`) and
  `+1 known-blocked` (`dynamic_userland`).
