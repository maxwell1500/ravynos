# libSystem.B and the component dylib state

**This is the authoritative record.** It replaces anything previously known
only from chat. Verified 2026-09-26 against the real build by one agent and
independently spot-checked at the SDK level by another.

> **Last reconciled 2026-09-26, after corecrypto landed.** Before that this
> document said 21 REAL and recorded corecrypto as a stub with a missing build
> system. corecrypto now builds, so the tally is **22 REAL when
> `usr/lib/system/libcorecrypto.dylib` is present in the SDK and 21 when it is
> not** - see its section, the file is currently unstable. A copy saying a flat
> 21 is a pre-corecrypto snapshot.


## `libsystem_kernel` is blocked on TWO independent things

**Not** blocked on absent code. The 126 unprovided libc symbols **do not need
source this tree lacks** — they are its syscall stubs and mach traps, built from
`Kernel/xnu/libsyscall` into `libsyscalls.a` and `libmach.a`.

**Syscall half.** `create-syscalls.pl` generates **454 stubs and a correct
`SYS.h` cleanly**, but they will not assemble:

    ___accept.s:9:354: error: invalid instruction mnemonic 'unwind_epilogue'

The string `unwind_epilogue` is in **NO file in this tree** (verified by grep),
and `-E` and `-c` output are **not line-aligned** for the same input.
**Mechanism unresolved — do NOT record a cause.**

**Mach half.** Needs `mach_service_port_info_data_t`, which the SDK's generated
`port.h` does not contain (0 occurrences; declared only at
`mach_types.defs:523`). Generation was rejected at
`$SDK/usr/include/mach/std_types.defs:65` (`import <Availability.h>;`), a file
byte-identical between the SDK and the in-tree xnu output. It persists with
`-nostdinc`, so it is **not** a resolution problem.

**CORRECTION:** the SDK's mach tree is a **123-header superset** of the in-tree
107, not an older subset. The SDK is not missing output the in-tree build has;
**every generated header in this tree is OLDER than its own `.defs`.**

Both are **single named unknowns**, not open-ended work: one assembler-path
resolution, one generation step. The full chain — the build is gated on
**reaching** them, which is gated on the mach headers, which is gated on the
generation step — is:

A `Subsystem` scaffolding wrapper cleared the earlier `no SubSystem declaration`
barrier on `mach_types.defs`, so generation proceeds one level deeper and fails
here. The file is **byte-identical** between the SDK and the in-tree xnu output
(verified with `cmp` against `EXPORT_HDRS/osfmk/mach/` and
`BUILD/dst/usr/include/mach/`), which **suggests an invocation problem rather
than a corrupt input - but that is not established.** Everything on the critical
path is downstream of this one line.

**The `mach_port_t` typedef family is CLOSED and committed (`3a27bba`).** 12
members, each sourced verbatim from the userspace branch of
`Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/mach/mach_types.h`, each individually
guarded, plus `eventlink_port_pair_t` carried by hand because it is array-form.
Verified by preprocessing a TU using all 12, 0 errors. **No invented
declarations anywhere.**

The derivation rule, so it is reproducible rather than extended by hand: emit only
`typedef mach_port_t <name>;` lines from the in-tree userspace branch, filtered
against the SDK's declared names extracted with a **GENERAL** parser. Three
approaches failed first: strict-pattern dedup (matched nothing in the SDK's
formatting, proposed 40 redefinitions) and two general-diff rules. The working
asymmetry is **strict pattern on the source side, general parser on the SDK side.**

## libSystem.B.dylib itself

Real, built, and installed: **4,120 bytes, 24 `LC_REEXPORT_DYLIB`, 0 undefined
symbols, 0 defined exports.** `usr/lib/libSystem.dylib` is a symlink to it and
resolves.

It links with no code of its own. A re-export-only dylib has **no undefined
symbols**, so it never needed the dyld shared-cache exemption — which is why it
links even though its install_name `/usr/lib/libSystem.B.dylib` is *not* under
`/usr/lib/system/`. That exemption was never the issue for it.

The `-reexport` list is unchanged from `Libraries/Libsystem/Makefile:35-46`.
**No target was dropped to make it link.** Three targets are still stubs or
absent; they are listed below with their specific blockers.

## The 25 re-export targets: 22 REAL (21 if libcorecrypto.dylib is absent — see its section)

| target | state | size | defined syms |
|---|---|---|---|
| **system_c** | REAL | 1,255,496 | 1,342 |
| system_asl | REAL | 239,536 | 221 |
| system_malloc | REAL | 263,712 | 84 |
| system_pthread | REAL | 164,208 | 185 |
| system_darwin | REAL | 96,640 | 65 |
| system_platform | REAL | 88,456 | 200 |
| system_blocks | REAL | 22,288 | 14 |
| CrashReporterClient | REAL | 8,704 | 6 |
| compiler_rt | REAL | 151,960 | 211 |
| unwind | REAL | 91,424 | 47 |
| xpc | REAL | 132,672 | 241 |
| launch | REAL | 91,720 | 152 |
| dispatch | REAL | 912,240 | 247 |
| system_m | REAL | 39,512 | 187 |
| system_coreservices | REAL | 13,832 | 2 |
| system_notify | REAL | 93,488 | 82 |
| system_info | REAL | 408,160 | 523 |
| copyfile | REAL | 74,496 | 11 |
| macho | REAL | 35,856 | 72 |
| removefile | REAL | 26,552 | 12 |
| system_dnssd | REAL | 62,064 | 48 |
| **system_kernel** | STUB | 8,064 | — |
| **dyld** | STUB | 8,064 | — |
| **corecrypto** | REAL | 47,128 | 42 defined (68 counting data syms) |
| **system_trace** | ABSENT | — | — |

Also real, and not in the 25 list: **libobjc.dylib, 1,608,088 bytes**, with
install_name `/usr/lib/system/libobjc.dylib` (see the warning below).

Note on `system_c`: the dylib size does not convey the achievement. **All 14
libsystem_c subprojects are complete — 693 objects across 16 archives.** An
SDK-level re-measurement of the *installed* copy reports 1,273 exports rather
than 1,342; the count depends on when it is measured, since link order and dead
stripping differ between the build product and the installed copy.

## The three remaining blockers

Each is a specific, named cause — not "fails to build". None is an
include-ordering accident.

### system_kernel — a header-generation step, not an ABI to invent

Verified: `mach_types.defs` in `$SDK/usr/include/mach/` **defines** the type at
line 621 (`type eventlink_port_pair_t = array[2] of mach_port_t;`), and the
generated `mach_eventlink.h` uses it — but the SDK ships **no
`mach_eventlink.h`**, and `mach_types.h` contains zero occurrences. The
declaration exists in the `.defs` source and never made it into the generated
header the build includes.

Defining an eventlink port-pair ABI here was **refused**, and the refusal was
correct: it is a kernel IPC structure and inventing it would be the same class
of act as inventing `os_log_pack_s`. **The honest route turned out to be
available after all** — but it is generation, not invention. `mach_types.defs`
already contains everything needed; the SDK provisioning step simply omits
migrating the output. Run mig over the `.defs` and install the result.

**THE SET IS ONE HEADER, not a set.** Comparing the three mach trees: the SDK's
`mach/` has 123 headers, `EXPORT_HDRS/osfmk/mach` has 107, and the generated
`mig_hdr/include/mach` the build includes has 27. Only `mach_eventlink.h` is
absent. An earlier reading called this a set problem; that was withdrawn. The
build halts at the first bad translation unit, so each fix reveals the next error
behind it and the pattern reads as expansion when it is only depth.

**The `mach_types.h` problem is a PATH problem, not stale content.**
`<mach/mach_types.h>` resolves to the System.framework PrivateHeaders copy, not
the `usr/include` one. **Both are 254 lines and both declare `io_master_t`
exactly once.** Change nothing about any header; stop the wrong path winning.

**Status: SOURCED shim identified; the generation hypothesis was TESTED and is
WRONG.** `mig` cannot process `mach_types.defs` at all — measured locally as
`mig: fatal: ".../mach_types.defs", line 712: 151 errors found. Abort.`, and the
file has **0 `Subsystem` declarations** because it is a types-only include
file. So the SDK is not withholding a product of a step it should run; the step
cannot run on this input.

The type is present and authoritative at
`Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/mach/mach_types.h` (395 lines, 2
occurrences) and can be sourced verbatim. **A wholesale sync is measured to be
actively harmful**: EXPORT_HDRS has `eventlink_port_pair_t` but **0** `suid_cred_t`,
while the SDK's `mach_types.h` has `suid_cred_t` but **0** eventlink. The two are
complementary, neither a superset, and copying either direction breaks the other
because the SDK's `mach/task.h` needs `suid_cred_t`. Same trap that broke 7 of
13 components on an earlier wholesale libkern sync. See `REMEDIATION_PLAN.md` B1.

### libsystem_c: links, but its runtime closure is UNVERIFIED  **[not a blocker on the 25-target table — a load-safety unknown]**

`libsystem_c.dylib` carries **272 undefined symbols**. They are not resolved -
they are deferred under the `/usr/lib/system/` shared-cache exemption, and
**ravynOS has no dyld shared cache.** "Links" and "loads" are different claims.

**MEASURED: 133 of the 272 are unprovided** (139 are covered by an installed
dylib), against all 6,605 symbols defined across `$SDK/usr/lib` and
`$SDK/usr/lib/system`:

    libsystem_kernel (syscall wrappers)  102
    mach traps (also kernel)             14
    misc kernel                           7
    libsystem_trace                        3
    libsystem_platform                     3
    libdyld                                2
    dyld                                   2

**`libsystem_c.dylib` CANNOT LOAD.** 126 of the 133 are unresolvable because
`libsystem_kernel` in the SDK is an 8,064-byte stub. This is the boot blocker and
it outranks dyld.

**But the BUILD is REPRODUCIBLE — a separate claim, and it is proven.**
`libsystem_c` was rebuilt clean from scratch: **693 objects, 16 archives, 0
errors**, producing `libsystem_c.dylib` at **1,255,496 bytes with exactly 1,342
exports** — byte-identical to the artifact that had been on disk. Matching size
and export count on a from-nothing rebuild is the strongest available evidence
that nothing was silently lost and that the build is deterministic here.

| | status |
|---|---|
| `libsystem_c` **builds reproducibly** | **PROVEN** — 693 objects, 16 archives, 1,255,496 B, 1,342 exports |
| `libsystem_c` **loads** | **UNVERIFIED, measured short** — 133 of 272 undefined unprovided |

**A reproducible build does not imply a loadable one.** The 272 undefined and 133
unprovided are a question about LOAD, not BUILD, and remain fully open.

**`libsystem_platform` is still outstanding** and must not be counted with libc.

**The 13-type mach shim is NOT SHIPPED.** It was committed as `f435475`, verified
only on a **synthetic** TU, then **broke `libsystem_c` and `liblaunch` in the real
build** across three successive versions. Rolled back in `0a235e5`; preserved out
of the build at `/Users/max/Projects/build/diagnostics/ravynos-eventlink-compat.h.disabled`.
`libsystem_c` rebuilds clean without it: 693 objects, rc=0, 1,255,496 B / 1,342
exports. **A synthetic TU proves the shim compiles; it does not prove the real
build resolves to it.** In the `ravynos-eventlink-compat.h` commit, each
under its own guard, each sourced verbatim from the **non-KERNEL** branches of
`Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/mach/*.h`, verified at 0 errors.
`mo_ipc_object_bits_t` and `mig_kern_server_routine_t` were **deliberately
excluded** - a userspace libsystem_kernel does not define kernel-server mig
bookkeeping. **Declaration-not-header is the rule for this family**: the in-tree
`port.h` carries `#if KERNEL` material that must not reach userspace, and a
wholesale copy is the `mach_types.h` complementarity trap.

**The derived SDK artifact gate is RED and its verdict is NOT trustworthy** -
1 rebuildable, 19 failed, 3 no-build-system, caused by generalising from one case
(absolute target paths for `libCrashReporterClient`) to all. The derivation is
sound; the verdict is not. **Never generalise from one case instead of from the
rule** - 19 false reds in one change. A named-broken guard beats a green-looking
one that lies.

**Tally 22/25; libc still cannot load.** **Seven commits, local only, unpushed**:
`1f0e802`, `4a37c54`, `3a27bba`, `f6f3df2`, `f435475`, `8b1203c`, `0a235e5`.

**Entry point: DELIVERED.** `tools/bootlab/build_all_libsystem.sh`, committed in
`0a235e5`, 209 lines, ran end to end as committed: **21 stages passed, 1
known-blocked, 3 skipped, 0 unexpected failures**. The known-blocked stage is
`libSystem.B` on `missing required libs *** system_trace` - a consequence of the
known B2 blocker, **not a broken build**. `check_sdk_stubs.sh` runs last as the
hard gate with `RAVYN_SDKROOT` exported, and correctly names four pre-existing
zero-byte BSD-tool stubs outside the Libsystem set. The derived gate `4a37c54`
remains **unwired and untrustworthy** by design, pending its own negative test.

**The driver is the first instrument here that runs the build the project
actually runs**, and on its first execution it **caught a regression every
targeted test had passed**. The remaining targeted verifications in this project
should not be trusted on their own. **No wrapper
change was needed at any point** - `isysroot-cc` and `build-libraries.sh` are
byte-identical to `1f0e802`. Remaining: the `unwind_epilogue` assembly failure
(**no cause recorded, none supported**); the mach half's `_kernelrpc_*`
signature provenance question, which is NOT a missing declaration; `lck_spin_t`
genuinely unsourceable with libsystem_trace needing 5 real symbols so it cannot
be dropped; dyld unchanged. A `libsystem_kernel.dylib` from the mach half alone
was considered and **DECLINED** - it would move the tally by one while carrying
none of the 126 syscall symbols libc needs.

> **Caveat for anyone re-running this:** `nm -g` on that 8,064-byte
> `libsystem_kernel` stub reports **97 exported symbols including `_open`,
> `_read`, `_readdir`**, all typed `T`. A naive `comm -23` of libc's undefined set
> against every dylib's `nm -g` output returns **0 unprovided** - which is
> wrong. **A symbol in a dylib's export table is NOT evidence that the dylib
> provides it.** See also: corecrypto is **19 objects / 74 exports** after the
> `-I` fix. **Do not add stubs to make the number zero.**

### system_trace — needs its own source, not a build fix

`lck_spin_t` is used by `Kernel/xnu/libkern/os/log_mem.h:36` and is defined
only in `Kernel/xnu/iokit/IOKit/IOLocks.h`, which is kernel-only.
`Kernel/xnu/libkern/lck.h` **does not exist in the tree at all**. There is no
userspace path to this type. See `Libraries/Libsystem/NOTES_os_log_pack_and_log_mem.md`.

**But the dependency test was run, and it is much narrower than "needed".** Only
**5 of libsystem_trace's 197 symbols are genuinely required** - 3 by
`libsystem_asl`, 3 by `libsystem_info`, sharing one. **`libsystem_c` needs 0 of
them**, so this is NOT a load-time dependency of the real libc. Note the
asymmetry honestly: the SOURCE is permanently absent, but the NEED is 5 symbols
from two components, so a userspace `lck_spin_t` shim would have a small, known
blast radius. Do not describe this as "libsystem_trace is needed".

### dyld — the `<stdint.h>` blocker is CLEARED; what remains is a sequence, not a project

**`<stdint.h>` is cleared and verified on the real build** — cstdint errors went
from 1 to 0 in an actual dyld build. The fix is a **pre-inclusion** in
`isysroot-cc`, not an ordering change: an earlier header in dyld's chain opens
the **C** `<stdint.h>` first, so `cstdint`'s own include is a no-op under that
guard, `_LIBCPP_STDINT_H` is never set, and the `#error` fires. **Ordering
flags cannot fix that; only opening libc++'s shim first does.**

**Next is `OPENBSM_1_2_alpha5`** — the same shape, a macro selecting an API
generation not set for this target.

> **No new dyld estimate is offered, deliberately.** The old "month-plus" was
> asserted before anything was measured and was wrong by an order of magnitude.
> dyld's blockers are **not in dyld's code** and are **not open-ended** — they are
> SDK header-configuration issues, one per translation unit, each so far costing
> minutes. **Two data points do not establish a total**, and a confident
> replacement would be wrong in the same way the original was.

> **Open question worth more than dyld:** these are SDK header-configuration
> issues, and libc's 272 undefined symbols and the `mach_types.h` generation
> gaps have the **same shape**. If any share a root cause, one fix could clear
> more than dyld. **Untested.**

### corecrypto — now REAL. The source was always there; the build system was the gap.

> **This corrects an earlier entry in this document, which stated that no
> corecrypto source exists in the tree. That was wrong, and the conclusion has
> been replaced twice over: the source exists, AND the library now builds. Do
> not re-derive either error.** The earliest search looked in the wrong places.
> The implementation is present, split across several trees:
>
> - `Kernel/Extensions/corecrypto/` — 22 `.c`, 68 `.h`
> - `Kernel/xnu/osfmk/corecrypto/` — 24 `.c`, 15 `.h`
> - `Kernel/xnu/libkern/crypto/` — 11 `.c`
> - `Kernel/xnu/EXTERNAL_HEADERS/corecrypto/` — 42 `.h`
> - `Libraries/Libsystem/CommonCrypto/` — 98 `.c` (including
>   `lib/corecryptoSymmetricBridge.c`), 23 `.h`
> - `Frameworks/Security/OSX/utilities/SecCoreCrypto.c`
>
> `Developer/` and `BSD/` were checked explicitly and contain no corecrypto.

> **Status: BUILT, BUT NOT PRESENT IN THE SDK AS OF THE LAST RECONCILIATION.**
> `Libraries/Libsystem/corecrypto/Makefile` exists and was measured building
> `libcorecrypto.dylib` at **47,128 bytes**, 42 defined symbols (68 counting
> data symbols), 13 undefined, installed at `usr/lib/system/libcorecrypto.dylib`.
> With it in place the re-export link re-measured at **22 of 25**.
>
> **However, a subsequent re-check found the file ABSENT from the SDK**, with
> no build activity in the preceding five minutes, and `-lcorecrypto` now fails
> with `ld: library 'corecrypto' not found`. The 22/25 figure is real but not
> stable: the library builds and was installed, and something has since removed
> it.
>
> Treat the tally as **22 when the file is present, 21 when it is not**, and
> check the SDK rather than trusting either number. `check_sdk_stubs.sh` reports
> this as `KNOWN: -lcorecrypto : absent`; that is the correct signal and should
> NOT be silenced by dropping corecrypto from the KNOWN list until the install
> is reproducible.
was re-measured after installation and reports **22 of 25**.

**Fact 1 — the correct `-I` is the kext's own header directory.**
Use `Kernel/Extensions/corecrypto/include/corecrypto/` (**48 headers**), NOT
`Kernel/xnu/EXTERNAL_HEADERS/corecrypto/` (**42 headers**). The latter is
missing `cc_abort.h`, `ccmd5.h`, `cc_debug.h` and `ccrc4.h`; using it drops the
build from 16/22 to 12/22. This is the same "which generation of headers is the
source written against" trap already hit with `Availability.h` and the `mach/`
trees.

**Fact 2 — `cc_abort.h` EXISTS.** A separate earlier claim that it was missing
was **wrong**. It is at `Kernel/Extensions/corecrypto/cc_abort.h` — a real
10-line header splitting `#define cc_abort panic` under `CC_KERNEL` from an
`fprintf`+`abort()` userspace implementation. The source files include
`<corecrypto/cc_abort.h>` while the kext keeps the file at the kext ROOT, not
in `include/corecrypto/`, so the angle-bracket include never resolves. A
one-line relative-path shim unblocks `cc_functions.c`, `cc_digest.c`,
`aes_cbc.c`, `aes_ecb.c`. **Status: identified, shim NOT yet landed** — verify
before assuming it is done.

**Fact 3 — this is NOT a drop-in replacement for the real library.** The
prebuilt corecrypto exports 9 `CC*` constants; this build exports 68 `cc_*`
functions and **0** `CC*` constants. The symbol sets are near-disjoint. It
satisfies the re-export only because ld64 needs the library to be findable, not
because it implements the same ABI. Anyone depending on `CC*` constants must not
treat this as shipped. (The same caveat is the first 30 lines of the Makefile;
it is repeated here because this document is where a reader looks.)

## Most stalls here were MODE problems, not content problems

The tree was correct and the **invocation** was wrong, five times over: the mach
header generation, the `mach_port_t` typedef family, the `Availability.h` guard,
the `-E`/`-c` divergence, and the assembler path. **Twice a confident answer
pointed at the source when the fault was in how the tool was being called.**
Distinct from the header-generation family below.

## Nine findings, in the order they were learned

1. **Read what the tool produced, not what you intended to produce** — `-E` and
   `-c` output are not line-aligned; identify the artefact before grepping.
2. **Never treat "no match" as "no data"** — five instances; the assembler beat
   the grep here.
3. **Check that the instrument can fail the way you need it to fail** — a C
   preprocessor was used to test a mig grammar question.
4. **Verify the inputs a tool will actually use, including supporting headers** —
   `stubs.list` was checked; the `SYS.h` that had to accompany it was not.
5. **A half-right hypothesis is the most dangerous kind** — the right half lends
   false confidence to the wrong half.
6. **When two observations conflict, do not settle on the plausible one.**
7. **Check inputs, not only outputs, before concluding something is missing** — a
   header and its `.defs` are an output and its input.
8. **A derived list only beats a hard-coded one if the derivation is right.**
9. **A gate earns the right to be committed by demonstrating a clean run, and the
   right to be trusted by demonstrating a red on a known-bad input** —
   `4a37c54` records its negative direction as UNVERIFIED.

## Six findings worth not re-investigating

**1. The ld64 rule that actually broke every dylib link.** ld64 decides whether
a dylib may carry unresolved symbols purely from its **install_name path**. A
dylib installed under `/usr/lib/system/` is treated as shared-cache-eligible
and may defer resolution to its cache siblings; anywhere else it must be
self-contained and ld64 fails with `ld: dynamic executables or dylibs must link
with libSystem.dylib`. Proven by single-variable A/B, same archive and same
flags:

    install_name /usr/lib/system/t.dylib -> BUILT  (12624 bytes, 3 undefined)
    install_name /usr/lib/t.dylib         -> REFUSED

This retro-explains many earlier confusing results, including a 0-`LC_LOAD_DYLIB`
dylib linking fine next to one that was refused.

**2. `-lsystem_trace` in libsystem_c's LDFLAGS is pure ceremony.** Proven by set
intersection: the 272 symbols undefined by libc against the 197 defined by
`libsystem_trace` intersect in **exactly zero**. The dependency is nominal and
costs nothing to carry; it is not a real constraint.

**3. `-I` order silently picks the winner when two generations of one header
are both reachable.** This is a general class, not a one-off, and it has now
bitten this project three times: `Availability.h` (isysroot-cc overlays it), the
XNU libkern `os/` headers, and `Kernel/xnu/EXTERNAL_HEADERS/stdlib.h` - a
one-line FBSD shim that pre-empts the SDK's `stdlib.h` and makes `abort()`
resolve to the shim instead of the real declaration. Scoped: a normal userland
program including `<stdlib.h>` compiles and calls `abort()` with 0 errors, so it
is not a userspace showstopper. But **whenever two generations of one header
are reachable, `-I` order decides silently.** See `REMEDIATION_PLAN.md`.

**4. A `#include_next` shim only works if it is found BEFORE the header it
shadows.** This is the `private/os/assumes.h` rule: a shim relying on
`#include_next` is useless unless the shim wins the `-I` search first.

**5. A shim that does not apply and reports success is worse than no shim.**
Found while landing the eventlink shim: `$HERE` was undefined in
`tools/bootlab/build-libraries.sh`, so the shim silently did nothing, and the
eventlink shim was additionally gated behind a *different* shim's flag. The
generalisation: **any compatibility shim must be verified with `clang -E` that
the build actually consumes the sourced definition, and a shim's success must be
distinguishable from its no-op.** This is the same category as the silent
stub-writer in the CrashReporterClient Makefile, which also reported nothing
while doing the wrong thing.

> **The pattern across this project is that silent, successful-looking failures
> are the dominant failure mode — not loud build errors.** Four instances now: the
> CrashReporterClient stub-writer, the undefined `$HERE`, the eventlink shim
> gated behind the wrong flag, and the `-I` precedence shadowing above. See
> `Libraries/Libsystem/libSystem.B_STATE.md` → "Note on the os_log_pack_s shim"

**6. Determine an include's provider by reading the compiler's emitted `-I` list
and the resolved path for the failing translation unit. Never by inferring it
from which directories exist.** The `mach_types.h` shadow was diagnosed by
reasoning about which directories existed; that inference was wrong. The
doubled-path `EXPORT_HDRS/osfmk` directory was never on `libsystem_kernel`'s
include path at all — `grep -c EXPORT_HDRS` on its Makefile returns 0. An overlay
directory that is present on disk but absent from the include path looks exactly
like an active shadow until you read the argument list. **This has produced three
wrong diagnoses in this project: this one, the `Availability.h` collision, and
the `mach/` overlay traps.** Same trap as finding 3, seen from the other end.
`Libraries/Libsystem/libSystem.B_STATE.md` → "Note on the os_log_pack_s shim"
below, and note that the same principle explains the unresolved
`<cstdint>` / `<stdint.h>` failure in dyld.

## Sub-dylib link recipe (reusable)

Every real dylib in the table above was made this way:

    clang++ -isysroot$SDK -nodefaultlibs -shared -dylib -fuse-ld=ld \
      -o libX.dylib -Wl,-force_load,libX.a \
      -Wl,-install_name,/usr/lib/system/libX.dylib \
      -Wl,-current_version,1 -Wl,-compatibility_version,1 \
      -Wl,-not_for_dyld_shared_cache -Wl,-undefined,dynamic_lookup \
      -Wl,-multiply_defined,error

- **`-Wl,-install_name,/usr/lib/system/...`** — see finding 1. Load-bearing.
- **`-Wl,-not_for_dyld_shared_cache`** — mandatory alongside
  `-undefined dynamic_lookup`; ld64 rejects the combination on a
  shared-cache-eligible dylib unless it is opted out.
- **`-Wl,-multiply_defined,error`** — tolerates 6 symbols that both libc++abi
  and libc++ define (`std::set_terminate`, `std::terminate`,
  `std::get_terminate`, `std::get_unexpected`, `std::unexpected`,
  `std::set_unexpected`). **Known debt, not a clean fix** — each should end up
  with a single owner.

## WARNING — libobjc's install_name is not stock macOS

`libobjc.dylib` is installed as **`/usr/lib/system/libobjc.dylib`**, not the
`/usr/lib/libobjc.dylib` that stock macOS uses. **This is load-bearing. Do not
"fix" it** — see finding 1. The same applies to all 21 sub-dylibs above, all
installed under `/usr/lib/system/`. These are bootstrap-stage names and are
expected to be revisited when a real shared cache exists.

An incident worth remembering: an intermediate rebuild of
`Libraries/objc4/Makefile` truncated `LDFLAGS` to two lines, silently losing
the install_name and both load-bearing flags. The link then failed with exactly
the refusal above. If that file is ever regenerated, check `LDFLAGS` survived.

## The PROVISIONAL os_log layout

`private/os/log.h` carries a prominent PROVISIONAL banner: the
`os_log_pack_s` layout is **ravynOS-internal, is NOT Apple's, and is not a
recovered ABI**. It is a local substitution that exists only to let
`libsystem_c` compile, and it is explicitly not a fix for the ABI question.

`private/os/assumes.h` chains to the real header via `#include_next` and
additionally supplies `typedef struct os_log_pack_s os_log_pack_s;`. That alias
is required because the SDK's `os/assumes.h:77` writes
`alignof(os_log_pack_s)` with a **bare tag name**, which is not a type name in
C11/C17. Defining the struct is necessary but not sufficient; the alias is what
makes that construct legal. C23 does not rescue it — `-std=c23` still errors on
this compiler.

**The extrapolation caveat proved correct.** At the time the shim landed,
`gen/FreeBSD/arc4random.c` compiled with zero `os_log_pack_s` errors while the
remaining ~380 libFreeBSD sources were individually unconfirmed, because the
build stops at the first failing translation unit. All 14 subprojects
subsequently completed, so nothing further materialised — but the caveat was
doing real work at the time and should not be read in hindsight as a risk that
turned out to be nothing. The general lesson stands: on a build that halts at
the first bad TU, clearing one file is an extrapolation, not a proof.

## Two further documented gaps

- The **`host_statistics` / `host_processor_info` / `task_info` / `thread_info`**
  family — the Mach trap wrappers libSystem's userspace is expected to expose —
  has **no userspace implementation anywhere in the tree**. `Kernel/xnu/osfmk`
  implements the kernel side, but those sources include `<mach/mach.h>` and
  depend on MIG-generated stubs, so they do not compile for userspace.
- **`LIBC_SUF_CANCELABLE`** is defined in libsystem_c's own `cdefs.h`, not in a
  shared header. Anything needing it must go through that private copy, which
  couples it to libsystem_c.

## See also

- `Libraries/Libsystem/NOTES_os_log_pack_and_log_mem.md` — the single source
  of truth for the `os_log_pack_s` and `os/log_mem.h` gaps. This file points
  there rather than restating them.
- `Libraries/Libsystem/private/os/log.h` — the PROVISIONAL pack layout.
- `Libraries/Libsystem/private/os/assumes.h` — the shim and the type alias.
- `Libraries/Libsystem/libsystem_info/MISSING_DEPS.md` — historical: its three
  unmet link dependencies (`xpc`, `system_trace`, `system_notify`) are all now
  resolved or closed.
- `Libraries/Libsystem/REMEDIATION_PLAN.md` — **the plan of record.** Where this
  document records WHAT IS, that one records WHAT TO DO, including the three
  items marked `[DECISION REQUIRED]` and the analysis marked `[UNVERIFIED]`.
  If they ever conflict, this document wins on measurement.

## Current deliverables

All untracked and visible to git; none hidden by the `.gitignore` rules:

- `Libraries/Libsystem/libSystem.B_STATE.md` — this document
- `Libraries/Libsystem/REMEDIATION_PLAN.md` — the plan
- `Libraries/Libsystem/NOTES_os_log_pack_and_log_mem.md` — the logging gaps
- `Libraries/Libsystem/libsystem_info/MISSING_DEPS.md` — historical record
- `Libraries/check_sdk_stubs.sh` — the post-build stub guard
- `Libraries/Libsystem/private/os/log.h` — the PROVISIONAL pack layout
- `Libraries/Libsystem/private/os/assumes.h` — the shim and the type alias

## Two mirror findings, and three bounded open items

**The failure is never the absence of measurement — it is the gap between what
was measured and what was concluded from it.** Two of these stalls were mine.

- **A verification that cannot fail the way the real build fails is not evidence
  about the real build.** The 13-type shim passed a synthetic TU at 0 errors and
  then broke `libsystem_c` and `liblaunch` across three successive versions.
- **A test broader than the question can cause the defect it was looking for.**
  The eleven-path vendored-include inventory looked systemic; an overlay landed
  on its strength would have disturbed a sound libc and concealed two real
  defects. **Neither finding is licence for the other** - one warns against
  under-testing, the other against over-testing.

**The vendored-include shadow class is latent, not live.** On a real `libBase`
translation unit (183 header opens), **0 headers resolve from
`Kernel/xnu/EXTERNAL_HEADERS`**, so `libsystem_c` is compiled against the right
headers. Genuine defects are confined to six components; worst is a **381-byte
`stdlib.h` shadowing the SDK's 14,705-byte one** in `libsystem_darwin` - the
`mach_types.h` complementarity trap in its purest form.

**Three bounded, measured open items:**

1. `libsystem_darwin` - live vendored shadow, the 381 B `stdlib.h`. Measured,
   not yet fixed.
2. openbsm `version` data file included as `<version>` across five components.
   Measured, not yet fixed.
3. Derived gate `4a37c54` - unwired and untrustworthy, pending its own negative
   test. Deliberate.

## Stub outcomes (2026-09-26) — shape over count

- **Deleted, do not re-create by inventing a source tree:** `libcache`,
  `libquarantine`, `libsystem_collections`, `libsystem_configuration`,
  `libsystem_containermanager` — each had 0 inbound `LC_LOAD`, 0 `-l`
  references, no re-export, and no source in the tree. A placeholder nothing
  links is a liability: a future consumer links it and gets a silent no-op.
- **Built:** `libcommonCrypto`, a pure re-export over the real `libcorecrypto`
  (53,608 B, 74 exports). **Its 0 exports is NOT a defect** — it fails loudly on
  load rather than silently doing nothing. Do not "fix" it by adding code.
- **Real work:** `libsystem_kernel` and `libdyld`.

## `libsystem_kernel` progress, and the one remaining error

Stubs **fully assemble** — the `.cfi_endproc` imbalance is fixed
(`LEAF_FUNCTION_PROLOGUE` never emits `.cfi_startproc`, so there was never a
region to close; the same imbalance existed in five hand-written custom stubs).

The `unwind_epilogue` paradox is solved: the token is `UNWIND_EPILOGUE`
**uppercase** and the assembler case-folds it in diagnostics; the SDK's vendored
`asm_help.h` had it stripped. Restored verbatim from Apple's header, preserving
the x86_64 port, **durability-proven by deleting the generated file and
re-syncing**. A mach census found **15 constants across 7 headers**, each sourced
verbatim with its source line named.

**One error remains**: `coalition_info_debug_info` conflicting types with
**byte-identical declarations in both contexts** — so it is a typedef resolving
differently under `__DARWIN_ONLY`/cdefs, not a source disagreement. **Diagnosed,
not patched.**

## Two measurement lessons

**(a) Check which tree wins before concluding a symbol is absent.** The mach
census verified `usr/include/mach` while
`System.framework/.../PrivateHeaders/mach` was what actually won — verification
passed and the build failed at the same time. A clean check on the wrong tree is
not a check.

**(b) A driver result is only meaningful when nothing else is touching the
tree.** A run was invalidated by concurrent builds.

## Honest unknowns, caveats intact

- **272 undefined / 133 unprovided, 126 attributed to `libsystem_kernel` —
  UNVERIFIED.** Untested, because the library has never linked.
- **dyld: 2 objects, unmoved across several rounds.** `<version>` cleared;
  frontier is `corecrypto/ccdigest.h` not found.
