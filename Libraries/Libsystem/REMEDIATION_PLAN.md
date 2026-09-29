# ravynOS Libsystem Remediation Plan

Status: 22 of 25 libSystem re-export targets are real, built from source, reproducible via bmake. This document covers what remains, what is wrong elsewhere in the repository, and the ordered path to a source-built dynamic userland.

Read `libSystem.B_STATE.md` first for the per-component measured state. This document is the plan of record for fixing what that document records as broken, blocked, or provisional.

## `libsystem_kernel` is blocked on TWO independent things

**Its syscall half.** `create-syscalls.pl` generates **454 stubs and a correct
`SYS.h` cleanly** from `Kernel/xnu/bsd/kern/syscalls.master`. Those stubs will
not assemble. The error is deterministic and reproduces in a pristine directory
with no stale artefacts:

    ___accept.s:9:354: error: invalid instruction mnemonic 'unwind_epilogue'

> **The decisive fact:** the string `unwind_epilogue` appears in **NO file in
> this tree** — not in the source, not in `SYS.h`, not in the 454 generated
> stubs, not in `bsd/`, and not in the preprocessed output (verified by grep
> tree-wide). The assembler reports a token that exists in no file the project
> owns. Further, the `-E` and `-c` outputs for the same input are **not
> line-aligned**: source line 9 is the `__SYSCALL2` call, while preprocessed
> line 9 is an `#line` marker about `SYS.h`.
>
> **The mechanism is unresolved. Do NOT record a cause.**

**Its mach half.** Needs `mach_service_port_info_data_t`. It is declared only at
`mach_types.defs:523` in the **SDK** — the SDK's generated `port.h` has **zero**
occurrences. The one generation attempt was rejected at
`$SDK/usr/include/mach/std_types.defs:65` (`import <Availability.h>;`), and that
file is byte-identical between the SDK and the in-tree xnu build output. It
persists with a correct include path and with `-nostdinc`, so it is **not** a
resolution problem.

> **Correction to an earlier claim in this plan.** The SDK's mach tree is a
> **123-header SUPERSET** of the in-tree 107 — 16 headers are SDK-only — not an
> older subset. The SDK is **not** missing generated output that the in-tree
> build has. **Every generated header in this tree is OLDER than its own
> `.defs`.** Any earlier text implying otherwise is withdrawn.

**Both are single named unknowns, not open-ended work:** one assembler-path
resolution for the syscall half, one generation step for the mach half.

## How to read this## How to read this

The measured state lives in `libSystem.B_STATE.md` — sizes, export counts, and the current disposition of every one of the 25 re-export targets. **This document does not restate those figures and must not be used as a substitute for them.** If the two ever disagree, the state document is authoritative for measurement and this one for intent.

Items marked **`[DECISION REQUIRED]`** are not engineering tasks; they need a human choice and should not be actioned unilaterally. There are three: A1, D1, E3. Items marked **`[UNVERIFIED]`** are analysis, not measurement — the reasoning is laid out and the conclusion is plausible, but nobody has run it yet.

## Priority ordering, and why

**REVISED 2026-09-26 — the ordering below was written when it was assumed that
dyld gated the boot path. It does not.** B0 measured that `libsystem_c.dylib`
cannot load, with 126 of its 133 unprovided symbols unresolvable because
`libsystem_kernel` is an 8,064-byte stub. **A kernel that cannot load libc
cannot reach `main()` no matter how well dyld compiles.** `libsystem_kernel` is
the critical path; dyld is not. See B0 and E2.

The order below is not by difficulty. It is by blast radius:

1. Category A first. It is a legal and reproducibility exposure that is live RIGHT NOW, it gets worse with every commit, and it is the only category that can make previous work worthless.
2. Category B second. It converts 22/25 into 25/25, and the research this session showed that most of what looked like hard ABI problems are actually header-provisioning or dependency-hygiene problems.
3. Category C third. It is a strict architectural improvement but nothing is blocked on it.
4. Category D fourth. Hygiene, low risk, keeps the guard green.
5. Category E last. It is the goal, and it is correctly last because every step in it is blocked on Category B.

## B0. `libsystem_c.dylib` is BUILD-reproducible; its LOAD closure is UNVERIFIED and known-short  **[THE ACTUAL BOOT BLOCKER]**

Measured: `libsystem_c.dylib` carries 272 undefined symbols. They are not resolved — they are **deferred** under the `/usr/lib/system/` shared-cache exemption (finding 1, the ld64 install_name rule). **ravynOS has no dyld shared cache.** These were measured against all 6,605 symbols defined by every installed dylib in `$SDK/usr/lib` and `$SDK/usr/lib/system`:

    RESOLVED by an installed dylib:   139
    UNPROVIDED:                        133

Composition of the 133:

    libsystem_kernel (syscall wrappers)  102
    mach traps (also kernel)             14
    misc kernel                           7
    libsystem_trace                        3
    libsystem_platform                     3
    libdyld                                2
    dyld                                   2

> ### ANSWER: `libsystem_c.dylib` CANNOT LOAD.
> **126 of the 133 are unresolvable because `libsystem_kernel` in the SDK is an
> 8,064-byte STUB.** It links; it has never been loadable. **That is the boot
> blocker, and it outranks the re-export count and outranks dyld.

### B0a. The BUILD is reproducible — a SEPARATE claim from the LOAD closure

`libsystem_c` was rebuilt **clean from scratch: 693 objects, 16 archives, 0
errors**, producing `libsystem_c.dylib` at **1,255,496 bytes with exactly 1,342
exports** — byte-identical to the artifact that had been on disk, rebuilt from
nothing. The size and export count matching exactly is the strongest available
evidence that nothing was silently lost and that the build is deterministic here.

**Keep the two claims apart:**

| | status |
|---|---|
| `libsystem_c` **builds reproducibly** | **PROVEN** — 693 objects, 16 archives, 1,255,496 B, 1,342 exports, byte-identical on rebuild |
| `libsystem_c` **loads** | **UNVERIFIED, and measured short** — 133 of 272 undefined symbols unprovided |

The 272 undefined and the 133 unprovided are unchanged and still open: they are a
question about LOAD, not about BUILD. **A reproducible build does not imply a
loadable one**, and the entire gap is downstream of the build.**

**This inverts the plan's stated priority order, and the inversion is worth stating explicitly.** This plan was written on the assumption that dyld gated the boot path. **It does not.** A kernel that cannot load libc cannot reach `main()` no matter how well dyld compiles. `libsystem_kernel` is the critical path; `dyld` is not.

> **Measurement caveat, because it will bite anyone who re-runs this.**
> `nm -g` on the 8,064-byte `libsystem_kernel` stub reports **97 exported symbols
> including `_open`, `_read` and `_readdir`**, all typed `T`. A naive
> `comm -23` of libc's undefined set against every dylib's `nm -g` output
> therefore returns **0 unprovided** — which is wrong. The stub carries an
> export table but no implementation and no `LC_LOAD_DYLIB`. **A symbol appearing
> in a dylib's export table is NOT evidence that the dylib provides it.**

> **Do not add stubs to make this number zero.** A recorded, measured gap is
> worth far more than a fake closure.

## Category A — Repository integrity and legal exposure

### A1. Apple binaries are in local history — 41 of them, and the recommendation has changed  **`[DECISION REQUIRED — a concrete recommendation now exists]`**

> **The decision document is `Libraries/Libsystem/APPLE_BINARY_EXPOSURE.md`.**
> Read that for the full option analysis. This section carries the facts and the
> recommendation only.

> **CORRECTION — the figure previously given here was wrong.** This section used
> to say "45 tracked binary files totalling 11,727,752 bytes". That came from a
> narrow `grep -E '\.dylib$|/dyld$|/bin/'` filter, not the full set. The correct
> totals are **54 tracked files, 35,706,769 bytes**. The wrong figure is stated
> here only so it cannot be read again as current.

**Of those 54, only 41 files / 11,470,256 bytes are Apple-derived:** 40 extracted
dylibs (8,945,664 B) plus the extracted `usr/lib/dyld` (2,524,592 B). These are
binaries taken from a macOS dyld shared cache, and they are the only files the
standing commitment plainly covers.

**The other 13 files / 24,236,513 bytes are NOT Apple's:** OVMF/EDK2 firmware
(BSD-licensed), a QEMU-generated `vars.fd`, and **our own** `kernel.development`,
`template_head.bin`, `template_tail.bin` and the gold `bin/*` binaries.

> ### The most actionable warning in this section.
> **A naive purge of `tools/bootlab/assets/` would delete the boot firmware, the
> QEMU variable store, and this project's own kernel and image templates** — a
> real and easily-missed way to break the harness permanently. Any purge must be
> path-scoped to the Apple files.

**The rewrite would be 9 commits deep, not 756.** First asset commit
`3987554127` (2026-09-06); the repository has 756 commits total.

**It is NOT pushed.** `git branch -r --contains 3987554127` and
`git tag --contains 3987554127` are both empty. **No remote and no tag ever
received these binaries.**

### RECOMMENDATION: NO REWRITE — go local-only.  **[EXECUTED 2026-09-26]**

> **This is no longer a recommendation awaiting a decision.** It was executed:
> commit `12077f1638` untracked the 41 Apple-derived files with `git rm --cached`
> and added `tools/bootlab/assets/.gitignore`. **They remain on disk** — nothing
> was deleted — and the action is fully reversible with `git add`. Tracked files
> under `tools/bootlab/assets/` are now **14** (the 13 that are ours or open
> source, plus the new `.gitignore`).
>
> Separately, commit `ef9608b0c7` **archived** (did not delete)
> `dsc_rebase.py`, `dsc_normalize.py`, `dsc_flagfix.py` and `build_stubs.sh` into
> `tools/bootlab/interop-archive/` with a README. Nothing in the build flow
> invoked any of them.
>
> **Decision record and rationale: `Libraries/Libsystem/APPLE_BINARY_EXPOSURE.md`.**

#### The original reasoning, retained for the record

Stated so a future reader can check it:

- A rewrite **protects nobody** while the commit is unpushed. No remote, no fork
  and no third party has received the history.
- It **costs** 9 local commit rewrites plus **reapplication of the 6 unpushed
  commits** (`1f0e802`, `4a37c54`, `3a27bba`, `f6f3df2`, `f435475`, `8b1203c`).
- It **risks** taking OVMF, `vars.fd`, `kernel.development` and the
  `template_*.bin` files with it.

**Do this instead:** add an ignore rule for the Apple paths, then
`git rm --cached` them. That drops exposure from **41 tracked files to 0 tracked
/ 41 local-only**, at no cost to the harness. **Revisit a rewrite only if the
repository is ever pushed with those binaries in it.**

**`assets/usr/lib/dyld` is STILL LOAD-BEARING.** It is the only extracted dyld;
`libsystem_kernel.dylib` does not build, so there is **no source-built
substitute**. Deleting it ends the QEMU interop test. That is the honest limit on
how far any cleanup can go today.

> **The distinction that decides this:** an **interop lab** keeping Apple
> binaries *locally and unpushed* is a materially different posture from a
> **repository that ships them**. The project is currently in the second state
> **by accident**, for 41 files — and that accident is cheap to undo.

### A2. Six further binaries in the assets tree are untracked and NOT ignored

All six confirmed UNTRACKED and NOT ignored — one `git add -A` from joining the
other 40. They were deliberately NOT ignored, because silently hiding Apple
binaries would mask a legal problem rather than resolve it. Two need correcting
from how they were previously described:

- **`libobjc.A.dylib` (6,856 B) is NOT the Apple library.** It is a small stub
  produced by `tools/bootlab/build_stubs.sh`. The real artifact is the
  **1,608,088 B source-built** `libobjc.A.dylib`. Superseded.
- **`liblaunch.dylib` (49,152 B) is superseded** by the **91,720 B source-built**
  `liblaunch.dylib` in the build SDK.
- `libcorecrypto_noasm.dylib` (933,888 B), `libcorecrypto_trace.dylib`
  (1,114,112 B), `libkxld.dylib` (147,456 B) and `libunc.dylib` (32,768 B) are
  **genuine Apple DSC extracts with no source-built equivalent** — deleting them
  removes the only copy.

### A3. Load-bearing build tooling is untracked  **[URGENT, no legal dimension]**

Untracked and non-ignored: `tools/bootlab/isysroot-cc`, `macar`, `build-libraries.sh`, `build_stubs.sh`, `dsc_rebase.py`, `dsc_normalize.py`, `dsc_flagfix.py`, `objc_stubs.c`, `ravynos-mach-compat.h`.

Every fix in this entire effort depends on `isysroot-cc`. A clean checkout has none of it, so the work is currently reproducible only on this machine. Unlike A1 this is purely an engineering problem and should be fixed immediately: commit these, because losing them loses the build system.

> **This risk has now DEMONSTRATED a cost, rather than merely posing one.** When
> the shared compiler wrapper `isysroot-cc` regressed, there was **no `git
> checkout` to roll back to**, and the recovery cost a full debugging round
> instead of a one-command revert. That incident is the evidence for why A3 is
> urgent rather than housekeeping.
>
> The tooling has since been committed locally as **`1f0e802`** (5 files, **local
> only, no push**), so the safety net exists now. Until that reaches a shared
> remote, one machine holds the only copy of the build system.

### A4. Build output was committable  **[DONE]**

`Libraries/llvm_target` is 7.2 MB of untracked, non-ignored build output holding the real `libc++.a` the dylibs link against. `.gitignore` rules have been added covering `*.o` (1,299 files), `*.a` (34), build `*.dylib`, generated mig stubs, libsystem_c generated lists, `Libraries/llvm_target/`, and the objc4/CrashReporterClient/dyld build products. Untracked entries went from 1,507 to 33, and every one of the 33 remaining is a real deliverable. Generated-source rules use explicit per-file paths rather than a blanket `*.c`/`*.h` rule, so hand-written headers such as `private/os/log.h` cannot be caught by accident.

## Category B — The three remaining re-export blockers

The headline finding of this research phase: most of what looked like un-solvable ABI problems are actually header-provisioning or dependency-hygiene problems. Two of the three have identified, non-invented fixes.

### B1. system_kernel: ONE missing mach header, now shimmed  **[the shim LANDED; the component still does not build]**

> **CORRECTION.** An earlier version of this section said the eventlink fix had
> "made this a SET problem". **That was wrong and is withdrawn** - it was an
> over-reading of the build's own behaviour. There is exactly **ONE** missing
> mach header.

**The measured position.** Comparing the three mach trees: the SDK's `mach/` has
**123** headers, `xnu EXPORT_HDRS/osfmk/mach` has **107**, and the generated
`mig_hdr/include/mach` that the build actually includes has **27**. Only
`mach_eventlink.h` is absent from the SDK.

**Solved and verified.** The `eventlink_port_pair_t` shim landed at
`tools/bootlab/ravynos-eventlink-compat.h`, with the typedef sourced **verbatim**
from `Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/mach/mach_types.h:205` (the
userspace branch): `typedef mach_port_t eventlink_port_pair_t[2];`

> **The verification bar, which should be the standard for every future shim:**
> `clang -E` must show the build consuming the SOURCED definition, not an
> inferred fallback. A shim that silently fails to apply is not a shim.

**What made it look like a set.** Each fix revealed a "new" error, and that
pattern read as an expanding set when it was **one error behind another** - the
build halts at the first bad translation unit. This is the same lesson already
recorded for the `os_log_pack_s` extrapolation, and it is why the one-at-a-time
reading was wrong.

**Two wrapper defects were found and fixed en route, and are recorded because
they fail SILENTLY:** `$HERE` was undefined in the wrapper, so the shim quietly
did nothing; and the eventlink shim was gated behind a *different* shim's flag.
See finding 5 — a shim that does not apply and reports success is worse than no
shim.

> **HONEST CURRENT STATE — do not read this section as further along than it is.**
> **No `libsystem_kernel.dylib` has been built.** The tally remains **22/25, not
> 23**. `libsystem_c.dylib` **still cannot load**, and the **126 unprovided
> symbols are unchanged**. Any earlier "residue ~19" figure was a *prediction* and
> has been formally withdrawn; it appears nowhere in this plan as a result.

Owner: `audit`.

#### B1a. The `mach_types.h` problem is a PATH problem, not stale content  **[do not edit any header]**

`<mach/mach_types.h>` resolves to
`$SDK/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/mach/mach_types.h`,
**not** to `$SDK/usr/include/mach/mach_types.h`.

**Both copies are 254 lines and both declare `io_master_t` exactly once.** The
content is correct and identical in the part that matters. **The fault is a wrong
path winning the search order, not a stale or wrong header.**

> This distinction is the whole fix: **change nothing about any header; stop the
> wrong path winning.** "Stale shadow" would send the next person to overwrite a
> correct header and break the component.

#### B1c. The 13-type mach shim: ROLLED BACK — it broke the real build  **[was "closed", is not shipped]**

> **This reverses an earlier "closed" claim in this plan.** The derived
> `mach_port_t` typedef shim was added to `tools/bootlab/ravynos-eventlink-compat.h`
> and committed as `f435475`, and this plan recorded the 13 types as **"sourced
> and shipped — closed, not open."** **That is no longer true.**

**What happened.** The shim was verified on a **synthetic** translation unit at
0 errors, and was approved on that basis. The first full run of the new build
driver — which builds **what the project actually builds**, rather than a
targeted test — showed the shim **breaks `libsystem_c` and `liblaunch` in the
real build**, across three successive versions of the set. It was rolled back.
**`libsystem_c` rebuilds clean without it: 693 objects, rc=0, dylib 1,255,496 B /
1,342 exports.** The file is preserved out of the build at
`/Users/max/Projects/build/diagnostics/ravynos-eventlink-compat.h.disabled`.
See commit `0a235e5`, which records the removal and adds the entry-point driver.

**The finding is more important than the shim.**

> ### A synthetic TU proves the shim compiles; it does not prove the real build
> ### resolves to it.
> **Those are different claims, and the first was allowed to stand in for the
> second.** The shim's 0-errors check was *real* and still insufficient, because
> the failure mode is a **collision with whichever `mach_types.h` the real build
> resolves** — a tree no SDK copy explains, and therefore not something a
> synthetic TU could ever have surfaced.

> **A verification that cannot fail the way the real build fails is not evidence
> about the real build.** Generalised: a test is only evidence for the property
> it is capable of failing on.

> **Companion clause, learned the same round: a run that predates your fix is not
> evidence about your fix.** The driver's final classification was reported from a
> run taken **before** that change and had to be withdrawn.

**What survives.** The 12 `mach_port_t` members and the derivation rule remain
valid and documented above; what is withdrawn is the claim that they are shipped.
The two kernel-server mig types remain deliberately excluded.

#### B1b. Methodology rule: read the `-I` list, never infer the provider  **[three wrong diagnoses so far]**

The include was diagnosed by reasoning about which directories **EXIST** rather
than by reading the compiler's actual `-I` list for that specific translation
unit. **That inference was wrong.** The doubled-path `EXPORT_HDRS/osfmk`
directory was never on `libsystem_kernel`'s include path at all —
`grep -c EXPORT_HDRS` on its Makefile returns **0**.

> **RULE: determine an include's provider by reading the compiler's emitted `-I`
> list and the resolved path for the failing translation unit. Never by inferring
> it from which directories exist.** An overlay directory that is present on disk
> but absent from the include path looks exactly like an active shadow until you
> read the argument list. Reasoning about it has produced **three** wrong
> diagnoses in this project: this one, the `Availability.h` collision, and the
> `mach/` overlay traps.

### B2. libsystem_trace: NON-EMPTY requirement, so the flag cannot be dropped

The dependency test has been run **twice, on two different axes, and the two
results disagree.** Both are recorded, because a reader deserves the discrepancy
rather than one convenient number.

- **Per-component measurement:** across the whole tree the requirement is **5
  symbols** — 3 by `libsystem_asl`, 3 by `libsystem_info`, sharing 1 — and
  **`libsystem_c` needs 0 of them.**
- **Boot-safety measurement (B0):** attributes **3 unprovided `libsystem_trace`
  symbols to `libsystem_c.dylib`.**

**These are not reconcilable as errors; they are different axes.** The first
asks which libraries *name* the symbols; the second asks which undefined symbols
*libc's image* still lacks at load time. The peer is measuring load-time closure,
not re-export-slot satisfaction.

**The verdict is unchanged and now firmer.** Unlike `-lsystem_trace` in
libsystem_c's LDFLAGS — whose intersection was **exactly zero**, on which
evidence the flag was removed — libsystem_trace's requirement here is
**NON-EMPTY and cannot be dropped.**

> **The contrast is the most useful thing in this section:** one flag was removed
> because the evidence was zero, the other is retained because the evidence is
> not. Removing a link flag on anything less than a zero intersection is how
> userspaces end up with unresolved symbols that only fail at launch.

The source problem is unchanged: `lck_spin_t` is defined only in kernel-only
`Kernel/xnu/iokit/IOKit/IOLocks.h`, and `lck.h` is **absent from the entire
tree** — permanent absent a local userspace shim. The asymmetry remains honest:
the SOURCE is permanently absent, the NEED is 3-5 symbols from two or three
components. **Do not describe this as "libsystem_trace is needed"** in the sense
of a 197-symbol fix.

### B3. dyld: the `<stdint.h>` blocker is CLEARED; what remains is a SEQUENCE, not a project

**The `<stdint.h>` blocker is cleared and verified on the real build.** The
`cstdint` error count went **from 1 to 0 in an actual dyld build**, and the
frontier moved a whole error class forward. This is not "resolved in principle".

**The fix is a PRE-INCLUSION, not an ordering change.** `isysroot-cc` now
force-includes `$SDK/usr/include/c++/v1/stdint.h` for non-assembler inputs.

> **Why an ordering change could never have worked — the mechanism:** an earlier
> header in dyld's include chain opens the **C** `<stdint.h>` first, so
> `cstdint`'s own `#include <stdint.h>` becomes a no-op under that header's
> guard, `_LIBCPP_STDINT_H` is never set, and the `#error` at `cstdint:149`
> fires. **Ordering flags cannot fix that — the C header is already open. Only
> opening libc++'s shim first works.** The shape matters more than the fix.

#### B3a. A hypothesis falsified by measurement — a true fact attached to the wrong causal story

It was hypothesised that the host CLT and the SDK were two libc++ copies racing
for `stdint.h`. **Measurement refuted it in one command: 806 of 806 libc++
headers in the failing TU resolve from `$SDK/usr/include/c++/v1/`, and 0 from the
Command Line Tools.** The CLT's copy is in the search list second and is never
opened. **The SDK's already wins**, so no `-isystem` ordering change could have
altered it, and a fix built on that premise would have been a **fourth attempt
against a cause that was not present**.

> This is the cleanest example in the project of a plausible,
> well-measured-sounding hypothesis that measurement refuted in one command. The
> underlying **fact was true** — the host CLT really does ship a `c++/v1/stdint.h`
> at 1,251 B against the SDK's 2,373 B, and they genuinely differ — **but the
> fact was not the mechanism.** A true fact, correctly measured, attached to the
> wrong causal story, is more dangerous than an obviously bad guess.

#### B3b. The "month-plus" estimate is dead, and no new number replaces it

> The figure is **not yet established**. It was asserted before any of it was
> measured, and it was wrong by an order of magnitude.
>
> **The measured situation:** dyld's blockers are **not in dyld's code** and are
> **not open-ended**. They are a sequence of **SDK header-configuration issues,
> one per translation unit**, each so far costing **minutes** to locate and fix.
> The `stdint.h` one is **done**. The `OPENBSM_1_2_alpha5` one is **next** and is
> the same shape — a macro selecting an API generation that is not set for this
> target.
>
> **The correct unit of work is one SDK header-configuration issue at a time,
> not "build a dynamic linker". No new total is offered, because two data points
> do not establish one, and a confident replacement would be wrong in the same
> way the original was.**

> #### Open question — worth more than dyld
> These are **SDK header-configuration issues**, and libc's **272 undefined
> symbols** and the **`mach_types.h` generation gaps** have the **same shape**.
> **If any of them share a root cause, fixing it once could clear more than dyld.**
> That is worth testing and is **currently untested**.

### B4. cc_abort.h: exists, and is a one-line fix  **[MINUTES]**

> **CORRECTION.** The previous state document recorded `cc_abort.h` as absent. **That was wrong.** `Kernel/Extensions/corecrypto/cc_abort.h` exists and is a real 10-line header that selects between `#define cc_abort panic` under `CC_KERNEL` and a `fprintf`+`abort()` implementation otherwise. Verified by direct read. A wrong negative left standing is worse than no entry, because it stops people looking — so this correction is recorded as prominently as the original finding was.

The source files include `<corecrypto/cc_abort.h>`, and the kext's header directory `Kernel/Extensions/corecrypto/include/corecrypto/` does not contain it — it sits at the kext ROOT. So pointing `-I` at the kext root resolves `<cc_abort.h>`, not `<corecrypto/cc_abort.h>`, and the angle-bracket include never matches.

Fix: a small `Libraries/Libsystem/corecrypto/include-shim/corecrypto/cc_abort.h` that `#include`s the real file by relative path, plus one `-I` line in the corecrypto Makefile. This is exactly the pattern already used successfully for `os_log_pack_s`, and it is **NOT a fabricated ABI** — the real definition is being pointed at, not invented.

Unblocks 4 files: `cc_functions.c`, `cc_digest.c`, `aes_cbc.c`, `aes_ecb.c`. Estimated effort: minutes; the file's existence and include form were both verified. Owner: `audit`.

## Category C — libc++ and the C runtime: the user's direct question

### C1. Direct answer: yes, the real libc++.a can and should be replaced

A real `libc++.1.dylib` was built and linked from the same sources during this research, using the established standalone-dylib recipe:

    1,397,256 B, 2,183 exports, 140 undefined
    install_name /usr/lib/system/libc++.1.dylib
    clang -shared -dylib -Wl,-force_load,.../libc++.a -nodefaultlibs
    -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache
    -Wl,-multiply_defined,error -Wl,-install_name,/usr/lib/system/libc++.1.dylib

It links cleanly. `-multiply_defined,error` was included deliberately and it passes, which is the proof that there is no symbol ambiguity within `libc++.a` itself.

### C2. What it replaces is a stub wearing the right name

`Libraries/Makefile:194` currently reads `touch ${.OBJDIR}/libc++.1.dylib`, and line 197 echoes the literal string `stubbed libc++ dylib for Darwin host`. This is the most harmful class of artifact this project exists to eliminate: a 0-byte dylib named `libc++.1.dylib` satisfies any `-lc++` lookup, then fails at link time with an unhelpful error. It also contradicts `Libraries/Makefile:188-189`, which states the intent to build a combined libc++ and libc++abi dylib.

### C3. Why the dylib is strictly better than the static archive

Three reasons, in order of weight:
1. **The static archive is wrong for this architecture.** Every consumer links it privately, so each dylib carries its own copy of all 2,183 symbols, and there is no single owner of the C++ runtime's state.
2. **The C++ runtime has process-wide state** — static initialisation and teardown, `atexit` registration, operator new/delete domains, OpenMP, `fdinfo`. With a private static copy per consumer, any of those can diverge. One dylib means one owner.
3. **The 140 undefined symbols are NORMAL and not a defect.** A dylib with a `/usr/lib/system/` install name is shared-cache-eliminated, so anything it does not define is resolved against the shared cache, exactly as for the 1,342-export `libsystem_c.dylib`.

### C4. Two real risks, both manageable

- The swap must be **ATOMIC** across `Libraries/Makefile:194` and every `-l`/`-L` in the sub-dylib LDFLAGS. Consumers currently linking `libc++.a` directly would get undefined references at their own link time for the 140 symbols unless they also gain `libc++.1.dylib` on their search path.
- `libc++.a` and `libc++abi.a` already collide on `std::overflow_error` (`libc++abi.a:535[stdinfo.cpp.o]` and `libc++abi.a:1919[stdlibcpp.cpp.o]` both define `_ZSt20overflow_errorD1Ev`). A single combined dylib from both is therefore not possible without de-duplication. The dylib above was built from `libc++.a` ALONE, which is the right call: libc++ already absorbs what it needs from libc++abi at link time today, and `-multiply_defined,error` proves there is no ambiguity within `libc++.a`. The conversion may remove this collision as a side effect.

Sequencing: fix `-D`/`ar -D` reproducibility first, convert, then **measure** the actual binary-size delta rather than asserting it.

### C5. Reproducibility: the static archive is NOT byte-reproducible

    build 1:  2,539,256 B  sha 60dc5b4f609dcdae67377828c5e483054758c070
    build 2:  2,539,256 B  sha b9daa5b0d6b69609a9aeacd6b3185cb78ae7b41f41
    build 3:  2,539,376 B  (third build, to isolate)

Same size, different hash every time. Investigated and the obvious causes are RULED OUT: zero embedded absolute source paths (`strings libc++.a | grep -c "Users/max/Projects/ravynos"` returns 0), so no `__DATE__` and no build path. **Isolated to the archive step**: all 43 compiled objects are byte-for-byte identical across builds; only the `ar` output differs, because each member embeds its mtime and the recipe invokes `ar` via `$(AR) -tv`, which is non-deterministic.

Fixes, in order: (1) `ar -D` deterministic mode, which zeroes mtimes/uids/gids; (2) until then, do not use a content-addressed integrity check over the archive; (3) do not treat shasum-differing as a build regression when comparing over `Libraries/llvm_target`. Recommend (1), then note that the dylib conversion in C1 makes this moot anyway.

### C6. What llvm_target actually is

`Libraries/llvm_target` is a build-output directory, 7.2 MB, containing `libcxx/lib/libc++.a` (2,539,376 B), `libcxxabi/lib/libc++abi.a`, `compiler-rt/lib/ravynos/libclang_rt.osx.a`, and `libunwind/lib/libunwind.a`. `git ls-files` returns 0 tracked files.

It would be LOST on a re-clone — but it is recoverable, which is what matters. The source is tracked and `Libraries/Makefile` already has the rules: `LIBCXX_DIR = ${ROOT_SOURCE_DIR}/Developer/Default.xctoolchain/llvm/libcxx` with a `libcxx` target compiling 43 libc++ and 19 libc++abi sources. It was re-run twice from clean during this research and reproduces both archives. **So it is a build product bmake regenerates from tracked source, not an opaque blob.** The real defect is that nothing in the default build path guarantees it gets built, so a `git clean` silently drops it until someone runs that target. Addressed by the Category D entry point.

## The `-I` precedence shadowing hazard

`Kernel/xnu/EXTERNAL_HEADERS/stdlib.h` — a one-line FBSD shim that defines
`_STDLIB_H_` and includes `<stddef.h>` — pre-empts the SDK's `stdlib.h` through
`-I` precedence. `abort()` therefore resolves to the shim rather than to the SDK
header that declares it. This surfaced while unblocking `aes_cbc.c` / `aes_ecb.c`
in corecrypto, where `cc_abort()`'s userspace branch calls `abort()`.

**Scoped, and the earlier framing is withdrawn.** A normal userland program
including `<stdlib.h>` compiles and calls `abort()` with 0 errors. The SDK's
header is sound, so **this is NOT a userspace showstopper**. Any earlier
"far bigger than two AES files" framing was too strong and is withdrawn.

Fixed for corecrypto only so far: **15 -> 19 objects, 68 -> 74 exports,
regression green.** **Five `libsystem_c` subprojects also carry this `-I` and
have NOT been swept.** Before touching them: run `clang -H` per subproject,
intersect the resolved header set against the tree, and remove the `-I` only
where the evidence shows it vestigial. **Do not sweep blindly** — a wholesale
`-I` removal is the same class of move as the header sync in B1, and it has a
track record here.

> **The generalisation, which matters more than any single instance:**
> whenever two generations of one header are both reachable, **`-I` order
> silently decides which one wins.** This is the THIRD instance of the same trap
> in this project, after `Availability.h` and the XNU libkern `os/` headers.
> Treat it as a general class to check, not three coincidences.

## Most of this project's stalls were MODE problems, not content problems

The tree was correct and the **invocation** was wrong, five separate times: the
mach header generation, the `mach_port_t` typedef family, the `Availability.h`
guard, the `-E`/`-c` divergence, and the assembler path. **Twice, a confident
answer pointed at the source when the fault was in how the tool was being
called.** This is distinct from the header-generation family and earns its own
entry.

## Ten findings — the two newest first, because they were the most costly

> ### 1. A verification that cannot fail the way the real build fails is not
> ### evidence about the real build.
> A **synthetic TU** proved the 13-type mach shim compiled at 0 errors; the real
> build then **broke `libsystem_c` and `liblaunch` across three successive
> versions**. **A test is only evidence for the property it is capable of
> failing on.**

> ### 2. A run that predates your fix is not evidence about your fix.
> The driver's final classification was reported from a run taken **before** that
> change, and had to be withdrawn. This is the same rule as #1 applied to **time
> rather than scope**: the evidence must be **contemporaneous with, and addressed
> to, the thing being claimed.**

3. **Read what the tool produced, not what you intended to produce.** When a tool
1. **Read what the tool produced, not what you intended to produce.** When a tool
   reports a line and column, identify which artefact that numbering refers to
   before grepping anything — `-E` output and `-c` input are not line-aligned.
   *Instances: the wrong translation unit by command-line adjacency; `io_master_t`
   for `io_main_t`; a gate printing PASS having tested nothing; a filter reporting
   "0 already defined" as though that were data.*

2. **Never treat "no match" as "no data."** A grep returning zero is "no match",
   not proof of absence. *Five instances. Here the assembler and the grep directly
   contradicted each other, and the assembler was closer to the truth.*

3. **Check that the instrument can fail the way you need it to fail, before
   trusting it to pass.** *A C preprocessor was used to test a mig grammar
   question and would have reported success on a statement it does not parse.*

4. **Verify the inputs a tool will actually use, including supporting headers,
   not just the ones you counted.** *`stubs.list` had 456 lines and was checked;
   the `SYS.h` that had to accompany it was not.*

5. **A hypothesis that is half right is the most dangerous kind, because the half
   that is right lends false confidence to the half that is wrong.**

6. **When two observations conflict, do not settle on the most plausible one.**
   Carry it as a hypothesis and go get the measurement that decides it.

7. **Check the inputs, not only the outputs, before concluding something is
   missing.** A generated header and its `.defs` are an **output and its input**,
   and only the output can be absent. *This nearly produced a confident and wrong
   "this source does not exist in this tree."*

8. **A derived list only beats a hard-coded one if the derivation is right; a
   wrong derivation is worse than an honest list because it reports with
   confidence.** *The strict-pattern dedup proposed 40 redefinitions.*

9. **A gate earns the right to be committed by demonstrating a clean run, not by
   being written — and it earns the right to be trusted by demonstrating a red on
   a known-bad input.** *`4a37c54` records its negative direction as UNVERIFIED.*

## The vendored-include shadow class: real, measured, and NARROWER than it looked

**Eleven** vendored `-I` directories precede the SDK's `usr/include` and contain
libc header names. On a **real `libBase` translation unit (183 header opens)**
the shadow is **LATENT, not live**:

- 87 headers from `Kernel/xnu/bsd/sys` — **intended**; that IS the libc
- 26 from the SDK
- 11 from `libsystem_c`'s own `os/` and `fbsdcompat/`
- 2 from `libkern`
- **0 from `Kernel/xnu/EXTERNAL_HEADERS`, which is not on `libBase`'s path at all**

So **`libsystem_c` is compiled against the right headers**, and "verified" has
meant the right thing.

### The genuine defects, confined to six components

| vendored path | headers | differs from SDK? | carriers | verdict |
|---|---|---|---|---|
| `Libraries/Libsystem/libsystem_c/include` | stdint, stddef, string, stdio, stdlib, unistd | n/a — this IS the libc | libsystem_c, dyld | **intended**, measured not winning |
| `.../openbsm` (5 paths) | `version` — a 19-byte **data file**, not a header | n/a | dyld, liblaunch, libsystem_asl, libsystem_info, libxpc | **defect** |
| `Kernel/xnu/EXTERNAL_HEADERS` | stdint 5556/2517, stddef 3816/2688, **stdlib 14705/381** | **YES** | libsystem_darwin | **live hazard** |
| `Libraries/Libsystem/libsystem_darwin/h` | string 7611/5409, stdio 16210/11346 | **YES** | libsystem_darwin | **live hazard** |
| `Kernel/xnu/libsyscall/mach` | string | not compared | dyld | unmeasured |
| `$BUILD/Kernel/xnu/EXPORT_HDRS/osfmk` | string | doubled-path artefact | libsystem_darwin | exists only because the build tree mirrors the source |

> **The 381-byte `stdlib.h` shadowing a 14,705-byte one is the `mach_types.h`
> complementarity trap in its purest form**, and is the **first thing to fix** in
> `libsystem_darwin`. I verified both sizes directly.

### The decisive negative result

**Removing the openbsm path does NOT clear dyld's blocker.** It removes
`OPENBSM_1_2_alpha5`, and a **same-family error at `cstddef:46` immediately
replaces it.**

> **This is not an include-ordering problem to be solved by reordering.**
> `libsystem_c/include/stddef.h` (3,816 B) is a **second libc generation** in the
> search path, distinct from `Kernel/xnu/EXTERNAL_HEADERS/stddef.h` (2,688 B) and
> from the SDK's. **No single include-path change fixes it.**

## Two mirror findings — together the through-line of this body of work

> **Framing: the failure is never the absence of measurement — it is the gap
> between what was measured and what was concluded from it. A measurement of one
> thing does not licence a conclusion about another.** Two of these stalls were
> mine: I approved the shim on a verification that could not fail that way, and I
> pushed a "two libc++ copies racing" hypothesis that one `clang -H` refuted at
> 806-of-806 headers resolving from the SDK. **Both were true, well-measured facts
> attached to the wrong causal story.**

### A verification that cannot fail the way the real build fails is not evidence about the real build

The 13-type shim passed a synthetic TU at 0 errors and then **broke `libsystem_c`
and `liblaunch` across three successive versions**. **A test is only evidence for
the property it is capable of failing on.**

### A test broader than the question can cause the defect it was looking for

The eleven-path inventory **looked systemic**. Landing an overlay on its strength
would have **disturbed a sound libc** and **concealed two real defects** behind
it. The measurement produced a **narrow** answer; reasoning from the shape of the
inventory would have produced a **broad, wrong** one. **Neither finding is licence
for the other** — one warns against under-testing, the other against over-testing.

## Never interpret output from a process that has not exited

The `mach_msg_aux_header_t` failure that consumed four debugging rounds **was not
a real failure.** It was an artefact of reading a build log **while the build was
still running**, combined with identifying the failing translation unit by
**command-line adjacency** rather than by the compiler's own `In file included
from` provenance. A partially-written log looks exactly like a failed build.

> **RULE: never interpret output from a process that has not exited, and get
> provenance from the tool rather than from adjacency.**

This is the same shape as the other instrument failures in this project — the
nested `sh -c` argument overflow, a malformed `-E` probe that produced a
misleading zero, and a `git` scope error. In every case the reasoning was sound
and **the instrumentation was what had to be fixed first.**

## Category D — Repository hygiene and build reproducibility

### D1. Four pre-existing zero-byte stubs  **[PARTIALLY RESOLVED]** — **`[DECISION REQUIRED]`**

`usr/lib/libedit.dylib`, `libncurses.dylib`, `libncurses.6.dylib`, `libutil.dylib` — all 0 bytes, all with mtime Aug 31 07:06, hours before this work began, so pre-existing rather than a regression. All have REAL sources in this tree under `BSD/lib/`: libedit (36 .c), ncurses/, and libutil/, each with its own Makefile that already references the output.

Disposition splits by relevance:
- **`libutil.dylib` is a genuine libSystem-adjacent component, not a stray. BUILD IT.**
- `libedit.dylib`, `libncurses.dylib`, `libncurses.6.dylib` are terminal libraries, not needed by Libsystem or by anything in the current dynamic-userland plan. Add them to a KNOWN list in `check_sdk_stubs.sh` so the guard goes green with the exception recorded, rather than building them or silently relaxing the check.

Nothing in `Libraries/` or `tools/` references any of the four by name, which is why they sat unnoticed. **`[DECISION: confirm the libutil-priority / known-stub split.]`**

### D2. A single reproducible entry point  **[NOT YET IMPLEMENTED]**

The build is currently `tools/bootlab/build-libraries.sh <target>` invoked per component, with a large environment preamble that has to be remembered. That is not reproducible by a new person, and it is the direct cause of A3 being uncommitted for so long.

Implement a SCRIPT rather than a runbook, ~30 lines: an ordering table plus a loop, ending with `check_sdk_stubs.sh` as a hard gate. Proposed order:

    runtime + libunwind + libcxx + libcxxabi      (Libraries/Makefile)
      -> libobjc, libCrashReporterClient, libxpc, liblaunch,
         libsystem_notify, libsystem_info, libdispatch, libmacho,
         copyfile, removefile,
         libsystem_{m,malloc,platform,pthread,blocks,asl,c,coreservices,darwin,dnssd}
      -> libSystem.B
      -> Libraries/check_sdk_stubs.sh  (gate)

The wrapper already accepts a subdir argument, so the driver is a loop plus the table plus the final guard call. Owner: `audit`, who owns `build-libraries.sh`.

### D3. The silent stub-writer: already eliminated

`Libraries/CrashReporterClient/Makefile` had a Darwin branch doing `touch` then `cp -f` into the SDK, masked by `2>/dev/null || true`. It fired on every recursive Darwin build through `Libraries/`, overwriting a real 8,704-byte library with 0 bytes — and a 0-byte archive is rejected by ld64, so it was never a usable substitute. Replaced with a real build (CRClient.c + CRClientCPP.cpp -> 2,928-byte .a -> 8,704-byte dylib).

The guard is `Libraries/check_sdk_stubs.sh`, which checks the 21 re-export targets that must be real against an 8,192-byte floor, reports the known blockers as KNOWN, verifies `libobjc.dylib` is a symlink resolving above the floor, verifies `libSystem.B.dylib` re-exports at least 20 targets, and fails on any 0-byte file in `usr/lib`, `usr/lib/system` or `usr/local/lib/system`.

`tools/bootlab/build_stubs.sh` was cleared decisively rather than by absence of evidence: it hardcodes its output as `$here/assets/$1`, so it cannot reach the SDK by any invocation, and nothing in the repo calls it.

One correction worth recording: a previously reported "15-byte libobjc.dylib" was a **measurement error, not a real incident**. `stat -f%z` does not follow symlinks and returned the length of the link-target string. The guard now resolves symlinks before measuring so the mistake cannot recur.

## Category E — The path to a source-built dynamic userland

### E1. Current state, stated precisely

**Nothing built in this effort has been staged into the bootlab image or is bootable.** This was confirmed by hash, not assumption. Dynamic `/bin/echo` still does not reach `main()`: dyld faults during initialisation at `dyld-fault: pid=2 cr2=0x7f805691e9a8 rip=0x7f8028001806 err=4 kret=1` / `dyld-exc: pid=2 exc=1 code=0x1 subcode=0x7f805691e9a8`. That address corresponds to the OLD `libSystem.B.dylib` stub and `___libkernel_init`, both of which are now replaced by real artifacts — but they are not staged, so the failure is unchanged.

Staging shape, for whoever gets there: `tools/bootlab/manifest.json` has only 4 entries — `usr/lib/dyld`, `usr/lib/libSystem.B.dylib`, a glob of `usr/lib/system` from asset_prefix `usr/lib/system/`, and `usr/lib/libobjc.A.dylib`. So dropping each real dylib into the assets tree at `usr/lib/system/` requires **no manifest edit at all** (the glob picks it up); only the three named entries would ever need touching.

### E2. The dependency chain — TWO INDEPENDENT CLOSURES

    libsystem_kernel completes  ->  libsystem_c.dylib's runtime closure closes  ->  libc is loadable
      ->  (independently) dyld compiles and links  ->  dyld is real
        ->  stage  ->  dyld init  ->  /bin/echo reaches main()  ->  clean exit  ->  PID 1 alive

**The two chains are INDEPENDENT and can be worked in parallel. NEITHER alone is
sufficient.** They are two separate closures that must both land. Do not read
this as dyld being downstream of libc or vice versa — the diagram shows libc
becoming loadable on its own branch, and dyld becoming real on its own.

The first branch is the one that is currently furthest from done **and** the one
this plan previously under-weighted. B0 measured it: 133 of libc's 272 undefined
symbols are unprovided, 126 of them because `libsystem_kernel` is a stub.

### E3. The DSC/rebaser path should be archived  **`[DECISION REQUIRED]`**

`tools/bootlab/dsc_rebase.py`, `dsc_normalize.py`, and `dsc_flagfix.py` were workarounds for consuming Apple dyld shared cache binaries. With 22 of 25 components now source-built, the path is obsolete. Continuing to keep Apple-derived binaries in the repository is precisely the legal exposure described in A1, and `build_stubs.sh` is a similar trap for the next person.

Recommendation: move all four to a clearly-labelled archive directory, or delete them, and treat any future need for them as a decision to make deliberately rather than inherit. Either way, note that running `dsc_rebase.py` produces Apple-derived binaries, which the standing commitment forbids committing.

## What was deliberately NOT done

The remaining gaps are knowable only because the dishonest shortcuts were available and refused. A future reader under time pressure deserves to see that list:

- **Mining a stripped DSC binary for the `os_log_pack_s` crash-path struct layout.** Refused. The layout is recorded as a PROVISIONAL, ravynOS-internal substitute in `private/os/log.h`, explicitly not claimed to match Apple's, and the true source (`os/log.h` / `os/log_mem.h` from a real macOS SDK) is named as the correct remedy.
- **Inventing `eventlink_port_pair_t`.** Refused — until B1 showed it does not need inventing, because the declaration already exists in `mach_types.defs`. Worth recording precisely because the honest answer turned out to be available.
- **Inventing `lck_spin_t` or a userspace `lck.h`.** Refused. `lck_spin_t` is defined in exactly one kernel-only header and `lck.h` does not exist in the tree at all; the correct next step is the B2 dependency measurement, not a fabricated declaration.
- **Fabricating a placeholder libSystem.** Refused. The 4,120-byte `libSystem.B.dylib` that does exist contains no code at all — only `LC_REEXPORT_DYLIB` entries — so it is a real library rather than a stub, and it re-exports 24 targets rather than a silently-shortened list.
- **Redistributing Apple binaries as a substitute for source.** Refused, including the six untracked ones in `tools/bootlab/assets/`, which were deliberately left un-ignored (A2) rather than hidden behind a `.gitignore` rule.
- **Dropping a re-export target to make a link succeed.** Refused. Every partial libSystem.B result in this effort was reported as a diagnostic, never installed, and the shortfall was written down instead.

## The derived SDK artifact gate is currently RED, and its verdict is NOT trustworthy

`tools/bootlab/check_sdk_artifacts.sh` (commit `4a37c54`) currently reports:

    rebuildable: 1    failed: 19    no build system: 3
    RESULT: FAIL -- the component(s) above cannot be rebuilt.

**The cause is a generalisation from a single data point.** To fix
`libCrashReporterClient`, which registers its archive under an absolute path when
`OBJROOT` is unset, the gate was changed to pass **absolute target paths to
everything** — and that broke the other 19. **The derivation is sound; the
verdict is not.**

Its own header already says it must not be trusted as a release gate and that a
red should be read as "investigate the gate first". That is the correct reading
and it is repeated here so this document does not present the gate as a working
guard.

> **Lesson: never generalise from one case instead of from the rule.** This is
> the same failure as a half-right hypothesis - and it produced **19 false reds
> in a single change**. A **named-broken guard is more useful than a green-looking
> one that lies**, so the honest label is the asset here, not the 19 reds.

## Entry point: DELIVERED and working

`tools/bootlab/build_all_libsystem.sh` is **committed** in `0a235e5`, **209 lines**,
and has **run end to end as committed**:

    21 stages passed, 1 known-blocked, 3 skipped, 0 unexpected failures
    (SUPERSEDED - see the baseline correction below. This was a --quick run that
     SKIPS 3 stages, one of which does not build. Do not quote it.)

The single known-blocked stage is `libSystem.B` on
`*** missing required libs *** system_trace` — a direct consequence of the B2
blocker. **That is a known block, not a broken build**, and not a regression in
the components that did build.

The hard gate `Libraries/check_sdk_stubs.sh` runs **last**, with `RAVYN_SDKROOT`
correctly exported, and correctly names **four pre-existing zero-byte BSD-tool
stubs outside the Libsystem set** — `libedit.dylib`, `libncurses.dylib`,
`libncurses.6.dylib`, `libutil.dylib`. That output is expected.

> ### What the driver PROVES, not just what it does
> It is **the first instrument in this project that runs the build the project
> actually runs**, rather than a targeted subset. **On its first execution it
> caught a regression that every targeted test had passed** — the 13-type mach
> shim breaking `libsystem_c` and `liblaunch`.
>
> **Therefore the remaining targeted verifications in this project should not be
> trusted on their own.** A green targeted test is evidence about a subset.

> **The driver's documented rule, which is the operational form of this session's
> central lesson:**
> **Never interpret output from a process that has not exited. Every stage waits
> for its child and judges on the exit code. Logs are kept for diagnosis and are
> never the evidence.**

## Closing status

## Three bounded, measured open items

The plan closes on **specifics**, not a general "remains".

1. **`libsystem_darwin`** — a live vendored shadow, worst case a **381-byte
   `stdlib.h` over 14,705**. **Measured, not yet fixed.** First thing to fix.
2. **The openbsm `version` data file** being included as `<version>` across **five
   components** — `dyld`, `liblaunch`, `libsystem_asl`, `libsystem_info`, `libxpc`.
   **Measured, not yet fixed.** Note removing it does not clear dyld; it moves the
   error to `cstddef:46`.
3. **The derived gate `4a37c54`** — still **unwired and untrustworthy, pending
   its own negative test. Deliberate.**

Each is measured, bounded, and attributable. None is open-ended.

## The dyld frontier, as measured 2026-09-26

`dyld` is now a **driver stage** (added to `tools/bootlab/build_all_libsystem.sh`).
It was already listed in `KNOWN_BLOCKERS` but had no stage, so its frontier was
only measured when someone remembered to build it by hand — which is how a
one-line undefined variable survived two rounds. Staging it means its error
signature appears in the standard run and any change is visible.

Two **independent** defects, not one with a cascade. This retests and confirms
the earlier negative result rather than repeating it.

**Defect 1 — CLEARED.** `Libraries/openbsm` exposes a **19-byte ASCII data file**
named `version` (contents `OPENBSM_1_2_alpha5`) at its root. **libc++ itself**
includes `<version>` for its C++20 feature-test macros — `bitset`, `ranges`,
`ostream`, `strstream`, `forward_list` all do — and on this case-insensitive APFS
volume the data file wins that include even though `c++/v1` is **earlier** on the
`-I` list. Measured, one variable at a time on a real dyld TU:

    openbsm present:  <version> -> Libraries/openbsm/version,  "unknown type name OPENBSM_1_2_alpha5"
    openbsm absent:   <version> -> $SDK/usr/include/c++/v1/version,  0 errors

The `-isystem`-beats-`-I` hypothesis was tested and **REFUTED**: `c++/v1`,
`libsystem_c/include` and openbsm all arrive as plain `-I`. Why the later path
wins is still **unexplained**; clang's only hint is
`-Wnonportable-include-path: specified path differs in case from file name on
disk`. Fix committed: drop the openbsm root from dyld's include path.

**Defect 2 — OPEN, and it is a class.** `cstddef:46` and `cstring:66` both report
that libc++ cannot find **its own** `<stddef.h>` / `<string.h>`, because
`Libraries/Libsystem/libsystem_c/include` — the second libc generation — wins
them. **Two independent instances measured.** Removing openbsm does **not** fix
these, which is the retest that confirms the earlier negative result.

> ### Correction to the inventory, and it matters
> `VENDORED-INCLUDE-INVENTORY.md` rates `libsystem_c/include` as **"intended"**
> for the libc build. **That verdict does not transfer to the dyld context.** The
> dyld result is the first measured evidence that the same path is **actively
> harmful** there. "Intended" is true for building libc; it is not a general
> licence, and this row should carry both verdicts.

## The `SDK_SOURCE_DIR` class — defined nowhere, used in four Makefiles

`SDK_SOURCE_DIR` is used but **defined in no Makefile in this tree**, so every
use expands to a root-absolute `/usr/include/...`. In dyld the four `-include`
forms failed immediately with
`<built-in>:1:10: fatal error: '/usr/include/AvailabilityInternal.h' file not found`.
All four Availability headers are present under the build SDK's
`usr/include`, so this was an undefined-variable defect, not a header-shadowing
problem. **Fixed in dyld only** (`6be42b49f8`).

Three further sites remain, **deliberately untouched** — one defect at a time,
and the driver shows those stages passing so the defect is latent there:

- `Libraries/libfirehose_kernel/Makefile:19`
- `Libraries/Libsystem/libsystem_c/libBase/Makefile:112`
- `Libraries/Libsystem/libsystem_c/libNetBSD/Makefile:16`

This is written down as a **class** so the remaining sites get fixed
deliberately rather than discovered.

---

# BASELINE CORRECTION, 2026-09-26 — read this before quoting any driver number

## The trustworthy figure

    stages passed 22   known-blocked 2   skipped 0   UNEXPECTED failures 2
    unexpected: libdispatch, libsystem_darwin
    check_sdk_stubs.sh  PASS
    RESULT: FAIL

**A full run, with nothing else touching the tree, is the only number worth
quoting.**

## What was wrong with the number quoted before

`24 passed / 2 known-blocked / 0 unexpected failures` appears throughout this
plan and in `libSystem.B_STATE.md`. **It was a `--quick` run that skips 3
stages, one of which does not build.** Every "0 unexpected failures" claim made
against it is weaker than it looked. This is the project lesson about baselines
applied to a baseline: *a baseline which omits stages is not a baseline.*

## Neither failure is a regression from this session's work

**`libdispatch`** — `__c11_atomic_store` / `__c11_atomic_fetch_sub` reported as
"no member" of namespace `os_atomic_std`, at
`Kernel/xnu/libkern/firehose/chunk_private.h:173,187,189` (chain
`block.cpp:31` -> `internal.h:1136` -> `firehose_internal.h:39` ->
`firehose/private.h:29`). Compiled as C++, `os_atomic_std` resolves to a
`std::atomic` implementation lacking the C11 names.

**Proven pre-existing**: it fails identically with `isysroot-cc` from `1f0e802`,
i.e. before **both** force-includes this session added. Open question: whether
the C++ branch is genuinely incomplete, or a guard is defeated by include order.
**Any fix belongs in the atomic header's configuration or the include path —
never in `chunk_private.h`, which is kernel libkern.**

**`libsystem_darwin`** — `os/assumes.h:130,134,157`, undeclared `os_log_...`.
Broke either way. The `stddef.h` revert removed a **different** class (14
occurrences at `sys/resource.h:203`), but this component was already broken
before that revert.

## 2026-09-27 — `run.sh full` was BLIND, the boot gate now exists, and the next fault is NOT ours

### The instrument was the defect

`run.sh full` — the project's headline acceptance test — reported a clean boot:
kernel banner, PID 1 banner, `/hello.txt` read, `alive tick 1..3`, **zero real
traps** (`tools/bootlab/work/serial_full.log`). It also **execed no dynamic
binary at all**: its PID 1 is `init/init_static.c`, a static LC_UNIXTHREAD
program that prints and spins. So dyld, the libSystem closure and every
dylib-linked `main()` were untested, and the gate was green on a path it never
reached. The previously recorded E1 fault (`dyld-fault: pid=2
cr2=0x7f805691e9a8 rip=0x7f8028001806 err=4`) was therefore **not reproduced by
the test — it was invisible to it.**

Closed by `tools/bootlab/run_dynamic_gate.sh` (`run.sh dynamic`): a static
exec-runner (`init/init_exec_dynamic.c`, LC_UNIXTHREAD, no dyld, so the only
dynamic process in the boot is the one under test) staged as PID 1 via
`manifest_dynamic.json`, which `execve()`s the dylib-linked `/bin/echo`.
Wired into the driver as known-blocked stage `dynamic_userland`, the same
treatment `dyld` gets.

**The verdict contract, and the part that matters most:**

| exit | meaning |
|---|---|
| 0 | `/bin/echo` reached `main()` (it prints `RAVYN-DYNAMIC-USERLAND-OK`) |
| 1 | blocked: dyld/kernel fault, signature printed verbatim |
| 2 | **harness fault — the kernel never booted. Never a kernel verdict.** |

Judged only on the serial log, read **after** the boot process exits. Exit 2
exists so the harness cannot blame the kernel for its own failure: the
firmware-stage `#UD` at `RIP 0xB0000` ("Can't find image information") looks
identical to a fault in the log and is not one.

**Cost: 205 s–358 s across two full runs — 40–55% of the loop.** The spread is
build caching, not variance in the gate. `BOOTLAB_SKIP_DYNAMIC=1` keeps it out
of the fast path. Recorded as a cost because a gate that dominates the loop
eventually gets skipped by habit, and a habitually-skipped gate is
indistinguishable from no gate.

> **Compare the signature, never the address.** Across three runs the fault is
> byte-identical except for the panic **caller address**
> (`0xffffff80184cc739` / `0xffffff8018ecc739` / `0xffffff80108cc739`). That
> movement is kernel slide. A gate that alerted on the address would report a
> new fault on every boot.

### The 6,856-byte `libobjc.A.dylib` stub was a trap, and it is the argument for checking EXPORTS

The gate's first run died with `Library not loaded:
/usr/lib/libobjc.A.dylib`, referenced from `libsystem_symptoms.dylib`: nothing
staged it. The file sitting in `assets/usr/lib/` was **not** a usable
substitute. Measured:

| | staged stub | real artifact |
|---|---|---|
| size | 6,856 B | 1,608,088 B |
| defined symbols | 45 | 2,145 |
| `_objc_msgSend` | **defined, as a no-op at `0x540`** | defined, real |

**Shipping the stub would have converted a loud dyld abort into a silent wrong
answer** — the first time anything called an Objective-C method, `_objc_msgSend`
would return whatever the empty stub returned, with no error anywhere. That is
precisely the failure class `check_sdk_stubs.sh` exists to prevent, and it is why
**a gate must check exports, not size**: the stub is a valid Mach-O, is named
correctly, sits at the right path, and is 0.4% of the right size. Size alone
would have passed it.

`tools/bootlab/stage_dynamic_libs.sh` now copies the real artifact out of the
generated SDK on every run and verifies size, export count and `_objc_msgSend`.
**It was negative-tested** — a 4,200-byte fake was planted and the gate was
confirmed to reject it — because a gate never seen red is the same defect as the
derived artifact gate's 19 false reds. It is copied, not committed: it is a
build product of our own `objc4` and `assets/usr/lib/*.dylib` is gitignored, so
a committed blob would rot silently against `objc4`.

### With libobjc staged, the NEXT fault is CoreFoundation — and it is NOT ours

    Library not loaded: /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
      Referenced from: <19C9DA96-742F-3A7D-A22D-E1DF683CE47B> /usr/lib/system/libxpc.dylib
      Reason: tried: '.../CoreFoundation' (no such file, no dyld cache)
    pid 1 exited -- exit reason namespace 6 subcode 0x1
    panic(cpu 0 caller 0xffffff8018ecc739):  initproc failed to start -- exit
      reason namespace 6 subcode 0x1 description: Library not loaded

**Assessed, deliberately not chased. It is an inherited Apple dependency:**

- **Our `libxpc` does not use CoreFoundation.** Measured across
  `Libraries/Libsystem/libxpc` (8 `.c` files): **0** occurrences of
  `CoreFoundation` in any include, **0** `CF*` symbols. Its `Makefile` links
  `dispatch system_c system_platform system_kernel system_blocks
  system_malloc launch dyld system_pthread` and **no framework at all**.
- The CF edge is a **non-weak** `LC_LOAD_DYLIB` in
  `assets/usr/lib/system/libxpc.dylib` (v3102.160.5) — an **Apple dyld
  shared-cache extract**, not a source build. It is the only blocking missing
  dependency of that binary: of its 22 load commands, 20 are staged, and the
  other absentee (`XPCSupport`) is **weak**, so dyld tolerates it.

**Size of the prize, for whoever picks this up:** `Frameworks/CoreFoundation`
source **is in this tree** — 5.5 MB, 160 C/ObjC files, **87,013 lines**, 44
public headers, with a bmake-dialect `Makefile` whose
`INSTALL_NAME_DIR = ${SLF}/CoreFoundation.framework/Versions/A` is exactly the
path dyld is asking for. So it is **obtainable here**, unlike the genuinely
absent components. But there is **no CoreFoundation binary in the generated SDK**
to stage instead, and it is a *framework* — a materially larger build than
anything else in the current closure.

> **Recommendation: do not build CoreFoundation.** It is not on the critical
> path of our stack, because our `libxpc` has no such dependency — it is on the
> critical path of the *Apple extract stopgap*. `Libraries/Libsystem/libxpc`'s
> default target is already `all: ${.OBJDIR}/libxpc.dylib`, so replacing the
> extract with our own removes the CF edge outright. That is the
> provenance-correct fix and it is far cheaper than building an 87,013-line
> framework to satisfy a dependency we do not have. **Re-measure after the swap;
> only if CF still appears is it genuinely ours.**

### Attribution correction — my own earlier caveat was wrong

I previously reported that `libsystem_darwin`'s pre-existing status "is not
cited in the notes". **That was wrong**, and the error is worth recording: I had
grepped a single commit's diff instead of reading this plan. `libsystem_darwin`
> **is** recorded above, at "Neither failure is a regression from this session's
 work": *`os/assumes.h:130,134,157`, undeclared `os_log_...`; broke either way;
> already broken before that revert.* The independent scope proof (every change
> confined to `tools/bootlab/`; `Libraries/`, `Kernel/xnu`, `build-libraries.sh`,
> `isysroot-cc` untouched) agreed with it. The lesson is the one already recorded
> in this document under *measurement caveat*: a grep of a diff is not a reading
> of the record.

## The 7.9 KB placeholder stubs — three outcomes, and the shape matters more than the count

| outcome | which | note |
|---|---|---|
| **DELETED** | `libcache`, `libquarantine`, `libsystem_collections`, `libsystem_configuration`, `libsystem_containermanager` | 0 inbound `LC_LOAD`, 0 `-l` references, no re-export, **and no source in the tree** |
| **BUILT** | `libcommonCrypto` | pure re-export over the real `libcorecrypto`: 53,608 B, 74 exports |
| **REAL WORK** | `libsystem_kernel`, `libdyld` | the actual project |

**A placeholder nothing links is a liability**: a future consumer links it and
gets a silent no-op. The record must say: **do not re-create these by inventing
a source tree.**

> **`libcommonCrypto`'s 0 exports is NOT a defect.** It is a re-export wrapper
> and it fails loudly on load rather than silently doing nothing. Do not "fix"
> it by adding code.

## `libsystem_kernel` — real progress, and the one error that remains

**Stubs now fully assemble.** The `.cfi_endproc` imbalance is fixed:
`LEAF_FUNCTION_PROLOGUE` never emits `.cfi_startproc`, so there was never a
region to close — and the same imbalance existed in five hand-written custom
stubs.

**The `unwind_epilogue` paradox is solved.** The token is `UNWIND_EPILOGUE`
**uppercase**; the assembler case-folds it in diagnostics, which is why it
appeared lower-case in every error. The SDK's vendored `asm_help.h` had
`UNWIND_PROLOGUE` / `UNWIND_EPILOGUE` stripped. Restored **verbatim from Apple's
own header**, preserving ravynOS's x86_64 port, and **proven durable by deleting
the generated file and re-syncing** — it regenerates correctly.

A mach census found **15 constants across 7 headers** needed from in-tree xnu,
each sourced verbatim with its source line named, also durability-proven.

**One error remains**: `coalition_info_debug_info` conflicting types, with
**byte-identical declarations in both contexts**. So the divergence is a
**typedef resolving differently under `__DARWIN_ONLY` / cdefs**, not a source
disagreement. **Diagnosed, not patched.**

## Two measurement lessons — the most reusable things here

**(a) Check which tree WINS before concluding a symbol is absent.** The mach
census verified `usr/include/mach` while
`System.framework/.../PrivateHeaders/mach` was what actually won — so
verification **passed and the build failed simultaneously**. A clean check on the
wrong tree is not a check.

**(b) A driver result is only meaningful when nothing else is touching the
tree.** A run was invalidated by the reader's own concurrent builds. Both have
now cost real rounds.

## Honest unknowns — preserved with their caveats intact

- **Load closure: 272 undefined / 133 unprovided, 126 attributed to
  `libsystem_kernel` — UNVERIFIED**, and untested because the library has never
  linked. The number is measured; its interpretation is not.
- **dyld: 2 objects, unmoved across several rounds.** `<version>` is cleared;
  the current frontier is `corecrypto/ccdigest.h` not found.

---

## dyld — the honest headline (2026-09-26)

**dyld has made NO progress across many rounds.** The frontier has not moved
from `corecrypto/ccdigest.h` not found. The `<version>` fix and the
`SDK_SOURCE_DIR` fix were real, but **neither moved the object count.**

**Object count: 1**, measured by a clean-slate rebuild
(`find . -name '*.o' -delete` then a full `bmake`). The method is recorded with
the number, because the number without the method is what caused 2 to be
over-quoted earlier.

**The mechanism by which the overlay fails to win the `corecrypto` include is
UNESTABLISHED.** Known: the header is **present and complete** at
`Kernel/xnu/EXTERNAL_HEADERS/corecrypto/ccdigest.h`, 6,285 B, a genuine Apple
header. The open question is the *mechanism*, not the absence. Not re-attempted
— it has consumed two rounds and produced nothing.

**Third measurement lesson, collected with the other two:**

> **Substituting the thing you are measuring cannot answer a question about
> it.** The trace was done by replacing `isysroot-cc` with a logging shim, which
> bypassed `overlay_for` entirely. The correct instrument is to log from
> *inside* the wrapper, or tee the real invocation after it has run.

All three now stand together: *check which tree wins*; *a driver result is only
valid on a quiet tree*; *do not instrument by substitution*.

## libxpc swap — executed and re-measured (2026-09-26)

Staged **our** source-built `libxpc.dylib` in place of the Apple DSC extract at
`tools/bootlab/assets/usr/lib/system/libxpc.dylib`.

| | before (Apple DSC extract) | after (ours) |
|---|---|---|
| size | 559,470 B | **132,672 B** |
| exports | 667 | **241** |
| CoreFoundation `LC_LOAD_DYLIB` | non-weak, v5026.6.7 | **none** |

Backed up to `/tmp/libxpc.apple-orig.dylib`; the swap was run twice and the
staged size was stable, so it is **idempotent** and reversible.

**Boot gate after the swap: GREEN.** `tools/bootlab/run.sh full` exited 0,
serial 36,811 bytes, **7 alive-tick lines, 0 panic/trap lines**, with
`RAVYNOS USERLAND SUCCESS: DYNAMIC BINARY CAT RUNNING AS PID 1` and
`Hello from /hello.txt via dynamic cat and staged libSystem!`

> **CoreFoundation did NOT reappear after the swap.** The earlier assessment —
> that the CF edge is a non-weak `LC_LOAD_DYLIB` inside the Apple extract and
> not ours — is confirmed, not corrected.

> **Read this honestly: the boot was already passing before the swap, so this is
> evidence the swap broke nothing, NOT evidence that it fixed anything.** The
> original goal — dynamic `/bin/echo` reaching `main()` — is unchanged; the
> closure is still 272 undefined / 133 unprovided, and 126 of those remain
> attributed to `libsystem_kernel`, which has never linked.

---

## CORRECTION: my earlier "GREEN" was a FALSE POSITIVE

I reported the boot gate green on the strength of these serial lines:

    === RAVYNOS PERSISTENT INIT RUNNING AS PID 1 ===
    === RAVYNOS USERLAND SUCCESS: DYNAMIC BINARY CAT RUNNING AS PID 1 ===
    Hello from /hello.txt via dynamic cat and staged libSystem!

**Those are the standard static init's banner. They are not evidence that
`/bin/echo` ran.** `grep -c RAVYN-DYNAMIC-USERLAND-OK tools/bootlab/run.sh`
returns **0** — the gate I ran never checks the marker, and it boots the
**standard** image (`manifest.json`), not `manifest_dynamic.json`. A gate that
boots the standard image and reads the serial log sees the static banner and
calls it a pass. That is the same defect class as the loud abort converted into
a silent no-op: a gate reporting success without measuring its property.

**The correct gate is `tools/bootlab/run_dynamic_gate.sh`** (4,031 B), which
declares `PASS_SIG="RAVYN-DYNAMIC-USERLAND-OK"` and a three-way exit: 0 PASS
(`/bin/echo` ran and printed the marker), 1 BLOCKED (dyld/kernel fault), 2 HARNESS.
I ran the wrong script.

## The real dynamic verdict: BLOCKED, exit 1

    Library not loaded: /usr/lib/system/libobjc.dylib
    pid 1 exited -- exit reason namespace 6 subcode 0x1,
      description Library not loaded: /usr/lib/system/libobjc.dylib
    panic(cpu 0 caller 0xffffff80066cc739): initproc failed to start --
      exit reason namespace 6 subcode 0x1
      description: Library not loaded: /usr/lib/system/libobjc.dylib

**Not chased**, per instruction. But the next edge is already identified: the
asset `usr/lib/libobjc.A.dylib` is the **6,856-byte `build_stubs.sh` stub** — the
one flagged in the very first Apple-binary audit as "not the Apple library at
all". Our real build is **1,608,088 B with 1,808 exports**. This is the same
one-line swap as `libxpc`, and it is a **harness** defect, not a code one.

## Dynamic gate progress: the libobjc staging fix WORKED, and the next edge is the libc closure

After staging the real `libobjc` at `/usr/lib/system/libobjc.dylib`, the dynamic
gate's fault changed shape. Recorded verbatim, **not chased**:

    pid 1 exited -- exit reason namespace 6 subcode 0x4,
      description Symbol not found: ___mb_cur_max
    panic(cpu 0 caller 0xffffff8007acc739):  initproc failed to start --
      exit reason namespace 6 subcode 0x4
      description: Symbol not found: ___mb_cur_max

**The subcode moved from 0x1 to 0x4.** `0x1` was "Library not loaded";
`0x4` is "Symbol not found". **libobjc now loads** — the staging fix is
confirmed by the fault changing, which is the right way to know a fix worked.

The next edge is a **C library** symbol: `___mb_cur_max` is `__mb_cur_max`, the
`mbstate` global, Mach-O-prefixed. So the dynamic path has cleared its Objective-C
runtime dependency and is now stopped by the **libc closure itself** — the same
272 undefined / 133 unprovided set. Not chased; that needs the decisions
pending with the user.

**This is also a working demonstration of the gate's value**: the earlier green
was a false positive on the wrong image, and once run correctly it has produced
three distinct, informative faults (`libobjc` not loaded -> `__mb_cur_max` not
found -> next) rather than one undifferentiated "fails".
