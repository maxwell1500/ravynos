# BOOT-PLAN

**The single living document for "how do we get to a booting system."**
Maintained across many rounds by several people. Readable by someone who has seen
none of this work. If a number in here has no method next to it, it is not
evidence.

Last updated: **2026-09-27**

## 1. The goal

> Build a ravynOS disk image whose `/bin/echo` and `/bin/cat` are **source-built
> dynamic (dylib-linked) binaries** that reach `main()` and exit cleanly, with
> **PID 1 alive** on the other side. Not a static binary that happens to print
> something; not an Apple binary staged from a shared cache. Ours, built from
> this tree's sources, loaded by our dyld, in a closure we assembled.

Everything below is in service of that sentence. When a change does not move
that sentence, it is not progress on this project.


## 2. Current state, measured

Every row carries the date it was measured and how. Rows marked **UNVERIFIED**
are claims, not results.

| # | Measurement | Value | Measured | Method |
|---|---|---|---|---|
| 1 | Driver baseline of record — **SUPERSEDED, PENDING THE RUN IN FLIGHT** | **23 passed / 3 known-blocked / 0 skipped / 2 UNEXPECTED** (`libdispatch`, `libsystem_darwin`); `check_sdk_stubs.sh` **PASS**; ~511 s | 2026-09-27 | `tools/bootlab/build_all_libsystem.sh`, **full** run, serial, alone, **zero builders confirmed**. **Stands as the last measured baseline. `libdispatch` has since been shown to build and link (row 16) and `libsystem_darwin` is fixed at the source level (row 18), so a new full run is in flight — but NO replacement number is written here until that run reports one. A predicted baseline is not a measurement.** |
| 2 | Baseline re-verification | byte-identical result after the `isysroot-cc` fix | 2026-09-27 | same, re-run; argv capture shows fix neither absent nor over-broad |
| 3 | `--quick` run validity | **skips 3 stages, one of which does not build** | 2026-09-27 | stage list diff vs full run |
| 4 | `libsystem_c` load closure — **BY SYMBOL TABLE ONLY; loadability is UNMEASURED and currently NEGATIVE** | **272 undefined / 267 satisfied / 5 unprovided *by symbol table*** (was 133). Of the 272, **143** by `libsystem_kernel` alone. ~~272 / 0~~ and ~~272 / 12~~ both **STRUCK** — the first a contaminated subtraction, the second measured before `libdyld` was reinstalled. ⚠️ **`nm` reads the SYMBOL TABLE; dyld reads the EXPORT TRIE, and ours are empty** (§7.6) — so this row **cannot** be evidence the closure resolves | 2026-09-27 | `nm`, never a link. A = `nm -u` symbol lines only, sorted, minus `dyld_stub_binder`. P = **`nm -gjU`** over the transitive `otool -L` closure, union, sorted. unprovided = A − P. **All 35 SDK dylibs copied and hashed first (35/35 byte-identical)** — md5s `libsystem_kernel 71051fb8…`, `libsystem_c 3babd71f…`, `libdyld 8277f4af…`. Install names resolve inside the ravynOS SDK only. **⚠️ AND: an exit code is not a gate, and `nm` is not a gate either** |
| 5 | `libsystem_kernel.dylib` | **LINKS AND INSTALLS.** 603 objects, 0 compile errors, 1693 warnings, 137 s, clean build | 2026-09-27 | all `.o`/`.a`/`obj`/`sys` deleted first; `ps` verified clear of bmake/build-libraries/isysroot-cc/llvm-libtool immediately before **and after**; rc=0 |
| 6 | `libsystem_kernel.dylib` in SDK | **617,080 B**, Mach-O 64-bit x86_64 dylib (was an **8,064 B** placeholder). **1,470** exports (`nm -gjU`), **12** undefined, ⚠️ **12 UNPROVIDED** against the **18-dylib** closure. ~~1,483 / 0 unprovided~~ **STRUCK — see §7.5** | 2026-09-27 | measured on the **installed artifact** with `nm`, not the archive and not the link's exit code. Closure size 18 independently reproduced by walking `otool -L`. **Note: 12 excludes `dyld_stub_binder`**, which is linker-synthesized |
| 7 | `libdyld.dylib` in SDK | **BUILT FROM SOURCE, and HARDENED — not "fixed".** **987,968 B**, `LC_DYLD_EXPORTS_TRIE` datasize **5,464** (was **0**), `LC_DYLD_CHAINED_FIXUPS` 1, `LC_DYLD_INFO_ONLY` **0** (was 1). **205** exports, **unchanged** — the flag changed the ENCODING, not the symbol set | 2026-09-27 | `otool -l` on the artifact in the generated SDK. ⚠️ **`-Wl,-fixup_chains` is forward-hardening, NOT a fix for an observed defect**: dyld in this image honours `LC_DYLD_INFO_ONLY` and resolved a trie-less `libsystem_c` fully (§7.8). Kept for the future risk that dyld drops the old format. **⚠️ NOT STAGED and NOT LOADED — the boot image still has the Apple extract at 385,783 B** |
| 8 | `libdyld` real build — ✅ **DONE (2026-09-27)** | **1 → 28 objects. The library LINKS and INSTALLS** (row 7): **987,968 B**, **205** exports, **10** `upward` reexport dependencies on the real `libsystem_*` dylibs, modern encoding (row 7). Frontier is off compile entirely | 2026-09-27 | clean-slate build, `ps` verified empty immediately before, distinct log, input mtimes recorded, `bmake -V LDFLAGS` checked first. ⚠️ **Two of the author's own measurements disagree and are recorded UNEXPLAINED**: a clean build's artifact carries three undefined symbols while a manual re-link from the same archive does not; and the build reports **28 objects for 27 `SRCS` entries**. **The remaining build failure is a different target** — the `dyld` TOOL in SUBDIR, on `dyldSyscallInterface.h:135: amfi_check_dyld_policy_self` — not the library |
| 8c | `libdyld`'s duplicate symbols are **correct behaviour reported correctly** | `Libraries/dyld/src/glue.c:145-158` **deliberately** defines all four handlers (source comments say so, each calls `dyld::halt()`) — a bootstrap linker refusing libc++'s exception runtime, which would abort through a runtime that does not exist yet. ld's warnings name **four** pulled members (`exception.o`, `new.o`, `typeinfo.o`, `verbose_abort.o`), so `exception.o` is being *dragged in*, not genuinely needed twice | 2026-09-27 | verified in the source and in the archive. **Not fixed** — options differ in kind (link libc++ selectively, or supply personality/unwind so `exception.o` is never demanded). Most dyld TUs already build `-fno-exceptions` |
| 8b | The two dyld changes are **jointly necessary** | shim opt-in alone: 1 error. `mach-o/` strip alone: 20. Both: **0**. Each defect **hides** the other — with shims off, the 20 shim-class errors stop compilation before `APIs.cpp:338`, so `PLATFORM_IOSMAC` appears **0 times** | 2026-09-27 | full 2x2, both factors, matched overlays. This is why a single combined build could not have attributed a moved count to either change |
| 8d | ✅ **the 3 unprovided symbols are DEFINED *and IN THE EXPORT TRIE*. Residual 45 → 6 → 4 → 2, in four dated steps — and BOTH 42 and 4 are STRAWN** | `_Znwm`, `_ZdlPv`, `__ZNSt3__122__libcpp_verbose_abortEPKcz` are all `T` in the installed artifact. **`dyld_info -exports` on the current artifact shows `__Znwm` @0xDE0 and `__ZdlPv` @0xE30 in the trie** — the structure dyld actually resolves from, not the symbol table `nm` reads. `__libcpp_verbose_abort` is correctly **absent from the trie** (hidden by `-unexported_symbol,__ZNSt3*`): it is satisfied *inside* libdyld and must not be exported. Residual: **45** → **42** (11:20, vs the 8,064-B placeholder) → **6** (11:25, vs the real 617,080-B `libsystem_kernel`) → **4** (11:28, `-fno-exceptions`) → **2** (resolver fixed, 8f). Undefined 128 → **123**; exports 203 → 205; size 994,056 → 993,360 B. **2 residual, `_ccsha256_di` + `_ccsha384_di`, and neither is a dyld symbol**: `libcorecrypto` exports 3 `ccsha1` forms, zero ccsha256/384 | 2026-09-27 | `nm -u` on the **installed artifact**, closure via `otool -L`, **asserted SDK-only**, `$INODE64`/`$DARWIN_EXTSN` normalised, probe positive-controlled. **Final pass re-run with providers taken from the EXPORT TRIE, not the symbol table** (9cf295d432 / 7b905d26f1: `nm` measures the wrong structure) — residual is **still 2** |
| 8f | ⚠️ **TRAP: a missing path in YOUR OWN search list is indistinguishable from a missing file in the tree** | I reported `/usr/lib/system/libobjc.dylib` as **UNRESOLVED — a load-time dependency with no provider**, and built a 22-symbol "libobjc is absent" bucket on it, then called it the largest Phase-6 blocker. **It was present the whole time**: `SDK/usr/lib/libobjc.A.dylib`, **1,608,088 B, 2,147 exports**. My resolver mapped the install name `/usr/lib/system/libobjc.dylib` to `$SDK/usr/lib/system/…` and **never tried `$SDK/usr/lib/`**, where it is actually installed (as a symlink). The fault was the resolver, not the tree, and I did not say so. **Ironic: I had warned about this exact class one exchange earlier** (host-path contamination) and then shipped its mirror | 2026-09-27 | caught by peer, verified by me before accepting: `ls` shows the file, `otool -D` shows the mismatched install name. **Fix: an install name may live in `usr/lib/system` OR `usr/lib` — try both.** Closure 18 → **19**; libdyld residual 4 → **2**; total unresolved 63 → **38**. `libobjc` supplies **31** symbols, and is multi-family: it also defines `__Unwind_Resume`, `___gxx_personality_v0`, `___objc_personality_v0` and both `__cxxabiv1` vtables, so a naive bucket table silently double-counts across families |
| 8e | ⚠️ **TRAP: this Makefile has NO dependency on itself — editing `CFLAGS` rebuilds nothing** | `CFLAGS.DyldSharedCache.o = -fno-exceptions` was added; the build **succeeded**, relinked, reinstalled, and produced a **different hash** — and changed **nothing**: residual stayed 6, both symbols still demanded. Cause: `bmake` rebuilds on source mtime only, and `.o` (11:13:15) was newer than `.cpp`. The hash differed only from Mach-O UUID nondeterminism. **A green build that changed nothing.** Fixed by `rm`ing the one stale `.o`; the flag then appeared on the real compile line and the residual moved 6 → 4 | 2026-09-27 | the tell was cheap: `grep -c isysroot-cc` on the build log showed **4** compile lines and `DyldSharedCache.cpp` was not among them. **Any Makefile-flag change in this tree must be proved to have reached a compile line before its effect is believed** |

| 9 | **Boot: `/bin/echo` reaches `main()`?** | **NO** | 2026-09-27 | `run.sh dynamic`; serial log |
| 10 | Current boot fault — ⚠️ **NOT a missing symbol and NOT a C-library problem** | **`Symbol not found: _strlen`** (was `___mb_cur_max`), dyld namespace 6 subcode 0x4, initproc failed to start | 2026-09-27 | ⚠️ **It is simply the FIRST import reached in a closure where nothing can resolve.** 26 of the 48 staged dylibs expose an export set of zero to dyld, so the first import fails; which one it is depends only on import order. **Do NOT go looking in `libsystem_c` for a missing `mb_cur_max` — the symbol is defined there.** The signature is an artifact of ordering, and a different first import reads as a different bug. Now `_strlen` because our `libsystem_c` **re-exports** the 22 C string/memory functions through **`libsystem_platform`, which is one of the 26 dead ones** (0 readable, 192 in its symbol table, mis-aligned LINKEDIT 'data in code'); 30 staged dylibs import `_strlen`. **The chain's leaf is dead — a staging gap, not a build gap** (§7.8) |
| 10a | ⚠️ **REGRESSION (cause now DISPROVEN — see 10d): staging our `libsystem_platform` coincided with a hang replacing a clean dyld abort** | 777 lines / `_strlen` abort → **632 lines / no fault, just stops.** **Deterministic:** 300 s and 600 s of kernel budget give **byte-identical** logs, 76 `vm_map_get_range` calls each. **Localized: dyld dies AFTER the shared-region fallback completes, one step before Ignition prints** — `check_np` returns ENOMEM, it does not block. See **§12** | 2026-09-27 | `serial_dynamic.20260927-1224.W300-TRUNCATED.log` vs `…122515.W600-HANG.log` vs the 777-line `…114528.log`; `vm_unix.c:962-971`. ⚠️ **The 76 `vm_map_get_range` lines are KERNEL-HEAP allocations, not userspace mappings** (they are `range_id=5` = `KMEM_RANGE_ID_DATA`, `map==kernel_map`, and their min/max is character-for-character the `kmem_data_range` zone) — they proxy kernel work, so 128→76 may mean the kernel stopped working, not that dyld stopped mapping |
| 10d | ✅ **`libsystem_platform` is INNOCENT — the one-variable revert did NOT restore the `_strlen` abort** | Reverted to the dead 145,572 B / 0-export library, image **byte-verified** to carry it (marker at offset 60090368, re-checked after the run), re-booted. **Every signature identical:** userspace band `0x1000004f0..0x10bb6eb10`, hottest CPL=3 RIP **`0x10bb44b61`**, dominant kernel RIP `0xffffff8006df9d43`, kernel slide `0x6a00000` — **all unchanged.** The correlation was **coincidental**; the fault is **upstream** and staging `libsystem_platform` only let dyld get *further* before the same wall | 2026-09-27 | `qemu_full.log` of the revert run (618,022 records) vs the hang run (449,650), compared on the **CPL=3 fingerprint** — userspace band, hot RIP, kernel slide. ⚠️ **The serial logs could NOT have settled this:** a silent hang's last line is an ordinary kernel message, so "still hangs" and "hangs differently" are indistinguishable there. **For a silent hang the QEMU interrupt log is the instrument** — and it is truncated on every boot, so copy it aside. §12.6 |
| 10b | **The kernel is IDLE and STARVED, not spinning and not deadlocked** | Dominant tail RIP, slid back by the measured kernel slide **`0x6a00000`**, is `0xffffff80003f9d43` = **`cmpl $0x0, %gs:0x58`** in `_ml_set_interrupts_enabled` — the **idle thread's wait for work**. `_idle_thread` (0xffffff8000286740) contains the same `%gs:0x58` poll and calls it | 2026-09-27 | `qemu_full.log`, last 300 dumps. ⚠️ **The kernel runs at a NONZERO slide although boot args say `slide=0`** — 0 of 121,837 dumps land in the kernel image at its link address, which is why nothing symbolized at first. Slide solved by maximizing exact function-entry hits (468/4,740). ⚠️ **This does NOT discriminate blocked-in-syscall from userspace-spin** — both starve the CPU identically; only the thread state does. It DOES rule out a kernel deadlock and a runaway kernel loop |
| 10c | ✅ **THE DISCRIMINATOR: the hang is a USERSPACE SPIN, not a blocked syscall** | **1,819 `CPL=3` records; userspace first appears at 48.7% into the log and the last one is the FINAL record** — one contiguous stretch to the end. 294 distinct RIPs in a 187 MB mapping, `0x1000004f0..0x10bb6eb10`. Not dyld's stack (`check_np` used `0x7ff7b6b15d58`) | 2026-09-27 | full 566 MB / 449,650-record scan of `qemu_full.log` for `CPL=3`, not just its tail — **the tail is all kernel because the tail is where the idle thread runs, which is why the tail-only read missed this entirely.** Settles §12.4's open question: idle CPU cannot distinguish blocked-in-syscall from userspace-spin, and the answer is **spin**. Consistent with §12.3 — dyld made its last kernel call, then spun without another. ⚠️ **Which code is NOT yet symbolized** (needs the userspace PIE slide + a matching load address); **not guessed** |
| 10e | ✅ **PROVENANCE: every dyld result on this campaign was produced by a kernel that is NOT a build of the committed source** | `vm_unix.o` was a **stale object compiled 2026-09-26 from a since-reverted local edit**; `kernel_build.py` does not recompile `vm_unix.c`, so it survived every rebuild. It set **`EINVAL` not `ENOMEM`**, tore the shared region down, and **deleted the `copyout`**. **REVERTED** and relinked; rebuilt kernels carry 0 occurrences of `"; using individual dylibs"`. **No source change was needed — the repo was already correct, only the build tree was wrong.** ⚠️ **Three more objects are still divergent** (`kern_exit.o`, `kern_fork.o`, `bsd_i386.o`), deliberately untouched — `kern_exit` reverting would re-break PID-1 reaping | 2026-09-27 | Disassembly diff of `_shared_region_check_np` (stale object vs same-`.o.json` from-source rebuild, which reproduces 4 sibling objects byte-identically); **all 1078 objects in `link.filelist`** swept by rebuild-and-compare. See **§12.5, §12.5a, §12.5b** |
| 10f | ✅ **The `ENOTTY` is an APFS mismatch, NOT a missing shared cache** | `25` = `ENOTTY`; innermost message is **`preboot: failed to get preboot device: 25`** (the 3 outer messages are the same error propagating). The lookup needs a **Preboot volume**, which is an **APFS construct**. **The image is FAT32; there is no APFS driver in the tree** (only `osfmk/kern/kern_apfs_reflock.c`, a lock primitive); `IOGetApfsPrebootUUID` is declared `extern` and **defined nowhere**. It dies at the *first* step, before any cache is considered | 2026-09-27 | string table of the staged `assets/usr/lib/dyld`: `preboot device` → `preboot mount point` → stat/open → `preboot uuid not available; cannot find boot cryptexes` → mount. `mkimage.py` builds FAT32 via `fat32img.py`; `Kernel/xnu/config/MASTER:143` has `CONFIG_MOUNT_PREBOOTRECOVERY` **on** so it is not a build flag. ⚠️ **The "no shared cache staged" hypothesis is WRONG and is recorded as wrong because it is the comfortable answer** — a cache would not fix a device lookup that never happens. `ignition level 0x5` was already requested. **Neither a build campaign nor a one-line fix.** §13 |
| 10g | ⚠️ **THE IMAGE RUNS APPLE'S DYLD — our `libdyld` is not in it at all** | The loader is **`assets/usr/lib/dyld` (2,562,000 B, 6 exports)**, a *separate staged file*, at image offset 44963840. The staged `usr/lib/system/libdyld.dylib` is the **385,783 B Apple** binary with **0 dyld-readable exports**, at 53176320. **Our `Libraries/dyld/libdyld.dylib` (987,968 B, 205 exports) is at offset −1: not in the image** | 2026-09-27 | byte-search of `boot_dynamic.img` for the first 2 KB of each of the three; plus `strings`: the staged `/usr/lib/dyld` has **83** `libignition` strings, **our `libdyld` has ZERO**. ⚠️ **So the whole `ENOTTY`/ignition frontier exists only in Apple's dyld** — our build has no ignition code at all, which makes "stage our dyld" a fundamentally different campaign step than "fix the preboot path." Three distinct dylds on disk, neither staged one ours |
| 10h | ✅ **THE HANG IS RESOLVED; frontier advanced `_strlen` → `___error`** | Re-staged our `libsystem_platform` (rebuilt, **86,176 B, 204 exports**; image byte-verified to carry ours, dead extract at −1) and booted: **780 lines, `Symbol not found: ___error`**, and **`Darwin Ignition Sequence` now PRINTS** (it never did in the hang runs). The 632-line silent hang is gone. **NOT a pass** — `RAVYN-DYNAMIC-USERLAND-OK` count **0**; PID 1 panics `initproc failed to start` | 2026-09-27 | `work/serial_dynamic.20260927-183021.OURS-platform.log`, 600 s kernel budget, firmware prompt 13.8 s; QEMU log preserved as `qemu_OURS-libsystem_platform.1830.log` (82.8 MB). ⚠️ **`Referenced from` and `Expected in` are BOTH `libSystem.B.dylib`** — it declares an import it does not define; dyld is not mis-routing. **Measured: 0 of 47 staged dylibs export `_error`**, and `libsystem_c` exports **0**, so the obvious guess is already wrong. **`_strlen` resolving is a CONSEQUENCE, not a fix** — the reexport chain through `libsystem_platform` was severed by the dead extract, so the first import merely moved. §14 |
| 10i | ⚠️ **Staging our `libdyld` is a CLEAN NEGATIVE — and it confirms the `___error` fault is a `libsystem_c` port gap** | Our `libdyld.dylib` (987,968 B, **205 exports**) staged at its own install-name path, replacing the 385,783 B Apple extract; image byte-verified (ours at 53176320, Apple at −1). **Fault byte-identical to the previous run** — same UUID, same `Referenced from`/`Expected in`, `diff` empty; 780→782 lines; `ignition boot failed: 25` persists | 2026-09-27 | `work/serial_dynamic.20260927-185010.OURS-libdyld.log`; QEMU log `qemu_OURS-libdyld.1850.log` (86.6 MB) preserved. **Expected:** the fault is internal to `libSystem.B` (a **71,948 B extract with 0 exports**), so no other dylib can satisfy a symbol it must provide itself. **No new failure, and specifically no `ccsha` error** (all three of `ccsha1/256/384_di` are provided by staged `libcorecrypto`). **Only `libsystem_c` can export `__error` and ours imports it without defining it — no staging change fixes this.** §16 |
| 10j | ⚠️ **CORRECTION: the fault is `___error` (C `__error()`, the errno accessor), NOT `error()`** | §14.2 searched for `_error` (C `error()`) and so called the symbol unprovided. `___error` is three underscores = C **`__error()`**, declared `extern int * __error(void)`. **Apple's `libSystem.tbd` — trie-level, generated from export tries — DOES contain `___error`**, so the provider is `libsystem_c`; ours has 0 exports and `nm` shows `U ___error`: **it imports the function it should define.** No definition exists anywhere under `Libraries/`; `err.h` does not declare it, `gen/FreeBSD/err.c` does not define it, yet **29 objects in `libBase.a` call it** (`sys/semctl.c:32-33` does `#define errno (*__error())`) | 2026-09-27 | **This is a PORT GAP, not a staging gap**, and it is the first fault in this campaign whose fix is identified down to the function: add `__error()` to `libsystem_c` and rebuild. Darwin's primitive `__mach_errno_addr()` is already referenced by `libsystem_pthread/pthread_cancelable.c:57`. ⚠️ The only `error`-named function in the tree is cctools' `void error(const char*,...)` in `libmacho/stuff/errors.h` — `__private_extern__` (never in a trie), wrong signature, and not even compiled. §15 |
| 10k | ⛔ **BLOCKED: `__error()` cannot be implemented correctly — the TSD reader primitive is absent** | The per-thread errno **exists and is wired** (`internal.h:231` `err_no`; `pthread.c:905,1629` set `tsd[ERRNO]=&t->err_no`; `__TSD_ERRNO=1`), and **nothing reads the field directly** — the TSD slot is the only path. But reaching it needs `_os_tsd_get_direct`, which is **used in 4 files and defined NOWHERE** (no `.c`, no `.s`), and `libsystem_pthread` exports **no TSD symbol**. Those refs are **latent** — `lock.c:299` calls it from an uncalled `always_inline` helper, which is why that library links | 2026-09-27 | grep for a definition across all file types: none. `libsystem_pthread` exports only `__pthread_clear_qos_tsd`. **Rejected `__thread` TLS rather than shipping it:** it would be a *second* errno separate from `t->err_no`, and **dyld itself calls `__error()`** (`dyld/src/glue.c:291-294`) *before* the pthread runtime populates any TSD — which is exactly why Darwin keeps errno in the pthread struct rather than TLS. **Unblock: provide `_os_tsd_get_direct` in libsystem_pthread and export it** (a different component from the one authorised); `__error()` is then one line. §17 |
| 10l | ✅ **CORRECTION: the dyld loader's link inputs are PRESENT — §15.1's "absent" was wrong** | Caused by checking the in-repo `Developer/ravynOS.sdk`, which is source-only with **no `lib/`**; the real `RAVYN_SDKROOT` is `/Users/max/Projects/build/.../ravynOS.sdk`. Against the real SDK **every input exists**: `libc.a`(26 members)/`libplatform.a`(47)/`libpthread.a`(18) in `usr/local/lib/dyld`, `libc++.a`, `libc++abi.a`, `libunwind.a`, `libCrashReporterClient.dylib`, **32/32 SRCS** (resolving from `Libraries/dyld`, not `Libraries/dyld/dyld`), and `dyld.exp` | 2026-09-27 | `ar`/`ls` against the real SDK; per-file existence check on the makefile's SRCS. **The loader is BUILDABLE** — never built (no `Libraries/dyld/dyld/dyld` binary), but nothing is missing. The only open item is whether the `-nodefaultlibs` link against these static archives succeeds, which is a link attempt rather than a missing prerequisite. **Whether the boot can ever run our dyld is not blocked by absent inputs.** §18 |
| 11 | Reexport tally | **22 of 25** | 2026-09-27 | reexport census over boot closure |
| 12 | Mach generations | SDK = **Catalina (10.15, 2019)**; in-tree xnu = **Darwin 24.0 / xnu-11215** (2021–22) | 2026-09-27 | `SDKSettings.json` newest mach copyright 2019; commit `394fe3eac3` |
| 13 | Mach migration size, corrected | naive swap: **54 modified + 45 deleted**; actually referenced: **14** | 2026-09-27 | two passes; 3,562 references across 14 headers, 693 objects |
| 14 | Components with no obtainable source | **15** (not 10) | 2026-09-27 | source census. All 15 referenced by the boot image |
| 15 | Stubs of those 15 | **8 fail loudly**, **7 fail silently** | 2026-09-27 | 161 imported symbols across 19 staged dylibs; 7 import zero |
| 16 | `libdispatch.dylib` | **BUILDS AND LINKS.** 32 objects, real **912,240-byte** dylib installed into the SDK, zero error signatures | 2026-09-27 | single-component build on a `ps`-verified quiet tree. **One of the two UNEXPECTED driver failures is CLEARED** |
| 17 | Cause of the `libdispatch` fix | **a global trigger in `isysroot-cc`, not a `libdispatch` defect.** Cleared by a per-component opt-in | 2026-09-27 | argv capture; the shim trigger was a filesystem check on the SDK, not on what the component's Makefile asked for |
| 20 | `libsystem_darwin` real build | **target class ELIMINATED: 0** `os_log_`/`assumes.h`/`cleanup.h` errors (20 before), and 0 across all 12 sources. **Still does not build** — 5 × *requires OS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE*, `mach.c:269,293,296` return-value, 5 × macro-arity. libtrace is **load-bearing** for `os_malloc`/`os_calloc`/`os_strdup`, so the fix was **too blunt** | 2026-09-27 | real `build-libraries.sh Libsystem/libsystem_darwin`, `ps` verified empty immediately before. See §7.4 |
| 18 | `libsystem_darwin` | libtrace define **removed**; **20 → 0** on a repro TU through the real wrapper. **Component link NOT yet measured** | 2026-09-27 | real `isysroot-cc` + real Makefile flags; `bmake -n` confirms the define reaches no compile line. See T1b |
| 19 | **KNOWN-UNMEASURED SURFACE created by the shim opt-in** | **CORRECTED by direct measurement — the earlier figures in this row were wrong.** Enumerated from the **driver's own stage list**, not from source counts: the components that lost the shim are **`objc4` (44 shim-reachable TUs: 43 `.mm` + 1 `.cpp`), `libsystem_malloc` (55), `libdispatch` (2), `libsystem_m` (1), `CommonCrypto` (1)**. **`ICU` is NOT a driver stage at all** — built by nothing in the driver — and its count is **794**, not 477. **Only `libdispatch` is measured** (20 → 0, better off); `dyld` opts in via `-D`. The rest are **UNMEASURED** | 2026-09-27 | `build_all_libsystem.sh` stage list; per-component `find` for `.mm/.cpp`; wrapper argv capture both directions (`-x objective-c++`: **17 shims → 0**). Per-shim A/B retained: **6 of 17 shims harmful, 11 harmless**. **`objc4` is a BOOT-CLOSURE risk, not a latent one** — `stage_dynamic_libs.sh` stages `libobjc.A.dylib` into the boot image, and its absence is the hard stop that made the `___mb_cur_max` fault reachable. Priority runs **objc4 → libsystem_malloc → libsystem_m/CommonCrypto → libdispatch**: closure before size. Evidence: notes sec. 31, 34 |

### 2.0 The one fact that should drive prioritisation

**The UNEXPECTED failures are the *only* thing making a full driver run
non-green.** Every other stage passes or is a declared known-blocked. Clearing
Phase 5 (§7) therefore converts `RESULT: FAIL` → `RESULT: PASS` **without
moving the actual goal one inch** — `/bin/echo` still does not reach `main()`.

**Where that stands (2026-09-27): one down, one to go.**

- **`libdispatch` — CLEARED.** 32 objects, a real 912,240-byte
  `libdispatch.dylib` in the SDK, zero error signatures, on a `ps`-verified
  quiet tree (row 16). The cause was **a global trigger in `isysroot-cc`, not a
  `libdispatch` defect** (row 17) — the shim family was keyed on a filesystem
  check against the SDK rather than on what the component's Makefile asked
  for, so it was pulling libc++ onto every C++ TU in the project. A
  per-component opt-in cleared it. **The atomic collision and the shim-trigger
  problem were the same change.**
- **`libsystem_darwin` — FIXED AT THE SOURCE LEVEL, link not yet measured**
  (row 18). It is now the **last** UNEXPECTED failure, which makes it the whole
  of "driver goes green". Its fix is `-DOS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE`
  removed: `assumes.h` already carries complete non-libtrace fallbacks
  (lines 253-257, 292-302), and the `<os/log_private.h>` this component was
  reaching is xnu's kernel header, which defines **none** of the five symbols
  that branch needs (§7.2). Verified 20 → 0 on a repro TU through the real
  wrapper; the component build is T1b.
- **The new baseline is in flight and deliberately NOT written here.** A
  predicted baseline is not a measurement; row 1 stands as the last measured
  one, marked superseded-pending.

This is worth stating plainly because it is the most tempting misreading in
the project. **A green driver run is a milestone, not progress.** It means the
instrument is trustworthy again, which matters for §6.5, and nothing more.
Anyone who reports "the build is green" without this sentence attached has
misreported the state of the work.

Conversely: while any failure stands in that column, a *new* failure is easy
to miss, because it hides in a column that is already non-zero. Fixing Phase 5
buys back the ability to see regressions, which is why it is worth doing even
though it does not advance the goal.

### 2.1 The two numbers that most often get quoted wrong

**`--quick` is not a baseline.** It skips three stages, and one of the three
(`libdispatch`) does not build. Every "0 unexpected failures" claim ever made
against a quick run is weaker than it looked. The earlier figure
`24 passed / 2 known-blocked / 0 unexpected` was a `--quick` number and is
**not** a full measurement; every regression claim made against it is weaker
than it appeared. **Only full runs are quotable.** Same rule for a driver run
with `BOOTLAB_SKIP_DYNAMIC=1`: it skips the only stage that boots anything.

**The 126-symbol attribution is a hypothesis, not a result.** It rests on
`libsystem_kernel` having never linked. The moment it does, recompute.

---

## 3. What "booting" means here

The word is used at two levels in this project and they must never be confused.

**Level 1 — static userland. WORKS.** PID 1 is a freestanding static Mach-O
(`init/init_static.c`, no `LC_LOAD_DYLIB`, raw syscall numbers). It opens
`/dev/console`, dup2s to 1/2, prints a banner and `alive tick N` lines, and
never exits. Acceptance: `alive tick` lines in `work/serial_full.log`, zero
traps. **This level is done and has been for some time.** It is a real result
and it is not the goal.

**Level 2 — dynamic userland. THE GOAL, NOT YET REACHED.** `/bin/echo` and
`/bin/cat` are dylib-linked, loaded by dyld, resolve their symbols out of a
libSystem closure **we assembled from this tree's sources**, reach `main()`,
and exit 0. PID 1 is the static exec-runner (`init_exec_dynamic.c`) that
`execve()`s them.

**`run.sh full` is not a userland gate and never was.** Its PID 1 execs
nothing, so it cannot observe dyld, the closure, or a single dylib-linked
`main()`. It reports a clean boot while the thing being built is untested. The
instrument for Level 2 is `run.sh dynamic`, wired into the driver as a
known-blocked stage so its fault signature appears in every standard run.

**A clean `run.sh full` is not evidence of progress toward this project.**

---

## 4. The phases

### Phase 0 — mach generation probe
**Goal:** determine whether `libsystem_c` survives a full xnu-11215 mach generation.
**Status:** **failed four times.** The current cause is narrow: `EXTRA_INCLUDES`
does not survive `build-libraries.sh`'s environment into the bmake sub-makes.
**Blocking:** the treatment arm cannot reach `isysroot-cc` on the real build
path. **Remaining cost: one line.**
**Unblocks:** a decision on which mach generation is authoritative.
**Risk:** low cost, but four failures mean the next one should be measured with
a non-zero hit count before it is believed. See §6.5.

### Phase 1 — `libsystem_kernel.dylib` links — ✅ **DONE (2026-09-27)**
**Goal:** the gate is 126 of 133 unprovided symbols.
**Status:** **ACHIEVED.** 603 objects, 0 compile errors, **617,080 B** installed
replacing the 8,064 B placeholder, **1,483 exports**, 12 undefined, **0
unprovided** against the 18-dylib closure (§7.5). The port reconciliation was
done properly rather than hand-sourced.
**Unblocks:** Phase 2, which is also now measured (§7.5).
**Risk:** **high — do not hand-source 16 port constants.** They are not
independent constants; they encode an ABI contract with the kernel, and a
wrong port number does not fail to compile, it silently routes to the wrong
port. The right fix is a deliberate reconciliation of the port-numbering
scheme across the generation boundary. If that is ever funded, the 16
hand-sourced bridge items become redundant and **must be reverted in the same
commit.**


### Phase 2 — closure recompute — ⚠️ **133 → 5. Two earlier numbers STRUCK.**
**Goal:** the moment `libsystem_kernel` links, recompute `libsystem_c`'s closure.
**Prediction:** **133 → ~7.**
**Status:** **MEASURED: 272 undefined, 267 satisfied, 5 unprovided**, against
pinned artifacts (§7.5). Attribution **143**, not the 126 recorded all session.
**The sequence of numbers in this one cell is itself the finding:** `133 → ~7`
predicted, `133 → 0` reported and **struck** (a contaminated subtraction),
`133 → 12` reported and **struck** (correctly measured, but before `libdyld` was
reinstalled), **`133 → 5` current.** Three of those four were produced by
correctly-executed instruments; only the last describes the tree as it stands.
**Unblocks:** Phase 3 — and the tail is **5**, split into **3 blocked behind
`libsystem_trace`** and **2 a bounded `SRCS` addition** (§7.5). Neither is the
126-symbol problem this tail was originally read as.
**On the prediction:** direction held, magnitude wrong twice, and the recorded
126 was an estimate standing in for a measurement for most of this session. It
should never have been quoted without "UNVERIFIED".

### Phase 3 — the remaining ~7 symbols
**Goal:** close the tail.
**Status:** not started. Composition: **3** need `libsystem_trace`, **3** are
`libsystem_platform`, **2** are `libdyld`.
**Unblocks:** Phase 6.
**Risk:** the `libsystem_trace` 3 are the expensive ones — see §5.4. Do not
assume they are a 3-symbol job.

### Phase 4 — real `libdyld.dylib` — ✅ **DONE (2026-09-27)**
**Goal:** replace the 8,064-byte placeholder with a real build.
**Status:** **ACHIEVED.** **1 → 28 objects**; a real **987,968-byte
`libdyld.dylib`** built from this tree's sources and installed into the
generated SDK (rows 7 and 8): **205** exports, **10** `upward` reexport
dependencies on the real `libsystem_*` dylibs, modern encoding. The earlier
"16 of 27" was stale and is superseded.
**⚠️ Two of the author's own measurements disagree and are recorded
UNEXPLAINED**, not smoothed: a clean build's artifact carries three undefined
symbols while a manual re-link from the same archive does not; and the build
reports **28 objects for 27 `SRCS` entries.** Both look like rounding details
and are not.
**Independence:** **fully independent of the mach question** — `glue.c`
includes no mach header at all. This is why it can run in parallel with
Phases 0–2 and why parking it behind them is a scheduling error, not a
dependency.
**Unblocks:** the 2 symbols in Phase 3, and Phase 6.
**Risk:** the real risk is no longer the header frontier — it is
`libdyld` being deprioritised because it is "independent", which cuts both
ways. A second, newer risk: this component is the sole opt-in user of the
libc++ shim family (§7.1b), so any change to that gate is now a *`libdyld`*
regression as well as a `libdispatch` one. Measure both, always.

### Phase 5 — fix `libdispatch` and `libsystem_darwin`
**Goal:** clear the 2 UNEXPECTED failures so a full run can go green.
**Status:** both **pre-existing**, both **diagnosed**, neither fixed by
design decision yet. See §7 for both diagnoses.
**Unblocks:** a trustworthy full-run baseline, and it removes the standing
risk that a real regression hides inside "the 2 known ones."
**Risk:** **both fixes are tempting in the wrong place.** `libdispatch` is a
header-configuration problem and the tempting fix is in
`chunk_private.h`, which is **kernel libkern** and must not be touched.
`libsystem_darwin` is a missing header and the tempting fix is a shim, which
would be a silent stub — the exact defect class this project exists to
eliminate (§5.5).

### Phase 6 — ⚠️ **make the libraries LOADABLE (1 of 26 done), then converge the image**
**Goal, as originally written:** stage **our** `libSystem.B` and **our**
`libdyld`; drop the Apple closure.
**⚠️ This phase is TWO pieces of work, and the first is 1 of 26 libraries done.**
`libdyld` is **hardened** — `-Wl,-fixup_chains`, trie datasize **5,464** where it
was 0, **same 205 exports** (§7.7). ⚠️ **That is an encoding change, not a fix
for an observed defect:** dyld in this image honours `LC_DYLD_INFO_ONLY` and
resolved a trie-less `libsystem_c` fully (§7.8).
**My "1 of 3" was an undercount.** Measured across every dylib in
`$SDK/usr/lib/system`: **26 total, 1 with a trie, 25 without.** The one is
`libdyld` — the one that was fixed. **So 25 of 26 libraries we build are still
in the old export format**, and until that changes **no closure census over them
means anything** — including row 4.
`libsystem_kernel` is kernel-link's while they hold it; the sequencing is
theirs, not ours to work around.
**The right shape for the hardening is ONE wrapper change, not 25 Makefile edits**
(§7.10) — and it is explicitly **not taken** yet.
**⚠️ AND the wrapper has a blind spot that must be surveyed FIRST: `objc4`
passes `-shared` and never `-dylib` on its link line, so it receives NO link
hygiene at all** — and it is the component the boot closure depends on (§7.11).
The verification is therefore **three arms, not 25 `otool -l` calls**, and the
first is a **read-only classifier census that needs no build**. Do that before
deciding anything.
**The second piece — staging — is untouched, and it is the one the boot depends
on.** The image still carries the Apple `libdyld` at 385,783 B, not our
987,968 B one (§7.7). **Unblocks:** Phase 7 — which remains blocked on the
second piece, not the first.
**Risk:** unchanged in kind and now much closer. This is the phase where the 41
Apple-derived files leave the disk, and where a **silent** stub does the most
damage because a wrong-but-loadable library looks like success (§5.5's
`libobjc.A.dylib`). **Add to that list: a correct, complete, fully-symbolled
library with an empty trie is exactly that failure, at a larger scale.**

**⚠️ And the sentence that reframes the whole page:** the image stages 45 Apple
extracts dated Sep 26, `assets/bin/echo` is an **Apple universal binary**, and
**the boot has never once exercised this session's work.** The builds are real
and the libraries are real; they are simply not the ones on the disk image.
Several of us have been reading successful builds as progress toward a boot.
**They are not, yet.** §7.6.

### Phase 7 — boot
**Goal:** `/bin/echo` reaches `main()` and exits; `/bin/cat` likewise; PID 1
alive.
**Status:** blocked. Current fault: `Symbol not found: ___mb_cur_max`, dyld
namespace 6 subcode 0x4.
**Unblocks:** the project.
**Risk:** low. Note that `___mb_cur_max` is a **C library** symbol, not an
`os_log` or platform symbol — which is a sanity signal that the closure is
being walked in roughly the right order.

### 4.1 Concurrency: what you may touch right now

**Read this section before picking up any phase.** The phase *numbering* is not
a work queue — it is a dependency graph, and several phases are explicitly
*not* blocked by the ones before them. Treating the list as sequential is the
single most expensive misreading available here, because it idles free work
behind the critical path.

**The critical path — everything else waits on this:**

    Phase 1 (libsystem_kernel links)
      -> Phase 2 (closure recompute; 133 -> ~7 is the falsifiable prediction)
        -> Phase 3 (the last ~7 symbols)
          -> Phase 6 (stage our libSystem.B + our libdyld)
            -> Phase 7 (echo/cat reach main())

Phase 1 is the whole ballgame. It is blocked on a single `_Static_assert`
about `HOST_DOUBLEAGENTD_PORT`. **One fix gates four phases.**

**Free-running — start these without waiting for anything:**

| Phase | Why it is independent |
|---|---|
| **Phase 4** (`libdyld`) | `glue.c` includes **no mach header at all**. It never touches the mach-generation question. It is parked behind phases that do not gate it, purely by list position. |
| **Phase 5** (`libdispatch`, `libsystem_darwin`) | Both are **pre-existing** failures with written causes. Neither is caused by, nor causes, anything in the critical path. Phase 5 is worth doing *even though it does not advance the goal* — see §2.0. |
| **Phase 0** (mach probe) | One line of plumbing. It informs a *decision* (§8.1), it does not gate a build. |

**The rule that governs all of it — concurrent builds into the generated SDK
invalidate each other's measurements.** This is lesson 2 (§6), stated here
because this is where it is actually needed:

- The generated SDK is **shared mutable state**. Two workers building into it
  at once produce numbers that are neither worker's.
- A driver run is only a baseline when **zero other builders are confirmed**
  (row 1, §2). A build result taken while another worker writes to the tree
  is not weak evidence — it is **not evidence**.
- **Do not run the full driver while anyone else is building.** It is the only
  instrument that can show a regression in a currently-green component, which
  makes it both the most valuable and the most easily corrupted measurement in
  the project. One run, on a quiet tree, is reserved to whoever is
  coordinating. Everyone else builds single components.
- Before *any* measurement: `ps` for `build-libraries.sh` / `bmake` /
  `isysroot-cc`, and if anything is running, **do not measure — contribute
  documents or code instead.**

**Cheap and always safe:** reading, writing documents, editing sources that
are not mid-build, and `-fsyntax-only` probes outside the repo. These cannot
corrupt anyone's measurement, because they write nothing into the build tree.
That is why the `libdispatch` diagnosis in §7.1 was reachable at all while two
other workers held the tree (§7.4).

---

## 5. Decisions taken, and the ones that were wrong

This is the most valuable section. The reasoning is preserved, not just the
outcome.

### 5.1 "SDK mach tree wins wholesale" — taken, then partly reversed, and the reversal was correct

An early fix reordered `-I` so the in-tree `osfmk` won, to supply
`mach_msg_aux_header_t`. That was **reverted**, and rightly: `osfmk/mach` is a
partial mirror missing whole headers (no `task.h` at all), while the SDK tree
is a coherent generation. **Mixing a partial mirror into a complete tree is
the defect itself.**

But "SDK wins wholesale" is only *partially* true, and discovering that cost a
cascade. Sourcing `mach_msg_aux_header_t` produced exactly **one** new error
(a suspiciously clean result), then a second in a different header
(`COALITION_INFO_GET_DEBUG_INFO`, absent from **both** SDK trees, present only
in `osfmk`). Pulling definitions across one header at a time does not
converge — **it makes the SDK tree a chimera of two xnu generations, which is
precisely the incoherence this workstream existed to remove.**

**Resolved by measurement, not by guessing.** One pass over the identifier sets
of both trees, intersected with what libsyscall actually references:

    SDK mach tree defines     2,604
    osfmk mach tree defines   2,897
    libsyscall references       995 (CAPS)
    CENSUS (referenced, in osfmk, absent from SDK)   15

Fifteen constants across **7** headers. That is a **bounded, sourced bridge
between two real xnu generations, not a chimera** — and every one was verified
absent from the *entire* generated SDK, not just the mach tree. Durability was
proven the same way as the `asm_help.h` fix: the eight census headers were
**deleted** from the generated SDK, re-synced, and all 15 symbols re-verified.

Two corrections to earlier estimates, both of which had been **overstating the
work by roughly 3x** and are recorded so nobody re-derives them:

- **A naive `osfmk/mach` → SDK swap would modify 54 and delete 45 headers**,
  including `task.h`. `osfmk/mach` is **not** a drop-in.
- But only **14** headers are actually referenced by `libsystem_c` — 3,562
  references total, `task.h` alone referenced by 273 of 693 objects. The other
  32 are mechanical. **Any estimate quoting 46 overstates it by ~3x.**

**And the tree that wins is not the one you would guess.** It is
`System.framework/Versions/B/PrivateHeaders`, which the `-I` puts ahead of the
sysroot. The first attempt sourced only `usr/include/mach`, verified the
defines were present, and **still failed to compile**; 17 header copies across
both SDK trees needed updating. *File size is not a proxy for generation* — the
in-tree `mach_types.h` is the **older** generation despite being larger.

### 5.2 "`suid_cred_*` is a hard stop" — **wrong, and caught by grepping badly**

The reasoning was: the type is used but never defined. **That was wrong.** The
grep was for `suid_cred_path_t;`, which cannot match
`typedef char suid_cred_path_t[1024];` because `[1024]` sits before the
semicolon. All three types **are** defined in the SDK's own `mach_types.h`.

This was made **twice in one session** (first concluding `mach_msg_aux_header_t`
was undefined in-tree, then this). When proving a type is absent, **grep the
bare NAME, not `name;`.** An array or function typedef puts other tokens
before the semicolon.

### 5.3 "`libsystem_trace` has no obtainable source" — **wrong**

It has **1,004 real lines of C** at `Libraries/Libsystem/libsystem_trace/`.
Filing it as unobtainable was a miscount, and it was load-bearing for the
"how many components have no source" figure, which is how **10** became
**15**.

It is nonetheless **not buildable**, for a different and precise reason: it
needs `os_log_buffer_s` and `os_log_buffer_context_t`, which have **zero
definitions tree-wide or in the SDK**, plus the kernel-only `lck_spin_t`
(§5.4). That distinction matters — "no source" and "has source, cannot build"
are different problems with different fixes, and conflating them hid both.

**Live legal exposure, stated plainly:** the staged binary is Apple's
**`1861.160.4`** against our Makefile's **`1147.0.3`**. `libsystem_trace` is
the **#1 load-bearing component** (14 non-weak references, 77 imported
symbols). Staging an untested replacement is a separate decision from building
one, and it is a human decision (§8.3).

### 5.4 "`lck_spin_t` cannot be sourced" — **wrong**, and it closes a question open since the original handoff

Its sole definition tree-wide sits inside `#ifdef MACH_KERNEL_PRIVATE`, and its
member uses `__kernel_data_semantics`. That reads as kernel-only.

But "kernel-only" is not "unsourceable." **This closes a standing question: a
userspace shim was never going to be the right answer, and the original
handoff's shim instinct was wrong for a reason nobody had articulated.** The
blocker is the *userspace ABI for a kernel lock primitive*, not the source.

### 5.5 "A stub for the missing components would be fine" — **refuted, and this is the core of the project**

Stubbing the 15 would fail **loudly** for 8 (library-load subcode 0x1, or
symbol-binding subcode 0x4 — 161 imported symbols across 19 staged dylibs).
**That is the exact error class the boot is currently stopped on.** So for
those 8 the stub "works" in the sense that it fails visibly.

**For the other 7 it would fail silently.** They import **zero** symbols:

    libkeymgr   libcache   libsystem_secinit   libsystem_eligibility
    libsystem_sanitizers   libsystem_configuration   libsystem_networkextension

Loud is survivable. **Silent is the defect class this project exists to
eliminate.** A guard that is never exercised is indistinguishable from a guard
that always passes.

The `libobjc.A.dylib` trap is the worked example and the reason gating must be
on **exports, not size**. A 6,856-byte `build_stubs.sh` placeholder defined
`_objc_msgSend` and `_objc_msgSendSuper2` as **no-ops** while lacking ~2,100
other symbols:

| | size | defined symbols |
|---|---|---|
| real source build | 1,608,088 B | 2,145 |
| the stub | 6,856 B | 45 |

It is a valid Mach-O, correctly named, at the right path, **0.4% of the right
size: every size-based check passes it.** Staging it would have converted a
**loud dyld abort into a silent wrong answer** — the first Objective-C call
returns whatever an empty stub returns, with no error anywhere. The real
1,608,088-byte build is staged now.

The gate was **negative-tested** (a 4,200-byte fake was planted and the gate
confirmed to reject it), because a gate never seen red is the same defect as
the derived-artifact gate's 19 false reds.

### 5.6 "0 unexpected failures" from a `--quick` run — **the measurement was not what it looked like**

See §2.1. The most expensive class of error in this project is a number that
is real, quoted accurately, and measures the wrong thing.

### 5.7 "The xnu sources are present, therefore the declarations are" — the pattern that predicts where the next component fails

Across four components the failure was never missing code. It was always a
missing **declaration**:

- a **coordinated port-numbering block** that cannot be sourced in pieces;
- **two absent struct layouts** plus a kernel-only `lck_spin_t`;
- a **`message.h` include-guard collision**;
- a **census that could not see a struct** because it compared only `#define`s
  and `typedef`s.

Each was a header-availability or header-configuration failure wearing a
compiler error's clothes. **This predicts where the next component fails, and
it is why the instinct to go looking for a missing `.c` file is usually wrong
here.**

### 5.8 Apple-derived asset posture (a decision to keep, deliberately)

41 files are **untracked but on disk** under `tools/bootlab/assets/`, on
purpose, with a `.gitignore` that must stay correctly scoped. Tracked count
under that tree is **14**. `assets/usr/lib/dyld` is still load-bearing for the
interop test. Do not "clean up" the untracked files.

### 5.9 Corrections the bootlab made to itself, and how they were caught

- The `#UD` at UEFI handoff is **not always** a stale pflash. `boot.py`
  re-copies `vars.fd` every run and it still recurred once; an identical
  re-run booted fine. Recorded as **unexplained**, not filed under the known
  cause. "Always copy fresh vars" is **necessary but not sufficient**.
- A **false-positive GREEN** was retracted after the probe was found never to
  have been consumed by a translation unit: `EXTRA_INCLUDES` did not survive
  into the bmake sub-makes, so treatment and control were the *same build*.
  Log said `rc=0 693 objects 0 errors` for both arms. It looked identical to
  success. See §6.5. (The `rc=0` there is a **compile-stage** figure: the link
  stage fails in both arms on `ld: library 'system_trace' not found`, sec. 20's
  documented blocker. The gate is "693 objects, 0 **compile** errors".)
- `/etc/rc` — which until 2026-09-26 was PID 1 and which actually executed
  `/bin/echo` and `/bin/cat` — has **no source in the tree**. Only its serial
  output survives, in gitignored `work/`, so it is **not recoverable**.
  `run.sh dynamic` replaces the capability deliberately, from source. **Do not
  assume `/etc/rc` is exercised.**
- The dynamic gate costs **205–358 s across two runs, 40–55% of the loop**. The
  spread is build caching, not variance in the gate. The *signature* is stable
  across runs; only the panic **caller address** moves, which is kernel slide.
  **Compare the signature, never the address.**

---

## 6. Lessons that must not be relearned

### 6.-1 ⚠️ **A positive control that agrees with the suspect has FAILED, not confirmed**

> **The rule now has a demonstration of itself surviving contact with the person
> who wrote it, which is the only way it stays true rather than becoming
> folklore.**

Every lesson in this section has been adopted by workers without anyone ever
testing whether it holds against the person who wrote it. I did, on
2026-09-27, and it failed — which is the point of running it.

I claimed a root cause: `dyld_chained_starts.segment_count == 0`, so the fixup
walk had no chains and was a no-op. I based it on a hand parser that read the
first `uint32` at the `LC_DYLD_CHAINED_FIXUPS` data as a segment count. It read
`0`. I checked the reader could return non-zero (synthetic inputs returned 1, 2,
0 and `None`), shipped the finding, and **committed it.**

Then I compiled a trivial C file with the **host** `clang`/`ld64` and ran the
same parser on it. It also returned `0` — on a binary that is *known* to have
working chained fixups. `dyld_info` then showed the truth: that first word is
`dyld_fixups_header.fixups_version`, the chain starts are **fully populated**,
and my root cause was wrong. (Cause: I hand-parsed with the 32-bit
`dyld_chained_starts_in_segment` layout while this tree's header is the
64-bit-safe one.)

**Three things make this the rule rather than an anecdote:**

1. **The control agreed with me.** That is the failure mode, not the success
    mode. A control is supposed to be *capable of disagreeing with the thing
    under test*. When it agrees, one of two things is true — the thing is right,
    or **the control is not measuring the thing you think it is** — and you
    cannot tell which from the agreement alone. The only way to tell is to know
    what the control does on an input you already know the answer to.
2. **I ran the control too late.** It was available before the first commit and
    cost one `clang` invocation. Everything between the parser and the control
    was me reading my own output.
3. **I read the agreement as confirmation.** Not scepticism — I explicitly
    treated "the known-good binary agrees" as bolstering a conclusion I had
    already written up. A control that cannot fail is the same defect as a
    check that cannot fail, wearing a lab coat.

**The operational form:** before trusting a control that passed, name the input
on which it must return the *other* answer, and run that. If you cannot name
it, you do not have a control; you have a second reading of the same file.
And run it **before** you write the finding down, not after you have committed
to it.

> The same round produced a second instance, in the opposite direction, which
> is worth pairing with this one. §42.2: a load-command walk reported
> `sizeofcmds` disagreeing with where the last command ended — and it did not.
> 15 commands, every `cmdsize` ≥ 8, no overruns, ending at exactly
> `32 + sizeofcmds`. **The table is well-formed**, so the fault is not a corrupt
> `cmdsize` in our own image and not a link problem. One check, and it removed
> half the hypothesis space. Checks that come back *clean* are worth as much as
> checks that come back dirty, and they are the ones nobody bothers to run.

> ## If you keep one thing from this document, keep this.
>
> **A lesson lowers the probability of a mistake. It does not remove the need
> to check — and the check is what actually catches it.**
>
> Proven the hard way on 2026-09-27: the `bmake` backslash-continuation trap
> was found, written up as a lesson, and committed. **An hour later, in the
> same file, while editing an unrelated line, the same mistake was made
> again** — an explanatory comment inside a continuation, silently truncating
> `LDFLAGS` to 6 tokens. It was caught by **`bmake -V LDFLAGS`**, the
> instrument that very lesson had created.
>
> Every other lesson in this section is about **knowing what a tool can see**.
> This one is about **not trusting yourself to have absorbed something**. It is
> the only one that applies when you are not holding a tool at all, which is
> most of the time.
>
> **Corollary, and it takes two forms — both learned the hard way here:**
> **write down the instrument, not just the conclusion**, *and* **write down
> when the instrument cannot see.**
>
> A conclusion is re-readable. An instrument is re-runnable. The two
> instruments that found more real defects this session than any build
> configuration change — `clang -E -H` (which header actually answered) and
> `bmake -V <var>` (is the variable the recipe reads the one you edited) — are
> both free, both read-only, and both work while the tree is contended. Had
> only the conclusions been written down, the second trap would have run to
> completion uncaught.
>
> **Attribution, because a shared document should not let one worker appear
> to have generated another's findings.** Three things in this section came from
> `plan`, not from the `dyld` workstream: **the stale-log finding** (queued jobs
> writing to one path, diagnosed as two jobs firing in sequence — a mechanism,
> not the "be careful which log you read" platitude); **§6.5's control-arm
> entry**, preserved in full with the reason it recurred, because it is the most
> expensive single measurement error in this project and it refused to be
> summarised away; and **the positive-control rule with its four broken
> probes** (§6.2), which is the frame that gave a false negative its name.
>
> **The second half is not optional, and omitting it is how an entry like this
> misleads.** Half the failures here were an instrument **pointed at the wrong
> thing**: `nm -gjU` over `libc++.a` members reporting empty and reading as
> "no overlap"; an `nm` pattern that could not match its own output format; a
> regex that measured an indented fragment and called an intact document
> corrupt. **An entry that says only "use `bmake -V`" invites the next person
> to use it on the wrong target.** The form that works is the one in §6.1a:
> **question, command, and what it settles** — with the third column doing real
> work, because it is the clause that tells you when the command is the wrong
> one.

### 6.0a The carry-forward: ask what the probe was pointed at, and when it ran

**Today produced seven instruments that ran cleanly and could not see the
thing. Every real defect was found by an instrument that was scoped
differently or ran at a different time than the question — almost none by an
instrument that was simply wrong about a value. Before trusting a negative,
ask what the probe was pointed at and when it ran. Six of the seven would
have been caught by that one question, and none by running the probe more
carefully.**

This generalises past this project, and it is the lesson worth keeping if
everything else here were deleted. It is also the direct descendant of three
earlier ones — *undeclared identifier* means the header resolved, *0 hits*
means the probe could not see, *link succeeded* means ld64 stopped complaining
— so this is **seven instances, one shape**.

| # | instrument | ran cleanly | could not see | caught by |
|---|---|---|---|---|
| 1 | `-fsyntax-only` repro | ✅ | the atomic header, because `-ferror-limit` aborted first | a second TU that compiles further |
| 2 | `cat -A` | ✅ | whether a directive was **valid** | a two-line compile; `cat -A` only shows bytes |
| 3 | lesson numbering | ✅ | a **merge** read as a **deletion** | reading the text around the gap |
| 4–6 | critical-path's instruments (×3) | ✅ | two census **false negatives**, a stale-object "clean" | checking what the probe was pointed at |
| 7 | `git diff --cached` before commit | ✅ | a commit that landed in the gap **after** the read | a worktree per agent; not available |
| — | `libc++` intersection probe | ✅ | reported **empty per member**, read as "no overlap" | naming the difference between the two |

**The operational form:** a negative result is evidence about *the probe*,
not about the world, until you have shown the probe can see the thing. Two

### A measurement error that makes the tree look **better** is strictly more
### dangerous than one that makes it look **worse** — and the second kind
### announces itself.

Two errors in one session, same shape, **not** symmetric:

| | produced | truth | direction | caught by |
|---|---|---|---|---|
| mine | 10 unprovided | **12** | **worse** — a red that should have been redder | inspection; a number that looked implausible |
| a peer's | **0** unprovided | **12** | **better** — a green that should not be green | nothing, for a long time |

The peer's survived **a build, a gate, an independent peer reproduction, and a
commit message.** It survived *my* verification because I ran the instrument
exactly as specified — a wrong instrument, faithfully operated, **agrees with
itself**, and agreeing is exactly what a self-fulfilling subtraction looks
like. That is the mechanism: `A − P` is near-empty **by construction**,
whatever the tree contains, so it cannot disagree with its own input.

**The rule, and it is the one I would want inherited:**
- **A number that improves the story deserves MORE scrutiny, not less.** A red
  that turns green is the outcome everyone is hoping for, which is precisely
  why it is the outcome you are least able to audit.
- **Check the method against a case where you know the answer.** Isolated
  proof: `_mach_msg2` is *undefined* yet appears in `nm -gj`. One symbol, one
  flag, settles it — no build, no peer, no commit.
- **When a subtraction returns nearly nothing, suspect the subtraction.**
  Residuals of exactly 0 from a set difference are a shape to be suspicious
  of, not a result to publish. This one was 0 *by construction*.
- **An instrument that is wrong at both ends and faithfully operated will
  confirm itself.** Specifying "run `nm -gj`" more carefully would not have
  helped; the specification was the defect. **Verify the instrument against a
  known case, not against the thing you are trying to learn.**

This is §6.0a with a direction attached: a negative result is evidence about
*the probe*. A **positive** result — especially a clean, welcome, on-schedule
one — is no better protected, and is more likely to be believed uncritically.

The operational form, and it now has **three** questions, not two: a result
is evidence about *the probe* until you have shown the probe can see the thing
— **what was it pointed at**, **when did it run**, and **which direction does
the error run**. All three are free to ask.

### Two more, both about the *ground* under a measurement rather than the
### instrument

**A closure is a function of every library in it — so pin the bytes, or the
number is a timestamp.** Two runs of the *same* script minutes apart gave
**12 then 5**, because `libdyld` was reinstalled between them. Both runs were
correct; the tree changed. **A closure figure without md5s attached is not
reproducible, and "reproducible" is the whole value of a measurement.** The
method now carries the hashes (§7.5). The same logic makes the 18-dylib count
itself a measurement: it changes if any member is reinstalled.

**A predicted change is not a measurement — and the prediction is usually the
more interesting outcome.** After the flag bug was found, the 143 was
predicted to move to 141 (a *known* bug existed nearby, and a change would be
the better story). It did not move. The reason is precise and worth keeping:
the 143 is `libsystem_c`'s **undefined** set against `libsystem_kernel`'s
**defined** exports, and the kernel is **not a member of its own provider
set** in that comparison — so the contaminated flag, which added the kernel's
own undefined names to its export list, **cannot reach the result.**
Verified: the kernel's 12 undefined names have **0 overlap** with
`libsystem_c`'s 272. **A bug in one subtraction says nothing about a second
subtraction that does not share its contaminated input.** Run the second
subtraction before you say the first one moved.

**Read the `--stat` of every commit, and treat a large deletion count as a
defect report about your own last action.** A whole-file `write` issued after
reading only a line range of a shared notes file replaced 2,679 lines with
155; the commit stat said 2,676 deletions. **Scoping the commit does not defend
against it** — a whole-file write is the same hazard as a whole-file stage,
and `git add <path>` scopes the path, not the content. What caught it was
reading the stat *before moving on*. Recovered from `HEAD~1` in the same turn,
nothing lost. **The cheap instrument is reading what the tool actually did,
not what you meant it to do** — the same conclusion as lesson 6.0a's index
race, reached from a different direction.

**Corollary, and it is the uncomfortable one:** none of these would have been
fixed by being more careful with the instrument. A correct, well-placed,
correctly-implemented probe still produced a confident wrong answer, because
the *guarantee it was supposed to provide did not exist*. Know which of your
instruments are **advisory** and which are **load-bearing**, and never lean
on an advisory one for a guarantee.

> **⚠️ And the gate that would have caught the largest error in this project:
> does this library have a NON-ZERO `LC_DYLD_EXPORTS_TRIE`?**
> `otool -l <lib> | grep -A3 LC_DYLD_EXPORTS_TRIE` → `datasize`. **`nm -gjU`
> counts symbols; only the trie decides whether dyld can resolve them.** 36 of
> the 47 staged dylibs have an **empty** trie and 6 have **no trie command at
> all**; all three of our source-built libraries are the same. dyld resolves
> reexports from the trie, not the symbol table, so a symbol `nm` reports as
> defined is **invisible at runtime**.
>
> **`nm` and `otool -L` and the stub check and the driver ALL pass a library dyld
> cannot resolve a single symbol from** — and the driver cannot even fail,
> because `bsd.sys.mk:541` adds `-Wl,-undefined,dynamic_lookup`. **An exit code
> is not a gate, and `nm` is not a gate either.** This is §6.0a at its most
> expensive: the instrument that missed it was the one **built specifically to
> answer the question**. §7.6.
>
> **⚠️ CORRECTION — the inference I drew from this gate was WRONG, and the
> boot worker refuted it with a boot.** "No `LC_DYLD_EXPORTS_TRIE` → dyld cannot
> resolve it" **does not hold.** Our `libsystem_c.dylib` has
> `LC_DYLD_INFO_ONLY` and **zero** trie commands, and it **resolved all 1,342
> symbols in its table** in a real boot (1,320 direct + 22 re-exports).
> **dyld in this image honours `LC_DYLD_INFO_ONLY`.** So:
> - **The correct gate is `dyld_info -exports`, and the count is `direct +
>   re-exports`.** Both are easy to get wrong: counting only direct exports
>   An earlier version of this line said "1,053 direct" — **my counting error,
>   and it manufactured a phantom 289-symbol defect** in a section whose subject
>   is precisely that `nm` and `dyld` disagree. §5.5's stub failure mode at the
>   level of a number: a wrong count creates a defect that does not exist, and
>   the reader goes looking for it.
> - **A trie is not required**; it is *available hardening* that removes a
>   format risk. `-Wl,-fixup_chains` demonstrably works (§7.7) but **nothing in
>   this session shows the old format failing on our libraries.**
> - **"has a dyld load command" is ALSO not evidence of exports** —
>   `libsystem_platform` and `libsystem_pthread` carry `LC_DYLD_INFO_ONLY` and
>   still read **0** exports while `nm` sees 192 and 209.
>
> **So the gate has THREE levels, and only the third is the question:**
> 1. `nm -gjU` counts symbols — necessary, nowhere near sufficient.
> 2. `otool -l | grep LC_DYLD_EXPORTS_TRIE` — a *format* fact, and **not**
>    loadability in either direction.
> 3. **`dyld_info -exports` — the only one that answers "can dyld resolve
>    this?"** Count direct **plus** re-exports. It is not in the driver.



**Do not grade a peer's prediction against your own.**
(2026-09-27.) Told a peer *"your instinct that it would move was correct"*
when I had no measurement either way — endorsing a guess because it matched
my guess. **Two workers agreeing on an unmeasured prediction is not a
second source; it is the same guess with two signatures.** The honest
report is the state of the knowledge: the instinct is reasonable, the
measurement has not been run, and here is the number. It later came back
**wrong** — the intuition was reasonable and the tree disagreed,
which is the ordinary outcome of a guess and says nothing about
the person who made it.

The wider form: **agreement between peers is not corroboration unless both
sides measured the same thing.** When two numbers agree, check that they came
from the same instrument on the same bytes first — a contaminated subtraction
and a clean one can agree, and two agents reasoning from one premise will
agree for reasons that have nothing to do with the tree.
|---|---|---|---|

### 6.0 The most transferable lesson in this project

> ### An "undeclared identifier" error is evidence the header **RESOLVED**.
> ### It is never evidence the header is **missing**.

A missing header produces `fatal error: 'x.h' file not found`. Only a header
that was **found, opened, and failed to define the name** produces *use of
undeclared identifier*. So when you see one, the include **worked** — and the
question shifts from *"where is it?"* to *"which one answered?"*

**This is the fourth instance of one shape, and it is the single most
transferable thing this project has produced:**

| # | instance | what resolved | what should have |

| 1 | the `mach/` trees | an `osfmk` generation, ahead on the path | the SDK's coherent generation |
| 2 | the libc++ shims | a C header already open, so libc++ declined to set its guard | libc++'s own shim |
| 3 | `os_atomic_std` | `Kernel/xnu/libkern/os/atomic.h` in a component that is C11 by construction | the C11 branch it was written against |
| 4 | `os/log_private.h` | xnu's 2,894-byte kernel header, via a concatenated `-I` | the `libsystem_c` generation `assumes.h` needs |

**The common shape: the declaration exists, the wrong generation wins, and the
error text points at the loser rather than at the cause.** In every case the
instinct was to go looking for a missing `.c` file or a missing header, and in
every case the file was there the whole time.

**How it bit, concretely.** I recorded that `os/log_private.h` "does not exist
on this component's include path" — and the very error I was quoting,
*use of undeclared identifier*, is the one error a missing header cannot
produce. **The error text refuted the diagnosis written next to it.** Read the
error's *shape*, not just its content: `not found` and `undeclared` are
findings about the search, not about the symbol.

Generalised into a habit: **before concluding a declaration is absent, ask
which copy answered the include.** `clang -E -H` prints the whole resolution
chain in one shot, and it is cheaper than any amount of grepping.

**The lesson that governs every other measurement in this section: never
compare counts, compare signatures.** A count that agrees while every
individual error differs is *worse* than a count that moves, because it
reads as confirmation. In the libc++ shim A/B (2026-09-27) the "before" and
"after" arms both reported **20 errors** and shared **none** of them;
reporting that as "no change" would have been false in both directions at
once. The instrument is the *set* of `file:line:col: error: <text>`, never
its cardinality. This is the exact mirror of lesson 6 below — there the
danger is a green result that means nothing; here it is a red result that
means the opposite of what it appears to mean.

**Third member of this family, and the subtlest: the wrapper emits
`-isystem$dir` as ONE joined token, so a check for `-isystem <path>` as two
separate arguments matches nothing at all.** That produced a confident
"there is no `c++/v1` on this command" finding which was simply false — the
directory was there, as a single token. The general form is the one that
matters:

> **An instrument that reports a fact about the wrong thing is worse than no
> instrument, because it produces a confident falsehood.** When a probe comes
> back empty, first prove the probe can see anything at all.

Both this and the count-versus-signature error are the same mistake wearing
different clothes: trusting that a negative result means "absent", when it
only ever means "my question did not match the thing I asked about".



1. **A flag in the Makefile is not a flag on the command line.** *First,
   because this one has cost the most.* Three separate dyld defects in a row
   had exactly this shape: an undefined `SDK_SOURCE_DIR`, an `openbsm` `-I`
   dropped to clear a data file, and a `#` comment sitting inside the backslash
   continuation of `COMMONFLAGS` — which silently ended the assignment and
   dropped four `-I` paths, including the one whose absence produced the
   error everyone was chasing. Each was found by reading the file; each was
   fixed by reading the **command**. The two cheapest instruments in this
   project are `bmake -V <var>` and the echoed recipe, and both were skipped
   every time. Generalised: when a build fails on a missing header, before
   asking which copy wins, ask whether the directory is on the list **at
   all** — `clang -E -v` prints the whole search list in one shot.
2. **Never interpret a running process as a completed result.** A build is done
   when the driver says so, not when the command has not yet returned.
3. **A build or driver result is only meaningful when nothing else is writing
   to the build tree.** A driver run was invalidated once by the reader's own
   concurrent builds. Zero builders confirmed is part of the measurement, not
   a preamble. Corollary, learned the hard way: check for *any* `bmake`,
   `clang` or build script, not for the parent script's name — a wait loop
   watching the parent exited while its `bmake` children kept working, and the
   number it produced was discarded.
   **And the corollary that is easy to miss: this applies to EDITING, not
   only to building.** An edit to a shared file mid-build corrupts that build
   just as surely as a concurrent compile does. Checking `ps` before every
   *measurement* is not the same as checking before every *edit*, and only
   the first is habitual. Concretely, this round: `isysroot-cc`'s overlay
   caches self-invalidate on `$0 -nt $stamp`, so saving an edit to that
   script mid-build means the running build's **next compiler invocation
   regenerates its derived state from the new script**. The in-flight
   `libsystem_c` build was straddled — partly old overlay, partly new — and
   had to be voided and re-run. The reasoning that made it feel safe was
   "this change only affects `mach-o/` consumers", which was true about the
   *content* and irrelevant to the *timing*.
   **A measurement is only as good as the conditions under which the thing
   measured was produced, and your edit is one of those conditions.**
4. **Check which header tree actually WINS before concluding a symbol is
   absent.** There are at least three `mach/` trees sharing include guards;
   whichever comes first on the path wins and the rest are silently never
   read. The winning tree has repeatedly been one nobody guessed.
5. **Do not instrument by substitution; replacing the thing you measure
   destroys it.** The sharper form, hit this round: do not test a flag change
   by running it back *through* the wrapper, which silently rewrites the flag
   being injected. Capture the wrapper's real emitted argv (`REAL_CC=/bin/echo`)
   and run **that**.
6. **A treatment arm is evidence only if the build log shows a non-zero hit
   count.** Green-on-both-sides is the failure mode to fear, not red.
7. **A verification that cannot fail the way the real build fails is not
   evidence about the real build.** A 4,200-byte fake was needed to prove the
   stub gate works.
8. **A test broader than the question can cause the defect it was meant to
   find.**
9. **When measuring a symlink, `stat` reports the target string length, not
   the file size.** The SDK shipped `usr/lib/libSystem.dylib` as a symlink to
   an 8,064-byte stub — and that placeholder is why dylib links appeared to
   succeed. This one measurement error is load-bearing for §5.7.
10. **The assembler case-folds identifiers in diagnostics.** `UNWIND_EPILOGUE`
    appears as `unwind_epilogue`; every case-sensitive search for the reported
    string fails. Always `grep -i`.
11. **Generated stub directories are ephemeral** — a failed build cleans them,
    so the file named in the error **cannot be found after the fact**. A whole
    session concluded `unwind_epilogue` "was in no file" because the file was
    not there. Reproduce by running the build, not by searching.
12. **`bmake` rejects a comment inside a backslash continuation** (and rejects
    `.else if` outright). Put the comment above the assignment; spell it as a
    nested `.if`. **It does not always reject it, and that is worse:** given a
    whole-line comment it silently truncated `COMMONFLAGS` instead of erroring.
    See §6, lesson 1.
13. **Measure with a control.** Without one you may be reporting your own
    harness. See §6.5 for the concrete instance.
14. **Two headers can fight over one identifier, with include order as the only
    referee.** (Added 2026-09-27 from the `libdispatch` diagnosis, §7.1.) The
    mechanism is that a macro's unstressed argument is expanded **before**
    substitution, so `#define os_atomic_std(op) std::op` composed with
    `#define atomic_store_explicit __c11_atomic_store` silently rewrites a call
    into a name that does not exist. Same family as a guard collision: an
    ordering fact, not a missing declaration.

    **Now confirmed twice, independently, which is why it is stated this
    strongly.** The `libdispatch` investigation (§7.1) reached that mechanism
    from the SDK's `usr/include/stdatomic.h`. A separate dyld investigation,
    working only from compiler output and never having seen §7.1, hit the
    *same two headers colliding over the same identifier* while choosing which
    libc++ shims to force-include — and had independently already recorded
    `stdatomic.h` as the one shim that must **not** be force-included, because
    including it makes the collision worse. Two investigations, no shared
    context, same collision. This is the clearest instance yet of §5.7's
    pattern: *the sources are present and the declarations exist, and they
    still do not compose.* Treat "it is in the tree" as the start of a
    question, never as its answer.
15. **A header-guard collision is not a search-order problem, and no amount of
    reordering will fix it.** libc++'s `c++/v1/<name>.h` deliberately declines
    to define `_LIBCPP_<NAME>_H` when the C header is already open (its first
    branch is `#if defined(__need_size_t) ... #include_next <stddef.h>`), so
    the later `#ifndef` in `cstddef` fires. Moving `c++/v1` ahead of the
    shadowing `-I` was measured: 20 errors → 7, `cstddef:46` still fires. The
    fix is to force-include the shim ahead of everything, as `stdint.h` already
    was here. Two traps that each cost a round: the shim *set* must be derived
    from libc++'s own `cxxx` wrappers (a hand list missed `stdio.h` and the
    build failed on the very next header), and `stddef.h`/`stdint.h` must come
    **first** (the same 17 shims alphabetically score 5 errors, because
    `ctype.h`, `float.h` and `math.h` sort ahead and drag the C headers in
    behind).
16. **A cache keyed only on the data it derives from cannot see a change to the
    code doing the deriving.** `overlay_for` was keyed on the source tree's
    mtimes, but the strip list lives in the script body — so editing it changed
    the overlay's correct contents, invalidated nothing, and the next build
    reused the stale overlay **and reported success**. The new `libcxx_shim_list`
    reproduced the identical defect one commit after it was noticed in the old
    code, which is the strongest possible argument for keying both on the
    script. Both now test `[ "$0" -nt "$stamp" ]`.
17. **Quote the counting method with every number, or the number is not
    reproducible.** A raw `find -name '*.o'` also matches the makedepend
    artifact `.depend.._src_glue.o`, so it over-reports. This is the most
    likely reason earlier rounds gave 1, 2 and 3 for overlapping work. dyld
    counts are Mach-O objects only, per `file(1)`.
18. **One directory, one `-I`, two unrelated needs — fix by overlay, not by
    subtraction.** The openbsm root carries both a 19-byte ASCII data file
    named `VERSION` that wins libc++'s `<version>` include, and the only path
    to `sys/bsm/audit.h`. Removing the `-I` wholesale cured the first and broke
    the second. `overlay_for` now mirrors the tree and drops exactly the one
    bad entry. Note the case: the file is `VERSION`, the include is
    `<version>`, the volume is case-insensitive so they are one inode — and
    `find` reports the *on-disk* spelling, so a lowercase exclusion pattern
    silently matches nothing. 273 files in, 273 out, and the file was still
    there.
19. **A superset fix can be WORSE than a targeted one, and you must measure
    the superset.** (2026-09-27.) Force-including the **full** libc++ C-header
    shim family — 21 headers rather than 8 — turned 8 errors into **20**. The
    extra shims pulled in `stdatomic.h`, which collides with
    `Kernel/xnu/libkern/os/atomic.h` over `atomic_store_explicit` (§7.1). The
    targeted 8-header set scored 0. **The failure is not obvious in advance**:
    "include more so nothing is missed" reads as strictly safer and is not.
    Corollary: **do not add `stdatomic.h` to any force-include list, and do not
    strip it from an overlay without checking who needs it.** Both directions
    are load-bearing; a superset and a stripped set each broke something real.
20. **An isolated repro is the right instrument for finding a mechanism, but a
    mechanism proven in a repro must still be proven in the real translation
    unit.** (2026-09-27.) A hand-written `-fsyntax-only` TU finds a mechanism
    in **seconds** where a component build takes **minutes** — it is the fastest
    instrument in the project and should be reached for first. But the
    collision in §7.1 was independently found by a *different worker in a real
    build*, not in a synthetic TU, and this project has already been burned by
    a synthetic test failing to carry the include set that produces the defect.
    **Use the repro to find the mechanism; use the real TU to prove the fix.**
    The strong form of the repro uses the *actual* source file with the
    *actual* Makefile flags — that is what makes it predictive rather than
    merely illustrative (§7.4).
21. **A `-ferror-limit` abort can hide the very error you are looking for.**
    (2026-09-27, §7.4.) A TU that dies with `fatal error: too many errors
    emitted` partway through a *system* header never reaches later code, so
    your fixed error reads as **0 in both the fixed and the unfixed build**.
    That is masking, not proof, and it is indistinguishable from success
    unless you check *which* errors remain and *where compilation stopped*.
    Generalise: **"0 occurrences of my error" is not "my code compiled."**
    Confirm a fix on a translation unit that gets far enough to reach the code
    you changed — here, `block.cpp` driven through the real `isysroot-cc`,
    which is what separated the fixed atomic failure from the unrelated libc++
    one that `-ferror-limit` had been hiding behind.
22. **A fix can be real, verified, and still not make the component build.**
    (2026-09-27, §7.4.) `libdispatch`'s original blocker is genuinely fixed and
    the component still does not link, because a *second, independent* blocker
    stands in another workstream. The honest report is "**PARTIAL**", with the
    A/B table attached, not "fixed" and not "failed". Two corollaries: A/B the
    real build rather than reasoning about attribution, and never report a
    green sub-result without the count of what is *still* red — a number that
    did not move because something masked it is not a number that improved.
23. **Any fix with two sites produces a failure that looks like a NEW bug, and
    the only reliable discriminator is whether the line numbers are identical
    to the previous run.** (2026-09-27, §7.2.) `libsystem_darwin` needed
    `-DOS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE` removed from **two** places: the
    `Makefile`, and `internal.h:63` in the source, which re-set it for all nine
    of the component's `.c` files. After the first, the build still failed —
    and the failure landed on **exactly the same lines**
    (`assumes.h:130,134,157,185`, `h/cleanup.h:100,124,145`). Identical line
    numbers on a "new" error is the signature of an *incomplete* fix, not a new
    problem. **Enumerate the definers before fixing one** — here that census is
    four lines of `grep`, and it would have saved a build. This generalises
    past defines: any change with two sites, the second site re-enables what
    the first removed, and the resulting error is indistinguishable from a
    regression unless you diff the line numbers.

24. **Equal error counts are not equal failures — compare signatures, never
    counts.** (2026-09-27, §7.2a.) The old `isysroot-cc` and the new one both
    report **20 errors** on `block.cpp` and share **nothing**: the old is 17×
    `resource.h` `unknown type name 'uint64_t'` + 2× `'uint8_t'`; the new is
    16× `aligned_storage.h` + 3× `type_list.h` `reference to unresolved using
    declaration`. Reading "20 = 20" as "inert" is the exact inverse of the
    green-on-both-sides trap in lesson 5. **Lesson 6 in the other direction:
    two results that look identical may share no content.**
25. **"No global setting works" is a finding, not a dead end — and it must be
    measured, not inferred.** (2026-09-27.) `dyld` and `libdispatch` need
    **opposite** libc++ shim settings and are provably not separable by any
    subset of the shim list: `stddef.h` is *required* by dyld (all 17 minus
    `stddef.h` → 20 errors on both dyld TUs) and *harmful alone* to libdispatch
    (10 errors). Same global setting, scores 0 and 20. The end state is
    therefore **per-component opt-in** — a design change with real cost, so it
    must be *chosen* with evidence attached rather than discovered by whoever
    hits it next. When two components need opposite settings of something
    global, the answer is almost never a cleverer global value.
26. **A compiler's include path can be load-bearing for a *branch*, not just
    for types — and that makes a fix silently unexercised.** (2026-09-27,
    §7.2a.) `OS_ATOMIC_USES_CXX` (`os/atomic.h:56-62`) **defaults to 0 when
    libc++ is not on the include path**, so with the shims off, the entire C++
    block — including the colliding `os_atomic_std(op)` — is *structurally
    unreachable*, and `block.cpp` compiles clean (exit 0, empty stderr, Mach-O
    produced). The C++ path is not "broken then skipped"; it is never taken.
    Two lessons: a clean build does not prove a fix is unnecessary, it may
    only prove the fix is **unreachable**; and when a guard keys off
    toolchain availability, **"which arm am I even in?" is part of the
    result** and must be reported with it.

27. **A path that works by coincidence is a trap, and it usually looks
    deliberate.** (2026-09-27, §7.2.) `-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/…`
    concatenates to `/Users/max/Projects/build/Users/max/Projects/ravynos/…` —
    a build tree containing a copy of the source path underneath it. It
    resolves, it holds 1,251 real headers, and **nothing populates it**: last
    written 2026-08-31, no script in the repo creates it, and the
    "correctly-slashed" form that sibling Makefiles use
    (`${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS`) **does not exist at all**,
    so those flags are dangling and silently so. Three copies of the same
    1,251-file tree exist and **all three differ**. Nothing is wrong enough to
    fail, and nothing is right enough to be trusted: this is what a
    header-generation mismatch looks like while it is still invisible. **When
    an include path surprises you, establish who maintains it before you rely
    on it or change it.**
28. **"Bigger file = newer generation" has now bitten in BOTH directions, so
    stop using it.** (2026-09-27.) Two instances, opposite signs:
    - `mach_types.h`: the **in-repo** xnu copy is the **older** generation
      despite being **larger** (15,395 B vs the SDK's 9,739 B) — it lacks
      `suid_cred_*`, the SDK's has it (§5.1, notes sec. 11).
    - `mach-o/loader.h`: the **`EXTERNAL_HEADERS` overlay** is a generation
      **ahead** of the SDK copy dyld is actually written against — dyld's
      sources reference `PLATFORM_IOSMAC` **6** times and
      `PLATFORM_MACCATALYST` **0**, and the two are the same value under
      different names. The overlay won the include and broke the build; the fix
      was to drop the whole `mach-o/` directory from the overlay, because
      `fat.h`, `fixup-chains.h`, `stab.h` and `loader.h` all differ and
      per-header syncing costs a round each.

    **The measurement that replaces the date/size heuristic: count references
    to each competing spelling in the CONSUMER.** That is what makes the second
    case a measurement rather than an opinion — the consumer says which
    generation it was written against. Two instances in opposite directions is
    enough to retire the heuristic: **a heuristic that has been wrong in both
    directions is not a heuristic.**

    Note the second case is §5.1's trade reached from the other side: **bridge
    where the gap is small and enumerable, drop the tree where it is not.**
    Both are the same decision, and both are correct.

### 6.1 Five more, all from 2026-09-27

29. **A path-scoped `git add` scopes the *path*, not the *content*.** (2026-09-27.)
    With several workers editing one shared document, those are different
    guarantees and the gap is invisible until someone reads the commit.
    `git add tools/bootlab/BOOT-PLAN.md` is path-scoped and still swept in
    ~60 lines another worker had written but not committed — `git status` on
    the *directory* showed the file as modified, which looked sufficient, and
    the mistake was made independently by two workers the same hour.
    **Before staging a shared file, `git diff <file>` and ask which hunks are
    yours.** For a living document under concurrent authorship, that check is
    not optional politeness; it is the only thing standing between "committed"
    and "attributed to the wrong person". The alternative — commit forward and
    do not rewrite shared history — is usually the cheaper repair.

    **A sharper form of this, hit immediately after writing the lesson above.**
    `git commit` commits **the index**, not the paths you just named to
    `git add`. A peer's file was already staged; my `git add` named three paths
    and was correct; `git commit` then took the whole index and swept the
    peer's file in alongside them. So the check has **two** parts: not just
    *what did I just add*, but *what is in the index* — `git diff --cached
    --name-only`. Naming paths scopes what you **stage**; it does not scope
    what you **commit**. Nothing was lost, but the attribution was wrong, and
    the cheap repair is a note in a later commit rather than a history rewrite
    with three workers active.

    **Correction to the above, and the reason it is worth recording at all:**
    the swept-in change was **not** the peer's. It was an
    `EXTERNAL_HEADERS` overlay exclusion for the whole `mach-o/` directory
    (`case "$rel" in ./mach-o/*) continue ;; esac`) — authored by a third
    worker, sitting uncommitted in the index. I attributed it to the peer I
    could see, which was wrong, and the peer checked, which is the only reason
    it was caught. **The failure mode is assuming the most likely author
    rather than identifying the actual one**, and on a shared index the most
    likely author is frequently not the right one. **Read the diff before
    attributing.**

    **A second correction, and it is the peer's, and it is stronger than
    either version above.** I recorded this as a misplaced check — "run
    `git diff --cached` immediately before committing". **That would not have
    helped**, because the other worker *did* exactly that: they ran
    `git diff --cached --name-only` immediately before their `git commit`, it
    printed exactly their three files, and none of mine was in the index at that
    moment. **My commit then landed between their check and their commit and
    took the whole index.**

    **So the defect is a TOCTOU race across a shared mutable index, not a
    habit.** The correct statement is theirs:

    > **With N workers on one index, a correct pre-commit check proves the
    > index was correct when you *read* it, and says nothing about what it was
    > when you *committed*. The check is necessary and it is not sufficient.**

    **First consequence:** the real fix is structural, not procedural — a
    worktree per agent, or a commit that takes explicit content rather than
    whatever the index holds. Neither is available while three workers share a
    tree, so the honest response is to **check after the fact**
       (`git show --stat HEAD`) and repair by attribution note rather than by
    history rewrite.

       **Second consequence, and the reason this is a lesson:** *the check cannot
       be made reliable by doing it more carefully.* A correct, well-placed check
       still lost the race. The instrument was fine; the guarantee it was supposed
       to provide does not exist.

       That is the **fourth** time today a well-formed check was defeated by
       something outside its reach: the `cat -A` that could not see validity
       (lesson 31), the `-fsyntax-only` repro that could not reach the atomic
       header (lesson 21), the numbering gap I read as a deletion (lesson 32), and
       now an index check that cannot survive the gap between reading and
       committing. **Know which of your instruments are advisory and which are
    load-bearing, and never lean on an advisory one for a guarantee.**
30. **A force-include that fixes a missing declaration usually means the
    include path is wrong, and here it demonstrably is.** (2026-09-27, §7.2.)
    The sharpest statement of that anti-pattern this project has produced, and
    it is stated as a rule rather than an anecdote because the failure mode is
    seductive: **a force-include works.** The build goes green, the include
    path stays wrong, and the next component inherits it. The proof available
    here was that the same declaration was reachable from a *different
    generation* elsewhere on the search list — `os/log_private.h` was found,
    it was xnu's, and it defined none of the five symbols `assumes.h` needed.
    **Before reaching for a force-include, run `clang -E -H` and read which
    copy answered.** The default reading of "a force-include made it compile"
    should be "the search order is wrong, and this is now hiding it".
31. **A result identical to a previous run is evidence the LOG is stale, not
    evidence the fix did nothing** — and a byte-level check cannot tell you
    whether a fix is *valid*. (2026-09-27, found by `plan` on their own
    build.) Queued builds kept reporting the same 9 "invalid preprocessing
    directive" errors at `internal.h:63-67`. Two polling wrapper jobs had
    fired in sequence and the older one's output was read as the newer one's
    result.

    **The root cause was NOT what it first appeared to be, and the correction
    is the useful part.** The stated cause here was angle brackets inside a
    `#` comment. That was wrong. **This toolchain rejects `# prose` comments
    in a C header outright** — verified minimally against a stock Apple clang
    on this host, where even `# hello world` is an invalid preprocessing
    directive. Only `#define`-style directives, `//` and `/* */` are accepted.
    The same text is perfectly valid in a Makefile, because bmake eats the `#`
    before the compiler ever sees the line — **which is exactly why the
    mistake survived: the same characters are correct two files away.**

    **How the wrong cause was "verified":** `cat -A` on the block, which
    showed clean `# ` lines and no `<` anywhere, and therefore appeared to
    prove the cause was gone. **A byte-level check answers "did my edit land",
    never "is this valid".** For validity you compile a two-line file. The
    build said no three times in a row and the plausible verification was
    what got trusted over it.

    **The rule, in two halves.** Before quoting any number, ask what the
    previous number was: if they are identical, the first question is not "did
    this fix do nothing" but "am I reading the same file twice" — check the
    log's own timestamp and the mtime of the source it claims to have
    compiled. And when a fix is supposed to have removed an error, **verify
    the error is gone by reproducing its absence, not by inspecting the
    source.** With several arms in flight across several workers this is not
    hypothetical; it is the default failure mode of parallel measurement, and
    it yields a result that is internally consistent and completely fictional.

32. **A lesson you can still fall into within the hour was not learned, only
    written — and the fall is the proof, not the failure.** (2026-09-27.) In one
    session the `bmake` backslash-continuation trap was found, written up as a
   lesson, committed, and then walked straight back into **while editing an
   unrelated line** in the same file: an explanatory comment placed *inside* a
   backslash continuation silently truncated `LDFLAGS` to 6 tokens. Caught
   immediately by `bmake -V LDFLAGS` — which is precisely the instrument that
   lesson prescribes, and which existed *because* of the earlier instance.

    **The general form, and it is the useful part: the cost of a lesson is not
    reading it, it is the first time you edit a file it covers.** Recording a
    lesson lowers the probability of the mistake; it does not remove the need
    to check, and the check is what actually catches it. Anyone who claims a
    lesson is "learned" on the strength of having written it down is
    describing a document, not a habit.

    **The saving grace was that the instrument already existed.** The check
    that caught the repeat was created by the first instance. That is the
    strongest argument for writing instruments down rather than only
    conclusions: the conclusion is re-readable, the instrument is
    re-runnable, and only one of them helps at 4pm on an unrelated edit.

    **And the corollary, which is this one: I then reported a document-integrity
    problem that did not exist.** I claimed lesson 32 "had been lost to a
    concurrent edit" and that the shared document was "losing entries under
    three-way edits". I had inferred deletion from a **gap in the numbering**,
    without reading the surrounding text. It had been **merged into lesson 31**
    — the peer had folded my `# prose` finding and the stale-log finding into one
    lesson, correctly, and renumbered. The content was there the whole time; I
    reported a phantom because I had spent the day learning that a plausible
    reading of a document is not a reading of the document, and then did it anyway
    on a *numbering* rather than a measurement.

    The peer checked, could not reproduce it, and said **"I cannot reproduce
    it"** rather than inventing a cause — which is the correct response to an
    unreproducible claim about one's own work, and strictly better than either
    defending it or conceding it. Verified since: lessons 1–32 contiguous, no
    gaps, no duplicates; and the `6.2 → 6.5` heading jump is pre-existing,
    with 6.3 and 6.4 never having existed in 25 revisions.

    **The rule, and it generalises past documents: a gap is a hypothesis, not
    a finding.** Read what is on both sides of the gap before reporting what is
    in it. A numbering gap is exactly as ambiguous as a zero error count, and I
    had already written the lesson about the zero.

### 6.1a Commands — the instrument for each recurring question

Everything in §6 is a **conclusion**: re-readable, not re-runnable. This is the
other half — the mapping from question to command, so nobody re-derives which
tool settles which argument. Compiled from the instruments that actually caught
something on 2026-09-27.

| question | command | what it settles |
|---|---|---|
| **Which header tree actually won?** | `clang -E -H <tu> \| grep <header>` | the whole resolution chain, one shot. Replaces any amount of `grep`-ing for the declaration. **Lesson 6.0.** |
| **Is this `-I` even on the path?** | `clang -E -v` (or `-H`) | prints the entire search list. First question when a build fails on a missing header — before asking *which copy* wins, ask whether the directory is there at all. |
| **Did the flag/define reach the compiler?** | `REAL_CC=/bin/echo <wrapper> <flags>` | the wrapper's **exact emitted argv**, no build. Settles "a flag in the Makefile is not a flag on the command line." Also the only way to see a joined token like `-isystem$dir`. |
| **Did bmake see my edit, whole?** | `bmake -V LDFLAGS` (or any var) | catches a `#` comment inside a backslash continuation, which truncates the assignment **silently**. Caught a repeat of this within the hour it was written down. |
| **Is this object count real?** | `find -name '*.o'` filtered by `file(1)` → Mach-O only | a raw `find` also matches the makedepend artefact `.depend.._src_glue.o` and over-reports. **Always quote the counting method with the number.** |
| **Is the atomic/C++ branch even reachable?** | `clang -E` a TU that uses the guarded name, and read the expansion | a guard keyed off toolchain availability can make a whole code path **unreachable**; a clean build then proves nothing. "Which arm am I in?" is part of the result. |
| **Did my edit actually change behaviour?** | `clang -fsyntax-only` on the **real** TU with the **real** Makefile flags | seconds, versus minutes for a component build. Use the real source and real flags or it is not predictive. |
| **Is this number the same as last time?** | compare log mtime against the source mtime it claims to have compiled | identical results across runs **separated by an edit** mean a stale log. See lesson 31. |
| **Is that result trustworthy at all?** | run the probe against something you know is there | a negative needs a positive control. **Lesson 6.2** — four probes in this project failed exactly here. |
| **Which mach/SDK generation is authoritative?** | `grep -c` each competing **spelling** in the **consumer** | not size, not date. The consumer says which generation it was written against. Lesson 28. |
| **Is my CHECK the thing that is broken?** | re-read the thing itself before reporting it as corrupt | **a measurement can be the defect.** An integrity script flagged "lesson 8 suspiciously short, 85 characters" in a document that was completely intact — the regex had measured an indented continuation fragment instead of the lesson, which was merely renumbered. Had the script been believed, a false corruption report would have entered the shared record. The sibling failure is a *negative* that should have been a positive. Lesson 6.2. |
| **Did that link do the right thing, and will it LOAD?** | **three gates — see the box below** | a link that succeeds is not a link that is correct, and it is not a library that loads. `-lSystem` resolves to a 4,120-byte `libSystem.B.dylib` with **0** exports; the link passes and the result is a placeholder. §5.5. |
| **Does dyld resolve this symbol, or does `nm`?** | `dyld_info -exports <installed dylib>` **and** `nm -gjU <same>`, then diff the two sets | **`nm` measures the SYMBOL TABLE; dyld resolves from `LC_DYLD_EXPORTS_TRIE`.** They are different structures and they can disagree. Run **both**: if they agree, either will do; if they differ, **the trie wins and the difference IS the finding.** A dylib with a populated trie and no `LC_DYLD_CHAINED_FIXUPS` is fine; one with an **empty** trie exports 205 names to `nm` and resolves none. Never gate on `nm` alone. |
| **Is this artifact's binding form one dyld will accept?** | `otool -l <installed dylib> \| grep -E 'LC_DYLD_(INFO_ONLY\|EXPORTS_TRIE\|CHAINED_FIXUPS)'` | distinguishes *populated trie under `LC_DYLD_INFO_ONLY`* (works — measured, 1,470 names, identical to `nm`) from *empty trie* (silently unloadable). A matching load-command profile is **evidence of the same class of defect, not proof of the defect** — the demo is adding `-Wl,-fixup_chains` and seeing the command appear. |

> ### The three gates, and the third is the only one that is not a proxy.
>
> For **any** dylib, in this order:
> >
> 1. **Exports dyld can see** — `dyld_info -exports` on the **installed**
>    artifact, crossed against the `otool -L` closure. *Never the archive, never
>    the build directory, never `nm` alone.*
> 2. **The load-command profile** — is there a **populated** export trie, and
>    under which of the two binding forms?
> 3. **An actual load.** *Neither of the first two is evidence of this.*
> >
> **Gates 1 and 2 are static, and every load-bearing property measured in this
> session so far is static** — 617,080 B, 1,470 exports, 12 undefined, 5
> residual, all true, none of it evidence of loadability. The reason is
> `bsd.sys.mk:541`: the link is **incapable of failing**, and an empty export
> trie is the same story one level down, with `nm` the same story two levels
> down. **Three libraries in this project have now passed gate 1 and would still
> not load.**

**The one-line version:** if you cannot name the command, you have a
conclusion, not a check.


33. **A link that SUCCEEDS is not evidence the link is correct — and check the
    export count, not the exit status.** (2026-09-27, §7.4b.) I measured
   `-nodefaultlibs -lSystem` and it produced a dylib, so I called the next
   blocker "cheap". A peer checked what it had linked *against*:
   `usr/lib/libSystem.B.dylib`, **4,120 bytes, 0 exported symbols** — a
   placeholder — while the 26 real dylibs that would compose a libSystem sat
   beside it with 98 to 1,342 exports each. A `libdyld.dylib` built that way
   installs cleanly, appears in the SDK, and resolves nothing at runtime.

   **This is §5.5 exactly, and the symmetry is the lesson: the same error is
   available in both directions.** "A stub that fails" is caught by the build;
   "a stub that links" is caught by nothing until runtime. So the discipline has
   a second half — after a link succeeds, **ask what it linked against**
   (`nm -gU <lib> | wc -l`), because a zero count is invisible to every
   existing gate and is the exact condition §5.5 was written about.

   **And the generalisable form: a successful operation proves the operation
   ran, not that it did the right thing.** This is the third instance today of
   the same shape reached from different directions — *undeclared identifier*
   meaning the header resolved, *0 hits* meaning the probe could not see, and
   now *link succeeded* meaning ld64 stopped complaining. All three are clean
   results in which the absence went unfelt rather than away.

### Why the read-only instruments won — and it is not that they are better

`clang -E -H` and `bmake -V <var>` found **more real defects** this session
than any build-configuration change made. **That is not a fact about the
commands. It is a fact about when each kind of tool is available.**
Every flag change needs a **quiet tree and a clean slate**, which on a shared
tree is rarely either. Every read-only instrument needs **neither**, so it
works while three workers are building — which is most of the time.
**The expensive tools are unavailable exactly when you most want to check
something, and that biases a team toward editing rather than looking.**

The consequence, stated as arithmetic: **a flag change converts a question
into an assumption that then has to be defended.** Two of the ten dyld
defects were found by reading a file; **none** was found by configuring one.
Of the flags changed that round, all but one needed defending afterwards —
which is the real cost, and it is invisible in a commit that looks clean.

**So the practice that follows is not "prefer cheap tools" but "read before
you configure, and record what you read."** The configuration change is
rarely where the defect is; it is where a defect becomes expensive to find,
because it now sits behind a clean build.

### 6.2 The positive-control rule, and the four probes that broke it

> **A negative result from any probe must be accompanied by a positive
> control proving the probe CAN see the thing it is looking for. "0 hits" is
> only evidence after you have shown the probe produces non-zero hits when
> something is there.**

**Not one of the four below was a mistake about the code.** Every one was a
mistake about the *instrument*, and every one produced a negative that read
exactly like a finding. That is what makes them dangerous: they are
indistinguishable from a result until you go looking for the control.

1. **Two error SETS read as "inert" because they were disjoint.** Comparing
    the "before" and "after" arms of the libc++ shim A/B, both reported **20
    errors** and shared **none** of them. Disjointness was initially read as
    "the change did nothing", which is the exact inverse of the truth. The
    control is not a count but a *containment* test: one arm's signature must
    appear in the other's, or the arms are describing different failures and
    the comparison has no meaning.
2. **A two-token check blind to a one-token emission.** `isysroot-cc` emits
>    `-isystem$dir` as a **single joined token**. A grep for `-isystem <path>`
>    as two arguments matches nothing, and produced a confident "there is no
>    `c++/v1` on this command" — false, the directory was right there. **Read
>    the emitter before writing the matcher.** The control: run the matcher
>    against a line you know contains the token.
3. **`comm` on whole `#define` lines conflates "defined differently" with
    "not defined".** Used to compare the `PLATFORM_*` block across two
>    `mach-o/loader.h` generations. It **happened to give the right answer for
>    the wrong reason**, which is the most dangerous kind, because a correct
>    answer suppresses the question. Compare the *identifier* (`awk '{print
    $2}'` on a `^#define NAME VALUE` line), never the line. The control is
    the same: a probe that cannot distinguish two different things is not a
    probe.
4. **A regex census reporting 2 symbols where the union was 12.** A pattern
    too narrow reads as a small, confident, wrong number. Any census must be
    checked against a known-larger set before its result is quoted.

**And the fifth, from the same round, which is the one that nearly shipped.**
The `mach-o/` overlay strip was committed, and the live overlay still
contained all ten `mach-o/` entries — read as "the strip condition does not
match", and the cache's `[ "$0" -nt "$stamp" ]` test correctly said NO, which
read as "the cache is stale". **Both were wrong.** A regeneration into a
scratch `ROOT_BINARY_DIR` gave 0 `mach-o` symlinks, 0 `Availability*`, and
127 total — and `ptrcheck.h` *present*, which is what proved the overlay was
 populated rather than empty. The two working strips travel the same `case`
 statement, so `Availability*` is the ideal control for a `mach-o/` probe:
 **0 for both means both fired; a populated non-`mach-o` header present means
 the probe is not simply reading an empty directory.** See
 LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 30.

**The habit, stated once:** when a probe returns zero, the next action is to
make it return non-zero on purpose. A probe you have never seen fire is not
yet an instrument.


### 6.5 The control-arm lesson, in full

The most expensive single measurement error in this project, preserved because
it recurred:

The mach-generation probe ran a **treatment** arm (`-I${XNU}/osfmk` first) and
a **control** arm (SDK first). Both reported
`rc=0 693 objects 0 errors`. The result was recorded as "NOT MEASURED, and NOT
attempted again" — and correctly distrusted, but only after the false GREEN
had already been believed once.

Flagged later by `critical-path` (2026-09-27): the `rc=0` in that log line is a
**compile-stage** figure. The link stage fails in both arms, identically, on
`ld: library 'system_trace' not found` — sec. 20's documented `libsystem_trace`
blocker, unrelated to mach headers. So the standing gate was carrying a stale
half that no run can reproduce. It is now **"693 objects, 0 compile errors"**,
with the link failure recorded separately as a known, expected, arm-independent
failure. The number never changed; only the stage it is read at.

Two independent causes, both worth remembering:


1. **`EXTRA_INCLUDES` does not survive `build-libraries.sh`'s environment into
   the bmake sub-makes.** It is re-exported there now (line 57). The argv
   capture proves the fix is neither absent nor over-broad: unset/empty adds
   nothing; with one argument set, byte-identical for assembler inputs.
2. **The overlay was never consumed by a single translation unit.** The probe
   had no mach header at all — its build path was never wired.

**A collapsed probe is a finding, not a null result:** a probe that silently
did nothing is not "not measured", it is *identical to success* in the
summary. The direct-wrapper proof was valid; the build path was not. **The
control arm is what made the difference visible**, and without it the same
build would have been reported as two independent confirmations.

---

## 7. The two diagnosed failures

Both are **pre-existing**. Both were diagnosed by reading, not by building.
**No fix has been applied to either.**

### 7.1 `libdispatch` — macro expansion order, not a missing C++ branch

**Error:**
```
Kernel/xnu/libkern/firehose/chunk_private.h:173: error: no member named
    '__c11_atomic_store' in namespace 'os_atomic_std'
...:187: same, for __c11_atomic_store
...:189: error: no member named '__c11_atomic_fetch_sub'
(each with 'address argument to atomic operation must be ...')
```

**Include chain:** `block.cpp:31` → `src/internal.h:1136` →
`src/firehose/firehose_internal.h:39` →
`Kernel/xnu/libkern/firehose/private.h:29` → `chunk_private.h:173`.

**Root cause (established by reading, then confirmed by reproduction).** Two
definitions collide, and include order is the only referee:

- `Kernel/xnu/libkern/os/atomic.h:69` — `#define os_atomic_std(op) std::op`
  (the C++ branch, taken because the TU is C++ and `KERNEL` is undefined).
- the generated SDK's `usr/include/stdatomic.h:131` —
  `#define atomic_store_explicit __c11_atomic_store`.

`op` is used **unstressed** in the replacement list, so the argument is
macro-expanded **before** substitution. Therefore:

    os_atomic_std(atomic_store_explicit)(p, v, os_atomic_std(memory_order_relaxed))
    =>  std::__c11_atomic_store(p, v, std::__c11_atomic_relaxed)

`std::__c11_atomic_store` does not exist. Reproduced exactly, in a throwaway
`-fsyntax-only` TU outside the repo:

    error: no member named '__c11_atomic_store' in namespace 'std'
    error: address argument to atomic operation must be a pointer to _Atomic type

**This settles the open question in the task:** the C++ branch of the atomic
header is **not** incomplete, and no guard is being defeated. The C++ branch is
taken correctly and does the right thing. The failure is that a *second* header
has already defined the identifier as a macro, and the unstressed argument
converts a correct C++ call into a C11 builtin name qualified by `std::`.

The `os_atomic_std` in the message is the macro, not a namespace — worth
stating because **`namespace os_atomic_std` exists nowhere** in the repo, the
SDK, or the build tree, and a reader who greps for it will find nothing and may
conclude the error is fabricated.

**Proven pre-existing:** fails identically with the `isysroot-cc` from commit
`1f0e802`, before both force-includes.

**Candidate fixes, and which to reject:**

- ❌ **Editing `chunk_private.h`.** It is **kernel libkern**, shared with the
  kernel build, and it is *correct* — it uses the documented portable spelling
  that works in both C and C++. Editing it fixes one component by breaking the
  kernel. **Never.**
- ❌ **A userspace shim that redefines `os_atomic_std`.** Same defect class as
  the `libobjc` stub in §5.5: it would make the failure disappear without making
  the code work.
- ❌ **Reordering the includes.** **Measured: does not work, in either
  order.** `os/atomic.h` first then `stdatomic.h` → the original 5 errors.
  `stdatomic.h` first then `os/atomic.h` → *different* errors, because the
  already-defined `__c11_*` macros corrupt libc++'s own `<atomic>`. The reason
  reordering cannot work is the same mechanism as the bug: the argument is
  expanded **at the use site**, so whatever order the two headers were read in
  is irrelevant by the time `chunk_private.h:173` is compiled. This is the
  "just reorder the includes" answer a future session will otherwise try.
- ❌ **Undefining the C11 operation macros in C++ mode.** Measured: 5 errors
  become **20**. `src/shims/lock.h` and `shims/atomic.h` genuinely call the
  unqualified C11 spellings, and `shims/atomic.h:30-32` `#error`s without
  `<stdatomic.h>`. Removing the macros breaks the component's own C11 code.
  This is also the shape of the superseded superset in lesson 14.

### 7.1a The fix that was applied

**`-DOS_ATOMIC_USES_CXX=0` in `Libraries/Libsystem/libdispatch/Makefile`.**

This selects `os/atomic.h`'s C11 branch, so `os_atomic_std(op)` → `op` →
`__c11_atomic_store` **unqualified**, which exists. The two headers stop
fighting because only one of them is now authoritative for atomics in this
component.

**Why this is principled rather than a paper-over.** libdispatch is a **C11
component by construction**: `src/shims/atomic.h:30-32` hard-`#error`s unless
`<stdatomic.h>` is present, and every atomic in the component goes through
those C11 spellings. The C++ branch of `os/atomic.h` was the *intruder* — it
is correct for a C++ program that wants `std::atomic`, and wrong for a C11
component that has already committed to `_Atomic`. Aligning the two in favour
of the component's actual language is not silencing; it is choosing the branch
the code was written against.

**Earlier in this round I recorded this same candidate as a "control, not a
fix".** That was wrong, and the correction is worth keeping: I rejected it for
being global. It is **not** global — it is one define in one component's
Makefile — and I had not measured it before ranking it. The lesson is lesson
**5**: rank nothing you have not run.

**Blast radius, bounded explicitly:**

| Scope | Affected? | Why |
|---|---|---|
| C TUs of any component | **No** | `OS_ATOMIC_USES_CXX` is only consulted when `__cplusplus`; in C the header takes the C branch regardless. |
| The kernel build | **No** | `Kernel/xnu` is not edited. The kernel's own build does not read `libdispatch/Makefile`. |
| Any other component | **No** | The define is local to `libdispatch/Makefile`'s `CFLAGS`. Nothing includes that Makefile. |
| `Libraries/Libsystem/private/` | **No** | Not touched. |
| `stdatomic.h` itself | **No** | Not modified. The SDK header stays byte-identical. |

**Proof it is a real fix and not a silencing artifact** (lessons 6 and 12 — the
assert was negative-controlled, and it fires): the type of
`firehose_chunk_pos_u::fcp_atomic_pos` (`chunk_private.h:40`) is

- **`std::atomic<uint64_t> volatile` WITHOUT the fix** (the C++ branch, and the
  collision), and
- **`_Atomic(uint64_t) volatile` WITH the fix** (genuine C11 atomic
  semantics).

A deliberately-wrong variant of the same `_Static_assert` was compiled to
confirm the assert *can* fail. It did. So the two results are a real
difference in the emitted type, not a compiler that had stopped complaining.

**Independently confirmed from a second direction.** The `dyld` worker hit the
same collision — `stdatomic.h` versus `Kernel/xnu/libkern/os/atomic.h` over
`atomic_store_explicit` — while force-including the full libc++ shim family,
and measured that the 21-header superset was **worse** than the targeted
8-header set (lesson 14). Two workers, different tasks, same two headers, same
identifier, arrived at independently. This is the strongest single piece of
evidence in the project and it is the clearest example yet of the §5.7
pattern: **the sources are all present; the declarations collide.**

### 7.1b The libc++ shim family is PER-COMPONENT, and the `stdint.h`
exoneration, stated precisely

**A second worker reported 19 new libc++ errors in `libdispatch`**
(`__type_traits/aligned_storage.h`, `__type_traits/type_list.h`,
"reference to unresolved using declaration", reached via `<limits>:827` →
`<type_traits>:428`) and correctly declined to touch `isysroot-cc`, which
another worker owned. The attribution was tested rather than accepted.

**What `stdint.h` in the shim family is NOT responsible for, precisely:**

- It **predates the shim family.** It was in the wrapper before commit
  `a71c46f5ac`, which only widened the set from 1 shim to 17.
- It **breaks `block.cpp` by itself.** Force-including the single
  `c++/v1/stdint.h` shim, with the other 16 removed, reproduces a hard
  failure in `block.cpp` on its own.
- **`libdispatch` was already blocked before any of this work** — §7.1's
  `__c11_atomic_store` failure, proven pre-existing against `isysroot-cc`
  from `1f0e802`.

So the shim work **swapped one failure for another on a component that was
already red**. That is materially different from "it broke libdispatch",
and the difference is the whole content of this entry.

**A/B, on real builds, comparing error SIGNATURES and not counts** (the
lead-in lesson in §6):

| component | with shim family | without |
|---|---|---|
| `dyld` | **16 objects** | **8 objects** |
| `libdispatch` | **19 libc++ errors** | **0 libc++ errors** (different, pre-existing fault) |

The two "20 errors" readings that made this look like a wash shared **no**
error text between them. A count-based reading would have concluded "no
change" and been wrong twice.

**No subset separates them.** `stddef.h` is **required** by `dyld` and
**harmful alone** to `libdispatch`; the family is load-bearing as a set.
The two components need opposite settings, so a global rule cannot serve
both. Hence the shim family is now **opt-in per component**:
`isysroot-cc` applies it only when it sees
`-DRAVYN_LIBCXX_SHIM_FORCE_INCLUDE=1` in the argument list, and
`Libraries/dyld/Makefile` is the one component that passes it.

**Why a `-D` and not an environment variable.** The define travels *on the
compiler command line*, which is the one channel demonstrated to reach the
bmake sub-makes — `EXTRA_DEFINES` does not survive `build-libraries.sh`'s
environment, and "a flag that looks set but never reaches the compiler" is
the dominant failure mode in this project. It is also self-documenting: a
reader of `Libraries/dyld/Makefile` sees why dyld needs this, next to the
code that needs it. Default is **off**, so a component that has not asked
emits nothing.

**Inertness, by `REAL_CC=/bin/echo` argv capture, byte for byte against the
previous wrapper:** plain C, `-x objective-c` and `-x assembler-with-cpp`
all **byte-identical**; a C++ TU with the define absent emits **0** shims
(it emitted 17 before); a C++ TU with the define emits the intended 17.
The `__cplusplus` gate stays tight — a **bare `-x` emits 0** even with the
define present, which is the bug that was found and fixed once already.

#### Was the shim trigger global? CONFIRMED on the trigger, REFUTED on the path

The escalation asked whether `isysroot-cc`'s trigger is a **filesystem check
on the SDK** rather than a check of what the component's Makefile actually
passed — and if so, whether it had been silently altering the include path of
every C++ component in the tree. Both halves were measured, and **the answer
is yes for the trigger and no for the path**:

- **The trigger WAS global, and that was the defect.** It tested
  `[ -d "$s_root/usr/include/c++/v1" ]` against whatever sysroot the
  invocation named. Every component that passes `--sysroot=$RAVYN_SDKROOT`
  satisfies it, regardless of whether its Makefile ever mentioned `c++/v1`.
  `libdispatch/Makefile` contains **0** occurrences of `c++/v1` and was
  still force-included 17 libc++ shims. This is now gated.
- **The PATH was never the wrapper's doing, and the opt-in does not need to
  fix it.** Raw `clang -isysroot $SDK -x c++ -E -v` — wrapper not involved
  at all — already lists `$SDK/usr/include/c++/v1` in its search path.
  **clang adds it itself, from the sysroot.** Control: the same invocation
  against a sysroot with no `c++` yields 0. So libc++ was reachable for
  every C++ TU regardless of what any Makefile asked for; the wrapper never
  widened the path, it only injected `-include` arguments.
- **The `-isystem` rewrite was never in play for `libdispatch` either.** It
  fires only on an `-I` argument ending in `/usr/include/c++/v1`.
  `libdispatch/Makefile` passes 0 such `-I`, so the wrapper emitted 0
  `-isystem` tokens for it. Verified in the wrapper's own emitted argv for a
  libdispatch-shaped command: **0 shims and 0 `-isystem c++/v1`**.

**So the opt-in gates the only thing that was actually global.** The
path-level concern is real but is clang's behaviour, not the wrapper's, and
it is not a regression introduced here. The blast radius of the *fix* is
therefore bounded: the shim `-include` list, on C++ components that did not
opt in.

#### Result, measured on a verified-quiet tree

`ps` for `bmake` / `build-libraries.sh` / `isysroot-cc` confirmed **zero
builders** before both builds.

**`dyld`: 16 Mach-O objects, unchanged.** Counting method: Mach-O objects
only, counted per file(1) and each one *verified* with `file` — which is what
excludes the three `Libraries/dyld/.depend.._src_*.o` makedepend artifacts,
since `file` reports them as ASCII text, not objects. Also excludes the
pre-existing deleted `unit-tests/.../bar.o`, untouched. A raw
`find -name '*.o'` over-reports as 19, which is why earlier rounds
disagreed. Frontier unchanged:
`dyld3/APIs.cpp:338:14: error: use of undeclared identifier 'PLATFORM_IOSMAC'`
— and by §6.0 that error is evidence `mach-o/loader.h` **resolved**.

**`libdispatch`: builds and links, exit 0.** 32 Mach-O objects and a real
912,240-byte `libdispatch.dylib`, installed into the SDK. **Zero** error
signatures. The component had been failing on the `__c11_atomic_store`
collision (§7.1) as well, so removing the shims cleared both.


### 7.2a The repro instrument (applies to both failures)

**Instrument:** `clang++ -fsyntax-only` on the **real** `block.cpp` with
**libdispatch's real `CFLAGS`** copied from its Makefile. No `-c`, no `-o`,
nothing written into the repo or the generated SDK.

- **~2 seconds**, against **minutes** for a real `bmake` build of the
  component. It is the fastest instrument in the project.
- It reproduced the failure **exactly**: same file, same lines
  (173/187/189), same 5 errors, before the fix; **0 errors** after.
- Using the *actual* source file with the *actual* Makefile flags is what makes
  it predictive. A hand-written 6-line TU finds the same mechanism, and is
  still worth doing for exploration, but it is weaker evidence — see lesson
  15.
- It is also **non-interfering by construction**, which is why the diagnosis
  was reachable while two other workers held the tree. It writes nothing into
  the build tree, so it cannot corrupt anyone's measurement (§4.1).

**Every candidate was measured, not ranked by argument.** Six candidates were
tried; the scores were 5 (baseline), 20, 20, 20, 5, **0**. Three of them
"should" have worked by reasoning alone.

**The candidate map — what does NOT work.** This is the most reusable artifact
in this section. Every row was measured on the real `block.cpp` with the real
Makefile flags; none was rejected by argument.

| # | candidate | errors | verdict |
|---|---|---|---|
| — | baseline (no fix) | 5 | the failure |
| A | undef the C11 op macros in C++ | 20 | **breaks** `shims/lock.h`; the component is C11 by construction |
| B | A + `using std::` declarations | 20 | same, plus `memory_order` conflicts |
| C | guard the C11 macros on `!__cplusplus` | 20 | same as A by another route |
| D | `-include` a header redefining `os_atomic_std` | 5 | **no effect** — a `-include` runs *before* the sources, so `stdatomic.h` redefines the macros afterwards |
| E | **reorder the two headers** | 5 / *different 5* | **fails both ways**; the argument expands at the use site, so read order is irrelevant |
| F | `-DOS_ATOMIC_USES_CXX=0` | **0** | **the fix** |

Rows A–C and D are the ones that "should" have worked by reasoning. **Four of
 six plausible candidates are wrong, and measuring is the only way to know
 which.**

**Outcome: CLEARED (2026-09-27). The component builds and links.**

The three states this section was tracking have resolved into one:

1. **No longer failing on the atomic collision** where it is reachable —
   measured, and the measurement stands below.
2. **No longer failing on the libc++ error.** The shim family is now
   per-component (§7.1b), and `libdispatch` does not opt in.
3. **Building and linking** — 32 objects, a real 912,240-byte
   `libdispatch.dylib` in the SDK, zero error signatures, on a `ps`-verified
   quiet tree. **One of the two UNEXPECTED driver failures is cleared.**

**Both causes turned out to be one.** The atomic collision and the shim
trigger were cleared by the same per-component change, because the trigger was
global: a *filesystem check on the SDK* rather than a check of what the
component's Makefile asked for, so libc++ was being pulled onto every C++ TU
in the project. **`libdispatch`'s Makefile carries no `-I …/c++/v1` at all.**

**`-DOS_ATOMIC_USES_CXX=0` remains, in exactly the terms claimed for it:
insurance that pins the C11 branch so the collision cannot return — not a fix
that moved a number.** It is still correct, still scoped to one Makefile, and
still worth carrying; it is not what unblocked this component.

**The measurement — and neither number in it is `libdispatch`'s state.**

| configuration | errors | `c11_atomic` |
|---|---|---|
| libc++ forced onto the path, **without** the define | **5** | 12 |
| libc++ forced onto the path, **with** the define | **0** | 0 |

The 5 errors are exactly those §7.1 diagnosed, and the define removes them.

**But this table is a controlled experiment, not a report of the component.**
Neither arm corresponds to a configuration the real build actually takes:

- The `libdispatch` Makefile carries **no `-I .../c++/v1` at all** — not as a
  separate flag and not as a joined one. The only reason libc++ appeared on
  this TU was the `isysroot-cc` shim family, whose trigger is a **filesystem
  check on the SDK**, not a check of what the component's Makefile asked for.
  So the shim family was pulling libc++ onto **every C++ TU in the project**,
  including components that never wanted it.
- A second worker, measuring the same component and shim set in a real build,
  got **19 libc++ errors and no `c11_atomic` at all** — a different arm
  entirely, most likely a different `-ferror-limit` cutoff. Unresolved at the
  time of writing, and deliberately not guessed at.

**So: do not quote either number as `libdispatch`'s state.** They are two arms
of an experiment. The discrepancy closes when the per-component opt-in
(§7.1b) makes **exactly one** real configuration possible, at which point one
build on a verified-quiet tree gives the true state. Until then the honest
entry is *"whatever remains, not yet measured."*

**It is also worth noting what the two arms agreed on: nothing.** 5 errors and
19 errors, zero shared messages. Two workers, same component, same nominal
shim set, and the measurements are not comparable — which is precisely the
counts-vs-signatures lesson (§6 preamble) arriving from the other direction.

**But the fix is currently UNEXERCISED, and that is the important caveat.**
`OS_ATOMIC_USES_CXX` (`os/atomic.h:56-62`) **defaults to 0 when libc++ is not
on the include path**. With the shim family off — now the default, and
libdispatch's setting under §7.1b — libc++ is not on this component's path at
all, so the entire C++ block containing `os_atomic_std(op)` is
**structurally unreachable** and `block.cpp` compiles **clean**: exit 0, empty
stderr, Mach-O produced. The path is not "broken then skipped"; it is never
taken.

So the accurate statement is: **`-DOS_ATOMIC_USES_CXX=0` is
correct-by-construction but currently unexercised**, and it is *not* what
unblocks `libdispatch`. What unblocks it is the shim setting (§7.1b). The
define is insurance — it pins the C11 branch so the collision cannot return if
libc++ is ever put back on this component's path — and insurance is worth
having, but it must not be reported as a fix that moved a number.

This is lesson 25: **a clean build does not prove a fix unnecessary, only
possibly unreachable** — and when a guard keys off toolchain availability,
"which arm am I even in?" is part of the result.

**The masking trap, in full, because it produced a false result here first.**
The first real build reported `c11_atomic=0` in **both** arms — with and
without the define. That is not a fix, it is `fatal error: too many errors
emitted [-ferror-limit=]` firing **inside libc++**, before compilation ever
reaches `chunk_private.h:173`. The `dyld` workstream independently reached the
same conclusion from the other side and, importantly, caught the second-order
error too: **"20 = 20" is not "inert".** The old wrapper and the new one both
print 20 errors and share **nothing** — different files, different messages.
Never compare counts; compare signatures (lesson 6, both directions).

**A third, independent blocker class also exists, and it is not ours.** With
the shim set at `stdint.h`+`stddef.h` (the *pre-existing* setting, before the
shim-family change), `block.cpp` fails with **17× `resource.h` `unknown type
name 'uint64_t'`** and 2× `'uint8_t'`, and `-DOS_ATOMIC_USES_CXX=0` changes
**nothing** there. So at least three failure classes stack on this one
translation unit, each masking the next. **This is why a single "it builds /
it doesn't" number is close to useless for this component**, and why §7.2a's
repro is the instrument that actually moves.

Per §2.0 none of this is progress toward the goal, and per §4.1 the next step
is T1 once the tree is quiet and the shim question is settled by its owner.

### 7.2 `libsystem_darwin` — an xnu header winning over the libsystem_c one

**Error:** `os/assumes.h:130,134,157: use of undeclared identifier 'os_log_...'`

> **CORRECTION, 2026-09-27.** The first version of this section concluded that
> `<os/log_private.h>` *does not exist* on this component's include path. **That
> was wrong**, and the error text itself refutes it: a genuinely missing header
> produces `fatal error: 'os/log_private.h' file not found`, not *use of
> undeclared identifier*. The header is found. It is the **wrong one.**
> Corrected diagnosis below; the rejected candidates are unchanged.

**Root cause: a wrong-generation xnu header shadows the intended one.**

`Libraries/Libsystem/libsystem_c/os/assumes.h:69-70`:

```c
#if defined(OS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE)
#include <os/log_private.h>
```

The define is set for this component at
`Libraries/Libsystem/libsystem_darwin/Makefile:21` (and again at
`internal.h:63`), so the branch is taken. Lines 130/134/157 are
`os_crash(...)` calls, which expand to `__os_crash_fmt` (`assumes.h:72-83`,
inside the same `#if`) and need `os_log_pack_t`, `os_log_pack_s`,
`os_log_pack_fill`, `os_log_pack_size`, and `__os_log_encode`.

**The header that answers `#include <os/log_private.h>` is xnu's**, reached via
the Makefile's line 37:

    -I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/libkern

which concatenates to
`/Users/max/Projects/build/Users/max/Projects/ravynos/Kernel/xnu/EXPORT_HDRS/libkern`
— a real directory (it exists; created 2026-08-27), holding
`os/log_private.h` at **2,894 bytes**. Measured against the five identifiers
`assumes.h` needs:

| identifier | xnu's `os/log_private.h` |
|---|---|
| `os_log_pack_t` | **0** |
| `os_log_pack_s` | **0** |
| `os_log_pack_fill` | **0** |
| `os_log_pack_size` | **0** |
| `__os_log_encode` | **0** |

All five are absent. The header is found, opens, declares its guard, and
provides a *different interface* — so the compiler correctly reports the
symbols as undeclared. **It is a shadow, not a gap** (§5.7, §6.3).

**Reproduced** through the project's own `isysroot-cc` with
`libsystem_darwin`'s real flags: 20 errors, led by
`assumes.h:130: call to undeclared function 'os_log_pack_size'` and
`'__os_log_encode'`.

**The `-I` path: a second, independent defect, investigated before deciding.**
Concatenating `ROOT_BINARY_DIR` and `ROOT_SOURCE_DIR` yields
`/Users/max/Projects/build/Users/max/Projects/ravynos/...` — the build tree
containing a **full copy of the source path** underneath it. Before changing it
the question was: does a mirrored tree really exist there, and does anything
populate it? **Answer: yes it exists, and NO — nothing populates it. It is an
abandoned fork, and it is load-bearing by accident.**

**Three trees, all 1,251 files, all mutually different:**

| path | newest file | vs the others |
|---|---|---|
| `${ROOT_BINARY_DIR}/EXPORT_HDRS` (`/Users/max/Projects/build/EXPORT_HDRS`) | 2026-09-03 | differs from both below |
| `${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/…/EXPORT_HDRS` (**the concatenated one**) | 2026-08-31 | differs from both below |
| `Kernel/xnu/BUILD/obj/EXPORT_HDRS` (in-repo) | 2026-09-04 | differs from both below |

- The **"correct" form `${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS` does not
  exist at all** — and that is the form `libsystem_c`'s own subdir Makefiles
  use (`libBase/Makefile:99`, `libc_dyld/Makefile:35`, `vLegacy/Makefile:59`,
  and others). So those `-I` flags are **dangling and silently so**.
- The concatenated tree was created **2026-08-27**, last written **2026-08-31**,
  and nothing has written it since. No script in the repo creates it: a search
  for any `rsync`/`cp`/`mkdir` targeting that shape returns nothing.
- Its `os/log_private.h` is **byte-identical to `Kernel/xnu/libkern/os/log_private.h`**
  — it is a copy of the xnu *source* header, not a generated one, which is why
  it carries the kernel interface and none of the five `assumes.h` symbols.
- The repo's own `Kernel/xnu/EXPORT_HDRS/` has the same seven subdirectories
  but **0 files** — the directories exist and are empty.

**So: the concatenation is a latent bug that works by coincidence on this
machine.** It is not load-bearing in the sense of "a build step maintains it" —
it is load-bearing only because an abandoned 2026-08-27 copy happens to sit
there. Remove it and this component silently loses a whole header tree; leave
it and this component silently reads a **stale fork** that nothing refreshes,
which is precisely how a header-generation mismatch persists unnoticed.
Compare `libdispatch/Makefile`, which uses `-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern`
— the in-repo source, no concatenation.

**Not changed this round, deliberately.** The header-tree decision is Phase 0 /
Decision 1 (§8) and is not mine to make unilaterally; the mirror's three-way
divergence needs a deliberate choice about which tree is canonical, and that
choice is exactly the mach-generation policy question still open. **The
libtrace fix below is independent of it** — the component no longer asks for
the header at all.

**The `stddef.h` revert is a red herring, and the 381-byte `stdlib.h` is
unrelated.** The revert removed a separate `uint8_t` class (14 occurrences at
`sys/resource.h:203`); this component was already broken independently. And the
vendored copy is `Libraries/Libsystem/libsystem_darwin/h/stdlib.h` at
**15,020 bytes**, not 381 — the SDK's is 14,705. **The "381-byte vendored
`stdlib.h`" does not exist in this tree as described.** It is installed to
`$SDK/usr/local/include/os/stdlib.h` by the Makefile's `headers:` target, a
*different* path from the shadowing candidate. Flagged, not assumed.

**The fix, applied: drop `-DOS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE` from
`libsystem_darwin/Makefile`.** A configuration correction, not new code:
`assumes.h` already carries complete non-libtrace fallbacks (lines 253-257,
292-302) and the component now uses them. The removal is documented in a
comment above the assignment — including *why* `__has_include` would not have
been sufficient (the header **is** found; it is the wrong generation) and the
condition for re-enabling it (only together with a `libsystem_c`-generation
`os/log_private.h` on this component's path).

**Verified before building:** through the real `isysroot-cc` with the
component's real flags, **20 errors → 0** on a TU that includes
`<os/assumes.h>`; and `bmake -n` confirms the define reaches **no** compile
line, with the Makefile still parsing cleanly (lesson: no `#` inside a
backslash continuation — the comment sits above the assignment).

**Scoping, checked rather than assumed.** A fix that clears
`libsystem_darwin` while leaving a sibling on the same path would be half a
fix, so: **only two Makefiles in the tree ever set this define** —
`libsystem_darwin` (now removed) and `libsystem_c/tests/Makefile` lines 41 and
43, which are *test* targets (`os_variant`, `osvariantutil`), not shipped
components. **`libdispatch` never sets it** and never includes
`<os/assumes.h>`, so it was never on this path. The fix is therefore complete
for the component set, not partial.

**The remaining candidates, unchanged:**

- ⏸ **Separately: fix the concatenated `-I`** so this component reads headers
  from the intended tree. **Deliberately not done** — see the three-tree
  investigation above; the canonical-tree choice is Decision 1 (§8) and is not
  a unilateral call. The libtrace fix does not depend on it.
- ❌ **Hand-writing an `os/log_private.h` shim.** It would have to invent
  `os_log_pack_t`'s layout and `os_log_pack_fill`'s ABI — §5.5's defect class,
  inside a crash-reporting path, which is the worst place for a silent wrong
  answer.
- ❌ **Sourcing xnu's `os/log_private.h`.** It is *already* what is being
  sourced, which is the bug. It defines none of the five identifiers.
- ❌ **A `-include` force-include of a log header**, as was tried with
  `stddef.h`. A force-include that fixes a missing declaration usually means
  the include path is wrong — and here it demonstrably is.

**Verification that does not need the build tree.** Because the tree is
contended, the fix was also checked by compiling **each of the component's
eleven `.c` files** through the real `isysroot-cc` with the real Makefile flags
and counting only errors that name `os_log_`/`assumes.h:`/`cleanup.h:`:

> **0 in all eleven.**

That is the failure class being eliminated, and it is gone everywhere. (Those
invocations also report unrelated errors — a missing `bsm/libbsm.h`, and
`__sized_by` diagnostics — because an ad-hoc `-I` list is not the build's; they
are **not** evidence about the component and are not recorded as such. Only the
log-family count is claimed here, and it is claimed because it is the only
thing the fix targets.) **The component link remains T1b**, taken only on a
`ps`-verified quiet tree.

**The fix was TWO places, and the first alone did not work — worth recording,
because a partial fix here looks exactly like a working one.**

1. `Makefile`: the define removed. Repro 20 → 0; `bmake -n` confirmed it
   reached no compile line. **Necessary, not sufficient.**
2. **`internal.h:63` set it too**, in the source, for all nine of the
   component's `.c` files. The first real build still failed with **7 errors on
   the *same* lines** — `assumes.h:130,134,157,185` and
   `h/cleanup.h:100,124,145`, all `use of undeclared identifier 'os_log_pack_s'`.
   **The identical line numbers were the tell:** a genuinely new failure does
   not land on the same three lines. `internal.h` also had an unconditional
   `#include <os/log_private.h>`, removed with the define.

**The lesson, and it generalises: when a define can be set from more than one
place, fixing one place yields a build that fails *the same way*, which reads
as "the fix didn't work" rather than "the fix was incomplete."** Enumerate the
definers before fixing one. Here that census is four lines of `grep` and would
have saved a build.

**Definers census, so nobody repeats the search.** After the fix, the only
remaining definers of `OS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE` in the tree are:

| location | kind |
|---|---|
| `libsystem_c/tests/Makefile:41,43` | two **test** targets — not shipped components |
| `libsystem_c/tests/assumes.c:1` | a **test** file |
| `libsystem_c/gen/FreeBSD/arc4random.c:48` | in `libsystem_c`, which builds today, so its include path resolves these correctly |
| `libsystem_c/stdio/FreeBSD/vfprintf.c:38` | same |

**Scoping, answering the question directly:** `libdispatch` does **not** carry
this configuration and never did — it includes neither `os/assumes.h` nor
`h/cleanup.h`, and its Makefile never set the define. **So this change could
not have fixed it, and the fix is complete for the component set rather than
half-applied.** Worth stating because §7.3 claims a shared root cause: that
claim is about *include-path shape*, not about this define, and the two
components' Phase 5 failures are independent.

**Component link:** see row 18 and T1b — measured only on a `ps`-verified quiet
tree.

### 7.3 The two failures share a root cause — this is the finding

They look unrelated. They are the **same defect**, once per component:

| | `libdispatch` | `libsystem_darwin` |
|---|---|---|
| xnu header that wins | `os/atomic.h` (C++ branch) | `os/log_private.h` |
| expected by | `shims/atomic.h` (a C11 component) | `libsystem_c/os/assumes.h` |
| reached via | `-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern` | `-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/.../EXPORT_HDRS/libkern` |
| symptom | `std::__c11_atomic_store` does not exist | `os_log_pack_size` / `__os_log_encode` undeclared |
| real fault | two generations of one interface fight | wrong generation of one interface answers the include |

**Common root cause: an xnu kernel header is on a libsystem component's
include path and wins over the generation that component was written
against.** In `libdispatch` the collision is *within* one interface
(`os/atomic.h` vs `stdatomic.h` over the same names); in `libsystem_darwin`
it is *between* two generations of `os/log_private.h`. Same shape, different
surface.

**What this predicts, and it is actionable:** any libsystem component whose
`CFLAGS` put `Kernel/xnu` on the path is exposed to this, whether or not it has
failed yet. `libdispatch` and `libsystem_darwin` are simply the two that
reached a header early enough to show it. **The inventory of components with
`-I…Kernel/xnu` is therefore a to-do list, not a coincidence** — and it is
cheap to produce. That is a better use of effort than diagnosing components
one at a time as they fail.

This is the §5.7 pattern at full strength: **the sources are all present, and
the declarations collide.** It is now five instances across four components.

### 7.4 `libsystem_darwin`: the target class is eliminated, and the fix was too blunt

**Measured, real build, `ps` verified empty immediately before.** The failure
class §7.2 set out to kill is **gone**:

> **0** errors naming `os_log_` / `assumes.h:` / `cleanup.h:` / `invalid
> preprocessing` — 20 before, 0 after, on the component's own build. Also 0
> across all twelve of the component's `.c` files compiled through the real
> wrapper with the real flags.
>
> **But the component still does not build, and the reason is that the fix was
> too blunt.** `h/stdlib.h:170,206,242` gate three real APIs —
> `os_malloc`, `os_calloc`, `os_strdup`:

```c
#if defined(OS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE)
#define os_malloc(__size) ({ … os_assert_malloc(…); … })
#else
#define os_malloc(__size) __os_requires_experimental_libtrace   // _Pragma(GCC error)
#endif
```
>
> So libtrace is **not an optional formatting choice here — it is load-bearing
> for a public API**, and the component's own `stdlib.c` and `mach.c` call
> those functions. Remaining errors: **5 ×** *requires
> OS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE*, `mach.c:269,293,296` failing to
> return a value, and **5 ×** *too many arguments to a function-like macro*.
>
**The honest conclusion: this is a `log_private.h` problem wearing a
feature-flag costume.** The define was never the defect. The defect is that
`<os/log_private.h>` resolves to xnu's kernel header, which has none of the
five symbols `os_assert_malloc` needs.

**The obvious fix — remove the dangling `-I` — CANNOT WORK, and this was
measured before building.** `isysroot-cc:644` sets
`LIBKERN_INC="${ROOT_SOURCE_DIR:-$HERE/../..}/Kernel/xnu/libkern"` and adds it
**unconditionally** — deliberately, per the comment above it: *"A guard that
cannot be proven active is the same as no guard."* The wrapper therefore
supplies the same include on **every** C compile regardless of what any
Makefile asks. Traced with `-H` on a TU that is nothing but
`#include <os/log_private.h>`:

| | `os/log_private.h` resolves to |
|---|---|
| with `libsystem_darwin`'s dangling `-I` | `…/build/Users/max/Projects/ravynos/Kernel/xnu/EXPORT_HDRS/libkern/os/log_private.h` |
| **without** it (wrapper's `-I` only) | `/Users/max/Projects/ravynos/Kernel/xnu/libkern/os/log_private.h` |

`diff` of the two: **identical, byte for byte.** Removing the dangling `-I`
changes which path answers and nothing else — there are two routes to the wrong
generation and a Makefile can remove only one. **This is a real absence, not a
mis-resolution a path fix can cure.**

**And the absence is total.** Every `os/log_private.h` in **every** tree —
`Kernel/xnu/libkern`, `BUILD/obj/EXPORT_HDRS`, the abandoned mirror, the SDK —
has `os_log_pack_fill: 0`. The only file in the tree that **defines** the five
symbols is `Libraries/Libsystem/libsystem_trace/log.h`, which is not a
`log_private.h` and is not on this component's path. **So Decision 4 is a real
decision about inventing an interface, not about picking a tree.**

Options, none taken unilaterally:

| option | cost | verdict |
|---|---|---|
| Re-enable libtrace **and** fabricate the five symbols | invents a crash-format ABI | ❌ §5.5's defect class, in a crash path |
| Vendor `libsystem_trace`'s declarations under a new name | the same invention, laundered | ❌ |
| Make the `h/stdlib.h` wrappers fall back to plain `malloc`/`calloc`/`strdup` when libtrace is unavailable | behaviour-preserving de-abstraction of three inline wrappers; invents no ABI | ⚠️ only ABI-free option, but **DECIDED NOT WANTED** — see below |
| Drop the three APIs from this component | narrows a public API | ❌ silently |
| Leave it unbuilt | — | ✅ **DECIDED** — non-closure component; recorded as an accepted failure |

**DECIDED 2026-09-27: leave `libsystem_darwin` unbuilt. Do not take the
`h/stdlib.h` fallback.** Recorded with its conditions so the line is holdable
without re-arguing it.

The fallback is the only option above that invents no ABI, which is exactly
why it is the right one **if the component has to build** — and "if it has to
build" is the part that fails. Phase 3's composition is **3 `libsystem_trace`
+ 3 `libsystem_platform` + 2 `libdyld`**; `libsystem_darwin` is in **none** of
them. So building it advances the goal by **zero symbols** while spending a
real change to that component's **public inline wrappers**. It would buy a
green driver run, and a green run is worth having — but for the reason in
§2.0: because it makes the instrument trustworthy again, **not** because it
moves anything. **Paying an ABI-adjacent header change for instrument trust
is a trade this project has already refused three times, and it should not
become a fourth for a non-closure component on the eve of Phase 1 clearing.**

**Conditions under which the fallback becomes wanted — ALL THREE required:**
1. Phase 1 has linked (`libsystem_kernel.dylib` links);
2. the closure has been recomputed (Phase 2, the falsifiable 133 → ~7);
3. someone has confirmed `libsystem_darwin` is actually **in** the closure.

**Any one failing, it is still not wanted.** And when taken it is its own
deliberate change on a quiet tree — never a side effect of something else.

**Both removals remain restored** (the `Makefile` define and `internal.h:63`,
with `os/log_private.h` put back), because the define is load-bearing for
`os_malloc`/`os_calloc`/`os_strdup` and the error it was blamed for is not
going away. **The component does not build and is not expected to.** A driver
run that reports `libsystem_darwin` as UNEXPECTED is therefore **correct and
expected** — it must be recorded as a known, accepted failure, never
suppressed to reach a green.

### 7.4a The dangling-flag census: exactly two components, and one builds today

Enumerated across every `Makefile` under `Libraries/` for the `EXPORT_HDRS`
`-I` form:

| form | count | components |
|---|---|---|
| `-I${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/…` (correct) | **14** | `Libraries/Makefile`, `libBase`, `libFreeBSD`, `libNetBSD`, `libTRE`, `libc_dyld`, `libc_static`, `vCancelable`, `vDarwinExtsn`, `vDarwinExtsnCancelable`, … |
| `-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/…` (dangling) | **2** | **`liblaunch`** (osfmk, san), **`libsystem_darwin`** (libkern) |

**`libBase` (lines 99, 103) and `libFreeBSD` (478, 483) are clean** — they use
the correctly-slashed form. So the component `critical-path` was building is
**not** carrying a latent copy of this bug, which was worth establishing before
it failed rather than after.

**`liblaunch` does carry it, and it currently builds.** That is the shape to
watch: a flag that works by coincidence, in a component with no symptom. Worth
a look precisely *because* it is green.

**Blast radius of the wrapper's injection is BOUNDED, and it matters that this
is on the record.** "Unconditional `-I` on every C compile in the project"
sounds far worse than it is. `Kernel/xnu/libkern`'s **root** contains **zero
standard-named headers** (0 `*.h` at the top level — it holds `Makefile`,
`OSKextLib.cpp`, `OSKextVersion.c`, `kernel_mach_header.c`, `mkext.c`,
`ptrauth_utils.c`, `stack_protector.c` and subdirectories). So the injection
**cannot shadow `stdint.h`/`string.h`/`stdlib.h`**, and it is **not** the
standard-header-shadowing class. Its exposure is bounded to the `os/` and
other *subdirectory* headers — which is the kernel-**generation** class of
§6.0, not the standard-header class. Recorded bounded, not as an open worry.

**Which narrows the census, and in the peer's words better than mine: for
`libkern` the concatenated form is DOUBLY moot.** The wrapper already injects
the correctly-spelled `-I Kernel/xnu/libkern`, so `libsystem_darwin`'s dangling
`-I …/EXPORT_HDRS/libkern` is a *second* route to a file measured
byte-identical. Removing it cannot help **and its absence would not help
either.** In `libsystem_darwin` the dangling form is a **latent cosmetic
defect, not a live blocker.**

**`liblaunch` is the one that is a live risk, and for a different reason:**
its concatenation is `-I …/EXPORT_HDRS/osfmk` and `…/san`, and **the wrapper
injects nothing for either** (verified: `isysroot-cc` has no `osfmk` or `san`
injection; line 379 only *mentions* the path in a comment). So there the
dangling path is the **only** route, and the file it reaches is whatever
happens to sit at that concatenated location. That is the stronger form of
"works by coincidence" — **no second correct route to fall back on** — and it
is worth a look precisely *because* `liblaunch` currently builds.

**Census footnote, so a later reader does not trip over a third hit:** an
`EXPORT_HDRS`-form grep also catches `Libraries/ICU/Makefile:10`, which
concatenates the same way but for
`${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Libraries/llvm_target/compiler-rt/lib/ravynos/libclang_rt.osx.a`
— a compiler-rt **runtime library** path, not a header tree. Different shape.
**"Exactly two" is correct for headers.**

---


### 7.4b `libdyld`'s link: `-upward-lc++` was the whole frontier (SOLVED)

**Root cause, found by bisection rather than by hypothesis — and the method is
the point.** The smallest synthetic dylib link that reproduces the message,
then remove **one flag at a time** until the message changes. No hypothesis
required. Reproduced independently here, in `/tmp`, writing nothing into the
build tree, with core flags `-lc++ -lc++abi -nodefaultlibs
-not_for_dyld_shared_cache -undefined dynamic_lookup`:

| | result |
|---|---|
| `+ -Wl,-upward-lc++` | **`ld: library 'c++' not found`** ← the exact frontier |
| `-upward-lc++` removed | `ld: dynamic executables or dylibs must link with libSystem.dylib` |

**Both messages reproduced exactly, single-flag delta, here and in the
peer's bisection.**

**Why `-upward-lc++` can never be satisfied in this SDK.** `-upward-X` means
"re-export libX from the dylib above me", so it requires libX to exist **as a
dylib**. Measured across the SDK: `libsystem_malloc`, `pthread`, `platform`,
`kernel`, `c`, `libxpc`, `libdispatch`, `libcompiler_rt`, `libsystem_blocks`
are all real dylibs in `usr/lib/system/`; **`libc++` is `usr/lib/libc++.a`
only — no `.dylib`, no `.tbd`.** So every *other* `-upward-` target in that
link is satisfiable and this one never can be. It is also the **only
incorrect** choice on its own terms: a bootstrap linker must not depend on
the C++ runtime dylib sitting above it in the cache, which is why dyld takes
libc++ statically via `-lc++ -lc++abi` (26 of 27 sources are C++).

Removed in `Libraries/dyld/Makefile`, with the reasoning **above** the
assignment and the bisection table in the comment. Verified: `bmake -V LDFLAGS`
→ **35 tokens, `-upward-lc++` absent, `-lc++` and `-lc++abi` present, tail
intact, no continuation truncation** (lesson 32's instrument, run for the
reason lesson 32 gives).

**The next blocker is `-nodefaultlibs`, and the peer's framing of it as a
circularity needs one correction that I measured.** `isysroot-cc` correctly
adds `-nodefaultlibs`, so ld64 requires an explicit libSystem, and the real
`libSystem` is assembled *from* these libraries. That much is right. But the
"must link with libSystem.dylib" error is **not** evidence that it cannot be
satisfied — it is ld64 asking for a library that was simply **not named on the
command line**. Both of these succeed:

```
-nodefaultlibs -lSystem                                             -> links (4,168 B)
-nodefaultlibs -lSystem -lc++ -lc++abi -undefined dynamic_lookup     -> links (4,120 B)
```

The SDK has real `usr/lib/libSystem.dylib` and `usr/lib/libSystem.B.dylib`.
So the open question is narrower and cheaper than "build-order circularity":
**whether an explicit `-lSystem` is correct for dyld, given that its whole
purpose is to be the thing that *provides* libSystem's contents.** That is a
real design question, not a mechanical one — and it is exactly why the peer
was right to hand over a frontier it understands rather than a link it forced.
**Not resolved here; recorded as the next decision, not attempted.**


## 8. Open questions requiring a human decision

1. **Fund the mach reconciliation, or not?** The number is **14 headers, not
   46.** The per-header policy doc and the reference count are enough to decide
   without it. **Recommendation remains: do not fund it yet.** The probe is
   unmade, and the policy document plus the reference count are enough to
   decide without it. **Decision 1.**

2. **The stub decision, on the load-weight / silent-seven asymmetry.** The
   stub decision is a genuine fork: *loudly* failing for 8 load-bearing
   components is arguably a **safer** state than 7 silent ones. Weighed
   against §5.5, the asymmetry is what makes this a decision rather than a
   default. **Decision 2.**

3. **`libsystem_trace`'s legal exposure.** The Apple policy is *staged where we
   have our own* is unbuildable. This is a live legal exposure, and building
   ours is a separate decision from staging the Apple `1861.160.4`. Not
   recommended without a decision. **Decision 3.**

4. **Which mach generation is authoritative, and how its gaps get filled
   without creating a chimera?** (Open since §5.1; the 15-constant census made
   the *bridge* tractable but did not answer the *policy*.) **Decision 1.**


5. **`libdyld`'s libSystem, and why "just add `-lSystem`" must not be done.**
   (New, §7.4b.) The `-upward-lc++` blocker is **solved**. The next one is that
   `isysroot-cc` adds `-nodefaultlibs`, so ld64 demands an explicit libSystem.

   **Naming `-lSystem` IS possible and the link then succeeds — against a
  placeholder.** Measured:

  | path | size | exported symbols |
  |---|---|---|
  | `usr/lib/libSystem.dylib` | → symlink to `libSystem.B.dylib` | — |
  | **`usr/lib/libSystem.B.dylib`** | **4,120 B** | **0** |
  | `usr/lib/system/libsystem_c.dylib` | 1,255,496 B | 1,342 |
  | `usr/lib/system/libdispatch.dylib` | 912,240 B | 329 |
  | `usr/lib/system/libsystem_malloc.dylib` | 263,736 B | 98 |

  **26 real dylibs** sit in `usr/lib/system/` to compose it. So a `libdyld.dylib`
  linked against `-lSystem` would install cleanly, appear in the SDK, and
  **resolve nothing at runtime.**

  **This is §5.5, not a variation of it: a stub that links is worse than a
  stub that fails.** It is the same shape as "undeclared identifier" meaning
*the header resolved*, and "0 hits" meaning *the probe could not see* — a
clean result where the absence went unfelt rather than away. **The two output
sizes I originally quoted (4,168 B and 4,120 B) proved only that ld64 stopped
complaining**, against a library that supplies nothing.

  **The actual question, which is neither "impossible" nor "one flag":** the
  correct libSystem **does not exist yet**, and the 26 real dylibs that would
  compose it do. So the 26 must become a libSystem first, and `libdyld` must
  bind that — which is a **build-order** question, reached from evidence
  rather than from the wrapper's documentation. Recorded as that, and
  deliberately **not** as either extreme.

  **Do not act on the 4,168 B number.** Anyone who reads it as "adding
  `-lSystem` works" will produce a `libdyld` bound to a placeholder — which is
  exactly how the `libobjc.A` stub got staged, the worked example in §5.5.
  **Decision 5.**

  **Update 2026-09-27: the second half of this decision is now CLOSED, and it
  closed in the direction that removes this one.** The allocator fork (§7.4e)
  was decided as **`glue.c` self-contained** — define `_Znwm`, `_ZdlPv` and
  `__libcpp_verbose_abort` locally, **no libc++ dependency**. So the reading
  that would have needed "a real libc++ dylib first" lost, and with it the
  idea that the allocator question and the libSystem composition question are
  the same question. **They are not.** The remaining half of Decision 5 is
  therefore *only* the libSystem composition itself, which stands unchanged.
  One of the two candidate trees just stopped being needed.

### 7.4c The dyld frontier moved past BOTH link blockers — new frontier is duplicate symbols

**Confirmed on a real clean-slate build** — 27 of 27, `ps` verified empty
immediately before, distinct log, input mtimes recorded (`isysroot-cc` 10:14:19,
`dyld/Makefile` 10:49:17), and all three link flags verified via
`bmake -V LDFLAGS` before building, since that instrument has already caught one
error today.

| frontier | status |
|---|---|
| `ld: library 'c++' not found` | **GONE** — the `-Wl,-upward-lc++` defect, fixed |
| `ld: dynamic executables or dylibs must link with libSystem.dylib` | **GONE — uncovered, not yet solved** (Decision 5) |
| **`ld: 4 duplicate symbols`** | **the current frontier** |

The four are `std::terminate()` / `std::get_terminate()` and
`std::unexpected()` / `std::get_unexpected()`, all four
`libdyld.a[3](glue.o)` vs `libc++.a[11](exception.o)`.

**This one is CORRECT behaviour being reported correctly.** Verified:
`Libraries/dyld/src/glue.c:145-158` **deliberately** defines all four, with
source comments *"std::terminate called by C++ unwinding code"* and
*"std::unexpected called by C++ unwinding code"*, each calling `dyld::halt()`.
That is a bootstrap linker refusing libc++'s exception runtime — exactly
right, because libc++'s handlers would abort through a runtime that does not
exist yet when dyld runs. **The authors knew and said so in the source.** The
link is correctly reporting that libc++'s exception machinery must not be
pulled in.

**The useful hint is in ld's own output:** the warnings name **four** pulled
members — `exception.o`, `new.o`, `typeinfo.o`, `verbose_abort.o` — so
`exception.o` is being *dragged in* by some other undefined libc++ symbol
rather than genuinely needed twice. Most dyld TUs already build
`-fno-exceptions`, which hints dyld may not want EH at all. **Not fixed** — the
options are different in kind (link libc++ selectively, or supply the
personality/unwind symbols so `exception.o` is never demanded), and the right
move is to have the room rather than guess, given the day's record.

### 7.4d CONVERGENCE: two independent workstreams, same frontier class

**The first time the frontier has looked the same in two independent
workstreams.**

| component | duplicates | cause |
|---|---|---|
| `libsystem_kernel` | **5** | libsyscall's hand-written shims vs mig-generated ones |
| `libdyld` | **4** | `glue.c`'s deliberate handlers vs `libc++.a`'s `exception.o` |

Same class — a symbol defined twice because two things both provide it —
different causes. **Two of the three load-bearing components in the project
are now failing at link on duplicate symbols.**

**Why this is a pattern and not a coincidence, which is the part worth
keeping:** the compiler never sees these, so a component reveals them only
when it finally reaches `ld64` — and **two hand-written providers of the same
name is the most common way to get there.** A component reaching the linker
for the first time should be *expected* to report this class, not something
novel. Both current cases are a deliberate hand-written shim colliding with a
generated or vendored one, which is the same shape as §5.5's `libobjc` and as
the `suid_cred_*` census in §5.1: **something was written twice, by two
people or two tools, and nothing complained until both were in one link.**


### 7.4e The `-lc++` removal is right for the wrong stated reason — and there is a latent load-time failure behind it


**The fix worked and the reasoning needs one correction, because the corrected
version is the one that predicts the next problem.**

Removing `-lc++ -lc++abi` made the link succeed, and the stated reason was
"libdyld.a has 593 undefined symbols and libc++ supplies **ZERO** of them".

**Measured independently: the intersection is 4, not 0.**

| symbol | in `libdyld.a` undefined | in `libc++.a` | defined in `glue.o`? |
|---|---|---|---|
| `_Znwm` (operator new) | yes | yes | **no — `U`, undefined** |
| `_ZdlPv` (operator delete) | yes | yes | **no — `U`, undefined** |
| `__ZNSt3__122__libcpp_verbose_abortEPKcz` | yes | yes | no |
| `_ZSt9terminatev` | yes | yes | **yes — `T`, defined** |

So "libc++ supplies none of them" is true **of the 589 that matter** and false
of these four, and **all four are load-bearing for the frontier**: the first
three are what made `-lc++` pull `exception.o`/`new.o`/`verbose_abort.o` in,
and the fourth is the `terminate` collision itself.

**The corrected reading, which is stronger:** dyld uses libc++ **headers** and
supplies its own runtime. `glue.c:367-380` *declares* `_Znwm`/`_ZdlPv` as
`extern` precisely **to provide them** — with source comments explaining that
the aligned variants must exist because `__libcpp_allocate` may call them — and
defines only the aligned forms. So the intent is unambiguous and the removal
of `-lc++` is **correct**.

**But the extern declarations are declarations, not definitions.** With
`-lc++` gone, nothing supplies them, and the installed `libdyld.dylib` carries
all three as `undefined, dynamically looked up` with **no provider in its
load graph** (row 8d). The link succeeded; the *load* is what is at risk.

**DECIDED 2026-09-27: `glue.c` is SELF-CONTAINED. Define `_Znwm`, `_ZdlPv`
and `__ZNSt3__122__libcpp_verbose_abortEPKcz` locally, wrapping dyld's own
allocation, in the same style the file already uses for
`terminate`/`unexpected`. Do NOT re-introduce a libc++ dependency.**

The reasoning: the file's existing design is *"a bootstrap linker supplies
its own runtime"*, and adding a libc++ dependency for three symbols would
contradict the decision **the same file made forty lines above**. The
`__libcpp_allocate` comment is an **assumption, not a constraint** — it
described the author's expectation that libc++ owns the unaligned forms, and
that expectation became unsatisfiable when `-lc++` was correctly removed. The
right response to an unsatisfiable assumption is to satisfy the need locally
**and record why**, not to preserve the assumption and leave the library
unloadable.

**The two-reading table above is KEPT deliberately** — as the record of what
the evidence supported *before* the decision. The decision is made; the
readings it was chosen between are preserved, because the next person needs
to know the alternative existed and why it lost. Only the framing changed.

**⚠️ CONSTRAINT, NOT DELEGATED — this one is explicitly NOT decided.** If
wrapping the obvious allocator turns out to be **wrong for a bootstrap
context** — early in `main`, before allocation is safe, or in a phase where
dyld must not take a lock — the implementer must **stop and escalate** rather
than guess. That question is open, is not answered by this decision, and is
not delegated to whoever picks up the file.

---

**IMPLEMENTED 2026-09-27 (aacfcb5a62, 7afb199ccc). The constraint above was
CHECKED, not assumed, and it did not bind — so no escalation was warranted.**

`glue.c:367-444` defines all three: `_Znwm` over `malloc` (failing through the
already-defined `_ZSt17__throw_bad_allocv()`, since dyld is `-fno-exceptions`
and must not throw), `_ZdlPv` over `free`, and
`_ZNSt3__122__libcpp_verbose_abortEPKcz` → `dyld::halt(msg)`. No libc++
dependency, no invented allocator, the `-lc++` removal untouched.

**Why `malloc` is safe here, against the three things the constraint named.**
*Too early:* `malloc`/`free` were **already** undefined in this dylib and
already bound to `libsystem_malloc` by a hard, non-weak
`LC_LOAD_UPWARD_DYLIB` — so this adds **no new edge to the load graph**, and
dyld's own code already allocates (the "malloc too early" worry is real and is
written down in `dyld2.cpp:6319` directly above a `new char[]`).
*Locking:* `malloc` takes no dyld lock, and the failure path is `dyld::halt()`,
which prints through `_simple_vdprintf` and does not allocate — so there is no
allocate-inside-allocate recursion. *Exceptions:* there are none to throw.

**Current state: residual 2, and `libdyld.dylib` still will not load.** The
chain — 45 → 42 (vs the placeholder) → 6 (vs the real `libsystem_kernel`) → 4
(`-fno-exceptions`) → **2** (resolver fixed) — is in row 8d. What remains is
`_ccsha256_di` and `_ccsha384_di`, and **neither is a dyld symbol**: it is a
`libcorecrypto` export-surface gap (it exports 3 `ccsha1` forms, zero
ccsha256/384). **Both facts belong in every report: it builds, links, installs
— and it will not load.**

**A second lever, found by the same discipline: remove the DEMAND.**
`CFLAGS.DyldSharedCache.o = -fno-exceptions` closed `__Unwind_Resume` **and**
`__gxx_personality_v0`, 2 of 6, adding no load edge. The obvious alternative,
`-Wl,-upward-lunwind`, closes **1** of 6 and adds an edge for a library
carrying 5 unprovided symbols of its own. `DyldSharedCache.cpp` has no
`try`/`catch`/`throw` at all, so the flag removes a demand and disables
nothing. This is the doctrine the section above already argued for — *remove
the demand, not the handlers* — applied to the last TU that had one.

**Three traps, all of which produce a green build and a wrong answer.** Rows
8d, 8e, 8f carry the detail; the one that generalises furthest is **row 8f**:
a path missing from **your own search list** is indistinguishable from a file
missing from the tree, and I shipped that as a headline ("libobjc is absent",
22 symbols, the largest Phase-6 blocker) after warning about its exact mirror
one exchange earlier. The file was there the whole time.

### 7.5 The closure: 133 → 5, measured against pinned bytes

**`libsystem_kernel` links and installs.** 603 objects, 0 compile errors,
**617,080 B** replacing the 8,064 B placeholder, **1,470** defined exports,
12 undefined, **12 unprovided** against an 18-dylib closure.

**Pinning is not ceremony, and that is the methodological point.** Two runs of
the same script minutes apart gave **12 then 5**, because `libdyld` was
reinstalled between them. **A closure number is only meaningful against named
bytes.** The md5s are now part of the method:

| artifact | size | md5 |
|---|---|---|
| `libsystem_kernel.dylib` | 617,080 B | `71051fb8ddb7662cbf1d610e602d04cb` |
| `libsystem_c.dylib` | 1,255,496 B | `3babd71f22bc441ee5ff6c275081703a` |
| `libdyld.dylib` | 993,360 B | `8277f4af79604ea488aa2966aec785de` |

All three verified here. Provenance control: all 35 SDK dylibs copied and
hashed, **35/35 byte-identical** to an SDK dylib.

> | | value |
> |---|---|
> | `libsystem_kernel` undefined | **12** |
> | — 7 mach/VM | `_mach_msg2`, `_mach_msg2_trap`, `_mach_msg_priority_{encode,is_pthread_priority,overide_qos,qos,relpri}_inline` |
> | — 5 version-compat | `_system_version_compat_mode`, `_system_version_compat_open_shim`, `_system_version_compat_check_path_suffix`, `__system_version_compat_open_shim`, `__system_version_compat_check_path_suffix` |
> | `libsystem_kernel` unprovided | **12** — the same 12 |
>
> All 12 unprovided are **exactly its own 12 undefined**, which is the tell that
> the provider set was contaminated (below).
>
> **`libsystem_c`: 272 undefined, 267 satisfied, 5 unprovided**, of which
> **143** of the 272 come from `libsystem_kernel` alone.

**The 5, and they are two genuinely different problems — not conflated:**

| symbol | owner | status |
|---|---|---|
| `_open$NOCANCEL`, `_openat$NOCANCEL` | **a `SRCS` gap, not a flag** | `libsystem_kernel` exports `_open`/`_openat` but **no `$NOCANCEL` variant**, while exporting **22 other `$NOCANCEL` symbols** (`_accept`, `_close`, `_fcntl`, `_connect`, `_fsync`, `_msgrcv`, `_msgsnd`, …). The cancelable/ mechanism is in `SRCS` with eight `*-cancel.c` files; these two entry points are simply not in it. **NOT DIAGNOSED** beyond that, and deliberately so — adding them is a `SRCS` question |
| `___os_log_encode`, `_os_log_pack_fill`, `_os_log_pack_size` | **`libsystem_trace`'s** | `libsystem_kernel` exports **0** `os_log` symbols. Notes §20 already established that component cannot be built without inventing two struct layouts and one kernel-private type, so this is **§20 arriving downstream** — consistent with it, not a new finding |

**All 5 verified here as defined in ZERO of the 35 SDK dylibs.** Not "not in
the closure" — **not in the SDK at all.**

**The attribution: predicted 126, actual 143. Direction held, number off by 17.**

**⚠️ Two numbers in this document are STRUCK and must never be quoted: `0`
and `12`.** `0` was a contaminated subtraction, and `12` was measured before
`libdyld` was reinstalled — **both were real measurements, taken correctly, of
a tree that then changed underneath them.** That is the honest shape of this
section: not one careless number, but three successive correct-looking numbers
of which only the last is current.

**The flag bug, which produced the `0`.** `nm -g` prints ALL external symbols,
**including the undefined ones**, so P contained every library's own undefined
set and each symbol in A appeared "provided" by whichever library merely
*referenced* it. **`A − P` is near-empty BY CONSTRUCTION**, whatever the tree
contains — a self-fulfilling subtraction. Isolated proof it is the flag and not
a parsing quirk:

```
_mach_msg2_internal   (defined)    nm -gjU: 1    nm -gj: 1
_mach_msg2            (UNdefined)  nm -gjU: 0    nm -gj: 1   <-- the bug
```

`nm -m` agrees: `(undefined) external _mach_msg2 (dynamically looked up)`.
**The fix is the flag `-U`, not a `grep` added afterwards.**

**Why the 143 was NOT contaminated, and the distinction is the lesson.** The
comparison is `libsystem_c`'s *undefined* set against `libsystem_kernel`'s
*defined* exports. `libsystem_kernel` is **not a member of its own provider set**
in that comparison, so the contaminated flag — which added the kernel's own
undefined names to its export list — **cannot reach the result.** Verified here:
`libsystem_kernel`'s 12 undefined names have **0 overlap** with `libsystem_c`'s
272. **A bug in one subtraction says nothing about a second subtraction that
does not share its contaminated input.** An intermediate claim that the 143
"would move to 141" was retracted for exactly this reason, and the retraction is
recorded because the prediction was the *interesting* outcome.

**⚠️ `rc=0` is the DEFAULT, not evidence — and this is how the `0` reached a
commit at all.** `BSD/share/mk/bsd.sys.mk:541` appends `-lSystem
-Wl,-undefined,dynamic_lookup` to **every** ravynOS dylib link, so **no ravynOS
dylib link can fail on an unresolved symbol.** A green link is not evidence
that symbols resolve; it is evidence that ld64 stopped complaining. **Every
"it builds" claim here resting on an exit code is weaker than it looks,
including several of mine. For any dylib: `nm -u` the INSTALLED artifact, cross
it against the `otool -L` closure, `-U` on the provider side, and pin the
artifacts. An exit code is not a gate.**

**Caveats that belong in the table, not a footnote:**

1. **A residual of 5 does NOT close the basic-IO finding.** `libsystem_c`
   defines neither `_write` nor `_open` in any archive; those names are not among
   the 272 it leaves undefined. **The basic-IO core gap is untouched.**
2. ~~**`libobjc.dylib` is a load-time dependency with no provider.**~~
   **STRUCK 2026-09-27 — it was a resolver defect, not a fact about the tree.**
   `libobjc` **is** in the generated SDK: `usr/lib/libobjc.A.dylib`,
   **1,608,088 B, 2,147 exports**, with `usr/lib/libobjc.dylib` a symlink to
   it. It declares install name `/usr/lib/system/libobjc.dylib` but is
   **installed at `usr/lib/`**, so a resolver that maps an install name only to
   `$SDK/usr/lib/system/…` calls it missing. **Both this caveat and the
   identical claim in the notes were the resolver's, and neither said so.**
   Found by `kernel-link`, verified independently before accepting. See row 8f:
   an install name may live in `usr/lib/system` **or** `usr/lib`.

**The method, which is why these numbers are trustworthy where 126 was not:**
A = `nm -u` on the target, symbol lines only, sorted, minus `dyld_stub_binder`.
P = **`nm -gjU`** over every dylib in the transitive `otool -L` closure, union,
sorted. unprovided = A − P. **Install names must resolve inside the ravynOS SDK
only** — macOS has a *real* `libsystem_kernel.dylib`, so a literal-path resolver
silently mixes the host in and reports 0 unprovided **off a host library**. An
attempt here found a 2-library "closure"; the fixed version asserts every closure
path is inside the SDK and finds **18**. **And the artifacts are pinned by
md5**, because a closure is a function of *every* library in it, and one of them
being reinstalled changes the answer.

### 7.6 ⚠️ THE BOOT HAS NEVER EXERCISED THIS SESSION — and `nm` cannot tell you

**This is the most important section in the document, and everything above it
is a statement about symbol tables rather than about a booting system.**

**The finding.** `dyld_info -exports` on the staged `libsystem_c.dylib` reports
*"symbol count from symbol table and dynamic symbol table differ"* and lists
**0 exports**. The symbol is present as a `D` symbol in the symbol table; its
`LC_DYLD_EXPORTS_TRIE` has **datasize 0**. Across the **47 staged dylibs**:
**36 have an empty export trie and 6 have no trie load command at all. Not one
has a usable trie.** The 6 without any trie command are `libsystem_pthread`,
`libobjc`, `libxpc`, `libsystem_kernel`, `libsystem_platform`, `libobjc.A`.

**Our own source-built libraries are the same**, verified here:

| library | `LC_DYLD_EXPORTS_TRIE` | `LC_DYLD_INFO_ONLY` |
|---|---|---|
| `libsystem_c.dylib` | **0** | 1 |
| `libsystem_kernel.dylib` | **0** | 1 |
| `libdyld.dylib` | **0** | 1 |

**Why that is fatal, and it is not a subtlety.** **dyld resolves reexports from
the export METADATA, not the symbol table.** A reexport consults its target's
export set; where that is unreadable, **the symbol is invisible at runtime** even
though `nm` lists it as defined. So:

> **`nm` measures the symbol table. dyld measures the export set.
> "267 of 272 satisfied" is a true statement about symbol tables and is
> NOT evidence that the closure resolves.**

**⚠️ CORRECTION, added after a boot refuted the sharper version of this.** This
section originally said the export **trie** specifically, and inferred that
*no trie → cannot resolve*. **That is wrong.** Our `libsystem_c.dylib` has
`LC_DYLD_INFO_ONLY` and **zero** trie commands, and it **resolved all 1,342
symbols in its table** in a real boot (1,320 direct + 22 re-exports) — dyld in
this image honours the old format. The accurate claim
is the one about the **export set**, which is format-independent: the defect is
an **unreadable export set**, and the only instrument that measures it is
`dyld_info -exports`, counting direct **plus** re-exports. §7.6a below, and the
gate in §6.1a is corrected accordingly.

**This is the most expensive instance of §6.0a in the project, and the sting is
that the instrument was the one built specifically to answer the question.** A
`nm`-based closure census **over-reports resolution**, and this project has been
quoting it as progress toward a booting system for the better part of a day.
**Every gate we have passes a library dyld cannot resolve a single symbol from:**
`nm -gjU` counts symbols; `otool -L` only reads load commands; the stub check
looks at size and a few names; **and the driver runs `ld` with
`-undefined dynamic_lookup`, so it cannot fail.**

**⚠️ And the same gate across the whole SDK, which corrects an undercount of
mine.** `$SDK/usr/lib/system` holds **26 dylibs: 1 with an export trie, 25
without** (§7.10). **36 Makefiles** under `Libraries/` carry an `LDFLAGS`
assignment and exactly **one** has the flag. So this is not a fact about the
Apple extracts — **25 of the 26 libraries we build are in the old format**, and
until that changes no closure census over them means anything.

**⚠️ The staging gap, which is the single most important sentence in this
document.** The image stages **45 Apple extracts dated Sep 26**, and this
session's work has **never been booted, not once**:

| artifact | staged (Apple) | ours (source-built) |
|---|---|---|
| `libdyld.dylib` | 385,783 B | **993,360 B** |
| `libsystem_c.dylib` | 691,936 B | **1,255,496 B** |
| `assets/bin/echo` | **Apple universal binary** (x86_64 + arm64e) | not built from source |
| staged `libsystem_kernel`, `libsystem_platform`, `libsystem_pthread`, `libobjc`, `libxpc` | Apple, **no trie command** | ours, **empty trie** |

**So several of us have been reading successful builds as progress toward a
boot, and the boot is running none of it.** The builds are real and the
libraries are real; they are simply **not the ones on the disk image**. Nothing
in this session has reached `main()`.

**What this changes about the plan, and it is not small:**

1. **Phase 6 is not "converge the image" any more — it is "make the libraries
   loadable", and that is a new and unstarted piece of work.** Producing a dylib
   whose export trie is empty is not a 90%-done library. The linker flags that
   would emit `LC_DYLD_EXPORTS_TRIE` are **not** being emitted, and why is
   **undiagnosed**.
2. **Every "N of M resolved" number in this document must be read as
   "by symbol table"** until a trie-based census says otherwise.
3. **The boot image cannot be validated by building.** It has to be validated by
   booting, and the current image boots Apple libraries.

**Not diagnosed here, and deliberately:** whether the empty trie comes from
`LC_DYLD_INFO_ONLY` being emitted without `trie`-emitting flags, from
`strip`/`lds` post-processing, or from the SDK's own toolchain defaults. That is
a real investigation and it is the **next** thing, ahead of anything else on
this page, because until it is answered **no library this session produces can be
booted** and no other number here means what it appears to mean.

---

### 7.7 The empty export trie was ONE FLAG — and the fix does not stage the library

**Diagnosed and fixed, one flag:** `-Wl,-fixup_chains` in
`Libraries/dyld/Makefile`. Verified here on the artifact **in the generated
SDK**, using the §6.1a gate — `otool -l` for the trie, **not** `nm`:

| | `LC_DYLD_INFO_ONLY` | `LC_DYLD_EXPORTS_TRIE` | `CHAINED_FIXUPS` | size | `nm` exports |
|---|---|---|---|---|---|
| before | 1 | **0** | 0 | 994,056 B | 205 |
| **after** | **0** | **1** (datasize **5,464**) | **1** | 987,968 B | 205 |

**Same 205 exports. Only the format changed.** ⚠️ **This was recorded here as
"only one of the two formats is one dyld can read" — that is now known to be
WRONG** (§7.8): dyld in this image honours `LC_DYLD_INFO_ONLY`, and our
`libsystem_c` resolved all 1,342 of its symbols with **no trie at all**. So
`-Wl,-fixup_chains` is **available hardening that removes a format risk, not the
fix for a demonstrated defect** — nothing in this session shows the old format
failing on our libraries. The flag is correct and worth keeping; the reasoning
that motivated it was not sound.

**Why every gate missed it, and this is the point of §6.0a in one line:** the
library "linked, installed, and exported 205 symbols" and **every instrument this
project owns agreed**. `nm` counts symbols and does not care which structure
they are in; `otool -L` reads load commands and not this one; the stub check
looks at size and a few names; the driver **cannot fail** (§7.5,
`bsd.sys.mk:541`). **The instruments were scoped differently from the question,
not wrong about a value.**

**⚠️ The same defect is present in our OTHER two libraries, unfixed.** Verified
here:

| library | `LC_DYLD_INFO_ONLY` | `LC_DYLD_EXPORTS_TRIE` | `CHAINED` | flag present? |
|---|---|---|---|---|
| `libdyld.dylib` | 0 | **1** | 1 | ✅ fixed |
| `libsystem_c.dylib` | **1** | **0** | **0** | ❌ |
| `libsystem_kernel.dylib` | **1** | **0** | **0** | ❌ |

`grep -c fixup_chains` is 3 in `Libraries/dyld/Makefile` and **0** in both
others. **So one of three libraries we build is currently in a format dyld can
read, and two are not.** Until the flag is applied to `libsystem_c` and
`libsystem_kernel`, **no closure census over them means anything** — including
row 4, whose numbers are symbol-table statements and nothing more. `libsystem_kernel`
is kernel-link's while they hold it, so the sequencing is theirs to set, not
ours to work around.

**⚠️ What is NOT claimed, and it is the part that matters more than the fix.**
The library is now in the *format* dyld can read. **It has not been loaded.**
The staged `libdyld` in the boot image is still the **Apple extract at
385,783 B**, not this 987,968 B one, so §7.6 stands exactly as written: **the
boot has never once exercised this session's work.** Making a library loadable
and staging it are **two different pieces of work and only the first is done.**
"Now it has a trie" must not drift into "now it boots" — that drift is precisely
the failure mode §5.5 exists about, one level up.

### 7.8 A boot PROVED the export-metadata diagnosis causal — and refuted my own inference

**The fault signature moved when exactly one variable changed.** That makes it
causal, not correlational:

| | fault |
|---|---|
| before | `Symbol not found: ___mb_cur_max` (dyld namespace 6 subcode 0x4, initproc failed to start) |
| **after** | `Symbol not found: _strlen` (same namespace, same subcode) |

**One thing was staged:** our source-built `libsystem_c.dylib` (1,255,496 B,
1,342 `nm` exports) over the Apple extract (691,936 B, **0** dyld-readable),
plus our `libCrashReporterClient.dylib`, which the image lacked entirely and
which our `libsystem_c` imports two symbols from. **Nothing else changed.**

**⚠️ `___mb_cur_max` is not a missing symbol and not a C-library problem.** It
is **simply the first import reached in a closure where nothing can resolve**,
so the first import dyld attempts fails and *which* one it is depends only on
import order. **Do not go looking in `libsystem_c` for a missing `mb_cur_max` —
the symbol is defined there.** The signature is an artifact of ordering, and a
different first import reads as a different bug. **Row 10, corrected.**

**Why the fault is now `_strlen`, which is the genuinely useful part.** Our
`libsystem_c` does not *define* the 22 C string/memory functions — it
**re-exports** them. `dyld_info -exports` shows
`[re-export] _strlen (__platform_strlen from libsystem_platform)`, and the 22
symbols in the `nm` export set that the plain list omits are exactly
`_bcmp _bzero _index _memccpy _memchr _memcmp _memcpy _memmove _memset
_memset_pattern4/8/16 _strchr _strcmp _strcpy _strlcat _strlcpy _strlen
_strncmp _strncpy _strnlen _strstr` — **all routed through
`libsystem_platform`**. And **`libsystem_platform` in the image is one of the
dead ones**: 0 readable exports, 192 in its symbol table, *mis-aligned LINKEDIT
content 'data in code'*. **30 staged dylibs import `_strlen`.**

> **So the frontier is a re-export chain whose LEAF is dead — the same class of
> defect as the one just cleared: a staging gap, not a build gap.** We have a
> good `libsystem_platform` (88,456 B, 204 exports, **all 204** dyld-readable,
> provides `__platform_strlen`, **no** structural complaint). Staging it over
> the 145,572 B dead extract is the obvious next **single-variable** step, and
> **it has deliberately NOT been done** — that is the coordinator's call, not
> this workstream's.
>
> **⚠️ This reframes §7.6's staging gap usefully.** Our libraries are
> *loadable*; the image is full of libraries that are not, and **a chain is
> only as alive as its weakest leaf.** Our own `libsystem_c` has **no export gap
> at all** — 1,320 direct + 22 re-exports = **1,342**, exactly its symbol-table
> count. Its only interesting property is that **22 of the 1,342 are re-exports
> rather than definitions**, and those 22 are the ones that just broke the boot,
> because the library they route through was dead. **`nm` counted all 272 of
> libsystem_c's undefined symbols as satisfied while the chain behind them could
> not resolve.** That is §5.5's stub
> lesson at the level of a re-export chain.

**The LINKEDIT complaint is a STAGING problem, not ours — and that was
measured, not assumed.** 24 of the 48 staged dylibs raise a structural
complaint from `dyld_info` (*mis-aligned LINKEDIT content 'symbol table'*, or
*'data in code'*, or *symbol count … differ*). **Zero of ours do**, across
`libsystem_c`, `libsystem_kernel`, `libdyld`, `libdispatch`,
`libCrashReporterClient` and two `/tmp` relinks of `libdispatch`. **Our linker
does not produce this damage** — so it is a property of the Apple extracts and
of whatever produced them, and it is fixed by staging, not by relinking.

### 7.9 Provenance: which BYTES were tested, and the staging design rule

**The measurement stands, and its scope is narrower than "today's libraries".**
A boot proved a **2026-09-26 build of `libsystem_c`** resolves and moves the
frontier to `_strlen`. That is a real result about real bytes. But those bytes
are **not** today's artifacts, and the plan must not imply otherwise.

| library | SHA-256 (first 32) | SDK mtime | so |
|---|---|---|---|
| `libsystem_c` | `d6822c7bc692409f563b45e1eee5e565` | **2026-09-26 14:08** | yesterday |
| `libCrashReporterClient` | `eaa7b2846354abecf301498bc79ea91f` | **2026-09-26 14:58** | yesterday |
| `libsystem_platform` | `62d73aacd833aafe22312ec3619040b5` | **2026-09-26 16:46** | yesterday |
| `libdyld.dylib` | — | 2026-09-27 | today |
| `libsystem_kernel.dylib` | — | 2026-09-27 | today |

All three staged-as-ours libraries are **byte-identical to their SDK copies**,
so nothing has drifted and the image is stable. But `libsystem_c` is being
actively rebuilt, so:

> **What has been established is narrower and still valuable: a `libsystem_c`
> built from THIS TREE resolves.** ⚠️ **But the tested artifact is still
> INSTALLED, so the result is not superseded** — and that is the good version
> of this risk, arrived at by accident. The concurrent `libsystem_c` build
> produced **no new artifact**: the flag was added, the link failed first for
> §20's `system_trace` reason, and the change was **reverted** (§7.10), so the
> installed `libsystem_c` is still 1,255,496 B / 1,342 exports and still
> compares byte-equal to the staged copy (`d6822c7b…`) at run time.
> **Had it not been reverted, this round's result would already be attributable
> to a superseded artifact.** Anyone reading this later should not assume a
> newer `libsystem_c` was tested: **re-stage and re-hash whenever the hash
> moves**, and say which bytes a result belongs to.

**Why this is not pedantry, and it is the same lesson as §7.5's pinning:** a
measurement is a statement about *specific bytes*, and a hash is how you keep
that statement true when the bytes move. We have already had one number in this
document (12 vs 5) change purely because `libdyld` was reinstalled between two
runs of the same script. **The result is not invalidated; it is pinned to an
artifact that has since been superseded.**

**⚙️ THE STAGING DESIGN RULE, which is a correctness property of the
experiment and not a convenience:**

> **Staged assets are taken as BYTE COPIES — never as references or symlinks
> into the generated SDK.**

That is exactly what makes a boot measurement immune to a concurrent rebuild
moving the artifact underneath it. A symlink into the SDK would make the image
a view of a moving target: the run would be testing bytes that changed after
the command was issued, and no hash taken afterwards could reconstruct what was
actually loaded. **If the staging step is ever "simplified" to a symlink, this
whole class of result becomes unciteable**, and nothing in the build would fail
to say so.

**Corollary, and it generalises past this project: any measurement of a
**reproducible** thing needs a pinned copy of the thing, taken before the
measurement and hashed. Taking the copy afterwards is not a small difference —
it is the difference between a result and an anecdote.**

### 7.10 The hardening is ONE wrapper change, not 25 Makefile edits — and it is deliberately not taken

**The scope, measured.** **36 Makefiles** under `Libraries/` carry an `LDFLAGS`
assignment. **Exactly one** has `-Wl,-fixup_chains` (`Libraries/dyld/Makefile`).
**26 dylibs** sit in `$SDK/usr/lib/system`; **1** has an export trie, **25** do
not. **My "1 of 3" was an undercount and is corrected in Phase 6 and here.**

**So the fix belongs in `isysroot-cc`, not in 25 Makefiles.** The wrapper already
owns link hygiene on this toolchain — it already injects `-nodefaultlibs`,
`-not_for_dyld_shared_cache` and the `-lSystem` strip, in the branch that fires
for dylib links. **25 Makefile edits become one wrapper change, in the place
whose own comment already justifies owning link hygiene.** Patching Makefiles
would also be the wrong shape for a different reason: the 25 would drift.

**⚠️ NOT TAKEN, and the reason is the session's own lesson rather than
caution for its own sake.** This is a **global change to a file on every
component's path**, and this session produced **seven instances of a global
change verified against too narrow a scope** (§6.0a) — a `-D` that reached one
TU and not another, a shim family applied globally when two components needed
opposite settings, an index check that lost a race. **It wants a decision with
the peers in it, not a diff at the end of a long session.**
**The mitigation that makes it tractable: the per-component gate is now one
`otool -l` call, so every arm is cheap to measure if it is taken up.**

**⚠️ `libsystem_c`: attempted, reverted, and the flag's effect there is
UNMEASURED.** The flag was added and a full clean build run; the link fails
first for an unrelated documented reason —
`ld: library 'system_trace' not found` (§20's `libsystem_trace` blocker,
`lck_spin_t` being `MACH_KERNEL_PRIVATE`). So the installed `libsystem_c.dylib`
is still the **pre-change** artifact (1,255,496 B, `TRIE=0`, 1,342 exports),
and it was **reverted rather than committed as an unverified edit to a
component the author does not own.**

> **⚠️ State the cause correctly, because "we fixed the encoding" is the sentence a
reader will take away and it is the wrong causal story.** The fault moved from
`___mb_cur_max` to `_strlen` when the **export SET became populated** — our
trie-less `libsystem_c` was staged and it resolved. **The encoding did not
change anything observable.** Anyone reading §7.10 as "the trie fix unblocked
the boot" will draw the wrong conclusion about the next staging step.

**Two claims that must not be conflated, and the distinction is the point:**
> the flag is **PROVEN** on dyld's real link (trie datasize 0 → 5,464, same 205
> exports, §7.7), and extending it to `libsystem_c` is **very likely fine and is
> NOT MEASURED.** "Likely fine" and "measured" have been conflated twice in this
> document already (§7.5's struck numbers), so they are separated here.

**The sharpest form of the §6.1a lesson, from the person who paid for it:** every
instrument in this project asked a question a **compiler or a linker** could
answer. The trie question is the first that asked what **dyld** would do. And
the reason that matters is that the milestone verification was **sincere and
wrong at the same time** — *"links, installs, 203 exports, `otool -L` correct,
stub check passes"* was a **true sentence about a library that could not be
loaded**. **There is no version of "be careful" that catches that. Only asking
the consumer's question does.**

**And the argument for the gate, in its strongest and least inference-laden
form** — which is *not* the form it was first written in. The original claim
was that a trie-less library is **unloadable**. **That was asserted, not
measured**, and it has been **retracted** (31fdb760fd): it is Apple's modern
dyld's behaviour applied to a ravynOS dyld that **has never booted once**, and
the boot logs support it **neither way** (`serial_full.log`,
`serial_dynamic.log` — nothing). Worse for the claim, `stage_dynamic_libs.sh`
has put a **trie-less** `libsystem_c` into the image and **moved the fault**,
which is evidence *against* it.

> **The argument that does not need the inference at all, and is therefore the
> better one:** `nm` counts symbols and **does not care which structure they
> live in**, so it passed either way and the defect survived **every gate in
> this project**. Checking that the structure dyld is **documented** to read is
> present costs **one `otool -l`**, catches an **encoding regression**, and
> **holds regardless of what any particular dyld does with the result.**

**The generalisable lesson, and it is about how claims decay:** a *measurement*
("the encoding is X, the export count is unchanged") sat next to a *consequence*
("therefore it was unloadable") in a comment someone would later read as
evidence. The measurement was solid; the consequence was unearned and nobody
checked it for a day. **Keep them in separate sentences, and let only the
measured one be load-bearing.** This is §6.0a from the other end — a
well-formed check cannot protect a claim the check was never about.

### 7.11 ⚠️ The wrapper's own classifier has a blind spot — `objc4` is invisible to it

**The precondition nobody checked before proposing the wrapper fix: does the
wrapper even see the link as a dylib?** Its link-hygiene branch fires only on
`-dylib` / `-dynamiclib` appearing in the argv. **And one component never
passes it.**

Verified here in `Libraries/objc4/Makefile` — and the shape is *exactly* the
bug the dyld workstream hit this morning:

| line | rule | flags |
|---|---|---|
| **108** | assembles `libobjc-trampolines.dylib` | `-fpic -shared **`-Wl,-dylib`**` |
| **118** | **links `libobjc.A.dylib`** | `-shared -o ${.TARGET} ${OBJS} ${LDFLAGS}` — **no `-dylib`** |

`-dylib` is on the **assemble** rule at line 108 and **absent from the actual
link** at line 118. `LDFLAGS` (line 93 onward) does not contain it. So:

> **`objc4` gets NO link hygiene from the wrapper at all** — no
> `-nodefaultlibs`, no `-not_for_dyld_shared_cache`, no `-lSystem` strip, and
> **no `-fixup_chains`** if the flag goes in that branch. It is **invisible to
> the mechanism.**

**This is not a prediction, and it is not hypothetical — it is the same defect
the dyld workstream already fixed once today.** `Libraries/dyld/Makefile`
spelled its link `-shared` and put `-dylib` in `COMMONFLAGS`, which flows into
`CFLAGS` and **not** into the link line; the branch never fired and dyld reached
ld64 carrying `-lSystem`. The fix there was to add `-dylib` to `LDFLAGS`.
**`objc4` has the same shape and nobody has looked, because nothing reports
it:** the link either works or it does not, and for `objc4` it works.

**And `objc4` is not a marginal component.** It is the one the boot closure
depends on — `stage_dynamic_libs.sh` stages `libobjc.A.dylib` into the boot
image, and its absence was the hard stop that made the `___mb_cur_max` fault
reachable at all (§2, row 19). **The component with the most direct route to
the boot is the one the link-hygiene mechanism cannot see.**

**⚠️ What this does to the verification design, and it sharpens the distinction
rather than collapsing it.** For the wrapper route, "the flag is on" and "every
component got it" collapse into one claim *for every link the wrapper
classifies as a dylib* — which is the real argument for the wrapper over 25
Makefile edits, because it keys on the link **event** rather than on 25 files
that can drift. **But the collapse is conditional on the classifier, and the
classifier has a known blind spot.** So the two claims remain different after
all, and **the delta is exactly the set of links that never pass `-dylib`.**

**So the verification is NOT 25 `otool -l` calls. Three cheap arms, in order:**

> **1. Classifier census.** Capture every link invocation the wrapper sees and
>    count how many lack `-dylib`. **Read-only argv capture, no build.** Right
>    now the answer is **at least one, `objc4`**, plus whatever the census turns
>    up. **Take this arm before anything is decided** — if the answer is larger
>    than one component, the decision is **"fix the classifier" as well as "add
>    the flag"**, and that is a bigger change than the one under discussion.
>
> **2. Invariant on the emitted argv.** For any dylib link, **assert
>    `-Wl,-fixup_chains` is present.** This is a property of the **wrapper**,
>    not of any component — which is precisely why it would have caught the
>    dyld incident, and why it is a gate on the emitted argv rather than another
>    careful read.
>
> **3. End-state census.** The `otool -l` sweep over `usr/lib/system` (§7.10) —
>    the only arm that proves the **goal** rather than the **mechanism**.
>
> Arm 1 is read-only and needs no build, so it is free and it is the one that
> can change the decision. **Do it first.**
>
> **✅ ARM 1 RUN — population is exactly 1.** Every Makefile and `.mk` under
> `Libraries/` was scanned for link rules (`${CC} … -o ${.TARGET}` with no
> `-c`), checking whether `-dylib`/`-dynamiclib` appears **on the link line or in
> the `LDFLAGS` that reaches it**, including multi-line assignments. The
> question turned out to be **structural and answerable statically — no build
> required.** Result: **1 dylib link whose line never carries `-dylib`** —
> `Libraries/objc4/Makefile:118`, the line already quoted above. Sanity checks
> both clean: `Libraries/dyld/Makefile:291` (`-dylib` in `LDFLAGS`) and
> `Libraries/Libsystem/libsystem_c/Makefile:144` (on the line).
>
> **So the decision is the SMALLER one: "add the flag, and fix one Makefile" —
> not "fix the classifier as well".** The file everyone depends on does not
> need to be touched for anything beyond the one flag, and `objc4` is a
> **one-line change of exactly the shape dyld already needed this morning.**
>
> ⚠️ **The census's own limit, so it is not over-read.** It is a **static** scan
> of link rules. It cannot see a link constructed indirectly — a variable that
> expands to `-dylib` from an untraced place, or a rule generated at build
> time. It is strictly better than grepping `-dylib` across a file (which would
> have missed that dyld carries it in `LDFLAGS` rather than on the link line,
> and would have miscounted), **but it is not the argv capture.**
> **The static census BOUNDS the population; arm 2's invariant is what stops
> recurrence.** `objc4` is **NOT fixed** — a one-line change to a component
> nobody has measured this session, better placed as a decision than as a diff
> at this hour.

### 7.12 Where the phases stand, and what the round actually cost

**Four of eight phases are now DONE**, and the plan should say so plainly rather
than leaving a reader to infer it from rows:

| phase | state |
|---|---|
| **Phase 1** `libsystem_kernel.dylib` links | ✅ **DONE** — 617,080 B, 1,470 exports, 12 unprovided (§7.5) |
| **Phase 2** closure recompute | ✅ **DONE** — 133 → **5**, attribution 143 (§7.5) |
| **Phase 3** the tail | ⚠️ **5, not ~7** — 3 blocked behind `libsystem_trace`, 2 a `SRCS` question (§7.5) |
| **Phase 4** real `libdyld.dylib` | ✅ **DONE** — 1 → 28 objects, 987,968 B, 205 exports |
| **Phase 5** the two failures | ✅ `libdispatch` cleared; `libsystem_darwin` **DECIDED unbuilt** (§7.4) |
| **Phase 6** make libraries loadable | ⚠️ **1 of 26** hardened; staging **untouched** (§7.10, §7.11) |
| **Phase 7** boot | ❌ **never exercised this session's work at all** (§7.6) |

**So: the libraries exist, and the boot has never run one of them.** That is the
honest summary of 2026-09-27, and every number above is a statement about
artifacts rather than about a working system.

**What the round cost, in the author's own accounting, because the failure modes
are more useful than the achievements:**

> One regression I introduced — a global shim force-include — caught by a peer.
> My own first bug **reproduced an hour after writing the lesson about it**,
> caught by the instrument that lesson created. A false **"zero"** reported as
> fact. Two more false negatives from my own greps. A malformed offline harness
> that produced two meaningless arms. Three confident wrong hypotheses before
> switching to bisection. **Four inferred causes written into shared documents
> as though they were findings, the last of which was retracted the same day.**

**The lesson, in the form worth keeping:**

> **Every instrument in this project asked a question a compiler or a linker
> could answer.** The two that found what nothing else could were **`clang -E -H`**
> (which header actually answered) and **`bmake -V <var>`** (whether the variable
> the recipe reads is the variable the author edited).

Both are **free**, both are **read-only**, and between them they found more real
defects than any build configuration change made all session.

### 7.13 Peer verification was load-bearing in BOTH directions — the part that would not survive a list of fixes

**This is the finding that would be lost if 2026-09-27 were summarised as
"ten defects fixed, two libraries built".** It is the thing that makes the ten
worth having, and neither worker had it before the other said it.

**Every correction this session went both ways, and that is what made them
cheap.** There were always two instruments pointed at the same claim, so a
disagreement was about *instruments* rather than about whose turn it was to be
believed.

| caught by the `dyld` workstream, in `plan` | caught by `plan`, in the `dyld` workstream |
|---|---|
| a **false "zero"** published as fact | a **format inference** stated as a finding, then retracted |
| an **unearned consequence** ("unloadable") in a comment read as evidence | **1-of-3** where the real number was **1-of-26** |
| **two counting errors** of mine (`1,053`, then `1,075` for a figure that is `1,342`) | a **phantom 289-symbol defect** manufactured by my wrong count |
| a **narrow-scope census** — I checked three libraries and generalised | an **inferred cause** written into a shared document as a measurement |
| a **misattributed commit**, where I blamed the wrong author | the **`-dylib` classifier blind spot** in objc4, invisible to the mechanism |
| — | three more **confident wrong hypotheses** before switching to bisection |

**The generalisable form, and it is the one to keep:**

> **Peer verification is worth nothing if it runs one way.** A workstream that
> only receives corrections has not been verified, it has been *corrected* — and
> the corrections it sends are the expensive kind, because nobody is checking
> them. The condition that makes verification cheap is that **both parties are
> pointing instruments at the same claims**, so a disagreement is a measurement
> dispute rather than a status dispute.
>
> **The test for whether a review culture is real: does it ever find something
> in the reviewer?** If a workstream's error rate is monotonically decreasing
> and no one is being corrected, the most likely explanation is not that the
> work got good. It is that the checks stopped being independent.

**And the honest asymmetry in the cost.** Both workstreams' final reports name
their own failures rather than only their fixes — a false zero, reproduced
lessons, inferred causes, malformed harnesses, scope errors — and both say the
peer correction was load-bearing rather than courtesy. **A report that lists
only achievements leaves every future reader unable to calibrate how much to
trust any single number in it**, and this document's value is mostly made of
knowing which numbers were struck, by whom, and why.

### 7.14 The conditions that produced 2026-09-27 — recreate these, do not admire them

**The reciprocity in §7.13 was not designed and not deserved.** It happened
because certain conditions held, and they are conditions rather than virtues,
which means they can be recreated deliberately or lost by accident. Recorded
here so the next session knows what it is reproducing and what it would have to
rebuild.

| condition | what it bought, concretely |
|---|---|
| **Four workers, one document, no component ownership between them** | nobody could protect a claim by owning the file it lived in; a wrong number in your own section was corrected by a peer with no standing to object |
| **The same read-only instruments available to everyone** — `clang -E -H`, `bmake -V`, `nm`, `otool -l`, `dyld_info` | disagreements were always about a *measurement*, never about whose turn it was to be believed. That is what made a retraction cheap |
| **A tree that was busy most of the time** | forced the read-only instruments to be the primary tools rather than the fallback, which is why the diagnoses exist at all |
| **Low cost to say "that is wrong"** | no hierarchy, no review queue, no politeness cost. Six false claims were retracted in a single day, which is only possible when retraction is free |
| **The document recorded METHOD, not conclusions** | a reader could re-derive a number, and could tell a measured one from an inferred one. This is why §7.5 can hold three struck numbers without becoming useless |
| **Path-scoped commits, never rewritten** | history stayed append-only, so a wrong claim remains visible next to its correction instead of being quietly edited away |

**⚠️ And the three that would have broken all of it, each of which happened at
least once:**

1. **A shared index across workers** — the TOCTOU race (§6.0a). Two correct
   checks, one lost race, and a commit carrying another author's work.
2. **A whole-file write on a shared document** — 2,679 lines replaced by 155,
   caught only by reading `--stat`.
3. **A number quoted without its method** — the 126-symbol attribution stood
   unverified for most of the session and was wrong by 17 when finally
   measured.

**The test, restated because it is the thing to apply on an ordinary day:** if
a workstream's error rate falls and nobody is being corrected, the likeliest
explanation is not that the work got good. **It is that the checks stopped
being independent.** The response is not to try harder — it is to notice the
absence of correction, because that is the signal, and it is silent.

**For whoever picks this up with fewer people:** the two instruments and the
method-not-conclusions rule survive a staffing change. The reciprocity does
not — it needs at least two parties who can check each other, and if that is
not available, the substitute is to make every number re-derivable and state
its method inline, so a later reader can check what nobody could check today.

## 9. How long, honestly

**An estimate with its reasoning shown, because an estimate without one is a
guess wearing a number's clothes.** All figures are per-worker, on a quiet
tree, and exclude queueing.

| Step | Estimate | Reasoning |
|---|---|---|
| Phase 1 — `libsystem_kernel` links | **0.5–2 days** | One `_Static_assert` is the current blocker and the reconciliation is scoped, but "15 constants across 7 headers" was a *census*, and §5.1 records a cascade after a clean-looking first result. Budget for the second and third in-tree-only symbols, not the first. |
| Phase 2 — closure recompute | **hours** | One link plus one analysis pass. It is a *measurement*, and it may falsify the prediction (§4, Phase 2). |
| Phase 3 — last ~7 symbols | **0.5–1 day** | 3 are `libsystem_trace`, which is the expensive tail (§5.3) and may not be buildable at all. |
| Phase 4 — real `libdyld` | **1–3 days** | Independent; frontier is a missing header, which is usually cheap. Can run **concurrently with Phase 1** — see §4.1. |
| Phase 5 — the two failures | **done this round** | `libdispatch` fixed and validated (§7.1a). `libsystem_darwin` diagnosed, fix not yet applied (§7.2) — hours. |
| Phase 6 — converge the image | **1–2 days** | Largely mechanical once the closure is real, but this is where a silent stub does most damage (§5.5). |
| Phase 7 — boot | **hours, if the closure is right** | The signature is stable and the instrument exists. It is a discovery phase, not a construction phase. |

**Serial estimate: roughly 4–9 working days**, assuming Phase 1 behaves and
`libsystem_trace` is not a hard blocker.

**With the concurrency in §4.1 actually used — two to three workers, cleanly
separated — roughly 2–4 days of wall clock**, because Phase 4 and Phase 5 do
not depend on Phase 1 at all.

**Where the uncertainty actually lives, and it is not spread evenly:**

- **Phase 1 is the whole estimate.** If the reconciliation is clean, this is a
  short project. If it opens a fifth in-tree-only symbol, every number above
  moves. *Do not treat the range as a distribution.*
- **`libsystem_trace` is a binary risk, not a duration.** 3 of the ~7
  remaining symbols route through it, and §5.3 concludes it is **not
  buildable** without inventing two struct layouts and a userspace ABI for a
  kernel lock. If that proves hard, the tail is a project, not a task.
- **The 511 s driver run is not on this list** and should not be added to it.
  It is an instrument, and it is reserved (§8.1, T2).

**What would change the prioritisation:** if Phase 1 turns out to be a
reconciliation in the shape of §5.1's warning — a coherent-generation decision
rather than a bridge — then the critical path lengthens by weeks and the
free-running phases (§4.1) should absorb the capacity instead. That is the
decision point, and it is §8, Decision 1.

---

## 10. The 41 untracked Apple files: when they go, and why they are a risk now

**They become deletable at Phase 6, and not before.** Phase 6 is the phase
that stages **our** `libSystem.B` and **our** `libdyld` and drops the Apple
closure. Until that phase *completes and boots*, the 41 files are load-bearing
— the staged Apple `libSystem.B.dylib` is what re-exports all 15 unobtainable
components, and `/bin/echo`'s single load command is that dylib. Deleting them
before then does not "clean up"; it removes the only working closure.

**Until then they are a standing exposure on two axes, and both are live:**

- **Legal.** Apple's binaries, on disk, in the working tree. §5.3 already
  names a concrete instance: `libsystem_trace` staged at Apple's
  **`1861.160.4`** against our Makefile's `1147.0.3`. This is not a
  hypothetical; it is the current state of the boot image.
- **Correctness.** Every one of them is a candidate for the §5.5 silent-stub
  failure, and 7 of the 15 unobtainable components would fail *silently*. The
  `libobjc.A.dylib` case (§5.5) is what that looks like when it goes wrong.

**The posture, so it is not rediscovered from scratch next round:** 41 files
untracked-but-on-disk under `tools/bootlab/assets/`, **deliberately**, with a
`.gitignore` that must stay correctly scoped. Tracked count under that tree is
**14**. `assets/usr/lib/dyld` is still load-bearing for the interop test.
**Do not "clean up" the untracked files, and do not `git add` under
`tools/bootlab/assets/`.**

**Exit criterion for Phase 6, stated in advance so it cannot be quietly
declared met:** the 41 files are deleted **and** `/bin/echo` reaches `main()`
and exits 0 (§1). Both, not either. Deleting them without the boot still
working is a regression, and a boot still working with them present means
Phase 6 has not actually happened.


## 11. Where the detail lives

This page is the plan and the reasoning. The detail is in:

- `tools/bootlab/LIBSYSTEM-KERNEL-BUILD-NOTES.md` — per-defect environment
  facts, with the wrong calls preserved and corrected
- `tools/bootlab/STATUS-AND-OPEN-DECISIONS.md` — current measured state, the
  four corrections, the standing-cavets table
- `tools/bootlab/MACH-HEADER-POLICY.md` — the 46 SDK-only mach headers, one
  line each
- `tools/bootlab/HANDOFF-libsystem_kernel.txt`, `VENDORED-INCLUDE-INVENTORY.md`
- `tools/bootlab/README.md` — the pipeline, step by step
- `Libraries/Libsystem/REMEDIATION_PLAN.md` — component-level status

---

## 8. KNOWN UNMEASURED SURFACES — deferred with a reason, not forgotten

Each entry here is a place where **no instrument currently covers something a
change in this project could plausibly break.** They are listed so that "the
build is green" is never read as covering more than it does.

### 8.1 `Libraries/ICU` — 794 C++ TUs, built by nothing in the driver

**The exposure.** The libc++ shim family was a *global* `-include` of 17
headers on every C++ TU until §7.1b made it per-component opt-in. A component
that genuinely needed it fails **later**, at whatever libc++ header it was
quietly relying on — a silent failure, not a loud one. `Libraries/ICU` has
**794** C++ translation units (the "477" figure that circulated was low) and
appears **nowhere** in the driver's stage list
(`build_all_libsystem.sh` lines 140-195).

**So a green driver run will never say whether the shim opt-in broke ICU.**
794 TUs, no instrument. That is the whole content of this entry.

**Why deferred rather than dropped.** ICU is not in the Phase 7 closure — the
goal is a booting image with a source-built dynamic `/bin/echo` and `/bin/cat`,
and ICU is not in that closure. Funding a 794-TU build for a component outside
the goal while the critical path is open is the wrong trade. Stated as a
decision, not an oversight.

**TRIGGER TO REVISIT — either of these, and it stops being optional:**

1. ICU enters the boot closure, or
2. a shared-file change is made that would plausibly affect it.

In either case **ICU needs its own build before that change is trusted.**

**What the driver DOES cover**, measured from its own stage list rather than
from recollection: of the components the driver builds, the ones with C++
sources are `dyld` (81, opts in via `-D`), `libsystem_malloc` (55),
`libdispatch` (2, was the casualty, now green), `libsystem_m` (1) and
`CommonCrypto` (1, not a driver stage). Everything else is C or Objective-C
and **could not have been affected**, because the wrapper's gate requires
`uses_cxx=yes`. Measurement order and full evidence:
LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 31.

---

## 12. The dyld hang, localized (2026-09-27)

Staging our `libsystem_platform` turned a clean dyld abort into a hang:

```
round 1  (libsystem_c + libCrashReporterClient)  777 lines  exit 1  "Symbol not found: _strlen"
round 2  (+ our libsystem_platform)              632 lines  exit 1  no fault, just stops
```

The question was whether dyld was stuck *inside* the shared-region fallback
or *after* it. Those are different problems. It is **after**.

### 12.1 The hang is deterministic, not a slow boot and not a loop

| Run | kernel budget | lines | `vm_map_get_range` calls | last line |
|---|---|---|---|---|
| W300 | 300 s | 632 | **76** | `vm_map_get_range` |
| W600 | 600 s | 632 | **76** | `vm_map_get_range` |
| round 1 (abort) | 150 s | 777 | **128** | `MACH Reboot` |

Double the budget and get **byte-identical** output: same 632 lines, same
76 calls, tails identical after normalizing addresses. **A loop cannot be
time-invariant**, and neither can a slow boot. This is a fixed stopping point.

### 12.2 The discriminator: Ignition never prints

The `shared_region: ... using individual dylibs` line is line 627 in **both**
the 777-line abort run and the 632-line hang. What follows differs:

```
round 1: 6 more vm_map_get_range, then "Darwin Ignition Sequence Version 1.0.0"
hang:    5 more vm_map_get_range, then nothing. Ever.
```

⚠️ **CORRECTED — see §12.5.** This was read as `shared_region_check_np`
"returning ENOMEM — it sets `error = ENOMEM` and returns; it is not a blocking
call… the fallback *works*." **The kernel that produced these logs did not do
that.** Disassembly of the object it was actually built from shows the
uncommitted local edit set **`EINVAL` (22)**, not `ENOMEM` (12), tore the shared
region down, and **removed the `copyout`**. The `error = ENOMEM` in
`vm_unix.c` is what the *committed* code does; the booted binary did something
else entirely. Reasoning about this path from the source was reasoning about
different code than the one under test.

### 12.3 ⚠️ `vm_map_get_range` is a KERNEL-HEAP proxy, not a userspace mapping

This is the correction that matters most, because the obvious reading is wrong.

Every one of the 76 lines is `range_id=5` with
`min=0xffffffcf01e61000 max=0xffffffffff891000` — and that pair is
character-for-character the `kmem_data_range` line from the zone table in the
**same log** (BOOT-PLAN row: `kmem_data_range : 0xffffffcf01e61000 -
0xffffffffff891000`). In `Kernel/xnu/osfmk/vm/vm_map.c:2151-2159` the print is
guarded by `if (map == kernel_map)` and `range_id == KMEM_RANGE_ID_DATA`.

**These are kernel-heap (kalloc-class) allocations, sizes 4096..1048576 — a
proxy for kernel-side work, NOT for dyld's `mmap` of dylibs.** Counting them as
"mappings dyld made" inverts the causality. The count dropping 128 → 76 may
mean the *kernel* stopped working, not that dyld stopped mapping.

They still rule out a spin: the tail sizes are varied and distinct, not one
value repeating.

### 12.4 What the QEMU log showed — ⚠️ CORRECTED, and the correction reverses the reading

`work/qemu_full.log` is **truncated by every `boot.py` start** — it is only
valid for the run that wrote it and must be copied aside before the next boot.
The W600 original (276 MB) was destroyed by a subsequent launch.

**First reading, and it was WRONG:** "CPL=0 and HLT=0 in 100% of dumps means the
CPU is actively executing kernel code, not idling." That inference rested on
RIPs that could not be symbolized, and it is backwards.

**What was actually blocking it: the kernel runs at a NONZERO slide while the
boot args say `slide=0`.** Measured: **0 of 121,837** interrupt dumps fall
inside the kernel image at its link address (`__TEXT` 0xffffff8000200000 ..
end of `__LINKEDIT` 0xffffff800120f000). Every kernel-space RIP sits ~106 MB
high. So nothing in the file symbolizes against `nm` directly — which is
precisely why the first pass produced nonsense symbol names.

**The slide is solvable.** Scanning 2 MB-aligned candidates for the one
placing the most distinct RIPs on exact function entries yields **`0x6a00000`,
468 exact hits** out of 4,740 distinct kernel RIPs. Slid back, the dominant
tail RIP is:

```
0xffffff80003f9d43   x151 of the last 300    cmpl $0x0, %gs:0x58
```

`0xffffff80003f9d20` is `_ml_set_interrupts_enabled`; the instruction before the
hot one is `sti`. This is the **idle thread waiting for work** — not a spin and
not a deadlock:

```
ffffff8000286740  _idle_thread
  ... cmpl $0x0, %gs:0x58 / jne
  ... callq _ml_set_interrupts_enabled
  ... callq _processor_idle
```

**So the correct statement is the opposite of the first: the CPU is IDLE,
waiting for work that never arrives.** `HLT=0` did **not** mean "actively
executing" — this idle path polls with interrupts enabled rather than halting,
so a clear HLT bit is expected here and discriminates nothing.

**What that costs the diagnosis:** the kernel is healthy and **starved**. It
sits in the idle loop because no runnable thread exists — which is what a
process blocked forever in a syscall, and what a userspace spin that never
re-enters the kernel, both look like from the kernel's side. **The idle-loop
finding does not discriminate between those two**; only the thread state does.
What it *does* establish is that this is **not** a kernel deadlock and **not** a
runaway kernel loop — the CPU is not spinning, it is waiting.

**CAVEAT, preserved:** the sample spans a run whose log was being rewritten
underneath the read, and the tail may sit near teardown. The slide solve is
reproducible (468 exact entry hits) and the idle-loop identification is
structural, but *tail attribution to teardown is not excluded*.

### 12.4b ✅ THE DISCRIMINATOR: dyld is running in USERSPACE, and it is a spin

§12.4 left one thing unresolved: an idle CPU cannot tell a process blocked
forever in a syscall from a userspace spin. **The QEMU log answers it, and the
answer is the spin.** This was found by scanning the *whole* log for `CPL=3`
instead of only its tail — the tail is all kernel because the tail is where
the idle thread runs.

Measured over the full 566 MB / 449,650 interrupt records:

| | |
|---|---|
| `CPL=3` (userspace) records | **1,819** |
| first userspace record | index 218,894 = **48.7% into the log** |
| last userspace record | index 449,550 = **100.0% — the final record** |
| distinct userspace RIPs | 294 |
| userspace address band | **0x1000004f0 .. 0x10bb6eb10** (a 187 MB mapping) |

**Userspace starts at the midpoint and runs, in one contiguous stretch, to the
very last record.** It is not a brief excursion that then died. The CPU is
idle *between* these — the idle thread runs when no user thread is on the CPU
— but there is a runnable user thread, and it is spinning.

The hot userspace addresses cluster tightly at the top of that band
(`0x10ba…`–`0x10bb…`), within ~43 MB, which is a mapping, not a stack. Note
this is **not** dyld's stack: `check_np` was called with `0x7ff7b6b15d58`, and
the band here starts at `0x100000000`. So it is a separate userspace mapping
being executed.

**What this settles.** The hang is **in userspace, executing a hot loop** — not
blocked in a syscall, not a kernel fault, and not the shared-region fallback.
The 76 `vm_map_get_range` lines being *kernel heap* (§12.3) is now fully
consistent: dyld made its last kernel call and then spun without making
another.

**⚠️ NOT YET SYMBOLIZED — and deliberately not guessed.** Identifying *which*
code needs the userspace slide (each run's PIE base differs; the three kernel
slides observed were `0x6600000` apart and 2 MB-aligned) plus a matching
`/bin/echo` or dylib load address. That is the next step, and it is the step
that turns "a spin in userspace" into a named loop.

#### 12.4b-i The spin is a REAL backward branch, and the image is excluded

Run-length encoding the last 400 userspace RIPs finds an actual **tight loop**,
not just "hot addresses":

```
0x10baf9fee  x48      <-- the loop body
0x10baf9ffc  x1       <-- 0xE (14 bytes) away: a short backward branch
```

**318 of 399 consecutive-record deltas are exactly zero** — the same
instruction sampled at the same RIP on every timer interrupt. That is a spin
loop, measured, not inferred. It sits at offset `0xbaf9fee` (186 MB) into the
mapping whose base is `0x100000000`.

**⚠️ The base is suggestive and the image is still NOT identified — one
candidate is now excluded by measurement, and one coincidence is worth
recording so nobody re-derives it as a conclusion.**

- `assets/bin/echo` has `__TEXT vmaddr 0x100000000` — **exactly the band
  base.** That is a real coincidence worth chasing, and it is *not* proof:
  `echo`'s `__TEXT` `vmsize` is `0x1000` (4 KB) while the hot RIPs are 187 MB
  past that base, so the executing code is in a **different mapping** that
  merely starts where `echo` would.
- **`libsystem_c` is EXCLUDED by measurement**, not by absence of trying: an
  exhaustive page-aligned slide search against its 2,392 symbols scores
  **5–8 exact hits out of 454** RIPs. Same negligible result for `libobjc`,
  `libxpc`, `libdyld`.
- The only staged libraries linking at slide 0 are `libCrashReporterClient`,
  `libobjc`, `libsystem_c`, `libxpc` — and none of them is a `__TEXT` big
  enough to hold a 580 KB span of 454 distinct RIPs except `libsystem_c`,
  which is excluded above. **No staged library accounts for the mapping.**

**So the honest position: a spin loop is confirmed and localized to 14 bytes of
a ~600 KB mapping based at `0x100000000`; the binary providing that mapping is
not yet identified.** The next step is a load-address census of the actual
process maps for that run, not another slide guess against staged files.

**Caveat:** sampled from a run whose log was concurrently being appended to,
and the tail may sit near teardown. The 48.7%→100% span is a property of the
whole file, not of a tail slice, so it does not depend on tail selection.

### 12.5 ✅ RESOLVED: the divergent object is located, characterised, and REVERTED

**Where it lived.** Not a template, not a patch step, not a `.o.json`
substitution — `bsd/DEVELOPMENT/vm_unix.o.json` names the committed source
(`/Users/max/Projects/ravynos/Kernel/xnu/bsd/vm/vm_unix.c`) and is itself
clean. The divergence was a **stale object compiled from a local edit that was
subsequently reverted in the tree**: `vm_unix.o` was built 2026-09-26 09:07
from an edited `vm_unix.c`, and the source was later restored (last commit
`394fe3eac3`, the pristine transplant). `kernel_build.py` does not recompile
`vm_unix.c` — it links whatever object the build tree holds, so the stale edit
survived every rebuild. `assets/kernel.development` (committed) never had it.

**Exactly what it changed**, by disassembling `_shared_region_check_np` in the
stale object against a from-source rebuild using the same `.o.json` command
(which reproduces four sibling objects byte-identically, so the command is
exact and the delta is source, not flags):

| | stale object | committed source |
|---|---|---|
| `copyout` (return start address to dyld) | **0 calls** | 1 call |
| `vm_shared_region_remove` | **2** | 1 |
| `vm_shared_region_set` | **2** | 1 |
| error on `..._start_address() failed` | **`EINVAL` (0x16 = 22)** | `ENOMEM` (0xc = 12) |

So the local edit did three undocumented things: it **tore the shared region
down** on failure, it returned **`EINVAL`, not `ENOMEM`**, and it **deleted the
`copyout`** that hands dyld the start address on success.

**⚠️ §12.2's claim was WRONG, and it was wrong in the direction that
hid this.** §12.2 said `check_np` "returns ENOMEM — it sets `error = ENOMEM` and
returns; it is not a blocking call." The booted kernel did **no such thing**:
it set `EINVAL`. Anyone reasoning from the source about the booted binary was
reasoning about different code.

**Judgement: REVERTED, not committed.** The edit is not a defensible
workaround as built. Its stated intent ("using individual dylibs") is
plausible — ravynOS stages **46 individual dylibs and no `dyld_shared_cache`**,
so the shared-region path can never succeed here — but the implementation is
beyond repair as a workaround: it returns an errno that contradicts the
function's own documented contract (the header block at `vm_unix.c:917-920`
says `EINVAL` = "no shared region", `ENOMEM` = "shared region is empty"), and
it drops the `copyout`, so on the success path it would return success while
never telling dyld where the region is. Shipping that as a permanent,
source-committed change would put a knowingly-wrong syscall contract into the
tree to preserve a behaviour whose necessity was never established.

**Action taken:** `vm_unix.o` recompiled from the committed source with its
own recorded command, and the kernel relinked. The rebuilt
`work/stripped_kernel.development` and `work/new_kernel.development` contain
**0** occurrences of `"; using individual dylibs"` and the upstream
`"...vm_shared_region_start_address() failed"` message. **No source change was
required and none was made** — the repo was already correct; only the build
tree was wrong.

#### 12.5-ii ✅ POST-REBUILD BOOT: the shared-region path now matches its source — and the divergent edit was **causing** the hang

Both gates were re-run against the relinked kernel (image content-hash verified
by `mkimage`: *"verify OK: 61 files, 75 tree entries, all content hashes
match"*, fresh `vars.fd`, every verdict read after the process exited).

`run.sh full` (static PID 1, execs nothing): **exit 0**, PID 1 banner +
`USERLAND SUCCESS` + `cat /hello.txt` + alive tick, **0 panics** — 603 lines vs
the pre-revert baseline's 610. The revert is not a regression to a working
boot.

`run_dynamic_gate.sh --window 600` is the instrument that actually calls
`check_np`, and it is where the result is:

| | pre-revert (divergent kernel) | post-revert (committed source) |
|---|---|---|
| `check_np` trace line | `... failed; using individual dylibs` | `... failed` (upstream) |
| `check_np` calls | **1** | **2** |
| **`Darwin Ignition` printed** | **NO** | **YES** |
| serial lines | 632 | 676 |
| last thing dyld did | spin, never reached Ignition | reached Ignition, `ignite() returned 25` |

**The binary now behaves as its source says**, and the two readings differ in
the direction that matters:

1. The kernel prints the **upstream** message, and returns `ENOMEM` as
   `vm_unix.c:970` says. The non-fatal fallback is **not** in the source and is
   **not** in the binary.
2. **`Ignition now prints — for the first time on this campaign.** §12.2 built
   its whole discriminator on "Ignition never prints" as the signature of the
   hang, and §12.2's premise (that `check_np` returned `ENOMEM`) was false. With
   the true upstream behaviour restored, dyld runs **past** the point where the
   divergent kernel stopped dead. **The "hang one step before Ignition" was
   produced by the local edit, not by the committed code.**
3. The frontier moves: dyld now gets as far as `ignite() returned 25` and
   `libignition: ignition boot failed: 25` (errno 25 = `ENOTTY`, "failed to
   lookup preboot") before calling `check_np` a second time and stopping.

**So the edit was not merely undocumented — it was load-bearing in the wrong
direction.** `EINVAL` + shared-region teardown + no `copyout` is not a graceful
fallback to individual dylibs; it is what stopped dyld short of Ignition.
Reverting it moved the failure **forward**, to a named, different error.
`/bin/echo` still does not reach `main()` (gate exit 1, **0 panics**, 0 abort
signatures), so the campaign is **not** unblocked — but the next thing to fix is
now a stated `ENOTTY` preboot lookup, not a mystery stall.

**This invalidates the campaign's dyld results**, because every image built
before this point (`work/boot.img`, `boot_dynamic.img`, `boot_echo.img`,
`boot_exec.img` — 2 hits each) and every `serial_*.log` from 2026-09-26/27 was
produced by the divergent kernel.

#### 12.5a ⚠️ THE SAME DEFECT, IN THREE MORE OBJECTS — still divergent, NOT fixed

The provenance sweep that found this was run over **all 1078 objects** in
`link.filelist`, recompiling each 2026-09-26 hand-built object from committed
source with its own `.o.json`. Seven objects were hand-built that day (they are
**not** in `kernel_build.py`'s recompile list, so they were never rebuilt since);
four reproduce **byte-identically**, three do not:

| object | verdict | divergent functions |
|---|---|---|
| `bsd/DEVELOPMENT/kern_exec.o` | identical | — |
| `bsd/DEVELOPMENT/sys_generic.o` | identical | — |
| `bsd/DEVELOPMENT/systemcalls.o` | identical | — |
| `osfmk/DEVELOPMENT/trap.o` | identical | — |
| **`bsd/DEVELOPMENT/kern_exit.o`** | **DIVERGENT** | `_proc_exit`, `_wait1continue`, `_wait4_nocancel`, `_exit_with_mach_exception` (+ cold) |
| **`bsd/DEVELOPMENT/kern_fork.o`** | **DIVERGENT** | `_fork_create_child`, `_uthread_destroy` (+ cold) |
| **`osfmk/DEVELOPMENT/bsd_i386.o`** | **DIVERGENT** | `_thread_set_child`, `_mach_call_munger64` |

#### 12.5a-i 🛑 `kern_exit.o` — reconstruction says the edit is FOUR changes, only ONE of which is the known fix. STOPPED, not landed.

The earlier note here guessed that the missing `_task_clear_cpuusage` /
`_workq_exit` were "consistent with the known `wait4`/exec-shadow-reap fix".
**That guess was wrong and is retracted.** Reconstructing the source by
hypothesis-and-recompile (build a candidate, diff its disassembly against the
stale object, repeat) identifies the edit as **four** distinct changes:

| # | change vs committed source | attributable to the known fix? |
|---|---|---|
| 1 | **ADD** `wakeup(pp);` inside `proc_is_shadow(p)` branch of `proc_exit` (after `p->p_listflag \|= P_LIST_DEADPARENT`, before `proc_list_unlock()`; source 2546-2550) | ✅ **YES — this is the `wait4`/exec-shadow-reap fix** |
| 2 | **REMOVE** `task_clear_cpuusage(proc_task(p), TRUE);` + comment (2203-2204) | ❌ no |
| 3 | **REMOVE** `workq_exit(p);` + its comment block (2220-2224) | ❌ no |
| 4 | **REMOVE** `if (result) { return result; }` from **`wait1continue`** (2853-2855) | ❌ no |

**Change 1 is confirmed by reconstruction:** adding only that one line makes
`_exit_with_reason` match the stale object *byte-for-byte*, which it does not
match without it. It is also independently corroborated by DWARF — the stale
object's `callq _wakeup` inside `_proc_exit` maps to its own line **2542**,
immediately after `callq _proc_list_lock` at 2539, which is exactly the
committed 2546-2550 branch plus the added wakeup.

**Change 4 is targeted, not incidental:** the file contains the *identical*
guard twice — at 2853 in `wait1continue` and at 3102 in `waitidcontinue`. The
stale object removed it from **`wait1continue` only** and kept
`waitidcontinue`'s. An accidental edit would not be that selective.

**Changes 2 and 3 are the problem.** Neither is the `wait4` fix, and neither is
benign-looking: they remove two `proc_exit` teardown calls, so a process exit
would skip clearing pending CPU-limit accounting and skip workqueue teardown.
Both are external symbols, so their absence is a source fact, not an
optimisation artefact (`nm` finds **zero** references to either in the stale
object). **Under the standing rule — "if any difference is not accounted for by
the known fix, stop and report rather than landing it" — this object is NOT
landed.**

**One difference was investigated and cleared:** `wait4_nocancel` has one fewer
explicit `proc_list_unlock` (5 vs 6), which looked like a lock leak on the
`return ECHILD` path. It is **not** — the stale object's shared epilogue at
`0x4bf7` performs the unlock, so the count balances. Recorded because "missing
unlock before ECHILD" is exactly the kind of finding that gets mis-reported as a
deadlock.

**Also retracted — the `ENOTTY` baseline was not measured against the dead
library.** §12.6 describes `libsystem_platform.dylib.DEAD_APPLE` as
145,572 B / 0 exports. The file actually staged when the `ENOTTY` run booted was
**86,176 B with 204 exports** — an `OURS` build, not the dead extract. Our
build has since been re-staged from the SDK (88,456 B, same 204-export set), but
the `ENOTTY` result should not be attributed to a dead library.

#### 12.5a-ii ✅ `bsd_i386.o` — change 1 **landed and proven**, change 2 characterised but **not** reconstructable

**1. `thread_set_child` discards `pid` — LANDED, proven byte-exact.** The object
writes a literal **zero** in both paths, not a symbol reference:

```
SOURCE    movl %esi, %ebx        ; ebx = pid
          movl %ebx, 0x3c(%rax)  ; iss64->rax = pid
DIVERGENT movl $0x0, 0x3c(%rax)  ; iss64->rax = 0
          movq $0x0, 0x88(%rax)  ; iss32->eax = 0
```

**Proven by elimination, not inference:** recompiling `bsd_i386.c` with only
those two lines changed to `0` makes **every function in the object
byte-identical** except `_mach_call_munger64` and `_mach_call_munger` — which
is exactly where change 2 lives. So change 1 is established, and change 2 is
established as the *only* remainder.

Landed with a comment: a child reaching this path observes `0`, as after a
successful fork, rather than its pid. That is what the exec-shadow proc
machinery needs. **The original rationale was not recorded in the tree** and was
recovered from the linked object — stated at the call site, not invented.

**2. A `current_task()` + `task_pid()` pair added to BOTH syscall mungers —
NOT landed, and deliberately so.** It sits immediately before the
invalid-syscall check (`if (call_number < 0 || call_number >= mach_trap_count)`),
and the result is **discarded**: `task_pid`'s return in `%rax` is overwritten
immediately and never used.

I could not reconstruct it, and I am not going to guess. Writing it as
`(void)task_pid(current_task());` **compiles the calls away entirely** — clang
deletes a discarded call — which is precisely why the stale object *has* them:
the original source must have consumed the value somewhere the trace
machinery compiles out. Guessing at that text would put invented source into
the tree under cover of a byte-level claim, which is the exact failure this
workstream exists to prevent.

So this is recorded as an **open provenance item**: two syscall entry points
carry a pid trace whose form is not recoverable from the object, with no
behavioural effect identified. It is the one remaining piece of `bsd_i386.o`.

#### 12.5a-iii ⚠️ `kern_fork.o` — localised to **one function, 8 instructions**, but not reconstructed

**The stale-object hypothesis is falsified for this one, quickly.** `kern_fork.o`
was built **2026-09-26**; `kern_fork.c` was last committed **2026-09-03**. An
object built 23 days *after* its source's last change cannot be stale, so this
is an **uncommitted edit** — the same category as `vm_unix.o` and
`kern_exit.o`.

**But the localisation is now tight, and that is the real result:**

| | object | committed-source rebuild |
|---|---|---|
| `__text` | 6,508 B | 6,540 B — the object is **32 B / 8 instructions short** |
| functions differing | **`_fork_create_child` only** (108 vs 115) | — |
| symbols only in either | **none** | — |

So the entire divergence is **one function, about seven instructions**, with
no call added or removed and no symbol appearing or disappearing.
`_uthread_destroy`, which had looked divergent, is a **pure line-number shift**
— identical code at a +3 line offset.

**What I tried and rejected.** The object lacks the `init_continuation` local
that `_fork_create_child` uses, so I reconstructed with the ternary inlined
into the `main_thread_create_waiting()` call. That candidate came out **32
bytes *larger*** than the object — the wrong direction, since the object is the
smaller one. So the edit is a *simplification* of that function, not a
refactor of the argument expression, and I have not found it.

**Leading hypothesis, offered as a hypothesis and not a finding:** the DWARF
line sets suggest the object generates no code for the
`if (result != KERN_SUCCESS) { printf(...); task_deallocate(child_task); }`
error path at `kern_fork.c:522-527`. Removing error handling is exactly the
shape that would make a function seven instructions smaller, and it is also
exactly the kind of change nobody should reconstruct from a line table.

**Not landed, not reverted.** The right change here is still *land with a
comment* or *revert*, and that decision needs the same thing `kern_exit.c`
changes 2/3 need: someone who knows why `_fork_create_child` was made
simpler. Eight instructions in one function is a small, bounded question — but
it is still a question, and guessing at it would be inventing source.

**Net position on the original three.** `vm_unix.o` **reverted**; `debug.o`
**landed**; `bsd_i386.o` change 1 **landed and proven**. Two remain open, and
**both are bounded, named questions rather than opaque objects**:
`kern_fork.o` is one function of about eight instructions in
`_fork_create_child`; `kern_exit.c` changes 2/3 are two named teardown calls in
`proc_exit`. Neither is reconstructable from the object, so neither is landed
or reverted — and both are questions for whoever has the history, not defects
this tool can settle.

#### 12.5b-i ✅ THE ASSERTION — the real number is **7**, and 13 of the first 20 were the check's own fault

`tools/bootlab/verify_provenance.py` implements the check: for each object in
`link.filelist`, recompile it from committed source with its own recorded
`.o.json` command and compare. Run over **all 1078 objects**, after the fixes
below:

| | count | meaning |
|---|---|---|
| reproduces committed source | **894** | verified |
| **does not reproduce** | **7** | **not** a build of this tree |
| no `.o.json` recorded | **177** | **unverified** — not the same as verified |

An earlier run of this same check reported **20**. **13 of those 20 were bugs in
the check, not divergences in the tree** — three separate false-positive
mechanisms, each of which called a real, innocent object divergent. All three
were found by asking "is the CODE actually different?" rather than "do the
bytes differ?".

| class | objects | what it actually is |
|---|---|---|
| **cleared — debug-section growth** | `kern_csr.o`, `panic_hooks.o`, `pe_bootargs.o`, `lock_ticket.o`, `locks.o`, `vm_fault.o`, `pal_routines.o` | `__debug_str` +16, `__debug_info` +11, `__debug_str_offs` +4 → 32 bytes, which also drags the segment's `vmsize`/`filesize` and every following `reloff`. **Every function instruction-identical** |
| **cleared — hibernate segment** | `bcopy.o`, `bzero.o`, `WKdmDecompress_new.o`, `WKdmData_new.o` | code sits in xnu's hibernate segment `__HIB` where a plain replay gives `__TEXT`. Section contents byte-identical — a build-configuration difference |
| ✅ **RESOLVED — STALE OBJECT. Rebuilt.** | `machine.o` | `machine.c` itself is unmodified since the transplant (**2026-08-29**). The three `.cold` fragments of `_processor_doshutdown` differ **only in `__LINE__` immediates**, each off by exactly **2** (`$0x2CF` vs `$0x2D1`, `$0x2D2` vs `$0x2D4`, `$0x2D0` vs `$0x2D2`) — asserts in `processor.h`, changed **2026-09-06**, after the object was built. Zero behavioural content |
| **RESOLVED — landed** | `debug.o` | **One change: the serial fallback echo was deleted from `panic_trap_to_debugger`.** All **33 `pal_serial_putc` calls** in the function come from that single block, and the object has none. Rebuilt from source with the block removed, **every non-debug section is byte-identical** except **4 bytes** of `__LINE__` immediate in four `.cold` fragments |
| ✅ **RESOLVED — STALE OBJECT, not an edit. Rebuilt.** | `pcb.o` | **Not a divergent edit at all: an object built six days before a committed header change.** `pmap.h` was last changed **2026-09-06** (`4e658e7656`); `pcb.o` was built **2026-08-31 04:43**. The object predates the ravynOS `no_shared_cr3` block in `set_dirbase()` |
| ✅ **RESOLVED — STALE OBJECT. Rebuilt.** | `machine_routines_asm.o` | **Proven the `pcb.o` way**: reverting the one commit that touched its source (`88b34d8c2a`, **2026-09-03**, which added a `testq`/`jz`/label null-check in `call_continuation`) makes the object reproduce **byte-for-byte**. Built **2026-08-31 04:57**, three days before that commit |
| **real, characterised** | `kern_exit.o`, `kern_fork.o`, `bsd_i386.o` | see 12.5a-i/ii/iii |

**`debug.o` — why the panic echo was removed, and what it costs.** The block
printed a `"\r\n!!! PANIC TRAP TO DEBUGGER: "` banner, the panic format string,
and a trailing `\r\n` to serial. It runs *after* `ml_panic_trap_to_debugger()`.

The reason is measurable from the logs: the bootlab decides "did the kernel
panic" by matching `panic` in the serial log, and in a **healthy** boot the
only matches are the `panic_init: entered... / checking boot args... /
completed successfully!` progress lines. A `PANIC TRAP TO DEBUGGER` banner is
the same false-positive class one level up, and no such banner appears in any
boot log on this campaign.

**The cost, stated rather than hidden:** this block was the fallback for a panic
that reaches serial *only* this way, and that case is now silent. Landed with
that written at the call site.

⚠️ **The `__LINE__` residual is unexplained and is recorded, not dismissed.**
The four differing bytes are `movl $0x873` (stale) against `$0x872` (ours) and
`$0x94` against `$0x93` — every one is **exactly one greater** in the stale
object, including at `__LINE__` 147/148, which is *before* the edited block and
cannot be shifted by it. So the source that built the object also differed from
committed `debug.c` by one line somewhere before line 147. It has no
behavioural effect and I have not located it; it is not claimed as explained.

#### 12.5b-iii ⚠️ `pcb.o` was a THIRD thing entirely — a **stale object**, and the first boot measurement on it was meaningless

Reconstruct-and-test, same method as `debug.o`, resolved it — and the answer is
not "an edit to land or revert".

**The object was built six days before a committed header change.** Removing
this block from `osfmk/i386/pmap.h` makes `pcb.o` reproduce:

```c
	if (no_shared_cr3) {
		/* Degenerate user tables: run user mode on the full pmap so
		 * syscall/IDT entry points need no double-map alias. Used for
		 * bringup (e.g. TCG) where the Meltdown split is unnecessary.
		 */
		ucr3 = pcr3;
	}
```

With it removed, the rebuilt object's `__text` is **exactly 13644 bytes — the
same size as the stale object** — with **2 residual bytes** instead of 10,262.
Those two are `movl $0x296/$0x297` against `$0x295/$0x296`: `__LINE__`
immediates, the same benign residue as `debug.o`.

**The timeline is the proof, and it is not ambiguous:**

| | date |
|---|---|
| `pmap.h` last changed — `4e658e7656`, "Kernel checkpoint: boot to userland handoff" | **2026-09-06** |
| `pcb.o` built | **2026-08-31 04:43** |

**So `pcb.o` is not a divergence to reconcile. The source is right and the
object is out of date.** Rebuilt from committed source; the check now clears it.

**Why this is its own category, and why it is the most consequential of the
three:** `vm_unix.o` and `debug.o` were objects carrying edits absent from the
tree. `pcb.o` was an object *predating a change that is in the tree* — the
opposite failure, and the check cannot tell them apart by looking at bytes
alone. It needed a build-candidate-and-test loop plus `git log` on the
transitive header.

**The consequence, stated plainly: every boot measured on this campaign has
been running a `set_dirbase()` without the degenerate-user-table handling.**
That is the split-CR3 path — the one the bootlab's own boot args and
`--mode full` depend on. `no_shared_cr3` is false under `full`, so the block is
mostly a no-op there, but under `--mode split` it is the difference between
working and not. **No boot result on this campaign should be read as
characterising the committed kernel.**

#### 12.5b-iv ✅ THE HEADLINE: five of the seven were **stale objects**, not uncommitted edits

The alarming reading of this whole workstream was "someone's uncommitted local
patches have been living in build artefacts and silently changing every boot".
**That reading is wrong for the majority, and the difference is one clean
rebuild each.**

| object | built | its source/header last changed | verdict |
|---|---|---|---|
| `pcb.o` | 2026-08-31 04:43 | `pmap.h` **2026-09-06** | stale — 6 days early |
| `machine_routines_asm.o` | 2026-08-31 04:57 | its `.s` **2026-09-03** | stale — 3 days early |
| `machine.o` | 2026-08-31 04:50 | `processor.h` **2026-09-06** | stale — 6 days early, `__LINE__` only |
| `vm_unix.o` | 2026-09-26 09:07 | reverted local edit | uncommitted edit — reverted |
| `debug.o` | 2026-08-31 04:50 | uncommitted edit | uncommitted edit — **landed** |

`pcb.o` and `machine_routines_asm.o` were each **proven**, not inferred:
reverting the one commit that touched their input makes the object reproduce
byte-for-byte. `machine.o`'s entire delta is three `__LINE__` immediates.

**So the campaign's kernel problem is "the build tree is out of date", which is
mundane and fixable, not "uncommitted edits", which would not be.** The two
genuine edits are real and both are now in source.

#### 12.5b-iv-a 📌 THE TRIAGE RULE — one date comparison per object, before any disassembly

> The stale hypothesis was falsified in one check: an object built 23 days
> *after* its source's last change cannot be stale. So this is an uncommitted
> edit — the same category as `vm_unix.o` and `kern_exit.o`, not the `pcb.o`
> family. **Cheap test, decisive answer.**

That is the rule that sorted these seven, and it is worth writing down because
it costs one `stat` and one `git log` and it decides the category *before* you
spend any time reading assembly:

```
mtime(object)  vs  last commit date of the source it names
              (+ every header that source includes, which is where
               pcb.o, machine.o hid)
```

| | reading | verdict |
|---|---|---|
| object **older** than its input's last change | the object predates a committed change | **stale** — rebuild it, change nothing |
| object **newer** | the source changed and was then reverted, or was edited at build time | **uncommitted edit** — reconstruct and land or revert |
| equal | cannot decide on dates alone | fall back to bytes |

`kern_fork.o` is the case that makes the rule worth stating. It looked exactly
like the `pcb.o` family, and reading its disassembly first would have been a
wasted afternoon: one `stat` against one `git log` said "built 2026-09-26,
source last committed 2026-09-03" and settled the category immediately.

**And the input is not always the file named in the `.o.json`.** `pcb.o`'s
source is `pcb.c`, which has not changed since the transplant — the staleness
was in `pmap.h`, three headers down. `machine.o`'s source is `machine.c`,
also untouched — the delta was `processor.h`. Reading only the named source
would have called both "unedited", which is the wrong answer twice.

#### 12.5b-v ⚠️ WHY THEY WENT STALE: assembly objects have only ONE of two build stages recorded

`machine_routines_asm.o`'s `.o.json` is not the command that produced the
object:

```
-o  /var/folders/.../T/machine_routines_asm-2b0762.s
```

It is **stage one of a two-stage assembly build** — preprocess to a temp file
— and the second stage, which actually emits `machine_routines_asm.o`, is **not
recorded anywhere**. `bcopy.o`, `bzero.o` and the `WKdm*` objects are the same
shape.

**⚠️ A RECORDED COMMAND THAT DOES NOT PRODUCE THE THING IT CLAIMS IS WORSE
THAN NO RECORD AT ALL, because it converts an unknown into a false known.**

This is the same hole as the 177 undecidable objects seen from the other side,
and the two are **not** the same defect:

| | the 177 | this |
|---|---|---|
| symptom | no command recorded | a command recorded that does not produce the object |
| what a replay does | nothing | **silently succeeds and writes the wrong file** |
| what a checker concludes | "unverified" — honest | **"matches" — false** |
| fix | record the missing step | record the step that actually runs |

Anyone re-running the provenance sweep over `machine_routines_asm.o` would have
"verified" it against a recipe that cannot reproduce it, and concluded it
matched. I hit exactly that: replaying
`machine_routines_asm.o.json` writes a temp file and leaves the object
untouched, and I only noticed because the object's mtime had not moved.

**So `verify_provenance.py` must not be read as certifying the 177, or the
assembly objects, on the strength of a command that exists.** It compares
what replaying the record produces against what is in the tree; where the
record is incomplete that comparison is not a provenance claim, and today the
script has no way to tell the two apart.

**Practical consequence:** for these objects, refreshing them requires
overriding `-o` to the tree path by hand. Done for `machine_routines_asm.o`;
the check now clears it.

**Where the 7 stand now:**

| object | state |
|---|---|
| `debug.o` | **landed** — serial panic echo, reason and cost both recorded |
| `pcb.o` | **rebuilt** — stale object |
| `machine_routines_asm.o` | **rebuilt** — stale object |
| `machine.o` | **rebuilt** — stale object, `__LINE__` only |
| `vm_unix.o` | **reverted** — uncommitted edit |
| `kern_exit.o` | changes 1 and 4 **landed**; changes 2 and 3 **open question for the user** |
| `bsd_i386.o` | characterised, not landed |
| `kern_fork.o` | characterised, not landed |

**Two remain open**, and both are uncommitted-edit candidates rather than stale
objects.

#### 12.5b-vi ✅ RELINKED — and the one boot attempted is **CONTAMINATED**, so it measures nothing

`kernel_build.py` relinked clean. `work/stripped_kernel.development`:

```
sha256  52a0b37d9974a22455e9481c24f21eb6578dc37272ec07b7d85173d97fbe40df
size    20,043,504 B
mtime   2026-09-27 19:27:35
```

**The provenance check now clears 5 of the 7:** `vm_unix.o`, `debug.o`, `pcb.o`,
`machine.o`, `machine_routines_asm.o`. Still flagged: `bsd_i386.o`,
`kern_fork.o`, `kern_exit.o`.

**A dynamic-gate boot was started on this kernel and it is NOT a result.** A
peer agent rebuilt `work/boot_dynamic.img` at 19:35 while the running QEMU held
it open, and had staged our own `dyld` into it. So that run mixes three
variables — a relinked kernel, a swapped loader, and an image rewritten
mid-flight — and describes none of them. It is recorded here only so it is not
mistaken later for a measurement:

```
pid 1 exited -- exit reason namespace 6 subcode 0x4, description Symbol not found: ___error
panic(cpu 0 caller 0xffffff800a0cc7f9): initproc failed to start
```

**Do not read that as "the relink broke something" or as "the frontier moved".**
It cannot distinguish those. What can be said from it is narrow: the panic text
*did* reach serial (`panic(cpu 0 caller ...)`), so the `debug.c` serial-echo
removal is **not** suppressing panic output on this path — the trade-off
written into that comment is behaving as documented.

**The class, stated once: shared mutable build state with no lock is not a slow
workflow, it is a source of wrong answers.** Three instances, from three
different directions, all producing a measurement that described neither state:

1. **A boot image rewritten under a running QEMU.** Overwriting the file does
   not update what the reader is executing; the result is a mix, and it looks
   like a result.
2. **Two `mkimage` runs racing on one output** — `VERIFY FAIL: content
   mismatch kernel.development`. The hash check *caught* it, which is the one
   consolation: the verifier refusing to describe an inconsistent image is the
   verifier working.
3. **A kernel object stale relative to a header that had already changed** —
   the quietest of the three, and the one that survived a whole campaign.

Same shape as the empty export trie and the unrecorded second assembly stage:
something changed in the build or launch path without anything saying so.
**The mitigation is a handshake, not a lock file** — whoever takes the machine
confirms *taken*, whoever releases it confirms *clear*, and neither moves until
the other has said so. Two agents sharing this lab on 2026-09-27 had exactly
one near-collision, and it was luck rather than process.

#### 12.5b-viii ✅ BOTH BOOTS DONE — the `no_shared_cr3` block is now **measured live**, and the honest claim is narrower than expected

Both runs on the pinned kernel `52a0b37…40df`, each with a freshly restored
`vars.fd`, each read only after the QEMU process exited.

| | `--mode full` | `--mode fallback` (`-s -no_shared_cr3`) |
|---|---|---|
| serial bytes | 36,766 | 37,111 |
| PID 1 banner | 1 | 1 |
| `USERLAND SUCCESS` | 1 | 1 |
| alive ticks | **6** | **6** |
| real panics | **0** | **0** |
| `failed to allocate a major number` | 0 | 0 |
| **`Kernel not sharing user map`** | **0** | **1** (line 231) |

**The mode is proven, not inferred.** `Kernel not sharing user map` appears once
in the `fallback` log and **zero times** in the `full` log. That is the
`pmap.c:543` line, and it is the difference between "I passed the right flag"
and "the flag took effect" — the distinction the whole workstream has been
arguing for, applied to the mode name instead of the mode.

**So `set_dirbase()`'s `no_shared_cr3` branch executed for the first time on a
kernel that has it, and the kernel booted to userland cleanly with it.** That
is the first runtime exercise of the exact code `pcb.o` had been missing since
2026-08-31.

**⚠️ And the claim is still narrower than it looks.** This does **not** show
the fix was *necessary*. `fallback` and `full` produce the **same outcome** —
both clean, both 6 ticks, both 0 panics. Nobody ever ran `fallback` on the
stale kernel, so there is no counterfactual: we do not know that without the
block `fallback` would have failed. What is established is that the block is
**present, live, and harmless** — not that it was load-bearing.

Neither run is comparable to the dyld frontier: `boot.py --img work/boot.img`
uses the static PID 1, which execs nothing, so no dyld ran and no
`shared_region` trace appears in either log. **The image also carries the peer
agent's `MH_DYLINKER`, but it was not reached.** These are kernel-health
measurements and nothing more.

**The known intermittent did not fire** in either run:
`early_random_init: … ccdrbg_init returned! … done!` and zero major-number
failures. Recorded because a run that *had* hit it would have needed a re-run
and would have been an HARNESS result, not a kernel one.

#### 12.5b-vii ⚠️ CORRECTION: the comparison was aimed at the wrong mode — `fallback`, not `split`

This section was wrong, and so was I for most of this workstream, in saying
`--mode split` is the mode the `no_shared_cr3` block affects. **It is not.**

```
split    → BOOT_BASE + " -s"
fallback → BOOT_BASE + " -s -no_shared_cr3"
full     → BOOT_BASE
```

Only `fallback` passes the flag, and the flag is the only thing that sets the
variable (`pmap.c:540`, `PE_parse_boot_argn("-no_shared_cr3", &no_shared_cr3, ...)`).
`no_shared_cr3` is declared `boolean_t no_shared_cr3 = DEBUG;` in `pmap.c:172`.

**And `DEBUG` is not defined in this build.** Proven by compiling a probe with
`kern_exit.o.json`'s exact command line:

```c
#ifndef DEBUG
#error "PROBE: DEBUG is NOT defined in this configuration"
#endif
```

→ `error: "PROBE: DEBUG is NOT defined in this configuration"`. `DEVELOPMENT`
is on the command line; `DEBUG` is not, and does not come from a header.

**So `no_shared_cr3` is FALSE by default in every mode the bootlab has been
using, and the `set_dirbase()` block that `pcb.o` was missing has been dead
code at runtime in all of them.** `--mode split` is exactly as dead as
`--mode full`; only `fallback` exercises it.

**What this does and does not change.** The `pcb.o` staleness was real and is
fixed — the source is now correct and the object carries the block. But no boot
measured on this campaign, and none that `--mode full` or `--mode split` can
produce, would have exercised that block either way. The fix mattered for
correctness of the tree, not for any behaviour observed so far.

**And the good news is that the mode is self-announcing.** `pmap.c:543` prints
`"Kernel not sharing user map"` when the flag takes effect, so a `fallback` run
can be *proved* to have exercised the block by grepping for that line rather
than by assuming it from the boot args.

**The three bugs in the check, each found by chasing a false positive:**

1. **Byte-exact comparison.** A source differing only in comments produces
   identical code and a different line table. Fixed by ignoring debug
   sections.
2. **Excluding debug by SEGMENT rather than by SECTION.** `kern_csr`,
   `panic_hooks` and `pe_bootargs` fold DWARF *inside* `__TEXT`, so a
   segment-offset cut missed them entirely — and blanking the debug bytes
   still leaves `vmsize`/`filesize`/`reloff` changed, because those track the
   debug section's size. Fixed by comparing section **contents**, which does
   not care.
3. **Reading `__bss` as if it had file content.** `S_ZEROFILL` sections report
   file offset 0, so `blob[0:size]` was slicing the **Mach-O header and load
   commands** and calling them section data. That is what made
   `__DATA,__bss` in `pal_routines.o` and `__TEXT,__bss` in `panic_hooks.o`
   read as divergent. Fixed by skipping offset-0 sections.

Plus one more: keying sections by `segname,sectname` reported `__HIB,__const`
vs `__TEXT,__const` as different. Now keyed by section name alone, with
duplicates kept as a list.

**The general lesson, which is the point of the exercise:** four of the five
things this check flagged on day one were the *check* being wrong. A
provenance gate is only as good as its false-positive rate, and every one of
these was a real object that a byte-compare called divergent. Each was caught
by asking "is the CODE actually different?" rather than "do the bytes
differ?".

Verified behaviour after the fixes: the check does **not** fire on any of the
16 cleared objects, nor on `kern_exec`/`sys_generic`/`systemcalls`/`trap`, nor
on the reverted `vm_unix.o`; it fires on exactly the four real ones.

**And the 177 undecidable remain the quieter half of the problem.** The real
build system recorded no compile command for them, so nothing in this tree can
prove what they are. They are ~16% of the kernel, linked into every boot, and
the honest word for them is *unknown*, not *fine*.

It is a **separate opt-in script, not wired into `kernel_build.py`**, for the
same reason: objects genuinely diverge today, so an inline gate would be red on
arrival and would be reporting a backlog, not a regression. It reports and
exits 0; `--strict` is the gate, and it only becomes honest once the real
divergence list above is empty. It is also slow (one compile per object,
~10 min for the whole tree), so it stays off the `run.sh full` path.

`--strict` also fails on objects with **no `.o.json`** — those are *unverified*,
which is not the same as verified, and silently treating them as fine is the
same error in a different costume.

#### 12.5b The rule, instantiated

A measurement of a reproducible thing needs a **pinned copy taken before the
measurement**, and the artifact under test must be **provably** the one that
will actually be loaded. `kernel_build.py` violates the second clause by
design: it recompiles a 43-object allowlist and links the other ~1035 objects
unverified from the build tree, so a hand-edited object is indistinguishable
from a built one. The generalisation to guard: **for any object in
`link.filelist` that is not rebuilt from source in the same run, assert that
rebuilding it reproduces it** — which is exactly the check that found all four
divergent objects here.

### 12.6 ✅ REVERT TEST RESULT: `libsystem_platform` is **INNOCENT** — the hang is unchanged

`libsystem_platform` was reverted to `libsystem_platform.dylib.DEAD_APPLE`
(145,572 B, **0 dyld-readable exports**) and the image **byte-verified** to
carry it (dead-library bytes at offset **60090368** in `boot_dynamic.img`,
re-checked *after* the run). One variable, and the image was confirmed to
contain it — a staged-tree change without a matching image rebuild tests
nothing, and that mistake was already made once on this campaign.

**The hang did not change. Not one bit of the signature moved:**

| | our `libsystem_platform` | **reverted (dead) `libsystem_platform`** |
|---|---|---|
| userspace band | `0x1000004f0..0x10bb6eb10` | **`0x1000004f0..0x10bb6eb10`** |
| hottest userspace RIP | `0x10bb44b61` | **`0x10bb44b61`** |
| dominant kernel RIP | `0xffffff8006df9d43` | **`0xffffff8006df9d43`** |
| kernel slide | `0x6a00000` | **`0x6a00000`** |
| `CPL=3` records | 1,819 | 2,813 |
| `_strlen` abort returned? | no | **no** |

**Conclusion: the correlation was coincidental. `libsystem_platform` is not
the cause.** It is the next library dyld reached, and staging it removed the
`_strlen` abort only by letting dyld get *further* before hitting the same
wall — the fault is upstream of it and was always there. **This is the more
valuable outcome of the two:** the frontier moved, and the next thing to
stage is no longer "find out about `libsystem_platform`."

**Method note — why this test was decisive rather than merely suggestive.**
The serial logs alone could not have settled it: the hang produces no fault
signature, so "still hangs" and "hangs differently" look identical in a log
whose last line is an ordinary kernel message. Comparing the **CPL=3 userspace
fingerprint** — the band, the hot RIP, the kernel slide — is what turned a
"nothing happened" observation into an attributable one. **For a silent hang,
the QEMU interrupt log is the instrument, not the serial log.** Copy it aside
before the next boot; it is truncated on every start.

**Still not done:** the spinning code is not symbolized (§12.4b). The band and
the hot RIP are now known to be **stable across the revert**, which makes that
the right next target — a stable address is a solvable one. It is not named
here because it is not yet known, and two plausible-looking guesses have
already been retracted from this file.

---

## 13. The `ENOTTY` frontier: dyld's ignition, and what `preboot` actually needs

After §12.5 removed the divergent `vm_unix` object, dyld reached
`ignite()` and failed there, naming its own cause for the first time this
campaign:

```
libignition: 1:      preboot: mounting preboot
libignition: 1: failed to lookup preboot: 25
libignition: 1:      preboot: failed to get preboot device: 25
libignition: 1:      preboot: ignition failed: 25
libignition: 1: ignition boot failed: 25
ignite() returned 25
```

`25` is `ENOTTY` (`Kernel/xnu/bsd/sys/errno.h:117`). The **innermost** message
is `failed to get preboot device` — the other three are the same error
propagating outward, so the whole fault is one failed device lookup, not four
separate problems.

### 13.1 What `ignite()` is looking for — established, not assumed

The preboot path in the dyld the image actually loads (`assets/usr/lib/dyld`)
is a **staged Apple dyld**, and its string table names each step separately:

```
/System/Volumes/Preboot
/System/Volumes/Preboot/Cryptexes/OS/
/private/preboot/Cryptexes/OS/
... preboot device: %s          preboot mount point: %s
... failed to get preboot device: %d
... preboot uuid not available; cannot find boot cryptexes: %d
... failed to mount preboot: %d
```

So the sequence is: **get the preboot device → get its mount point → stat/open
it → look up the preboot UUID → find boot cryptexes under
`<preboot>/Cryptexes/OS/` → mount.** It dies at the *first* step.

### 13.2 ⚠️ THE ARTIFACT IS APFS-ONLY, AND WE HAVE NEITHER APFS NOR A PREBOOT VOLUME

**This is the finding: it is not a shared-cache staging question, and it is not
a one-line path fix. It is an architectural mismatch, and no dyld argument
avoids it.**

- A **Preboot volume is an APFS construct.** There is no such thing on FAT32.
- **The boot image is FAT32.** `mkimage.py` builds it via `fat32img.py`; the
  GPT-partitioned image's only filesystem is FAT32.
- **There is no APFS in this kernel at all.** No APFS driver under
  `Kernel/xnu/bsd/vfs/`; the only APFS-named file in the tree is
  `osfmk/kern/kern_apfs_reflock.c`, a lock primitive.
- `IOGetApfsPrebootUUID` is **declared `extern` and never defined** anywhere in
  the tree (`bsd/kern/bsd_init.c:1290`, `bsd/kern/kern_sysctl.c:2937`); it is
  IOKit, which is not in this build.

**The hypothesis in circulation — "we stage 46 dylibs and no shared cache, so
the preboot lookup has nothing to find" — is WRONG, and it is worth killing
explicitly because it is the comfortable answer.** The lookup fails *before* it
ever looks for a cache: it cannot get the preboot **device**. A shared cache
would not fix it, and building one would not fix it. `ignition level 0x5` was
already requested and dyld still ran ignition; the level is not the blocker.

**So this is not a build campaign and not a one-line fix.** It is a third
thing: dyld must be prevented from entering the preboot/ignition path at all,
or given a preboot volume and an APFS stack to find one on.

### 13.3 ⚠️ TWO STAGING FACTS THAT INVALIDATE EARLIER ROWS

Both found by direct measurement while re-staging, and both mean the image is
not running what this file has been claiming:

1. **The image does NOT run our `libdyld`.** The dyld that loads is
   **`assets/usr/lib/dyld` (2,562,000 B, 6 exports)**, a *separate staged
   file*, not `assets/usr/lib/system/libdyld.dylib`. Our real build
   (`Libraries/dyld/libdyld.dylib`, **987,968 B, 205 exports**) is **not
   staged at all** — the staged `libdyld.dylib` is the 385,783 B **Apple**
   binary with **0 dyld-readable exports**. Three distinct dylds exist on disk
   and none of the staged ones is ours.
2. **Our `libsystem_platform` build had been lost** — not in
   `staging_backup/`, which held only the dead Apple extract. It was briefly
   reconstructed from the surviving 262,936-byte `static/libsystem_platform.a`
   (one link, no recompile) to **86,176 B / 204 exports**; that interim rebuild is
   kept at `staging_backup/libsystem_platform.dylib.OURS`.
   **The original 88,456 B / 204-export campaign build has since been restored
   and is what is staged and booted** — so the 86,176 B figure here is the
   *interim rebuild*, not the staged binary. Both define `_bzero` **and**
   `__platform_bzero`, so the alias note below applies to each.
   **The earlier loss is the process lesson: the build product was never backed
   up, only the thing it replaced.**

⚠️ One deviation from the Makefile recipe, recorded because it is not
cosmetic: **the `-Wl,-alias_list,xcodeconfig/libplatform.aliases` was
dropped.** With it the link fails — `duplicate symbol '___bzero'`, because the
archive defines *both* `___bzero` and `__platform_bzero` and the alias list
maps one onto the other. The link succeeds without it. **Whether that alias is
*required* is NOT established**; it links and exports 204 symbols, but "it
links" is not "it is correct", and this deviation should be revisited rather
than inherited.

---

## 14. ✅ BOOT RESULT: the hang is GONE and the fault ADVANCED to `___error`

Run 2026-09-27 18:17, one variable: **our `libsystem_platform` (86,176 B, 204
dyld-readable exports) re-staged.** Image byte-verified to carry ours at offset
60090368 and **not** the dead extract (`find` returned −1). 600 s kernel
budget, firmware prompt at 13.8 s.

### 14.1 The signature changed — this is a result, not a green gate

| Run | libsystem_platform | Lines | Signature |
|---|---|---|---|
| round 1 | dead Apple (0 exports) | 777 | `Symbol not found: _strlen` |
| round 2 | ours | **632** | **no fault — HANG before Ignition** |
| **this run** | **ours (rebuilt)** | **780** | **`Symbol not found: ___error`** |

**The hang did not recur.** `Darwin Ignition Sequence Version 1.0.0` now
prints — it never did in the hang runs — and the boot proceeds *past* ignition
to a clean, diagnosable dyld abort. **The 632-line silent hang is resolved.**

**And the first unresolvable import moved from `_strlen` to `___error`.** The
frontier advanced one symbol. Per the rule that governs this campaign, a
changed signature is the evidence; nothing here is a pass — `/bin/echo` still
does not reach `main()` (`RAVYN-DYNAMIC-USERLAND-OK` count: **0**) and PID 1
panics with `initproc failed to start`.

### 14.2 ⚠️ The new fault is fully characterized: `libSystem.B` wants `_error` from ITSELF

```
panic(cpu 0 caller 0xffffff801f4cc7e9):  initproc failed to start --
  exit reason namespace 6 subcode 0x4 description: Symbol not found: ___error
  Referenced from: <…> /usr/lib/libSystem.B.dylib
  Expected in:     <…> /usr/lib/libSystem.B.dylib
```

Note **`Referenced from` and `Expected in` are the same library.** dyld is not
mis-routing the symbol to a wrong provider; `libSystem.B.dylib` declares an
import it does not itself define.

**Measured: NO staged library defines `_error`.** `dyld_info -exports` across
all 47 staged dylibs returns **zero** hits, and `nm` on `libSystem.B` finds no
`_error` symbol at all. So this is a **staging gap of the same shape as
`_strlen` was**: a leaf nobody provides.

⚠️ **Do not assume which library should provide it.** The obvious guess is
`libsystem_c` (it owns `errno` and friends) and it is **already measured
wrong**: `libsystem_c` exports **0** occurrences of `_error`. The real
provider has not been identified.

### 14.3 Why `_strlen` resolved — a *consequence*, not a fix

`libsystem_c` re-exports the 22 C string/memory functions **through
`libsystem_platform`** (row 10). With the dead extract staged that chain was
severed and `_strlen` failed first; with our 204-export build staged the chain
is intact, `_strlen` resolves, and dyld walks **further** to the next
unsatisfied import. **Nothing was fixed — the first import in the chain simply
moved.** This is exactly the failure mode row 10 warns about, now observed
from the other side.

### 14.4 Logs preserved (both, immediately after exit)

- `work/serial_dynamic.20260927-183021.OURS-platform.log` (48,569 B, 780 lines)
- `work/qemu_OURS-libsystem_platform.1830.log` (82,845,004 B)

`qemu_full.log` is truncated by every `boot.py` start; both copies were taken
as soon as the process exited.

---

## 15. ⚠️ CORRECTION: the failing symbol is `___error` (C `__error()`), not `error()`

§14.2 and row 10h call the fault `___error` and describe it as a **staging gap**
with "no provider identified". **That framing is wrong on the symbol and on the
class of defect.** The evidence:

```
dyld:  Symbol not found: ___error          <-- THREE underscores
```

`___error` is the Mach-O name for C **`__error()`** — the BSD/Darwin **errno
accessor**, declared `extern int * __error(void);`. It is **not** `error()` from
`<err.h>` (which would be `_error`, two characters). §14.2 searched for the
wrong symbol and consequently called it unprovided.

**The provider is `libsystem_c`, and Apple proves it:** Apple's own
`libSystem.tbd` — a **trie-level** description generated from the export
tries, not `nm` — contains `___error,` (1 occurrence). Our build SDK's
`libsystem_c.dylib` has **0 exports** of it and `nm` shows `U ___error`: our
port **imports the function it should define.**

**It is a PORT GAP, not a staging gap.** In the ravynOS tree:

- `Libraries/Libsystem/libsystem_c/include/err.h` — **no** `error`/`__error`.
- `Libraries/Libsystem/libsystem_c/gen/FreeBSD/err.c` — defines
  `err/verr/errc/verrc/errx/verrx/warn/…` and **not** `__error`.
- **No definition of `__error()` exists anywhere under `Libraries/`.**
- Yet it is *used*: `libsystem_c/sys/semctl.c:32-33` does
  `extern int * __error(void);` / `#define errno (*__error())`, and **29
  objects** in `libBase.a` carry `U ___error`.

**So the fix is bounded and known**: add `__error()` to `libsystem_c` and
rebuild it. It is a missing function definition, not a missing library and not
a wrong loader route. This is the first fault in this campaign whose fix is
identified down to the function.

⚠️ **A negative result worth keeping:** the only `error`-named function in the
library tree is cctools' printf-style `void error(const char*, ...)` in
`libmacho/stuff/errors.h`, which is `__private_extern__` (hidden ⇒ never in an
export trie), is not `int error(int)`, and is not even compiled —
`libmacho/Makefile` builds only `arch.c getsecbyname.c getsegbyname.c swap.c`.
It cannot be the provider and was not guessed into the record.

### 15.1 The loader and `libdyld` are DIFFERENT BINARIES — the image runs neither of ours

§14/row 10g said "the image runs Apple's dyld". Precisely, there are **two**
distinct roles, and only one of them is the loader:

| Role | Path | Type | Staged | Ours? |
|---|---|---|---|---|
| **the loader** | `/usr/lib/dyld` | `MH_DYLINKER`, entry `__dyld_start` | `assets/usr/lib/dyld` 2,562,000 B, **Apple** | **never built** |
| **the dyld library** | `/usr/lib/system/libdyld.dylib` | `MH_DYLIB` | was the 385,783 B Apple extract, **0 exports** | `Libraries/dyld/libdyld.dylib` 987,968 B, 205 exports |

**Our 987,968-byte build is `MH_DYLIB` and has NO `__dyld_start`** (the Apple
loader has it at `0x4e50`). It therefore **cannot be the loader**, and copying
it over `/usr/lib/dyld` was not attempted — it would have produced a guaranteed
unbootable image and a meaningless result.

**The real loader target has never been built.** It is
`Libraries/dyld/dyld/makefile` (`-Wl,-dylinker -Wl,-dylinker_install_name,/usr/lib/dyld
-e __dyld_start`), a *different* target from the top-level
`Libraries/dyld/Makefile` that builds the `libdyld.dylib` shim. Its link inputs
are **absent**: `-lc -lpthread -lplatform` (from `$RAVYN_SDKROOT/usr/local/lib/dyld`),
plus `-lc++ -lc++abi` — `libc++`/`libc++abi` exist only as static `.a` under
`Libraries/llvm_target/`, and the in-repo `Developer/ravynOS.sdk` is source-only
with **0 dylibs**.

**What was done instead:** our `libdyld.dylib` was staged at **its own
install-name path** `/usr/lib/system/libdyld.dylib`, replacing the 0-export
Apple extract. That is the faithful form of "stage our dyld" — the DYLINKER
path is impossible, and this path is what our binary's own `install_name`
specifies. The Apple **loader is untouched**, so the `ENOTTY` in §13 is
expected to persist, since that code lives in the DYLINKER, not in
`libdyld.dylib`.

**Also resolved — the `ccsha` frontier the brief flagged is NOT real.** Our
`libdyld` imports `_ccsha1_di`, `_ccsha256_di`, `_ccsha384_di` (three, not
two), and the staged `libcorecrypto.dylib` **exports all three**. No
unprovided-symbol failure should arise from them.

---

## 16. Staging our `libdyld` — a clean NEGATIVE, and it confirms §15

Run 2026-09-27 18:38, 600 s kernel budget, firmware prompt 13.4 s. One
variable: our `libdyld.dylib` (**987,968 B, 205 dyld-readable exports**)
staged at its own install-name path `/usr/lib/system/libdyld.dylib`, replacing
the 385,783 B Apple extract. The **Apple `MH_DYLINKER` loader was left
untouched**, because it cannot be replaced (§15.1).

Image byte-verified: our `libdyld` present at offset **53176320**, the Apple
385,783 B `libdyld` **absent (−1)**, the Apple loader still at 44963840.

### 16.1 The signature did NOT move

```
Symbol not found: ___error
  Referenced from: <3229D4F7-FE40-3BE4-BCB9-F21F1C734B21> /usr/lib/libSystem.B.dylib
  Expected in:     <3229D4F7-FE40-3BE4-BCB9-F21F1C734B21> /usr/lib/libSystem.B.dylib
```

**Byte-identical to the previous run** — same UUID, same `Referenced from`,
same `Expected in` (a `diff` of the two fault blocks is empty). 780 → 782
lines, and `ignition boot failed: 25` still present at line 675, as expected
while an Apple loader is in place.

### 16.2 Why this is the *expected* outcome, and why it is worth having

The fault is **entirely internal to `libSystem.B`** — an import it declares
and cannot satisfy — and `libSystem.B` is a **71,948 B extract with 0
dyld-readable exports**. Swapping a different dylib elsewhere in the closure
cannot satisfy a symbol the failing image is expected to provide *itself*.

**This is a clean negative that strongly confirms §15 rather than a failed
experiment:**

1. It rules out `libdyld` as a factor in the `___error` fault.
2. It **confirms the fault is a `libsystem_c` port gap**: only `libsystem_c`
   can export `__error`, and ours imports it (`U ___error`) without defining
   it. **No staging change can fix that** — it requires adding `__error()` to
   `libsystem_c` and rebuilding it.
3. It produced **no new failure** — in particular **no `ccsha` error**, so
   our `libdyld`'s own imports were not the obstacle. Whether it was actually
   loaded is not distinguishable from the serial log; the absence of any new
   fault is the measurable fact.

**The next step is now identified to the function:** add `__error()` to
`Libraries/Libsystem/libsystem_c` and rebuild. Darwin's primitive for it,
`__mach_errno_addr()`, is already referenced by
`libsystem_pthread/pthread_cancelable.c:57`, so the implementation has an
existing basis in the tree rather than needing new machinery.

### 16.3 Logs preserved

- `work/serial_dynamic.20260927-185010.OURS-libdyld.log` (48,683 B, 782 lines)
- `work/qemu_OURS-libdyld.1850.log` (86,619,297 B)

---

## 17. `__error()` — BLOCKED, and why a global is not the answer

Authorised to implement `__error()` in `libsystem_c`. **The per-thread
semantics cannot be established with what the tree has, so this stops here
rather than shipping a global or an invented TLS.**

### 17.1 The storage exists and is already wired — that part is not in question

- `Libraries/Libsystem/libsystem_pthread/internal.h:231` —
  `errno_t err_no;  // thread-local errno` in `struct _pthread`.
- `pthread.c:905` and `:1629` — `t->tsd[_PTHREAD_TSD_SLOT_ERRNO] = &t->err_no;`
  in **both** thread-init paths. The slot holds a **pointer to** the thread's
  errno, not a copy.
- `__TSD_ERRNO = 1` (`os/tsd.h:37`), aliased as
  `_PTHREAD_TSD_SLOT_ERRNO` (`tsd_private.h:83`).
- The SDK contract is exactly one function: `sys/errno.h:80-81` declares
  `extern int * __error(void);` and `#define errno (*__error())`. **Every
  `errno` use in the entire userspace is a call to this**, which is why 29
  objects in `libBase.a` carry `U ___error`.
- **Nothing reads the `err_no` field directly** (no `->err_no` anywhere). The
  TSD slot is the *only* accessor path, so reading it would be exactly right.

### 17.2 ⚠️ The reader primitive is ABSENT — used in four places, defined nowhere

Reaching that slot requires `_pthread_getspecific_direct(slot)`, which
`tsd_private.h:283-291` defines as an inline over **`_os_tsd_get_direct`**.

**`_os_tsd_get_direct` and `_os_tsd_get_base` have NO definition anywhere in the
tree** — no `.c`, no `.s`, no assembly primitive — and `libsystem_pthread`
exports **no TSD symbol at all** (its only tsd-ish export is
`__pthread_clear_qos_tsd`). They are referenced by:

```
Libsystem/libsystem_malloc/malloc_printf.c
Libsystem/libsystem_platform/os/lock.c
Libsystem/private/pthread/tsd_private.h
Libsystem/private/os/semaphore_private.h
Libsystem/libsystem_pthread/private/tsd_private.h
```

Those references are **latent**: `libsystem_platform/os/lock.c:299-305` calls
it from a `static inline __attribute__((always_inline))` helper that is never
called, so the symbol is eliminated and that library links. **Any code path
that actually needs the TSD reader cannot link.**

### 17.3 Why `__thread` TLS was rejected rather than shipped

`__thread int _e; int* __error(void){return &_e;}` is per-thread, not a
global, so it would satisfy the letter of "never a global" — and it is still
wrong here, for a reason specific to this codebase:

1. **It would be a second errno.** The real one is `t->err_no` via TSD slot 1.
   A private TLS copy is a different location; anything that ever reaches the
   pthread-side storage sees a different value.
2. **dyld itself calls it.** `Libraries/dyld/src/glue.c:291-294` declares
   `extern int* __error(void);` and uses it — and dyld runs *before* the pthread
   runtime has populated any TSD slot. That is precisely why Darwin keeps errno
   in the pthread struct rather than in TLS: the early-dyld path must not
   depend on runtime initialisation. A `__thread` in a dylib additionally
   requires dynamic TLS to be set up by the loader at that moment.

**So the blocker is a missing runtime primitive, not a missing function
body.** Writing `__error()` correctly means first providing
`_os_tsd_get_direct` (x86_64 TSD-base read, likely assembly) **in
libsystem_pthread, exported** — after which `__error()` itself is one line.
That is the unblock, and it is a different component from the one authorised.

## 18. ⚠️ CORRECTION: the dyld loader's link inputs are PRESENT, not absent

§15.1 said the loader's inputs were "absent". **That was wrong, and the cause
is worth recording: `RAVYN_SDKROOT` is not the in-repo
`Developer/ravynOS.sdk`.** That directory is source-only and has **no `lib/`
at all**; the real build SDK is
`/Users/max/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk`.
Checking the wrong one produced a confident, wrong negative.

**Against the real SDK, every input the loader needs is on disk:**

| Input | Status |
|---|---|
| `-lc -lpthread -lplatform` → `$RAVYN_SDKROOT/usr/local/lib/dyld` | **PRESENT** — `libc.a` (26 members), `libplatform.a` (47), `libpthread.a` (18) |
| `-lc++ -lc++abi` | **PRESENT** — `libc++.a`, `libc++abi.a` in the SDK (also in `Libraries/llvm_target/`) |
| `-lunwind` | **PRESENT** — `libunwind.a` |
| `-lCrashReporterClient` | **PRESENT** — `libCrashReporterClient.dylib` |
| `SRCS` | **32 / 32 present** under `Libraries/dyld/` (`.PATH: ${.CURDIR}/..` — they resolve from `Libraries/dyld`, *not* from `Libraries/dyld/dyld`) |
| `dyld.exp` (exported_symbols_list) | **PRESENT**, 1,461 B |

**Conclusion: the loader is BUILDABLE.** It has never been built — there is no
`Libraries/dyld/dyld/dyld` binary — but nothing is missing. The one open item
is whether the link succeeds with `-nodefaultlibs` against these static
archives, which is a link attempt, not a missing prerequisite.

**This is the decision that matters for the project:** whether the boot can
ever run *our* dyld is not blocked by absent inputs. It has been untested
because nobody ran the build, not because the material is unavailable.

---

## 19. ✅ `__error()` IMPLEMENTED AND PROVEN — and the chain to boot is blocked above it

### 19.1 ⚠️ The primitive was NOT missing — the same "wrong place" failure, a fourth time

§17 concluded `_os_tsd_get_direct` was "defined nowhere". **That was wrong.**
It is defined as an `always_inline` in **`os/tsd.h`**, which
`libsystem_pthread/private/tsd_private.h:56` already includes. The earlier
grep missed it because it looked for a *function-definition* pattern and this
is an inline in a header. **Same class as the preboot lookup, `libobjc`, and
`RAVYN_SDKROOT`: not-found from a search that was never pointed at the right
place. Four instances now — this is the project's most expensive failure mode
and it deserves a standing rule (§20).**

`os/tsd.h` supplies it two ways, and `Kernel/xnu/libsyscall/os/tsd.h` is the
in-tree original of the same header: a GS-relative path
(`_os_tsd_get_base()` = `((void * __attribute__((address_space(256))) *)0)`)
and a direct `__asm__("mov %%gs:%1, %0" ...)`. Both are the **x86_64 Darwin
mechanism, in-tree** — nothing was hand-written, and
`libsystem_pthread/pthread_asm.s:162` (`movl %gs:0x0, %edx // pthread_self()`)
independently confirms `%gs:0` is the TSD base.

### 19.2 What was added

**`Libraries/Libsystem/libsystem_c/gen/FreeBSD/err.c`** — the right home: it
is the err family and it is already compiled into `libFreeBSD.a`. 48 lines, all
additive:

```c
int * __error(void) {
	return (int *)_os_tsd_get_direct(__TSD_ERRNO);
}
```

plus an `#error` guard so the build **fails** rather than silently compiling a
global if `<os/tsd.h>` is ever unavailable. `libsystem_c`'s
`unexport.list` is **empty** (a deny-list, not an allow-list), so the symbol
will export.

### 19.3 PROOF — it compiles to the Darwin mechanism

Built for real, then disassembled:

```
___error:
  movq $0x1, -0x8(%rbp)                    ; slot 1 = __TSD_ERRNO
  movq -0x8(%rbp), %rax
  movq %gs:__e_visprintf(,%rax,8), %rax      ; %gs-relative, index*8
  retq
```

`nm` reports `T ___error` — a defined **global**, so it is a real export and
not dead-stripped. **The function is correct, per-thread, and derived rather
than invented.**

### 19.4 ⛔ Two blockers remain ABOVE it, and neither is in `libsystem_c`

**(a) `libsystem_c` cannot LINK.** It needs `-lsystem_trace`
(`-Wl,-upward-lsystem_trace`), and that dependency cannot be satisfied three
ways over:

1. **Absent from the SDK** — it is not in `usr/lib/system` (26 dylibs, none of
   them `libsystem_trace`).
2. **Fails to build** — a mach-generation mismatch: `log.c` wants
   `struct os_log_buffer_s` / `os_log_buffer_context_t` (the SDK generation)
   and instead reaches `Kernel/xnu/libkern/os/log_mem.h`, failing on
   `unknown type name 'lck_spin_t'` and ~19 more. **This is the documented
   danger area** — row 20 records that a previous libtrace fix "was too blunt"
   because libtrace is load-bearing for `os_malloc`/`os_calloc`/`os_strdup`.
   **Deliberately not fixed here.**
3. **The only extract is dead** — the staged `libsystem_trace.dylib`
   (219,902 B) fails to link with `mis-aligned LINKEDIT content 'data in
   code'`, the **same defect class** that killed `libsystem_platform` and
   `libsystem_pthread` as staged libraries (row 10).

**(b) `libSystem.B` has never been built.** The image's
`usr/lib/libSystem.B.dylib` is a **71,948 B extract with 0 dyld-readable
exports** that carries `U ___error`. dyld's message is `Expected in:
/usr/lib/libSystem.B.dylib` — it expects the symbol *there*, because
`libSystem.B` is a **pure re-export umbrella**
(`Libraries/Libsystem/Makefile:35-42` re-exports `libsystem_c` and ~14
others). **So even a correctly linked `libsystem_c` would not fix the boot
until a real umbrella is built and staged** — and none is, in the tree or the
SDK.

**Net: the fix is correct and in place; the route to the image is blocked in
two places that are each a real piece of work, and neither is the function
any more.** No boot was run this round and no signature is claimed.

### 19.5 The dyld loader was NOT built this round

§18 established every input is present. The build was not started: the
`libsystem_c` build was occupying the shared SDK (the campaign forbids
concurrent builds into it), and the loader build is a large, separate piece of
work. It remains the cheapest large experiment available, and it is still
unattempted.

---

## 20. ⚠️ STANDING RULE: "not found" from a search pointed at the wrong place

This has now happened **four times**, always with the same shape — a confident
negative, an expensive conclusion built on it, and a later correction:

| # | What was searched | Where it was actually looked for | Cost |
|---|---|---|---|
| 1 | `libobjc.A.dylib` | only `$SDK/usr/lib/system/`, never `$SDK/usr/lib/` | a 22-symbol "libobjc is absent" bucket, called the **largest Phase-6 blocker** |
| 2 | the `ENOTTY` preboot lookup | assumed a missing shared cache; the real cause is that **the lookup dies at its first step** | a comfortable wrong cause, defended at length |
| 3 | `RAVYN_SDKROOT` | the in-repo `Developer/ravynOS.sdk`, which is source-only with **no `lib/`** | "the loader's link inputs are absent" — **wrong**; all of them are present |
| 4 | `_os_tsd_get_direct` | grepped for a *function definition*; it is an **`always_inline` in `os/tsd.h`** | "the TSD primitive is defined nowhere; a runtime primitive must be written" — **wrong**; it was already in the tree |

**The rule:** before recording ANY absence, confirm the search was pointed at
the right place. Concretely —

1. **An inline in a header is a definition.** Grepping for a definition
   pattern misses `static __inline__` in a header. Search for the *symbol*,
   then read what is found.
2. **Find the real `RAVYN_SDKROOT` before searching the SDK.** It is
   `/Users/max/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk`,
   **not** the in-repo `Developer/ravynOS.sdk`.
3. **Resolve `.PATH` before counting missing sources.** `Libraries/dyld/dyld/makefile`
   sets `.PATH: ${.CURDIR}/..`, so its `SRCS` resolve from `Libraries/dyld/`.
   Checking `Libraries/dyld/dyld/` showed **36 "missing"** files that all exist.
4. **A negative that would be expensive to be wrong about gets a second,
   independent check** before it is written down.

**Why this is the most important section in this file.** Each of the four
produced a *confident, plausible, wrong* answer, and in three cases the wrong
answer was acted on — one became a 22-symbol blocker, one a defended root
cause, one a wrongly-blocked campaign. A correct answer found by a search that
could not see is worth less than an honest "I did not find it, and here is
exactly where I looked."

### 20.1 The general form, and a fifth instance

The rule is **not** "check where the probe was pointed." It is **"check what
pattern the probe assumes."** Absence of a construct a probe cannot express is
indistinguishable from absence of the construct. The assumptions that have
each produced a false "absent" here:

| # | Probe assumed | Reality |
|---|---|---|
| 1 | symbol names are case-sensitive | `UNWIND_EPILOGUE` case-folds |
| 2 | `NAME;` means a pointer | `char name[1024]` |
| 3 | the SDK is `Developer/ravynOS.sdk` | it is under `/Users/max/Projects/build/...`; the in-repo one has **no `lib/`** |
| 4 | a definition is a function definition | `_os_tsd_get_direct` is an **`always_inline` in a header** |
| 5 | `-lNAME` resolves to `NAME.dylib` | it resolves to **`libNAME.dylib`** — the linker supplies the prefix |

**So before recording any absence, name the assumption the probe was making**,
and check that assumption is what the toolchain actually does. §21 is the fifth
instance, caught within the same round that produced it — which is the only
reason it is cheap.

### 20.2 ⚠️ STANDING RULE: a UNION must be asserted ≥ its largest member

Added 2026-09-27 after §38.8 recorded a union that was **provably broken and
would otherwise have been believed**: a shell loop over 44 libraries produced
`P_dyld = 1,550` while one member of that same union — `libsystem_kernel` —
had **1,581** exports on its own. A union smaller than its own largest member
is not a measurement, and nothing about the output looked wrong.

**The rule, for every union computed in this project:**

1. Compute each member's size individually as you go, not just the union.
2. **Assert `union ≥ max(member)` before reporting anything derived from it.**
   This is cheap and it is the only thing standing between a broken loop and a
   confidently wrong closure table.
3. If the assertion fails, **discard the union** and every number computed
   from it. Do not "sanity check" it by eye.

It applies to symbol unions (`nm -gjU`), export tries (`dyld_info -exports`),
file lists, and any set built by looping. It is a **control**, in the same
family as the positive controls above: a result that cannot be wrong is not a
result.

Two sibling traps from the same round, both worth the standing status:

- **Match on `dyld_info`'s exit code, not on a grep for `error`.** A grep for
  `error` matches the *symbol* `__error`, and reported a healthy 1,255,496 B
  `libsystem_c.dylib` as FAILED.
- **Mach-O symbol names carry a leading underscore, and the count matters.**
  `___error` is three. A `sed 's/^_//'` plus a two-underscore search makes a
  defined symbol look undefined *and* the reverse. Compare **exact** Mach-O
  names; do not normalise.

---

## 21. The `libSystem.B` umbrella — ⛔ blocked on the SAME `-lsystem_trace`

Ordered ahead of the loader because it is the campaign's frontier: the image's
`/usr/lib/libSystem.B.dylib` is a **71,948 B Apple extract with 0
dyld-readable exports** carrying `U ___error`, so every boot result this
session has been measured **through a dead umbrella**. `Libraries/Libsystem/Makefile:35-50`
builds the real one as a pure re-export umbrella, and it has never been built.

### 21.1 ⚠️ Fifth instance of §20, caught in the act

The first audit of the umbrella's 26 link inputs reported **four** missing:
`llaunch`, `lcopyfile`, `lremovefile`, `libsystem_trace`. **Three of those were
wrong.** `-lcopyfile` resolves to **`libcopyfile.dylib`** — the linker supplies
the `lib` prefix — and I had checked for `lcopyfile.dylib`. Re-audited against
the real names, **exactly one input is genuinely missing: `-lsystem_trace`.**

The umbrella was **not** blocked on four libraries. It is blocked on one. The
generalisation §20 asks for is the right one and this is its cleanest example:
**the probe assumed a naming convention (`lNAME` → `NAME.dylib`) that the
toolchain does not use.**

### 21.2 Three of the four gaps closed

`liblaunch`, `copyfile` and `removefile` all have sources and all built clean:

| | size |
|---|---|
| `liblaunch.dylib` | **91,704 B** |
| `libcopyfile.dylib` | **74,472 B** |
| `libremovefile.dylib` | **26,552 B** |

`libc++.a` was already in the SDK, so `-lc++` resolves. **The umbrella's link
inputs are now complete except for one library.**

### 21.3 ⛔ The remaining gap is the one we were told not to fix — and it is the SAME one

§19.4(a) blocked `libsystem_c`'s link on `-lsystem_trace`. **The umbrella's
link needs it too** (`-Wl,-reexport-lsystem_trace`, and `-lsystem_trace` at
`Makefile:45,49`). The premise that the umbrella "does not depend on
`libsystem_trace`" is **wrong**, and it is worth correcting rather than
working around: `-lsystem_trace` is on the umbrella's own link line.

Proven with a control, not inferred — same link line, one flag changed:

```
with    -lsystem_trace  ->  ld: library 'system_trace' not found   (exit 1)
without -lsystem_trace  ->  0 errors
```

**So there is exactly one blocker between us and a real umbrella, and it is
the library that was explicitly placed off-limits this round.** It cannot be
produced: `log.c` (519 lines, 1 of only 3 TUs) fails on the mach-generation
mismatch reaching `Kernel/xnu/libkern/os/log_mem.h`. It cannot be
substituted: **no static archive exists**, and the only copy on disk is the
dead staged extract with mis-aligned LINKEDIT content.

**Consequence, stated plainly: the umbrella, the `MH_DYLINKER` loader, and the
relink of `libsystem_c` are now all blocked behind ONE library** — and that
library is in row 20's documented danger area, where a previous blunt fix was
already rejected once because libtrace is load-bearing for
`os_malloc`/`os_calloc`/`os_strdup`. **That is now the single highest-leverage
unblock in the project**, and it is a decision, not a search.

No boot was run and no signature is claimed. Nothing was staged.

---

## 22. ⛔ The `MH_DYLINKER` loader build — FAILS AT COMPILE, not link

Built 2026-09-27. **The premise that the loader is "the one unblocked
experiment" is wrong.** Its *link* inputs are all present (§18), but the build
never reaches the link: it dies in **3.8 s** with three compile errors in the
very first translation unit, `src/dyldInitialization.cpp`.

### 22.1 The three errors, and two of them are two flags

| # | Error | Cause |
|---|---|---|
| 1 | `unknown type name 'DyldSharedCache'` (`ImageLoader.h:305`) | a **cascade** from #2 |
| 2 | `expected ';' at end of declaration list` — `uintptr_t thread __kernel_data_semantics;` (`kdebug_private.h:476`) | `__kernel_data_semantics` **is** defined, at `Kernel/xnu/bsd/sys/cdefs.h:1320`. The loader's makefile has **no `-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd`**, so the SDK's `sys/cdefs.h`, which lacks it, wins. **Fix: `-I Kernel/xnu/bsd`** |
| 3 | `use of undeclared identifier 'amfi_check_dyld_policy_self'` (`dyldSyscallInterface.h:135`) | the header reads `#if !defined(__RAVYNOS__) && __has_include(<libamfi.h>)` → include `libamfi.h`; `#else` → declare the stub itself. **`__RAVYNOS__` is never defined in this build**, so it takes the `#if` branch, and `libamfi.h` does not carry this newer symbol. The stub already exists at `src/missing_symbol_stubs.c:212`. **Fix: `-D__RAVYNOS__`** |

**Verified, not inferred:** re-compiling that one TU with **only**
`-D__RAVYNOS__ -I Kernel/xnu/bsd` added takes it from **3 errors to 1**. The
header already contains a ravynOS accommodation for exactly this case and it
has simply never been switched on. Error 1 was a cascade and goes with #2.

### 22.2 The remaining error is STRUCTURAL, and it is not about one header

```
fatal error: 'System/sys/event.h' file not found
```

**`sys/event.h` is present** — 18,015 B, among **186** headers under
`System.framework/Versions/B/PrivateHeaders/sys/` in the build SDK. The cause
is that **`System.framework/Versions/B/` contains `PrivateHeaders/` and no
`Headers/` directory at all.** `#include <System/sys/event.h>` under
`-iframework` resolves through the framework's **`Headers/`**, which does not
exist here.

⚠️ **So this is not one missing header — it is every `<System/...>` include in
dyld failing**, and dyld uses that form throughout. Expect recurrence across
the 32 sources rather than a single fix. It is a third *kind* of blocker:
`libsystem_trace` is a mach-generation mismatch, this one is a framework
layout gap.

### 22.3 An audit note, in the interest of not repeating §20

While diagnosing #1 I first concluded `sys/event.h` was **absent from the build
SDK**, on the strength of a search whose pattern only matched the in-repo
SDK's path. It is present. **Sixth near-miss of the standing rule, caught
inside the same round that produced it.** Two of the last two were caught only
because the rule made me re-probe rather than write down the first answer —
which is the argument for having written it down.

### 22.4 State

**No source was changed** — the two flags were passed on the command line for
the test compile; `Libraries/dyld/dyld/makefile` is untouched. **No boot, no
staging, no signature.** The loader is **2 flags and 1 structural SDK gap**
away from compiling, and the **link remains untested** — so even a successful
compile would not yet establish that the `-nodefaultlibs` link against the
static archives works.

---

## 23. ✅ The loader COMPILES — and reaches the link, where a seventh §20 instance stops it

### 23.1 What was committed, and each verified

| Change | Verification |
|---|---|
| `-D__RAVYNOS__` + `-I Kernel/xnu/bsd` in `dyld/dyld/makefile` | compile errors 3 → 1 |
| `System.framework/Versions/B/Headers` + top-level `Headers` symlink, in `build-libraries.sh` | `<System/sys/event.h>` now resolves; **created → removed → re-synced → returned** |
| **DELETED** `Libraries/dyld/DyldSharedCache.h` | compile errors 1 → **0** |

⚠️ bmake does **not** permit `#` comments inside a backslash-continued
assignment — putting them inside `COMMONFLAGS` broke the build with
`Unassociated shell command`. The comments now sit **above** the variable.

### 23.2 The deleted file is the §5.5 stub failure mode in its purest form

`Libraries/dyld/DyldSharedCache.h` is a committed **ZERO-BYTE** file (in git
since `ae6124feae`). The makefile's `-I${.OBJDIR}/..` **is** `-I Libraries/dyld`
and it is the **first** `-I` in the list, so `#include "DyldSharedCache.h"`
resolved to the empty file and every use of the type became `unknown type
name`. Confirmed both directions with `-H`:

```
with  -I Libraries/dyld first  ->  Libraries/dyld/DyldSharedCache.h            (0 bytes)
without                        ->  Libraries/dyld/dyld3/shared-cache/…        (declares it)
```

**A zero-byte file that satisfies an `#include` is not a file that defines the
wrong thing — it is one that defines nothing while appearing to satisfy the
reference.** That is more dangerous than a wrong stub, and it is the reason it
is recorded rather than just fixed.

### 23.3 ⛔ Where it stops: the link, on a SEVENTH instance of §20

```
ld: Shared cache eligible dylibs cannot use '-undefined dynamic_lookup' or '-U'
```

This is the project's **own already-documented** error, and its known remedy is
`-Wl,-not_for_dyld_shared_cache` — which `isysroot-cc:672` adds. But that line
is inside the wrapper's link-hygiene branch, and `isysroot-cc:276` decides that
branch **solely** on:

```
-dylib|-dynamiclib|-Wl,-dylib|-Wl,-dynamiclib
```

**The loader links with `-Wl,-dylinker`, which the wrapper does not know.** The
branch never fires, so `-nodefaultlibs`, `-undefined dynamic_lookup` **and the
remedy** are all never applied. **A third spelling of the same link mode,
missing from a four-way case statement.** The next change is one line, and it is
not made here.

### 23.4 The §18 open item, answered

§18 asked whether the loader's link inputs were present. They were. §22 found
the build never reached the link at all. **It does now** — the `-nodefaultlibs`
link against the static archives is no longer theoretical, and the first
obstruction to it is a wrapper that does not recognise `-dylinker`. **No boot,
no staging, no signature this round.**

---

## 24. ⚠️ A fourth instance of the class, and the narrow rule it yields

### 24.1 The generalisation, stated usefully

**An artifact that a live process holds open is not pinned, and overwriting it
does not update what that process is running.**

Observed 2026-09-27: `work/boot_dynamic.img` was rebuilt at 19:35 while another
agent's QEMU held it open. That QEMU was executing neither the old nor the new
configuration cleanly, and its result was correctly declared unciteable by its
owner. **The generalisation worth keeping is the narrow one above** — it is
actionable, unlike "be careful", because it says exactly which artifacts are
unsafe to touch while a run is in flight.

### 24.2 It is the same shape as three earlier findings

| | What changed silently | What it invalidated |
|---|---|---|
| stale `vm_unix.o` | a build-tree object predating its source | every boot result, on a kernel not in the tree |
| empty export trie | 25 of 26 dylibs in the old export format | every closure census over them |
| `isysroot-cc:276` | a four-way `case` missing `-dylinker` | the loader's entire link hygiene |
| **image under a live QEMU** | **the file a running reader was executing** | **that run's result** |

**Common shape: something in the build or launch path changed without anything
saying so, and a measurement taken across the change describes neither state.**

### 24.3 The loud/silent asymmetry, which is the expensive half

The same class has a *loud* and a *silent* form, and the silent one is the
dangerous one:

- **Loud:** a `#` comment inside a bmake backslash-continued assignment →
  `Unassociated shell command`. Cannot be missed; costs minutes.
- **Silent:** a comment inside the same kind of continuation in
  `Libraries/dyld/Makefile` truncated `COMMONFLAGS` to **6 tokens** and said
  nothing — a green-looking build is still possible.
- **Silent:** `pcb.o` stale from 2026-08-31, predating the committed
  `no_shared_cr3` block — every boot on this campaign ran a `set_dirbase()`
  without the degenerate-user-table handling, and the build was green throughout.

**The failure mode that costs a day is the one that does not announce itself.**
Three instances here are not three coincidences; they are one habit of trusting
a green build.

---

## 25. Boot with our loader — ⛔ the KERNEL panicked first, so the run says NOTHING about the loader

### 25.1 What was staged, and how it was verified

Pre-boot checks, both done and both reported rather than assumed:

- **VERIFIED CLEAR** — no `qemu-system` process; another agent's run held the
  image and was **not** killed (its owner declared that run contaminated and
  unciteable, which is the correct call and the same class as §24).
- Fresh `vars.fd` restored before the boot.
- Image rebuilt once, cleanly. ⚠️ **My own error, recorded:** I first launched
  two `mkimage` runs against the same output file and got
  `VERIFY FAIL: content mismatch kernel.development`. That was self-inflicted
  and is the *same* class as §24 from the other side — concurrent writers
  producing a result that describes neither state. Rebuilt once, alone, and got
  `verify OK: 61 files, all content hashes match`.

**Verified from the FAT32 image, not the build tree** (the check that
distinguishes our loader from a dylib at the right path):

| | |
|---|---|
| our loader in image | offset **44963840**, 1,733,080 B |
| Apple's loader in image | **−1 (absent)** |
| filetype read from the image | `MH_MAGIC_64 x86_64 DYLINKER` |
| `__dyld_start` | defined |
| `LC_ID_DYLINKER` | `/usr/lib/dyld` |
| kernel in image | offset 2902016, sha256 `52a0b37d…fbe40df` — **matches the relinked kernel byte for byte** |

### 25.2 ⛔ The signature — and why it is NOT a loader result

```
panic(cpu 0 caller 0xffffff80030a63ac): random_init: failed to allocate a
    major number! @randomdev.c:106
  0xfffffff5908d7d40 : 0xffffff8002a68ee5 mach_kernel : _random_init + 0x65
```

624 lines. **The kernel panicked inside `bsd_init`, at `bsd_autoconf` →
`random_init`, before userland existed.** Last stages: `socketinit`,
`domaininit`, `skywalk_init`, `memorystatus_init`, `sysctl_mib_init`,
`bsd_autoconf`, then the panic.

**dyld never ran.** Counted in the log: **0** occurrences of the
`RAVYNOS DYNAMIC-USERLAND GATE` banner, **0** of `Ignition`, **0** of
`Symbol not found`, **0** of `shared_region`. The loader was never invoked, so
this run carries **no information** about whether our `MH_DYLINKER` works.

**This is a known intermittent, and it is a kernel fault with no relationship
to the loader variable.** `random_init` failing to allocate a cdev major number
has been seen on this harness with an identical kernel and image, where the
next identical run reached userland. It is `bsd_init`-stage, pre-dyld, and it
predates anything this round changed. **Treating it as a loader result would be
the exact error this campaign keeps making — attributing a result to the thing
that was changed when the thing that was changed was never reached.**

The right response is a re-run, not a conclusion.

---

## 26. ✅✅ OUR `MH_DYLINKER` RAN — and produced the first USERSPCACE CRASH with a backtrace

The §25 run was a kernel panic in `random_init`, pre-dyld, uninformative about
the loader. **Re-run on the identical, pinned image: the loader ran.**

### 26.1 The signature, verbatim

```
=== RAVYNOS DYNAMIC-USERLAND GATE: execve /bin/echo ===

build_signal_reason: unable to allocate signal reason buffer.
pid 1 exited -- exit reason namespace 2 subcode 0xb, description none
coredump (echo, pid 1): writing core to /cores/core.1
coredump (echo, pid 1): failed to open core dump file /cores/core.1: error 2

panic(cpu 0 caller 0xffffff801c4cc7f9):  initproc failed to start --
    exit reason namespace 2 subcode 0xb description: none

Thread 0 crashed
RAX: 0x0000000000000002  ...  RFL: 0x0000000000010206
RIP: 0x000000010928102d  CS: 0x000000000000002b  SS: 0x0000000000000023
	0x000000010928102d
	0x00000001092829c5
	0x00000001092814a8
	0x0000000109281614
	0x000000010926e7a4
	0x00000001091ef0a1
	0x00000001091ef06e
	0x000000010920c8e3
```

### 26.2 Why this is a different KIND of result, not just a different one

| | every previous boot | this one |
|---|---|---|
| gate banner | absent (hang) or present | **present, line 597** |
| failure | dyld *abort*, namespace 6 subcode 0x4 | **namespace 2 subcode 0xb** |
| what we got | a *symbol name* to go chase | **a RIP and an 8-frame backtrace** |
| `CS` | kernel | **`0x2b` — CPL 3, userspace** |

**`CS: 0x2b` is the load-bearing detail: the crash is in USERSPACE, at
`0x10928102d`, inside a mapping in the `0x1091xxxx–0x1092xxxx` band — which is
where our loader is mapped.** For the first time the campaign has a *fault
address in our own code* rather than a missing symbol in Apple's. The symbol
chasing is over; this is now a debugging problem in dyld, and it has a
backtrace.

### 26.3 Two separate findings, not to be conflated

1. **Our dyld crashes in userspace** at `0x10928102d`. This is the frontier.
2. **`build_signal_reason: unable to allocate signal reason buffer.`** is a
   *kernel* message, and it means the kernel could not even allocate the buffer
   it uses to describe a userspace crash. That is its own defect and it will
   degrade the next crash report too. It is almost certainly the same
   `random_init` major-number allocation trouble seen in §25 — **cdev
   registration is failing on this boot**, which is worth its own line.

### 26.4 Provenance of this run

Same image as §25, byte-verified before both boots: our `MH_DYLINKER` at
offset 44963840 (`MH_DYLINKER`, `__dyld_start`, `LC_ID_DYLINKER
/usr/lib/dyld`), Apple's absent at −1, kernel sha256 `52a0b37d…40df` at
2902016 matching the relinked kernel exactly. **The only difference between
§25's 624 lines and this run's 668 is the intermittent `random_init` panic
clearing** — which is itself more evidence that §25 was the known flake and
carried no loader information.

---

## 27. ✅✅ SYMBOLIZED: the crash is a `%gs` load in `__mig_get_reply_port`, before `%gs` exists

### 27.1 The slide, proven semantically rather than by a metric

16 frames, all inside our loader. Minimising "distance to nearest preceding
symbol" picked base `0x1091c4000` — **which is wrong**: it names `_ioctl` and
`___MIG_check__Reply__host_info_t` at the crash. **The metric chose badly and
was overruled by meaning.**

The correct base is **`0x1091c3000`**, and it is proven by one frame:

```
000000000009b534  T __dyld_start
000000000009b554  callq  dyldbootstrap::start(...)      <-- a CALL
000000000009b559  movq  -0x8(%rbp), %rdi               <-- frame 0x10925e559
```

`0x10925e559 - 0x1091c3000 = 0x9b559`, **the instruction immediately after a
`callq`**. A backtrace's outermost frame is a *return address*, so this is not
a fit, it is an identity. Every other candidate was discarded on this basis.

⚠️ **A wrong "nearest symbol" is the same defect as a wrong instrument.** The
minimising metric is not a substitute for a check that the answer *means*
something.

### 27.2 The crash instruction

```
00000000000be020  t __mig_get_reply_port
  be020  pushq  %rax
  be021  movq  $0x2, __framesize(%rsp)
  be029  movq  __framesize(%rsp), %rax
  be02d  movq  %gs:__framesize(,%rax,8), %rax     <-- RIP 0x10928102d, THE FAULT
  be036  popq  %rcx
  be037  retq
```

**The faulting instruction is a `%gs`-relative load.** `%gs` is the segment
holding thread-local state. It faults because **`%gs` is not established yet at
this point in dyld's bootstrap** — this is 4th instruction into a function
reached from the loader's own allocator's first `mach_vm_allocate`.

### 27.3 The full chain, all 16 frames

| frame | +offset | symbol |
|---|---|---|
| 0x10928102d | +0xbe02d | `__mig_get_reply_port` **+0xd — CRASH** |
| 0x1092829c5 | +0xbf9c5 | `__kernelrpc_mach_vm_allocate` +0x65 |
| 0x1092814a8 | +0xbe4a8 | `_mach_vm_allocate` +0x48 |
| 0x109281614 | +0xbe614 | `_vm_allocate` +0x34 |
| 0x10926e7a4 | +0xab7a4 | `__simple_salloc` +0x24 |
| 0x109201619 | +0x3e619 | `MachOAnalyzer::withChainStarts` +0xb9 |
| 0x10920c51f | +0x4951f | `MachOLoaded::fixupAllChainedFixups` +0x9f |
| 0x10920c6e9 | +0x496e9 | `MachOLoaded::forEachFixupInAllChains` +0x1b9 |
| 0x10920cb0c | +0x49b0c | `MachOLoaded::walkChain` +0xcc |
| 0x10920c8e3 | +0x498e3 | `MachOLoaded::fixupAllChainedFixups_block_invoke` +0x1d3 |
| 0x10925de3a | +0x9ae3a | `dyldbootstrap::rebaseDyld_block_invoke` +0x7a |
| 0x10925dc9b | +0x9ac9b | `dyldbootstrap::rebaseDyld` +0x10b |
| 0x10925dac6 | +0x9aac6 | `dyldbootstrap::start` +0x96 |
| 0x10925e559 | +0x9b559 | `__dyld_start` +0x25 — **outermost** |

Read as a story: **`__dyld_start` → `dyldbootstrap::start` →
`rebaseDyld` → chained-fixup application → `__simple_salloc` (the bootstrap
allocator) → `_vm_allocate` → `_mach_vm_allocate` →
`__kernelrpc_mach_vm_allocate` → `__mig_get_reply_port` → fault on a `%gs`
load.**

### 27.4 What it means

Our dyld gets through entry, bootstrap, and into **rebasing itself** — real
work, on our own code — and dies when the bootstrap allocator's first MIG
round-trip touches thread-local state that does not exist that early. This is
**a dyld bug, in dyld**, not a missing symbol and not an inherited fault.

It also explains the separate kernel message: `build_signal_reason: unable to
allocate signal reason buffer` — **allocation is failing on this path**, and
the kernel could not even allocate the buffer it uses to describe the crash.
Two symptoms, one area. The cdev major-number theory is still **unmeasured**.

---

## 28. ✅ THE `%gs` FAULT IS FIXED — and it revealed a different fault

### 28.1 Root cause, established before the fix

`__mig_get_reply_port` is **libsystem_kernel's** `mig_reply_port.c`
(`Kernel/xnu/libsyscall/mach/mig_reply_port.c`), reached from the loader via
`__kernelrpc_mach_vm_allocate`. It is a one-liner:

```c
static inline mach_port_t _mig_get_reply_port(void) {
	return (mach_port_t)(uintptr_t)_os_tsd_get_direct(__TSD_MIG_REPLY);
}
```

`_os_tsd_get_direct` is the `%gs`-relative reader from `os/tsd.h` — **the same
TSD accessor `__error()` needs** (§15/§17). So the `__error()` blocker and this
crash are **one missing-primitive problem at two sites**.

**dyld already had the right mechanism.** `src/glue.c:116` defines
`_dyld_setup_minimal_tsd()`, which installs a ten-slot direct-TSD block via
`_thread_set_tsd_base()` and populates the ERRNO slot. Its own comment says it
must run *"before any fallible syscalls hit libsyscall's cerror path."*

**It was called after the fixup walk** — which is exactly where the fallible
syscall lives. **The comment already stated the requirement; only the placement
was wrong.** The fix was to move the call, not to add a mechanism and not to
introduce a global.

### 28.2 Verified in the emitted code, not assumed

In the rebuilt `dyldbootstrap::rebaseDyld`: `callq _dyld_setup_minimal_tsd` at
**0x9ac27 (rebaseDyld+0x97)**, `callq fixupAllChainedFixups` at **0x9ae25**.
Order is now correct in the binary. The old duplicate call was removed.

### 28.3 The boot after the fix

| | before | **after** |
|---|---|---|
| serial lines | 668 | **705** |
| old crash `0x10928102d` | present | **absent (0 occurrences)** |
| fault | `%gs` load in `__mig_get_reply_port` | **a different fault** |

**The `%gs` fault is gone and dyld got further.** A new crash appeared:
`RIP 0x116b8538b`, still `CS 0x2b` (userspace), and the backtrace is a
**repeating 3-address cycle** — 23 frames in the visible window drawn from
just four distinct addresses (0x116b8538b, 0x116b8438b, 0x116b83ff1,
0x116b8542e), one of them an **exact 0x1000** from another. A tight repeating
cycle like that is the signature of **runaway recursion / stack exhaustion**,
not of a bad address.

### 28.4 ⚠️ NOT SYMBOLIZED, deliberately, and the reason matters

**I did not attach function names to the new frames, and this is a considered
refusal rather than an omission.** The slide search returns a "best" base of
0x116af5000 naming `std::__1::vector` internals — **and I do not believe it.**
Unlike §27, there is no outer frame to anchor on: every frame is inside a single
5 KB cycle, so the backtrace carries almost no information about the base, and
the same metric that chose *wrong* in §27 is being asked to choose here with far
less to go on. The one exact 0x1000 spacing between two frames is itself a
reason to distrust the result — a real code layout does not usually place two
recursion sites exactly one page apart.

**Attaching those names would be the same defect as every wrong instrument this
campaign has produced**, and I have been the one catching them. The next step
for this fault is to pin the load address from outside the backtrace — the QEMU
interrupt log, or a loader that reports its own base — and only then symbolize.

**What IS established:** the `%gs` ordering fix is correct, is in the binary,
and removed the fault it targeted. The frontier has moved to a second,
different fault in the same subsystem.

### 28.5 The class-check: this was the INSTANCE, and the class is closed

Cheap check, and it is the one that separates fixing an instance from fixing a
class. `start()` is the whole early path, and it has **exactly one** fallible
step before the TSD block exists:

```
start()
  kdebug_trace_dyld_marker(...)   <- guarded by kdebug_is_enabled(); a debug
                                     trace, NOT an allocation, does not reach
                                     the mig/calloc path
  rebaseDyld(dyldsMachHeader)     <- TSD now established FIRST inside this
  mach_init()                     <- after
```

`dyldbootstrap::start` and `rebaseDyld` both live in **`dyldInitialization.cpp`** —
the same file as the fix — so there is no second copy of the bootstrap hiding
elsewhere, which is itself worth having checked given that `dyldbootstrap.cpp`
does not exist as a file in this tree at all.

**Every fallible syscall on the early path now runs after the TSD block is
installed.** Nothing else in `start()` allocates, and the one call that precedes
it is a tracepoint. So the `%gs` defect is fixed as a class, not just at the one
frame that exposed it.

### 28.6 Pinning the new fault's slide — what is needed, and what is refused

The image gives a **file** offset (44963840), not a runtime base, and the
previous run's slide does not carry over: this run's frames are at `0x116b8…`
against the previous run's `0x1092…`, so the loader is re-slid per boot and
there is **no trusted address to inherit**.

The serial log does not name dyld's load address, and the backtrace cannot
supply it (§28.4). So the slide is **not established**, and no function names
are attached to those frames.

**The cheap, correct way to pin it: have dyld report its own base.** One line
early in `start()` — print or kdebug-trace `dyldsMachHeader`, which *is* the
load address — and one boot. That converts an unanchored backtrace into an
anchored one, and it is strictly better than any amount of slide searching.
Not done this round, and deliberately: it is a diagnostic change to the loader,
not a fix, and it should be labelled as instrumentation rather than mistaken
for progress.

### 28.7 The anchoring instrument: first attempt produced NOTHING, and that is a result

The load-base print was added, the loader rebuilt, image verified (loader at
44963840, Apple at −1, kernel at 2902016), fresh `vars.fd`, booted.

**705 lines — identical to the run before it — and ZERO occurrences of
`DYLD-LOAD-BASE`.** The instrumentation did not fire.

**Cause: the fd.** dyld's own logging is

```c
#define _ZN4dyld3logEPKcz(fmt, ...) _simple_dprintf(2, fmt, __VA_ARGS__)   // glue.c:248
```

and `halt()` likewise uses fd 2. **fd 1 does not reach the console this early
in bootstrap.** I used fd 1. Fixed to fd 2, rebuilt, committed.

**Recorded rather than quietly retried**, because this is the same lesson as
the seven standing-rule instances, one level down: **a probe that cannot see is
not a probe that found nothing.** The instrument was built, the string was
verified present in the binary, the image was byte-verified — and it still
produced nothing, because the one thing I did not check was which descriptor
the loader can actually write to at that point in its own startup.

**What this run does establish**, and it is a second confirmation of §28.6:
the crash RIP was **0x1145d739b**, against **0x116b8538b** in the previous
boot and **0x10928102d** two boots ago. **Three boots, three slides.** No
cross-run symbol comparison is valid here, and the anchoring boot has to be
repeated with fd 2.

---

## 29. ✅ ANCHORED AND SYMBOLIZED — and it is semantically obvious

### 29.1 The instrument, on its third attempt

Two boot cycles were lost to this instrument before it worked, and both
failures are recorded above (§28.7 and the fd-2 attempt): first the wrong fd,
then — after that was fixed — **the print sat AFTER `rebaseDyld()`, the very
call that crashes, so it could never fire.**

**That second failure is the same defect class as the `%gs` fix, committed hours
earlier in the same function: a correct mechanism in the wrong place.** I fixed
that class and then reproduced it in my own instrument. The generalisation that
covers both: *a probe assumes not only a delivery channel but that it runs at
all before the thing it measures.*

**Verified in the emitted binary before the third boot**, not in the source
alone: inside `dyldbootstrap::start`, `leaq` of the `DYLD-LOAD-BASE` literal is
at **0x9aac6**, `callq __simple_dprintf` at **0x9aacf**, `callq rebaseDyld` at
**0x9aad8** — the print precedes the call.

### 29.2 The boot

```
DYLD-LOAD-BASE: 0x119a5b000          <- the loader naming its own address
RFL: 0x0000000000010202, RIP: 0x0000000119b1a39b, CS: 0x2b, SS: 0x23
```

707 lines. **Fifth consecutive slide**, which keeps confirming the re-sliding
finding: `0x10928102d → 0x116b8538b → 0x1145d739b → 0x10e58939b → 0x119b1a39b`.

### 29.3 The cycle, anchored and named

| frame | offset | symbol |
|---|---|---|
| 0x119b19001 | +0xbe001 | `_mig_get_reply_port` **+0x51** |
| 0x119b1939b | +0xbe39b | `_mach_port_construct` +0x4b |
| **0x119b1a39b** | **+0xbf39b** | **`__kernelrpc_mach_port_construct` +0xb — CRASH** |
| 0x119b1a43e | +0xbf43e | `__kernelrpc_mach_port_construct` +0xae |

**It is not a runaway walk. It is a reply-port acquisition loop, and it should
terminate after exactly one `mach_port_construct`.** The source says why it
does not — `Kernel/xnu/libsyscall/mach/mig_reply_port.c`:

```c
mach_port_t mig_get_reply_port(void) {
    mach_port_t port = _mig_get_reply_port();
    if (port == MACH_PORT_NULL) {
        kr = mach_port_construct(mach_task_self(), &opts, NULL, &port);
        _mig_assert(...);
        _mig_set_reply_port(port);      // <-- store it
    }
    return port;
}
```

**The loop means the port it stores is not being seen on the next call** — so
`_mig_get_reply_port()` reads NULL again, constructs again, and repeats. The
store and the load disagree.

**This is the SAME defect as the `%gs` fault, one level deeper, and that is the
finding.** The `%gs` fault was that no TSD base existed at all; my fix
established one, and the load no longer faults. But the TSD is now only
**partly** right: `_dyld_setup_minimal_tsd()` populates slots 0 (THREAD_SELF) and
1 (ERRNO) and leaves the rest of its ten-slot block as zeroed statics, while
`mig_reply_port` round-trips through slot 2 (`__TSD_MIG_REPLY`). **The base is
established; the slot's write is not surviving the read.**

**Semantically obvious, ours, and located** — which is the standard this whole
campaign has been arguing for and the first defect to meet it.

### 29.4 ⚠️ The register file corrects §29.3 — the TSD fix WORKED, and the authorized next fix is probably wrong

Three things in the register dump, none of which required the print to see:

**1. The anchor is independently confirmed.** `R8: 0x0000000119a5b000` — that
is **exactly the `DYLD-LOAD-BASE` the loader printed**. The offset arithmetic in
§29.3 is therefore right by two independent routes, not one.

**2. The crash is a STACK STORE, and the stack is exhausted.**

```
__kernelrpc_mach_port_construct +0xbf390  pushq %rbp
                                   +0xbf391  movq  %rsp, %rbp
                                   +0xbf394  subq  $0x90, %rsp
                                   +0xbf39b  movl  %edi, -0x8(%rbp)   <-- FAULT
```

`movl %edi, -0x8(%rbp)` is the **fourth instruction**, a stack write. It cannot
fault except with a bad `%rsp` — and `RSP 0x7ff7b1c8bf70` sits **0x90 below
`RBP 0x7ff7b1c8c000`**: the frame has no room left. The stack is at its limit.
(An earlier crash had `RSP 0x7ff7b7f2b620`; this one is far lower — the stack
has *grown*.) **So the loop is unbounded, and what we are seeing is stack
exhaustion, not a bad address.**

**3. ⚠️ The faulting function is `_mig_get_reply_port` — TWO underscores — where
the pre-fix crash was `__mig_get_reply_port`, THREE.**

That is the important one. The %gs fault was inside `__mig_get_reply_port`'s
`_os_tsd_get_direct(__TSD_MIG_REPLY)`. **We no longer crash there.** The TSD
read is now succeeding, which is precisely what the ordering fix was supposed to
achieve.

**Therefore the authorized next step — "make slot 2 round-trip" — is probably
not the right change, and it has NOT been applied.** The evidence says the TSD
path is now working and the fault has moved downstream, into a port-construction
loop that exhausts the stack. Shipping the authorized fix on the strength of the
previous round's reasoning would be re-committing a conclusion the new
measurement has already overtaken — which is the error this file exists to
prevent.

**What is needed next, and it is a different question:** why does
`mig_get_reply_port` recurse? Either the reply port still is not surviving, or
`mach_port_construct` re-enters. **Those are distinguishable and I have not
distinguished them.** The next step is to read `mig_reply_port.c`'s construct
path and `__kernelrpc_mach_port_construct` together, not to apply a fix
authorised against a premise this section has just overturned.

### 29.5 The cheap check ELIMINATES my own §29.3 diagnosis

The two candidate causes, and which one survives:

**Cause 1 — the reply port fails to survive (my §29.3 diagnosis). ELIMINATED.**

| | |
|---|---|
| slot `mig_reply_port.c` reads | `_os_tsd_get_direct(__TSD_MIG_REPLY)` |
| slot it writes | `_os_tsd_set_direct(__TSD_MIG_REPLY, port)` |
| `__TSD_MIG_REPLY` | **2** (`libsyscall/os/tsd.h:38`, and the SDK header agrees) |
| what `_dyld_setup_minimal_tsd()` sets the base to | `sMinimalTSD` |
| what it populates | slot 0 (THREAD_SELF), slot 1 (ERRNO) |
| **slot 2** | **left as a zeroed static — inside the block, and NULL is the correct first value** |

So slot 2 **is** in the ten-slot block, **is** zero-initialised, and the store
and the load both go through the same `%gs` base. **The round-trip should
succeed**, whether or not `_thread_set_tsd_base()` itself worked — if the
syscall failed, both the store and the load would use whatever base `%gs`
already held, and they would still agree.

**Which means the authorized fix would have changed nothing.** Declining it was
correct, and this is why: the diagnosis it rested on does not survive its own
cheap check.

**Cause 2 — `mach_port_construct` re-enters. SURVIVING, and the source predicts
it.** `mig_reply_port.c` carries this warning directly above the function:

> *"Tracing is masked during this call; otherwise, a call to printf() can
> result in a call to malloc() which eventually reenters
> `mig_get_reply_port()` and deadlocks."*

The observed cycle is exactly that shape — `mig_get_reply_port` →
`_mach_port_construct` → `__kernelrpc_mach_port_construct` → back — and it ends
in **stack exhaustion**, not in a bad address. A MIG subsystem that needs a
reply port in order to reply is a bootstrap deadlock, and it is a **design
issue rather than a missing initialisation**.

**So the next step is not a fix but a decision about the construct path**, and
it should be read as code before anything is changed. Recording the elimination
matters as much as the finding: a plausible chain of causation survived one
round of enthusiasm and died on a four-line check.

### 29.6 DESIGN CALL: (2) — bypass MIG in the bootstrap allocator, not a re-entrancy guard

**The evidence that decided it.** `_mach_port_construct` disassembles to a
**direct trap**, not a MIG call:

```
_mach_port_construct:
  be376  callq  __kernelrpc_mach_port_construct_trap
```

**So `mach_port_construct` does not itself need a reply port, and the re-entry
is NOT the `printf`→`malloc` path the comment in `mig_reply_port.c` names.**
That warning is real but it is not what is happening here. The cycle runs
through the kernelrpc *path*, and the bootstrap allocator reaches MIG at all
only because `__simple_salloc` → `_vm_allocate` is a MIG-generated stub.

**Why (1) is rejected, on the coordinator's own stated reasoning.** A
re-entrancy guard in `mig_reply_port.c` means a **plain static in-progress flag
in a library that is shared with all of userspace and is not single-threaded
there.** The loader is single-threaded at this point, so a static would be
correct *here* — and wrong everywhere else, in exactly the shape already
rejected once in this campaign: a global standing in for per-thread state is a
silent-wrong-answer defect. It also adds a re-entrancy invariant to a
subsystem whose own comment states it was never designed for one.

**Why (2) is the answer.** The circularity exists only because the bootstrap
allocator is routed through MIG. Removing that routing removes the circularity
rather than papering over it, and it is almost certainly what Apple's dyld does
— which is why this has never surfaced there. It also confines the change to
dyld's own bootstrap, where the single-threaded assumption actually holds, and
leaves `mig_reply_port.c` — shared, and correctly not re-entrant — alone.

**What implementing it requires, stated so the next person does not have to
re-derive it:** dyld's `__simple_salloc` must reach a vm allocation without a
reply-port round-trip. That means either a direct trap wrapper for
`vm_allocate` used only before `mach_init()`, or a small bootstrap-only
allocator. **The correct boundary is `mach_init()`** — which §28.3 already
established runs *after* `rebaseDyld()`, so "before mach_init" is exactly the
window in which the circularity exists and exactly the window in which a
bypass is safe.

**Not implemented this round, and the reason is budget rather than
doubt.** The decision is made and evidenced; a change to the bootstrap
allocator needs a build and a boot to verify, and this turn has neither left.
Shipping it unverified would be the error this file exists to prevent, in the
opposite direction.

### 29.7 The fix site, located exactly — and it IS in dyld's own bootstrap

`_simple_salloc` in libsystem_platform is a red herring for this bug. **dyld
carries its own `__simple_salloc`**, and it is the one on the crashing path.
Disassembled from the loader's own image:

```
__simple_salloc:                                   (0xab780, dyld's own)
  ab788  leaq  _mach_task_self_(%rip), %rax
  ab78f  movl  __framesize(%rax), %edi
  ab795  movl  $..., %edx
  ab79f  callq _vm_allocate        <-- the MIG-generated stub
```

**So the routing is dyld's own, not libsystem_platform's.** That is exactly
the scope the coordinator set: the change belongs in dyld's bootstrap, where
the single-threaded assumption actually holds, and **libsystem_platform and
`mig_reply_port.c` are both left untouched** — neither is the defect.

**The change is therefore one call site**, `__simple_salloc` at 0xab780 in
`Libraries/dyld/…`, plus an explicit runtime boundary that flips at
`mach_init()` so the bypass cannot leak past it. Making the boundary a runtime
check rather than a comment is the requirement, and it is satisfiable here
because `mach_init()` is a distinct, already-identified call site
(§28.3, after `rebaseDyld()`).

**Not implemented this turn: budget, not doubt.** The decision is evidenced and
the site is now a single function, but the change needs a build and a boot to
verify and neither is available. §29.6 already recorded why shipping it
unverified is the same error in the opposite direction, and that reasoning
applies to me as much as to anyone else in this campaign.

### 29.8 ⚠️ CORRECTION to §29.7 — I attributed ownership from location, not provenance

§29.7 said *"the routing is dyld's own, not libsystem_platform's"* and that
libsystem_platform could be left untouched. **That is wrong, and it came from
the same error I have been catching all session: reading a symbol in a linked
binary and inferring where it is defined.**

`__simple_salloc` is at 0xab780 **in dyld's image** because dyld statically
links `libsystem_platform.a`. Its provenance is:

```
libsystem_platform.a:string_io.o:  00000000000010a0  T __simple_salloc
libsystem_platform.a:asl.o:                            U __simple_salloc
```

and the source is `libsystem_platform/simple/string_io.c:486`,
`_simple_salloc()`, which calls `vm_allocate()`. **It is libsystem_platform's
code.** Changing it would change that library for every consumer.

**So the coordinator's scope instruction and the code's actual location are in
tension, and the tension resolves against editing `string_io.c`:**
`libsystem_platform` is shared and must not be modified for a loader-only
bootstrap concern. The change therefore has to be **a dyld-local allocation
path that shadows the linked `_simple_salloc` for the pre-`mach_init` window
only** — which is a shim, not an edit, and which is why the "explicit runtime
boundary" the coordinator asked for is not optional decoration here: it is the
only thing keeping a dyld-local path from becoming a second, divergent
allocator for the rest of userspace.

**Not built this turn, and the correction is why.** I was about to build on a
premise I had just falsified. Building it would have meant either editing a
shared library against instruction, or inventing a shadowing scheme I had not
verified. Both are the error this file exists to prevent, and the second would
have carried a confident commit message saying the circularity was resolved.

### 29.9 ⛔ The scoped fix CANNOT LINK — measured, not argued

The coordinator's scope was "a dyld-local path that shadows the linked
`_simple_salloc` for the pre-`mach_init` window." **That is not linkable**, and
the reason is a static-archive fact:

```
libsystem_platform.a:string_io.o  provides 14 symbols, including
                                  __simple_dprintf, __simple_esprintf,
                                  __simple_put, __simple_sfree, ...
```

**dyld uses `__simple_dprintf` throughout**, so `string_io.o` is pulled into
the link **regardless** of whether `__simple_salloc` is defined elsewhere.
A dyld-local definition of `__simple_salloc` is therefore a **duplicate symbol**
against an archive member that is already being linked for other reasons. An
archive member is skipped only when nothing it provides is still undefined —
and here plenty is.

**So the scope as given is not implementable**, and the real choice is narrower
than it looked:

| option | cost |
|---|---|
| **(a)** gate a bypass inside `string_io.c` itself | the code is there and the gate is a runtime check on `mach_init`, so it is shared-CORRECT — but it edits a library the coordinator scoped out |
| **(b)** intercept at dyld's call sites | no shared edit, but `__simple_salloc` is called from many places in dyld3, and missing one silently reintroduces the circularity |
| **(c)** give dyld its own allocator under a different name and convert its bootstrap callers | no duplicate, no shared edit, but it is a larger and less obviously correct change than either of the above |

**None of these is a one-line change, and I am not picking one by preference.**
(a) is the smallest and is arguably in-scope after all — the coordinator's
exclusion of `libsystem_platform` was aimed at my *wrong localisation*, and the
correction in §29.8 moved the code back there. **That is a question for the
coordinator, not one to resolve by guessing**, because the tension is between a
scope instruction and a link-time fact, and only they hold both.

**Nothing built this turn.** The measurement above is the deliverable: a scoped
change that would have failed at link, found before it was written.

---

## 30. Design findings for the bypass — reading only, machine yielded

No build, no boot, and **nothing written to `libsystem_platform`** while the
other worker holds their two boot windows.

### 30.1 The source-level gate site

`Libraries/Libsystem/libsystem_platform/simple/string_io.c:486`,
`_simple_salloc()`:

```c
_SIMPLE_STRING
_simple_salloc(void)
{
	BUF *b;
	if(vm_allocate(mach_task_self(), (vm_address_t *)&b, VM_PAGE_SIZE, 1))
		return NULL;
	...
}
```

**One call, one line, the smallest gate in the tree.** This is dyld's
`__simple_salloc` at 0xab780 with `callq _vm_allocate` at 0xab79f — the same
function, seen from the other side. The direct-trap target already exists in the
image as **`__kernelrpc_mach_vm_allocate_trap` (0xbdd00)**, so no new syscall
plumbing is required.

### 30.2 ✅ The `mach_init` signal IS observable, and needs no new flag

This was the question that could have invalidated the design, so it is worth
being precise. `mach_init.c:102` keeps `static bool mach_init_inited` — **not
observable outside that translation unit**, and editing it would mean touching
libsyscall.

**But the signal is already exported.** `mach_init.h:76`:

```c
extern mach_port_t      mach_task_self_;      /* NOT static -- exported */
#define mach_task_self() mach_task_self_
```

and `mach_init.c:66` initialises it to `MACH_PORT_NULL`, with the only
assignment being `mach_init.c:135`, inside `mach_init_doit()`:

```c
mach_task_self_ = task_self_trap();
```

**So `mach_task_self_ != MACH_PORT_NULL` is a runtime, exported, already-in-scope
predicate for "mach_init has run"** — and `string_io.c:26` already includes
`<mach/mach_init.h>`, so the symbol is visible with no new header and no change
to libsyscall.

⚠️ **Stated honestly, it is a proxy, not a dedicated flag:** it becomes true
when `mach_init_doit()` runs, which is also what `_mach_fork_child()` calls.
So the boundary is precisely *"mach_init (or a fork) has initialised the mach
layer"* — which is exactly the condition under which the MIG path is safe, and
is arguably the more correct predicate rather than a proxy for it.

### 30.3 Blast radius, and what it actually is

| question | answer |
|---|---|
| Other `__simple_salloc` users in the library | **`asl.o` only** (`__simple_esprintf`, `__simple_sappend`, `__simple_sfree`) |
| `__simple_salloc` call sites in dyld's image | **6** |
| `mach_task_self.h` needed? | no — `mach_init.h` already included |

**The blast radius is small and it is the same for every consumer.** `asl.o`
is libsystem_platform's own, and the gate is a runtime check, so asl's users
get identical behaviour: the trap path only while `mach_task_self_` is NULL,
which is only before `mach_init()`. **No consumer is worse off**, and after the
boundary every one of them reaches the original `vm_allocate` path, unchanged.

**One thing that is NOT yet established, and should be before the change ships:**
whether dyld has any *other* pre-`mach_init` allocation route that does not go
through `__simple_salloc`. Six call sites in the image use it, but the image
cannot show which of them execute before `mach_init()`. **If one of them is on
a different early path, the gate would not cover it** — and the signature would
be unchanged, which is the "the circularity is not where the disassembly put it"
outcome and is worth knowing immediately.

### 30.4 What is committed, and what is deliberately not

**Nothing.** The design is fully determined by the three findings above, and the
change is one call site — but writing it into `libsystem_platform` on disk while
another worker is mid-build would contaminate their measurement, which is the
failure mode this project has paid for repeatedly and which I have declined
twice today. **The change is written and held, not written and landed.**

### 30.5 `build_signal_reason` is MEASURED — and it kills my UNMEASURED cdev theory

The other worker (on `build_signal_reason`) established the cause:

> `build_signal_reason: unable to allocate signal reason buffer` appears on
> every userspace crash on this system, and its cause is **a `Z_NOWAIT` zone
> refusal, not a cdev/random_init problem.**

**This retires a theory I had been carrying as UNMEASURED for several rounds.**
§19.4(a) and §25.3 both recorded that the message was "plausibly related to the
cdev major-number trouble seen in the `random_init` panic" and that this was
**unmeasured**. It is now measured, by someone else, and it is **wrong**. The
message is a zone-allocation policy refusal on the crash-reporting path; the
`random_init` cdev failure is a separate intermittent.

**Two different faults that I had merged into one story.** They are unrelated,
and the honest correction is that the link I drew was plausible, repeatedly
labelled unmeasured, and false. Keeping the label is what stopped it becoming
a conclusion — and it was the peer, not me, who closed it.

**What this changes for my work:** nothing structurally, and one thing
practically. The `build_signal_reason` message will appear on every crash in my
runs and is **not** a signal about the dyld fault — it is a property of the
crash-reporting path, not of the fault being reported. Anyone reading a future
log should not treat it as part of the dyld signature.

**Collision clearance, on evidence rather than assurance:** their build is
`kernel_build.py` only — xnu kernel objects and a relink of
`work/stripped_kernel.development`. It does not touch `Libraries/Libsystem`,
and their image was staged at 22:04 from a **previously built SDK**, not one
they rebuild. So my unbuilt `string_io.c` change cannot be in their image. The
QEMU running since 22:04:29 is theirs — boot 1 of 2 — and I have not touched
it. **No revert is held.**

---

## 31. The `__simple_salloc` gate is BUILT — and the cycle is read from source, not from the symbol table

Built 2026-09-27, 22:09-22:10, alone, `ps` verified clear of bmake / build-libraries /
isysroot-cc / mkimage / QEMU immediately before. `libsystem_platform` rc=0; the
`dyld` subdir linked and produced a **1,733,184 B** loader (was 1,733,080, +104).
The overall `build-libraries.sh dyld` rc=1 and that is **not** this change: the two
errors are in `Libraries/dyld/libslc_builder` (`ClosureBuilder.h:286: no template
named 'optional' in namespace 'std'`, a libc++ gap, plus one `kdebug_private.h`
parse error). Different component, pre-existing, untouched.

### 31.1 The gate is in the emitted code, not just in a green build

Verified in the artifact, because §8e's trap is exactly "a build that succeeded
and changed nothing":

| artifact | evidence |
|---|---|
| `SDK/usr/local/lib/dyld/libplatform.a` `string_io.o` | 262,936 → **263,104 B**; `_simple_salloc` at +0x10a0 now opens `movq _mach_task_self_(%rip),%rax` / `cmpl $0x0` / `jne` → `callq ___kernelrpc_mach_vm_allocate_trap`, with `callq _vm_allocate` preserved verbatim on the taken branch |
| `Libraries/dyld/dyld/dyld` | `__simple_salloc` at **0xab780**; the gate occupies **0xab788-0xab7b3** and the original `callq _vm_allocate` is still at **0xab7cc** |
| control preserved | `assets/usr/lib/dyld.PRE-SALLOC-GATE` = the exact loader the 22:03 control ran, sha256 `624f8431…` |
| treatment | `assets/usr/lib/dyld.DYLD-BOOT-VERSION` sha256 `886a4674…`, `cmp`-identical to the built binary. **⚠️ It is NOT in `assets/usr/lib/dyld` at the time of writing** — the co-ordinated worker holds that path with their own loader for their boot 2 (§31.10), and restores mine by sha256 afterwards. Both are kept; neither is discarded. |

**The link resolves**: `__kernelrpc_mach_vm_allocate_trap` is a `T` in
`SDK/usr/local/lib/kernel/libkernel.a`, which is on the loader's `-L` path
(`dyld/makefile:127`), and it is also an export of `libsystem_kernel.dylib`. The
in-function `extern` produced the Mach-O name `___kernelrpc_...` (three
underscores) as it must.

### 31.1a ✅ POSITIVE CONTROL: the rebuild differs from the control by exactly the gate

Address-shift noise makes a raw `otool -tV` diff useless here — the 104 added
bytes move every RIP-relative literal, producing **10,414** changed lines that
are almost all the same instructions with new displacements. Normalising that
away leaves a diff small enough to read, and it is the attribution evidence
between the 22:03 control loader and this one:

| comparison | result |
|---|---|
| symbol names (`nm -n`, last field) | **identical except one addition**: `___kernelrpc_mach_vm_allocate_trap` |
| exports (`nm -gj`) | **identical except the same one addition** |
| mnemonic histogram, all addresses stripped | **+1 `callq`, +1 `cmpl`, +1 `jne`, +1 `jmp`** — and nothing removed |

Those four are the gate and nothing else: the test, the branch, the new call, and
the join. **So a signature change in this run is attributable to the gate**, and
if the signature does *not* move that is equally attributable — neither outcome is
confounded by an unrelated rebuild difference.

The one new symbol is worth naming rather than glossing, and getting the scope of
it right matters. Referencing `__kernelrpc_mach_vm_allocate_trap` from
`string_io.c` made that trap appear in the loader's **symbol table**, where it
was not before:

| surface | control | gated |
|---|---|---|
| `nm -gj` globals | 18 | **19** (`___kernelrpc_mach_vm_allocate_trap` added) |
| `LC_DYLD_EXPORTS_TRIE` datasize | 160 | **160** — unchanged |

So the loader's **public export surface is unchanged**; what grew is the set of
symbols the image defines, which is exactly what a new call reference should do.
It is a symbol `libkernel.a` has always defined — the gate changed which ones the
image happens to reach, not what the archive contains, and not what anything
downstream can import.

### 31.2 ⚠️ THE CYCLE, read as SOURCE. §29.7's premise is REFUTED

§29.7 and the handoff both rest on "`_mach_port_construct` is a **direct trap**,
not a MIG call". **That is half true and the half that is false is load-bearing.**
`assets/usr/lib/dyld` at 0xbe350:

```
_mach_port_construct:
  0xbe376  callq  __kernelrpc_mach_port_construct_trap     <-- IS a real trap
  0xbe37e  cmpl   $0x10000003, -0x24(%rbp)                 <-- MACH_SEND_INVALID_DEST
  0xbe385  jne    0xbe39e                                   <-- if not, RETURN
  0xbe396  callq  __kernelrpc_mach_port_construct          <-- the MIG fallback
```

`__kernelrpc_mach_port_construct` (0xbf390) is **not** a trap. It builds a MIG
request on the stack, calls `_mig_get_reply_port` at **0xbf439**, and then
`_mach_msg` at **0xbf496**. So the trap is tried, **fails with a sentinel, and
falls into MIG** — and MIG needs a reply port, which is obtained by constructing
a port. **The cycle closes on itself and allocates nothing.**

### 31.3 ✅ WHY the trap fails, from the kernel source — and it is one condition

`Kernel/xnu/libsyscall/mach/mach_port.c:657-673` is the whole of it:

```c
rv = _kernelrpc_mach_port_construct_trap(task, options, (uint64_t) context, name);
if (rv == MACH_SEND_INVALID_DEST)              /* 0x10000003, message.h:1337 */
        rv = _kernelrpc_mach_port_construct(task, options, (uint64_t) context, name);
```

and `osfmk/ipc/mach_kernelrpc.c:338-361` — the trap is **fully implemented**; the
sentinel is the *default*, and the sole way to keep it is to fail the one guard:

```c
int
_kernelrpc_mach_port_construct_trap(...)
{
        task_t task = port_name_to_current_task_noref(args->target);
        int rv = MACH_SEND_INVALID_DEST;             /* <-- default */
        if (!task) goto done;                        /* <-- the only early exit */
        mach_copyin(args->options, &options, sizeof(options));
        rv = mach_port_construct(task->itk_space, &options, args->context, &name);
        ...
}
```

The target it is given is `mach_task_self()`. `mach_init.c:66` initialises
`mach_task_self_` to `MACH_PORT_NULL` and the only assignment is `mach_init.c:135`
inside `mach_init_doit()`. **`Libraries/dyld/src/dyldInitialization.cpp` calls
`mach_init()` at line 128; the fixup walk is at line 123, i.e. it runs
BEFORE `mach_init()`, not after it.**
So during `rebaseDyld` the port name is 0, `port_name_to_current_task_noref(0)`
is NULL, and the trap hands back the sentinel by construction.

### 31.4 ✅ CAUSE AND EFFECT ARE BOTH ALREADY IN THE PANIC REGISTER DUMP

No further measurement is needed to establish the chain; the 22:03 control log
already contains it, once the frames are anchored (`DYLD-LOAD-BASE: 0x119a5b000`):

| register | value | what it is |
|---|---|---|
| `RDI` | **`0x0`** | the `task` argument of the deep `__kernelrpc_mach_port_construct` frame — i.e. `mach_task_self_`, loaded by `_mig_get_reply_port` from `_mach_task_self_(%rip)` and passed straight through `_mach_port_construct` |
| `RAX` | **`0x10000003`** | `MACH_SEND_INVALID_DEST` — the trap's return, still live in `EAX` from `_mach_port_construct+0x4b` (`movl -0x24(%rbp),%eax`) |

`RDI == 0` and `RAX == MACH_SEND_INVALID_DEST` are the two ends of §31.3's
chain, sitting in the same register file. **This is why the gate cannot work**:
it tests `mach_task_self_ == MACH_PORT_NULL` and routes around MIG when true —
but the *reason* MIG is entered is that the same NULL, and routing one call site
around it leaves 51 others, plus the recursion itself.

### 31.5 ✅ THE BRIEF'S PREDICTED-FAILURE-MODE QUESTION, ANSWERED BY COUNTING

"Is there a pre-`mach_init` allocation path that does not go through
`__simple_salloc`?" **Yes, and the gate covers 1 of 52.** Enumerated by scanning
the emitted loader for every call to a MIG-capable entry point:

| callee | call sites in the image | note |
|---|---|---|
| `_vm_allocate` | **52 sites in 51 functions** | the gate intercepts exactly **1** (`__simple_salloc`). The other **51 sites in 50 functions** are dyld's own — `OverflowSafeArray<…>::growTo` ×12, `ImageLoaderMachO::mapSegments`, … — and every one of them reaches the same trap with the same NULL port name |
| `__kernelrpc_mach_port_construct` | 1 | reached from `_mach_port_construct` — the recursion, needing **no allocation at all** |
| `__kernelrpc_mach_port_allocate` | 1 | `_mach_thread_self` |
| `_host_info` | 1 | `dyld::isHaswell()` — a MIG stub, no allocation |
| `_mach_port_deallocate` | 9 | `dyld::getHostInfo`, `dyld::isHaswell`, `ImageLoader::runInitializers` |
| `_mach_port_construct` | 2 | **`dyld::sendMessage()` (0x7f858)** and `_debug_control_port_for_pid` |
| `_vm_copy` | 2 | `ImageLoaderMachO::mapSegments` |

And the decisive one is not an allocation at all: **`mig_get_reply_port()` calls
`mach_port_construct()` itself** (`mig_reply_port.c:73`) to mint the very reply
port the MIG stub needs. It allocates nothing, calls no allocator, and recurses
forever. **No allocator gate can reach it.**

And it is not a quirk of libsyscall either. `dyld::sendMessage`
(`dyld2.cpp:801`) reaches the identical cycle from **dyld's own code**, with no
allocator anywhere in it — at 0x7f843 it loads `_mach_task_self_(%rip)` and calls
`_mach_port_construct` at 0x7f858, passing the same NULL:

```
000000000007f843  leaq  _mach_task_self_(%rip), %rax
000000000007f84a  movl  __framesize(%rax), %edi        ; == 0
000000000007f858  callq _mach_port_construct
```

**So every port operation in the loader recurses while `mach_task_self_` is
NULL** — dyld's own IPC, libsyscall's reply-port bootstrap, and the kernelrpc
trap fallback all fail for one reason, and that reason is not the allocator.

### 31.6 ⚠️ PREDICTION, WRITTEN BEFORE THE BOOT

`_simple_salloc`'s gated branch calls
`__kernelrpc_mach_vm_allocate_trap(mach_task_self(), …)` with
`mach_task_self_ == 0`. `osfmk/ipc/mach_kernelrpc.c:55-74` defaults that trap's
`rv` to `MACH_SEND_INVALID_DEST` and only proceeds `if (task)`. So the gated call
**also** returns the sentinel, `kr != 0`, and `_simple_salloc` returns **NULL**.

**What happens to that NULL is not uniform, and I checked all six callers in the
emitted code rather than assuming.** Four of the six test it; **two do not**:

| caller | first thing after the call | NULL safe? |
|---|---|---|
| `mkstringf` (`dyld2.cpp:455`) | `if (buf != NULL)` | **yes** — returns `"mkstringf, out of memory error"` |
| `throwf` (`dyld2.cpp:472`) | `if (buf != NULL)` | **yes** |
| `socket_syslogv` (0x72b4a) | `cmpq $0x0; jne; jmp` away | **yes** |
| `_abort_report_np` (0xa0bbf) | `cmpq $0x0; je` to the no-buffer path | **yes** |
| **`Diagnostics::error(char const*, __va_list_tag*)` (0x2c09c)** | `callq __simple_vsprintf` **unconditionally** | **NO** |
| **`_sprintf` (0xa0c8f)** | `callq __simple_vsprintf` **unconditionally** | **NO** |

**This corrects my own first draft of this section**, which predicted a
NULL-dereference without checking: for four of the six call sites a NULL is a
handled, ordinary out-of-memory condition and dyld carries on. The dereference
is specific to the two callers that skip the test.

So there are **three** distinguishable outcomes, not one, and the log tells them
apart:

| outcome | what it means |
|---|---|
| **A** — NULL deref in `__simple_vsprintf` | `_simple_salloc` WAS the entry, and a diagnostic fired. The gate worked as designed and exposed the real precondition. |
| **B** — dyld gets *further*, new fault elsewhere | `_simple_salloc` was the entry but no diagnostic fires pre-`mach_init`, so removing the MIG call simply lets the fixup walk proceed. **The best outcome** — it means the cycle really was only the bootstrap allocator's routing after all, and §31.3's chain is right for a reason other than the one given. |
| **C** — the 3-frame cycle, unchanged | the entry is one of the other 50 `_vm_allocate` sites, or a MIG stub with no allocation in it at all. The gate is a no-op and §31.3 is right that no allocator gate can work. |

**C is the outcome the evidence favours** and **A is the one that would refute
§31.3**, because A requires the cycle to have been reachable *only* through
`__simple_salloc`. Recording all three before the run is the point.

**The discriminator, computed now so the comparison is not made up afterwards.**
All four functions of the cycle sit at the same offset in both loaders, shifted
by exactly **+48 bytes**:

| function | control | gated |
|---|---|---|
| `__kernelrpc_mach_port_construct_trap` | 0xbdda4 | 0xbddd4 |
| `_mig_get_reply_port` | 0xbdfb0 | 0xbdfe0 |
| `_mach_port_construct` | 0xbe350 | 0xbe380 |
| `__kernelrpc_mach_port_construct` | 0xbf390 | 0xbf3c0 |

So **outcome C is recognisable without any judgement**: the same four names, the
same in-function offsets (`+0xb`, `+0x4b`, `+0x51`, `+0xae`), and the same
register values `RDI=0` / `RAX=0x10000003`, with every raw address exactly +48
from the control. Anything else is A or B.

### 31.7 The fix site the evidence actually points at

One condition, not one call site: **`mach_task_self_` must be non-NULL before any
MIG call**, and dyld already owns the ordering decision that violates it —
`dyldInitialization.cpp:123` uses MIG, `:128` is what makes MIG safe.

**And the obvious fix is safe, which I checked rather than assumed.** The
tempting worry about "just move `mach_init()` earlier" is that it might itself
need MIG or memory, which would only relocate the fault. It does neither.
`mach_init()` → `mach_init_doit()` in the emitted loader is 58 instructions and
its **entire transitive call tree** is:

```
_mach_init_doit        -> _task_self_trap            (5 insns, ZERO calls: movq/movl/syscall/retq)
                       -> _mach_reply_port           (5 insns, ZERO calls: movq/movl/syscall/retq)
                       -> __init_cpu_capabilities    -> __get_cpu_capabilities
                       -> __pthread_set_self         -> __pthread_set_self_dyld
                                                          -> ___thread_selfid, __thread_set_tsd_base
```

**No MIG stub anywhere in it** — and that is checkable against the other list in
this document: none of those leaves is among the 16 functions that call
`_mig_get_reply_port`. The body is two `syscall` traps, two comm-page reads, and
the CPUID/TSD primitives. It sets `_mach_task_self_` at **0xbd459**, the exact
variable whose NULL value is the whole fault.

Three of those leaves are not local labels, which was the gap in the argument, so
they were disassembled too (`llvm-objdump`, which emits local symbols that
`otool -tV` drops) — and they close it:

| leaf | body | MIG? |
|---|---|---|
| `__get_cpu_capabilities` @0xbd414 | `movabsq $0x7fffffe00010,%rax; movq (%rax),%rax; retq` — a comm-page read | no |
| `___thread_selfid` @0xc0e7c | `movl $0x2000174,%eax; syscall` — a **direct trap** | no |
| `__thread_set_tsd_base` @0xc111c | `movl $0x3000003,%eax; syscall` — a **direct trap** | no |
| `__pthread_set_self_dyld` @0xa6700 | calls only the two traps above | no |
| `_cerror_nocancel` | **zero calls** — a pure TSD/errno write | no |
| `__pthread_exit_if_canceled` | `___pthread_canceled`, `_abort_with_reason`, `_pthread_exit` | no |

**So `mach_init()`'s entire transitive call tree in this loader is comm-page
reads, direct `syscall` traps, and TSD/errno writes. No MIG stub is reachable
from it — there is no gap left to argue about.**

So the change is a **one-line move** — `mach_init()` from `:128` to above `:123`
— with no new mechanism, no new symbol, and the same shape as `0ad4aa2ef5` (the
`%gs` fix), which was also a correct mechanism in the wrong place. With
`mach_task_self_` non-NULL, `port_name_to_current_task_noref` resolves, both
`mach_port_construct_trap` and `mach_vm_allocate_trap` stop returning the
sentinel, no MIG is entered during the fixup walk, and **the cycle cannot form**.

**⚠️ NOT APPLIED AND NOT TESTED — this is a design plus a measurement, not a
result.** Deliberately: it is a change to a file the coordinator has edited
twice today on a workstream they own, §29.9 established that scope questions
here are the coordinator's to answer rather than to be guessed at, and — the
decisive reason — **the image window is held by another worker for the rest of
this round, so it could not be booted.** Landing an untested source change and
calling it progress is precisely the failure this document exists to prevent.
It is written so that applying it is one `mv` of one line.

### 31.8 ⚠️ TWO NEGATIVE FINDINGS, and the first one undercuts §29.7's premise

**The entry frame into the cycle has NEVER been observed in a boot log.** Every
anchored run on disk stops at exactly **51 frames**, all of them the 3-frame
cycle repeated 17 times, and every one ends with the kernel's `Backtrace
continues...`:

| log | base | frames | distinct frames |
|---|---|---|---|
| `GS-FIX.2034` | `0x116b8538b` | 51 | 3 |
| `BASE.2119` | `0x1145d739b` | 51 | 3 |
| `ANCHOR.2149` | `0x119a5b000` | 51 | 3 |
| `PRE-SIGREASON-FIX` (control) | `0x119a5b000` | 51 | 3 |

The recursion is ~17 deep when the stack gives out, so the frame that first
called `_mig_get_reply_port` sits at 52+ and the stackshot never reaches it.
**§29.7's "`__simple_salloc` is the entry" is therefore an INFERENCE** — carried
over from the shallower `%gs` crash, where the trace did fit — and not an
observation from any of these logs. §27's sixteen-frame chain is not reproduced
in any file in `work/`. That does not make the gate useless; it makes the gate's
precondition **untested**, which is exactly the outcome §31.6 predicts.

**"The slide is different every boot" is wrong as stated, and it matters.** The
base is **identical** (`0x119a5b000`) across the 21:49 and 22:03 runs. The five
distinct slides in the handoff are five *kernels*, not five boots: 20:34 and
21:19 differ because `kernel_build.py` relinked in between. The anchor is
stable within a kernel and moves across kernels. And it is checkable rather than
assumed: **the two most recent runs are byte-identical in base, registers, RIP
and frame list**, so this fault is **deterministic, not intermittent** — which is
one more reason a single boot is a legitimate measurement here.

### 31.9 ✅ The chain is closed in FIVE in-tree files, and the loader is built from them

`.PATH: ${XNU}/libsyscall/mach` (`libsystem_kernel/Makefile:11`) with
`XNU = ${ROOT_SOURCE_DIR}/Kernel/xnu` (`:4`), and `mig_reply_port.c` at `:242` — so
the loader's `_mig_get_reply_port` — 0xbdfb0 in the control loader, 0xbdfe0 in
the gated one, per the discriminator table in §31.6 — **is** the file below, not
a lookalike:

```
  mig_reply_port.c:73          kr = mach_port_construct(mach_task_self(), &opts, NULL, &port);
  mach_port.c:668-669          if (rv == MACH_SEND_INVALID_DEST)
                                   rv = _kernelrpc_mach_port_construct(...);   /* MIG */
  mach_kernelrpc.c:341-348     task_t task = port_name_to_current_task_noref(args->target);
                               int rv = MACH_SEND_INVALID_DEST;  if (!task) goto done;
  mach_init.c:66,135           mach_task_self_ = MACH_PORT_NULL until mach_init_doit()
  dyldInitialization.cpp:123,128     the fixup walk is at :123, mach_init() is at :128
```

All five are in this tree and all five were read. **Nothing on that list is
inferred**, and the two ends of it are sitting in the panic register dump
(§31.4).

### 31.9b ⚠️ A CONFOUND I CANNOT ELIMINATE, stated before the run

My run and the 22:03 control will **not** differ only by the loader. Between
them the other worker relinked the kernel: `work/stripped_kernel.development`
was rewritten at 22:18 by `kernel_build.py` from their `kern_sig.c` change, and
the 22:03 control's kernel payload no longer exists on disk to be hashed. **The
control's kernel sha256 is therefore unrecoverable**, and I am not going to
pretend otherwise or compare against the `52a0b37d…` recorded in §26, which is
from a different run entirely.

`run_gated_loader.sh` now pins the kernel path and prints its sha256 before
`mkimage` runs, so my run's kernel is on the record. The judgement I am entitled
to afterwards is bounded by that:

* If the signature **moves**, the loader change is the only thing in this run
  that was built to move it. **The disjointness is not an assertion — it is the
  diff.** Their kernel change is 29 lines in `build_signal_reason()`,
  `bsd/kern/kern_sig.c`, switching `os_reason_alloc_buffer_noblock` to
  `os_reason_alloc_buffer` so the crash-reporting zone allocation blocks instead
  of refusing. That is `kalloc`/zone policy on the signal-reason path. The fault
  under test is `port_name_to_current_task_noref` returning NULL in
  `osfmk/ipc/mach_kernelrpc.c`. Different subsystem, different lock, different
  data structure, and nothing in either diff touches the other. That is as
  strong as a one-boot result can be here, and it is still one boot.

  **One visible consequence to expect and not be surprised by:** their change
  should make `build_signal_reason: unable to allocate signal reason buffer.`
  **disappear** from my log. §30.5 recorded that line as present on every
  userspace crash here and as a property of the crash-reporting path, not of
  the fault. Its absence is therefore further evidence their kernel took effect,
  and it is **not** part of the fault signature either way.
* If the signature does **not** move, the kernel difference is a live confound
  and I say so rather than claiming the gate is exonerated. What survives the
  confound is not the gate's verdict but the *static* finding, which does not
  depend on any boot: the cycle contains no allocation, and `mach_task_self_` is
  0 in the register file.

`run_gated_loader.sh`'s central safety property was **tested, not assumed**:
invoked with a live QEMU running it printed `FATAL: a QEMU is running and holds
the image`, exited 1, created no image, and left `assets/usr/lib/dyld` at the
other worker's sha. A guard that has never been seen to fire is not a guard.

**Two boots, not one, is what would settle it** — the same image booted with the
control loader and with the gated loader — and that is a clean design the moment
anyone has two free windows.

### 31.10 ✅ The two crash signatures cannot be silently each other's

The `build_signal_reason` worker runs two boots against the same image and the
same `assets/` tree, with a `kernel_build.py` relink between them. Two workers
chasing one crash on one image is exactly the situation this project has
contaminated measurements in before, so the arrangement was made explicit rather
than trusted:

* They boot `--window 600` and hold the image window; I did not run `mkimage`,
  `boot.py`, or `stage_dynamic_libs.sh` while their QEMU held `boot_dynamic.img`,
  and I confirmed the image and the QEMU log were untouched before and after.
* I rebuilt `libsystem_platform` **into the SDK**, which is a real hazard here:
  `run_dynamic_gate.sh` calls `stage_dynamic_libs.sh` **unconditionally**, before
  its `if [ $BUILD -eq 1 ]` block, so the gate re-stages `assets/usr/lib/*` from
  the SDK on every invocation **including `--no-build`**. They identified this
  themselves and are running `mkimage.py` + `boot.py` directly for their boot 2.
* `mkimage.py` reads **only** from `assets/` — verified in the source, not
  assumed — so my SDK rebuild has no other path into their image.
* `assets/usr/lib/system/libsystem_platform.dylib` is 88,456 B,
  sha `62d73aac…`, dated Sep 26 14:08. It predates both of us, is **not** the
  86,712 B build I put in the SDK, and contains no gate. Their image's
  libsystem_platform cannot contain my change.
* The one file that genuinely crossed was `assets/usr/lib/dyld`, which I had
  already replaced before they told me their schedule. They preserve mine as
  `dyld.DYLD-BOOT-VERSION`, restore the control as `assets/usr/lib/dyld` for
  their boot 2, and put mine back afterwards **verifying sha256 rather than
  trusting a filename**. `dyld.PRE-SALLOC-GATE` is a second, independent copy of
  the control, so the control is recoverable even if one of us is wrong.

**Loaders on disk, all retained, none overwritten** (inventory corrected
22:32 by the peer, who caught a stale line in my own text — `dyld.DYLD-BOOT-VERSION`
was THEIR temporary copy, made to hold my gated build while they restored the
pre-gate one for their boot 2, and they deleted it afterwards as agreed):

| file | bytes | sha256 | what |
|---|---|---|---|
| `dyld` | 1,733,184 | `886a4674…` | **ours, gated — ACTIVE** |
| `dyld.PRE-SALLOC-GATE` | 1,733,080 | `624f8431…` | ours, pre-gate (their boot 1 + the 22:03 control) |
| `dyld.PREV-SALLOCGATE` | 1,733,080 | `624f8431…` | same control, saved by my run script at 22:31 |
| `dyld.orig` | 2,524,592 | — | Apple |

A revert test still costs one `cp` in either direction.

---

## 32. ✅ `build_signal_reason` FIXED — it was Z_NOWAIT, not a shortage, and NOT the `random_init` flake

Owner: the crash-reporting path (`bsd/kern/kern_sig.c` `build_signal_reason`), not
the dyld fault. Committed `254ac5f40f`. This is a **kernel** finding and is
**load-bearing for the next crash report**, which is why it is worth landing
before the loader work moves on.

### 32.1 ⛔ The `random_init` connection is REFUTED, not merely unmeasured

§26.3 said the two symptoms were "almost certainly the same" cdev trouble. That
was a guess carried as a note. It is now **false**, and it is false twice over:

**By co-occurrence, in both directions.** In the very log that produced the
message (`work/serial_dynamic.log`), `early_random_init: done!` (line 301),
`bsd_autoconf: calling kminit` (561) and `setconf: using AHCI rootdev disk0s1
(major 1, minor 1)` **all succeeded**. The flake did not happen in the run that
produced the failure. Conversely boot 1 below hit the flake — `pfinit`, `ptmx_init`
and `random_init` all failing the same way — and produced **no** signal-reason
failure at all, because it never reached userspace.

**By mechanism, which is the stronger half.** The flake is **not a memory
problem**. `cdevsw_add` (ravynOS's own `bsd/kern/bsd_stubs.c`, not upstream)
calls `cdevsw_isfree(index)`, and for a **fixed** major like `RANDOM_MAJOR` it
simply tests whether that table slot is still all-zero. It returns -1 when
some earlier init already occupied the slot. A fixed-major collision in a
static table has no memory pressure in it whatsoever. Two faults, merged
into one story because the merge was plausible.

### 32.2 Which allocation, and which layer — the message does not say

`ret != 0` covers **EINVAL, ENOMEM and EIO**, so the string alone cannot
identify the layer. EINVAL is excluded **by arithmetic, with no boot**:

| quantity | value | source |
|---|---|---|
| `sizeof(struct kcdata_item)` | 24 | `osfmk/kern/kcdata.h:256` |
| payload (`p_name` 16 + `pid_t` 4) | 20 | `param.h:95` MAXCOMLEN=16 |
| padding `2*(16-1)` | 30 | `kcdata.h:254` KCDATA_ALIGNMENT_SIZE |
| begin+end markers `2*24` | 48 | |
| **request** | **146** | |
| `OS_REASON_BUFFER_MAX_SIZE` | 5120 | `bsd/sys/reason.h:162` |

146 ≤ 5120, so EINVAL is out. Reproduced by a standalone program built from
the tree's own constants, not by reading the arithmetic once.

Also settled by reading: `os_reason_create()` **succeeded** every time — the
"signal reason structure" message appears **0** times in every log. The zone
machinery was alive and allocating. Only the second allocation failed.

### 32.3 The layer is `zalloc_item`, and it is `Z_NOWAIT`-specific

```c
if (zone->z_elems_free <= zone->z_elems_rsv / 2) {
        if ((flags & Z_NOWAIT) || zone->z_elems_free) zone_expand_async_schedule_if_allowed(zone);
        else                                            zone_expand_locked(zone, flags);
        if (__improbable(zone->z_elems_free == 0)) { zs->zs_alloc_fail++; return {}; }  /* refuse */
}
```

A `Z_NOWAIT` caller may only **schedule** an expand, never perform one. The
refusal condition is `z_elems_free == 0` and is **independent of
`z_elems_rsv`** — which kills the obvious "just raise the zone reserve" fix
*by reading*, before anyone spends a boot on it.

### 32.4 Measured, boot 1 — temporary `ZPROBE` in `zalloc.c`, since reverted

With the zone lock **still held**, the probe did the exact expand a blocking
caller would do. Same zone, same instant, same size; blocking was the only
variable.

```
ZPROBE: heap=data.   zone=kalloc.4096 idx=51  esize=4096 nowait=1 free=0->1 avail=0 rsv=0
        va=0 wired=0/1->4294967295 exhausted=0 no_callout=0 async=1 VERDICT=EMPTY-BUT-EXPANDABLE
ZPROBE: heap=shared. zone=kalloc.576  idx=309 esize=576  nowait=1 free=0->7 ...
        exhausted=0 VERDICT=EMPTY-BUT-EXPANDABLE
```

`z_wired_max = UINT32_MAX` and `zone_exhausted()=0`, so **not** VA-exhausted;
a blocking retry immediately produced elements. The instrument was confirmed
linked (`strings | grep -c ZPROBE` = 1) **before** the boot was spent, and the
string is its own positive control: it fired on real refusals.

⚠️ **The limit of this evidence, stated plainly.** Boot 1 hit the `random_init`
flake and never reached userspace, so these are the **mechanism class**, not
the 146-byte `kalloc.192` target being observed directly. `kalloc.h`'s index
table puts 146 at idx 6 → 192, but a table is documentation; the runtime print
is what settles a zone's identity, and it never got the chance. Nobody should
read §32.4 as "we watched the signal-reason allocation fail".

### 32.5 The fix, and why blocking is the honest one

`os_reason_alloc_buffer_noblock` → `os_reason_alloc_buffer` (Z_WAITOK). No larger
buffer, no fallback, no skipped description.

Blocking is correct **for this caller**, on evidence:
- thread context, not interrupt context (`zalloc_ext` asserts that case
  separately, and did not fire);
- `proc_lock`, held at two of three call sites, is a **sleepable** `lck_mtx`
  (`kern_fork.c`: `lck_mtx_lock(&p->p_mlock)`);
- **the decisive one** — this function *already blocks on a zone allocation two
  lines above*, because `os_reason_create()` does `zalloc_flags(..., Z_WAITOK)`.
  A "must not block here" rationale cannot justify the `noblock` call, because
  the function blocks unconditionally before reaching it.

**A design question this does raise, flagged rather than hidden:** the
blocking/nonblocking split in this file *does* track the lock context —
`build_userspace_exit_reason()` (kern_sig.c:1496) uses the blocking variant and
is called from `abort_with_payload_internal` (kern_exit.c:1390) with **no**
`proc_lock` held. So the `noblock` at this site was not arbitrary. The answer
here is that the function blocks regardless, which makes the distinction
meaningless *at this call site* — but anyone changing the `os_reason_create`
allocation to `noblock` would remove that answer, and should not.

### 32.6 Verification

Image rebuilt once and alone; `mkimage`: `verify OK: 61 files, 75 tree
entries, all content hashes match`. Fresh `vars.fd` (`boot.py:63` re-copies it
unconditionally every run). The `dyld` in the image was **uncrossed** against
the concurrent worker's build and checked by sha256 both ways, so the image
varies by this kernel change and nothing else.

| observation | pre-fix | post-fix |
|---|---|---|
| `unable to allocate signal reason buffer` | **1** | **0** |
| `signal reason structure` | 0 | 0 |
| kcdata `invalid exit reason buffer` | 0 | **0** ← positive control |
| kcdata `type mismatch` | 0 | **0** ← positive control |

Same fault both runs: namespace 2 subcode 0xb, gate banner and `DYLD-LOAD-BASE`
present.

**Why the kcdata rows are the control and `description none` is not.** A NULL
buffer short-circuits `exit_reason_get_string_desc()` *before* any validation
print, so `description none` is emitted identically whether the buffer was
never allocated or is populated without a user string — it discriminates
nothing. The two kcdata rows discriminate: post-fix, `exit_reason_get_string_desc`
got past the NULL check, past `kcdata_iter_valid()`, and past the
`KCDATA_BUFFER_BEGIN_OS_REASON` type check, which it could not have done had the
allocation still been failing. **The allocation now succeeds and the kcdata is
structurally valid.**

### 32.7 A build-system defect found on the way, worth its own line

`kern_sig.o` was **absent from `kernel_build.py`'s recompile allowlist**. Editing
`kern_sig.c` would therefore have produced a green build, a successful relink, and
an **unchanged kernel**. That is precisely the "a green build changed nothing"
failure `verify_provenance.py` exists to catch, and it would have made this whole
investigation look like it had failed. Added to the allowlist.

---

## 32. ✅✅ THE GATE RESOLVED IT — the recursion is GONE, and what replaces it is a SILENT STOP

Booted 2026-09-27 22:32:30, `run_gated_loader.sh SALLOCGATE`, image built once and
alone, `verify OK: 61 files, 75 tree entries, all content hashes match`, and the
loader **byte-verified inside the image** before the boot:

| arm | result |
|---|---|
| gated loader's first 4 KB in the image | offset **44,963,840** — PRESENT |
| control loader's first 4 KB in the image | offset **−1** — absent |

Both arms, because a one-armed check cannot say no. Kernel pinned and recorded:
`work/stripped_kernel.development`, sha256 `4f20e581…`, 20,043,504 B — the
peer's 22:18 relink, **not** the control's kernel (§31.9b's confound, real).

### 32.1 THE SIGNATURE, verbatim

```
DYLD-LOAD-BASE: 0x10e560000

vm_map_get_range: range_id=5 size=28672 ...
vm_map_get_range: range_id=5 size=32768 ...
vm_map_get_range: range_id=5 size=24576 ...
vm_map_get_range: range_id=5 size=32768 ...
vm_map_get_range: range_id=5 size=16384 ...
vm_map_get_range: range_id=5 size=16384 ...
```
**620 lines. `boot.py` reports `alive-tick lines: 0   panic/trap lines: 0`. The
log ends there and stays silent for the remaining ~285 s of budget.**

### 32.2 The comparison that carries the result

| | control 22:03 | **gated 22:32** |
|---|---|---|
| panic / `Thread 0 crashed` / `Debugger called` / backtrace lines | **5** | **0** |
| non-empty lines after `DYLD-LOAD-BASE` | 93 | **6** |
| `build_signal_reason: unable to allocate…` | present | **0** |
| outcome | stack-exhaustion panic in the 3-frame cycle | **no crash at all** |

**The 3-frame `mig_get_reply_port` → `_mach_port_construct` →
`__kernelrpc_mach_port_construct` recursion is not in this log at all.** Not at a
different address, not at a different depth — absent. `boot.py` counted zero
panic and zero trap lines, and there is no `RAVYN-DYNAMIC-USERLAND-OK`, so this
is **not** a pass either.

### 32.3 ✅ The gate did what §31.3 said it could not

§31.3 established that the recursion needs `mach_task_self_ == 0` and no
allocation, and concluded "no allocator gate can reach it". **The recursion is
gone, so that conclusion was wrong, and it is worth being precise about how.**

It was wrong in its *reach*, not its *mechanism*. `__simple_salloc` was the entry
after all — which §31.8 had already flagged as an INFERENCE no log had ever
shown. With the gate, `_simple_salloc` calls the trap, the trap returns
`MACH_SEND_INVALID_DEST` (because `mach_task_self_` is still 0), and
`_simple_salloc` returns **NULL without ever entering MIG**. The cycle is never
started, so it never needs to be escaped. **A gate that prevents the recursion
from starting does not have to reach the recursion.** My §31.5 claim that it
covers "1 of 52" sites was a true count and a wrong inference about consequence.

Which caller got the NULL is not in the log — the frontier is now a silent stop,
not a fault, so there is no RIP to read. `Diagnostics::error` and `_sprintf` are
the two that would have dereferenced it (§31.6), and the silence is consistent
with either a handled NULL or a spin.

### 32.4 The new frontier, stated as what it is

**Not a crash. A silent stop** after 6 kernel map calls, in the same
`28672/32768/24576/32768/16384/16384` sequence the control also passed through —
one step short of where the control died. That is the same neighbourhood as
§10a's `check_np`-returns-ENOMEM hang and is **not yet localised**: no RIP, no
backtrace, no QEMU register state for a userspace fault, because there is no
fault. Next instrument is the QEMU `CPL=3` scan that discriminated the §10c hang,
not another backtrace.

### 32.5 ⚠️ What this run does NOT establish

* **One boot.** Deterministic on the control (§31.8), but a single gated run.
* **The kernel differs** from the control (`4f20e581…`, §31.9b), and my run
  varies **two** things at once — loader and kernel — so it cannot attribute
  anything to either change.
* ⚠️ **The `build_signal_reason` 1 → 0 count is a PROVENANCE witness and NOT a
  verification of their fix.** Correction recorded at their insistence and it is
  right: the string's absence witnesses that the kernel in my image is theirs,
  which is the check that the two of us are not looking at different machines.
  It is **not** independent confirmation of their change, and **not** evidence
  about the 146-byte `kalloc.192` zone they never observed directly.
  **Their before/after is the stronger evidence and mine must not be cited
  alongside it**: theirs holds the loader fixed (sha `624f8431…`, uncrossed both
  ways) and varies only the kernel, and it reproduces the *same* fault — same
  namespace, subcode `0xb`, same `DYLD-LOAD-BASE` gate — on both sides. Mine has
  no matched before. And on the far side of their change from anything it
  touches, my outcome is a poor control surface: a signal that would have fired
  under either kernel discriminates weakly.
* **The settling experiment is still unrun:** the same kernel, two images, the
  pre-gate loader and the gated one, differenced. It is one command away —
  `run_gated_loader.sh assets/usr/lib/dyld.PRE-SALLOC-GATE <tag>` — and it is
  what turns "the signature vanished" into "the gate made it vanish".

### 32.6 ⚠️ A regression I introduced and caught, recorded because it nearly was not

My `symbolize_anchored.py` rewrite (33566368f6) added byte-level decoding and
**broke segment parsing**: `image extent` computed to `0x0`, so the tool refused
to name *every* address, including the four it had named correctly a minute
earlier. A stricter tool that refuses everything is not stricter — it is broken,
and it fails in the direction that looks careful. Caught only because I ran the
new version against a log whose answer I already had. Reverted in 895299e2fd; the
byte-decoding feature is not attempted again without a two-arm test first.

**Nothing symbolized in §32.1–32.3** — there is no faulting address to symbolize,
and the one place a symbol was needed (the control's cycle) was symbolized from
the anchored base in §31.2 with the loader's own `DYLD-LOAD-BASE` print.

### 32.7 ✅ The settling experiment is unrun, and its prediction is recorded

The peer has no window left (both of theirs spent, 22:04 and 22:20, done 22:31).
The experiment that turns "the signature vanished" into "the gate made it vanish"
is one command, and the prediction is specific enough to be falsifiable:

```
./run_gated_loader.sh assets/usr/lib/dyld.PRE-SALLOC-GATE PREGATE 300
```

| arm | expected, if the gate is what removed the recursion |
|---|---|
| pre-gate loader, **their** kernel | the `mig_get_reply_port` stack-exhaustion panic **returns** |
| `build_signal_reason` | stays **0** — the kernel fixes that string and the loader does not touch it |

**If the panic returns and the string stays 0, both workers have a clean 2×2.**
If the string returns too, something is wrong with the reasoning above and that
is worth hearing immediately. This is UNRUN — recorded, not claimed.

---

### Index note — there are two §32 in this file

`§32 (build_signal_reason FIXED — Z_NOWAIT, not a shortage, and NOT the
random_init flake)` and `§32 (THE GATE RESOLVED IT — the recursion is GONE)`
were appended within minutes of each other by two workers and both took 32.
Neither number has been changed, because each is now cited by the other
(`§32.7` is cited from the loader work, and the loader work is cited from
here) and renumbering either would break a live cross-reference.

To cite unambiguously, use the leading words:

- `§32 build_signal_reason` — the kernel crash-reporting path. Owner: the
  `bsd/kern/kern_sig.c` crash-reason buffer. Commit `254ac5f40f`.
- `§32 THE GATE RESOLVED IT` — the dyld loader recursion. Owner:
  `_simple_salloc` / mach IPC.

---

## 33. ✅ THE SILENT STOP IS NAMED — it is a fault, in the GATE, on the gate's own data read

The serial log cannot see this by construction: no panic, no backtrace, no
`build_signal_reason`. The QEMU dump is the instrument, and it holds **38
`CPL=3` records out of 5,829,179** — a fingerprint of exactly the kind §10c
predicted, one contiguous burst at lines 679,611–684,071, after which the CPU
never returns to ring 3. **38 records, not 5.8 million.**

⚠️ A first pass with a stricter pattern returned **0** and I nearly recorded
"userspace never ran" — which the serial log's `DYLD-LOAD-BASE` print
contradicts outright. The pattern, not the machine, was wrong.

### 33.1 Symbolized from the anchored base `0x10e560000` (R8 in every record)

| RIP | offset | symbol |
|---|---|---|
| `0x10e5faa30` | 0x9aa30 | `dyldbootstrap::start` |
| `0x10e600a30/34` | 0xa0a30/4 | `_dyld_setup_minimal_tsd` (+0x0, +0x4) |
| `0x10e5a3f50` | 0x43f50 | `MachOFile::hasLoadCommand` |
| `0x10e5a40d0/f8` | 0x440d0/8 | `MachOFile::forEachLoadCommand` |
| `0x10e5a6220` | 0x46220 | `MachOFile::hasChainedFixups` |
| `0x10e5a6b41/6b/be4` | 0x46b41/6b/e4 | `MachOLoaded::getLinkEditLoadCommands` block_invoke +0x4a1/+0x4cb/+0x544 |
| `0x10e59e560/60d` | 0x3e560/60d | `MachOAnalyzer::withChainStarts` (+0x0, +0xad) |
| `0x10e5a8390` | 0x48390 | `MachOLoaded::getLinkEditContent` |
| `0x10e5a9480` | 0x49480 | `MachOLoaded::fixupAllChainedFixups` |
| `0x10e5a98a6/9970` | 0x498a6/9970 | `fixupAllChainedFixups` block_invoke +0x196/+0x260 |
| `0x10e5a9aef` | 0x49aef | `MachOLoaded::walkChain+0xaf` |
| `0x10e5a4fff` | 0x44fff | `MachOFile::forEachSegment` block_invoke +0x11f |
| `0x10e58c0f0` | 0x2c0f0 | `Diagnostics::noError` |
| `0x10e60b6e0` | 0xab6e0 | `__simple_dprintf` |
| `0x10e60a6e0` | 0xaa6e0 | `__simple_vdprintf` |
| `0x10e60a79f` | 0xaa79f | `___simple_bprintf+0x1f` |
| `0x10e60bfe9` | 0xabfe9 | `_hex+0x79` |
| `0x10e621104` | 0xc1104 | `_write` |
| **`0x10e60b78f`** | **0xab78f** | **`__simple_salloc+0xf`** |
| **`0x8010000000000001`** | — | **NOT IN THE LOADER — a kernel-range address, at CPL=3** |

**This is the whole fixup walk, reading as source.** `start` → minimal TSD →
`hasChainedFixups` / `forEachLoadCommand` → `getLinkEditLoadCommands` →
`withChainStarts` → `fixupAllChainedFixups` → `walkChain` → `forEachSegment` →
`Diagnostics::noError`. The loader got **further than it has ever got** — through
the entire fixup walk, with no recursion — and then died at the gate.

### 33.2 The two faults, verbatim

```
 31087: v=0e e=0004 i=0 cpl=3 IP=002b:000000010e60b78f pc=000000010e60b78f
        SP=0023:00007ff7bb93c770 CR2=000000010e66feb4
RAX=000000010e66feb4 ... R8=000000010e560000  GS =0000 000000010e66dae0

 31088: v=0d ... cpl=3 IP=002b:8010000000000001 pc=8010000000000001
        SP=0023:00007ff7bb93c768 env->regs[R_EAX]=000000010e66feb4
CCS=0000000000000020 CCD=00007ff7bb93c770 CCO=SUBQ
```

A **#PF** at `__simple_salloc+0xf` on address `0x10e66feb4`, then a **#GP** with
`RIP = 0x8010000000000001` and `CCO = SUBQ` — a `SUBQ` executing at a
**kernel-range address in ring 3**. `GS = 0x10e66dae0`, so the minimal TSD block
is installed and `%gs` is sound.

**`CR2 = 0x10e66feb4` is exactly `_mach_task_self_`.** `nm` puts it at vmaddr
`0x10feb4`; `0x10e66feb4 − 0x10e560000 = 0x10feb4`. The faulting address is the
gate's own predicate variable, to the byte.

And that variable sits **220 KB into `__DATA`'s zero-fill**: `__DATA` is
`vmaddr 0xda000, vmsize 0x37000` but only **`filesize 8192`** — so
`_mach_task_self_` at `0x35eb4` into the segment is far past the last file-backed
byte.

### 33.3 ⚠️ THE CONTRADICTION I CANNOT EXPLAIN, stated rather than smoothed

The instruction at `0xab78f` is, in the byte-verified image:

```
00000000000ab788  leaq  _mach_task_self_(%rip), %rax
00000000000ab78f  cmpl  $0x0, __framesize(%rax)
```

That is a **read**, and it computes `RAX + displacement`. But the recorded error
code `e=0004` is a **write**, and `CR2` equals `RAX` **exactly**, which requires
the displacement to be zero. Those cannot both be true of this instruction.

**Three candidate explanations, none established:**
1. the displacement really is 0 and `otool`'s `__framesize(%rax)` rendering is
   of a zero-extended form I am misreading;
2. the running image is not the image I byte-verified (the control says it is —
   first 4 KB at 44,963,840, control at −1 — but that is the **head**, and a
   divergent `__DATA` is exactly what a head-only check cannot see);
3. the CPU decoded a different access than the one I am attributing.

**Explanation 2 is the one that would matter, and the head-only control cannot
exclude it.** The fix is to compare the *whole* loader, not its first 4 KB, and
the run script's control should hash the entire staged file into the image rather
than match a prefix. **Not done this round — the run is over and this is the next
thing to fix.**

### 33.4 What this does and does not say about the gate

**Keep the gate.** It is four instructions, byte-verified, and the recursion it
was built to stop is gone: the fixup walk now runs to completion and the failure
has moved *inside* the gate rather than into a cycle. That is progress.

But §31.7's `mach_init()` move is now **more** attractive, not less, and for a
second reason: `mach_init_doit` **writes** `_mach_task_self_`. If that page is
genuinely not present, the move faults too. **So the predicate variable's
accessibility is the open question, and it gates both fixes** — the gate and the
`mach_init()` move. That is the single most important thing this round
established, and it is a question about a page, not about dyld.

---

### 32.8 A VACUOUS COMPARISON REPORTED AS AGREEMENT — and the count control that caught it

Not a kernel result. A measurement-method result, kept here because the
`e3b0c44...` signature is the most recognisable one in the record and because
the failure it describes is the one this project has been punished by
repeatedly.

While checking whether the two divergent objects `kern_exit.o` and
`kern_fork.o` (12.5a backlog) undermined the reasoning in §32, the first
attempt at comparing the build-tree object against a fresh compile of the
committed source produced:

    buildtree : e3b0c44298fc1c149afbf4c8996fb924
    committed : e3b0c44298fc1c149afbf4c8996fb924

Identical. Which would have been reported as **"the two objects agree, the
divergence does not touch the code I relied on"** — a clean, reassuring,
completely false result.

`e3b0c442...` is the SHA-256 of the **empty string**. The extraction regex was
`^[0-9a-f]{16} ` with a literal space, and `otool -tV` emits a **TAB** after
the address. The probe matched nothing, hashed nothing, and two empty inputs
hash identically by definition. **A vacuous match reported as agreement is
exactly the failure this project keeps punishing**, and it is worse than a
broken probe that crashes, because it returns the answer you wanted.

It was caught only because the same command was run with a count control
first:

    kern_exit.o: 0 lines_of_disasm
    kern_exit_committed.o: 0 lines_of_disasm

Zero is not a plausible disassembly count, so the pattern was wrong rather
than the objects being empty. With `[[:space:]]` and the count re-run as a
control, the real numbers appeared — 5373 vs 5385 instructions for
`kern_exit.o`, 1563 vs 1570 for `kern_fork.o` — and the objects genuinely
**do** differ.

Only then was the actual question asked, function by function, and only then
did the useful answer come out: `exit_reason_get_string_desc` and `_proc_lock`
are instruction-identical in the linked objects, differing only in a
literal-pool displacement and an address, so the §32 reasoning describes the
code that actually ran.

**The rule this earns, which is not specific to this episode:** *a comparison
that can return "identical" must be able to return "different" on the same
input, and the cheapest proof is to run it on something known to differ before
trusting an "identical".* An empty-input hash is a comparison that cannot fail.

---

## 34. ✅ PROVENANCE CLOSED WHOLE-FILE — explanation 2 is REFUTED, and the page question is answered

### 34.1 The head-only control is replaced by a whole-file control, and it says the image is ours

Run against the image that already exists — no rebuild, no second boot:

| probe | result |
|---|---|
| gated loader, **all 1,733,184 bytes**, sha256 `886a4674…` | **offset 44,963,840 — byte-identical** |
| control loader, all 1,733,080 bytes, sha256 `624f8431…` | **−1, absent** |
| loader `__DATA` (8,192 B @ fileoff 892,928) | offset 45,856,768 — found |

**Explanation 2 is dead: the running image is the image I byte-verified.** So the
fault address, the decode contradiction and the `__DATA` question are **not**
downstream of a measurement gap. That was the single highest-value check in the
project and it is now closed, and it retroactively strengthens every earlier
`DYLD-LOAD-BASE` anchor: the binary those were symbolized against is provably the
binary that ran.

### 34.2 ✅ WHY `_mach_task_self_` is not in the image at all — and the arithmetic that shows it

The image stores the loader's file bytes contiguously, so `image[BASE + n] =
file[n]`. The segment table is:

| segment | vmaddr | vmsize | fileoff | filesize |
|---|---|---|---|---|
| `__TEXT` | 0x0 | 0xd5000 | 0 | 872,448 |
| `__DATA_CONST` | 0xd5000 | 0x5000 | 872,448 | 20,480 |
| `__DATA` | 0xda000 | **0x37000** (225,280) | 892,928 | **8,192** |
| `__LINKEDIT` | 0x111000 | 0xcc000 | 901,120 | 832,064 |

`__DATA`'s vmaddr equals its fileoff (0xda000 = 892,928), so the mapping looks
like an identity — **and that is the trap.** `_mach_task_self_` is at vmaddr
`0x10feb4`, which is **212,660 bytes past the end of `__DATA`'s file-backed
region**. It is **NOBITS**: there are no file bytes for it, and therefore none in
the image. Its runtime value is supplied by the kernel as zero-fill.

I made this exact mistake first: I read `file[0x10feb4]`, got non-zero bytes,
and nearly called it initialised data. Those bytes are at file offset 1,111,220,
which is past `__DATA` and inside `__LINKEDIT`. **Reading a zero-fill address as
if it were file-backed is its own instrument failure, and it is the second one
this round.**

### 34.3 So the page question has an answer, and it is a KERNEL-side one

The image does not contain `_mach_task_self_`. The kernel must map `__DATA`'s
**vmsize**, not its **filesize**, for the symbol to exist at runtime. The run
produced a **#PF on exactly that address**. Therefore:

> **The zero-filled `__DATA` page containing `_mach_task_self_` was NOT mapped.**

This is **not a dyld problem and not an image problem.** It is a
segment-mapping question: something in this kernel's Mach-O load path is
honouring `filesize` where it must honour `vmsize`, or is failing to map the
zero-fill tail.

**And that is why both candidate fixes are blocked on it, exactly as predicted:**
the gate **reads** `_mach_task_self_` and `mach_init_doit` **writes** it. Neither
can work until that page is mapped. **The fix is upstream of both, in the
kernel's segment mapping, and it is one check to confirm.**

### 34.4 The decode contradiction, now narrower but NOT resolved

Whole-file provenance removes the "different binary" explanation. What remains:

* `0xab78f` in the provably-identical binary is `cmpl $0x0, disp(%rax)` — a
  **read**, and its effective address is `RAX + disp`.
* the dump records `e=0004` — a **write** — and `CR2 == RAX` **exactly**, which
  needs `disp == 0`.

A read of a non-zero displacement cannot produce a write error code with
`CR2 == RAX`. **I am not resolving this by assertion.** Two readings survive, and
both are checkable:

1. the `#GP` at `0x8010000000000001` (`CCO=SUBQ`, a kernel-range address at
   CPL=3) means the process was already off the rails, and this `#PF` is a
   *consequence* — which would make the error-code disagreement a symptom rather
   than a contradiction;
2. the effective address really is `RAX`, meaning the faulting access is not the
   `cmpl` at all.

**Left open, as instructed, pending the mapping check.**

### 34.5 Next, in order

1. **Confirm the mapping claim from the kernel side** — does this kernel map
   `__DATA` to `vmsize` or only to `filesize`? One check, and it decides whether
   the next fix is in the kernel's segment loader, in the image, or in dyld.
2. Only then re-read the decode contradiction.
3. **The run script's control is now whole-file** for the loader; the kernel is
   still pinned by sha256 of the *payload* rather than hashed into the image, and
   that gap is real and unclosed.

### 34.6 ⛔ The place the fix belongs is NOT IN THIS TREE

To confirm §34.3 from source I looked for the Mach-O segment mapper:

```
$ grep -rln 'macho_load_tcm\|macho_load(' Kernel/xnu/osfmk Kernel/xnu/bsd
   (no results)
$ find Kernel/xnu -name 'macho*.c'
   Kernel/xnu/tests/macho_size_63133398.c          <-- a test, not the loader
$ grep -rln 'LC_SEGMENT_64' Kernel/xnu/osfmk
   kalloc.c, processor_core.c, dyld_kernel_fixups.h, arm_init.c, ...   <-- none is a mapper
```

**There is no Mach-O exec/segment loader in this tree.** `macho_load.c` — the file
that decides how much of a segment gets mapped — is absent, which is consistent
with row 14's census of components with no obtainable source and with §5.7's
pattern (the declarations are present, the implementation is not).

**So the defect §34.3 names has no source file here to fix.** That is a hard
constraint on what is achievable next, and it is the opposite of the situation a
moment ago, when the candidate fix was a one-line move in a file we own. The
frontier has moved from *our* code to *absent* code.

Two consequences worth stating before anyone spends time here:

* **Do not look for the bug in dyld.** dyld is doing the only thing it can: it
  read a symbol its own image says is zero-fill, and the page was not there.
* The next real step is **deciding where the segment mapping actually happens in
  THIS system** — it may be the Apple-derived dyld that `assets/usr/lib/dyld`
  held before we replaced it, or a boot-time path outside `Kernel/xnu` entirely.
  That is a question about provenance of the running kernel, not a code fix, and
  it should be answered before anyone opens an editor.

---

## 35. ⚠️ THE KERNEL PROVENANCE GAP IS WORSE THAN "HEAD-ONLY" — and closing it found a real image defect

Told to close the last provenance gap the way I closed the loader's. I could not,
and **the reason is a property of the image, not of my method.**

### 35.1 The whole-kernel hash search does not work on this image, and the naive reading is wrong

```
kernel payload  work/stripped_kernel.development  20,043,504 B  sha 25abd69f…
whole-kernel contiguous offset in image ................................ -1
   head      4,096 B -> 2,902,016
   head     65,536 B -> -1
   head  1,048,576 B -> -1
   head 16,777,216 B -> -1
```

**"The kernel is not in the image" is a METHOD FAILURE and I nearly recorded it
as a finding** — the third instrument-that-cannot-fail in this pattern. The
fragmentation test settles it:

| probe | image offset | contiguous with 2,902,016? |
|---|---|---|
| `payload[8192:+4096]` | 2,910,208 | **yes** (+8,192) |
| `payload[65536:+4096]` | 2,967,552 | **yes** (+65,536) |
| `payload[1048576:+4096]` | 3,950,592 | **yes** (+1,048,576) |
| **`payload[4096:+4096]`** | **−1** | **NOWHERE IN THE IMAGE** |

### 35.2 ✅ The actual finding: the image is missing exactly ONE 4 KB WINDOW of the kernel

The kernel in the image is byte-identical to the payload at +8,192, +65,536,
+1,048,576 and beyond — the file **is** contiguous — **except for the single
4,096-byte window at file offset 4096–8191, which is not present at any offset.**

So the kernel's contents are ~99.98% verified against the payload and the
residue is **one page**. That page is the same size as my original head-only
check, which is a coincidence I distrust rather than celebrate.

**What this means, stated exactly:** the boot's kernel is attributable to the
payload **up to one unverifiable 4 KB window**. It is not attributable as a
whole. Any claim of the form "this run ran THIS kernel" is currently supported
by a sha256 of the payload **at build time** plus this partial match — which is
exactly the blind spot I was told to close, now narrowed from "the first 4 KB"
to "all but one 4 KB window".

### 35.3 ⛔ AND MY RUN'S KERNEL PIN IS NOW UNVERIFIABLE

`work/stripped_kernel.development` was rebuilt after my run: `4f20e581…` →
`25abd69f…`, same 20,043,504 bytes. The peer diffed the two instruction streams
as a control before attributing it: **2,381,719 instructions in both, exactly 15
differ, every one a `__LINE__` immediate passed to an inlined `panic_plain`,
every delta exactly +12 matching their net +15/−3 in `kern_sig.c`.** No logic,
no layout shift.

**But the image still holds the OLD kernel, and the old payload no longer exists
on disk.** So the hash my run pinned cannot be checked against the image, and
cannot be re-derived from what is here. **The kernel my boot ran is identified
by a build-time hash and a partial byte match, and nothing more.** That is a
weaker statement than I made in §32, and it is the correction.

### 35.4 What would actually close it, and why it is not a code fix

Not a better search — the search is fine and the bytes are absent. It needs one
of:

* **the 4,096–8,191 window recovered or explained** in the image builder
  (`fat32img.py` / `mkimage.py`) — most likely a cluster-chain or short-write
  defect, and a one-line fix once seen;
* **a hash of the kernel recorded from inside the image** at build time, e.g.
  embedded in the boot arguments, so the running kernel identifies itself rather
  than being identified by a file that can be rebuilt underneath us;
* **the payload preserved** alongside the image, which is the cheapest and is
  what would have made §35.3 checkable.

The third is a change to how runs are recorded, not to any code under test.

---

## 36. ⚠️⚠️ CORRECTION — I misread §33.2, and the "fault at the gate" was NOT a fault

Told to test the zero-fill question before accepting a frontier that had left our
code. Testing it required reading the **control's** QEMU dump
(`qemu_ANCHOR.2149.log`, 118 MB — byte-identical signature to the 22:03 control),
and that comparison destroys my own §33.2.

### 36.1 `v=0e e=0014` is QEMU's NORMAL entry convention, not a fault

| | control 21:49 | gated 22:32 |
|---|---|---|
| `CPL=3` records | **2,627** | **38** |
| `v=0e e=0014 … cpl=3` (CR2 == PC) | 2,081 | the great majority of both |
| `v=0e e=0004 … cpl=3` | **present** (rec 47542, CR2=0x7fffffe00044) | present (rec 31087) |

`e=0014` with `CR2 == PC` is QEMU's ordinary demand-entry bookkeeping, and it
appears thousands of times at CPL=3 in **both** runs. `e=0004` appears at CPL=3 in
the **control** too — and the control went on to its panic. **Neither pattern is
the death.**

**So §33.2's "two faults, the first at `__simple_salloc+0xf`" was wrong. I read
routine records as faults.** That is the **sixth** instrument in this round that
could not fail, and the most consequential, because I built a frontier on it.

### 36.2 What the terminal event actually is

The gated run's **last** userspace record is still the one thing that stands:

```
 31088: v=0d ... cpl=3 IP=002b:8010000000000001 pc=8010000000000001
        CCO=SUBQ
```

A **`#GP` with RIP at a kernel-range address while in ring 3**, after which the CPU
never returns to CPL=3 at all (38 records versus the control's 2,627). **That is
the death. Everything before it is bookkeeping.**

`0x8010000000000001` is unexplained and remains the open item — recorded, not
explained, exactly as instructed.

### 36.3 ✅ The decode contradiction is RESOLVED — and it was a disassembler, not the CPU

The bytes at `0xab78f` are `83 38 00`:

```
83 /0  with modrm 38  ->  mod=00, reg=000 (CMP), rm=000 (RAX)
                        ->  cmpl $0x0, (%rax)      NO DISPLACEMENT
```

**`CR2 == RAX` is exactly correct.** The instruction reads `[RAX]`, and RAX holds
`&_mach_task_self_` from the preceding `leaq`. There is no contradiction, and
there never was.

The phantom contradiction came from **`otool` printing a `__framesize`
placeholder for a displacement of zero.** Reading that placeholder as a real
displacement is the **fifth** instrument that could not fail, and it is the one
that made me doubt a correct register dump. **Had I decoded the bytes first,
§33.4 would never have been written.**

### 36.4 The zero-fill question: NOT settled, and now honestly open

`&_mach_task_self_` in the control would be `0x119b6aeb4`. Records at or near it
in the control's dump: **zero**. So the control's QEMU log does **not**
independently show that the page was read or present.

What survives is only the register-dump inference — `RDI = 0` means
`mig_get_reply_port`'s `movl _mach_task_self_(%rip), %edi` **returned** 0, so the
load completed. That is an inference from a read result, which is good evidence
but is not a page-table observation, and I had been calling it more than that.

**So the frontier is NOT out of our code, and it is NOT inside it either. It is
open.** What is established:

* the gate is reached and the fixup walk runs to completion (§33.1 — stands);
* the recursion is gone (§32 — stands);
* the terminal event is a `#GP` at a kernel-range RIP in ring 3 (§36.2);
* `CR2 == RAX` is correct and the access is a **read** of `&_mach_task_self_` (§36.3);
* whether that page is present is **unestablished** — the check that would settle
  it is a mapping observation, not another register dump.

### 36.5 The builder hole: recorded as a FINDING, hypotheses labelled as hypotheses

**Finding:** the kernel payload is contiguous in the image and **exactly one
4,096-byte window, at file offset 4096–8191, is absent at any offset.** The
boot's kernel is attributable to the payload up to one unverifiable page. **This
stands, unaffected by anything above.**

**Hypotheses, explicitly not findings:** a cluster-chain defect in `fat32img.py`;
a short write; a size-dependent path in the builder. I named these as *likely
causes* and none has been tested. I have not touched the builder and will not
without saying so first — the other worker is in that tree.

**The distrust of the coincidence stands:** the hole is the same size as my
previous blind spot, at an offset that is itself that size. Two coincidences of
size is a reason to distrust the *location* of the hole, not a reason to trust it.

**Agreed priority order, now recorded:** preserve the payload beside the image
(cheapest, and it is what would have made §35.3 checkable at all), then carry a
kernel hash in the boot arguments so the running kernel identifies itself, then
explain the window.

---

## 37. ⚠️⚠️ §35 WAS WRONG — there is no hole in the image, and the builder is proven clean

The peer investigated independently and the finding is **mechanically** wrong, not
merely probably wrong.

**The builder, proven byte-exact.** On a fresh image against the payload current
at that moment: whole payload contiguous in the image **true**, pages not found
over 4,893 pages **NONE**. And the control that makes it trustworthy: the same
probe returned "3 pages missing" thirty seconds earlier, so **it can fail**.

**What I actually had.** The peer got 3 "missing" pages, not 1 — payload offsets
4096, 5,873,664, 9,240,576 — and diffing them byte-by-byte:

| payload offset | bytes differing | what they are |
|---|---|---|
| 4096 | 16 / 4096 (0.39%) | a relocated pointer |
| 5,873,664 | 1 / 4096 (0.02%) | — |
| 9,240,576 | 14 / 4096 (0.34%) | `0xce4` vs `0xcd8` — **their `__LINE__` immediate** |

**The mechanism, and it is the seventh instrument that could not fail:**

> A forward contiguity scan reports a **hole** wherever a window contains even one
> differing byte, while the windows either side match perfectly. So it reports
> "hole at 4096" when the truth is "the two files first differ at 4264".

My image was built at 22:19 and contains the 22:19 kernel. I compared it against
the payload on disk at 22:52, which was their 22:47 rebuild. **I compared two
different files and reported the difference as a defect in the image.** The
builder dropped nothing. There is no missing page.

**The peer declined to claim my finding was wrong, and that was right:**

> I cannot prove your original observation was an artifact, because the artifact
> you measured against — the 22:19 kernel file — no longer exists; I overwrote it
> at 22:47… "overwhelmingly likely" is not "proven".

**The contemporaneous payload is gone, so this is overwhelmingly likely and not
proven, and it is recorded that way.**

### 37.1 What survives of §35, and what does not

| §35 claim | status |
|---|---|
| the image is missing one 4,096-byte window | **WRONG** — no window is missing; one differs |
| the builder has a cluster-chain / short-write / size-dependent defect | **WRONG** — proven byte-exact |
| my run's kernel pin is unverifiable | **STANDS, and for the now-correct reason**: the payload was rebuilt, and the record said only *which file was on disk at build time*, never *which kernel that was* |
| the kernel is attributable only up to an unverifiable page | **MOOT** — it is attributable in full, provided the contemporaneous payload is kept |

### 37.2 ✅ THE DURABLE GAP IS FIXED — an image now identifies its own contents

Announced to the peer before touching it, as agreed; `tools/bootlab/mkdirimage.py`
only, nothing else. `mkimage.py` now, after the existing self-verify passes:

* hashes **every** staged file with **sha256** and writes a sidecar
  `<image>.digests`, one `sha256  path` per line;
* prints the **kernel's** digest on stdout, called out, because the kernel is the
  one payload another worker relinks mid-session.

**The existing md5 self-verify is unchanged.** It was never wrong; it proves the
image faithfully reproduces *a* file, and the sidecar records *which*.

Tested before committing, because an untested instrument is this round's
recurring failure — built a scratch image and cross-checked:

```
verify OK: 61 files, 75 tree entries, all content hashes match
kernel sha256 (recorded): 25abd69f88ddda10…   == shasum of the real payload
usr/lib/dyld               886a4674532af69a…   == shasum of our gated loader
wrote work/SCRATCH-DYLD.img.digests (61 digests)
```

Scratch image deleted. `work/boot_dynamic.img` and the peer's
`work/boot_dynamic.SIGREASON.img` untouched.

**This is what would have made §35.3 checkable at all**, and it is the cheapest of
the three closures the coordinator ranked. It does not explain the old run; it
means the next one cannot have the same problem.

---

## 38. ⛔ `libsystem_trace` — the scoped fix does NOT work, and the premise is 1-of-5, not 1-of-3

Workstream: build `libsystem_trace`, relink `libsystem_c`, build the `libSystem.B`
umbrella. The assigned fix was a **configuration change**: point `log.c` at the
SDK's `os/log.h` generation instead of xnu's `os/log_mem.h`.

**That change was measured and it does not fix it. It is a regression.** And
separately: `libsystem_trace` gates **1 of 5** dead providers, not 3 items. No
source file was changed. Nothing was staged. No boot was run.

### 38.1 Which header wins, and why — `clang -H` on the REAL emitted command

The command was read out of the real build log, not reconstructed. Built via
`tools/bootlab/build-libraries.sh Libsystem/libsystem_trace` (the script accepts
any directory under `Libraries/`, which reaches this component without first
building the 10 subdirs that precede it in `SUBDIR` and die on
`ld: library 'system_trace' not found`).

The relevant `-I` order, from the emitted argv:

```
 9  -I$SDK/usr/local/include/kernel
10  -I$ROOT_SOURCE_DIR/Kernel/xnu/libkern      <-- wins every os/ lookup
11  -I$ROOT_SOURCE_DIR/Frameworks
12  -I$SDK/usr/include
13  -I$SDK/System/Library/Frameworks/System.framework/PrivateHeaders
```

Live `-H` on that exact command (output redirected to `/tmp`, tree untouched):

```
.. /Users/max/Projects/ravynos/Kernel/xnu/libkern/os/log.h
.. /Users/max/Projects/ravynos/Kernel/xnu/libkern/os/log_private.h
.  /Users/max/Projects/ravynos/Kernel/xnu/libkern/os/log_encode_types.h
.. /Users/max/Projects/ravynos/Kernel/xnu/libkern/os/log_mem.h
.  /Users/max/Projects/ravynos/Kernel/xnu/libkern/os/log_encode.h
Kernel/xnu/libkern/os/log_mem.h:36:2: error: unknown type name 'lck_spin_t'
```

All five `os/` headers come from **`Kernel/xnu/libkern`**, because `-I` 10 is the
only directory on the path that contains an `os/` subtree at all. Independently
corroborated by the committed `.depend.log.o`, which lists the same five paths.

### 38.2 ⚠️ Why reordering cannot work — `log_mem.h` is not on the `-I` list

`os/log_mem.h` is reached from **`os/log_encode_types.h:39`, a *quoted*
`#include "log_mem.h"`**. A quoted include resolves relative to the including
file's own directory, so it does not consult `-I` at all. **No include-path
reorder can move it.** Verified by running both arms and reading `-H`: the `-I`
order changed and `os/log.h` moved with it, while `os/log_mem.h` did not —
which is also the positive control proving the probe can see a difference.

### 38.3 The SDK has no `os/log_encode*.h` to offer in exchange

The SDK's only `os/` tree is `Kernel.framework/Versions/A/PrivateHeaders/os/`,
which contains `alloc_util, atomic, base, cpp_util, log, object, overflow,
trace` (+privates). **`os/log_encode.h`, `os/log_encode_types.h`,
`os/log_private.h` and `os/log_mem.h` are all absent.** So making the SDK win
cannot redirect the encode chain; it can only change `os/log.h`.

And `os/log.h` is not the problem. Diffed, the SDK copy (18,048 B) is a strict
**subset** of xnu's (19,307 B): the 28-line diff is *entirely* inside
`#ifdef XNU_KERNEL_PRIVATE` and `#ifdef KERNEL`. Everything userspace reads is
byte-identical.

### 38.4 The experiment, both arms, verbatim

Arm A — as-is. Arm B — SDK's `os/` inserted ahead of xnu's libkern.

```
A: os/log.h -> /Users/max/Projects/ravynos/Kernel/xnu/libkern/os/log.h
   1x error: unknown type name 'lck_spin_t'
   2x error: invalid application of 'sizeof' to an incomplete type 'struct os_log_buffer_s'
   1x error: unknown type name 'os_log_buffer_context_t'; did you mean 'os_log_context_t'?
   + 11 more

B: os/log.h -> /Users/max/Projects/build/Tools/inc-3308252313/os/log.h   (the SDK's)
   1x error: unknown type name 'lck_spin_t'                                <-- UNCHANGED
   2x error: invalid application of 'sizeof' to an incomplete type 'struct os_log_buffer_s'  <-- UNCHANGED
   1x error: unknown type name 'os_log_buffer_context_t'; did you mean 'os_log_context_t'?    <-- UNCHANGED
   + 2x unknown type name 'memory_order', 2x 'memory_order_seq_cst',
     2x 'memory_order_acq_rel', 1x each acquire/release/consume   <-- NEW REGRESSION
```

**The SDK's generation demonstrably won** (arm B's path is the wrapper's overlay
of the SDK's `Kernel.framework/PrivateHeaders`, and it is the *only* thing that
changed). The three absent types are **unchanged**, and a new error class
appears because the SDK's `os/log.h` pulls C11 atomics that the xnu generation
did not. Not applied.

### 38.5 ⚠️⚠️ §20-class CORRECTION — `os/log_mem.h` is NOT a public macOS header

`Libraries/Libsystem/NOTES_os_log_pack_and_log_mem.md:142-147` recommends:
"it is a public SDK header on real macOS, so it is a fetch-a-real-header
problem". **That is wrong, and following it would send someone chasing a header
Apple does not ship.** Measured against the two genuine Apple SDKs on this host:

| probe | MacOSX15.4.sdk | MacOSX26.5.sdk |
|---|---|---|
| files named `log_mem.h`, whole SDK | **0** | **0** |
| files named `os_log.h`, whole SDK | **0** | **0** |
| headers **defining** `struct os_log_buffer_s` | **0** | **0** |
| headers **declaring** `os_log_encode` | **0** | **0** |
| *positive control:* `grep -rl os_log_type_t` on the same tree | finds `usr/include/os/log.h` | — |

Apple's public `os/log.h` declares nothing named `os_log_encode` at all. The
public API takes `void *buffer` precisely so the layout stays opaque;
`os_log_buffer_s` / `os_log_buffer_context_t` / `_os_log_encode` are internal to
the closed-source `libsystem_trace.dylib`. **This is not a header-import task.**

Neither generation of `os/log.h` defines any of the five symbols `log.c` needs
(0 hits in both), with `log.c` itself as the positive control (3/1/1/1/2 hits).

### 38.6 ⛔ STOPPED, per the brief — what a real fix would require

`log.c` is written against **Apple's private, never-published `libsystem_trace`
ABI**. No configuration change, header, include order, or public SDK on any
machine can satisfy it. Only three ways forward, and all are design decisions
about a component that owns crash formatting, not configuration:

1. **Obtain the private header** from a non-public source. An authorization
   question, not an engineering one.
2. **Re-derive `os_log_encode` against the public contract** — drop the
   `os_log_buffer_s` prefix framing entirely. A rewrite of the encode path.
3. **Declare a ravynOS-local buffer layout** — i.e. invent the struct. Refused;
   it is a silent-wrong-answer defect in the crash path.

No new declaration was added. Nothing in `Libraries/Libsystem/private/` or
`Kernel/xnu` was touched.

### 38.7 ⚠️⚠️ THE PREMISE IS WRONG — `libsystem_trace` is 1 of **5** dead providers

This is the larger finding, and it is measured. Taking the transitive `otool -L`
closure of the image's `/usr/lib/libSystem.B.dylib` over `tools/bootlab/assets`
and testing **every member** with `dyld_info -exports`:

**44 closure members, 0 unresolved deps — and 20 of the 44 have ZERO
dyld-readable exports.** Including the umbrella itself.

`unprovided = A − P`, A = `nm -u`, P = union of `dyld_info -exports` over the
closure, exact Mach-O names (no normalisation), all md5-pinned:

| consumer | A | unprovided as staged | unprovided if our built libs were staged | delta |
|---|---|---|---|---|
| `libsystem_c.dylib` | 273 | **51** | **3** | −48 |
| `bin/cat` | 40 | 3 | **0** | −3 |
| `bin/ls` | 91 | 9 | 5 | −4 |
| `bin/echo` | 10 | 0 | 0 | 0 |

The 51 are exactly the symbols of the five dead providers — libtrace (3),
libdispatch (~19), pthread (~17), blocks (2), libsystem_info (~10). And **four
of those five are already built and already dyld-readable**:

| library | staged in image | our built (SDK) |
|---|---|---|
| `libdispatch` | 550,562 B — **UNREADABLE** | 912,240 B — **329 exports** ✅ |
| `libsystem_pthread` | 118,674 B — **UNREADABLE** | 164,216 B — **188 exports** ✅ |
| `libsystem_blocks` | 78,975 B — **UNREADABLE** | 22,288 B — **20 exports** ✅ |
| `libsystem_info` | 299,483 B — **UNREADABLE** | 408,160 B — **549 exports** ✅ |
| `libsystem_trace` | 219,902 B — **UNREADABLE** | **absent — never built** |

So restaging four libraries the project has **already built** takes
`libsystem_c` from 51 unprovided to **3**, and those 3 are exactly
`___os_log_encode`, `_os_log_pack_fill`, `_os_log_pack_size` — i.e. exactly
`libsystem_trace`, confirming both halves of the premise at once. **The
umbrella is gated on 5 dead providers, 4 of which need only restaging and no
compilation at all.** That is a much cheaper lever than the one assigned, and
it is the recommendation.

### 38.8 Measurement notes — four ways this round nearly recorded a wrong number

1. **`A − P` can be vacuously zero.** The SDK's own
   `usr/lib/libSystem.B.dylib` (4,120 B, md5 `52717a95…`) has A=0 *and* 0
   exports, so `unprovided = 0` — a "pass" that means the file is a stub. A
   closure number is only meaningful next to the artifact's own A and its
   `dyld_info` exit status.
2. **A shell loop silently truncated `P_dyld` to 1,550** — smaller than one
   member (libsystem_kernel alone has 1,581). Replaced with a script that
   *asserts* `union ≥ max(single file)`; the corrected union is **6,705**. The
   broken number is discarded and no result below depends on it.
3. **`___error` is three underscores.** A `sed 's/^_//'` plus a two-underscore
   search made a defined symbol look undefined and vice versa. All results here
   use exact Mach-O names with no normalisation.
4. **`grep -E 'error'` matched a symbol named `__error`.** The first
   `dyld_info` pass reported a healthy 1,255,496 B `libsystem_c` as FAILED.
   Re-keyed on the exit code. (Its real numbers: 265 readable exports, 1,342
   symtab — and it is the *staged* copy that is unreadable.)

`ps` was checked before both builds: no `bmake`, `isysroot-cc` or
`build-libraries` running. No file was edited while executing.

---

## 39. ✅ FOUR LIBRARIES RESTAGED — 51 → 8, not 51 → 3, and the table named two MORE

§38 found that four of the five dead providers were already built and already
dyld-readable, and that the image was running on dead Apple extracts for them.
Restaging was authorised for those four. **Done, verified whole-file from the
FAT32 filesystem, and the prediction was wrong by five symbols** — in the most
useful possible way, because the control was specified in advance and it paid.

### 39.1 What was done

Byte copies, never symlinks, Apple originals backed up first
(`tools/bootlab/work/staging_backup/`, which `work/` is gitignored, so the
backups cost the repo nothing and cannot be committed by accident):

| library | Apple original (md5) | our build now staged (md5) | size |
|---|---|---|---|
| `libdispatch` | `0fd3bfd8b7e70de0f0b5ad4d9738562f` | `fe47805175f619a191a32943b8e97a50` | 550,562 → 912,240 |
| `libsystem_pthread` | `eea945a58b7ebe1f0be27ef1ab0c711b` | `b52c70d3ae8bed903820394993298907` | 118,674 → 164,216 |
| `libsystem_blocks` | `34c13c5ae1409cc674b5ff62260c9b41` | `1cf9fba02e292a4d985a0bf1211bbf39` | 78,975 → 22,288 |
| `libsystem_info` | `a16c5dca23336acd7f6f276594656956` | `dbcfc48de0da131e04347b59353e9adb` | 299,483 → 408,160 |

All four are **regular files** (`stat -f %HT`), all four `cmp`-identical to the
SDK source, all four install names `/usr/lib/system/<name>.dylib` and all four
`x86_64` — matching the Apple originals they replaced on both counts.

### 39.2 Image rebuilt once, alone, and verified WHOLE-FILE from the filesystem

`python3 mkimage.py work/RESTAGE.img` — a scratch name, so the other workers'
`boot_dynamic*.img` were not touched. `verify OK: 61 files, 75 tree entries,
all content hashes match`.

The four were then read **back out of the FAT32 filesystem with
`Fat32Img.read_path` and md5'd whole** — not a head sample, because a head
sample cannot see `__DATA`:

```
libdispatch         912240  fe47805175f619a191a32943b8e97a50  == ours YES  == apple no
libsystem_pthread   164216  b52c70d3ae8bed903820394993298907  == ours YES  == apple no
libsystem_blocks     22288  1cf9fba02e292a4d985a0bf1211bbf39  == ours YES  == apple no
libsystem_info      408160  dbcfc48de0da131e04347b59353e9adb  == ours YES  == apple no
WHOLE-FILE VERDICT: our four present AND apple four absent -> PASS
```

The md5s read out of the image are identical to the ones pinned before the copy.
`RESTAGE.img` md5 `f57c9f05c1b6df53632ac7e380bd747d`.

### 39.3 The closure, computed FROM THE IMAGE, with the §38.8 assertion

44 closure files, 0 unresolved deps. **Unreadable: 20 → 16.** Union `P`:
6,705 → **7,787**, and the assertion `union ≥ max(single file)` holds
(7,787 ≥ 1,581, `libsystem_kernel`). The image-derived closure and the
assets-derived one agree exactly, which is itself a cross-check.

| consumer | A | before | **after** | delta |
|---|---|---|---|---|
| `libsystem_c.dylib` | 273 | 51 | **8** | **−43** |
| `bin/cat` | 40 | 3 | **0** | −3 |
| `bin/ls` | 91 | 9 | 6 | −3 |
| `bin/echo` | 10 | 0 | 0 | 0 |

**The prediction of "exactly 3" was wrong. It is 8.**

### 39.4 ⚠️ What the 8 are, and why — TWO MORE DEAD PROVIDERS

```
___os_log_encode      -> NOT DEFINED BY ANY IMAGE LIBRARY   (libsystem_trace, never built)
_os_log_pack_fill     -> NOT DEFINED BY ANY IMAGE LIBRARY
_os_log_pack_size     -> NOT DEFINED BY ANY IMAGE LIBRARY
_bootstrap_parent     -> liblaunch
_nan / _nanf / _nanl  -> libsystem_m
_fpclassify           -> NOT DEFINED BY ANY IMAGE LIBRARY (our libsystem_m exports it)
```

`libsystem_m` and `liblaunch` are **still dead Apple extracts**, and they are
the same defect and the same remedy as the four just fixed. Both are already
built and both are already readable:

| library | staged (still Apple) | our build |
|---|---|---|
| `libsystem_m` | 535,784 B — UNREADABLE | 39,512 B — **187 exports** (`ab14f714aa8cd31ad82810cfc3e01a41`) |
| `liblaunch` | 49,152 B — UNREADABLE | 91,704 B — **153 exports** (`d6c61e693ddaa3f2aaa8d66d1f6e0541`) |

**Projection, measured not guessed** (union of those two tries' `dyld_info`
output with the image's current `P`; the image was not modified):

```
libsystem_c.dylib   unprovided now = 8   with six = 3
the remainder with six:
   ___os_log_encode
   _os_log_pack_fill
   _os_log_pack_size
```

**So the §38 prediction was right, and it was off by two libraries rather than
by any error in the method.** The lever is **six** restages, not four, and at
six `libsystem_c` reaches exactly the three `libsystem_trace` symbols — which
is the clean statement of what `libsystem_trace` actually gates.

Not done unilaterally: restaging two more libraries changes the image payload
other workers are measuring, and the authorisation named four. **Recommend
authorising `libsystem_m` and `liblaunch`; the evidence is above and the
method is identical.**

### 39.5 One more false negative of my own, caught in flight

Mapping the 8 to providers, my first loop printed `_nan -> <nobody in assets>`.
It was wrong: `nm -g libsystem_m.dylib` shows `T _nan` directly. The loop's
`nm -gjU | grep -qx` over a glob was the faulty probe, not the file. Recorded
because it is the same shape as §38.8's other three: **a negative produced by a
probe that could not express the thing it was looking for.** A `T` in
`nm -g` is a definition; a pipeline that filters it away first is not a
definition search.

No boot was run. `ps` was checked before the restage and before the image
build: no `bmake`, `isysroot-cc`, `build-libraries` or `qemu` running.

---

## 40. ✅ THE ZERO-FILL PAGE **IS** MAPPED — §34.3 is REFUTED, and the terminal `#GP` is an **UNBOUND GOT STUB**

The open question was one measurement: is the `__DATA` zero-fill page holding
`_mach_task_self_` mapped? **It is.** §34.3 concluded it was not, on the strength
of a `#PF` — and that conclusion is wrong, for a reason worth writing down
because it is the **seventh** instrument in this round that could not fail.

### 40.1 §36.4's premise is FALSE — the control has that record and it is a fault

§36.4 records "Records at or near [`&_mach_task_self_` in the control]:
**zero**." The control is `qemu_ANCHOR.2149.log`, base `DYLD-LOAD-BASE:
0x119a5b000`, so the address is `0x119a5b000 + 0x10feb4 = 0x119b6aeb4`. It is
there:

```
 49181: v=0e e=0004 i=0 cpl=3 IP=002b:0000000119b0678f pc=0000000119b0678f
        SP=0023:00007ff7b248b780 CR2=0000000119b6aeb4
```

`CR2` is `_mach_task_self_` **to the byte**, and `pc − base = 0xab78f` is the
**same offset** as the gated run's. Two independent boots, two slides, one
offset. §36.4's zero was a search that could not express what it looked for.

### 40.2 The `#PF` is a FIRST TOUCH, and a first touch is not an absent mapping

`e=0004`: bit0=0 (read), **bit1=0 (page not present)**, bit2=1 (user). A
demand-zero page has no PTE **by design** — its first read raises `#PF` with
bit1 clear, `vm_fault` allocates the zero page, and the instruction is retried
successfully. **`e=0004` is the expected state of a mapped-but-unbacked page, not
evidence of a missing one.** §34.3 read a normal demand fault as a broken map.

The control settles it by what it did **next**: **2,594 further CPL=3 records**,
same thread, `SP` continuing monotonically down the same stack
(`0x7ff7b248b960 → b780 → b778 → b6f8`). A thread cannot run on past a fault on
an address that has no mapping — the kernel would deliver `EXC_BAD_ACCESS` and
terminate it. **The fault was resolved in-guest, which requires a VM object
covering the address.** The gated run does the same thing: the record after the
`#PF` is `v=0d … cpl=3 SP=0023:…`, i.e. resumed in ring 3.

So: **mapped, demand-zero, first touch, in both runs — and therefore not the
discriminator between them.** The built kernel agrees with the source:
`bsd/DEVELOPMENT/mach_loader.o` (Aug 31, same bulk build as §10e's stale
`vm_unix.o`) disassembles to **two** `callq _map_segment` from `_load_segment`
(`0x21c7`, `0x2a7c`) with the `tmp_start`/`tmp_end` delta-overflow checks — the
file-backed part *and* the zero-fill delta, `vmsize` honoured.

### 40.3 The control's burst, which costs nothing and was never read

| | control 21:49 | gated 22:38 |
|---|---|---|
| CPL=3 records | **2,627** | 38 |
| `v=0e e=0006` (read, **page present**, access denied) | **2,048** | 0 |
| `v=0e e=0004` (read, page not present) | 10 | 9 |
| `v=dd` (GP) | 546 | 7 |
| last CPL=3 | `e=0006` on `0x7ff7b1c8dfe8`, 8 below `SP` | `#GP` RIP `0x8010000000000001` |

**The control's 2,048 faults are `e=0006` — the page is PRESENT and the access is
denied — on addresses 8 bytes *below* `SP`.** That is a walk down a stack into a
mapped-but-protected region, and it is the control's *last* activity. The control
did not die at `_mach_task_self_`; it thrashed for 2,000-odd records afterwards
and then panicked. `e=0006` is also the **positive control** for the error-code
discriminator: the same field, same logs, demonstrably reporting "present".

### 40.4 ✅ `0x8010000000000001` IS NOT A KERNEL ADDRESS — it is a literal in our own `__got`

§36.2 recorded it as "a kernel-range address at CPL=3". It is **non-canonical**:
bit47=0, bits62:48=`0x10`, and canonical form requires bits62:48 == bit47. It is
not in the kernel half (`0xffff8…`–`0xfffff…`) and not in the user half. It is
therefore a value the CPU was told to *execute*, not a kernel pointer.

It is also **in the image**. Whole-file provenance is §34.1's (both loaders
`sha256`-matched byte-for-byte), and a byte search of the staged loader finds it
**once**, at file offset `0xd5018` — which is `__DATA_CONST + 0x18`, the second
slot of `__DATA_CONST,__got` (addr `0xd5000`, size `0x78` = 15 slots):

```
+0x10  00 00 00 00 00 00 10 80      0x8010000000000000
+0x18  01 00 00 00 00 00 10 80      0x8010000000000001   <-- the terminal RIP
+0x20  02 00 00 00 00 00 10 80      0x8010000000000002
   … one per slot, 13 of them …
+0x70  0c 00 00 00 00 00 10 80      0x801000000000000c
```

Decoded against `Libraries/dyld/include/mach-o/fixup-chains.h`, these are
`dyld_chained_ptr_64_bind` with **`bind=1`** and **ordinal = 0…12**, `next=2`:
**unresolved import descriptors, left exactly as the linker wrote them.**

### 40.5 ⚠️⚠️ **CORRECTION — §40.5's first version was WRONG, and `dyld_info` refuted it**

I read the first `uint32` at the `LC_DYLD_CHAINED_FIXUPS` data as
`dyld_chained_starts_in_image.segment_count`, found it `0`, and built a root
cause on it: *"no chain starts, the walk is a no-op."* **That is false.** The
data at `0xdc000` is a **`dyld_fixups_header`**, whose first field is
`fixups_version`, not a segment count:

```
fixups_version  0x00000000      <- I read this as segment_count
starts_offset   0x00000020
imports_offset  0x00000074
symbols_offset  0x000000A8
imports_count   13              <- I read this as something else
imports_format  1 (DYLD_CHAINED_IMPORT)
symbols_format  0
```

**And the chain starts are fully populated.** `dyld_info -fixup_chains` on the
staged loader:

```
seg[1]  segment_offset 0x000D5000 (__DATA_CONST)  pointer_format 6
        pages: 5   start[0..4] = 0x0000 each
seg[2]  segment_offset 0x000DA000 (__DATA)
```

**The walk has real work to do and it is pointed at exactly the right pages —
all five pages of `__DATA_CONST`, each with a chain starting at offset 0, which
is where the `__got` lives.** The control loader is identical in shape (12
imports, same 5 pages, same starts).

**How it went wrong, and it is the third time this round:** my hand parser used
the **32-bit** `dyld_chained_starts_in_segment` layout (`uint32 page_size`,
`uint32 pointer_format`, `uint32 segment_offset`) while the header in *this* tree
(`Libraries/dyld/include/mach-o/fixup-chains.h`) is the **64-bit-safe** one
(`uint16 page_size`, `uint16 pointer_format`, `uint64 segment_offset`). The
offsets did not line up, so I read a plausible-looking integer out of a header.

**The control that should have caught it, and did not run soon enough:** I
compiled a trivial C file with the **host** `clang`/`ld64` and ran the same
parser on it. It also reported `segment_count = 0` — on a binary that is
*known* to have working chained fixups. **A positive control that agrees with
the suspect is a control that has failed, not a confirmation**, and I read it as
confirmation. It was run late, and it should have invalidated the claim
immediately rather than being filed as a curiosity.

**What survives, and it is the load-bearing part:** the `__got` contents, the
stub table, the non-canonical finding, and the exoneration of the gate. Those
were established by byte search, by the indirect symbol table, and by
`dyld_info -imports` — not by the starts parser. What does **not** survive is
"the walk visits nothing."

### 40.5b ✅ THE REAL DEFECT, restated: the walk visits the right pages, resolves **zero of 13** binds, and returns `noError`

The imports table is present and correct — `dyld_info -imports` names all 13,
and they are **all `<flat-namespace>`** (there are no `LC_LOAD_DYLIB`s, so there
is no ordinal table; every import must be resolved by searching the loaded
closure by name):

```
0x0000 ____chkstk_darwin                        0x0007 _pthread_rwlock_unlock$UNIX2003
0x0001 ___kernelrpc_mach_vm_allocate_trap        0x0008 _pthread_rwlock_wrlock$UNIX2003
0x0002 ___libunwind_Registers_x86_64_jumpto      0x0009 _system_version_compat_check_path_suffix
0x0003 ___shared_region_map_and_slide_np        0x000A _system_version_compat_open_shim
0x0004 ___unw_getcontext                        0x000B _voucher_mach_msg_fill_aux
0x0005 _mach_msg2                               0x000C _voucher_mach_msg_fill_aux_supported
0x0006 _pthread_rwlock_rdlock$UNIX2003
```

So the machinery is all there: starts, imports, symbols. **The walk runs over
`__DATA_CONST`, reaches the 13 `bind=1` slots, writes none of them, and returns
`Diagnostics::noError`.** `__stubs` is 11 six-byte `jmpq *GOT[k]` thunks, so the
first stub executed jumps at a raw descriptor and the process dies with `#GP`.

**The leading hypothesis, and it is a hypothesis:** all 13 imports are
**flat-namespace**, and our `fixupAllChainedFixups` bind path does not resolve
flat-namespace imports — it looks for a dylib ordinal, finds none, and leaves
the descriptor silently instead of reporting it. That is consistent with every
observation, and it is checkable in our own source.

**The guard is worth more than the hypothesis.** A fixup pass that resolves
zero binds and reports success is a check that cannot fail — the same defect
class as `rc=0` by default and the empty export trie. It should be landed
independently of whichever mechanism is at fault, because it is the thing that
let a broken image walk silently for this long.

| stub | GOT | raw slot value | target |
|---|---|---|---|
| 0 | `0xd5010` | `0x8010000000000000` | `____chkstk_darwin` |
| **1** | **`0xd5018`** | **`0x8010000000000001`** | **`___kernelrpc_mach_vm_allocate_trap`** |
| 2 | `0xd5020` | `0x8010000000000002` | `___libunwind_Registers_x86_64_jumpto` |
| 3 | `0xd5028` | `0x8010000000000003` | `___shared_region_map_and_slide_np` |
| 4 | `0xd5030` | `0x8010000000000004` | `___unw_getcontext` |
| 5 | `0xd5038` | `0x8010000000000005` | `_mach_msg2` |
| 6–8 | `0xd5040`–`0xd5050` | ordinals 6–8 | `pthread_rwlock_{rd,un,}lock` |
| 9 | `0xd5068` | `0x801000000000000b` | `_voucher_mach_msg_fill_aux` |
| 10 | `0xd5070` | `0x804000000000000c` | `_voucher_mach_msg_fill_aux_supported` |

### 40.6 Why this run and not the control: the gate is NOT the discriminator

The brief's instruction was to start at the gate. **The gate is innocent of the
terminal event, and this exoneration is now closed rather than assumed.**
`dyld.PRE-SALLOC-GATE` has the *same* populated chain starts over the same five
`__DATA_CONST` pages, the *same* structure — 10 stubs, **12** imports — and its
`GOT[1]` is **also `0x8010000000000001`**, bound to
`___libunwind_Registers_x86_64_jumpto`. Both loaders fail to bind their GOT in
exactly the same way.

The gate's whole effect is that it **added one import**: 12 undefined symbols
→ 13, the new one being `___kernelrpc_mach_vm_allocate_trap` at **ordinal 1**,
which is precisely the slot whose raw descriptor became the terminal RIP. The
gated build is not more broken; it is **one instruction closer to executing a
GOT slot that was never going to be bound.** The control would have died at
`0x8010000000000001` too, had it reached its stub 1.

**Keep the gate.** It is byte-verified, the recursion it stopped is gone, and
the fixup walk still completes. It is not what killed this run.

### 40.7 ⛔ What I did NOT do, and one thing that got worse

* **I did not read the guest's page tables or a `vm_map`.** A monitor walk was
  written (`/tmp`, never in the repo) and the monitor socket already exists
  (`boot.py` line 80), but **the live walk was not achieved**: two re-boots of
  `work/boot_dynamic.SALLOCGATE.img` produced **14** and **0** CPL=3 records and
  **never printed `DYLD-LOAD-BASE`** — the loader did not run, so there was no
  user `CR3` to walk. The answer in §40.2 therefore rests on the MMU's own fault
  report plus the control's survival, **not** on a page-table dump. Stated
  because §34.5 asked for the mapping check specifically.
* **Those two boots are a new observation, not a pass:** the same image that
  produced the 22:38 fingerprint did not reproduce it twice afterwards. Not
  explained. Not investigated — it is another worker's window to own.
* No build was run. `ps` was checked before both boots: no `bmake`,
  `isysroot-cc`, `build-libraries` or other `qemu`.
* **No evidence was lost:** `work/qemu_full.log` was overwritten by the re-boots
  only after verifying `work/qemu_SALLOCGATE.log` **byte-identical to it across
  all 7,629,941,057 bytes** (chunked compare, not a hash). Serial logs went to
  new files. `vars_full.fd` is re-copied from `assets/vars.fd` by `boot.py` on
  every run, as required.

### 40.8 The next step, which is in our code

`fixupAllChainedFixups` must not return `noError` after resolving **zero of 13**
binds on pages it demonstrably visited. The likely mechanism is that all 13
imports are **flat-namespace** and our bind path has no flat-namespace lookup, so
it leaves each descriptor silently — but the mechanism is a hypothesis and the
guard is not: a pass that binds nothing and says `noError` is a check that
cannot fail, the same class as `rc=0` by default and the empty export trie.
Until it is fixed, every stub call is a coin flip on a non-canonical address, and
which one fires first is not a fact about the fault.

---

## 41. ✅ SIX RESTAGES — `libsystem_c` reaches **exactly 3** unprovided, and they are all `libsystem_trace`

Continuation of §39. `libsystem_m` and `liblaunch` authorised and restaged, same
six-step scope. **The prediction held exactly: 3, and nothing else.**

### 41.1 The two restaged

Backed up first (refusing to overwrite; no collision — `work/staging_backup`
had neither name), then byte-copied. Not symlinks; `stat -f %HT` = `regular
file`; `cmp`-identical to the SDK source; install names and arch matching the
Apple originals they replace.

| library | Apple original (md5) | our build now staged (md5) | size |
|---|---|---|---|
| `libsystem_m` | `546ae6fdef460aba51e8e9376223c5a2` | `ab14f714aa8cd31ad82810cfc3e01a41` | 535,784 → 39,512 |
| `liblaunch` | `ada39b217f326d55b6fc61eb5bb4282d` | `d6c61e693ddaa3f2aaa8d66d1f6e0541` | 49,152 → 91,704 |

Load-command check run **before** the image build, because a restaged library
can carry a dependency the image does not satisfy: **0 missing deps for
both.** Worth noting the shape changed — our `libsystem_m` is self-contained
where Apple's pulled in `libdyld`/`libcompiler_rt`/`libsystem_pthread`, and our
`liblaunch` pulls 10 where Apple's pulled 3. All 10 are present, and the
closure below confirms it end to end.

### 41.2 Image rebuilt to a scratch name, verified whole-file from the filesystem

`work/RESTAGE6.img` (scratch; the peers' three `boot_dynamic*.img` untouched at
536,870,912 B each). Verbatim: `verify OK: 61 files, 75 tree entries, all
content hashes match`. `RESTAGE6.img` md5 `7103fe0abb77b9b47e720f0cc359b68c`.

Read back out of the FAT32 filesystem with `read_path`, md5'd **whole**:

```
libsystem_m   39512  ab14f714aa8cd31ad82810cfc3e01a41  == ours YES  == apple no
liblaunch     91704  d6c61e693ddaa3f2aaa8d66d1f6e0541  == ours YES  == apple no
WHOLE-FILE VERDICT: our two present AND apple two absent -> PASS
```

and §39's four re-confirmed present and ours in this same image.

### 41.3 Closure from the image, with §20.2's assertion applied to my own union

44 files, 0 unresolved deps. Unreadable **16 → 14**. `P` **7,787 → 8,127** —
which is **exactly** the value §39.4 projected, to the symbol.

The standing rule was asserted as a hard `assert` (not a print), which is the
only way a rule stays true:

```
union = 8127    max single file = 1581 (libsystem_kernel.dylib)   -> PASS
```

| consumer | A | baseline | after 4 | **after 6** | total delta |
|---|---|---|---|---|---|
| `libsystem_c.dylib` | 273 | 51 | 8 | **3** | **−48** |
| `bin/cat` | 40 | 3 | 0 | **0** | −3 |
| `bin/ls` | 91 | 9 | 6 | 6 | −3 |
| `bin/echo` | 10 | 0 | 0 | 0 | 0 |

**The remainder is exactly three, and nothing else:**

```
___os_log_encode
_os_log_pack_fill
_os_log_pack_size
```

All three present, **0 extra**. This is now a clean statement of what
`libsystem_trace` actually gates: **nothing else in the closure is waiting on
it.** Every other provider in the image is either ours and readable, or an
Apple extract that nothing needs a definition from.

### 41.4 The 14 still unreadable, and the 6 `ls` still wants

Still unreadable (all Apple extracts): `libSystem.B`, `libcache`,
`libcompiler_rt`, `libquarantine`, `libsystem_collections`,
`libsystem_configuration`, `libsystem_containermanager`,
`libsystem_darwindirectory`, `libsystem_eligibility`,
`libsystem_featureflags`, `libsystem_networkextension`, `libsystem_sanitizers`,
`libsystem_trace`, `libunwind`. **None of them defines a symbol anything in the
closure still needs** — the 3 remaining are defined by no image library at all.

`bin/ls` still wants 6, and they are **not** part of this lever:
`_humanize_number`, `_strtonum`, `_tgetent`, `_tgetstr`, `_tgoto`, `_tputs` —
terminfo and BSD-utility symbols, defined by **no library in the image**. They
belong to components this tree has not built (`libbsd`/`ncurses`-shaped), not
to the restaging work, and they are recorded here so the next reader does not
re-derive them.

### 41.5 State

Six restages done, all backed up, nothing staged to git, no boot run. The
image is built and verified; **running it is the next worker's call.** The
honest summary of where this workstream ends: the closure is as closed as the
built tree allows, and the last three symbols are the three that only
`libsystem_trace` can supply — which is §38's stop, unchanged and now the
*only* thing between this image and a resolved `libsystem_c`.

---

## 42. `RESTAGE6.img` BOOTED — the fault **MOVED**, and it moved a long way

`work/RESTAGE6.img`, md5 `7103fe0abb77b9b47e720f0cc359b68c`, §41's image.
`ps` checked clear before the boot: no `bmake`, `qemu`, `clang`,
`isysroot-cc` or `build-libraries`. Evidence preserved as
`work/qemu_RESTAGE6.log`, 1,110,633,353 B, sha256 `c033af9b26be8ad…`.

### 42.1 The fault signature, verbatim

```
18,469,180 exception records total:  509,984 at CPL=3, 329,532 at CPL=0

CPL=3 v/e histogram:  v=dd e=0000  509,976      (#GP)
                      v=07 e=0000        8      (#NM)
                      v=0e                 0     (#PF)   <-- ZERO page faults

CPL=0 v/e:            v=dd e=0000  327,499      (#GP)
                      v=20 e=0000    1,552
                      v=ff e=0000      452      (#MF — double fault)

 29378: v=dd e=0000 cpl=3 IP=002b:0000000100000635 pc=...0635 SP=0023:00007ff7bfeffd30 EAX=000000000000001a
 29380: v=07 e=0000 cpl=3 IP=002b:000000010000073f pc=...073f SP=0023:00007ff7bfeffd30 EAX=0
 29385: v=dd e=0000 cpl=3 IP=002b:00000001000007b2 pc=...07b2 SP=0023:00007ff7bfeffd30 EAX=0000000000000b32
839515: v=dd e=0000 cpl=3 IP=002b:00000001000007b2 pc=...07b2 SP=0023:00007ff7bfeffd30 EAX=0000000000fecb58

PC distribution:  0x1000007b2 x 502,266   0x1000007b0 x 7,607
                  0x10000073f x 9         0x100000635 x 1        0x100000790 x 1
```

**This is not the §40 terminal event, and not a variant of it.** There is no
`#GP` at a raw GOT descriptor to report, so there is no GOT slot or ordinal to
name. What there is instead:

* **509,976 ring-3 `#GP`, up from 38 CPL=3 records in the 22:38 run and 2,627 in
  the control** — four orders of magnitude past anything this project has seen.
* **Zero `#PF` at CPL=3.** The `_mach_task_self_` demand-zero first touch — the
  fault §40.2 characterised — **is simply not in this run at all.** Whatever was
  faulting there is no longer faulting.
* **327,499 kernel `#GP` and 452 kernel double faults.** The kernel is in the
  same storm. This is a machine-wide fault loop, not a userspace process that
  died.

### 42.2 What it is doing: executing inside its own load commands

The five distinct ring-3 PCs span **`0x100000635`–`0x100000790`, a 347-byte
window**, and the two hottest are **2 bytes apart** — a byte-stepping loop, not
a function. `SP` never moves from `0x7ff7bfeffd30` and **`EAX` counts up**
across the whole run (`0x1a`, `0xb32`, `0x18a6`, `0x242a` … `0xfecb58`).
That is a loop counter.

The bytes actually being executed are load-command bytes. For this loader the
load commands occupy `0x20..0x7b8` and `__text` starts at `0x1000`:

```
0x7b0:  80 db 0d 00 f0 00 00 00      0x7b2 is the low half of LC_DATA_IN_CODE.dataoff (0xddb80)
0x635:  63 00 00 2e 63 00 00 06      inside LC_SYMTAB/LC_DYSYMTAB
0x73f:  00 00 00 00 00 00 00 00      inside LC_UNIXTHREAD
```

`LC_UNIXTHREAD` is the **last** load command, and the hot pair sits **6 bytes
into `LC_DATA_IN_CODE`**, the very last one. A `forEachLoadCommand` loop that
has run off the end of the load commands and is now interpreting them as
instructions is the shape that fits: a counter in `EAX`, a fixed `SP`, two-byte
steps, and no exit.

**The base is NOT confirmed, and I will not assert it.** `DYLD-LOAD-BASE` was
printed to the serial log, and **the serial log was lost**: I set
`--window 300` while the harness command timeout is also 300 s, so `boot.py`
was killed at exactly its own window expiry, before it writes the file. The
absolute PCs above are measured; "these offsets are inside the load commands"
holds **if** the base is `0x100000000`, which I could not confirm. **That was my
error and it cost the anchor.** What survives base-independently is the
347-byte window, the 2-byte stride, the fixed `SP` and the counting `EAX`.

### 42.3 Not a regression, and the loader is unchanged

Only *dylibs* differ in this image; `assets/usr/lib/dyld` is the same file §40
analysed, whole-file verified. So the change in behaviour comes from the
**closure**, not the loader binary — six libraries whose exports now come from
our loaders instead of dead Apple extracts. The loader got far enough to
process a much larger closure and then fell off the end of a load-command walk.
That is a **new frontier**, and it is downstream of §40, not a step back from it.

### 42.4 ✅ Two defects in `fixupAllChainedFixups`, found in source and LANDED

`dyldInitialization.cpp:123` calls the fixup walk with an **empty** bind-target
array:

```c
ma->withChainStarts(diag, 0, ^(const dyld_chained_starts_in_image* starts) {
    ma->fixupAllChainedFixups(diag, starts, slide, dyld3::Array<const void*>(), nullptr);
});
diag.assertNoError();
```

So the first chained-fixup bind it meets has ordinal 0 against
`bindTargets.count() == 0` and **must** take the `out of range bind ordinal`
error arm at `MachOLoaded.cpp:1224` — the arm that was broken. Committed
(`72bb096663`), two defects:

1. `void* newValue;` was **never initialised**. Every error arm did
   `stop = true; break;` — and that `break` exits only the `switch`, so control
   fell through to `fixupLoc->raw64 = (uintptr_t)newValue;` with `newValue`
   holding an indeterminate value. An uninitialised store into the pointer slot
   being fixed up. Now `nullptr`.
2. Those four compiled error arms are now `return`, so a slot we failed to fix
   up is left alone rather than overwritten with a placeholder.

**NOT YET BUILT OR BOOTED** — the machine was held by the measurement boot for
the whole change. Verification owed: `build-libraries.sh dyld`, restage, boot,
and check both that `out of range bind ordinal` now surfaces and that the
loader stops jumping through `__got`.

### 42.5 The non-reproduction is EXPLAINED, not filed as flaky

§40.7 left the two failed re-boots unexplained. They are not flaky, and the
evidence is in the logs that were kept:

| run | outcome |
|---|---|
| `serial_ptwalk.log` | **`panic(cpu 0): random_init: failed to allocate a major number! @randomdev.c:106`**, immediately preceded by `ptmx_init: failed to obtain /dev/ptmx major number`, from `_bsd_rooted_ramdisk` |
| `serial_mapwalk.log` | no panic, but the loader never printed `DYLD-LOAD-BASE` |

⚠️ **CORRECTION — my first pass at this said "fixed-major collision", and that is
WRONG for both observation points.** I re-read the call sites instead of
trusting the summary I had written, and neither one uses a fixed major:

| site | call | what `cdevsw_isfree` actually does |
|---|---|---|
| `bsd/dev/random/randomdev.c:104` | `cdevsw_add(RANDOM_MAJOR, …)` and `randomdev.c:53` is **`#define RANDOM_MAJOR -1`** — *"let the kernel pick the device number"* | `index == -1` → **`index = 0`**, free-slot scan from 0. **Panics** on failure (`:106`) |
| `bsd/kern/tty_ptmx.c:205` and `:215` | `cdevsw_add(-15, …)` **twice** — once for `ptmx`, once for `ptsd` | `index = 15`, free-slot scan from 15. **Needs two slots.** On the *second* failure it rolls back with `cdevsw_remove` and prints **the same message as the first** (`:217`) |

**So the real mechanism is free-slot exhaustion, not a fixed-major collision —
and one exhaustion event inside `ptmx_init` alone produces two identical
`ptmx_init: failed to obtain /dev/ptmx major number` lines.** The two lines in
the log are not two independent failures, and "two independent failures in one
boot" (§42.5's original reading) was an artefact of a message reused for two
different conditions.

What survives from the original reading: it is still **two failures in one
boot**, still **not bad luck**, still **not memory pressure**, and still
upstream of the loader. §32.1's co-occurrence record stands — including a boot
that hit `pfinit`/`ptmx_init`/`random_init` together and produced no
signal-reason failure at all **because it never reached userspace**.

**So: the kernel died before userland, in a ravynOS-local cdev major-number
collision, for a reason that is upstream of the loader, the gate, the image and
the closure.** That is an explanation, not a consistency, and it is a blocker
for *reliable measurement* in its own right: it needs an owner, and it is
`bsd_stubs.c`, not anything in §40–§42.

### 42.6 ⛔ `cdevsw_add`: a measurement instrument with a fault in it — FULL CHARACTERISATION for an authorised owner

`bsd/kern/bsd_stubs.c` is **ravynOS's own, not upstream** (§32.1). Read-only
characterisation below; **I have not edited `Kernel/xnu` and this is not
authorised to me.** It is written up precisely so it can be handed to someone
who is.

**The mechanism, exactly.**

```c
int cdevsw_isfree(int index) {            // bsd_stubs.c:212
    if (index < 0) { ...free-slot search... }      // 216
    if (index < 0 || index >= nchrdev) return -1;  // 230
    devsw = &cdevsw[index];
    if ((memcmp(devsw, &nocdev, sizeof(cdevsw_t)) != 0))   // 235
        return -1;
    return index;
}

int cdevsw_add(int index, const cdevsw_t *csw) {  // :256
    lck_mtx_lock_spin(&devsw_lock_list_mtx);
    index = cdevsw_isfree(index);           // 259
    if (index < 0) index = -1; else cdevsw[index] = *csw;
    lck_mtx_unlock(&devsw_lock_list_mtx);
    return index;                           // bare -1, no reason
}
```

**Four defects, each visible in the code above, and one of them only bites on
the free-slot path — which is the path both observation points take (§42.5):**

1. **The "is it free" test is a whole-struct `memcmp` against `nocdev`** — a
   *pristine-slot* test, not an *is-this-major-claimed* test. Any non-zero byte
   anywhere in that `cdevsw_t`, written by anything, for any reason, makes the
   slot invisible to the scan **for the rest of the boot**. No re-check that the
   occupying entry is the same device, and no recovery. On the free-slot path
   (`index < 0`, lines 216-228) this means the scan at 224 skips such a slot
   silently and can run off the end of the table returning −1 with no record of
   where it stopped. *(For a genuinely fixed major — `index >= 0` — the same
   test is taken at 235 and returns −1 immediately. Neither observation point
   here is fixed; that path is a related hazard, not this failure.)*
2. **`cdevsw_add` returns a bare `-1` with no reason code.** The caller cannot
   distinguish *table full* from *this fixed major already taken* from *index
   out of range*. That is why the only diagnostic available is the generic
   `random_init: failed to allocate a major number` — and why identifying the
   two failures in one boot required reading them out of the serial log by hand.
3. ⛔ **`ptmx_init` reuses one message for two different conditions.**
   `tty_ptmx.c:206` prints it when the **first** `cdevsw_add(-15)` fails;
   `tty_ptmx.c:217` prints **the identical string** when the **second** one
   (for `ptsd`) fails, after rolling back the first. **A reader cannot tell
   which happened, and one exhaustion event produces two identical lines** — which
   is exactly how §42.5 first mis-read this as two independent failures.
4. ⛔ **`ptmx_init` needs two slots from the same start point and its comment
   disagrees with its code.** `tty_ptmx.c:200-202` says *"We start looking at
   slot 10"*, but both calls pass **`-15`**. The comment is stale, and the
   two-slot requirement is undocumented at the call site.
5. ⚠️ **The hazard is already documented in `bsd_stubs.c` and unfixed.**
   Lines 250-253, verbatim: *"-1 is unusable, since there are kernel internal
   devices that call this function with absolute index values, which will
   stomp on free-slot based assignments that happen before them. -24 is
   currently a safe starting point."* `ptmx_init` starting at 15 is a local
   workaround for precisely that, and `random_init` uses the very `-1` the
   comment calls unusable.
**Why the same kernel and image pass or fail.** Which slots the scans skip, and
in what order inits arrive, depends on allocation- and ASLR-dependent early-boot
ordering — so anything that perturbs layout changes who finds a free slot. The
image is identical; the winner is not. That is a mechanism, and it is why
§40.7's two divergent re-boots of one image are **explained** rather than merely
tolerated.

**What I did not establish, and a kernel owner will want it first:** *why* the
table has no all-zero slot from 15 (`ptmx`) and from 0 (`random`) at
`bsd_rooted_ramdisk` time. Candidates I can name but have **not** measured: a
slot left non-zero by a partial or rolled-back registration; `nchrdev` being
small relative to the number of devices ravynOS registers; or a registration
that writes a `cdevsw_t` and then mutates a field. **A single
`printf("%d: %d\n", cdevsw_isfree(i), i)` census of the table at
`bsd_rooted_ramdisk` time would settle it in one boot**, and I have not run it
because it needs a `Kernel/xnu` edit I am not authorised to make.

**Shape of a fix, for whoever owns it** — deliberately not implemented here:

* Test **device identity** (the `d_`-pointer set) rather than requiring the
  whole struct to be byte-zero, so a slot with a benign non-zero field is not
  treated as occupied.
* Return **distinct failures** for *already claimed* / *no free slot* / *out of
  range*, so the caller can name which. This alone would have made the 22:38
  investigation cheaper.
* Replace N inits independently scanning for slots with **one table built once**,
  so arrival order cannot decide an outcome, and give `ptmx_init` a documented
  two-slot reservation rather than two independent scans from the same start.

**Why this outranks a frontier advance this round.** A boot lab that
intermittently dies before userland is an instrument with a fault in it, and
every fault observed through it carries an extra branch: *was this the real
fault, or the `cdevsw` exhaustion?* §42's 509,976-fault storm was not
ambiguous, but the two prior runs were. **Naming this is worth more than the
frontier.**

---

## 43. ⚠️⚠️ CORRECTION — the "uninitialised write" was a SOURCE defect with **no runtime effect in this build**

§42.4 and commit `72bb096663` say the old `fixupAllChainedFixups` "stored an
indeterminate value into the pointer slot being fixed up", and offered that as
a mechanism for the frontier. **I checked the emitted code, and that is not
what this build does.**

**What the OLD binary actually does on the error path** — decoded, not
inferred:

```
00000000000497cc  leaq  0x7859f(%rip), %rsi   ## "out of range bind ordinal %d (max %lu)"
00000000000497d3  movb  $0x0, %al
00000000000497d5  callq __ZN11Diagnostics5errorEPKcz
00000000000497da  movq  -0x20(%rbp), %rax
00000000000497de  movb  $0x1, __framesize(%rax)     <- stop = true
00000000000497e1  jmp   0x4999a                     <- straight to the epilogue

000000000004999a  addq  $0x90, %rsp
00000000000499a1  popq  %rbp
00000000000499a2  retq
```

**The error arm jumps to the function epilogue. There is no
`fixupLoc->raw64 = newValue` on that path** — the optimiser had already deleted
the store, because `newValue` is uninitialised there and reading it is
undefined behaviour, so the compiler was entitled to drop the write entirely.

**So, precisely:**

* **The source defect is real.** `void* newValue;` is read uninitialised on
  every error path. That is undefined behaviour, and its consequences are
  whatever the optimiser decides — which is precisely why it must not be left
  in a fixup path.
* **The runtime consequence I claimed did not occur in this build.** No
  indeterminate value was stored, so the fix **does not** explain the unbound
  `__got` and **does not** explain the frontier. I said otherwise in a commit
  message; this section supersedes it.
* **The `break` → `return` change is a no-op at the machine level for these
  arms** — the compiler already produced a direct return. It makes the source
  say what it means and stops a future optimiser from deciding differently.

**Both changes are still correct and still worth keeping** — this project's own
rule is to eliminate the condition rather than test for it, and undefined
behaviour in a pointer-fixup routine is not something to leave in place on the
strength of "the optimiser happened to help". But they are **hygiene, not the
fix**, and no boot result should be read as confirming them.

**How it was caught, which is the reusable part:** the artifact's hash moved,
which proves nothing (§8e). What settled it was bounding the *function* by its
next symbol and reading the two epilogues. Three false starts got there first:
an `awk` that captured 123,492 instructions instead of one function; a
disassembly count of **0 instructions for both binaries** — the §32.8 vacuous
match, which would have read as "identical" and confirmed nothing; and a
grep for the store that returned 0 *because the store is not there*, which is
the one result that actually meant something. **Every one of those four reads
was compatible with "the fix changed nothing", and only the last was
distinguishing.**

---

## 44. ✅ THE `fixupAllChainedFixups` FIX IS BUILT, BOOTED, AND **BEHAVIOUR-NEUTRAL** — the debt is paid

`run_gated_loader.sh ../../Libraries/dyld/dyld/dyld FIXUPGUARD 200`, the
project's own path, which also does the `pgrep` refusal, the backup, the
`mkimage` verify and the copy-aside of the QEMU log. **I should have used it
earlier instead of hand-rolling a boot; it encodes every discipline in this
document and I re-derived most of them badly.**

### 44.1 Provenance, all of it checked

| item | value |
|---|---|
| loader built | `39e5384831ad22810cec713df29171d1` (1,733,184 B) |
| staged `assets/usr/lib/dyld` | same hash; `dyld.PREV-FIXUPGUARD` keeps the previous one |
| whole-file in image | **all 1,733,184 bytes at offset 44,963,840, sha256 identical** — the new `run_gated_loader.sh` control, *and* re-verified independently |
| mkimage | `verify OK: 61 files, 75 tree entries, all content hashes match` |
| kernel payload | `25abd69f88ddda10…` (20,043,504 B), recorded by the script |
| QEMU log | `work/qemu_FIXUPGUARD.log`, 5,072,791,805 B, copied aside by the script |
| serial | `work/serial_dynamic.FIXUPGUARD.log`, 620 lines, 0 panics, 0 alive ticks |

⚠️ **Cross-run kernel attribution is still impossible and I am not claiming it.**
This run's kernel is recorded (`25abd69f`); §35.3 established the 22:38 run's
kernel payload no longer exists on disk. The *loader* attribution is airtight in
both runs (whole-file, both directions); the *kernel* is only pinned for this
one.

### 44.2 The anchor I lost last time, recovered

```
DYLD-LOAD-BASE: 0x10faab000
```

so `&_mach_task_self_` = `0x10faab000 + 0x10feb4` = **`0x10FBBAEB4`** — and the
terminal record's `EAX` is `0x10fbbaeb4`, **to the byte**. The §40 signature is
confirmed against an anchor rather than inferred.

### 44.3 Result: the fault is UNCHANGED, and that is the result

```
85,262,499 exception records:  36 at CPL=3,  3,875,527 at CPL=0

CPL=3 v/e:  v=0e e=0014 x 20    v=0e e=0004 x 9    v=dd x 5
            v=0e e=0007 x 1     v=0d e=0000 x 1

 39183: v=0e e=0004 cpl=3 IP=002b:000000010fb5678f CR2=000000010fbbaeb4   offset 0xab78f
 39184: v=dd e=0000 cpl=3 IP=002b:000000010fb56794   EAX=0                  offset 0xab794
 39186: v=0d e=0000 cpl=3 IP=002b:8010000000000001   EAX=0
```

36 CPL=3 records against the 22:38 run's **38**, the same five categories in the
same proportions, and the **terminal event byte-identical**: `#GP` with
`RIP = 0x8010000000000001` at CPL=3. Anchored offsets reproduce §40.1's list —
`0x9aa30` start, `0xa0a30/34` minimal TSD, `0x43f50`/`0x440d0`/`0x440f8` the
load-command walk, `0x46220` `hasChainedFixups`, `0x3e560` `withChainStarts`,
`0x48390` `getLinkEditContent`, **`0x49480` `fixupAllChainedFixups`** (matches
`nm` exactly), `0x49aef` `walkChain`, `0xaa6e0`/`0xab6e0`/`0xaa79f`/`0xabfe9`/
`0xc1104` the simple print path, and **`0xab78f` the gate**.

**So the UB fix changed nothing observable — exactly as §43 predicts it would,
and as the decoded epilogue said it would.** The frontier is unmoved, the fix is
verified not to regress anything, and the two are now separated.

⚠️ **One genuine difference, stated without over-reading it:** this run has an
extra `#GP` at offset `0xab794`, which falls **inside the displacement bytes of
the gate's `jne`** (`0xab793: 75 21`). A `#GP` decoded from the middle of a
branch means control did not arrive from `0xab78f` — a bad indirect jump
somewhere. I have **not** attributed it beyond that, and I am **not** reporting
symbol names from a symbolizer that returned the same wrong name for every
address.

### 44.4 What this settles about the guard

The guard (`Libraries/dyld/src/dyldInitialization.cpp`, landed in `7681647da6`)
is **still unbuilt**, and its bit test is validated against the real data:
of the 15 `__got` slots it would report **13 unbound**, correctly not counting
the 2 rebases, and correctly not counting a resolved value. When built it will
turn "starts, then dies at whichever stub fires first" into "refuses to start,
having said `chained fixups left 13 of 15 bind slots unbound`". **That message
is the whole point**, and it is the number a reader of this plan has been
missing since §33.

---

## 45. The guard is **compiled and in the binary** — and its boot is the measurement that says **the walk visits nothing**

### 45.1 The guard did not compile, and that is why it was landed unbuilt the first time

`bb58334494`. One real error:

```
dyldInitialization.cpp:142:55: error: use of undeclared identifier 'MachOLoaded';
                                         did you mean 'dyld3::MachOLoaded'?
```

Qualified, rebuilt, and the guard is now provably **in the artifact** rather than
merely in the source:

| | size | sha256 | guard string present? |
|---|---|---|---|
| built (with guard) | 1,737,704 B | `1d47e8c543cbccb3cd6d8d1166e3febf` | **YES** |
| staged (pre-guard) | 1,733,184 B | `39e5384831ad22810cec713d` | **no (0)** — negative control |

### 45.2 The boot: NEITHER message appears, and that is the result

`run_gated_loader.sh ../../Libraries/dyld/dyld/dyld BINDBINDGUARD 240`, window
240 against a 900 s harness timeout so the serial log was written. Base
`0x10c48e000`, 620 lines, 0 panics, 0 alive ticks, QEMU log 6,448,590,748 B.

```
grep 'out of range bind ordinal\|bind slots unbound\|DYLD-LOAD-BASE' serial
  614: DYLD-LOAD-BASE: 0x10c48e000
  (the other two: ABSENT)
```

**That is a positive measurement, not an absence of evidence:**

1. `fixupAllChainedFixups` is called with an **empty** `bindTargets`, so the
   first bind it meets **must** take the `out of range bind ordinal` arm
   (`MachOLoaded.cpp:1224`). It did not. **So the walk never reached the `__got`
   binds.**
2. The guard re-walks the same chains and counts slots still carrying the bind
   bit. It reported **zero** — not "13", not "0 of 0", nothing. **So the
   re-walk found no bind slots either.**

Both point the same way, and it is the conclusion §40.5 got *accidentally right
by the wrong method*: **`forEachFixupInAllChains` visits nothing at runtime**,
even though `dyld_info` shows the chain starts fully populated in the file. The
loader walks every chain to completion, reports `noError`, and has bound nothing
because it was never pointed at anything.

### 45.3 The three places I could check are all correct — and one I could not find

| place | verdict |
|---|---|
| `MachOAnalyzer::withChainStarts:3293-3294` | **correct** — reads the `dyld_chained_fixups_header` and steps by `header->starts_offset` |
| `MachOLoaded::getLinkEditContent:423-425` | **correct** — takes a *file* offset, subtracts `linkeditFileOffset`, adds `linkeditUnslidVMAddr + slide` |
| `MachOLoaded::walkChain:1284` | **correct** — `this + segInfo->segment_offset + pageIndex * page_size` |

⚠️ I formed a hypothesis that `getLinkEditContent` was doing the *same*
file-offset mistake I had made in my own parser, and **it does not.** Recorded
because I nearly let "it is exactly the bug I made" stand in for a check.

**The one thing I could not answer: where `leInfo.chainedFixups` is assigned.**
`grep 'chainedFixups\s*='` over `MachOAnalyzer.cpp` returns **nothing** — every
hit is a *use*. `withChainStarts` invokes its callback only
`if ( leInfo.chainedFixups != nullptr )` (`:3291`), so **a null there means the
callback never fires, `fixupAllChainedFixups` is never called, the guard's
re-walk never runs, and not one diagnostic is produced** — which is precisely
what §45.2 observed.

**And it is consistent with `hasChainedFixups()` being true** (§33.1 saw it in
the trace): that is a *different* function, implemented with
`hasLoadCommand(LC_DYLD_CHAINED_FIXUPS)`, so it and `leInfo.chainedFixups` can
disagree.

**This is a hypothesis and I am labelling it one.** A failed `grep` is not proof
of absence — §34.6 is the standing example in this document of concluding
"absent" from a pattern that did not match. **The next check is one grep of
`getLinkEditPointers`'s load-command loop**, and nothing should be edited until
it is read. If `chainedFixups` is genuinely never assigned, the fix is one
assignment in that loop, and it would explain the entire frontier: a loader that
rebases nothing, binds nothing, and says `noError` while its `__stubs` jump at
raw literals.

---

## 46. ✅ THE CAUSAL CHAIN, CLOSED END TO END — and two diagnostic defects that hid it

### 46.1 What the boot actually proved

The probe (`CHAINPROBE`, kept per instruction) printed:

```
DYLD-LOAD-BASE: 0x113ea7000
CHAINPROBE: block FIRED, starts=0x113fb9020 seg_count=4 off0=#x off1=#x off2=#x off3=#x
```

* **The block FIRED** — `leInfo.chainedFixups` is **not** null. §45.3's
  hypothesis is **REFUTED**, and the reason the grep found no assignment is now
  known: the assignment is `MachOLoaded.cpp:88`,
  `result.chainedFixups = (linkedit_data_command*)cmd;`, inside
  `getLinkEditLoadCommands`, reached via `getLinkEditPointers` (`:177`→`:179`).
  **My grep searched only `MachOAnalyzer.cpp`.** §8f's trap, verbatim: *a missing
  path in your own search list is indistinguishable from a missing file in the
  tree.* §34.6 was the same mistake with `macho_load.c`.
* `starts − base = 0x112020` = `__LINKEDIT` `0x111000` + `starts_offset` `0x20`.
  So `getLinkEditContent` and `withChainStarts` are both **correct**.
* `seg_count = 4` at runtime, matching the file.

And the anchored fingerprint says the walk **does** reach the binds:

| offset | what |
|---|---|
| `0x49aef` | `walkChain` — the walk is running |
| `0x49978` | `fixupAllChainedFixups` — taking an error arm |
| `0xaba7f` | `__simple_salloc` — **allocating in order to format the message** |
| — | `#GP` at `0x8010000000000001` |

### 46.2 The chain

`rebaseDyld` passes an **empty** `bindTargets` → the walk reaches `__got[0]`,
ordinal 0, and `0 >= 0` → takes the `out of range bind ordinal` arm →
`diag.error` formats into `_buffer` **through `_simple_salloc`** → that
allocation crosses the `__simple_salloc` gate to
`__kernelrpc_mach_vm_allocate_trap`, **through `__stubs[1]`** → `__got[1]` is
still the raw descriptor `0x8010000000000001` → non-canonical → **`#GP`**.
`diag.assertNoError()` is never reached.

> **The first thing that would have reported the fault is killed by the fault.
> A check that cannot fail cannot report either.**

### 46.3 ⛔ DEFECT ONE: `_simple_sprintf` has no flag handling, and renders unsupported flags as literal text

`Libraries/Libsystem/libsystem_platform/simple/string_io.c:332` switches on
**ONE character** after `%`. `'0'`–`'9'` are **width** digits (333, 337-341),
and the `default` arm at **434** does `put_c(b, esc, *fmt)` — it **prints the
character literally and continues**.

So **`%#x` emits the two characters `#x`.** That is not a probe artifact: my own
probe printed `off0=#x` and I nearly read `#x` as a value. Supported and safe:
`%c %d %i %o %p %s %u %x %X %l %y`. **`%#` is unusable, and the failure is
silent** — no error, no marker, just text that looks like a formatted number.

This is the **second** instance in this workstream of a formatter that cannot
express the thing rendering something that looks like a value. The first was
§36.3's `__framesize` placeholder. **Both times the instrument lied in the same
direction: it produced a plausible token instead of admitting ignorance.**

### 46.4 ⛔ DEFECT TWO: `Diagnostics::error` prints nothing in a non-cache-builder build

`Libraries/dyld/dyld3/Diagnostics.cpp:86-103`:

```c
void Diagnostics::error(const char* format, va_list list)
{
    //FIXME: this should be assertNoError(), but we currently overwrite some errors
    //assertNoError();
    _buffer = _simple_salloc();
    _simple_vsprintf(_buffer, format, list);
#if BUILDING_CACHE_BUILDER          // <-- the ONLY place it prints
    if ( !_verbose ) return;
    fprintf(stderr, "%s", _simple_string(_buffer));
#endif
}
```

**In the dyld tool build the `fprintf` is compiled out.** Every `diag.error`
records into `_buffer` and prints **nothing**. So a missing message on the
serial log is **not** evidence the code did not run — which is exactly how §45.2
reasoned, and §45.2 was wrong *for the wrong reason* even though its conclusion
turned out to hold.

**This is a diagnostic compiled out in the configuration that needs it** — the
same class as the empty export trie and `rc=0` by default.

### 46.5 The fix: report the bind failure WITHOUT allocating

`MachOLoaded.cpp` now calls `reportUnbindableBind()` **before** `diag.error()` on
both 64-bit arms. `_simple_dprintf` formats into a **stack buffer** and
`write(2)`s the result — no heap — which is why `DYLD-LOAD-BASE` prints from the
same binary at the same early moment. If `diag.error` then dies in
`_simple_salloc`, the diagnosis is already on the console.

```
dyld: UNBINDABLE chained fixup: bind ordinal %u is out of range,
      bindTargets.count() is %u, fixups walked so far %u. The slot is left as a
      raw bind descriptor and the __stubs through it will NOT resolve.
```

Plain conversions only, deliberately — §46.3 says why. `fixupsSeen` is counted
in the lambda so the message can say how far the walk got. `#include <_simple.h>`
is the same include `Loading.h:32` uses; `Libsystem/private` is already on this
target's include path and **was not modified**.

⚠️ **UNBUILT-TILL-BOOTED and then UNCOMMITTED** — see §46.6.

### 46.6 The three fix shapes, and which one I took

The brief preferred the non-allocating report; **I agree, and here is why it is
the right one rather than merely the chosen one.** The other two shapes —
removing the bootstrap's own imports from `__stubs`, or teaching the loader to
bind its own `__got` first — both make the *bind succeed*. That is a better
ending, but it is an ending we would reach **without knowing the ordinal or the
count**, and this loader has now failed silently for a long time. The
non-allocating report converts a fatal `#GP` into a **legible diagnosis in one
boot**, and the next move then follows from evidence instead of inference.

The general lesson is §46.4's: **"the error path allocated" is the lesson; this
is only its first instance.**

### 46.7 State

Built via `tools/bootlab/build-libraries.sh dyld`; only the two known
`libslc_builder` errors remain (separate target, separate configuration,
neither error file in my diff). Artifact `1c42db880a74e25d597bcb40e3e095df`,
1,737,640 B. `UNBINDABLE` present in the new build and **absent (0)** from the
staged one; `CHAINPROBE` kept in both, 3 each, as instructed.

**Left uncommitted and unstaged on purpose** — a parallel untrack-and-commit
workstream is running and must not collide with this one.

---

## 47. ✅ THE NON-ALLOCATING REPORT WORKS — the fatal `#GP` is now a legible diagnosis in one boot

`run_gated_loader.sh … NOALLOC 240`, artifact `1c42db880a74e25d597bcb40e3e095df`.
Serial log 623 lines (three more than before), 0 panics, 0 alive ticks.

```
614: DYLD-LOAD-BASE: 0x10c4c7000
620: CHAINPROBE: block FIRED, starts=0x10c5d9020 seg_count=4 off0=#x ...
623: dyld: UNBINDABLE chained fixup: bind ordinal 0 is out of range,
     bindTargets.count() is 0, fixups walked so far 4. The slot is left as a
     raw bind descriptor and the __stubs through it will NOT resolve.
```

**The two numbers the brief asked for, measured:**

* **`bindTargets.count()` is 0** — exactly the empty
  `dyld3::Array<const void*>()` that `dyldInitialization.cpp:123` passes. Not
  inferred; printed.
* **`bind ordinal 0`** — the first bind in the chain, i.e. the first `__got`
  slot that is a bind at all.

### 47.1 The `__got`, re-read at its **current** address

⚠️ **`__got` MOVED between builds: `0xd5000` → `0xd6000`.** I dumped the old
address and briefly concluded all 15 slots were rebases. That was **my
instrument reading a stale offset**, and I only caught it because the boot
message said *bind ordinal 0* and the file said otherwise. Re-read at
`0xd6000`:

```
[ 0] 0x00100000000da760  rebase      <- slide-baked
[ 1] 0x00100000000b98f0  rebase      <- slide-baked
[ 2] 0x8010000000000000  BIND ordinal 0
 …
[14] 0x804000000000000c  BIND ordinal 12
-> 13 bind slots of 15
```

**13 binds, ordinals 0–12 — the 13 flat-namespace imports.** Two rebases first,
then the binds. The chain is exactly what `dyld_info` said it was.

### 47.2 ⚠️ My own counter was wrong, and the arithmetic caught it

The boot printed *"fixups walked so far 4"*. The `__got` shows **two** rebases
then the failing bind, so the truth is **3 walked, the third being the bind**. My
error arm did `++fixupsSeen` *in addition to* the increment at the top of the
block, double-counting the current fixup.

**This is the project's own lesson, applied to my own instrument:** a number
that is off by one is worse than no number, because it is trusted. Corrected in
both arms with a comment saying why, rebuilt (`d3459f0d85004b0002cc7cbd52969e58`),
and re-booted as `NOALLOC2` to measure the corrected value rather than assert it.

### 47.3 What the next move now is, from evidence rather than inference

`bindTargets.count() == 0` is not a mystery any more; it is a **printed value at
the point of failure**. So the choice the brief deferred is now decidable on
data:

* The loader has **no binding mechanism at all** in its own image — no
  `LC_LOAD_DYLIB`, no `LC_DYLD_CHAINED_IMPORTS`, no `LC_DYLD_INFO_ONLY`. There
  is nothing that *can* supply 13 flat-namespace targets to a dylinker.
* So either the bootstrap must **not need them** (resolve its own imports without
  a `__got`/stub, or without the flat-namespace imports at all), or the linker
  must be given a reason to emit a real bind target.

**Either way the diagnosis is now one boot away from being a fix**, which is
what the non-allocating report was for.

### 47.4 Still open, and it is the general defect

`Diagnostics::error` prints nothing in a non-cache-builder build (§46.4). This
round worked around it rather than fixing it, because the workaround is local
and provably allocation-free. **The general fix — make `Diagnostics::error`
report in the configuration that needs it — is untouched**, and it is the same
class as the empty export trie. It should not stay a workaround.

### 47.5 ✅ The corrected counter is now MEASURED, and it agrees with the `__got`

`NOALLOC2` never reached the loader — 239 lines, no `DYLD-LOAD-BASE`, QEMU log
2.4 MB against 7.7 GB, ending in `!!!! Can't find image information. !!!!` at
the firmware handoff. **That run tested nothing**, and I am not counting it.
(One more instance of the boot being unreliable for reasons unrelated to the
loader; see §42.6 for the `cdevsw` half of that story, and note this one is at
the *firmware* handoff, before any kernel code.)

`NOALLOC3` retried it, artifact `d3459f0d85004b0002cc7cbd52969e58`, 623 lines:

```
dyld: UNBINDABLE chained fixup: bind ordinal 0 is out of range,
     bindTargets.count() is 0, fixups walked so far 3.
```

**`3`, not the `4` the over-counting build printed** — and `3` is what the
`__got` says it must be: `__got[0]` and `__got[1]` are the two slide-baked
rebases, `__got[2]` is the first bind (ordinal 0), so the third fixup walked is
the one that fails. **The instrument and the file agree**, which is the only
reason to believe the number.

### 47.6 The measurement, complete

| what the brief asked for | measured value | where |
|---|---|---|
| the exact ordinal | **0** | printed at the point of failure |
| `bindTargets.count()` | **0** | printed at the point of failure |
| how far the walk got | **3** fixups, the 3rd being the failing bind | printed, and confirmed against the `__got` |

**The fatal `#GP` at a non-canonical literal is now a legible line on the serial
console, in one boot.** That was the point of the non-allocating report, and it
is delivered.

**Two things remain, and neither is the diagnosis any more:**

1. **The actual fix.** `bindTargets.count() == 0` is now a printed fact, so the
   choice is decidable on data: the loader has no binding mechanism in its own
   image, so the bootstrap must either stop needing a `__got`/stub for its own
   imports, or the link must be given a reason to emit real bind targets.
2. **`Diagnostics::error` still prints nothing** in a non-cache-builder build
   (§46.4). This round worked around it; the general defect is untouched and
   should not stay a workaround.

---

## 48. The deciding question: what are the 13 imports, and what *should* resolve each?

Answered **before** any code change, by measuring. Two facts from the link line
decide the shape:

* `-Wl,-undefined,dynamic_lookup` **is on the dyld link line.** The link was
  *told* to tolerate undefined symbols. For a dylinker that is normally correct,
  because the intended satisfier is the **lazy `dyld_stub_binder`**.
* **The stubs emitted are direct `jmpq *GOT[k]` — non-lazy.** So the binder never
  runs, nothing binds the `__got`, and the loader falls through to a chained-fixup
  bind it has no targets for.

**That is a link-shape defect, and it is upstream of the loader's fixup code.**

### 48.1 Classification of all 13, measured

Linked libraries on the line: `-lc -lpthread -lplatform -lCrashReporterClient
-lunwind -lc++ -lc++abi -lkernel -lSystem`.

| ord | symbol | what should resolve it | measured |
|---|---|---|---|
| 1 | `___kernelrpc_mach_vm_allocate_trap` | **a direct trap** | `string_io.c:542` declares it `extern` and **calls it as an ordinary function**. Not a macro, not a `syscall` inline, anywhere in the tree. The comment at `:500` says *"No new syscall plumbing"* — that is the decision that created the import. |
| 3 | `___shared_region_map_and_slide_np` | **a direct trap** | same MIG family, same shape; defined in no linked library |
| 5 | `_mach_msg2` | **a direct trap** | MIG trap name; defined in no linked library |
| 6 | `_pthread_rwlock_rdlock$UNIX2003` | **a versioning bug in `libpthread.a`** | the archive **does** define `_pthread_rwlock_rdlock` — **without** the `$UNIX2003` suffix |
| 7 | `_pthread_rwlock_unlock$UNIX2003` | same | archive defines `_pthread_rwlock_unlock`, unsuffixed |
| 8 | `_pthread_rwlock_wrlock$UNIX2003` | same | archive defines `_pthread_rwlock_wrlock`, unsuffixed |
| 11 | `_voucher_mach_msg_fill_aux` | **a library that was not linked** | defined in `libsystem_kernel.dylib`; the line has `-lkernel` → `usr/local/lib/kernel/libkernel.a`, a *different* library |
| 12 | `_voucher_mach_msg_fill_aux_supported` | same | same |
| 0 | `____chkstk_darwin` | dylinker-internal / wrong archive | defined in `libsystem_pthread.dylib`; the line links `usr/local/lib/dyld/libpthread.a` instead |
| 2 | `___libunwind_Registers_x86_64_jumpto` | dylinker-internal | `-lunwind` **is** on the line and supplies neither this nor ord 4 |
| 4 | `___unw_getcontext` | dylinker-internal | same |
| 9 | `_system_version_compat_check_path_suffix` | dylinker-internal | defined in no linked library |
| 10 | `_system_version_compat_open_shim` | dylinker-internal | same |

**Buckets:**

* **3 should not be imports at all** (1, 3, 5) — MIG/kernel traps that a
  dylinker must issue, not call.
* **3 are a symbol-versioning bug in `libpthread.a`** (6, 7, 8) — the definitions
  exist, unsuffixed. **This is a defect in a library, not in the loader**, and it
  alone accounts for three of the thirteen.
* **2 are a library that was not linked** (11, 12).
* **5 are genuinely "the dylinker must resolve this for itself"** (0, 2, 4, 9, 10).

### 48.2 The expectation is CONFIRMED, and sharpened

*"A dylinker at `rebaseDyld` has no business binding its own imports, and most of
these 13 should not exist."*

**Confirmed.** Of 13: **3 must not be imports at all**, **3 are a versioning bug
in a library we built**, **2 are a library we simply did not link**, leaving
**5** that are genuinely the dylinker's own to resolve.

**So the fix is in the link, not in the loader** — the same class as the earlier
defect where a sub-dylib was linked against a zero-export `libSystem` stub: **a
link that should never have been asked to succeed, and did.**

### 48.3 What I did NOT do

**No code change this section.** The brief asked for the classification before
any code change, so the two `reportUnbindableBind`/guard edits and the
`CHAINPROBE` instrumentation stand exactly as they were when the diagnosis was
measured, and the non-allocating report is what made this classification
possible to reach in one boot.

⚠️ One instrument caveat, stated rather than smoothed: the first pass of the
provider census reported the `pthread_rwlock` trio as "NOT DEFINED", because it
matched bare names. Re-running `nm -gjU` on the **linked** `libpthread.a` and
grepping for the unsuffixed forms found all three. **The first answer was a false
negative produced by a probe that could not express the thing it was looking
for** — §38.8's shape, and the reason I re-ran it instead of reporting it.

---

## 49. ⚠️ `-fixup_chains` TESTED: removing it does **not** yield lazy stubs — it **crashes ld64**

### 49.1 BEFORE — the stub bytes, which are the evidence

`__stubs` @ `0xc178a`, 66 bytes, **11 stubs of 6**:

```
stub[0] ff 25 80 48 01 00
stub[1] ff 25 82 48 01 00
stub[2] ff 25 84 48 01 00
stub[3] ff 25 86 48 01 00
```

`ff 25` = **`jmpq *disp(%rip)`** — direct, through the `__got`. **Not lazy.**

And the stronger half: **`_dyld_stub_binder` is not in the image at all**
(`nm` returns nothing). The lazy mechanism is not merely unused here — **it is
absent**, while `-Wl,-undefined,dynamic_lookup` is on the link line and is
*correct* for a dylinker. The link was told "these may be undefined; something
will bind them at runtime", and **nothing in the image can.**

### 49.2 The test, and what it actually did

`-Wl,-fixup_chains` removed from **`Libraries/dyld/dyld/Makefile:117`** — the
MH_DYLINKER tool's own `LDFLAGS` — and rebuilt.

**`ld64` SEGFAULTED.** The last thing it printed was a degenerate section table:

```
__la_symbol_ptr  addr=0x000000000, size=0x000000000, fileOffset=0x00000000
__LINKEDIT       addr=0x000000000, size=0x000000000, fileSize=0x00000000
clang: error: unable to execute command: Segmentation fault: 11
```

So without the flag ld64 produced **`__la_symbol_ptr` with size 0** — *no lazy
symbols* — and then died on a zero-sized `__LINKEDIT`.

**The hypothesis is REFUTED in its actionable form.** Removing `-fixup_chains`
from this link does not give lazy stubs. **It gives a crashed linker.** The flag
is **load-bearing for this dylinker link to produce a binary at all** — which is
a different and stronger claim than "it converted the stubs".

### 49.3 The conflict is real, and there were **two** flags decided in two places

* `Libraries/dyld/Makefile:284` — `-Wl,-fixup_chains` on the **`libdyld.dylib`**
  link (`-shared -dylib`, install_name `/usr/lib/system/libdyld.dylib`). **This
  is the one it was adopted for**: without it the link emits legacy
  `LC_DYLD_INFO_ONLY` and no `LC_DYLD_EXPORTS_TRIE` (measured, lines 253-256).
* `Libraries/dyld/dyld/Makefile:117` — `-Wl,-fixup_chains` on the
  **`MH_DYLINKER` tool** link.

**They are separate `LDFLAGS`, so the export trie and the stub shape never had to
trade off.** They were adopted in different rounds, for different reasons, in
different files, and **nobody connected them** until a boot proved the conflict.
That is the design constraint worth writing down, and it is not the one the
hypothesis assumed.

**Which means option (a) — "bind its own `__got` in `rebaseDyld` from a real
target list" — is not forced by this test.** §48 already measured that **10 of
the 13 imports are eliminable without any new binding mechanism**: 3 must be
traps, 3 are a symbol-versioning bug in `libpthread.a`, 2 are a library that was
not linked. Only 5 are genuinely the dylinker's own to resolve.

**So the evidence points at the other option: carry no external imports at all
in the bootstrap path**, because most of these 13 were never supposed to exist.

### 49.4 Two process findings I owe

* **`Libraries/dyld/dyld/Makefile` is NOT tracked by git.** `git checkout --` on
  it fails with *"pathspec did not match any file(s) known to git"*. My earlier
  claim that everything I touch is path-scoped-and-revertible was **wrong for
  this file**. Reverted by hand, line 117 restored, and verified.
* **A failed dylinker link DELETES the last good loader.** The link removed
  `Libraries/dyld/dyld/dyld` before it crashed, so the artifact was gone until I
  rebuilt. Rebuilt and verified: 1,737,640 B, `UNBINDABLE` present, `CHAINPROBE`
  ×3, `-Wl,-fixup_chains` and `-Wl,-undefined,dynamic_lookup` both back on the
  link line, and `__stubs` back to `ff 25 80 48 01 00`. **Any future experiment
+  that edits this link should copy the artifact first** — a green link is not the
  only way to lose it.

---

## 50. Eliminating the 13 imports: the instrument, the baseline, and what is actually tractable

### 50.1 The instrument, and why it re-locates `__got` every time

`/tmp/gotdump.py`. **`__got` has moved once already (0xd5000 → 0xd6000) and a
hard-coded offset is an instrument that lies.** It locates `__got` through
`dyld_info -segments` on every run and **cross-checks the bind count against
`dyld_info -imports`**, a second method.

Control, on two loaders known to differ:

| loader | `__got` | slots | BIND slots | `dyld_info -imports` |
|---|---|---|---|---|
| `dyld.PRE-SALLOC-GATE` | **0xd5000** | 14 | **12**, ordinals 0–11 | 12 |
| `dyld` | **0xd6000** | 15 | **13**, ordinals 0–12 | 13 |

Two different addresses, two different answers, and the two independent methods
agree in both cases. **A comparison that can return "different" on the same
input.** (An earlier ad-hoc version mis-indexed `dyld_info`'s columns and
reported "not found" — the control is what caught it.)

**BASELINE: `__got` @ 0xd6000, 15 slots, 13 binds, ordinals 0–12, plus 2
slide-baked rebases at slots 0 and 1.**

### 50.2 Category 1 — the 3 "should be traps" — tractability, measured

| ord | symbol | call sites in `Libraries/dyld` + `Libraries/Libsystem` |
|---|---|---|
| 1 | `___kernelrpc_mach_vm_allocate_trap` | **exactly one** — `libsystem_platform/simple/string_io.c:542`, declared `extern` and called as a function |
| 3 | `___shared_region_map_and_slide_np` | **exactly one** — `dyld3/SharedCacheRuntime.cpp:587` |
| 5 | `_mach_msg2` | **ZERO** |

⚠️ **`_mach_msg2` is not the loader's own import at all.** Nothing in
`Libraries/dyld` or `Libraries/Libsystem` references it, so it is pulled in by a
**linked archive** (`libc++`, `libunwind`, `libSystem`, …). **That is a different
defect with a different fix** and it does not belong in the "the dylinker should
not import this" bucket — it belongs in "an archive we link drags in a Mach
dependency". Chasing it as a dylinker-trap problem would be the wrong work.

The other two are genuinely one call site each, so both are tractable — but both
require writing real syscall traps (kernel ABI, and the number has to be right),
which is **not** a change to make without a boot to verify it.

### 50.3 Category 2 — the 2 vouchers — **NOT fixable by linking**, and now we know why

`-lsystem_kernel` on the tool link fails: **`ld: library 'system_kernel' not
found`**. The reason is structural:

* The `MH_DYLINKER` tool link carries **`-Wl,-static`**, so it can only take
  **`.a`** files. `-lCrashReporterClient` works precisely because
  `usr/lib/system/libCrashReporterClient.a` **exists**.
* **`usr/lib/system` contains exactly three static archives**: `libCrashReporterClient.a`,
  `libdyld.a`, `libutil.a`.
* **`libsystem_kernel` has no `.a` at all** — only a `.dylib`, and a `-static`
  link will not take it.

So the two voucher imports cannot be removed by adding a library. The routes are
**build `libsystem_kernel` as a static archive**, or provide the two symbols
locally — and the latter is a stub, which is the defect class this project exists
to eliminate. **This is the same constraint the plan already records for
`libCrashReporterClient.a`.** *(The failed link deleted the artifact again; the
copy-first rule below is what saved it.)*

### 50.4 Category 3 — the 3 `$UNIX2003` — the archive has **no versioning at all**

```
nm $SDK/usr/local/lib/dyld/libpthread.a | grep -c UNIX2003   ->  0
nm ... | grep rwlock_rdlock                                  ->  T _pthread_rwlock_rdlock
```

**`libpthread.a` carries zero versioned symbols.** The definitions exist, unsuffixed.
So this is not "the archive is missing them" — it is **the archive and the loader
disagree about symbol naming**, and which side is wrong is a question about how
`libpthread.a` was built versus how the loader's TUs see the headers. **I have
not established which side is wrong, and I am not going to pick one by guessing.**

### 50.5 Two process debts, acted on

1. ⛔ **The `MH_DYLINKER` link line is UNTRACKED and therefore unversioned.**
   `Libraries/dyld/dyld/Makefile` is not in git (`git ls-files` is empty for it;
   `git checkout --` on it fails). **A 1.7 MB loader whose link recipe exists
   nowhere in history is a real fragility.** Staging it was not permitted this
   round, so this is recorded here instead: **whoever next has a window should
   `git add Libraries/dyld/dyld/Makefile`**, because §49's whole result — that
   `-fixup_chains` is load-bearing for this link — is only reproducible from an
   unversioned file.
2. ✅ **Copy the artifact before any link experiment, every time.** A **green**
   link is not the only way to lose the working binary — a *failed* one deletes
   it, because ld64 removes the output before it dies. This happened twice
   (§49.2 and §50.3). The rule was followed from the second occurrence onward:
   `cp Libraries/dyld/dyld/dyld /tmp/dyld.ARTIFACT.BACKUP` before the voucher
   link, which is the only reason the artifact survived it.

### 50.6 State after this round

Restored and **verified**: `Libraries/dyld/dyld/dyld`, 1,737,640 B, `__got`
@ 0xd6000 / 15 slots / **13 binds, ordinals 0–12**, agreeing with
`dyld_info -imports`; `UNBINDABLE` reporter present, `CHAINPROBE` ×3 kept, and
`-Wl,-fixup_chains` and `-Wl,-undefined,dynamic_lookup` both back on the link
line. `Libraries/dyld/dyld/Makefile` line 125 restored to
`-lCrashReporterClient` with no `-lsystem_kernel`.

**Net: 0 of the 13 eliminated.** The work produced the instrument, the baseline,
and — more usefully — the finding that **two of the three categories are not what
they look like**: `_mach_msg2` is not the loader's import at all, and the
vouchers cannot be fixed by linking because the dylinker link is static and
`libsystem_kernel` has no archive.

---

## 51. Five items: what landed, what did not, and one claim of mine that was false

### 51.1 ⛔ Item 0 is VOID — the `MH_DYLINKER` link recipe was never untracked

I reported in §49.4 and §50.5 that `Libraries/dyld/dyld/Makefile` is **not in
git** and that "a 1.7 MB loader whose link recipe exists nowhere in history is a
real fragility". **That is false.**

```
$ git ls-files | grep -i 'dyld/dyld/makefile'
Libraries/dyld/dyld/makefile
```

**It is tracked — under a lower-case name.** I searched with
`git ls-files Libraries/dyld/dyld/Makefile` (capital `M`), got nothing, and
concluded "untracked". The working copy is **clean** against the commit, and the
file has been in history since *The Great Migration*. **There is nothing to
stage, and the fragility I described does not exist.**

⚠️ **This is the FOURTH time this session that a false claim of mine came from a
search that could not express what it was looking for.** The others: `_mach_msg2`
"zero call sites" when it is dragged in by an archive; `%#x` printing as `#x`;
and §40.5's empty chain-starts. **In every case the instrument returned a clean,
confident, wrong answer rather than an obvious failure.** The defences that
worked were all *controls* — a second method, a known-different input, or a boot
that contradicted the file — never more careful grepping.

### 51.2 ✅ Item 2 LANDED, and it is in the artifact

`Libraries/dyld/dyld3/Diagnostics.cpp:86` — the `fprintf` is no longer confined
to `#if BUILDING_CACHE_BUILDER`. `error()` now always reports, via
`_simple_dprintf(2, "dyld error: %s\n", ...)` — the allocation-free, stdio-free
route, because the errors that matter happen during `rebaseDyld` and
`_simple_dprintf` is the same path `DYLD-LOAD-BASE` prints from at that moment.

⚠️ Worth recording: `Diagnostics.cpp` **already had `#include <_simple.h>` at
line 32**. So the missing report was **never a compile limitation** — the
non-cache-builder path was simply never written.

**Verified in the built artifact:** `strings` finds `dyld error: %s` (1).
`__got` re-measured and **unchanged**: @ 0xd6000, 15 slots, **13 binds, ordinals
0–12**, cross-checked against `dyld_info -imports` (13).

### 51.3 ⚠️ Item 3 is in the SOURCE but **NOT in the artifact** — and the build said nothing

`Libraries/Libsystem/libsystem_platform/simple/string_io.c:433` — the
unsupported-conversion arm emitted the character literally; it now emits
`<UNSUPPORTED-CONVERSION>` via `put_s` (verified present at :118/:136), and the
supported set is recorded in the comment: `%c %d %i %o %p %s %u %x %X %y`, with
`%l` as a length modifier. **No flag handling exists at all** — `0` is a width
digit, and nothing consumes `# + - . * space`.

**But it did not reach the loader, and the build was green while doing nothing —
§8e's trap, hit a fourth time in as many rounds:**

* `grep -c string_io /tmp/build_diag.log` → **0**. Not compiled.
* the SDK's `libplatform.a` is dated **Sep 27 22:57**, predating the 06:17 edit.
* `strings` on the rebuilt loader → **0** markers.
* `build-libraries.sh libsystem_platform` **does not build it** (RC=1, 2.9 s,
  archive unchanged) — that is not the component name the script uses.

**Owed, and not done:** build the `libsystem_platform` component by whatever name
the script actually uses, relink the dylinker, confirm the marker reaches
`__stubs`/the image, and boot. **I am not claiming this one works.**

### 51.4 Not started this round, stated plainly

* **Item 1 — the 10 imports: 0 eliminated.** §50's tractability findings stand
  (2 traps at one call site each; 2 vouchers unfixable by linking because the
  tool link is `-static` and `libsystem_kernel` has no `.a`; 3 `$UNIX2003` whose
  correct direction is still unestablished). No progress, no padding.
* **Item 4 — the `forEachLoadCommand` loop: still unresolved, and my §42 reading
  should be treated as unproven.** One cheap observation bears on it and argues
  *against* my own reading: **502,266 of the 509,976 ring-3 `#GP` records are at a
  SINGLE pc**, with `EAX` counting up. A loop stepping through load-command
  *bytes* would advance the pc; a fault handler returning to the same
  instruction forever would not. So "the CPU is executing its own load commands"
  is **not** supported by the pc distribution, and a machine-wide fault loop
  (the kernel was simultaneously in a 327,499-`#GP` storm with 452 double
  faults) is at least as good an explanation. **Marked unresolved rather than
  re-asserted.**

### 51.5 ⚠️ Item 3 is BLOCKED, by a deliberate gate — recorded, not forced

`build-libraries.sh` takes **directory names under `Libraries/`**, not library
names. `libsystem_platform` lives at `Libraries/Libsystem/libsystem_platform`, so
the name is **`Libsystem`** — that is why the earlier `libsystem_platform`
attempt failed with *"no such subdir"*. Building it:

```
=== building Libraries/Libsystem ===
Libraries/Libsystem/xcodescripts/linker_arguments.sh ...
*** missing required libs ***
system_trace
*** Error code 1
```

**The `Libsystem` group refuses to build until `system_trace` exists.** And
`system_trace` is precisely the component §41 identifies as supplying the last
three `libsystem_c` symbols — the known-hard one. So the chain is
`system_trace` → `Libsystem` (for `libplatform.a`) → relink `dyld`.

⚠️ **I could trivially have bypassed this** — `build-libraries.sh` does exactly
one thing per directory (`cd $ROOT/Libraries/$d && bmake -m …`), so
`cd Libraries/Libsystem/libsystem_platform && bmake -m …/share/mk` would build the
archive while skipping the group's prerequisite check. **I have not done that**,
and the reason is this project's own rule rather than caution for its own sake:
the gate is a *condition*, and satisfying the check without the condition is the
move that produced the zero-export `libSystem` stub this workstream is full of.
**I do not know whether `libsystem_platform` genuinely needs `system_trace`**, and
guessing is the thing that has burned me four times this session. Deciding it is
a real question with a real answer, and it is not mine to answer by skipping the
check that raises it.

**State: item 3's fix is in `string_io.c` and is NOT in any artifact. Not
claimed to work. Nothing staged, nothing pushed.** The artifact and the SDK's
`libplatform.a` were both copied to `/tmp` before these build attempts, per the
rule, and both are intact.

**The two routes, for whoever picks it up:**

1. Build `system_trace`, then `Libsystem`, then relink the dylinker and boot.
   The honest route, and it advances §41's blocker as a side effect.
2. Establish whether `libsystem_platform` actually needs `system_trace` — read
   the group Makefile's prerequisite and the component's own link line. If it
   does not, the gate is over-broad for this subdir and narrowing it is a real
   fix. **That is a question to answer, not a flag to bypass.**
