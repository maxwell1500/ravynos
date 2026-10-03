# ravynOS provenance — where every binary comes from, and the plan to finish the job

Written 2026-10-02 against `darwin` @ `03da2e863b`, host macOS 26.6.2 x86_64.
Companion to `BOOT-PLAN.md`, which records how the system was made to boot.
This document answers a narrower question: **when ravynOS links, stages, or
boots something, is that something ours, Apple's open-source Darwin, or lifted
out of the host Mac?**

**This is a LIVING DOCUMENT.** It began as a one-time audit and is now the
standing provenance record of the project. Reading order: §2 is how provenance
is measured, §3 is what each region of the tree turned out to be, §4 is the
state of every phase with its evidence, §5 (**Living Document & Architectural
Lifecycle**) is the state machine, the prohibition on host runtime binaries,
the automated gates, and the roadmap forward, and §8 is the evidence index.
Phases are never deleted when they close — they are marked, and their evidence
stays.

**Where the project stands, 2026-10-02.** All eight phases are closed or done:
**P0 CLOSED**, **P1 EXECUTED**, **P2 DONE**, **P3 DONE**, **P4 DONE**, **P5
DONE**, **P6 CLOSED**, **P7 DONE**. P1's execution is the change since the
previous revision: 57 Apple binaries and dyld debug snapshots were moved out of
`tools/bootlab/assets/` into `tools/bootlab/assets-quarantine/`, nothing was
deleted, and every quarantined file is recorded by sha256, filetype and
historical identity in `assets-quarantine/QUARANTINE_INVENTORY.txt`. `assets/`
now scans **HOST-EXTRACTED: 0**, and all three manifests pass the gate.

**Everything in this document is prepared in the working tree and
UNCOMMITTED.** `manifest_cpmv.json`, `closure_gate.py` and
`provenance_scan.py` are untracked; the edits to `manifest.json`,
`manifest_dynamic.json`, `closure_check.py`, `README.md`, `.gitignore` and the
runner scripts are unstaged. No claim below should be read as describing a
commit.

What "done" means for each, measured after the change:

| phase | result |
|---|---|
| **P0 — CLOSED** | `tools/bootlab/manifest_cpmv.json` exists and is un-ignored (untracked; no commit was made): 46 explicit entries, **no glob**, one `asset:` entry (a plist), **0 absolute paths**. `closure_check.py manifest_cpmv.json --nm-check 0` → PASS: 0 unstaged dependencies, 0 dangling `N_INDR` aliases, 0 REJECT, 0 unresolved, HOST-EXTRACTED 0. **The last blocker is gone:** the 2 entries that used to resolve outside the repo are now produced **in-repo** — `libcompiler_rt.dylib` by a new `Libraries/Libsystem/Makefile` rule (170 vendored compiler-rt TUs) and `libunwind.dylib` by a redirected `UNWIND_TARGET = ${.CURDIR}/libunwind.dylib`; both manifest entries now read `../../Libraries/Libsystem/…`. The manifest is therefore **relocatable**, not merely relative. The `closure_gate.py` preflight is retained as the guard against any future entry reintroducing an external path. Producer artifacts independently verified in §4 P0. **Updated 2026-10-02:** `manifest_dynamic.json` and `manifest.json` have both been swept since — the latter no longer globs `assets/usr/lib/system/` and now passes too, so the P0-era statement that it "still fails and is protected" is superseded by P1's manifest sweep. |
| **P1 — EXECUTED** | **57 files MOVED out of `assets/` into `tools/bootlab/assets-quarantine/`; nothing deleted.** 31 host-extracted dylibs + `dyld.orig` + `libSystem.B.dylib{,.orig}` (34 host-extracted in total), the host **disk** product binaries `assets/bin/{cat,echo,ls}` and the two host frameworks `CoreFoundation` / `XPCSupport`, the 17 `dyld.PRE-*`/`dyld.PREV-*` debug snapshots, and `assets/usr/lib/dyld` (not host-extracted — a superseded build of *our own* dyld, and `MH_DYLIB`, which the kernel rejects as a dylinker). Every sha256, filetype, `LC_UUID`, `__TEXT` vmaddr and milestone identity is in `assets-quarantine/QUARANTINE_INVENTORY.txt`; the 17 snapshots are described individually, with the probe strings measured in each image. `provenance_scan.py --target assets` → **HOST-EXTRACTED: 0** (was 34). **All three manifests now pass the gate** (`manifest.json` reported 32 host-extracted before). Collateral sweep: `manifest.json` de-globbed and repointed, `manifest_dynamic.json` repointed at `work/{echo,sh}_dyn` + `usr/lib/libedit.dylib`, `run.sh` default moved to `manifest_cpmv.json`, `assets-quarantine/` gitignored. `run_gated_loader.sh` is the one consumer that no longer works as written and is recorded as such. |
| **P2 — DONE** | `closure_gate.py` gates the **unprotected** runner scripts — `run.sh` (`mkimage`, `full`), `run_dynamic_gate.sh`, `run_gated_loader.sh`, `run_minxfer.sh`, `run_applefree.sh` — on the same manifest argument each hands `mkimage.py`, and refuses before image construction. `run.sh` now injects its default manifest explicitly rather than inheriting `mkimage.py`'s, so gating a tree can never diverge from building it. It does **not** cover a direct `mkimage.py` call. Provenance can also judge **image bytes** (`closure_check.py --image`), with a demonstrated negative control (§7); that mode is automatic only for `run_dynamic_gate.sh --no-build`. **The blocker P2 was built to survive no longer exists**: when P2 was written, 31 host-extracted dylibs sat in `assets/` and the gate was the only thing between them and a disk. After P1 they are gone from the tree, so the gate's job is now the next clone and the next contributor — plus the relocatability preflight, which still refuses a manifest naming a path outside the repository. Kept for those reasons, not for the old one. |
| **P3 — DONE** | The 0-byte `libncurses{,.6}.dylib` are gone and their **producer is fixed** — `BSD/lib/ncurses/Makefile` no longer `touch`es them and fails loudly instead. `Libraries/check_sdk_stubs.sh`'s `RECORDED_ZERO_BYTE_STUBS` **allow-list is deleted**; a 0-byte dylib is now an unconditional FAIL, and retired stubs may not return at any size. Both directions proven with negative controls (§4 P3). |
| **P4 — DONE** | The last two libobjc unwind symbols are closed, which is what drove the clean closure from FAIL to PASS. Verified by the full cycle in §4 P4. |
| **P5 — DONE** | **The fix is applied and verified.** `-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/mach` became `-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall` (`Libraries/Libsystem/Makefile:23`) — the parent, which exposes no top-level headers, so all 63 `mach/` headers now resolve to the build SDK's `usr/include/mach` and **zero** to `Kernel/xnu/libsyscall/mach/mach/`. Verified in the required order: full `build_all_libsystem.sh` **PASS** (29 stages, 0 failures, hard gate PASS, 404s); `closure_check.py manifest_cpmv.json --nm-check 0` → **PASS** (0 host-cache extractions of 42 staged, closure complete); `nm -gU …/libunwind.dylib` still `T` at unchanged `c242`/`c1f0`. Guard renaming remains a measured **no-op** and tree deletion remains measurably **wrong** (in-repo and build-SDK `mach/` are one tree and its copy — 0 of 91 headers differ); neither was needed. Component-dependence under `RUNTIME_FLAGS`' `PrivateHeaders` is out of scope and untouched (§4 P5). |
| **P6 — CLOSED** | **`libcompiler_rt.dylib` is closed on BOTH counts.** *Version:* resolved to **17.0.6** from four independent signals, recorded in `Developer/Default.xctoolchain/_PROVENANCE`. *Artifact origin:* no longer an unrecorded artifact — a producer workstream added a `Libraries/Libsystem/Makefile` rule building it in-repo from **170 vendored compiler-rt TUs**, and the produced dylib was independently verified: 81,472 B, x86_64, **529 exports**, `install_name` matching the manifest `path`, fresh `LC_UUID`, and object source paths under the tracked `Developer/Default.xctoolchain/llvm/compiler-rt/lib/builtins/`. **The eight rebased host-extracted files are no longer an open item.** Their original Apple build was never recoverable — a rebase destroyed the evidence — and it was left UNKNOWN rather than guessed at. P1 retired the question by moving the files into the gitignored quarantine, where the inventory records them by sha256 and states that their original build is unknown and will stay unknown. P6's goal was "no binary **in the tree** should have an unrecorded origin"; the archive is where a destroyed piece of evidence belongs, because it cannot reach a disk. |
| **P7 — DONE** | The acceptable-borrowing policy is written (§4 P7) and referenced from `README.md` and `BOOT-PLAN.md`. P1 converted it from a stated rule into an enforced one: the files the rule forbids are out of the tree, and `provenance_scan.py` + `closure_gate.py` keep them out. |

Every claim carries either a `file:line` or the command that produced it.

---

## 1. Current state

The concern that prompted this audit was that ravynOS was borrowing libraries
from the host Apple Mac rather than building from Apple's open-source Darwin
source. Two independent audits were run. They disagreed about how bad the
situation was, and **both answers were correct about different parts of the
tree**:

| Claim | Status then | Status now (after P1) | Evidence |
|---|---|---|---|
| The **build path** borrows library code from the host Mac | **No.** ~100% vendored Apple OSS | unchanged — **No** | §3.1 |
| The **live boot closure** contains host-extracted binaries | **No.** 0 of 41 | unchanged — **No** | §3.3 |
| **Borrowed Apple binaries remain in the tree** | **Yes. 31 dylibs** in `assets/usr/lib/system/`, plus `dyld.orig`, `libSystem.B.dylib.orig`, and 17 dyld snapshots | **No.** 57 files MOVED to `tools/bootlab/assets-quarantine/`; `provenance_scan.py --target assets` → `HOST-EXTRACTED: 0` | §3.2, §4 P1 |
| A **manifest** stages that contaminated region | `manifest_dynamic.json` cleaned by P0; `manifest.json` still did, and was protected | **Neither does.** All three manifests pass; `manifest.json`'s glob is gone | §4 P0, §4 P1 |
| The clean closure exists only as an **uncommitted file in `/tmp`** | **Largely** — `tools/bootlab/manifest_cpmv.json`, un-ignored and tracked-eligible, and **relocatable**: all 46 entries repo-relative | unchanged, and it is now the **default** for `run.sh mkimage` and `run.sh full` | §4 P0 |

**The default boot path is no longer blocked.** When this table was first
written, `run.sh mkimage` and `run.sh full` **stopped** rather than built,
because the default manifest was `manifest.json`, it staged 32 host-extracted
binaries, and it was a protected path that could not be edited. All three of
those conditions are gone: `manifest.json` was authorized and de-globbed, the
binaries it staged are quarantined, and `run.sh` now defaults to
`manifest_cpmv.json`. Verified end to end — `./run.sh mkimage work/boot.img`
gates clean and writes a 46-file image with matching content hashes.

So the honest summary is: **the product is clean, the tree is clean, and the
gate that keeps both that way runs before every image the unprotected runner
scripts build** — as prepared, uncommitted work. P0 moved the clean closure out
of `/tmp` into a repository file that passes every check; P2 made the runners
ask `closure_check.py` first and stop on a nonzero verdict; P1 removed the
contamination the gate had been guarding against.

**What still limits this, and it is one thing.** The gate is reached only by
the scripts that call it: a bare `python3 mkimage.py --manifest M` bypasses it
entirely. `mkimage.py` is a protected path, so that is not fixable here.
Everything else that used to qualify this summary has been closed rather than
hedged. And nothing in this document describes a *commit* — no commit was made.

### The four borrowing categories

1. **Build tools — acceptable, unavoidable.** The host Command Line Tools supply
   `clang`, `ar`, `nm`, `strip`, `ld`, `otool`, `byacc`, `flex`.
   `Developer/Default.xctoolchain` is a source-only layout with no built tools,
   so `bsd.*.mk` paths must be pinned to the host CLT binutils.
2. **Headers — mild.** The host CLT `usr/include` contains only `FlexLexer.h`,
   `module.modulemap` and `swift/`, so Apple SDK headers are *not* being copied
   in wholesale. One block in ravynOS's `sys/cdefs.h` is transcribed from the
   host SDK's `cdefs.h` (see §3.1).
3. **Library code — was severe, and no longer exists.** 31 dylibs in
   `tools/bootlab/assets/usr/lib/system/` had been extracted from the host's
   shared cache. That was the finding that mattered, §2 is the test that proved
   it, and P1 quarantined all 57 affected files. **A fourth category P1
   discovered is now recorded alongside these three: host *disk* product.**
   `assets/bin/{cat,echo,ls}` were byte-for-byte copies of this host's
   `/bin/{cat,echo,ls}` and were **invisible to §2's test**, because they came
   off the filesystem rather than out of the shared cache. Category 3 is
   resolved; category 4 was found and resolved in the same pass.

---

## 2. How provenance is measured

This is the strongest evidence available, and it is worth stating precisely
because it is reproducible.

**The test.** Apple mints a fresh `LC_UUID` per build. The host's dyld shared
cache stores every image's `LC_UUID`. Therefore *a binary whose `LC_UUID`
appears in the host cache's image records came out of that exact Apple build.*
This is unforgeable and machine-local, unlike a byte comparison against a
toolchain that may have been updated.

**The subject.** `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/`
holds a **split** cache: `dyld_shared_cache_x86_64h` (888,668,160 B) plus six
subcaches `.01`–`.06` (697 MB – 1.0 GB each). All seven must be scanned; the
base file alone is not the whole cache.

**The correction that must not be repeated.** An earlier pass indexed the cache
by 2048-byte-aligned pages and reported **24** host-extracted files. That number
was wrong. Shared-cache images are **not** all 2048-aligned, so an aligned page
index silently skips images. The correct answer is **31**. Anyone re-deriving
this must not use page-aligned indexing. §3.2 records what the array layout
actually is.

**A second correction, found while re-verifying.** `0x1de48` is a valid position
in the image array, but it is *not the start of the array*. It is the `address`
field of record index 3796; the `address`-only images array actually begins at
`0x3d8` with 3626 records, which matches the 3626 images listed in the official
`dyld_shared_cache_x86_64h.map`. Walking **forward** from `0x1de48` covers only
619 records. To avoid depending on that subtlety, the scan used here builds a
**deliberate superset**: every non-zero 16-byte UUID at an 8-byte-aligned
offset whose following `u64` falls inside one of the cache's 30 mapped ranges
(from the `.map` file). That yields **10,835 UUIDs**. Over-approximation is safe
here — a 128-bit UUID does not collide by accident — while under-approximation
would silently hide a borrow, which is exactly the failure mode that produced
the "24".

**Reproduce:**

```
python3 tools/bootlab/provenance_scan.py --target tools/bootlab/assets/usr/lib
```

`provenance_scan.py` is P2, landed 2026-10-02; this is the command that
produces the numbers §3.2 records. Its exit status is load-bearing:
0 = clean, 1 = a host-extracted binary was found, 2 = the check could not
run at all.

---

## 3. Provenance classification

### 3.1 The build path — vendored Apple OSS

`Libraries/Libsystem` **is** Apple's own source, imported verbatim as
Libsystem-1353.0.10 (macOS 12 Monterey).

| Evidence | Location |
|---|---|
| "Library versions within libsystem were taken from Monterey System.tbd" | `Libraries/Libsystem/Makefile:245` |
| `libsystem_c.dylib 1353.0.10` | `Libraries/Libsystem/Makefile:259` |
| `__DARWIN_ONLY_UNIX_CONFORMANCE` gates | `Libraries/Libsystem/libsystem_c/include/sys/cdefs.h:53,55,57` |
| Apple's own `libsystem_c/Libc.xcodeproj`, `Libsystem.xcodeproj` present | `Libraries/Libsystem/` |
| Upstream import provenance recorded | `Developer/ravynOS.sdk/_PROVENANCE` (`apple-oss-distributions/distribution-macOS.git`, `rel/macOS-12`; `CarbonHeaders.git`) |
| 22 files carry `Begin-Libc`, 25 carry `LIBC_ALIAS_*` | `grep -rl` over `Libraries/Libsystem` |

Also vendored: `Libraries/dyld`, `Libraries/objc4`, `Libraries/CrashReporterClient`,
`BSD/` (FreeBSD userland), `Kernel/xnu` (Darwin 24 / xnu-11215).

**No library code is copied from the host CLT SDK into the product.**

**The three recent Libsystem functions are not Apple code.** `copy_file_range`,
`chflagsat` and `acl_is_trivial_np` are FreeBSD POSIX-2008 APIs called by the
FreeBSD-derived `BSD/bin/cp`, `BSD/bin/mv` and `BSD/usr.bin/find`.

```
$ git log --all --oneline -S<fn> -- Libraries/Libsystem     # for each of the three
(no output, exit 0)
```

No commit anywhere in the repository ever introduced or removed these
identifiers. They are new work, and they are still untracked:

```
$ git status --porcelain Libraries/Libsystem/libsystem_c/emulated/{copy_file_range,chflagsat}.c \
                       Libraries/Libsystem/libsystem_c/posix1e/acl_trivial.c
?? .../emulated/chflagsat.c
?? .../emulated/copy_file_range.c
?? .../posix1e/acl_trivial.c
```

The declarations had to be added first because Apple's Libsystem declares
**none** of the `*at` family. Searching the vendored headers returns exactly one
hit, and it is a comment:

```
$ grep -rn "fstatat\|linkat\|symlinkat\|readlinkat\|setattrlistat" Libraries/Libsystem/libsystem_c/include/
include/fcntl.h:38: *   bsd/vfs/vfs_syscalls.c:7395  fstatat() accepts AT_SYMLINK_NOFOLLOW_ANY
```

Five vendored headers are modified to carry them: `fcntl.h`, `fts.h`, `paths.h`,
`sys/acl.h`, `unistd.h`. **This is a FreeBSD/Darwin seam, not host borrowing.**

**Placement follows Apple's own convention, with one exception.**
`libsystem_c/emulated/` is Apple's designated home for functions emulated over
other primitives, and already contains `brk.c`, `bsd_signal.c`, `lchflags.c`,
`lchmod.c`, `lutimes.c`, `statvfs.c`, `tcgetsid.c`. `copy_file_range.c` and
`chflagsat.c` went there. `emulated/lchflags.c:30-43` is the same technique —
`lstat` then `setattrlist(..., FSOPT_NOFOLLOW)`.

> **Discrepancy.** The audit brief placed all three new functions in
> `emulated/`. Two are there. `acl_is_trivial_np` is in
> `libsystem_c/posix1e/acl_trivial.c`, alongside the rest of the POSIX.1e ACL
> code, which is the correct home for it. Minor, but recorded so the next reader
> does not go looking in the wrong directory.

**The header transcription.** `__DARWIN_ONLY_UNIX_CONFORMANCE` is defined by
the kernel's `bsd/sys/cdefs.h` only inside `#ifdef KERNEL` / `#ifdef XNU_PLATFORM_*`
blocks. Userspace defines neither, so the generated `libc-features.h` aborts with
`Feature mismatch: __DARWIN_ONLY_UNIX_CONFORMANCE == 0`. ravynOS therefore
transcribes that block into its own `cdefs.h` and injects `-DXNU_PLATFORM_MacOSX`
centrally through the `isysroot-cc` shim. This is the one real header borrowing,
and it is a build-configuration workaround, not code.

### 3.2 The staged assets — 46 files, 31 host-extracted

`tools/bootlab/assets/usr/lib/system/` contains **46** dylibs. Scanned against
the host cache UUID set: **31 HOST-EXTRACTED**, 15 not in the host cache.

**HOST-EXTRACTED (31).** Borrowed Apple binaries, extracted from the host Mac's
shared cache:

```
libcache                       libsystem_collections       libsystem_dnssd
libcommonCrypto                libsystem_configuration     libsystem_eligibility
libcopyfile                    libsystem_containermanager  libsystem_featureflags
libcorecrypto                  libsystem_coreservices      libsystem_networkextension
libcorecrypto_noasm            libsystem_darwin            libsystem_notify
libcorecrypto_trace            libsystem_darwindirectory   libsystem_sandbox
libkeymgr                      libsystem_sanitizers        libsystem_secinit
libkxld                        libsystem_symptoms          libsystem_trace
libmacho                       libsystem_trial             libunc
libquarantine                  libunwind
libremovefile
libsystem_asl
```

**Corroborating, independent signal.** These files also carry the **host
cache's absolute load address** in their `LC_SEGMENT_64 __TEXT` `vmaddr` — e.g.
`libcache.dylib` at `0x7ff812eaa000`, which is exactly the `__TEXT` vmaddr the
host `.map` file records for `/usr/lib/system/libcache.dylib`. No repo build
emits a load address in the host shared cache's range. Two unrelated signals
agreeing is what makes this a measurement rather than an inference.

**Rebased in place.** Eight of the 31 were mutated after extraction (rebase /
fixup), which is why a byte-scan misses them but the UUID hits — the UUID
survives the rewrite:

| File | `__TEXT` vmaddr | Note |
|---|---|---|
| `libcorecrypto_noasm.dylib` | `0x7f8060000000` | rebased |
| `libcorecrypto_trace.dylib` | `0x7f8070000000` | rebased |
| `libkxld.dylib` | `0x7f80b0000000` | rebased |
| `libsystem_darwindirectory.dylib` | `0x7ffe0c345000` | rebased |
| `libsystem_eligibility.dylib` | `0x7ffe0c34a000` | rebased |
| `libsystem_sanitizers.dylib` | `0x7ffe0c355000` | rebased |
| `libsystem_trial.dylib` | `0x7ffe0c35d000` | rebased |
| `libunc.dylib` | `0x7f8290000000` | rebased **and stripped to `__text` = 0** |

> **Discrepancy.** The audit brief listed **7** rebased files. The eighth is
> **`libkxld.dylib`**, whose `__TEXT` vmaddr `0x7f80b0000000` is equally
> non-Apple-native. It was omitted from the brief's list. The count of 31
> host-extracted files is unaffected.

`libunc.dylib` is the worst individual case: host-extracted, then stripped to
nothing. It exports exactly two symbols and no code:

```
$ nm -gU tools/bootlab/assets/usr/lib/system/libunc.dylib
00007f82900004b0 S _uncVersionNumber
00007f8290000480 S _uncVersionString
```

Any call into it would fault.

**NOT host-extracted (15).** 14 are vendored Apple OSS, built from
`Libraries/Libsystem`, `Libraries/dyld`, `Libraries/objc4` and
`Libraries/CrashReporterClient`; `libcompiler_rt.dylib` is a `Libraries/Makefile`
build target (151,960 B, 529 exports), built from the vendored compiler-rt
sources at **LLVM 17.0.6** (§4 P6). None is a lifted Apple binary.

**Also borrowed, outside `system/`:**

| Path | Bytes | Fact |
|---|---|---|
| `assets/usr/lib/dyld.orig` | 2,524,592 | **universal `[x86_64][arm64e]`**, `MH_DYLINKER`. No repo build emits an arm64e slice. Its x86_64 slice matches 105/537 host-cache pages verbatim. |
| `assets/usr/lib/libSystem.B.dylib.orig` | 81,920 | host-extracted (UUID hit); `__TEXT` vmaddr `0x7f8028000000`, rebased |
| `assets/usr/lib/libSystem.B.dylib` | 71,948 | host-extracted (UUID hit), `__TEXT` vmaddr `0x7ff812eb0000` |
| `assets/usr/lib/dyld` | 988,088 | `MH_DYLIB`. The kernel rejects a DYLIB used as the dynamic linker with `EXEC_EXIT_REASON_BAD_MACHO`. Not host-extracted, but wrong — `manifest_dynamic.json` already works around it by staging `Libraries/dyld/dyld/dyld` instead. |
| `assets/usr/lib/dyld.PRE-*` / `dyld.PREV-*` | 17 files, 1.69–1.73 MB each | dead snapshots from 2026-09-27 → 09-28. |

> **Discrepancy.** The audit brief counted **16** snapshots. There are **17**
> (`ls assets/usr/lib/dyld.PRE* | wc -l` → 17; sixteen match `dyld.PREV*` and
> one is `dyld.PRE-SALLOC-GATE`).

**Staleness.** Comparing the 46 staged files against the current SDK at
`/Users/max/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk`:

| Result | Count |
|---|---|
| byte-identical to the SDK | **2** (`libCrashReporterClient.dylib`, `libcompiler_rt.dylib`) |
| present but divergent | 24 |
| absent from the SDK entirely | 20 |

> **Discrepancy.** The brief said "only 3 of the 46 are byte-identical." My
> measurement is **2**. Only 26 of the 46 have an SDK counterpart at all; the
> other 20 cannot be byte-identical to anything current. The conclusion is
> unchanged and slightly worse than stated: 44 of 46 are not current.

### 3.3 The live closure — 41 nodes, 0 host-extracted

`/tmp/manifest_cpmv.json` stages 46 entries → 41 Mach-O `x86_64` nodes, 40 in
closure. Scanning the **41 source files** those entries point at:

```
scanned 41 Mach-O files; 0 HOST-EXTRACTED, 41 not-in-host-cache
```

Scanning the whole SDK independently:

```
$ python3 <scanner> $SDK/usr/lib/system/ $SDK/usr/lib/
scanned 74 Mach-O files; 0 HOST-EXTRACTED, 74 not-in-host-cache
```

Bucketing the 41 staged Mach-O files by where each one is built from:

| Bucket | Count | Share | Contents |
|---|---|---|---|
| **VENDORED_APPLE_OSS** | **31** | **76%** | 27 built into the SDK from Apple's sources; 3 from `Libraries/` (`objc4` → `libobjc.dylib`, `Libsystem` → `libSystem.B.dylib`, `dyld` → `dyld`); 1 from `BSD/lib/libedit` |
| **GENERATED** | **10** | **24%** | the 9 `work/*_dyn` utilities (`sh`, `echo`, `ls`, `cat`, `mkdir`, `rm`, `test`, `cp`, `mv`) and `work/init_shell` → `/sbin/launchd` |
| **HOST_EXTRACTED** | **0** | **0%** | — |
| Load-bearing stubs | **0** | 0% | — |

> **Discrepancy.** The audit brief reported this bucket as
> "VENDORED_APPLE_OSS 37/41 (90%), GENERATED 4/41 (10%): init_shell, the 10
> `*_dyn` utilities, BOOTX64.EFI, the kernel". That framing counts the four
> *categories* rather than the *files*, and it names BOOTX64.EFI and the kernel,
> which `closure_check.py` reports separately from the 41 Mach-O nodes. Counting
> the 41 nodes individually gives **31 vendored / 10 generated / 0
> host-extracted**. The headline — **0% host-extracted** — is unaffected and is
> the number that matters.

The SDK result matters more than it looks: `libcorecrypto`, `libcopyfile`,
`libmacho`, `libremovefile`, `libsystem_asl`, `libsystem_coreservices`,
`libsystem_darwin`, `libsystem_dnssd`, `libsystem_notify` and `libcommonCrypto`
**all appear in `assets/` as host-extracted AND in the SDK as repo-built**.
Repo-built replacements for the borrowed set already exist. That materially
lowers the cost of P1.

`closure_check.py` on `/tmp/manifest_cpmv.json`, **as re-verified after P4
landed**:

```
staged entries: 46   Mach-O x86_64 nodes: 41   non-Mach-O: 5
nodes in closure: 40        dependency edges: 177     export universe: 10784
unstaged dependencies: 0    dangling N_INDR: 0
PASS: 30    REJECT: 0
files affected: 0  distinct symbols: 0
VERDICT: PASS  (closure complete, all non-weak undefineds resolve, all staged dylibs valid)
```

The distinction the brief blurred: the closure is **structurally clean** (0
REJECT, 0 unstaged, 0 dangling) *and* now its **overall verdict is PASS** too.

This was the last FAIL. Before P4 it reported `files affected: 1 / distinct
symbols: 2` — `___libunwind_Registers_x86_64_jumpto` and `___unw_getcontext`
from `usr/lib/system/libobjc.dylib` — for a total verdict of FAIL. Those two
symbols were not missing code; they were compiled into `libunwind.dylib` as
`.private_extern` symbols and so were unreachable from a standalone dylib.
**P4** was a visibility fix, not a build fix; see §4 P4.

---

### P0 — Make the clean manifest durable `CLOSED 2026-10-02 — all 46 entries repo-relative (portability prerequisite met)`

**Goal.** Stop the contamination from reaching a boot image, and make the clean
closure a property of the repository instead of a property of `/tmp`.

**Why first.** Everything else is cleanup. This is the only item where doing
nothing actively causes harm: `manifest_dynamic.json` currently resolves
`{"glob": "usr/lib/system"}` against `assets/`, which pulls in all 46 assets
including all 31 borrowed binaries. Its closure:

```
staged entries: 61   Mach-O x86_64 nodes: 54
nodes in closure: 53        unstaged dependencies: 3
  bin/ls                         LC_LOAD_DYLIB /usr/lib/libncurses.5.4.dylib
  bin/ls                         LC_LOAD_DYLIB /usr/lib/libutil.dylib
  usr/lib/system/libkxld.dylib   LC_LOAD_DYLIB /usr/lib/libc++.1.dylib
PASS: 20    REJECT: 28
files affected: 28 distinct non-weak undefined symbols: 84
VERDICT: FAIL
```

The 28 REJECTs carry one signature — `exports_trie=(0,0)` against a nonzero
`__LINKEDIT.fileoff`, i.e. the historical
`malformed mach-o image: dyld chained fixups info underruns __LINKEDIT`:

```
REJECT  usr/lib/system/libcache.dylib
        __LINKEDIT fileoff=49152 filesize=3916  exports_trie=(0, 0)
          line 487  REJECT exports trie dataoff=0 >= 49152  (0 < 49152 ? True)
```

**Changes.**
1. Promote `/tmp/manifest_cpmv.json` to a repository manifest (suggested:
   `tools/bootlab/manifest_cpmv.json`).
2. Replace the `glob` in `manifest_dynamic.json` with explicit per-file entries,
   so no future edit can silently re-admit an `assets/` binary.

**Two refinements the evidence forces.** The brief describes `manifest_cpmv.json`
as staging "ZERO files from `assets/` (no globs, no `asset:` keys)". It has
**one** `asset:` key:

```
{"path": "System/Library/CoreServices/com.apple.Boot.plist", "asset": "com.apple.Boot.plist"}
```

That is a plist, not a binary, so the conclusion holds — but P0 must state the
rule precisely: **zero `asset:` entries that resolve to a Mach-O**, not "zero
`asset:` keys".

More importantly, **38 of its 46 entries pin absolute, machine-specific paths**
(`/Users/max/Projects/build/...`). Promoting it verbatim bakes this machine's
build directory into the repository — which is exactly what
`manifest_dynamic.json`'s own comment warns against ("a manifest naming it would
pin a machine-specific path"). P0 must therefore also **de-pin those 38 entries**
to `$RAVYN_SDKROOT`-relative or repo-relative paths, exactly as
`manifest_dynamic.json` does for `Libraries/dyld`.

**Acceptance (checkable) — all three met, but that is NOT the whole goal.**
These are the checks the original P0 text listed; the goal it stated
("a property of the repository, not of `/tmp`") also required relocatability,
which is **not** met. Do not read PASS below as P0 being done.
- `python3 tools/bootlab/closure_check.py manifest_cpmv.json --nm-check 0`
  → `unstaged dependencies: 0`, `dangling N_INDR aliases: 0`, `REJECT: 0`,
  0 unresolved non-weak symbols, `HOST-EXTRACTED: 0`, `closure_check: PASS`.
- `grep -c '"glob"' tools/bootlab/manifest_dynamic.json` → `0`
  (also `0` in `manifest_cpmv.json`).
- `python3 tools/bootlab/provenance_scan.py --manifest manifest_cpmv.json`
  → `HOST-EXTRACTED: 0`, exit 0.

**What landed, and the two places the ideal was not reachable.**

1. `manifest_dynamic.json` was cleaned, not just de-globbed: the 27 closure
   members are now named individually, `usr/lib/libSystem.B.dylib` is the repo
   build product rather than the host-extracted asset, and `bin/ls`,
   `bin/cat` and `usr/lib/libobjc.A.dylib` were dropped — each for a reason
   recorded in the manifest's own comment and confirmed by `closure_check`.
   It now passes. `manifest.json` **could not** be cleaned: it is a protected
   path, so it still fails the gate, and `run.sh full` / `run.sh mkimage`
   (default manifest) therefore stop before building. That is the correct
   verdict — the images it describes cannot boot — but it is a live
   consequence, not a completed cleanup. Unblocking it needs authorization to
   edit `manifest.json`, or an explicit move of the default to
   `manifest_cpmv.json`.

2. **The two external entries are now IN-REPO. P0 is no longer PARTIAL on this
   ground.** This item was PARTIAL because both `libunwind.dylib` and
   `libcompiler_rt.dylib` resolved outside the repository. A producer
   workstream closed both (2026-10-02), and the manifest followed them:

   | entry | before | after |
   |---|---|---|
   | `usr/lib/system/libcompiler_rt.dylib` | **no producer at all**; the entry pointed at `../../../build/...` | produced in-repo by `Libraries/Libsystem/Makefile` (`COMPILER_RT_TARGET = ${.CURDIR}/libcompiler_rt.dylib`, rule at `:405`) from **170 vendored compiler-rt TUs**; manifest entry is now `../../Libraries/Libsystem/libcompiler_rt.dylib` |
   | `usr/lib/system/libunwind.dylib` | repo-built but linked **only** into the SDK dir, so the manifest had to name `../../../build/...` | redirected: `UNWIND_TARGET = ${.CURDIR}/libunwind.dylib` (`Libraries/Libsystem/Makefile:199`), with the SDK copies now a *consequence* of that target rather than its only output; manifest entry is now `../../Libraries/Libsystem/libunwind.dylib` |

   **Independently verified 2026-10-02, from the produced artifacts** (not
   from the worker's report, and without running a build):

   ```
   $ ls -la Libraries/Libsystem/lib{compiler_rt,unwind}.dylib

   $ sed -n '/^COMPILER_RT_SOURCES = /,/^$/p' Libraries/Libsystem/Makefile \
       | grep -oE '[A-Za-z0-9_]+\.[cS]\b' | sort -u | wc -l
   170                                   # matches the reported TU count

   $ nm -gU Libraries/Libsystem/libcompiler_rt.dylib | wc -l
   529                                   # matches the reported export count

   $ otool -D Libraries/Libsystem/libcompiler_rt.dylib
   /usr/lib/system/libcompiler_rt.dylib
   $ lipo -info Libraries/Libsystem/libcompiler_rt.dylib
   Non-fat file: ... is architecture: x86_64
   $ otool -L Libraries/Libsystem/libcompiler_rt.dylib | tail -n +2
       /usr/lib/system/libcompiler_rt.dylib (compatibility version 1.0.0, current version 1.0.0)
   ```

   The `install_name` and the manifest's `path` agree, which is what makes
   `usr/lib/system/libcompiler_rt.dylib` resolvable in the image; the version
   pair matches the target's `-Wl,-current_version,1.0.0`.

   **Provenance is now VENDORED_APPLE_OSS by construction, not by assumption.**
   The dylib's `LC_UUID` is `A351AF58-A2BC-3C9E-BC62-20D2A5E407FF`, and its
   objects carry compile-time source paths under
   `Developer/Default.xctoolchain/llvm/compiler-rt/lib/builtins/` — the
   tracked, `_PROVENANCE`-recorded tree. So the artifact is no longer an
   unrecorded one, which is what P6 was waiting on.

   **P4 is not regressed by the `libunwind` redirect** — checked read-only with
   `nm`, since the unwind symbols are ABI-critical:

   ```
   $ nm -gU Libraries/Libsystem/libunwind.dylib | grep -E 'unw_getcontext|Registers_x86_64_jumpto'
   000000000000c242 T ___libunwind_Registers_x86_64_jumpto
   000000000000c1f0 T ___unw_getcontext
   000000000000c1f0 T _unw_getcontext
   ```

   Same three symbols, same `T` type, and the same addresses (`c242` / `c1f0`)
   P4 recorded — so the redirect changed where the file is written, not what
   is in it.

   **Every manifest entry is now repo-relative.** The only remaining
   `/Users/...` strings in `manifest_cpmv.json` are two prose lines in its own
   comment block (lines 22 and 30) describing what P0 *used to* do; no entry
   resolves outside the repository:

   ```
   $ grep -n '/Users/' manifest_cpmv.json
   22:  "pinned 38 entries to /Users/max/Projects/build/... -- this machine's build",
   30:  "entries to /Users/max/Projects/build/... -- this machine's build tree --",
   ```

   Because `mkimage.py` is protected and expands no variables, a manifest could
   never name `$RAVYN_SDKROOT`; that constraint is what forced the
   sibling-build-tree spelling in the first place, and producing the dylibs
   in-repo is the correct resolution of it.

   **What this does NOT claim.** The relocatable manifest is now in place, but
   the producer targets only run after a `Libraries/Libsystem` build, so
   `manifest_cpmv.json` is only stageable once that build has been run.
   Note what the `closure_gate.py` relocatability preflight does and does not
   cover here: it refuses any source resolving **outside** the repository,
   whether or not it exists. An in-repo source that has simply not been built
   yet resolves *inside* the repo and is therefore **not** what this preflight
   catches — a fresh checkout missing the `Libraries/Libsystem` build is
   caught downstream by `closure_check.py`, not by the preflight. The
   preflight is retained as the guard against a *future* entry reintroducing
   an external path, which is the direction that matters.

   **Verification status of the producer work itself.** The artifacts and their
   exports were verified directly, as above. At the time this section was
   written a full `closure_check.py` / `closure_gate.py` pass over the
   repointed manifest had **not** been run here, because a concurrent
   Libsystem build was active in this tree. That is no longer the state of the
   evidence: the relocatability workstream subsequently ran the full gate on
   both clean manifests and observed `closure_gate.py manifest_cpmv.json` →
   `closure_check: PASS` / `=== closure gate: PASS -- continuing ===` (exit 0),
   and the same for `manifest_dynamic.json`, with 0 sources resolving outside
   the repository in each (46 and 40 entries respectively). Strictness of the
   preflight was confirmed in the other direction with negative controls.

   **It fails by name, not cryptically — and existence is deliberately not a
   pass.** `closure_gate.py` runs a relocatability preflight before
   `closure_check.py`: it lists every entry resolving outside the repository,
   names `RAVYN_BUILD_DIR` and its default, and exits 1 with
   `REFUSED (relocatability preflight)` **whether or not the path exists on
   this machine**, rather than letting `mkimage.py` report a bare
   `missing file source` that points an operator at the wrong problem. That
   strictness is the point: an out-of-repo entry that happens to be populated
   on the machine running the gate proves only that *this* checkout's sibling
   layout exists — which is precisely how a repo-relative manifest looks clean
   here and fails on a fresh checkout. Existence is not a pass. Missing,
   malformed and unreadable manifests fail closed too.

   With no out-of-repo entries left, both clean manifests now pass this
   preflight (0 outside in `manifest_cpmv.json`'s 46 entries and
   `manifest_dynamic.json`'s 40; `closure_gate.py` → PASS, exit 0 on each,
   measured by the relocatability workstream). The guard is now load-bearing in
   the direction that matters: any *future* entry that reintroduces an external
   path is refused by name, before image construction.

**Should the durable manifest just be the cleaned `manifest_dynamic.json`?**
No — measured, not assumed. The two files are not redundant:

| | `manifest_cpmv.json` | `manifest_dynamic.json` |
|---|---|---|
| staged entries | 46 | 40 |
| `usr/lib/system/` closure members | 28 | 28 (same 28, byte-identical sources) |
| PID 1 | `work/init_shell` → `execve()`s `/bin/sh` | `init_exec` marker → `work/init_exec` → `execve()`s `/bin/echo` |
| `/bin` staged | sh, echo, ls, cat, mkdir, rm, test, cp, mv | sh, echo |
| also stages | `usr/lib/libedit.dylib` | `etc/rc`, `hello.txt` |

Dropping `manifest_cpmv.json` would leave the dylib-linked core utilities and
the `/bin/sh` variant with **no durable manifest at all** — the echo gate
would be the only durable tree. So both stay.

The cost of that decision is stated rather than hidden: the 28-entry closure
block is duplicated across the two files, byte-identically, and the manifest
format has no include mechanism, so this cannot be factored out without
changing `mkimage.py` — a protected path. Any future edit to one closure
member must be made in both files. That is the single maintenance hazard P0
introduces, and it is the price of not losing the `/bin/sh` tree.

### P1 — Purge the host-extracted region `EXECUTED 2026-10-02 — 57 files MOVED to tools/bootlab/assets-quarantine/, nothing deleted; assets/ now scans HOST-EXTRACTED 0`

**Goal.** Remove the 31 borrowed binaries and their dead relatives from the tree.

**Why second** (written when P1 was still deferred; kept, because the premise it
examined is the premise P1 later acted on). The premise was "once P0 lands,
nothing stages these files". P0 **partially** delivered that, and the gap is
worth being exact about rather than rounding up:

| | stages `assets/usr/lib/system/`? | after P1 |
|---|---|---|
| `manifest_cpmv.json` (the clean closure) | **no** — 28 members named individually from repo/SDK paths, 0 glob, 1 `asset:` entry and it is a plist | unchanged; now `run.sh`'s default |
| `manifest_dynamic.json` (dynamic-userland echo gate) | **no** — same closure after P0 swept its glob | unchanged, plus `bin/{sh,echo}` repointed at `work/*_dyn` |
| `manifest.json` (**default**, protected) | **yes** — still a `glob` over `assets/usr/lib/system/`, plus `usr/lib/libSystem.B.dylib`. Protected, so P0 could not clean it | **glob removed.** It was authorized and de-globbed as part of P1, and now passes the gate |
| `manifest_minxfer.json`, `manifest_applefree.json` | **yes** — inherited the same glob, plus `asset:` entries for `bin/{sh,cat,echo,ls}` and `usr/lib/dyld`; gitignored per-experiment manifests, not swept | **REFUSED, and no longer for a provenance reason.** Measured: `closure_gate.py manifest_minxfer.json` → `closure_check: missing asset: assets/bin/cat`, exit 1. These two still name moved files, so they fail at *stage* time rather than on closure. They are per-experiment manifests and were not migrated; P1 did not convert them, and the gate stops them from building either way |

So, as written: two manifests clean, one default manifest not, two diagnostic
ones not. P2's gate kept the dirty ones from being built — it refused them
rather than cleaning them. That was the state P1 was deferred in, and it is
also why P1 could act safely once authorized: by then there was a measured
clean closure to move *to*, a gate that would stop anything else reaching a
disk, and a reason to believe the borrowed files were not load-bearing (§3.3).
The last two rows now read differently, and the difference is recorded rather
than edited away.

One caveat that **has now been resolved**, recorded here because the earlier
version of this section got it backwards: P0 originally did *not* make
`manifest_cpmv.json` relocatable — two entries depended on an out-of-repo build
tree. As of the 2026-10-02 producer workstream that is no longer true. Both are
now produced **in-repo** (`libunwind.dylib` by redirecting `UNWIND_TARGET` to
`${.CURDIR}`, `libcompiler_rt.dylib` by a new build rule over 170 vendored
compiler-rt TUs), and all 46 entries are repo-relative. The manifest is
relocatable; see §4 P0 for the verification.

What is unchanged, and should not be confused with the above: this was a
**portability** gap, never a **provenance** one. Neither file was ever
host-extracted, and closing the gap did not change their provenance class —
it only removed this host's build-tree layout from the picture.

**Status.** EXECUTED. On 2026-10-02 the deferral recorded below was reversed by
the user, in these words: *"Well if it isnt load bearing lets no longer use
apple binaries."* The premise P1 was deferred against — that the host binaries
might be load-bearing — had already been disproved by measurement (§3.3: the
live closure contained 0 of them), and P0/P2/P3 had by then built the
replacements, so the condition for acting was met. **The files were MOVED, not
deleted.** Quarantine rather than deletion is the standing rule for this
project: these bytes were Apple's, they must never be published, and a
forensic question about the incident must still have an answer.

**What happened, as executed.**

| | count | where it went |
|---|---|---|
| host-extracted dylibs in `assets/usr/lib/system/` | 31 | `assets-quarantine/usr/lib/system/` |
| host-extracted outside it: `dyld.orig`, `libSystem.B.dylib`, `libSystem.B.dylib.orig` | 3 | `assets-quarantine/usr/lib/` |
| `assets/usr/lib/dyld` — NOT host-extracted, a superseded build of **our own** dyld (`MH_DYLIB`, which the kernel rejects as a dylinker; §3.2) | 1 | `assets-quarantine/usr/lib/` |
| host **disk** product binaries: `assets/bin/{cat,echo,ls}` | 3 | `assets-quarantine/bin/` |
| host frameworks: `CoreFoundation`, `XPCSupport` | 2 | `assets-quarantine/System/Library/...` |
| dyld debug snapshots `dyld.PRE-*` / `dyld.PREV-*` | 17 | `assets-quarantine/usr/lib/` |
| **total moved** | **57** | |

Every file's sha256, byte size, filetype, `LC_UUID`, `__TEXT` vmaddr, mtime and
historical milestone is recorded in
`tools/bootlab/assets-quarantine/QUARANTINE_INVENTORY.txt`. The 17 snapshots
are described there individually, by the milestone their name encodes
(BINDBINDGUARD, CHAINPROBE, CHKSTK-LOCAL, VOUCHERS-FIXED, WALK-BOUNDED,
CONTROLPERTURB, …), with the probe strings actually found in each image so the
identity is checkable rather than asserted. That satisfies the "preserve what
has historical value, separately" requirement below, which is why nothing was
silently dropped.

**A category the audit brief did not name, and that mattered most.** The three
files under `assets/bin/` were **not** in the host dyld shared cache. Their
`LC_UUID`s are absent from it, so §2's test — the test this whole document
rests on — reports them as NOT host-extracted, and did so before and after the
quarantine. They were byte-for-byte copies of this host's `/bin/cat`,
`/bin/echo` and `/bin/ls` (universal `x86_64`+`arm64e`, carrying
`LC_CODE_SIGNATURE`), which `assets/.gitignore` had recorded all along. **The
provenance test is blind to host-disk product by construction**: it answers
"did this come out of the shared cache?", not "did this come off this
machine?". Quarantining them is the only reason this is now a closed question
rather than a permanent gap in the instrument.

**What was deliberately NOT quarantined.** `assets/bin/sh` (4,280 bytes, single
architecture, `LC_UNIXTHREAD`, no `LC_LOAD_DYLIB`) is a freestanding static
image **this repository built**, and 15 of the 46 dylibs under
`assets/usr/lib/system/` are vendored Apple OSS built from `Libraries/`. Both
are recorded as ours in `assets/.gitignore`. Quarantining them would have been
wrong, and the inventory says so explicitly so a later reader does not read
their absence as an oversight.

**The collateral sweep this forced.** The move broke every manifest that named
one of those paths, so all three were repointed at repo-built equivalents in
the same pass: `manifest.json`'s `glob` over `assets/usr/lib/system/` and its
`asset: bin/{cat,echo,ls}` entries are gone (replaced by the same explicit
closure `manifest_cpmv.json` uses); `manifest_dynamic.json` stages
`work/{echo,sh}_dyn` plus `usr/lib/libedit.dylib`; `run.sh` now defaults to
`manifest_cpmv.json` for both `mkimage` and `full`. Details in README.md.

**Acceptance (checkable) — MET, 2026-10-02.**

```
$ python3 tools/bootlab/provenance_scan.py --target tools/bootlab/assets
  Mach-O files examined: 18
HOST-EXTRACTED: 0
provenance_scan: PASS

$ cd tools/bootlab
$ python3 closure_gate.py manifest_cpmv.json      # -> PASS, HOST-EXTRACTED 0
$ python3 closure_gate.py manifest_dynamic.json  # -> PASS, HOST-EXTRACTED 0
$ python3 closure_gate.py manifest.json           # -> PASS, HOST-EXTRACTED 0
$ ./run.sh mkimage work/boot.img                  # -> 46 files, digests match
```

Zero `LC_UUID` hits anywhere under `assets/`, and no file matching
`dyld.orig|dyld.PRE*|dyld.PREV*|libSystem.B.dylib.orig` remains there. All three
manifests pass with **HOST-EXTRACTED: 0** — where before the quarantine,
`manifest.json` reported 32.

**Risk — what actually broke, and what it cost.** The prediction P1 made below —
that the damage would land at stage time rather than build time, and that the
only things that could break are manifests naming an `assets/` path — held
exactly. Nothing in the kernel, the loader, dyld or any build product was
affected. What broke was, in full:

- `run_gated_loader.sh` stages into `assets/usr/lib/dyld`, which no longer
  exists, so the loader-swap experiment is no longer runnable as written. It
  must be repointed at a repo-built dyld before it is used again. The
  inventory records this, since it is the one consumer of the archive that
  still wants a file out of it.
- `manifest.json`'s `glob` over `assets/usr/lib/system/` and its three
  `asset: bin/…` entries, and `manifest_dynamic.json`'s `asset: bin/{sh,echo}`
  entries. All repointed at repo-built equivalents in the same pass.

The prediction that `dyld.orig` might still be needed was checked before moving
it, and it is not: both clean manifests stage `Libraries/dyld/dyld/dyld`, a
source-built `MH_DYLINKER`. Nothing was lost, and nothing was lost silently —
every sha256 is in the inventory.

**A consequence worth stating plainly.** P1 retired the gate's original
justification. `closure_gate.py` existed because 31 host-extracted dylibs sat
in `assets/` and P2's gate was the only thing keeping them off a disk. That is
no longer the situation: there is nothing left under `assets/` to defend
against. The gate is kept anyway, because its job is now the *next* clone and
the *next* contributor, and because its relocatability preflight still refuses
a manifest that names a path outside the repository — a failure mode P1 did not
and cannot address.

### P2 — Make provenance mechanically enforced `DONE 2026-10-02`

**Goal.** Convert a one-time audit into a standing gate, so recurrence is
very unlikely rather than merely possible — and, on the paths that go through
the gate, not silent.

Scope, stated up front because "enforced" is easy to over-read: the gate
covers the **unprotected runner scripts** (`run.sh` `mkimage`/`full`,
`run_dynamic_gate.sh`, `run_gated_loader.sh`, `run_minxfer.sh`,
`run_applefree.sh`), each on the manifest it hands `mkimage.py`. It does not
cover a direct `mkimage.py` invocation. It also cannot repair the **protected**
default `manifest.json` — that manifest is refused, which blocks the default
boot path rather than cleaning it.

> **Updated 2026-10-02, after P1.** The sentence above was true when written
> and is now history: `manifest.json` was authorized and de-globbed, so it is
> no longer refused, and the default boot path is no longer blocked. `run.sh`
> also now injects its default manifest explicitly instead of inheriting
> `mkimage.py`'s, so the gate and the build cannot name different manifests.

**This was the load-bearing defence; P1 has now made it the second line.**
When P2 was written, P1 was deferred, so the 31 known host-extracted files were
still in the tree and this scanner plus the mechanical gate were the only thing
between them and a disk. **P1 has since moved all of them into the gitignored
quarantine**, so the first line of defence is now structural rather than
procedural. The gate is kept, and it is kept for a reason that did not exist
when it was written: it is what protects the *next* clone and the *next*
contributor, and it is the only thing that will notice if someone re-extracts
from the shared cache or names a path outside the repository. A guard that is
>only load-bearing during an incident is a guard that gets removed when the
incident ends; this one is now the standing check.

**This is now the load-bearing defence.**
Without P2, the next
person who adds an `assets/` glob can reintroduce the entire problem silently,
and the only symptom is a boot failure inside QEMU.
**Change.** Add `tools/bootlab/provenance_scan.py` implementing §2's test:
- build the host-cache UUID set from all seven split-cache files,
- scan a target tree or the resolved closure of a manifest,
- exit nonzero if any Mach-O's `LC_UUID` is a host-cache hit.

Wire it into the build/stage path so it **fails the build**, and into
`closure_check.py` as an additional verdict line.

**Note on ordering.** P1's acceptance criterion is this scanner, so the tool is
written in P1 and promoted to a build gate here. They are one piece of code, not
two. Implementing and wiring the gate in P2 was essential while P1 was
deferred; it remains what keeps the guarantee true now that the files
themselves are gone.

**The mechanical gate.** One helper, `tools/bootlab/closure_gate.py`, is
called before any image is constructed. It is a thin wrapper over
`closure_check.py` — no second checker to drift — and propagates its exit
status, so `set -e` scripts stop and `|| fail` scripts report. It is wired
into every unprotected runner that builds a disk, each on **the same manifest
argument it hands `mkimage.py`**:

| runner | manifest gated | where |
|---|---|---|
| `run.sh mkimage` | the caller's `--manifest`, else `manifest.json` | before `mkimage.py` |
| `run.sh full` | `${RAVYN_MANIFEST:-manifest.json}` | before `mkimage.py` |
| `run_dynamic_gate.sh` | `manifest_dynamic.json` | before `mkimage.py`; with `--no-build`, `--image "$IMG"` instead |
| `run_gated_loader.sh` | `manifest_dynamic.json` | before `mkimage.py` |
| `run_minxfer.sh` | `manifest_minxfer.json` | before `mkimage.py` |
| `run_applefree.sh` | `manifest_applefree.json` | before `mkimage.py` |

`run.sh full` takes the manifest from the environment rather than from
arguments because it must not forward `mkimage.py` arguments: `boot.py` then
boots `work/boot.img`, so a redirected image would boot a stale one.
`run_shell_af.py` consumes an image rather than building one, so it is out of
scope; the same check is available by hand with
`closure_gate.py <manifest> --image <img>`.

**What the gate covers, precisely.** A normal runner gates the **sources**
that are about to be staged — before any image exists. That is where a
borrow can still be *prevented*, and it is what all five runners do. Only
`run_dynamic_gate.sh --no-build` gates a **finished image**, because in that
mode there is no build step to precede. Nothing re-gates the image a normal
run just produced: that would cost a second full pass over a 512 MiB image
(~60 s), and it is available by hand via `closure_gate.py M --image IMG`.
So "`--image` is what the gate does" would be wrong; it is one of two modes,
and the runners use the other one.

**Image-bytes provenance — not a source scan wearing an `--image` label.**
`closure_check.py --image IMG` already parsed every staged path out of the
image for the closure and symbol checks, but its provenance verdict was still
computed from the files the manifest names. It now judges
`provenance_scan.macho_uuids_and_text_bytes(readback[path])` — the bytes
actually on the disk — and says so in its report (`bytes judged from: the
image, read back out of it`). `provenance_scan.py`'s Mach-O reader was split
into a bytes core plus a path wrapper for this. Two gaps closed in the same
pass: `manifest_sources()` now resolves `init`, `init_exec` and `kernel`
entries (PID 1 is a staged Mach-O and was previously not judged at all), and a
source it cannot read now raises instead of being silently dropped — dropping
it printed the same `HOST-EXTRACTED: 0` as having seen everything.

**Acceptance (checkable).**
- **Before P1 (the original measurement):** scanning `assets/usr/lib/system/`
  alone flags exactly **31** host-extracted files (`HOST-EXTRACTED: 31`,
  `NOT-IN-HOST-CACHE: 15`, of 46 present) and exits 1. Scanning all of
  `tools/bootlab` flags **44**: those same 31, plus three directly under
  `assets/usr/lib/` (`libSystem.B.dylib`, `libSystem.B.dylib.orig`,
  `dyld.orig` — the `.orig` copies sit in `assets/usr/lib/`, not in
  `assets/usr/lib/system/`), plus ten under
  `tools/bootlab/work/staging_backup/`. `work/` is gitignored build scratch,
  not staged content; only the 34 under `assets/` are in the tree.
- **After P1 (measured 2026-10-02, the second bullet below has been
  PROMISED and is now KEPT):** `provenance_scan.py --target assets` →
  `Mach-O files examined: 18`, `HOST-EXTRACTED: 0`,
  `NOT-IN-HOST-CACHE: 18`, `provenance_scan: PASS`. Scanning
  `assets-quarantine/` — the gitignored archive — still reports **34**, which
  is the control that proves the scanner would have found them and is not
  simply reporting zero because it stopped looking.
- The scanner exits nonzero on a deliberately planted copy of any one borrowed
  file (a negative control — see §8).

**Risk, and how it is closed.** The scanner depends on a *host-specific* path
(`/System/Volumes/Preboot/Cryptexes/...`). On a machine without that cache the
host UUID set cannot be built, so the check cannot run at all — and a check that
cannot run must not be allowed to report success. The scanner therefore **fails
closed**: a missing or unreadable host cache exits `2` (`EXIT_CANNOT_RUN`) with
a `NOT SATISFIED` banner, and it deliberately prints no `HOST-EXTRACTED: 0`
summary, since "not in the host cache" is vacuously true without a cache to
compare against. `closure_check.py` fails closed the same way on its own cache
load. The single escape hatch is `--allow-missing-host-cache`: an explicit
human waiver that exits 0 but still prints `NOT SATISFIED` and never `PASS`,
and whose report is explicitly labelled non-authoritative. The prior
fail-open default (plus the `--no-host-cache` / `--require-host-cache` pair)
was removed: it let a plain invocation on a machine with no host cache print
`NOT SATISFIED` and still exit 0. A pinned UUID list as an alternative input
remains a possible future refinement.

### P3 — Eliminate the silent stub class `DONE 2026-10-02 (producer + SDK gate); manifest wiring is P2's`

**Goal.** Remove the class of defect where a link succeeds against something
that cannot possibly work at runtime.

**Why it matters.** These are the *dangerous* cases — not the loud ones.

**Defect 1 — zero-byte dylibs — FIXED.** In the SDK:

```
$ ls -la $SDK/usr/lib/libncurses*
-rw-r--r--  1 max staff  0 Aug 31 07:06 libncurses.6.dylib
-rw-r--r--  1 max staff  0 Aug 31 07:06 libncurses.dylib
```

**Root cause found, and it was not the ncurses library.** The producer was a
`touch` on a Darwin-only branch of the BSD Makefile:

```
BSD/lib/ncurses/Makefile (before)
  .if "${.MAKE.OS}" == "Darwin"
  all:
      @echo "stub ncurses for Darwin host"
      touch ${RAVYN_SDKROOT}/usr/lib/libncurses.dylib ${SYSROOT_DIR}/usr/lib/libncurses.dylib
      touch ${RAVYN_SDKROOT}/usr/lib/libncurses.6.dylib ${SYSROOT_DIR}/usr/lib/libncurses.6.dylib
  .else
  ...the real configure + gmake build...
```

This is **the same defect that destroyed `libCrashReporterClient`**, which is
what `Libraries/check_sdk_stubs.sh` exists to catch, and the same one the
sibling `BSD/lib/libedit/Makefile` and `BSD/lib/libutil/Makefile` had already
had removed. It survived because the guard's only defence was a
`RECORDED_ZERO_BYTE_STUBS` **allow-list**, which reported both files as
`KNOWN-STUB` and exited 0. That is the deeper lesson: an allow-list converts a
detection into a permission, and two of its three entries have since turned out
to be unnecessary — `libedit.dylib` is now built for real (247,072 B) and
`libutil.dylib` too (18,936 B). **Only `libncurses` was ever genuinely unbuilt.**

> **A correction to this section's earlier claim.** It said the 0-byte files
> "**are** load-bearing in `manifest_dynamic.json` via `bin/ls`'s
> `LC_LOAD_DYLIB /usr/lib/libncurses.5.4.dylib`". **They are not.**
> `/usr/lib/libncurses.5.4.dylib` is a *third* name that neither stub ever
> provided, so the link could never have resolved — the stubs were not
> satisfying that reference, they were sitting next to it. Measured 2026-10-02:
> **zero** `LC_LOAD_DYLIB` references to `libncurses.dylib` or
> `libncurses.6.dylib` exist anywhere in the SDK or in the staged bootlab
> closure. Both files were unreferenced weight, and `assets/bin/ls` is not in
> the clean closure anyway (`manifest_cpmv.json` stages `work/ls_dyn`, whose
> only dependency is `libSystem.B.dylib`).

**Defect 2 — silent link-time success generally — already a hard failure.**
`closure_check.py` computes unstaged dependencies correctly and **already
includes them in its exit status**:

```python
# closure_check.py:989
ok = (not errors and not missing_deps and not unresolved and not rejects)
```

So "make an unresolved `LC_LOAD_DYLIB` a hard build failure" needs no new
checker — the computation exists and is load-bearing. What is still missing is
that nothing *requires* it to pass before an image is built; that wiring is
`closure_gate.py` in **P2**, owned by the other workstream, and deliberately
not duplicated here. Verified against the clean manifest:

```
$ python3 tools/bootlab/closure_check.py /tmp/manifest_cpmv.json --nm-check 0
  unstaged dependencies: 0
  VERDICT: PASS  (closure complete, all non-weak undefineds resolve, all staged dylibs valid)
closure_check: PASS
```

**Changes made.**

1. **`BSD/lib/ncurses/Makefile`** — the Darwin branch no longer `touch`es. It
   now fails loudly, naming the real prerequisite. Also fixed a latent
   `.endfor`/`.endif` mismatch at the end of the file (pre-existing; the `.if`
   had a stray `.endfor` before its `.endif`).
2. **The two 0-byte files deleted from the SDK.** Not built for real: ncurses'
   own build runs `configure` + `gmake`, is not on the Libsystem or
   dynamic-userland critical path, and adding a large unverified dependency to
   satisfy a link that does not exist is the wrong trade. The loud failure
   names the prerequisite if that ever changes.
3. **`Libraries/check_sdk_stubs.sh`** — the `RECORDED_ZERO_BYTE_STUBS`
   allow-list is **deleted**. A 0-byte file in `usr/lib`, `usr/lib/system` or
   `usr/local/lib/system` is now an unconditional `FAIL`. A new
   `DELIBERATELY_ABSENT_STUBS` check re-arms the other direction: if
   `libncurses.dylib` / `libncurses.6.dylib` reappear — at *any* size — that
   fails, because a stub being silently re-installed by an unaudited build path
   is the exact regression this script exists to catch.

**Acceptance — met, verified 2026-10-02.**

- `find $SDK -name '*.dylib' -size 0` → **empty**.
- `Libraries/check_sdk_stubs.sh $SDK` → `== OK: no stub regressions ==`,
  **exit 0**.
- Producer fixed: `bmake -m BSD/share/mk all` in `BSD/lib/ncurses` exits **1**
  with the FATAL message and **creates no files** (verified against a scratch
  `RAVYN_SDKROOT`).
- **Negative controls** — the checks are proven able to fail, not just to pass:

  | Control | Injected | Result |
  |---|---|---|
  | 1 | 0-byte `usr/lib/libncurses.dylib` into a scratch SDK | `FAIL: ... is 0 bytes -- a retired stub has returned` + `FAIL: usr/lib/libncurses.dylib is 0 bytes`, **exit 1** |
  | 2 | **non-empty** `usr/lib/libncurses.6.dylib` into a copy of the real SDK | `FAIL: ... has returned`, **exit 1** |

  Control 2 is the one that matters: an allow-list would have passed it.

**Risk (recorded, accepted).** `libncurses` may be genuinely needed by a BSD
utility later. Removing the stubs means that need now surfaces as a **loud
link failure** instead of a silent runtime no-op, and
`BSD/lib/ncurses/Makefile` names the fix. That is the intended trade. Nothing
in the current closure needs it, and no symbol was faked to make the gap
disappear.

### P4 — Close the two libobjc unwind symbols `DONE`

**Goal.** Drive the cpmv closure verdict from FAIL to PASS. This was the last
thing standing between the clean manifest and a green build.

**Status: DONE.** Fixed and independently re-verified 2026-10-02; the closure
now reports `VERDICT: PASS`.

**The gap.** `Libraries/objc4/libobjc.A.dylib` had two unresolved non-weak
undefined symbols:

```
$ nm -u Libraries/objc4/libobjc.A.dylib | grep -i unwind
___libunwind_Registers_x86_64_jumpto
___unw_getcontext
```

**Root cause: visibility, not missing code.** *An earlier revision of this
section claimed the two `.S` files "were never compiled" and that building
them would supply the symbol. **That was false**, and the evidence it rested
on was a misread command.* Both `.S` files were compiled and linked into
`libunwind.dylib` the entire time — as **private** symbols:

```
$ nm $SDK/usr/lib/system/libunwind.dylib | grep -E 'unw_getcontext|Registers_x86_64_jumpto'
000000000000c1f0 t ___unw_getcontext
000000000000c242 t ___libunwind_Registers_x86_64_jumpto
```

Lowercase `t` means *present, not exported*. The original check used
`nm -gU`, and `-U` filters private symbols out entirely — which is precisely
what made them look absent. The symbols were never missing; they were
unreachable.

The cause is LLVM's own `assembly.h`:

- `assembly.h:118` and `assembly.h:121` — `#if defined(__APPLE__)` defines
  `#define HIDDEN_SYMBOL(name) .private_extern name`
- `assembly.h:258-265` — `DEFINE_LIBUNWIND_FUNCTION` emits
  `.globl SYMBOL_NAME(name)` **and** `HIDDEN_SYMBOL(...)`, unconditionally on
  every non-AIX target

So every function in both `.S` files was emitted `.globl` **and**
`.private_extern`. ld64 localises `.private_extern` and drops it from the
export trie, so nothing outside the dylib could bind to it. The `Makefile`
rules had been building and linking these objects all along — the object file
is the proof:

```
$ nm -m Libraries/Libsystem/UnwindRegistersSave.o      # before the fix
0000000000000000 (__TEXT,__text) private external ___unw_getcontext
```

**Why Apple never needed to export these.** Apple's own `libunwind.dylib` has
the identical shape — same `.S` files, same private symbols — and it binds,
because `libobjc` and `libunwind` are both members of the **dyld shared
cache**. The cache is produced by linking every image as ONE link unit, in
which `.private_extern` resolves freely between members of that single unit.
ravynOS has no shared cache: every dylib loads standalone, and a private symbol
in a standalone dylib is unreachable. That is the entire delta, and it is why
this is a **visibility defect, not a missing-code defect**.

**The fix that landed.** Two files, both in `Libraries/Libsystem/`:

1. **NEW `unwind_asm_export.h`** — includes the real `assembly.h`, then
   `#undef HIDDEN_SYMBOL` / `#define HIDDEN_SYMBOL(name)`. This works because
   `DEFINE_LIBUNWIND_FUNCTION` expands `HIDDEN_SYMBOL` at the *point of use*,
   not the point of definition, and `assembly.h`'s `UNWIND_ASSEMBLY_H` include
   guard (`assembly.h:15-16`) makes each `.S` file's own
   `#include "assembly.h"` a no-op.
2. **`Makefile:140-166`** — added `-include ${.CURDIR}/unwind_asm_export.h` to
   the two existing `${CC} -c` rules and to both prerequisite lists.

No LLVM source was edited, and no stub, alias, or weakened symbol was
introduced. The vendored LLVM tree stays unmodified, so a future toolchain sync
cannot silently revert this. The `__TEXT,__text` bytes are **byte-identical**
to a plain unmodified upstream compile — only the linkage differs — and the
ABI-critical slot offsets in `__libunwind_Registers_x86_64_jumpto` (0 rax …
128 rip, 56 rsp) are untouched, because no instruction was touched.

> ### ⚠️ Rebuilding the `.S` files unchanged does nothing
>
> This is the trap that produced the original, false root cause recorded in
> this section. The `.S` sources were **already** being built. Recompiling them,
> cleaning the objects, or re-running the existing build rules **cannot** change
> the outcome — they will emit `private external` symbols again, exactly as
> before.
>
> **Do not "fix" this by hand-writing an alias, a stub, or a wrapper.** The code
> exists, is correct, and is upstream's own. Only its visibility was wrong, and
> only `unwind_asm_export.h` corrects that. If `nm` ever shows lowercase `t`
> here again, the `-include` has been lost or reverted — restore the
> `-include`, not the symbol.

**Acceptance — met, verified 2026-10-02.**

- `nm -gU $SDK/usr/lib/system/libunwind.dylib` lists both, now uppercase `T`:

  ```
  000000000000c242 T ___libunwind_Registers_x86_64_jumpto
  000000000000c1f0 T ___unw_getcontext
  000000000000c1f0 T _unw_getcontext
  ```

  Addresses are unchanged from the pre-fix build (`c242` / `c1f0`) — only the
  symbol type moved `t` → `T`. `_unw_getcontext` (single underscore) is still
  present, so nothing regressed.

- `nm -m Libraries/Libsystem/UnwindRegistersSave.o` no longer says "private
  external":

  ```
  0000000000000000 (__TEXT,__text) external ___unw_getcontext
  0000000000000000 (__TEXT,__text) external _unw_getcontext
  ```

- `closure_check.py /tmp/manifest_cpmv.json` reports `files affected: 0`,
  `PASS: 30  REJECT: 0`, `unstaged dependencies: 0`, `dangling N_INDR: 0`, and
  `VERDICT: PASS`.

**Risk (still binding).** `__libunwind_Registers_x86_64_jumpto` hard-codes
`unw_tdep_frame_t` slot offsets (0 rax … 128 rip, 56 rsp), and **those offsets
are the ABI**. The fix deliberately touches none of them — it changes linkage
only — but any future attempt to "simplify" this path by reimplementing it in C
would reintroduce a latent crash. The risk is confined to correctness of the
unwind path on crash and does not affect normal execution.

### P5 — Fix the `mach/` header shadowing `DONE 2026-10-02 — the fix is applied and the three-step verification passed; the diagnosis below is kept as the record of how it was found`

**Goal.** Make `#include <mach/...>` deterministic.

**The problem.** Multiple `mach/` header trees are on the include path and share
the same include guard, so whichever comes first wins and the rest are **never
read**. They are not interchangeable:

| Tree | Entries | Guard |
|---|---|---|
| `Developer/ravynOS.sdk/usr/include/mach` | 139 | `#ifndef _MACH_MACH_TYPES_H_` (line 73) |
| `$SDK/usr/include/mach` (build SDK) | 173 | `#ifndef _MACH_MACH_TYPES_H_` (line 73) |
| `Developer/ravynOS.sdk/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/mach` | 65 | `#ifndef _MACH_MACH_TYPES_H_` (line 73) |
| `Kernel/xnu/libsyscall/mach/mach` | **14** | mixed; `mach.h` is `#ifndef _MACH_H_` |
| `BSD/include/mach` | 61 | no such guard |
| `Developer/Default.xctoolchain/include/mach` | — | — |
| `Developer/Default.xctoolchain/cctools/include/mach` | — | — |

```
$ diff -q <PrivateHeaders>/mach/mach_types.h $SDK/usr/include/mach/mach_types.h
Files ... differ
```

They differ, so this is a real ambiguity, not a harmless duplicate.

> **Discrepancy.** The audit brief described "FOUR `mach/` header trees". At
> least **seven** exist, and the one the brief missed entirely is the one that
> actually wins for several headers: `Kernel/xnu/libsyscall/mach/mach`.

**Measured result: the build mixes two mach generations inside a single
translation unit.** A probe TU including `mach/{mach_types,mach,mach_init,
mach_error,host_priv,task,thread_act,ports,vm_prot}.h`, preprocessed with the
real `Libraries/Libsystem/Makefile` `-I` set through the real `isysroot-cc`,
resolves 63 headers:

```
$ REAL_CC=.../clang tools/bootlab/isysroot-cc -H -E --sysroot=$SDK \
    <the Makefile's exact -I list> /tmp/p5probe.c

.../SDK/usr/include/mach/mach_types.h          <- SDK generation
.../ravynos/Kernel/xnu/libsyscall/mach/mach/mach.h            <- xnu generation
.../ravynos/Kernel/xnu/libsyscall/mach/mach/mach_error.h
.../ravynos/Kernel/xnu/libsyscall/mach/mach/mach_init.h
.../ravynos/Kernel/xnu/libsyscall/mach/mach/mach_interface.h
.../ravynos/Kernel/xnu/libsyscall/mach/mach/vm_page_size.h
+ 58 more, all .../SDK/usr/include/mach/
```

So the answer is **per-header, not per-tree**: 58 of 63 come from the build
SDK's `usr/include/mach`, and **5 come from xnu libsyscall** because
`-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/mach` (`Libraries/Libsystem/Makefile:14`)
precedes `-I${RAVYN_SDKROOT}/usr/include` (`:18`). The three files that actually
differ between those two trees are `mach.h` (8,029 vs 7,342 B),
`mach_init.h` (3,836 vs 3,648 B) and `mach_interface.h` (2,035 vs 2,062 B);
`mach_error.h` and `vm_page_size.h` are byte-identical.

It is **not** tree-dependent either — the answer changes with the component:

```
$ ... --sysroot=$SDK -I$SDK/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders
      # i.e. the RUNTIME_FLAGS set, Libraries/Makefile:24-35
.../SDK/.../System.framework/Versions/B/PrivateHeaders/mach/mach_types.h   <- PrivateHeaders wins
.../SDK/usr/include/mach/mach.h
```

**Acceptance — met: the transcript above is the record.** Exactly one resolved
path per header, from a real compile under the real wrapper.

**Why no source was changed — the proposed fix does not work.**

The plan proposed "delete the shadowed trees or rename the guards so each tree
is independently reachable". **Renaming the guards was measured and is a no-op.**
The resolution of `<mach/x.h>` is decided by `-I` search order, *before* any
guard is consulted; the guard only suppresses a second read of a file that was
already read. Two headers under the same spelling cannot both be reached, so
distinct guards change nothing:

```
$ mkdir -p /tmp/p5guard/{a,b}/mach     # both define the SAME guard, different bodies
$ clang -E -Ia -Ib t.c | grep -oE 'int from_[AB]'
int from_A                              # only A; B is never even opened
$ sed -i '' 's/_MACH_H_/_MACH_B_H_/' b/mach/h.h   # give B a distinct guard
$ clang -E -Ia -Ib t.c | grep -oE 'int from_[AB]'
int from_A                              # unchanged
```

The same holds when one file is reachable under two spellings (`<mach/m.h>` and
`<m.h>`): clang dedupes on the resolved path, and a distinct guard does not
produce a second copy. So guard renaming **cannot** make a shadowed tree
reachable, and it carries a real downside — it removes the only thing that
currently makes an accidental double-inclusion harmless.

**Deleting a tree is the wrong move here, and measurably so.** `sync_mach()`
(`build-libraries.sh:412-448`) already declares the source of truth and copies
the in-repo SDK tree into the build SDK on every build. Measurement of that
state: **0 of 91 shared headers differ** between
`Developer/ravynOS.sdk/usr/include/mach` and `$SDK/usr/include/mach`; the build
SDK's extra 32 are generated MIG/server headers with no in-repo counterpart.
The in-repo and build trees are therefore **not rival trees — they are one
tree and its copy.** Deleting either breaks the build for no benefit, and the
documented alternatives were already tried and are strictly worse: the xnu
`EXPORT_HDRS/osfmk/mach` generation has no `suid_cred_*`, so `mach/task.h:846`
dies, and substituting xnu mach wholesale produces conflicting types for
`mach_task_is_self` (both measured, `build-libraries.sh:425-446`).

#### ✅ FIXED 2026-10-02 — the ambiguity is resolved, not merely characterised

The one-line fix identified above has now been **applied and verified**. The
flag is `-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall` — the **parent**, not the
`mach/` subdirectory (`Libraries/Libsystem/Makefile:23`, with the reasoning in a
comment above `CFLAGS`). `libsyscall/*.h` does not exist, so the parent
contributes no top-level headers of its own and `<mach/...>` now resolves
through `-isysroot` to the SDK's single generation. That is the same shape as
the working precedent at `isysroot-cc:196`, which drops `./mach/*` from two
other trees for exactly the same reason.

The mix is gone, not reduced:

```
$ REAL_CC=/Library/Developer/CommandLineTools/usr/bin/clang \
    ./tools/bootlab/isysroot-cc -H -E --sysroot="$SDK" \
    -I./Kernel/xnu/bsd -I./Kernel/xnu/libsyscall \
    -I./Kernel/xnu/libsyscall/wrappers -I"$SDK/usr/include" -I"$SDK/usr/local/include" \
    /tmp/p5v.c 2>&1 >/dev/null | grep -cE 'libsyscall/mach/mach/'
0
```

and every `mach/` header in the transcript now resolves to
`$SDK/usr/include/mach/`. The 5 previously-xnu headers — `mach.h`,
`mach_init.h`, `mach_error.h`, `mach_interface.h`, `vm_page_size.h` — come from
the SDK, alongside the 57 that always did. 63 headers, **one generation**.

**Verification — all three steps, in the required order, all passed:**

1. **Full `Libraries/Libsystem` build** — `tools/bootlab/build_all_libsystem.sh`,
   404s, `RESULT: PASS`: `stages passed 29, known-blocked 0, skipped 0,
   UNEXPECTED failures 0`, and the hard gate
   `Libraries/check_sdk_stubs.sh` **PASS**. This is the step that mattered:
   `libunwind`, `libobjc` and `libsystem_c` all build on this `-I` set, and none
   of them broke.
2. **Closure gate** — `python3 tools/bootlab/closure_check.py manifest_cpmv.json
   --nm-check 0` → `closure_check: PASS`, `VERDICT: PASS` on both sub-checks
   (host-cache provenance 0 extracted of 42 staged binaries; closure complete,
   all non-weak undefineds resolve, all staged dylibs valid). 0 unresolved
   weak undefineds, 0 LC_DYSYMTAB inconsistencies.
3. **P4 unwind symbols unchanged** —
   `nm -gU $SDK/usr/lib/system/libunwind.dylib`:

   ```
   000000000000c242 T ___libunwind_Registers_x86_64_jumpto
   000000000000c1f0 T ___unw_getcontext
   000000000000c1f0 T _unw_getcontext
   ```

   Both symbols are still exported `T` at the **unchanged** addresses `c242` /
   `c1f0`. The P4 defect is not reintroduced.

**What this does not claim.** The change is scoped to
`Libraries/Libsystem/Makefile`. The *component-dependence* noted above still
exists in principle: `RUNTIME_FLAGS` (`Libraries/Makefile:24-35`) puts
`System.framework/Versions/B/PrivateHeaders` on the path, so a library built
under those flags still sees a different `mach/` generation than one built under
`Libsystem`'s. That is a separate include-path decision about a different set of
components, not the shadowing fixed here, and it is left as it was found.

**Reproduce it now (read-only; touches nothing).** The `-I` list below is the
current `Libraries/Libsystem/Makefile` set. Change `libsyscall` back to
`libsyscall/mach` to reproduce the pre-fix split.

```
SDK=/Users/max/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk
printf '#include <mach/mach.h>\n#include <mach/mach_init.h>\n#include <mach/mach_error.h>\n#include <mach/mach_types.h>\n' > /tmp/p5v.c
REAL_CC=/Library/Developer/CommandLineTools/usr/bin/clang \
  ./tools/bootlab/isysroot-cc -H -E --sysroot="$SDK" \
  -I./Kernel/xnu/bsd -I./Kernel/xnu/libsyscall \
  -I./Kernel/xnu/libsyscall/wrappers -I"$SDK/usr/include" -I"$SDK/usr/local/include" \
  /tmp/p5v.c 2>&1 >/dev/null | grep -oE '^\.+ .*/mach/[a-z_]+\.h' | sed -E 's/^\.+ //' | sort -u
```

Expected now (verified 2026-10-02, post-fix): the output is the **full
transitive closure** — 63 `mach/` headers, because `mach.h` pulls in most of the
SDK tree — and **every one of them is under `$SDK/usr/include/mach/`**:

```
$SDK/usr/include/mach/mach.h
$SDK/usr/include/mach/mach_error.h
$SDK/usr/include/mach/mach_init.h
$SDK/usr/include/mach/mach_interface.h
$SDK/usr/include/mach/vm_page_size.h
... 58 more, all $SDK/usr/include/mach/ ...
```

For the record, the **pre-fix** transcript under
`-I./Kernel/xnu/libsyscall/mach` had these 5 `mach/` headers resolving to
`Kernel/xnu`, and `libsyscall/mach/string.h` alongside them:

```
./Kernel/xnu/libsyscall/mach/mach/mach.h
./Kernel/xnu/libsyscall/mach/mach/mach_error.h
./Kernel/xnu/libsyscall/mach/mach/mach_init.h
./Kernel/xnu/libsyscall/mach/mach/mach_interface.h
./Kernel/xnu/libsyscall/mach/mach/vm_page_size.h
./Kernel/xnu/libsyscall/mach/string.h
... 57 more, all $SDK/usr/include/mach/ ...
```

(That earlier grep pattern also matched `libsyscall/mach/string.h`, which is a
different header reached under the same `-I`; it is gone too.)

**Files involved, exactly:**

| Path | Role |
|---|---|
| `Libraries/Libsystem/Makefile:23` | **the line changed**: `-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall`, with the reasoning in a comment above `CFLAGS`; it no longer shadows `:31` (`-I${RAVYN_SDKROOT}/usr/include`) |
| `Kernel/xnu/libsyscall/mach/mach/` | the 14-header non-SDK generation that used to win; still on disk, simply no longer on the include path. **Not edited — `Kernel/xnu` is protected** |
| `tools/bootlab/isysroot-cc:196` | the working precedent (drops `./mach/*` from two other trees) |
| `tools/bootlab/build-libraries.sh:412-448` | `sync_mach()`, which already keeps the in-repo and build SDK trees identical |
| `tools/bootlab/MACH-HEADER-POLICY.md` | the separate per-header xnu-11215 migration census (a different question; not addressed here) |
| `Developer/ravynOS.sdk/usr/include/mach/` | the declared source of truth (91 `.h`); its build-SDK copy is byte-identical for all 91, and is now the **only** `mach/` generation Libsystem sees |

**Acceptance status: MET.** The plan's acceptance ("a recorded `clang -H`
transcript from a real compile showing exactly one resolved path per header") is
now satisfied for the fix, not only for the diagnosis: the post-fix transcript
above shows all 63 `mach/` headers resolving to one tree, and the full
build + closure gate + P4 `nm` cycle (§ above) passed after the edit.

### P6 — Close the remaining UNKNOWN classifications `CLOSED 2026-10-02 — libcompiler_rt closed on version and artifact; the 8 rebased host files are RETIRED by P1's quarantine, which is where an unrecoverable origin belongs`

**Goal.** No binary in the tree should have an unrecorded origin.

**Items.**
- **`libcompiler_rt.dylib` — LLVM version RESOLVED 2026-10-02: 17.0.6.**
  It is a genuine `Libraries/Makefile` build target (`Libraries/Makefile:139`,
  `RTOBJ = ${.OBJDIR}/llvm_target/compiler-rt/lib/ravynos/libclang_rt.osx.a`,
  guarded by `require_real_archive.sh`), **not** a lifted Apple binary. Its
  sources are vendored:

  ```
  $ strings Libraries/llvm_target/compiler-rt/lib/ravynos/libclang_rt.osx.a | grep llvm
  /Users/max/Projects/ravynos/Developer/Default.xctoolchain/llvm/compiler-rt/lib/builtins/absvdi2.c
  ... (all builtins)
  ```

  **The version is recorded in the repository, in the build system itself.**
  The root `Makefile` derives it from the vendored CMake project rather than
  hardcoding it, and exports it to every sub-make:

  ```
  Makefile:77  LLVM_VERSION_MAJOR != grep 'set.LLVM_VERSION_MAJOR' Developer/Default.xctoolchain/llvm/llvm/CMakeLists.txt | ...
  Makefile:81  LLVM_VERSION = ${LLVM_VERSION_MAJOR}.${LLVM_VERSION_MINOR}.${LLVM_VERSION_PATCH}
  Makefile:117 (exported to every SUBDIR)
  ```

  Reproducing that exact extraction:

  ```
  $ for v in MAJOR MINOR PATCH; do grep 'set.LLVM_VERSION_'$v \
      Developer/Default.xctoolchain/llvm/llvm/CMakeLists.txt | sed -E 's/^.* ([0-9]+).*$/\1/'; done
  17
  0
  6
  ```

  Four independent signals agree, which is the standard applied throughout
  this document — one from the source tree, one from the build configuration,
  one from a built tool, and one from a hardcoded path in the build:

  | # | Signal | Value |
  |---|---|---|
  | 1 | `llvm/CMakeLists.txt:15-23` sets `LLVM_VERSION_{MAJOR,MINOR,PATCH}` | 17 / 0 / 6 |
  | 2 | root `Makefile:77-84` extracts the same three and exports `LLVM_VERSION` | 17.0.6 |
  | 3 | the built compiler's own version string (`clang --version`) | `Apple clang version 17.0.6` |
  | 4 | `Libraries/Makefile:119` hardcodes the matching resource dir | `-isystem${TOOLCHAIN}/usr/lib/clang/17/include` |

  Signal 3 is the strongest, because it comes from the **binary that actually
  built this tree**, not from a declaration about it:

  ```
  $ /Users/max/Projects/build/.../Toolchains/Default.xctoolchain/usr/bin/clang --version
  Apple clang version 17.0.6
  Target: x86_64-apple-darwin25.6.0
  ```

  The upstream tag is recorded too, in
  `Developer/Default.xctoolchain/_PROVENANCE:13-15`: `swiftlang/llvm-project`
  at tag **`swift-6.0-RELEASE`** (Apache-2.0 WITH LLVM-Exception). Swift 6.0
  is built on LLVM 17, so tag and version are consistent — two more agreeing
  signals rather than a coincidence.

  So the **version** classification is **VENDORED_APPLE_OSS / LLVM 17.0.6**,
  recorded in `Developer/Default.xctoolchain/_PROVENANCE` (see §6 item 1).

  **The version is not the artifact — and as of the 2026-10-02 producer
  workstream, both questions now have answers.** They were conflated here, and
  the second is the more material one:

  | question | status 2026-10-02 |
  |---|---|
  | *Which LLVM version were the compiler-rt sources?* | **CLOSED** — 17.0.6, four agreeing signals. |
  | *Who builds `usr/lib/system/libcompiler_rt.dylib`?* | **CLOSED** — `Libraries/Libsystem/Makefile` now builds it in-repo from **170 vendored compiler-rt TUs** (`COMPILER_RT_TARGET = ${.CURDIR}/libcompiler_rt.dylib`, rule at `:405`). |

  Previously this row was **OPEN — an unrecorded artifact**: `Libraries/Makefile:8-9`
  defined `RTLIB`/`RTLIB2` and `mkdir -p`'d them, but the `compiler_rt` target
  only *verified* a prebuilt archive via `require_real_archive.sh`, and
  nothing linked the dylib. So the version told us what the sources would have
  been *had they been built here*, while saying nothing about the file actually
  staged — and that file could not be dropped, because `libSystem.B.dylib`
  re-exports it and `liblaunch`, `libsystem_pthread` and `libunwind` all link
  `-lcompiler_rt`.

  **That is no longer true, and the classification is now by construction rather
  than by assumption.** Verified from the produced file itself (§4 P0 for the
  commands):

  - `Libraries/Libsystem/libcompiler_rt.dylib`, 81,472 B, `x86_64`, built
    2026-10-02 08:36;
  - `nm -gU` → **529 exports**, the count the reference dylib had;
  - `install_name` `/usr/lib/system/libcompiler_rt.dylib`, matching the
    manifest's `path`, so it resolves in the image;
  - `LC_UUID A351AF58-A2BC-3C9E-BC62-20D2A5E407FF`, and its objects carry
    compile-time source paths under
    `Developer/Default.xctoolchain/llvm/compiler-rt/lib/builtins/` — the
    tracked, `_PROVENANCE`-recorded tree.

  So the classification is **VENDORED_APPLE_OSS**, established two independent
  ways: it is built from vendored sources *and* its export set matches the
  reference. The "version" and "artifact" questions now agree, which is the
  first time they have.
- **The rewritten host-extracted files — original build UNKNOWN. RETIRED by
  P1's quarantine, 2026-10-02.** Eight files (the rebased set in §3.2) were
  extracted from the host and then rewritten, so their UUIDs match the host but
  their contents no longer correspond to any Apple build. Their **original**
  provenance was recoverable only from the host cache's `.map` file, and that
  was never resolvable from the repository: a rebase destroys the on-disk
  evidence, and inventing an Apple build number for a file that was rewritten
  would be a guess presented as a fact. This stayed UNKNOWN **by construction**
  for exactly as long as P1 was deferred, and the record below says so rather
  than rounding it up to a partial pass.

  **What retired it was not an answer — it was removal from the tree.** The
  eight files were moved to `tools/bootlab/assets-quarantine/usr/lib/system/`,
  where the inventory records each one by sha256, `LC_UUID` and `__TEXT`
  vmaddr, and states plainly that its original Apple build is unknown and will
  stay unknown. P6's goal was "no binary **in the tree** should have an
  unrecorded origin"; the archive is where a file with an unrecoverable origin
  belongs, because it is gitignored and cannot reach a disk. The question was
  never made answerable. It was made irrelevant to the product, and the
  unanswerable part was written down instead of guessed at.

**Acceptance — MET, 2026-10-02.**

P6's goal is "no binary in the tree should have an unrecorded origin". Two
classes were open when this phase was written:

- **Closed earlier:** the compiler-rt **version** (17.0.6) — from the build
  system, the built compiler, the resource dir and the upstream tag, four
  independent signals that agree.
- **Closed 2026-10-02 (producer workstream):**
  `usr/lib/system/libcompiler_rt.dylib` is no longer an unrecorded artifact. It
  is built in-repo from 170 vendored TUs, exports the same 529 symbols, carries
  a fresh `LC_UUID`, and its objects name the tracked compiler-rt sources.
- **Closed 2026-10-02 (P1):** the eight rebased host-extracted files are out of
  the tree and recorded as unrecoverable-origin in the quarantine inventory.

**Nothing in `tools/bootlab/assets/` has an unrecorded origin.** The only file
in the quarantined set whose original build was never recoverable is
documented as such, in a gitignored directory that cannot reach a disk, which
is the strongest form of "recorded" that a destroyed piece of evidence admits
to. P6 is CLOSED.

### P7 — Write down the acceptable-borrowings policy `DONE 2026-10-02 — written in §4 P7, referenced from README.md and BOOT-PLAN.md, and now ENFORCED as well as stated`

**Goal.** Make the rule explicit so a future contributor does not have to
re-derive it or accidentally reverse it.

**The rule, in one sentence: borrowing Apple's _source_ is the project;
borrowing Apple's _built binaries_ is the defect.** For shared-cache extracts
the line between them is exactly the `LC_UUID` test in §2 — but P1 showed that
test has a blind spot, so the rule below is stated by **what a file is**, not
only by how it was obtained, and §4 P7 adds the two signals that close it.

#### The classes

| Class | Verdict | Rationale |
|---|---|---|
| **Host _tools_** from the Mac CLT / platform toolchain — `clang`, `ar`, `nm`, `strip`, `ld`, `otool`, `llvm-libtool-darwin`, `llvm-objcopy`, `byacc`, `flex`, `xcrun` | **Acceptable, and unavoidable** | `Developer/Default.xctoolchain` is a **source-only layout with no built tools**, so `bsd.*.mk`'s tool paths must be pinned to host binutils. On a Mac host there is no alternative. Pinned centrally in `tools/bootlab/build-libraries.sh:105-129`, not scattered per-Makefile. These produce **build outputs**; they are never staged into a runtime image. |
| **Vendored Apple open-source** — `Libraries/Libsystem`, `dyld`, `objc4`, `CrashReporterClient`, `BSD/`, `Kernel/xnu`, `Developer/Default.xctoolchain/llvm` | **The intended path** | This is the whole point of the project. Each import is recorded in a `_PROVENANCE` file with its upstream repo and tag. |
| **Host _headers_** | **Mild, case by case, must stay minimal** | The host CLT `usr/include` holds only `FlexLexer.h`, `module.modulemap` and `swift/`, so Apple SDK headers are **not** being copied in wholesale. The one real transcription is the `__DARWIN_ONLY_*` block in `Libraries/Libsystem/libsystem_c/include/sys/cdefs.h:53,55,57`, needed because the kernel's `cdefs.h` gates those macros behind `#ifdef KERNEL`. A build-configuration workaround, not code. |
| **Host Mac _runtime binaries_** — any Mach-O whose `LC_UUID` is in the host dyld shared cache, **or** which is a copy of a binary from the running host system, **or** which carries a signal no ravynOS build can produce (an `arm64e` slice, `LC_CODE_SIGNATURE`) | **Never acceptable** | The exact failure this audit was commissioned to find. Invisible to byte-scans after a rebase, undetectable at link time, and only fails at boot. The three-part definition matters because the `LC_UUID` clause alone would have passed `assets/bin/{cat,echo,ls}`. |

#### The exceptions that existed today — and what happened to them

The user chose on the morning of 2026-10-02 to keep the borrowed assets in the
tree (P1 option 3). That was a decision, not an oversight, and its terms are
written here so a future reader does not mistake it for an accident — or for
permission to add more. **All three have since changed. They are recorded in
the state each was left in, and in what replaced it, because a policy that
quietly loses its exceptions has also quietly lost its audit trail.**

1. ~~**The 31 host-extracted dylibs stay in `assets/`.**~~ **They did, until
   the same day.** What made that safe was never tolerance: P2's gate made them
   **detected and unstaged-by-construction** — the clean closure scanned 0
   host-extracted, the scanner flagged all 31 by `LC_UUID`, and the moment one
   entered a manifest or a glob the build failed. Then P1 moved all 57 affected
   files to the gitignored `assets-quarantine/`, and `assets/` scanned 0.
   **The policy is now enforced by absence, backed by the gate** — a stronger
   position than "refused unless someone names a clean manifest", and one that
   does not depend on remembering to name one.
2. ~~**`assets/` is a protected path.**~~ **It was, and it still is — but P1
   was authorized past it.** That is precisely why the change was a *decision*
   rather than a step, and why the files were moved rather than deleted. The
   protection now means the quarantine archive is not to be edited or
   republished, not that the contamination must stay.
3. **Build outputs are not runtime content.** Unchanged, and the one exception
   that survives: the host toolchain's binaries (LLVM 17.0.6 clang et al.,
   §4 P6) are legitimately used to *build*, and must never be *staged*. The
   distinction is the whole of this table — a host tool is a build tool; a host
   dylib in `usr/lib/` is borrowed runtime code. P1 did not touch it and must
   not.

**One new rule, added because P1 found a case this table did not cover.** The
"host runtime binary" row above is defined by the `LC_UUID` test, and that test
cannot see **host disk product** — a Mach-O copied off the running system
rather than out of the shared cache. `assets/bin/{cat,echo,ls}` were exactly
that: byte-for-byte copies of this host's `/bin/{cat,echo,ls}`, universal
`x86_64`+`arm64e`, carrying `LC_CODE_SIGNATURE`, and reported as *not*
host-extracted by every scan that ran against them. The class is therefore now
stated by its **consequences**, which are checkable without the cache:

| signal | why it is a rule and not a heuristic |
|---|---|
| **universal binary with an `arm64e` slice** | this repository targets x86_64 only. No build of ours has ever produced an arm64e slice. `dyld.orig` — the only arm64e file in the old contaminated region — is the proof that the signal was correct |
| **`LC_CODE_SIGNATURE` present** | we do not sign. A signed image in a ravynOS disk is Apple's |
| **not in the host dyld cache, but also not built from a tracked source** | the residual case, and the one no signal catches. It is caught by *process*: every manifest entry names a source, and `closure_gate.py` refuses one that resolves outside the repository |

#### What "staged" means, precisely

The rule is enforced at the boundary where content becomes a runtime image —
the manifest. A path is **staged** when any of these holds:

- it is a literal `"file"` or `"asset"` entry in a bootlab manifest;
- it is matched by a `"glob"` entry resolved against `assets/`;
- it is copied in by a staging script (`stage_dynamic_libs.sh`,
  `extract_assets.py`, `dsc_rebase.py`) or by `mkimage.py` walking a directory;
- it is the output of a build target that is itself staged.

`closure_check.py --image` extends the test past the manifest to the **image
bytes**, so a hand-copied binary that never appeared in any manifest is still
caught.

#### Enforcing it

- `tools/bootlab/provenance_scan.py` — builds the host-cache UUID set and
  exits nonzero on a hit. **Fails closed** (exit 2) when the host cache is
  unavailable, because a check that cannot run must not report success (§4 P2).
- `tools/bootlab/closure_gate.py` — refuses to build an image unless
  `closure_check.py` passes.
- `Libraries/check_sdk_stubs.sh` — the SDK-side gate: no 0-byte or near-empty
  dylib may sit where a real library belongs, and retired stubs may not return
  (§4 P3). An allow-list was removed here deliberately: a list that permits a
  0-byte dylib is a permission, not a detection, and it is what let two of its
  three entries go unbuilt for weeks.

**Acceptance — met 2026-10-02, and then enforced.** The policy is **written** and
referenced from `tools/bootlab/README.md` ("Acceptable borrowing") and
`BOOT-PLAN.md` (the companion-document pointer). Both references are in the
working tree; **nothing here is committed**, per the standing no-commit
instruction.

**What changed after it was written.** A written rule is only documentation,
and this project had already seen a rule that everybody agreed with fail to
hold: the "acceptable borrowing" table predated the 31 host-extracted dylibs by
months. P1 closed that gap by making the rule **structural** — the binaries the
rule forbids are out of `assets/` entirely, `assets-quarantine/` is gitignored,
and both gates above now run against every image the runner scripts build. A
policy that is enforced cannot be quietly reversed by the next person who adds
a glob; it takes an explicit, visible act to put an Apple binary back.

**Risk.** The remaining risk is not the policy but the **blind spot the policy
does not cover**: §2's test detects shared-cache extracts, and P1 found three
Apple binaries (`assets/bin/{cat,echo,ls}`) that are host *disk* product and
therefore invisible to it. The rule covers that case; the *instrument* does
not. Any future scanner should treat "universal binary with an `arm64e` slice"
and "LC_CODE_SIGNATURE present" as independent host-origin signals, because
this repository has no legitimate producer of either.


---

## 5. Living Document & Architectural Lifecycle

**This file is a living document, not a plan that was written once.** It began
as a one-time audit on 2026-10-02 and became the standing provenance record of
the project the same day, because the moment a rule exists but nothing keeps it
true, the rule decays into folklore. Everything below exists to stop that.

### What "living" means here — four commitments

1. **Phases are never deleted, only marked.** When a phase closes, its heading
   changes to `DONE` / `CLOSED` / `EXECUTED` and its evidence stays in place. A
   closed phase that still carries its own numbers is worth more than a tidy
   table: P1's status was flipped by the user on the strength of §3.3's
   measurement, and that measurement is only still there because closed phases
   are not rewritten.
2. **Every status claim carries the command that produced it.** The Appendix
   (§8) is an evidence index; a claim with no reproduction is a claim with no
   status. This is why superseded statements are marked superseded rather than
   quietly corrected — see the P0 row, which records both the original claim
   and the P1 sweep that invalidated it.
3. **A phase that reverses records the reversal, including the reasoning that
   changed.** P1 was DEFERRED on 2026-10-02 and EXECUTED later the same day.
   Both records exist. The deferral is not an embarrassment to be edited out;
   it is the record of *why* the decision was defensible at the time, and it is
   what made the reversal an evidence-based act rather than a change of taste.
4. **Discrepancies are stated, not smoothed.** This document contains
   "Discrepancy" call-outs where two counts disagree (the 45-vs-46 blob
   question, the 16-vs-17 snapshot count, the omitted eighth rebased file, the
   brief's "3 byte-identical" against the measured 2). Each was resolved by
   measurement. Removing them would make the file cleaner and less true.

### The state machine

Every phase moves through these states, and the state is in the heading, not in
a separate tracker that can drift:

```
OPEN ──▶ DEFERRED ──▶ EXECUTED ──▶ DONE / CLOSED
 │           │            │
 │           │            └─▶ SUPERSEDED   (a later phase replaced it)
 │           └─▶ REOPENED                 (the premise was disproved)
 └─▶ WRITTEN                            (the output is a decision, not a change)
 ```

| state | means |
|---|---|
| `OPEN` | identified, not started |
| `DEFERRED` | a decision was taken not to act, and the reasoning is recorded — *not* "we forgot" |
| `EXECUTED` | the change was applied; the section says what moved, where, and what it cost |
| `DONE` | the phase's work is complete and verified |
| `CLOSED` | the phase's goal is met and no further work against it is planned |
| `WRITTEN` | the deliverable is a written decision (a policy), not a code change |
| `SUPERSEDED` | a later phase made it moot; kept for the record |

**P1 demonstrates the interesting transitions.** `DEFERRED → EXECUTED` is the
one that matters most, and the mechanism that made it legitimate is written
into the phase: a deferral must state the condition under which it would be
reversed, and the reversal must show that the condition was met. P1's
deferral said the files were load-bearing; §3.3 measured that they were not,
and the reversal cites that measurement rather than asserting it. **A
deferral that does not name its reversal condition is not a deferral, it is a
silent rejection.**

### The prohibition: no host runtime binaries

Stated once, and it is the rule this whole document exists to defend:

> **Borrowing Apple's _source_ is the project. Borrowing Apple's _built
> binaries_ is the defect.** A host binary may be used to *build* ravynOS. It
> may never be *staged into* ravynOS.

Concretely, as of 2026-10-02:

- **`tools/bootlab/assets/` contains no host-extracted binary.** Measured:
  `provenance_scan.py --target assets` → `HOST-EXTRACTED: 0`.
- **`tools/bootlab/assets-quarantine/` holds everything that did,** byte for
  byte, with its identity recorded. It is gitignored, so quarantining is also
  de-publishing. Quarantine, never unrecoverable deletion: the forensic
  question ("which Apple build was that?") must still have an answer, and the
  answer must be one that costs nothing to keep.
- **Host *tools* remain legitimate and unrestricted** — `clang`, `ar`, `nm`,
  `strip`, `ld`, `otool` from the host Command Line Tools build ravynOS every
  day. `Developer/Default.xctoolchain` is source-only, so pinning the host
  CLT binutils is required, not a compromise. The line is *build* vs *stage*,
  and it is a real distinction rather than a rhetorical one.
- **The three blind spots are named** so a future scanner does not rediscover
  them: (1) the `LC_UUID` cache test cannot see host **disk** product, which is
  how `assets/bin/{cat,echo,ls}` survived every scan; (2) a **universal
  binary with an `arm64e` slice** cannot be a ravynOS build product — nothing
  in this repository targets arm64e; (3) `LC_CODE_SIGNATURE` has no legitimate
  source in a ravynOS-built image. These three are heuristics, not proof, and
  are recorded as such.

### The gates that keep it true

The prohibition above is a rule. These are what make it a property:

| gate | when | what it refuses |
|---|---|---|
| `provenance_scan.py` | on demand, over a tree or a manifest closure | any Mach-O whose `LC_UUID` is in the host dyld shared cache |
| `closure_check.py` | by the gate below | incomplete closure, unresolved non-weak undefineds, dylibs dyld2 rejects — and, by default, runs the provenance scan **fail-closed**: an unreadable host cache is a FAIL, never a pass |
| `closure_gate.py` | before every image the unprotected runner scripts build (`run.sh mkimage`/`full`, `run_dynamic_gate.sh`, `run_gated_loader.sh`, `run_minxfer.sh`, `run_applefree.sh`) | to build at all. Also runs a **relocatability preflight** that refuses any manifest entry resolving outside the repository, by name, whether or not the path exists here |
| `Libraries/check_sdk_stubs.sh` | SDK build | a 0-byte or near-empty dylib where a real library belongs. An allow-list of "known" stubs was **deleted**, not extended: a list that permits a stub is a permission, not a detection |

**Two properties of the gate design are worth preserving, because both were
learned the hard way.** First, *fail closed*: a check that cannot run must not
report success, so an unreadable host cache is exit 2 rather than exit 0. A
gate that degrades to "assume fine" is worse than no gate, because it looks
like one. Second, *one implementation*: `closure_gate.py` is a thin wrapper
around `closure_check.py`, with no second checker and no second opinion, so the
two cannot drift apart.

**What the gates do not cover, stated plainly.** A direct
`python3 mkimage.py --manifest M` bypasses `closure_gate.py` entirely. The gate
is reached by the scripts that call it, not by the image format. This is a
known limit, not an oversight, and closing it would mean changing `mkimage.py`,
which is a protected path.

### Roadmap forward

The provenance work is closed. What follows is where these guarantees have to
hold next, and what each phase will need from this document:

- **Phase 3 — Launchd. (Build side DONE; first dyld fault now root-caused,
  2026-10-02.)** The old text here read "PID 1 is currently a purpose-built
  static program (`work/init_shell`, `work/init_exec`)". **That is superseded.**
  A real `/sbin/launchd` is now built from the vendored BSD/sXin/launchd
  sources by `build_launchd.sh` (MH_EXECUTE, `LC_MAIN`, `DYLDLINK`, one
  `LC_LOAD_DYLIB` = `/usr/lib/libSystem.B.dylib`), staged via
  `manifest_cpmv.json`'s `sbin/launchd` entry, and the kernel reaches it:

      bsd_init: bsd_do_post - doneload_init_program: attempting to load
        /usr/appleinternal/sbin/launchd.development
      load_init_program: attempting to load /sbin/launchd
      pid 1 exited -- exit reason namespace 2 subcode 0xb, description none
      panic(cpu 0 caller 0xffffff8000abccb9):  initproc failed to start --
        exit reason namespace 2 subcode 0xb description: none

  **The kernel's PID 1 zero-RSP double fault is fixed** — the handoff now
  cleanly enters `load_init_program` instead of double-faulting. What remains
  is userspace, and the fault is *not* a dyld exit reason. `namespace 2` is
  `OS_REASON_SIGNAL` (`Kernel/xnu/bsd/sys/reason.h:113`), not `OS_REASON_DYLD`
  (which is 6, same file :117), and `subcode 0xb` is `11` =
  `SIGSEGV` (`Kernel/xnu/bsd/sys/signal.h:99`). So PID 1 segfaults; it does not
  exit through dyld's reason path, and no `DYLD_EXIT_REASON_*` code
  (`Libraries/dyld/include/mach-o/dyld_priv.h:433-440`) is involved. Those codes
  top out at 9 anyway, so `0xb` cannot be one.

  Symbolized against the loader at load base `0x10ec6b000` (solved from the
  six backtrace frames in `work/serial_full.log:553-558`, each landing on an
  instruction boundary of the staged `dyld` and on the frame's return address):

      dyldbootstrap::start+164            (the `_simple_dprintf(2, "DYLD-LOAD-BASE…")` call)
      __simple_dprintf+140
      __simple_vdprintf+94
      _write+20                           (0xbf2e0, the `retq` after the syscall stub)
      _cerror_nocancel+32                 <- CRASH, RIP 0x10ed25c50 == _cerror_nocancel+0x20

  `_cerror_nocancel+0x20` is `movq %gs:__framesize(,%rax,8), %rax` — a
  **`%gs:`-relative load with GS base still 0** (`movq` at file offset `0xbac50`;
  QEMU logs `GS =0000 0000000000000000` for every cpl=3 frame in
  `work/qemu_full.log`). CR2 = `0x8` is exactly `gs:0 + 1*8`, so this is not an
  inference. **The `DYLD-LOAD-BASE` print is what kills the loader**: `start()`
  calls `_simple_dprintf` *before* `rebaseDyld()` (and thus before
  `_dyld_setup_minimal_tsd()`), the write's syscall wrapper takes its
  `cerror` path, and `cerror` needs the `%gs:`-relative errno/framesize storage
  that does not exist yet. This is the same defect class already recorded at
  `Libraries/dyld/src/dyldInitialization.cpp:98-119` — "a correct mechanism in
  the wrong place" — recurring one call earlier: the TSD setup that fixes the
  `%gs` fault still lives *inside* `rebaseDyld`, which runs after the print that
  needs it. Evidence: `work/serial_full.log`, `work/qemu_full.log`.

  The provenance question Phase 3 raises is unchanged and still open: launchd
  loads launchd *agents and daemons* by path, so the closure stops being static
  and becomes whatever the plists name. That is a new instrument, not a bigger
  manifest.
- **Phase 4 — Kexts and APFS.** The kernel collections and the filesystem both
  pull in code that currently has no in-repo producer. This is where the
  "unrecorded artifact" class is most likely to reappear, because a filesystem
  driver is exactly the kind of thing that is tempting to import rather than
  write. P3 and P6 are the precedent: the answer was always to fix the
  producer, never to allow-list the artifact.
- **Phase 5 — Trust Cache.** Code signing stops being a build-time curiosity and
  becomes a runtime gate on what will execute. This document's LC_UUID reasoning
  is *not* sufficient there — a trust cache admits binaries by hash, and a
  hash does not tell you where a file came from. The provenance record here is
  what a trust cache entry has to be justified against.
- **Phases 6/7 — SMP and GUI.** Multi-cpu changes make provenance checks
  racy in a new way (a scan must see a settled image), and the GUI stack is the
  largest remaining consumer of frameworks whose binaries do not exist in-repo
  at all. Expect the first genuinely hard provenance question here: a
  framework is a *bundle* of binaries, and a per-binary rule may not compose.

**How to update this document.** Change the phase heading, update the summary
table at the top, add the command and its output to the Appendix, and — if the
change reverses or softens something previously claimed — leave the old claim
visible with a pointer to what superseded it. Do not delete a section because it
is now true; that is the only edit that makes this file worse.


---

## 6. Non-goals and protected paths

**Non-goals for this plan.**
- Kernel work. The real kernel gap — MIG ids 206 (`host_get_clock_service`) and
  3418 (`semaphore_create`) falling to the default dispatch path and returning
  `MIG_BAD_ID` (-303), consistent with the boot banner
  `mig_table_max_displ = 2` over 241 kobjects — is a **kernel** change and is
  out of scope. `clock_gettime` works via `mach_absolute_time`; `sleep` and
  `nanosleep` return `EINVAL`.
- Retaining any host-extracted binary "because it works". None of the 31 was
  load-bearing in the clean closure — and that was **measured** (§3.3) before
  P1 acted, not assumed afterwards.
- Rebuilding the boot image or running QEMU. All findings here are offline.

**Protected paths under the current working agreement.** These are not to be
modified without the user's explicit go-ahead:

| Path | Why protected |
|---|---|
| `Kernel/xnu` | Vendored Darwin kernel; heavily customised, out of scope for provenance work. |
| `tools/bootlab/boot.py` | Boot harness; proven-working control. |
| `tools/bootlab/mkimage.py` | Image builder; changing it risks every image at once. |

**Two paths left that list on 2026-10-02, by explicit authorization.** The
reasoning is kept here because the reasoning is the point — and because the
original reasons were vague enough to be worth correcting on the record:

| Path | Was protected because | Now |
|---|---|---|
| `tools/bootlab/manifest.json` | "the reference manifest" — which in practice meant it could not be cleaned, and therefore had to be refused | **edited.** Its `glob` over `assets/usr/lib/system/` was replaced by the same explicit closure `manifest_cpmv.json` uses; it now passes the gate |
| `tools/bootlab/assets/` **contents** | the staged-asset tree held 31 borrowed binaries, and moving them out was not authorized | **moved.** 57 files went to `assets-quarantine/`, gitignored, byte-identical, inventoried |

`mkimage.py` remains protected, and still defaults to `manifest.json`. `run.sh`
therefore passes `--manifest` explicitly rather than relying on that default —
which is also what keeps the gate and the image build naming the same manifest.
Editing `mkimage.py` was never necessary and was never attempted.

### The tension in P1 — deferred, then executed

P1 would remove files from `tools/bootlab/assets/`, which was protected. On the
morning of 2026-10-02 the user resolved it as **option 3, leave the files and
add P2's gate only**. That was a deferral, not a rejection, and it was
defensible at the time: removal had not yet been shown to be safe, and
`libsystem_kernel.dylib` did not build, so there was a genuine possibility that
something would turn out to need a host binary.

Later the same day the user reversed it, on the strength of a measurement
already in this document: *"Well if it isnt load bearing lets no longer use
apple binaries."* §3.3 had established that the live closure contained **0**
host-extracted binaries, so the premise the deferral rested on was false.
**Option 1 was chosen: quarantine rather than delete.** Option 2 (delete
outright, keeping only the snapshots' historical notes) was rejected, because a
forensic question about the incident must still have an answer, and an answer
that costs nothing to keep is worth more than a tidy tree.

The general lesson, now encoded in §5: **a deferral must state the condition
under which it would be reversed, and the reversal must show that the
condition was met.** P1's deferral named a premise; the premise was measured
false; the reversal cites the measurement. That is what separates a decision
from a change of taste, and it is why the deferral text was left in place when
P1 was executed rather than edited out.

**All eight phases are now closed or done:** P0 CLOSED, P1 EXECUTED, P2 DONE,
P3 DONE, P4 DONE, P5 DONE, P6 CLOSED, P7 DONE. **No phase awaits sign-off**,
and none is blocked on an approval. Nothing in this document is committed.

## 7. Open questions / UNKNOWN

Recorded so they are not silently re-derived.

1. **`libcompiler_rt.dylib` — RESOLVED on both counts, 2026-10-02.** Two
   questions were open about this file. Both are now closed, and the order in
   which they closed matters: closing the first did **not** settle the second.

   **(a) Which LLVM version were the compiler-rt sources? — CLOSED: 17.0.6.**
   The version *was* recorded in the tree all along, in the build system: the
   root `Makefile:77-84` derives `LLVM_VERSION_MAJOR/MINOR/PATCH` from
   `Developer/Default.xctoolchain/llvm/llvm/CMakeLists.txt` and exports them to
   every sub-make (`Makefile:117`). It yields 17 / 0 / 6, matching the built
   compiler's own `Apple clang version 17.0.6` and the
   `-isystem${TOOLCHAIN}/usr/lib/clang/17/include` in `Libraries/Makefile:119`.
   Upstream tag `swift-6.0-RELEASE` is in
   `Developer/Default.xctoolchain/_PROVENANCE:13-15`, consistent (Swift 6.0 is
   built on LLVM 17). Full derivation in §4 P6.

   The lesson for the next reader: this read as UNKNOWN only because the search
   looked for a *version manifest* rather than for the build system's own
   definition. Provenance is often already derived and exported rather than
   stored as a literal.

   **(b) Who builds `usr/lib/system/libcompiler_rt.dylib`? — CLOSED by a
   producer, 2026-10-02.** This was the more material question, and it was
   still open when (a) closed:

   | | state |
   |---|---|
   | **Before** | **No producer anywhere in this repository.** `Libraries/Makefile:8-9` defined `RTLIB`/`RTLIB2` and `mkdir -p`'d them, but the `compiler_rt` target only *verified* a prebuilt archive via `require_real_archive.sh`; nothing linked the dylib. The staged file was therefore an **unrecorded artifact** — a genuine P6-class UNKNOWN — and it could not be dropped, because `libSystem.B` re-exports it and `liblaunch`, `libsystem_pthread` and `libunwind` link `-lcompiler_rt`. |
   | **After** | Built in-repo by `Libraries/Libsystem/Makefile` from **170 vendored compiler-rt TUs** (`COMPILER_RT_TARGET = ${.CURDIR}/libcompiler_rt.dylib`, rule at `:405`). Verified from the produced file: 81,472 B, x86_64, **529 exports**, `install_name` matching the manifest `path`, a fresh `LC_UUID`, and object source paths under the tracked `Developer/Default.xctoolchain/llvm/compiler-rt/lib/builtins/`. The manifest entry is now repo-relative. |

   **Why the two had to be kept apart.** Knowing the toolchain version says what
   the sources would have been *had they been built here*; it says nothing about
   what built the file actually staged. Reporting (a) as though it closed (b)
   would have left a load-bearing binary in the image with no recorded origin
   while this document claimed the question was settled. It now has a producer,
   so its classification is **VENDORED_APPLE_OSS by construction** rather than
   by assumption.

2. **The rewritten host-extracted files' original builds — STILL UNKNOWN, and
   that is now the correct final answer rather than a gap.** Their UUIDs match
   the host cache, so they came from *a* host Apple build. Which build, and
   which cache subcache, is recoverable only from
   `dyld_shared_cache_x86_64h.map` on this machine. A rebase destroyed the
   on-disk evidence, and a guess would be indistinguishable from a measurement,
   so none was made.

   **P1 retired the question without answering it.** The eight files are in
   `assets-quarantine/`, gitignored, recorded by sha256 / `LC_UUID` / `__TEXT`
   vmaddr, with the honest answer — *host-extracted, then rebased, original
   build unknown and unknowable from the repository* — written into the
   inventory rather than filled in with a plausible build number. P6 is CLOSED
   on that basis: its goal was no binary **in the tree** with an unrecorded
   origin, and a file that cannot reach a disk and cannot be mistaken for ours
   is recorded as thoroughly as a destroyed fact admits to being.

3. **Which `mach/` tree wins — RESOLVED. P5 is DONE.** Measured and fixed
   2026-10-02. It was never one tree: the answer was per-header and
   **deterministic**, and the real build mixed two generations inside a single
   translation unit — 58 of 63 probed headers from the build SDK's
   `usr/include/mach`, and 5 (`mach.h`, `mach_init.h`, `mach_error.h`,
   `mach_interface.h`, `vm_page_size.h`) from `Kernel/xnu/libsyscall/mach/mach`,
   because that `-I` preceded the SDK's. The fix drops the `mach/` subdirectory
   (`Libraries/Libsystem/Makefile:23` now points at `libsyscall`), so **all 63
   resolve to the SDK's tree and 0 to xnu** — verified by the same `clang -H`
   probe, then by a full build, the closure gate and the P4 `nm` check (§4 P5).
   Guard renaming was measured to be a no-op and tree deletion to be wrong;
   neither was needed. One related question is untouched and out of scope: under
   the `RUNTIME_FLAGS` include set (`Libraries/Makefile:24-35`) rather than
   Libsystem's, `mach_types.h` still resolves to
   `.../System.framework/Versions/B/PrivateHeaders/mach`, so header resolution
   remains **component-dependent across components** — a different include-path
   decision, not the shadowing P5 fixed.

4. **The image-array layout — partially resolved, and worth writing down so
   nobody repeats the confusion.** Two different structures both use 32-byte
   records and both key on an address at offset +16:
   - the **address-only** images array at `0x3d8`, 3626 records, matching the
     3626 images in `dyld_shared_cache_x86_64h.map`;
   - a **UUID-bearing** array whose records hold a non-zero `uuid[16]` at +0 —
     this is the one the test needs. `0x1de48` is a valid position in it, but it
     is record 3796, **not** the start.

   A strict "longest ascending run" detector latches onto the address-only array
   (whose UUIDs are all zero) and reports the right *count* with no *UUIDs*.
   That is a silent failure. The superset approach in §2 avoids it.

5. **Audit methodology correction — do not repeat.** A 2048-byte-aligned page
   index over the shared cache **under-counts**, because shared-cache images are
   not all 2048-aligned. It reported **24** host-extracted files. The correct
   answer is **31**. Any future index of the cache must be record-aligned, not
   page-aligned.

6. **Whether anything still depends on the quarantined files.** A `grep` sweep
   over manifests, scripts and Makefiles is needed before P1. Not yet done;
   P1's risk assessment depends on it.

---

## 8. What a wrong conclusion would look like

The obvious way to get this wrong is to build a scanner, trust that it found
something, and never check that it *would* have found it. Two controls are
required before any number in this document is treated as settled:

- **Positive control.** The scanner must be able to flag a known-borrowed file.
  It does: it flags 31 plus `libSystem.B.dylib`, `libSystem.B.dylib.orig` and
  `dyld.orig`, and each hit was corroborated by the independent `__TEXT` vmaddr
  signal (§3.2). Two unrelated signals agreeing is the standard applied
  throughout.
- **Negative control (P2) — DONE, and run in its hardest form.** The scanner
  must be able to *fail*: plant a borrowed file and confirm the gate rejects
  it. Two controls were run on 2026-10-02, and the second is the one that
  matters, because it isolates the image-bytes path from the source path.

  1. *Refusal control.* `./run.sh mkimage work/gate_refuse.img --manifest
     manifest.json` → exit 1, `closure gate: REFUSED`, and
     `work/gate_refuse.img` **does not exist** afterwards. The gate stops
     before image construction rather than after.
  2. *Image-bytes control.* An image was built from `manifest_cpmv.json` with
     the unchanged `mkimage.py` (`verify OK: 46 files`, exit 0). The
     `LC_UUID` of `usr/lib/dyld` **inside the image only** was then
     overwritten with the one from `assets/usr/lib/system/libcache.dylib` —
     16 bytes, in place, nothing else changed. Results:

     | check | bytes judged | verdict |
     |---|---|---|
     | `closure_check.py manifest_cpmv.json --nm-check 0` | staged sources | `PASS`, `HOST-EXTRACTED: 0` |
     | `closure_check.py manifest_cpmv.json --image <dirty> --nm-check 0` | the image | `FAIL`, `HOST-EXTRACTED: 1`, names `usr/lib/dyld` |

     Same manifest, same tree, 16 bytes apart: the source scan correctly says
     nothing is borrowed, and the image scan correctly says something is.
     That is the proof that the `--image` verdict is made about the artifact
     and is not the source verdict relabelled — and it is the control that
     would have failed had the change been cosmetic.

- **Negative control for the P0 relocatability preflight — run 2026-10-02.**
  Strictness here means the gate refuses an out-of-repo source *whether or
  not it exists on the machine running it*, because existence is a property
  of this workstation, not of the manifest. A control that only ever used a
  path absent from this host could not tell that rule apart from the old
  only-if-missing one, so the decisive case was run with the sibling build
  tree **populated**:

  | control | manifest source | exists on this host? | result |
  |---|---|---|---|
  | external file | `/tmp/closure_gate_negctl_external.txt` | yes | `REFUSED (relocatability preflight)`, exit 1 |
  | sibling path, absent | `../../../build/CLOSURE_GATE_NEGCTL.txt` | no | `REFUSED (relocatability preflight)`, exit 1 |
  | **sibling path, present** | `../../../build/CLOSURE_GATE_NEGCTL.txt` | **yes — file created for the test** | `REFUSED (relocatability preflight)`, exit 1, printed `exists here, still refused` |
  | missing manifest | — | — | `cannot read manifest …: No such file or directory`, exit 1 |
  | malformed JSON | — | — | `cannot read manifest …: Expecting property name`, exit 1 |
  | truncated JSON | — | — | `cannot read manifest …: Expecting value`, exit 1 |
  | directory as manifest | — | — | `cannot read manifest …: Is a directory`, exit 1 |

  The third row is the one that carries the weight: under the previous
  only-if-missing rule it would have **exited 0** and the image would have
  been built, which is exactly how a repo-relative manifest could look clean
  on the machine that produced it and fail on a fresh checkout. All controls
  were scratch files outside the repository (plus one deliberately created
  file in the sibling build tree) and were removed afterwards; no repository
  file was involved. The positive side is the same two manifests in normal
  use: `manifest_cpmv.json` (46 entries) and `manifest_dynamic.json` (40) each
  resolve **0** sources outside the repository and pass the full gate, exit 0.


- **Negative controls for the P3 SDK gate — run 2026-10-02.** A guard that has
  only ever printed `OK` proves nothing, so `Libraries/check_sdk_stubs.sh` was
  made to fail on purpose, in both directions, after the allow-list it used to
  carry was deleted:

  | control | injected | expected by an allow-list | actual |
  |---|---|---|---|
  | 1 | a 0-byte `usr/lib/libncurses.dylib` | pass (it was `KNOWN-STUB`) | `FAIL: … is 0 bytes -- a retired stub has returned`, exit 1 |
  | 2 | a **non-empty** `usr/lib/libncurses.6.dylib` | pass (size > 0) | `FAIL: … has returned`, exit 1 |

  Control 2 is the one that distinguishes a *check* from a *filter*: any
  size-based test passes it. It fails now because the name is retired, which
  is the property that actually matters — a stub re-installed by an unaudited
  build path must not slip back in.

A related trap, recorded because it cost an audit pass: **a test that shares the
bug cannot find the bug.** The `LC_UUID` test is independent of file size, page
alignment and content, which is precisely why it catches the eight rebased files
that a byte-scan misses.

---

## Appendix — evidence index

| Claim | Command / location |
|---|---|
| 31 host-extracted dylibs | LC_UUID scan, `assets/usr/lib/system/`; §3.2 list |
| Independent corroboration | `__TEXT` vmaddr vs `dyld_shared_cache_x86_64h.map` |
| Live closure 0/41 | LC_UUID scan over the 41 manifest_cpmv source files |
| SDK 0/74 | LC_UUID scan over `$SDK/usr/lib/system/` + `$SDK/usr/lib/` |
| cpmv closure PASS-shaped | `closure_check.py /tmp/manifest_cpmv.json --nm-check 0` |
| dynamic closure FAIL | `closure_check.py manifest_dynamic.json --nm-check 0` |
| Build path is Apple OSS | `Libraries/Libsystem/Makefile:245,259`; `_PROVENANCE` |
| 3 functions are new work | `git log --all -S<fn> -- Libraries/Libsystem` → empty |
| No `*at` declarations | `grep` over `libsystem_c/include/` → 1 comment hit |
| 2 unwind symbols were unreachable (now resolved) | `nm -u Libraries/objc4/libobjc.A.dylib` |
| `.S` sources present | `Developer/Default.xctoolchain/llvm/libunwind/src/UnwindRegisters*.S` |
| Root cause: `.private_extern`, not missing code | `assembly.h:118,121` + `:258-265`; `nm -m UnwindRegistersSave.o` |
| Fix: `HIDDEN_SYMBOL` override via `-include` | `Libraries/Libsystem/unwind_asm_export.h`; `Makefile:140-166` |
| Both symbols now exported `T` at unchanged addresses | `nm -gU $SDK/usr/lib/system/libunwind.dylib` → `T` @ `c242`/`c1f0` |
| Closure PASS after P4 | `closure_check.py /tmp/manifest_cpmv.json` → `VERDICT: PASS`, `files affected: 0` |
| Zero-byte dylibs were the ncurses `touch` (not ncurses itself) | `BSD/lib/ncurses/Makefile` Darwin branch (pre-fix); git: `c23b2d2a8b` added that branch |
| Nothing referenced libncurses (so removal was safe) | `otool -L` sweep over every SDK dylib + staged asset: **0** hits for `libncurses{,.6}.dylib` |
| Producer no longer stubs; fails loudly | `cd BSD/lib/ncurses && bmake -m ../../share/mk all` → FATAL, exit 1, no files created |
| Allow-list deleted; 0-byte is now an unconditional FAIL | `Libraries/check_sdk_stubs.sh:156-224`; `find $SDK -name '*.dylib' -size 0` → empty |
| Negative control 1 (0-byte retired stub returns) | inject `: > $SCRATCH/usr/lib/libncurses.dylib` → `FAIL: …a retired stub has returned`, exit 1 |
| Negative control 2 (non-empty retired stub returns) | inject non-empty `usr/lib/libncurses.6.dylib` into a real-SDK copy → `FAIL: …has returned`, exit 1 |
| LLVM version is 17.0.6 (source) | `llvm/llvm/CMakeLists.txt:15-23` → 17 / 0 / 6 |
| LLVM version is 17.0.6 (build system) | `Makefile:77-84` extracts it; `:117` exports `LLVM_VERSION` to every SUBDIR |
| LLVM version is 17.0.6 (the binary that built this) | `Default.xctoolchain/usr/bin/clang --version` → `Apple clang version 17.0.6` |
| LLVM version is 17.0.6 (hardcoded resource dir) | `Libraries/Makefile:119` → `-isystem${TOOLCHAIN}/usr/lib/clang/17/include` |
| Upstream tag consistent with 17.0.6 | `Developer/Default.xctoolchain/_PROVENANCE:13-15` → `swift-6.0-RELEASE` |
| Which `mach/` tree wins: **63 SDK / 0 xnu libsyscall** (post-fix) | reproduce command in §4 P5 — `clang -H -E` through `isysroot-cc` with `Libraries/Libsystem/Makefile`'s `-I` set; `grep -cE 'libsyscall/mach/mach/'` → `0`, and every resolved path is under `$SDK/usr/include/mach/` |
| The 7th mach tree the brief missed | `Kernel/xnu/libsyscall/mach/mach` — 14 headers, and the one that **used to** win `mach.h`; still on disk, no longer on Libsystem's include path |
| Guard renaming cannot fix the shadowing | `/tmp/p5guard`: distinct guard on the 2nd tree → resolution unchanged (`int from_A` either way) |
| In-repo and build-SDK mach trees are one tree + a copy | 0 of 91 shared headers differ (`cmp` sweep); `sync_mach()` at `build-libraries.sh:412-448` |
| P5's pre-fix mix compiled anyway, and nothing enforced it | `clang -fsyntax-only` on `mach.h + mach_init.h + task.h + thread_act.h` under the real flags → clean. Superseded: the mix no longer exists, and the full build now enforces the single-generation path |
| P5's one-line fix is APPLIED and VERIFIED | `Libraries/Libsystem/Makefile:23`; `build_all_libsystem.sh` → `RESULT: PASS` (29 stages, 0 failures, hard gate PASS, 404s); `python3 tools/bootlab/closure_check.py manifest_cpmv.json --nm-check 0` → `closure_check: PASS`; `nm -gU …/libunwind.dylib` → `000000000000c242 T ___libunwind_Registers_x86_64_jumpto`, `000000000000c1f0 T ___unw_getcontext` — unchanged |
| compiler_rt's in-tree build dir is no longer an untracked leak | `Libraries/.gitignore` now ignores `/Libsystem/compiler_rt/`; `git status --porcelain Libraries/Libsystem/compiler_rt/` → empty. `${.OBJDIR}` resolves to `${.CURDIR}` for Libsystem (its `config.x86_64.normal.h` and `.dylib`s land in-tree), so that directory *is* `${RT_OBJDIR}` — including `include/libkern`, a symlink into the machine-local build SDK that is broken on any other checkout |
| The gate's DEFAULT verdict used to be a refusal | **SUPERSEDED 2026-10-02 (P1).** It read `run.sh full` gates `${RAVYN_MANIFEST:-manifest.json}`, which staged the borrowed region and was refused. The default is now `manifest_cpmv.json` and passes; `RAVYN_MANIFEST` still overrides |
| **`assets/` is clean after P1** | `cd tools/bootlab && python3 provenance_scan.py --target assets` → `Mach-O files examined: 18`, `HOST-EXTRACTED: 0`, `NOT-IN-HOST-CACHE: 18`, `PASS` (was 34 host-extracted) |
| **All three manifests pass after P1** | `python3 closure_gate.py manifest_cpmv.json` → `PASS -- continuing`; same for `manifest_dynamic.json` and `manifest.json`. `manifest.json` reported **32** host-extracted and `REFUSED` before |
| **The image still builds with the new default** | `./run.sh mkimage work/boot.img` → gate `PASS`, `manifest: …/manifest_cpmv.json`, `wrote work/boot.img (12614 clusters used of 130301)`, `verify OK: 46 files, 59 tree entries, all content hashes match`, `wrote work/boot.img.digests (46 digests)`, exit 0 |
| **57 files moved, byte-identical** | `find tools/bootlab/assets-quarantine -type f ! -name QUARANTINE_INVENTORY.txt \| wc -l` → 57; spot-checked sha256 (`libcache.dylib` `d9322a93…`, `bin/echo` `d2d4d70e…`) match the inventory verbatim |
| **The quarantine cannot be published** | `git check-ignore -v tools/bootlab/assets-quarantine/usr/lib/dyld.orig` → `tools/bootlab/.gitignore:12:assets-quarantine/` |
| **Host disk product is invisible to the UUID test** | `python3 provenance_scan.py --target assets/bin --target assets/System` → `HOST-EXTRACTED: 0` on the three Apple `/bin` copies, before *and* after the quarantine. They were identified by `assets/.gitignore`'s recorded slice UUIDs (`x86_64 8D210E93-…`) instead |
| libcompiler_rt.dylib is produced in-repo from 170 vendored TUs | `Libraries/Libsystem/Makefile` `COMPILER_RT_TARGET`/`:405`; TU count independently recounted: `sed -n '/^COMPILER_RT_SOURCES = /,/^$/p' … \| grep -oE '[A-Za-z0-9_]+\.[cS]\b' \| sort -u \| wc -l` → 170 |
| the produced libcompiler_rt.dylib matches the reference | `nm -gU Libraries/Libsystem/libcompiler_rt.dylib \| wc -l` → 529; `otool -D` → `/usr/lib/system/libcompiler_rt.dylib`; `lipo -info` → x86_64; 81,472 B |
| its provenance is vendored source, not a host binary | `otool -l` LC_UUID `A351AF58-…`; `strings` shows `Developer/Default.xctoolchain/llvm/compiler-rt/lib/builtins/*.c` compile-time paths |
| libunwind.dylib redirected in-repo, P4 not regressed | `UNWIND_TARGET = ${.CURDIR}/libunwind.dylib` (`:199`); `nm -gU Libraries/Libsystem/libunwind.dylib` → `T` @ `c242`/`c1f0`, same as P4 |
| every manifest entry is now repo-relative | both entries read `../../Libraries/Libsystem/…`; only `/Users/` hits left are prose at manifest_cpmv.json lines 22 and 30 |
| Unstaged deps are already a hard FAIL | `closure_check.py:989` — `ok = (not errors and not missing_deps and …)` |
| `libSystem.dylib` symlink correct | `ls -la $SDK/usr/lib/libSystem.dylib`; `sha256` vs `Libraries/Libsystem/libSystem.B.dylib` (`19e377ab…`) |
| `dyld.orig` is universal | `lipo -info` → `x86_64 arm64e`. **Now quarantined**: `assets-quarantine/usr/lib/dyld.orig`, sha256 `4fc23ac1…` |
| 17 dyld snapshots | **Pre-P1:** `ls assets/usr/lib/dyld.PRE* \| wc -l` → 17. **Post-P1:** `ls assets-quarantine/usr/lib/dyld.PRE* \| wc -l` → 17; each is described individually in `QUARANTINE_INVENTORY.txt` §1, with its probe strings measured (`CHAINPROBE` first appears in `dyld.PREV-NOALLOC`, which is what dates the CHAINPROBE build) |
| `mach/` guard collision exists | `grep -m1 MACH_MACH_TYPES_H_` across trees; `diff -q` shows they differ |
| `mach/` guard collision is NOT the cause of the split | resolution is decided by `-I` order; a control TU with distinct guards resolves identically (§4 P5) |