# Status and open decisions

Final consolidation. Documents only; no source changed. This records what was
measured, what was proved, what was refused, and what the user still has to
decide. Reasoning history is preserved rather than rewritten, including the
things that were wrong and how they were caught.

---

## 1. BASELINE OF RECORD

    stages passed 23   known-blocked 3   skipped 0   UNEXPECTED failures 2
    unexpected failures: libdispatch, libsystem_darwin
    check_sdk_stubs.sh  PASS
    RESULT: FAIL (expected; the two failures are the known pre-existing pair)

Full run, 0 skipped, serial, alone, **0 builders confirmed** immediately before
launch. `libsystem_c` compiles in 143 s to **693 objects with 0 compile
errors**.

**CORRECTION 2026-09-27 — the `rc=0` half of this gate is stale and was
flagged by `critical-path`, not by me.** The gate was written as "693 objects,
rc=0" and the rc half cannot be reproduced, because the single failure is at
**LINK**, not compile:

    ld: library 'system_trace' not found
    clang: error: linker command failed with exit code 1

That is sec. 20's documented `libsystem_trace` blocker — `lck_spin_t` is
KERNEL-PRIVATE, and `os_log_buffer_s` / `os_log_buffer_context_t` exist in no
file anywhere in the tree or the SDK — and it has nothing to do with mach
headers. It is expected, pre-existing, and byte-identical in both probe arms.

**The gate is therefore "693 objects, 0 COMPILE errors", with the link failure
recorded separately as a known arm-independent failure.** The number is
unchanged; only the stage of the build at which it is read has changed. Left
as it was, any future run that correctly reproduced 693 objects and 0 compile
errors would be recorded as FAILING the baseline purely because a known
unbuildable component is still in the link line.

**What this gate does and does not cover.** It brackets the mach-header
generation only. It cannot detect a change to `isysroot-cc`, because
`libsystem_c` is pure C and the shim change is provably inert there (0
`.cpp`/`.cxx`/`.CC`/`.mm` sources, and 0 `-include` arguments across 697
captured invocations). A C++ regression is invisible to this gate by
construction, and the one instrument that would see it is the full driver run.

**Re-verified identically after the `isysroot-cc` `-x` fix**, which was a change
to a file on every component's path. The argv capture shows the fix is neither
absent nor over-broad:

    plain C                       0 force-includes
    -ObjC -x objective-c          0    <- was 1 before the fix
    -x objective-c++              1    <- guard not over-tightened
    .cpp source                   1    <- still works

So: **verified, not assumed.**

### The two unexpected failures, both pre-existing

    libdispatch        Kernel/xnu/libkern/firehose/chunk_private.h:173,187,189
                       __c11_atomic_store / __c11_atomic_fetch_sub are "no member"
                       of namespace os_atomic_std. Reached via block.cpp:31 ->
                       internal.h:1136 -> firehose_internal.h:39 -> private.h:29.
                       Compiled as C++, os_atomic_std resolves to a std::atomic
                       implementation lacking the C11 names, so the __cplusplus
                       branch is not taken as expected.
                       PROVEN pre-existing: fails identically with isysroot-cc
                       from 1f0e802, before both force-includes.

    libsystem_darwin   Libraries/Libsystem/libsystem_c/os/assumes.h:130,134,157
                       use of undeclared identifier 'os_log_...'
                       This is what remained AFTER the stddef.h revert removed
                       the entire uint8_t class (14 occurrences at
                       sys/resource.h:203 in the pre-revert run).

Neither source was edited. `chunk_private.h` is kernel libkern under
`Kernel/xnu`; `assumes.h` is under `libsystem_c`.

### The `--quick` figure that was never a baseline

Every "0 unexpected failures" claim made in this project was measured against a
`--quick` run, which **skips 3 stages**. A full run has 0 skipped, and
`libdispatch` is one of the stages `--quick` does not build — and does not
build. Quote the full-run figure from now on.

---

## 2. THE MACH GENERATION QUESTION

### Versions, identified

    in-tree xnu   Darwin 24.0 / xnu-11215   (Sonoma; 2021-2022 copyright years)
                  git 394fe3eac3 "Transplant Darwin 24.0 (xnu-11215) kernel"

    SDK mach tree ravynOS 0.7, "macOS 10.15 compatible"   (Catalina; 2019 years)
                  SDKSettings.json; newest mach copyright 2019; last touched by
                  51cd14312f "Support building ravynOS on Linux (#543)"

**Four xnu generations apart.** `libsyscall` ships inside xnu-11215 and asserts
on xnu-11215 semantics, so it targets the newer generation unambiguously. These
are the identifiers the trees actually carry; there is no build number in the
SDK mach headers, and no finer relationship was guessed.

### The migration, sized correctly

    headers in the SDK mach tree        123
    headers in osfmk/mach                85
    present in BOTH                      77
      differ                             54
      identical                          23
    SDK HAS, osfmk LACKS                 45   <-- would be DELETED by a swap
    osfmk HAS, SDK LACKS                  8

A naive `osfmk/mach` -> SDK swap is **54 modified plus 45 deleted**, including
`task.h` — the header whose `mach_msg_aux_header_t` and
`coalition_info_debug_info` failures started all of this. It is a **merge, not a
copy**, which is why quoting "54 files" overstates the job.

**But the judgement-per-header work is 14, not 46:**

    total headers in the set          46
    in osfmk-11215                     0
    referenced by libsystem_c         14   <- the real work
    NOT referenced by libsystem_c     32   <- mechanical, keep the SDK copy

    3,562 references across the 14; task.h alone is 273 of libsystem_c's 693
    objects, and eleven more sit at 273.

Per-header table with dispositions: `tools/bootlab/MACH-HEADER-POLICY.md`.
`libsystem_c` references **none** of the 16 hand-sourced bridge items, so it is
green *despite* the mix rather than because of it.

### The probe: NOT MEASURED, and not attempted again

    CONTROL    rc=0   693 objects   0 errors     <- rc is a COMPILE-stage
    TREATMENT  rc=0   693 objects   0 errors        figure here; see §2. The
                                                    link stage fails identically
                                                    in both arms on
                                                    system_trace (sec. 20).

    grep -c probe_osfmk_mach <treatment build log>  ->  0

The overlay was never consulted by a single translation unit. The two arms were
the same build. **Not "survivable", not "not survivable" — not measured.**

Two reasons the arms were void:

1. `EXTRA_INCLUDES` does not survive `build-libraries.sh`'s environment
   sanitisation into the bmake sub-makes, so it never reached `isysroot-cc` on
   the build path. The direct-wrapper proof was valid; the build path was not
   wired.
2. `libsystem_c/darwin/compatibility.c` includes **no mach header at all**, so
   it could never have exercised the overlay under any circumstances.

**The finding that generalises: a treatment arm is evidence only if the build
log shows a non-zero hit count. Green-on-both-sides is the failure mode to fear,
not red.** A collapsed probe is a finding; a probe that silently did nothing is
not, and it looks identical to success in the summary.

The `EXTRA_INCLUDES` passthrough is committed and proven inert (byte-identical
argv unset vs empty; +1 argument when set; byte-identical for assembler inputs
via the gate). It is a measurement tool only. No component sets it and the build
does not depend on it.

### The bridge has a hard limit — recorded so it is not crossed again

Sourcing 15 constants and one struct across the generation boundary was safe and
was done. The limit is a **coordinated port-numbering scheme**:

    libsyscall/mach/port_descriptions.c:80
      _Static_assert(HOST_DOUBLEAGENTD_PORT == HOST_MAX_SPECIAL_PORT, ...)

The sourced constant is NOT wrong — in-tree and SDK agree byte for byte. The
divergence is that the SDK sets `HOST_MAX_SPECIAL_PORT = HOST_FAIRPLAYD_PORT`
while xnu asserts `HOST_DOUBLEAGENTD_PORT`. These are not independent
constants: they encode an ABI contract with the kernel, and **a wrong port
number does not fail to compile — it silently routes to the wrong port.** Not
sourced across the boundary. Deliberately.

If a future generation reconciliation is funded, the 16 hand-sourced items
become redundant and **must be reverted in the same commit as the migration**,
not in a follow-up. Leaving them in place is how a chimera forms.

---

## 3. libsystem_trace

**The source is there, and it still cannot be built.** 1,004 real lines —
`log.c`, `signpost.c`, `init.c`, three headers, a `Makefile`. Filing it as
"no source, never obtainable" was wrong. That does not make it buildable.

Three types it needs, checked by **bare name** across the whole tree and the SDK:

    lck_spin_t              ONE definition tree-wide, and it is KERNEL-PRIVATE:
                            Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/i386/locks.h:42
                            inside #ifdef MACH_KERNEL_PRIVATE, member uses
                            __kernel_data_semantics. No userspace declaration
                            exists anywhere.
    os_log_buffer_s         0 files anywhere -- tree or SDK
    os_log_buffer_context_t 0 files anywhere -- tree or SDK

`Kernel/xnu/libkern/os/log_mem.h:36` uses all three unconditionally. Building it
would require **inventing two struct layouts and a userspace ABI for a kernel
lock primitive**. Refused. This is a design decision, not a build blocker, and
it is not ours to make by guessing.

**`lck_spin_t` is kernel-only, not unsourceable.** That question has been open
since the original handoff and is now closed with evidence. It is exactly why a
userspace `lck_spin_t` shim was never going to be right, and someone will
otherwise try it — this paragraph exists to stop that.

The staged Apple binary (version `1861.160.4` against our Makefile's
`1147.0.3`) was **not touched**. Staging an untested replacement is the
`libobjc` trap.

---

## 4. THE FIFTEEN COMPONENTS, CORRECTED

It is **fifteen, not ten**. "10 of 12" was an unverified subtraction and was
wrong. `libsystem_trace` was wrongly in the list. Three further components with
no source exist: `libkxld`, `libsystem_trial`, `libunc`.

**"0 references from anything we stage" was wrong, not stale.** All fifteen are
referenced by the boot image: 32 non-weak, 1 weak, 15 re-export, 3 upward. The
mechanism is that the staged Apple `libSystem.B.dylib` re-exports all fifteen and
`/bin/echo` has a single load command naming that dylib, so every one is
reachable at run time.

**The SDK half of that claim was correct:** none of the fifteen exists in the
SDK at all. "Unreachable" was a statement about the SDK tree, not the boot
image, and the two were conflated.

---

## 5. THE STUB ANSWER — this drives the decision

A stub for these would **fail loudly**, not silently:

    at library load          subcode 0x1
    at symbol binding        subcode 0x4   (161 imported symbols across 19
                                              staged dylibs)

That is the exact error class the boot is stopped on right now. **The
silent-no-op mode this project exists to eliminate is NOT reachable for the
eight load-bearing components.**

It **is** live for the seven dormant, which import zero symbols:

    libkeymgr   libcache   libsystem_secinit   libsystem_eligibility
    libsystem_sanitizers   libsystem_configuration   libsystem_networkextension

**Loud for eight, silent for seven.** That asymmetry is the fact the user needs
for the stub decision.

---

## 6. THE PATTERN ACROSS FOUR COMPONENTS

More useful than any single result, and it predicts where the next component
will fail:

> **The xnu sources are present and the types they need are not.**

- A coordinated port-numbering block that cannot be sourced in pieces
  (`port_descriptions.c`).
- Two absent struct layouts and a kernel-only lock type (`libsystem_trace`).
- A stale-vs-in-tree include-order collision (`mach/message.h`).
- A census that was complete for its own method and invisible to a struct
  definition (`struct coalinfo_debuginfo`).

In each case the blocker is a **missing declaration, not missing code**. This is
a design question, not a build one, and it is the framing to take to the user.

---

## 7. STANDING CAVEATS — verbatim

> **Closure: 272 undefined / 133 unprovided, 126 attributed to
> `libsystem_kernel` — UNVERIFIED.** Untested because the library has never
> linked. Not confirmed, not falsified. Every round it has stood on nothing.

> **dyld: 8 objects, up from 1**, frontier moved twice. See §7 detail below.

**RESOLVED 2026-09-27 -- mechanism established, and it was not an include
problem.** A comment block sat *inside* the backslash continuation of
`COMMONFLAGS` in `Libraries/dyld/Makefile`, so bmake ended the assignment
there and four `-I` paths -- including `-I Kernel/xnu/EXTERNAL_HEADERS` --
never reached the compiler. `clang -E -v` on the real command shows **zero**
`corecrypto` directories on the search list: the header was never absent and
never a stub, the directory was simply not on the command line. Fixed by
moving the comment above the assignment (commit 37f7cd727f). Full analysis in
LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 22.

**Second frontier, now also cleared: the libc++ shim class.** `Tracing.cpp`
died with 20 errors across `cstddef`/`cstring`/`cstdlib`/`climits`/`cctype`/
`cwchar`/`cwctype`. Cause is a **guard collision, not search order**: libc++'s
`c++/v1/<name>.h` declines to define `_LIBCPP_<NAME>_H` when the C header is
already open (its `#if defined(__need_size_t)` first branch), so `cstddef`'s
own include is a no-op and the `#ifndef` fires. Moving `c++/v1` ahead of the
shadowing `-I` was tried and **cannot** work — 20 → 7, `cstddef:46` still
fires. Fix is to force-include the shim family, as `stdint.h` already was.

Two traps, each of which cost a round and are now encoded: the set must be
**derived** from libc++'s own cxxx wrappers (a hand list missed `stdio.h` and
the build failed on the very next header), and `stddef.h`/`stdint.h` must come
**first** (the same 17 shims alphabetically score 5 errors, because `ctype.h`,
`float.h` and `math.h` sort ahead and drag the C headers in behind).

```
    COMMONFLAGS truncation fixed (sec. 22)      2 objects
    + libc++ shim family                         8 objects
    + cache self-invalidation                    8 objects  (no regression)
```

The object count is **Mach-O objects only**, per `file(1)`, excluding the
makedepend artifact `.depend.._src_glue.o` and the pre-existing deleted
`unit-tests/bar.o`. A raw `find -name '*.o'` over-reports. This counting
method is stated every time because the number without it is not reproducible
— it is why earlier rounds reported 1, 2 and 3 for overlapping work.

**Inertness of the shared-wrapper change**, full argv captured from the
committed wrapper and from the new one and compared byte for byte: plain C,
`-ObjC -x objective-c`, `-x assembler-with-cpp`, and C++ with no libc++ on the
path are all **byte-identical**; only C++ TUs with libc++ present differ
(`-include` 1 → 17). The `-x` guard from sec. 21 is preserved.

**Cache defect found and fixed**: `overlay_for`'s stamp is keyed on `$src`, but
the strip list lives in the wrapper body — so editing it silently reused the
stale overlay and reported success. `libcxx_shim_list` reproduced the same
defect in new code. Both now also test `[ "$0" -nt "$stamp" ]`, proven by
forcing the stamp to 2000-01-01 and asserting it advances. Details and the two
ways to test it wrongly are in sec. 24.

**Next blocker (sec. 25)**: `liblaunch/vproc_priv.h:31: fatal error:
'sys/bsm/audit.h' file not found`. Commit a6e2c35015 dropped
`-I .../Libraries/openbsm` *entirely* to clear its 19-byte `version` data file,
removing the hazard and the `sys/bsm/*` headers together. Not yet fixed.

**Not validated by a full driver run** — the only instrument that could show a
regression in a component that was green. That run was reserved by the user.

## 8. WHAT THE USER STILL HAS TO DECIDE

1. **Fund the mach reconciliation, or not.** The number is 14 headers, not 46.
   Recommendation remains **do not fund yet**; the probe is unmeasured, and the
   policy document plus the reference count are enough to decide without it.
2. **The stub decision**, on the loud-eight / silent-seven asymmetry in §5.
3. **`libsystem_trace`**: the Apple binary is staged where we have our own
   unbuildable source. That is a live legal exposure, and building ours would
   require inventing ABI. Neither is recommended without a decision.
4. **`libdispatch` and `libsystem_darwin`**: known-broken with written causes.
   Both fixes belong in header configuration or the include path — never in
   `chunk_private.h`, which is kernel libkern.
