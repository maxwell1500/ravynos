# libsystem_kernel build notes

Durable record of environment facts and defects found while building
`libsystem_kernel.dylib`. Written down because several of these cost hours
and will bite the next person. Nothing here is a workaround: each entry names
a cause and, where fixed, the commit that fixed it.

## 1. THE GENERATED SYSCALL STUBS ARE EPHEMERAL

`Kernel/xnu/libsyscall/xcodescripts/create-syscalls.pl` writes ~454 `.s`
files into `Libraries/Libsystem/libsystem_kernel/sys/`, and each failed build
cleans that directory.

**Consequence:** after a failed build, the file named in the error message
(e.g. `sys/___accept.s`) does not exist. Every search for it, and for any
string inside it, comes back empty. This is why a whole debugging session
concluded the string `unwind_epilogue` "was in no file" — the file was not
there to be searched. Reproduce by running the build, not by searching.

**Name the triple underscore correctly.** `___accept.s` is `__` + syscall
name + `.s` — the generator's name for the legacy `__accept` syscall. It is
NOT Mach-O symbol mangling. `_____sigwait_nocancel.s` follows the same rule.

## 2. SEARCH CASE-INSENSITIVELY. THE ASSEMBLER LOWERCASES IN DIAGNOSTICS.

The error reads:

    sys/___accept.s:9:354: error: invalid instruction mnemonic 'unwind_epilogue'

but the text in the source is **`UNWIND_EPILOGUE`**, uppercase. The
assembler lowercases the token when it reports it as an unrecognised
instruction. Every case-sensitive `grep` for the reported string fails.

Always `grep -i` when hunting something an assembler or compiler named.

## 3. THE STUBS MUST BE COMPILED BY THE WRAPPER (fixed)

`compile-syscalls.pl` and `mach_install_mig.sh` both resolved their compiler
with `xcrun -sdk $SDKROOT -find cc`, which returns
`Default.xctoolchain/usr/bin/cc` — a 46-byte universal shim. That made the
generated stubs the ONLY translation units in the Libsystem build that did
not go through `tools/bootlab/isysroot-cc`, so they alone missed the
`-isysroot` conversion, the injected `__DARWIN_*` platform defines, and the
wrapper's other corrections.

Both scripts now honour `$CC` (and `$LIBTOOL`) from the environment and fall
back to `xcrun`. Honouring the caller's toolchain is the correct fix rather
than rewriting the `xcrun` lookup, because on a machine where `xcrun` is
right the old code was already correct.

Verify the fix actually took effect — do not assume it:

    grep -c "isysroot-cc" <build log>     # must be non-zero

## 4. MACH HEADERS: MIXING GENERATIONS -- see the correction below

> **REVERTED. The -I${XNU}/osfmk ordering from 064733a is GONE.** The SDK mach
> tree now wins wholesale. The SDK tree is the coherent generation: it carries
> mach/task.h, which osfmk does not have at all, and the suid_cred_* types.
> osfmk is a partial mirror missing whole headers. Mixing a partial mirror into
> a complete tree is the defect itself. Analysis in sec. 11.

Original finding, still valid:

Two REAL copies of `mach/message.h` exist and they differ by a generation:

    SDK  .../System.framework/Versions/B/PrivateHeaders/mach/message.h  34,206 B
         0 occurrences of mach_msg_aux_header_t, no `#if PRIVATE` guard
    in-tree  Kernel/xnu/osfmk/mach/message.h                            62,286 B
         declares mach_msg_aux_header_t behind `#if PRIVATE` (line 629)

`CFLAGS` listed the SDK's `PrivateHeaders` BEFORE `-I${XNU}/osfmk`, so the
stale copy won and every unconditional user of the type failed with
"unknown type name". Fixed by reordering. No shim, no invented layout.

**General rule for this tree:** there are multiple `mach/` and `bsd/` header
trees that share include guards. Whichever appears first on the include path
wins and the others are silently never read. When a type is "missing", check
*which copy* won before concluding anything about the type.

## 5. bmake REJECTS A COMMENT INSIDE A BACKSLASH CONTINUATION

A `#` comment placed on a continued line inside a variable assignment is
parsed as a shell command:

    bmake: Makefile:58: Unassociated shell command "..."
    bmake: Fatal errors encountered -- cannot continue

Put the comment ABOVE the assignment instead. Same for `.else if`, which bmake
rejects outright with "The .else directive does not take arguments" — spell it
as a nested `.if`.

## 6. PATH MUST BE FREE OF ENTRIES CONTAINING SPACES

`mach_install_mig.sh` builds `PATH=...:$PATH` unquoted. A desktop-integration
directory such as VMware's `Fusion.app/Contents/Public` contains a space and
the recipe mis-parses:

    /bin/sh: .../Fusion.app/Contents/Public:...: command not found

Set a clean `PATH` before invoking bmake:

    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$ROOT_BINARY_DIR/Developer/usr/bin"

Also `unset DEVELOPER_DIR` when pointing it at the build tree — it breaks the
system `xcrun` shim.

## 7. OPEN: SYS.h IS CFI-UNBALANCED (not fixed)

With the SDK's stripped `asm_help.h` macros restored (see below), the stubs
now expand `UNWIND_EPILOGUE` correctly, and the next error is real:

    error: this directive must appear between .cfi_startproc and .cfi_endproc

Cause, measured in BOTH copies of the header:

    Kernel/xnu/libsyscall/custom/SYS.h                     PROLOGUE=0  EPILOGUE=2
    Libraries/Libsystem/libsystem_kernel/sys/SYS.h         PROLOGUE=0  EPILOGUE=2

`create-syscalls.pl:56` copies `SYS.h` verbatim from
`Kernel/xnu/libsyscall/custom/SYS.h`, so the defect is upstream in xnu, not in
the generator. The stubs emit `.cfi_endproc` with no matching
`.cfi_startproc`. Fixing it means deciding whether xnu's syscall stubs should
carry unwind info at all — that is a behaviour change, not a mechanical one,
and is deliberately not made unilaterally.

## 8. SDK HEADER: architecture/i386/asm_help.h IS STRIPPED

The ravynOS SDK's vendored copy of `architecture/i386/asm_help.h` had the
`UNWIND_PROLOGUE` / `UNWIND_EPILOGUE` macros deleted from inside the
`#ifdef __ASSEMBLER__` block, while the system's own copy of the same Apple
header still has them:

    ravynOS SDK  asm_help.h   9,715 B   UNWIND_EPILOGUE absent
    CommandLineTools/MacOSX.sdk ...     UNWIND_EPILOGUE defined (line 57)

Restored verbatim from Apple's header. This lives in the generated SDK, not
the repo, so it is not covered by the git history here and will be lost on an
SDK regeneration until the sync step that populates `usr/include/architecture`
is taught to copy the complete header. **This is a real outstanding gap.**

## 9. THE GENERATED SDK'S mach/ TREE IS A GENERATION BEHIND -- SYSTEMIC

Measured across all 77 mach headers present in both trees:

    generated SDK smaller than in-tree (stale)  47
    identical                                    23
    generated SDK larger                         7

The worst are not marginal:

    mach_traps.h    9,282 -> 26,381
    vm_param.h      2,687 -> 23,754
    vm_types.h      3,567 ->  9,068
    mach_types.h    9,739 -> 15,395
    vm_statistics.h 18,673 -> 32,546

`usr/include/mach/message.h` (the file in sec. 4) is one instance of this
pattern, not a special case. **Every component that touches mach headers will
hit this class one file at a time.** The fix belongs in the sync step, not in
individual headers -- same standard as the asm_help.h fix in sec. 8, i.e. a
cp -f that survives regeneration, proven by deleting the generated file and
re-syncing.

CAUTION before acting on this: the in-tree xnu is not a drop-in replacement
for the SDK tree. `Kernel/xnu/osfmk/mach/task.h` does not exist at all, and
`Developer/ravynOS.sdk/usr/include/mach/` carries headers xnu does not. A
wholesale overlay would break components that build correctly today. Compare
per file.

## 10. suid_cred_* -- NOT A HARD STOP (correcting an earlier wrong call)

    <SDK>/usr/include/mach/task.h:846: error: unknown type name 'suid_cred_path_t'

I first recorded this as a hard stop, on the reasoning that
suid_cred_path_t was used but never defined. **That was wrong.** I grepped
for `suid_cred_path_t;`, which cannot match `typedef char
suid_cred_path_t[1024];` because the `[1024]` sits before the semicolon.

All three types ARE defined, in the SDK's own mach_types.h, inside the
`_MACH_MACH_TYPES_H_` guard (opens line 73, closes line 254):

    suid_cred_t        mach_port_t    line 141
    suid_cred_uid_t                   line ~
    suid_cred_path_t   char[1024]     line 210

So this is the SAME class as sec. 4 and sec. 9: a mach header that is
reachable in principle and not reachable in practice. The open question is
which mach tree wins the include search for mach/task.h, and whether
something defines `_MACH_MACH_TYPES_H_` before mach_types.h is actually
read. Not yet established. **No shim is warranted and none was written.**

LESSON, recorded because I made this error twice in one session (first
concluding mach_msg_aux_header_t was undefined in-tree, then this): when
proving a type is absent, grep for the bare NAME, not for `name;`. An
array or function typedef puts other tokens before the semicolon.

## 11. THE TWO mach TREES ARE DIFFERENT GENERATIONS AND MUST NOT BE MIXED

The `suid_cred_*` failure in sec. 10 is a guard collision between the two
trees, but the roles are the reverse of what sec. 9 assumed, and it is caused
by sec. 4's own fix.

Traced with the REAL failing compile command (`thread_register_state.c`),
`clang -H`, with `-I${XNU}/osfmk` present:

    mach/mach_types.h  ->  Kernel/xnu/osfmk/mach/mach_types.h   (IN-TREE, 15,395 B)
    mach/task.h        ->  <SDK>/usr/include/mach/task.h        (SDK,     new)

    suid_cred_t / suid_cred_uid_t / suid_cred_path_t:
        in-tree mach_types.h   0 occurrences
        SDK    mach_types.h   2 / 1 / 1

So the IN-TREE mach_types.h is the OLDER generation despite being LARGER, and
the SDK's is the newer despite being smaller. **File size is not a proxy for
generation** -- sec. 9's "47 behind" count assumed it was, and is therefore
unreliable and should not be acted on without per-file comparison.

With `-I${XNU}/osfmk` REMOVED (the pre-064733a order), the SDK's own coherent
mach trees are used throughout and the unknown-type errors drop to 0. But in
that order `mach_msg_aux_header_t` is missing again.

**Therefore the two mach trees cannot both be wanted: the SDK tree is
coherent but lacks mach_msg_aux_header_t; the in-tree tree is a different
generation and lacks suid_cred_*. Mixing them per-header is the defect, and
sec. 4's ordering merely changed WHICH mix you get.**

The correct fix is a single decision to make ONE coherent generation win for
the whole mach tree -- not per-header syncing, and not a shim. Which one wins
is a real design question:
  - SDK tree: self-consistent, has suid_cred_*, lacks mach_msg_aux_header_t
  - in-tree xnu: has mach_msg_aux_header_t, lacks suid_cred_*, and
    osfmk/mach/task.h does not exist there at all, while the SDK carries mach
    headers xnu does not

Not yet decided. Recorded rather than guessed.

## 12. SOURCED mach_msg_aux_header_t -- AND THEN THE CASCADE STOPPED THE WORK

Per the decision, -I${XNU}/osfmk was removed and the SDK mach tree was
allowed to win wholesale. With the ordering gone, the build was re-measured
and the COMPLETE set of in-tree-only symbols it actually needed was extracted
from the real compile, not guessed:

    unknown type name 'mach_msg_aux_header_t'      <- exactly ONE type

No cascade from that type. It was sourced from
Kernel/xnu/osfmk/mach/message.h:626-629 verbatim into the SDK's mach/message.h
in both trees the build can reach, and build-libraries.sh now cp -f's it from
the source SDK so regeneration keeps it. Three of the four mach/message.h
copies were updated; the fourth (Kernel.framework/.../A/Headers) is read-only
and is not on any include path.

THEN the cascade appeared, in a different header:

    <R>/libsyscall/wrappers/coalition.c:62: error: use of undeclared identifier
        'COALITION_INFO_GET_DEBUG_INFO'

    Developer/ravynOS.sdk/usr/include/mach/coalition.h   6,117 B   0 occurrences
    <generated>/usr/include/mach/coalition.h            6,117 B   0 occurrences
    Kernel/xnu/osfmk/mach/coalition.h                   7,582 B   1 occurrence

It is absent from BOTH SDK trees and present only in osfmk. That is a second
in-tree-only symbol in a second header, so the "one type" result was narrow
luck rather than a sign the SDK tree suffices.

**WORK STOPPED HERE DELIBERATELY.** Pulling definitions across one header at
a time does not converge: it makes the SDK tree into a chimera of two xnu
generations, which is precisely the incoherence this whole workstream
existed to remove. The honest conclusion is that this libsyscall snapshot
targets the in-tree xnu generation for several mach interfaces, and "SDK
tree wins wholesale" is therefore only PARTIALLY true -- the correct end state
is a coherent generation selected deliberately, with its gaps filled by
sourcing from a single identified generation, not by opportunistic
per-header accumulation.

NEEDS A DECISION before more work: which generation is authoritative, and how
its gaps get filled without creating a chimera.

## 13. THE CENSUS: 15 SYMBOLS, 7 HEADERS -- BOUNDED, SOURCED, DURABLE

Computed in ONE pass, not by compiling until the next error: the identifier
sets of the two mach trees were intersected with what libsyscall references.

    SDK mach tree defines    2,604
    osfmk mach tree defines  2,897
    libsyscall references       995 (CAPS)
    CENSUS (referenced, in osfmk, absent from SDK)   15

  COALITION_INFO_GET_DEBUG_INFO      coalition.h:169
  CPU_SUBTYPE_ANY                    machine.h:189
  HOST_DOUBLEAGENTD_PORT             host_special_ports.h:114
  HOST_IOCOMPRESSIONSTATS_PORT       host_special_ports.h:111
  HOST_IO_MAIN_PORT                  host_special_ports.h:79
  HOST_MANAGEDAPPDISTD_PORT          host_special_ports.h:113
  HOST_MEMORY_ERROR_PORT             host_special_ports.h:112
  LIBSYSCALL_MSGV_AUX_MAX_SIZE       message.h:615
  MAXCONCLAVENAME                    mach_param.h:86
  MPO_REPLY_PORT                     port.h:481
  TASK_INSPECT_PORT                  task_special_ports.h:80
  TASK_READ_PORT                     task_special_ports.h:82
  THREAD_INSPECT_PORT                thread_special_ports.h:72
  THREAD_MAX_SPECIAL_PORT            thread_special_ports.h:76
  THREAD_READ_PORT                   thread_special_ports.h:74

**This is the SMALL AND BOUNDED case, not the version-mismatch case.** 15
constants across 7 headers is a bridge, not a rewrite. Every one was checked
to be absent from the ENTIRE generated SDK, not just the mach tree, and every
line is copied verbatim from the in-tree header named beside it.

The census is also the answer to "is the SDK tree a superset": it is not, but
it is missing only 15 constants that libsyscall uses. That is a bounded,
sourced, documented bridge between two real xnu generations, not a chimera.

**Durability proven the same way as asm_help.h:** the eight census headers
were DELETED from the generated SDK, re-synced from the source SDK, and all
15 symbols verified present afterwards.

**Note the tree that actually wins.** Not `usr/include/mach` -- it is
`System.framework/Versions/B/PrivateHeaders/mach`, which
`-I${RAVYN_SDKROOT}${SLF}/${SYSPRIVHDR}` puts ahead of the sysroot. The
first attempt sourced only `usr/include/mach`, verified the defines were
present, and STILL failed to compile. 17 header copies across both SDK trees
were updated. Check which tree wins before concluding a symbol is absent.

## 14. OPEN: coalition_info_debug_info -- a typedef-level divergence, NOT a text one

    wrappers/coalition.c:60: error: conflicting types for
        'coalition_info_debug_info'
    Kernel/xnu/bsd/sys/coalition.h:55: note: previous declaration is here

The two declarations are BYTE-IDENTICAL. Verified with cat -A on both the
definition and the declaration:

    int coalition_info_debug_info(uint64_t cid, struct coalinfo_debuginfo *cru, size_t sz);

so this is NOT a signature disagreement in the source text and must not be
"fixed" with a cast or by editing either signature. The divergence is one
level down: the same token resolves to different types in the bsd/cdefs
context of <sys/coalition.h> and in the libsyscall context of coalition.c --
the __DARWIN_ONLY / cdefs family this project has hit repeatedly, most
recently for the -DXNU_PLATFORM_MacOSX feature mismatch.

Relevant: `struct coalinfo_debuginfo` is NOT defined in either winning SDK
mach tree (0 occurrences in System.framework/.../PrivateHeaders/mach/coalition.h
and in usr/include/mach/coalition.h). It is only defined in
Kernel/xnu/osfmk/mach/coalition.h:171 and the Kernel/xnu/BUILD copies. An
incomplete struct cannot by itself cause this, so the typedef resolution is
the thing to measure next -- not the struct.

NOT FIXED. Recorded rather than patched, because every candidate fix that does
not involve a typedef-level measurement is a guess.

## 15. THE --quick BASELINE IS NOT A BASELINE

Every "0 unexpected failures" claim made in this project was measured against
a `--quick` driver run, which SKIPS 3 STAGES. A full run has 0 skipped.
libdispatch is one of the stages `--quick` does not build, and it does not
build at all:

    Kernel/xnu/libkern/firehose/chunk_private.h:173: error: no member named
        '__c11_atomic_store' in namespace 'os_atomic_std'
    ...:187: same, for __c11_atomic_store
    ...:189: no member named '__c11_atomic_fetch_sub'
    (plus 'address argument to atomic operation must be ...' on each)

Include chain, from the real compile of block.cpp:

    libdispatch/src/block.cpp:31
      -> src/internal.h:1136
        -> src/firehose/firehose_internal.h:39
          -> Kernel/xnu/libkern/firehose/private.h:29
            -> Kernel/xnu/libkern/firehose/chunk_private.h:173

NOT a source defect and NOT caused by the isysroot-cc force-includes:
rebuilding with isysroot-cc from 1f0e802 (before BOTH force-includes) fails
identically, rc=1, 5 errors.

This is a HEADER-CONFIGURATION failure. xnu's atomic family exposes
`__c11_atomic_*` through namespace `os_atomic_std`; compiled as C++ that
namespace resolves to a std::atomic-backed implementation which does not
provide the C11 names, and the __cplusplus branch of the atomic header is not
being taken as expected. Next step is to establish which branch of
Kernel/xnu/libkern/osfmk atomic header libdispatch's include path selects,
not to edit chunk_private.h.

Consequence for the plan: 24 passed / 2 known-blocked / 0 unexpected was a
--quick figure and is NOT a full measurement. Every regression claim made
against it is weaker than it appeared. The first trustworthy full-driver
number is the one to quote from now on.

---

## 2026-09-26 — kernel-side summary

**Stubs fully assemble.** The `.cfi_endproc` imbalance is fixed:
`LEAF_FUNCTION_PROLOGUE` never emits `.cfi_startproc`, so there was never a
region to close. The same imbalance existed in five hand-written custom stubs.

**`unwind_epilogue` solved.** The token is `UNWIND_EPILOGUE` **uppercase**; the
assembler case-folds it in diagnostics, which is why every error showed it
lower-case. The SDK's vendored `asm_help.h` had `UNWIND_PROLOGUE` /
`UNWIND_EPILOGUE` stripped. Restored **verbatim from Apple's own header**,
preserving the ravynOS x86_64 port, and **durability-proven by deleting the
generated file and re-syncing**.

**Mach census: 15 constants across 7 headers** needed from in-tree xnu, each
sourced verbatim with its source line named, also durability-proven.

**One error remains:** `coalition_info_debug_info` conflicting types, with
**byte-identical declarations in both contexts**. The divergence is therefore a
**typedef resolving differently under `__DARWIN_ONLY`/cdefs**, not a source
disagreement. **Diagnosed, not patched.**

### Two lessons this round, both of which cost real time

**(a) Check which tree WINS before concluding a symbol is absent.** The census
verified `usr/include/mach`, but
`System.framework/.../PrivateHeaders/mach` was what actually won. Verification
passed and the build failed at the same time. **A clean check on the wrong tree
is not a check.**

**(b) A driver result is only meaningful when nothing else is touching the
tree.** One run was invalidated by concurrent builds.

### Honest unknowns

- **Load closure: 272 undefined / 133 unprovided, 126 attributed to
  `libsystem_kernel` — UNVERIFIED**, untested because the library has never
  linked.
- **dyld: 2 objects, unmoved across several rounds.** `<version>` is cleared;
  the current frontier is `corecrypto/ccdigest.h` not found.

## 16. FIXED: coalition_info_debug_info -- the incomplete type, not the signature

Traced with -H on the real compile of wrappers/coalition.c:

    winning mach/coalition.h  <SDK>/System.framework/.../PrivateHeaders/mach/coalition.h
    struct coalinfo_debuginfo in that header    0 occurrences -- NOT DEFINED
    struct coalinfo_debuginfo in usr/include/   0 occurrences -- NOT DEFINED
    struct coalinfo_debuginfo in osfmk/mach/    1 occurrence  -- DEFINED
    preprocessed output                         0 occurrences of the struct body

The type is INCOMPLETE in every userspace TU. Both declarations preprocess to
byte-identical text, and it is the absent struct body -- not the signature --
that makes clang reject them. Sourced verbatim from
Kernel/xnu/osfmk/mach/coalition.h:171 into 4 SDK copies. Error gone.

## 17. LIMITATION OF THE CENSUS (sec. 13) -- what "15 symbols" did and did not mean

The census compared #defines and typedefs. It therefore CANNOT see a struct
definition, a variable, or an enum. "15 symbols" was complete for its own
method and INCOMPLETE for the header surface: struct coalinfo_debuginfo was
missing and invisible to it. Any future census on this tree must state its
method explicitly, or repeat this error.

## 18. THE BRIDGE IS AT ITS LIMIT -- do not source across this line

    <R>/libsyscall/mach/port_descriptions.c:80: error: static assertion failed
      _Static_assert(HOST_DOUBLEAGENTD_PORT == HOST_MAX_SPECIAL_PORT,
                     "all host special ports must have descriptions");

The sourced constant is NOT wrong -- in-tree and SDK agree byte for byte:

    osfmk/mach/host_special_ports.h:114  #define HOST_DOUBLEAGENTD_PORT (28 + HOST_MAX_SPECIAL_KERNEL_PORT)
    <SDK>/usr/include/.../host_special_ports.h:297   (identical)

The divergence is the coordinated port-numbering SCHEME. The SDK sets
HOST_MAX_SPECIAL_PORT = HOST_FAIRPLAYD_PORT; xnu's port_descriptions.c
asserts it equals HOST_DOUBLEAGENTD_PORT.

**DO NOT source a port-numbering block across a generation boundary.** The 15
independent constants were safe. These are not independent: they encode an ABI
contract with the kernel, and a wrong value does not fail to compile -- it
silently routes to the wrong port. Stopping here is deliberate. The honest
finding is that the SDK mach tree and in-tree xnu are different xnu releases
and libsyscall targets a third; this needs a deliberate generation
reconciliation, not more sourcing.

---

## 2026-09-26 — dyld: the honest headline, and a third measurement lesson

**dyld has made NO progress across many rounds.** The frontier has not moved
from `corecrypto/ccdigest.h` not found. The `<version>` fix and the
`SDK_SOURCE_DIR` fix were real, but **neither moved the object count.**

**Object count: 1, not 2.** Measured by `find . -name '*.o' -delete` followed by
a full `bmake` rebuild — a clean-slate count, not an incremental one. The
method is recorded with the number because the number without the method was
what caused the earlier 2 to be over-quoted.

**The mechanism by which the overlay fails to win that include is
UNESTABLISHED.** What is known: `Kernel/xnu/EXTERNAL_HEADERS/corecrypto/ccdigest.h`
is present and is a complete, genuine 6,285-byte Apple header — not a stub.
That sentence is the open item. It is not "absent", and it is not "a stub".

### Third measurement lesson: do not instrument by substitution

> **Substituting the thing you are measuring cannot answer a question about
> it.** The `-I` trace was done by replacing `isysroot-cc` with a logging shim.
> That bypassed the wrapper's `overlay_for` function entirely, so the `-I` path
> observed was the raw one, not the substituted overlay. The test could not
> answer the question it was built for, and its output was uninformative in
> **both** directions. The correct instrument is to log from *inside*
> `isysroot-cc`, or to tee the real invocation after the wrapper has run.

This is the same shape as the other two: *check which tree wins*, and *a driver
result is only valid on a quiet tree*. **All three are now collected.**

Also noted for whoever reads the overlay: a mid-rebuild read briefly reported
the overlay's `corecrypto/ccdigest.h` as 79 bytes. That was a **stale symlink
being written**, not a stub. Re-reading gave the full real header. Do not
conclude "stub" from a single read of a file that may be mid-rebuild.

## 19. PROBE STATUS: STILL NOT MEASURED -- the treatment arm was a no-op

    CONTROL    rc=0   693 objects   0 errors
    TREATMENT  rc=0   693 objects   0 errors   <-- IDENTICAL, and MEANINGLESS

    NOTE (2026-09-27, flagged by critical-path): the `rc=0` in both lines is a
    COMPILE-stage figure, not a whole-build one. The link stage fails in both
    arms, identically, on `ld: library 'system_trace' not found` -- sec. 20's
    documented libsystem_trace blocker, unrelated to mach headers. Any gate
    written as "693 objects, rc=0" therefore has a stale half that no run can
    reproduce; the gate is **693 objects, 0 COMPILE errors**, with the link
    failure recorded separately as a known arm-independent failure.

The treatment looked green. It is not evidence. `grep -c probe_osfmk_mach` over
the entire treatment build log returns **0**: the overlay was never consulted
by a single translation unit. The two arms are the same build.

Cause: `EXTRA_INCLUDES` does not reach `isysroot-cc` through
`build-libraries.sh`. The script sanitises and re-exports its own environment
(it hardcodes `EXTRA_DEFINES` at line 46), so a variable set in the caller's
environment does not survive into the bmake sub-makes. My isysroot-cc proof
worked because it called the wrapper directly; the build path does not.

ALSO worth knowing, and the reason a naive single-TU probe would have misled
here: `libsystem_c/darwin/compatibility.c` includes NO mach header at all, so
it pulls nothing from the overlay under any circumstances. Proving the
passthrough on that file proves nothing about the treatment. A valid treatment
must show a non-zero overlay hit count in the build log, or it is a no-op.

LESSON, and it is the same one three times now: a probe is evidence only when
its treatment arm demonstrably differs from its control. Green-on-both-sides
is the failure mode to fear, not red.

The gate itself is proven inert:
  C input,      unset vs empty-set   BYTE-IDENTICAL (511 B)
  C input,      unset vs set         +1 argument (/tmp/probe_osfmk_mach)
  assembler,    unset vs set         BYTE-IDENTICAL (370 B)

## 20. libsystem_trace HAS SOURCE BUT IS NOT BUILDABLE

Measured, not assumed. `Libraries/Libsystem/libsystem_trace/` really does
contain log.c, signpost.c, init.c, three headers and a Makefile -- 1,004
lines of C. It was wrongly filed under "no source, never obtainable"; the
source is there. That does NOT make it buildable, which is the finding.

Three types it needs, checked by BARE NAME across the whole tree and the SDK:

  lck_spin_t             1 definition, and it is KERNEL-PRIVATE:
                           Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/i386/locks.h:42
                           inside `#ifdef MACH_KERNEL_PRIVATE`, and the member
                           uses `__kernel_data_semantics`. There is no
                           userspace declaration anywhere. Sourcing this into
                           userspace would mean inventing a userspace ABI for a
                           kernel lock primitive.

  os_log_buffer_s        0 files anywhere -- tree or SDK
  os_log_buffer_context_t 0 files anywhere -- tree or SDK

`Kernel/xnu/libkern/os/log_mem.h:36` uses all three unconditionally. So
libsystem_trace cannot be built without inventing at least two struct layouts
and one kernel-private type, which the project rules forbid outright.

This also answers the original handoff's open question about lck_spin_t: it
is not "unsourceable" so much as KERNEL-ONLY. That is a different and more
useful answer, and it is why substituting a userspace lock_spin_t was never
going to be right.

## 21. FIXED: isysroot-cc treated "-x objective-c" as C++

The uses_cxx loop matched a bare `-x`, so ANY invocation with -x got the
libc++ stdint force-include -- including plain Objective-C. libsystem_trace
builds with `-ObjC -x objective-c` and failed with:
  <SDK>/usr/include/c++/v1/stdint.h:106:10: error: '__config' file not found
  <SDK>/usr/include/c++/v1/__config:13:10: error: '__config_site' file not found
which is the known symptom of force-including libc++ into a build that does not
have libc++ on its path. Now only an explicit c++/c++-header/objective-c++
argument sets uses_cxx; a bare -x no longer does. The .cpp/.cxx/.CC/.mm
extension cases are unchanged.

## 22. SOLVED: dyld's ccdigest.h blocker was a bmake PARSE defect, not an include defect

Closes the open item recorded in the 2026-09-26 dyld section, which said the
mechanism by which the overlay fails to win that include was UNESTABLISHED.
It is now established, and it is not an include-resolution question at all.

    Libraries/dyld/Makefile, inside the backslash continuation of COMMONFLAGS:
        -I${.CURDIR}/../Libsystem/liblaunch \
        # The openbsm ROOT was on the include path ...        <-- comment
        #   (The -isystem-beats--I hypothesis was tested ... \
        -I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS

bmake ends a variable assignment at a comment, so the assignment stopped at
`liblaunch` and the last four `-I` paths never reached the compiler. This is
the sec. 5 hazard (# inside a backslash continuation) occurring SILENTLY
instead of as "Unassociated shell command", which is why it survived several
rounds of investigation.

Measured, three independent ways:

    bmake -V COMMONFLAGS          12 -I paths, last is .../Libsystem/liblaunch
    after the fix                16 -I paths, last is .../EXTERNAL_HEADERS
    clang -E -v (real cmd)       ZERO corecrypto dirs on the search list

The `-H`/`-v` search list has 17 entries and not one of them contains a
`corecrypto` subdirectory. The overlay on disk was complete and correct the
whole time -- `inc-208358498/corecrypto/ccdigest.h` is a valid symlink to the
real 6,285-byte Apple header -- it was simply not on the command line. So the
question "which corecrypto path wins" has the answer **none of them**: there
was no corecrypto path to win.

Only `-isystem` in the whole command is the wrapper's `c++/v1` conversion, and
it contains no corecrypto either, so the -isystem-beats--I hypothesis is
refuted for the third time on this component. Fix: move the comment ABOVE the
assignment, per sec. 5's own rule. Commit 37f7cd727f.

    clean-slate build, quiet tree verified immediately before:
    before  1 object  (src/start_glue.o)  -- blocked on corecrypto/ccdigest.h
    after   2 objects (src/start_glue.o, src/glue.o)

Counted as Mach-O objects only. **A raw `find -name '*.o'` over-counts**: the
build also emits `.depend.._src_glue.o`, a makedepend artifact that is not an
object, so the naive count reports 3 for a build that produced 2. Any dyld
object count quoted without saying which of the two it is is not reproducible.

### The new frontier, and a REFUTED hypothesis

`src/glue.c` compiles; the build now stops on `dyld3/Tracing.cpp` with
`cstddef:46` / `cstring:66` / `cstdlib:90` / `climits:46` "tried including X
but didn't find libc++'s X header".

The handoff's proposed test -- remove `-I .../libsystem_c/include` as a
single variable -- **does not work**. Run on the real Tracing.cpp command, it
leaves all of those errors firing unchanged. That is measured, not assumed.

With it removed, `clang -H` shows `<stddef.h>` still resolving to

    /Users/max/Projects/build/Tools/inc-208358498/stddef.h

which is the **EXTERNAL_HEADERS overlay** -- i.e. the very path this commit
restores. So the blocker is not `libsystem_c/include` at all; it is that
`EXTERNAL_HEADERS` carries its own stale generation of the C library headers
and now wins them, exactly as the inventory predicted (it lists
EXTERNAL_HEADERS' stdint/stddef/stdlib as content-divergent). The overlay
strips only `Availability*` from that tree; `stdint.h` (2,517 B), `stddef.h`
(2,688 B) and `stdlib.h` (381 B, a one-line FBSD shim) are all still live in
it as symlinks, and every one of them is an `-I` while libc++'s `c++/v1` is
the single `-isystem`, so `-I` wins and libc++'s shims are skipped.

`Libraries/Libsystem/corecrypto/Makefile` sec. 70-76 has already diagnosed and
fixed this identical shadow for corecrypto ("That -I has been removed"), and
the obvious remedy -- extend the overlay's existing strip list in
isysroot-cc -- is therefore **NOT taken here, deliberately**: `-I
EXTERNAL_HEADERS` is also carried by `libBase/Makefile`, `libFreeBSD/Makefile`
and `Libraries/Libsystem/Makefile`, so the change is cross-component and
cannot be validated while another worker is building into the same SDK.

Worse, it would silently not take effect. `overlay_for` rebuilds only when the
overlay's `.stamp` is missing or when something in the SOURCE tree is newer
than the stamp. The strip list lives in the wrapper's own body, not in the
source tree, so editing it does NOT invalidate the stamp and the next build
would reuse the stale overlay without a word. Any such change has to fix the
stamp key at the same time, and then force a rebuild by hand -- which is the
half-written-overlay window in which a previous round read
`corecrypto/ccdigest.h` as a 79-byte stub and nearly recorded a real header as
a fake. Two coupled changes to a shared component, unvalidatable on a busy
tree: a decision, not a change to make alone.

### Fourth measurement lesson: a flag in the Makefile is not a flag on the command line

`# The openbsm ROOT was on the include path`, `SDK_SOURCE_DIR` and now this
comment are three defects in a row that all had the same shape -- **the
Makefile says the flag is there and the compiler never received it.** Each was
found by looking at the file. Each was fixed by looking at the *command*.
`bmake -V <var>` and the echoed recipe are the two cheapest instruments in
this project and they were skipped every time.

Generalise it: when a build fails on a missing header, before asking which
copy wins, ask whether the directory is on the list at all. `clang -E -v`
prints the whole list in one shot and settles it.

## 23. dyld's libc++ shim class: guard collision, NOT search order

`dyld3/Tracing.cpp` died with 20 errors across `cstddef`, `cstring`,
`cstdlib`, `climits`, `cctype`, `cwchar`, `cwctype`, all of the form
"tried including <X.h> but didn't find libc++'s <X.h> header".

### The cause, and why reordering could never have worked

libc++'s `c++/v1/<name>.h` is a shim that forwards to the C header and only
then defines `_LIBCPP_<NAME>_H`. Its first branch is

    #if defined(__need_ptrdiff_t) || defined(__need_size_t) || ...
    #  include_next <stddef.h>
    #elif !defined(_LIBCPP_STDDEF_H)

so when the C header is **already open**, the shim deliberately declines to
define the guard. An earlier header (`sys/param.h`, the `machine/*` headers)
opens the C `<stddef.h>` first; `cstddef`'s own `#include <stddef.h>` is then a
no-op under the C header's guard; `_LIBCPP_STDDEF_H` is never set; the
`#ifndef` fires. This is the **same mechanism** that already forced
`stdint.h` to be force-included in sec. 21's neighbourhood, and it is a
guard collision, not an ordering problem.

MEASURED on the real command bmake echoes, Tracing.cpp:

    c++/v1 moved ahead of the shadowing -I    20 -> 7 errors, cstddef:46
                                             still fires. Ordering is not the
                                             cause. Do not retry this.

### The set must be derived, and the order is load-bearing

Two separate traps, each of which cost a round:

    8 hand-listed shims                     Tracing.cpp 0, then Closure.cpp
                                             dies at cstdio:104 -- stdio.h was
                                             missing from the list
    all 21 libc++ shims, alphabetical       20 errors: WORSE than the 8
    17 derived shims, alphabetical           5 errors: cstddef, cstdint
    17 derived shims, stddef/stdint FIRST    0 errors, Mach-O produced

The 21-shim superset is worse because the set must be *the shims libc++'s
cxxx wrappers reference*, not "every `*.h` mentioning `include_next`".
`stdatomic.h` in particular collides with `Kernel/xnu/libkern/os/atomic.h`
over the identifier `atomic_store_explicit` (flagged independently by `plan`).
The order fails alphabetically because `ctype.h`, `float.h` and `math.h` sort
ahead of `stddef.h` and drag the C headers in behind it.

`isysroot-cc` now derives the list from libc++'s own cxxx wrappers, with
`stddef.h` and `stdint.h` named explicitly and emitted first.

### The count, with its method, because the method is the measurement

Counted as **Mach-O objects only**, per `file(1)`, excluding the makedepend
artifact `.depend.._src_glue.o` and the pre-existing deleted
`unit-tests/bar.o`. A raw `find -name '*.o'` over-reports, which is the most
likely reason earlier rounds disagreed about this number.

    COMMONFLAGS truncation fixed (sec. 22)      2
    + libc++ shim family                         8
    + cache self-invalidation                    8   (no regression)

## 24. A CACHE KEYED ON ITS DATA CANNOT SEE A CHANGE TO ITS CODE

`overlay_for` rebuilds the EXTERNAL_HEADERS mirror when its `.stamp` is
missing or when something **under `$src`** is newer. The strip list that
decides `Availability*` is excluded lives in `isysroot-cc`'s body, not in
`$src`. So editing the strip list changed the overlay's correct contents
without invalidating anything, and the next build reused the stale overlay
and **reported success**. Anyone editing that list would have concluded the
edit had no effect, which is the same failure shape as the half-written
overlay in which a real 6,285-byte header read as a 79-byte stub.

`libcxx_shim_list`, added one commit earlier, reproduced the identical defect
in new code. Both now also test `[ "$0" -nt "$stamp" ]`.

Note that the libc++ shim work does **not** make the strip list irrelevant --
the two are orthogonal. The force-include changes which header libc++ opens
first; the strip list changes which files the overlay mirrors. dyld's
`cstddef` class cleared without touching the strip list at all, which is
itself the proof that they are independent.

TESTING THIS, two ways that both produce a FALSE "the fix did not fire":

1. `touch isysroot-cc` immediately after a build is not a valid test. `touch`
   within the same second as the previous stamp write is not strictly newer,
   and `-nt` is strict.
2. A command with no `-I` for that tree never calls `overlay_for` at all, so
   its stamp cannot move. The first attempt at this test reported a failure
   that was entirely an artefact of the test. Force the stamp old instead:
   `touch -t 200001010000 <stamp>`, then assert it advances.

## 25. (SOLVED in sec. 26) dyld's next blocker is the openbsm include path, again

    Libraries/Libsystem/liblaunch/vproc_priv.h:31:10: fatal error:
        'sys/bsm/audit.h' file not found

`Libraries/openbsm/sys/bsm/audit.h` exists and is real. Commit a6e2c35015
dropped `-I .../Libraries/openbsm` **entirely** to clear the 19-byte ASCII
data file `Libraries/openbsm/version` (contents: `OPENBSM_1_2_alpha5`), which
won libc++'s `<version>` include. That removed the hazard and the
`sys/bsm/*` headers together: one directory, one `-I`, two unrelated needs.

So the same defect that was fixed by subtraction is now blocking by
omission, and the obvious remedy is the mirror image of what was done before:
an overlay for openbsm that drops only the `version` data file. That is the
idiom `overlay_for` already implements for four other trees. NOT done here,
because it is a second change in the same shared wrapper and the frontier
should be moved one measured step at a time.

## 26. SOLVED (sec. 25): openbsm overlay, and the case trap in it

`openbsm` now joins `overlay_for`'s case list; the overlay omits `version` and
keeps all 272 remaining files. The `-I` is back in `Libraries/dyld/Makefile`.

    overlay 272 files, source 273      exactly one entry removed
    $OV/version, $OV/VERSION           absent
    $OV/sys/bsm/audit.h                present

**Case matters here and getting it wrong is silent.** The first attempt used
`case "$b" in version)` and excluded nothing at all: 273 files in, 273 out,
`version` still present. The file on disk is `VERSION` (uppercase), libc++
includes `<version>` (lowercase), and the volume is case-insensitive so both
stat to inode 82312419 and the include matches. But `find` reports the *on-disk*
spelling, so a lowercase pattern never matches. Now matched with an explicit
`[Vv][Ee][Rr][Ss][Ii][Oo][Nn]`, because `/bin/sh` has no `$nocasematch`.

This closes the `-Wnonportable-include-path` "specified path differs in case
from file name on disk" hint that the original comment recorded as
unexplained. The mechanism is the case difference, and it is now the fix.

Object count, Mach-O only per `file(1)`, clean-slate, quiet tree verified:
**8 -> 16**. Next blocker: `dyld3/APIs.cpp:338:14: error: use of undeclared
identifier 'PLATFORM_IOSMAC'`.

## 27. EVALUATED, NOT IMPLEMENTED: stripping the stale C headers from the EXTERNAL_HEADERS overlay

Requested as an evaluation only. **Nothing was changed.** The force-include
work cleared the libc++ half of this class; it did not clear the C half, and
this section is the measurement of what the C half would cost.

### The blast radius is two components, not four

Four Makefiles carry `-I .../Kernel/xnu/EXTERNAL_HEADERS`. Whether the
overlay's copy of a header actually WINS depends on what precedes it:

| component | overlay position | an earlier `-I $SDK/usr/include`? | overlay wins? |
|---|---|---|---|
| `Libraries/dyld/Makefile` | line 86 | no (SDK only via `-isysroot`) | **YES** |
| `Libraries/Libsystem/Makefile` | line 11 | no — SDK's is at line 20 | **YES** |
| `libBase/Makefile` | line 113 | **yes, line 112** | no |
| `libFreeBSD/Makefile` | line 495 | **yes, line 493/494** | no |

So a strip could only change dyld and the top-level Libsystem. `libBase` and
`libFreeBSD` already shadow the overlay with their own `-I $SDK/usr/include`
and are **unaffected by construction** — the two components with the most
content, and the ones most likely to be broken, are the two the strip cannot
reach. That is the opposite of the usual risk shape here, and it is worth
knowing before the change is considered.

### What each overlay copy would cost, by ground truth

Measured with `clang -E -dM`, comparing macro **names** (not full lines --
comm on full lines conflates "defined differently" with "missing", which
inflated the apparent loss to 40 macros when the real name-level loss is 12).

| header | overlay macros | SDK macros | names ONLY the overlay has |
|---|---|---|---|
| `stddef.h` | 449 | 449 | **1** (`RSIZE_MAX`) |
| `stdint.h` | 483 | 713 | **12** |
| `stdlib.h` | 484 | **2,446** | **9** |

- **`stdlib.h` is the big one and stripping it is a large net gain.** The
  overlay's is the 381-byte one-line FBSD kernel shim declaring only
  `malloc`/`free`/`strtoul`; the SDK's declares 1,962 more macros. This is the
  same shadow `corecrypto/Makefile` sec. 70-76 diagnosed and removed by hand.
- **`stddef.h` is a wash** — 449 vs 449, one extra name. Low value either way.
- **`stdint.h` is the only real content risk**: the overlay's carries
  `UINT8_MIN`, `UINT16_MIN`, `UINT32_MIN`, `UINT64_MIN`, `UINTMAX_MIN` and
  `NULL`, and the SDK's genuinely does not define the `UINT*_MIN` family
  (verified directly in the file: it defines `UINT64_MAX` and no `UINT*_MIN`).
  A TU using `UINT8_MIN` and including only `<stdint.h>` would break.
  **Measured consumer count: 0 files** in `Libraries/dyld`,
  `Libraries/Libsystem/libsystem_c` or `Libraries/Libsystem/libsystem_darwin`
  reference `UINT*_MIN` at all. The risk is real but currently unclaimed.

### `stdatomic.h` CANNOT be fixed by stripping, and this is the useful part

Both copies define the macro at the centre of the `libdispatch` collision:

    EXTERNAL_HEADERS/stdatomic.h:154   #define atomic_store_explicit __c11_atomic_store
    $SDK/usr/include/stdatomic.h:131   #define atomic_store_explicit __c11_atomic_store

The `os_atomic_std(op)` macro expands its unstressed argument before
substitution, so the collision fires **whichever copy wins**. Stripping
`stdatomic.h` from the overlay would change which file is read and change
nothing about the failure. BOOT-PLAN lesson 19 warns not to strip it "without
checking who needs it"; the stronger statement is that **nobody needs it
stripped, because stripping it accomplishes nothing.** The strip list is the
wrong instrument for the atomic problem.

### Why it is still not implemented

1. The blast-radius argument above is derived from `-I` ORDER in four
   Makefiles. It is consistent with the two facts measured directly (dyld's
   `<stddef.h>` resolving to `inc-208358498`, and the inventory's `libBase`
   trace opening **zero** headers from EXTERNAL_HEADERS), but the other two
   components have no direct trace, and `Libraries/Libsystem/Makefile` is
   never itself built as a component.
2. Now that both caches self-invalidate, a wrong strip **takes effect
   immediately** rather than being silently ignored. That makes the change
   more dangerous, not less: the previous failure mode was a no-op, and this
   one is a real regression in a green component.
3. Only a full driver run can show that. It was reserved by the user and has
   not been performed.

RECOMMENDATION, if it is ever taken up: strip `stdlib.h` first and alone
(largest gain, zero measured consumers of the lost names, and it is the one
`corecrypto/Makefile` already removed by hand for the same reason). Leave
`stdint.h` and `stdatomic.h` alone. Do not treat the three as one change.

## 28. THE PORT-NUMBERING PREMISE: VERIFIED, IN THE BUILT KERNEL

Sec. 18 stopped at

    _Static_assert(HOST_DOUBLEAGENTD_PORT == HOST_MAX_SPECIAL_PORT, ...)

on the reasoning that host special port numbers "encode an ABI contract with the
kernel" and must not be sourced across a generation boundary. That reasoning
assumes the SDK's mach tree and the kernel are two peers to be reconciled. They
are not: **we build the kernel.** The premise was right and the refusal was
based on a wrong model. Evidence, strongest last:

  1. The kernel is xnu-11215. `git log --oneline -- Kernel/xnu` ->
     `4e658e7656 Kernel checkpoint: boot to userland handoff (Darwin 24 /
     xnu-11215 x86_64)`, and the only commit that has ever touched
     `Kernel/xnu/osfmk/mach/host_special_ports.h` is `394fe3eac3 "Transplant
     Darwin 24.0 (xnu-11215) kernel"`. `git status --porcelain -- Kernel/xnu`
     is EMPTY, so that header is pristine upstream, not something a previous
     worker edited.
  2. The built kernel says so:
     `/Users/max/Projects/build/DEVELOPMENT_X86_64/version.c`
       `const char __kernelVersionString[] = "@(#)VERSION: " OSTYPE " Kernel
        Version 24.3.0: Mon Aug 31 05:02:35 PDT 2026; ..."`
  3. The kernel sizes its own port array by the in-tree value --
     `osfmk/kern/host.h:81`  `ipc_port_t special[HOST_MAX_SPECIAL_PORT + 1];`
     and bounds-checks with it in `osfmk/kern/host.c:1304,1322,1360,1382`
     (`id > HOST_MAX_SPECIAL_PORT`).
  4. THE KERNEL BINARY AGREES. `otool -tV -p _host_set_special_port
     kernel.development.unstripped`, at ffffffff80024cd10:
         ffffffff80024cd24   leal  -0x24(%r15), %ecx     ; ecx = id - 36
         ffffffff80024cd28   cmpl  $-0x1c, %ecx         ; unsigned, vs -28
         ffffffff80024cd2b   setb  %cl
     accepts exactly id in [8, 35]. 8 is HOST_MAX_SPECIAL_KERNEL_PORT+1 and
     35 is 28 + HOST_MAX_SPECIAL_KERNEL_PORT == HOST_DOUBLEAGENTD_PORT -- the
     IN-TREE bound. The SDK's HOST_MAX_SPECIAL_PORT (HOST_FAIRPLAYD_PORT, 31)
     would have left userspace unable to name four ports the running kernel
     accepts, doubleagentd among them.
  5. The SDK really is the older generation. Newest copyright in
     `Developer/ravynOS.sdk/usr/include/mach` is 2019; in `Kernel/xnu/osfmk/mach`
     it is 2024. SDKSettings.json: `"DisplayName": "ravynOS 0.7 (macOS 10.15
     compatible)"`.

The gap was 5 lines, byte-for-byte, in both SDK copies of
`host_special_ports.h` -- now sourced, with 12 of the sec. 13 census constants
moved into the numbered block in their in-tree order so the header is no longer
a chimera for host special ports. `HOST_IO_MAIN_PORT` stays appended: it is a
plain value, not a port.

## 29. TWO MORE BLOCKERS CLEARED, BOTH BOUNDED

**IOKit.framework was structurally broken, not wrong.**
`err_iokit.sub:31` could not find `IOKit/IOReturn.h` although the SDK carries it:

    note: did not find header 'IOReturn.h' in framework 'IOKit'

The framework had `Versions/A/{Headers,PrivateHeaders}` and nothing else -- no
`Versions/Current`, no top-level `Headers` symlink, which is what clang's
framework lookup follows. `diff -rq` between the SDK's
`IOKit.framework/Versions/A/Headers` and `Kernel/xnu/BUILD/dst/.../Headers`
reports NO differences, so the content was already the right generation. The
two symlinks are now created (copied from System.framework's form) and repaired
on every build.

`IOKit/IOKitLib.h` was then missing too, and it is not in xnu -- xnu does not
ship IOKitLib. We own it: `Kernel/IOKitUser/IOKitLib.h`, 76,961 B, and a
byte-identical second copy at `Kernel/kext_tools/FILES/3rd/IOKit/`. Copied from
the former. Checked for a generation clash first: of the 21 `k*` symbols
IOKitLib.h names, all the ones that come from IOKitKeys.h/IOTypes.h/IOReturn.h
are present in the SDK's IOKit headers, and the four that are not
(`kIOMasterPortDefault`, `kIORegistryIterateParents`,
`kIORegistryIterateRecursively`, `kIOServiceInteractionAllowed`) are declared
inside IOKitLib.h itself, so their absence elsewhere is expected.

**`io_main_t` / `host_get_io_main` are a RENAME, not a new ABI.** xnu-11215
renamed `io_master_t`->`io_main_t` and `host_get_io_master`->
`host_get_io_main`. Measured, not assumed:

  * same trap: SDK `mach_host.h:1267` `{ "host_get_io_master", 205 }` against
    the generated `mach_hostUser.c:1093` `__DeclareSendRpc(205,
    "host_get_io_main")`
  * identical request: both `{ mach_msg_header_t Head; }`
  * identical reply: both `{ Head; msgh_body; mach_msg_port_descriptor_t
    io_master|io_main; }`

So `host_get_io_main` was added ADDITIVELY beside the existing
`host_get_io_master` in `usr/include/mach/mach_host.h`, and
`typedef mach_port_t io_main_t;` (verbatim from
`Kernel/xnu/osfmk/mach/mach_types.h:227`) beside `io_master_t` in both SDK
mach_types.h copies. Nothing was replaced or removed, so no consumer of the old
spelling can regress, and the new declaration provably cannot route anywhere
the old one does not already route. `libsyscall/mach/host.c` now compiles; the
assertion of sec. 18 and this error are both gone.

**A fourth measurement lesson: `-I<dir>/mach` is not how you put a mach tree on
the include path.** `-I${.OBJDIR}/mig_hdr/include/mach` looks inert because
`#include <mach/mach_host.h>` then resolves to
`.../mig_hdr/include/mach/mach/mach_host.h`. The `-I` that works is the PARENT,
and isysroot-cc deliberately overlays exactly that one and strips its `mach/`
subdirectory (its case list has `*/libsystem_kernel/mig_hdr/include`), so the
build-generated tree is unreachable from that Makefile as written. Moving the
flag to the front of CFLAGS changed nothing, which is what made this worth
writing down. `clang -H` on the REAL captured invocation settles it:

    . <SDK>/usr/include/mach/mach_host.h

Reversing the `-I` order changes nothing either. The Makefile now carries the
finding as a comment so it is not retried.

## 30. WHERE THE CASCADE ACTUALLY STOPS: mach/message.h

With the port block, IOKit and the io_main rename resolved, `libsystem_kernel`
compiles every translation unit except ONE. Quoted from
`tools/bootlab/build-libraries.sh Libsystem/libsystem_kernel`:

    /Users/max/Projects/ravynos/Kernel/xnu/libsyscall/mach/mach_msg.c:75:15:
        error: unknown type name 'mach_msg_option64_t'
    .../mach_msg.c:78:18: error: use of undeclared identifier 'MACH64_SEND_MSG'
    .../mach_msg.c:78:50: error: use of undeclared identifier 'MACH64_RCV_MSG'
    .../mach_msg.c:84:16: error: use of undeclared identifier 'MACH64_RCV_SYNC_WAIT'
    .../mach_msg.c:205:2: error: use of undeclared identifier 'mach_msg_vector_t';
        did you mean 'mach_msg_destroy'?
    fatal error: too many errors emitted, stopping now [-ferror-limit=]

585 objects build. `libsystem_kernel.dylib` is NOT produced.

    mach_msg_option64_t   osfmk/mach/message.h 5 occurrences
                          SDK usr/include/mach/message.h          0
                          SDK .../PrivateHeaders/mach/message.h  0
    mach_msg_vector_t     osfmk/mach/message.h 2 / SDK 0 / SDK 0
    MACH64_SEND_MSG       osfmk/mach/message.h 2 / SDK 0 / SDK 0

and `mach_msg.c` names 54 distinct `mach_msg_*` / `MACH64_*` identifiers.

**STOPPED HERE, and the reason is the class, not the count.** Everything sourced
so far was a constant, a typedef of an existing type, or a routine proven to be
the same trap under another spelling -- none of which can mis-route or mis-size
anything. `mach_msg_option64_t` and `mach_msg_vector_t` are STRUCT DEFINITIONS
of the Mach message ABI. A wrong one does not fail to compile, it corrupts the
message. That is precisely the class sec. 18 was right to protect, and it is
also the class sec. 4 already tried and had to back out: the SDK's
`mach/message.h` is 34,206 B and the in-tree one is 62,286 B, and the ONE type
taken from it so far (`mach_msg_aux_header_t`) had to be delivered through a
force-include shim precisely because wholesale adoption was not safe.

Four mach headers now want the xnu-11215 generation: coalition.h, message.h,
host_special_ports.h, mach_types.h. The first three were bridgeable. The fourth
is the message ABI, and the honest reading is that this is not a list of
constants to accumulate -- it is one decision, deferred since sec. 12, about
which generation of the mach tree this SDK is.

`mach/message.h` is also the header most likely to be needed by every other
component, so guessing here is the worst place to guess.

## 28. THE SHIM FORCE-INCLUDE IS COMPONENT-SPECIFIC, AND MAKING IT GLOBAL IS A REGRESSION

The most important finding of this round, and it is a conflict rather than a fix.
Reported by `plan`: the libc++ shim force-include (§23) is blocking `libdispatch`.

MEASURED on the real `block.cpp` command captured from a `libdispatch` build log,
run through the real `isysroot-cc` with `REAL_CC=/bin/echo` to get its exact
emitted argv, then `clang` on that argv. "Old" = `a71c46f5ac^` (stdint.h only),
"new" = HEAD (17 shims).

    OLD (1 shim)    20 errors   17x resource.h "unknown type name 'uint64_t'"
                               2x resource.h "unknown type name 'uint8_t'"
    NEW (17 shims)  20 errors   16x aligned_storage.h "reference to unresolved using declaration"
                                3x type_list.h      "reference to unresolved using declaration"

**Both print "20 errors generated" and have nothing in common.** The first
instinct was to read that as "inert". It is not — this is §6 lesson 6 pointed the
other way, and the rule is symmetric: never compare counts, compare signatures.
Two builds can agree on a count and disagree on every error in it.

### libdispatch was ALREADY broken, by the pre-existing shim

`block.cpp` compiles with **zero** shims:

    0 shims                0 errors
    stdint.h alone        20 errors
    stddef.h alone        10 errors
    all 17                20 errors

Per shim, each force-included alone on `block.cpp`:

    HARMFUL (6)   stdint.h 20  stddef.h 10  wchar.h 7  limits.h 5
                  stdlib.h 5   string.h 3
    HARMLESS (11) ctype.h errno.h fenv.h float.h inttypes.h locale.h math.h
                  setjmp.h stdio.h uchar.h wctype.h

The `stdint.h` force-include — already in `isysroot-cc` **before** this round,
added for dyld's `cstdint` — produces 20 errors on `block.cpp` by itself. So
`libdispatch` was blocked before the shim family existed, on
`resource.h: unknown type name 'uint64_t'`, not on `os_atomic`. The §23 change did
not break it; it exchanged one failure for another.

Note the corollary for anyone reading `plan`'s "os_atomic is fixed": it is not
observed working, it is **masked** by an earlier failure, exactly as the
`-ferror-limit` reasoning implied. With zero shims `block.cpp` compiles cleanly,
so the `os_atomic` failure may not be reachable from this TU at all.

### dyld and libdispatch need OPPOSITE settings — and no subset separates them

    dyld Tracing.cpp   0 shims 20   stdint 20   stddef+stdint 6   all 17 0
    dyld Closure.cpp   0 shims 20   stdint 20   stddef+stdint 7   all 17 0
    libdispatch        0 shims  0   stdint 20                    all 17 20

Checked rather than assumed, and the two requirements are genuinely incompatible:
`stddef.h` is **required** by dyld (all 17 minus `stddef.h` = 20 errors on both
dyld TUs) and is **harmful alone** to libdispatch (10 errors). No subset of the
shim list satisfies both. The force-include must therefore become **per
component**, not global.

### Same family, opposite direction

dyld needs the shim opened FIRST, because the C header is already open and
libc++'s shim declines to set its guard (§23). libdispatch needs it **not opened
at all**: force-included early, libc++'s `stddef.h` pulls the C header in under
its own `include_next`, and `type_list.h:27`
(`bool = _Size <= sizeof(typename _TypeList::_Head)`) then parses with `size_t`
in a state that does not resolve. "Already opened" is the shared family; the two
components need opposite answers to it.

### What this means for the round's headline

The `8 -> 16` object count for dyld is real and was measured on a quiet tree, but
it was obtained with a **global** change whose necessity is **component-local**.
The honest statement is not "the shim family fixed dyld" but "the shim family
fixes dyld and cannot be global". Treating a component-specific workaround as
global is this project's recurring failure mode, and the reason it is written
down here rather than quietly left in place.

### NOT DONE, deliberately

The correct end state — an opt-in the component opts into, dyld in and
libdispatch out — needs a mechanism to reach a bmake sub-make, and
`build-libraries.sh` is the place for it, which another worker owns and is
mid-probe in. Doing it now would be a second change to shared files on a busy
tree, with the one instrument that could prove it (the full driver run)
reserved. Left as a recorded decision, not a silent state.

---

## 20. THE SHIM FAMILY IS NOW OPT-IN, VIA A `-D` ON THE COMPONENT'S OWN LINE

The "NOT DONE, deliberately" note above is now done, by the mechanism chosen
after escalation: a **`-D` written in the component's own `CFLAGS`**, not an
environment variable and not a change to `build-libraries.sh`.

    isysroot-cc applies the shim family only when it sees
        -DRAVYN_LIBCXX_SHIM_FORCE_INCLUDE=1
    in the argument list.  Libraries/dyld/Makefile is the only component that
    passes it.

**Why a `-D` rather than an env var.** The failure mode this whole workstream
is made of is a flag that looks set and never reaches the compiler.
`EXTRA_DEFINES` does not survive `build-libraries.sh`'s environment into the
bmake sub-makes. A `-D` in the component's `CFLAGS` travels **on the compiler
command line**, which is the one channel demonstrated to reach them. It is
also self-documenting: the reason sits in `Libraries/dyld/Makefile` next to
the code that needs it, not in a file three hops away.

**Default is off.** A component that has not asked emits nothing, which is
the safe direction for a script sitting on every component's path.

### Inertness, measured with `REAL_CC=/bin/echo` argv capture

Compared byte for byte against the previous wrapper:

| invocation | result |
|---|---|
| plain C | **BYTE-IDENTICAL** |
| `-x objective-c` | **BYTE-IDENTICAL** |
| `-x assembler-with-cpp` | **BYTE-IDENTICAL** |
| C++ TU, define absent | 17 shims -> **0** (this is the intended change) |
| C++ TU, define present | **17**, the intended set |

The `__cplusplus` gate stays tight, re-checked explicitly because this bug was
found and fixed once already:

| invocation, define PRESENT | shims emitted |
|---|---|
| **bare `-x`** (neutral filename) | **0** — a bare `-x` must not trigger |
| `-x objective-c` | 0 |
| `-x c++` | 17 |
| plain `.cpp` | 17 |
| `-x assembler-with-cpp` | 0 |

**A note on how to get that last table wrong.** The first attempt at the bare
`-x` test passed `/tmp/t.cpp` as the input, and the wrapper's `*.cpp` pattern
matched the *filename*, so the test reported 17 and looked like a failure of
the `-x` guard. It was not testing the guard at all. The input file must have
a neutral extension or the filename rule answers instead of the `-x` rule.
This is the same family as "do not instrument by substitution": the test
measured a different thing than the one being asked about.

### I reproduced, in new code, the exact defect this workstream was briefed on

Adding the `-D` to `Libraries/dyld/Makefile` was done first as a comment
block *inside* the backslash continuation of `COMMONFLAGS` — silently ending
the assignment, which is defect #1 in this component's brief and was fixed
once already. Caught on re-read, cut out, and placed **above** the
assignment. Recorded because the failure mode is not "forgetting the rule",
it is that the natural place to explain a flag is immediately beside the flag,
and that place is inside a variable assignment in a bmake file.

---

## 29. `PLATFORM_IOSMAC` — DIAGNOSED BY READING, NOT YET FIXED

Frontier:

    ./dyld3/APIs.cpp:338:14: error: use of undeclared identifier 'PLATFORM_IOSMAC'

**What it is.** A `dyld_platform_t` constant from `<mach-o/loader.h>`, spelled
`6` in the SDK's generation and renamed `PLATFORM_MACCATALYST` in the newer
one. Both define the value; only the spelling differs. It is a **rename across
loader.h generations**, not a missing declaration and not an ABI question —
nothing here encodes a wire contract, so the usual "do not invent an ABI" bar
does not apply to the constant itself.

**This is `undeclared identifier`, therefore the header RESOLVED.** A header
that is not on the path says `file not found`. Per §6.0, the question is
never "where is it?" but "which copy answered?"

**Which copy answered — from the real emitted argv, `-H` on the exact command
the wrapper produced:**

    # 1 ".../build/Tools/inc-208358498/mach-o/loader.h" 1 3 4

and that resolves to:

    /Users/max/Projects/ravynos/Kernel/xnu/EXTERNAL_HEADERS/./mach-o/loader.h

**Exactly one** `mach-o/loader.h` is ever opened. It is the
`EXTERNAL_HEADERS` overlay, reached through
`-I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS`, and the SDK's own
`usr/include/mach-o/loader.h` is **never read**.

**The generation gap, quoted:**

    EXTERNAL_HEADERS (WINS)          SDK usr/include (loses)
    #define PLATFORM_MACCATALYST 6    #define PLATFORM_IOSMAC 6
    #define PLATFORM_MAX ...          (no PLATFORM_MAX)

So the winner is the **newer** generation here, and dyld's source is written
against the **older** spelling. That is the mirror image of sec. 11, where
the in-tree `mach_types.h` was older despite being larger. **File size is
still not a proxy for generation, in either direction.**

References in dyld's own sources: `PLATFORM_IOSMAC` x6, `PLATFORM_DRIVERKIT`
x1, `PLATFORM_MACCATALYST` x0, `PLATFORM_MAX` x0. dyld needs the old
spelling and does not use anything only the new one offers.

**Is the overlay's `mach-o/` needed at all?** Measured against the SDK's tree,
which is a strict superset for headers:

    files in EXTERNAL_HEADERS/mach-o but not in the SDK:  Makefile, arm
                                                       (neither is a header)
    identical in both:  nlist.h, reloc.h
    divergent:          fat.h, fixup-chains.h, stab.h, loader.h

So dropping `mach-o/` from the `EXTERNAL_HEADERS` overlay — the same
treatment `Availability*` and the two `Kernel.framework` trees already get in
`overlay_for()` — would let the SDK's complete tree win and would very likely
supply `PLATFORM_IOSMAC`. **That is a hypothesis, not a result.** It is
untested, because testing it means a build, and the tree is currently held
for another worker.

**Two things to check before acting, both cheap:**

1. `fat.h`, `fixup-chains.h` and `stab.h` also differ. If a later TU wants a
   symbol only the `EXTERNAL_HEADERS` generation of one of those defines, the
   same rename trap fires again. Worth a grep of dyld's sources for the
   union of both generations' identifiers before dropping the directory,
   rather than fixing `loader.h` and discovering `fat.h` next round.
2. `EXTERNAL_HEADERS/mach-o/loader.h` is a **symlink target inside
   `Kernel/xnu`**, which is off-limits to edit. The overlay is the only lever,
   and that is the right one: it changes no source file.

### 30. THE STRIP IS CORRECT; THE 10:16:28 OVERLAY WAS NOT GENERATED BY IT

Recorded because the sequence of events is a trap, and because for several
steps the correct-looking conclusion was the wrong one.

**What happened.** The `mach-o/` strip was added to `overlay_for()` at
10:14:19. The live overlay `Tools/inc-208358498/.stamp` shows 10:16:28 --
*after* the edit -- and at that moment the overlay still contained all ten
`mach-o/` entries. Read naively that says "the strip condition does not
match", and the cache self-invalidation test (`[ "$0" -nt "$stamp" ]`)
correctly reported NO, which appears to confirm "the cache is reusing a
stale overlay".

**Both readings were wrong, and each was a false instrument:**

- *The cache was not stale.* A regeneration demonstrably happened at 10:16:28.
- *The condition was not broken.* Regenerating from the current script into a
  scratch `ROOT_BINARY_DIR` (which writes nothing into the build tree) yields:

      mach-o/ symlinks : 0     <- the strip under test
      Availability*    : 0     <- the WORKING control, same code path
      ptrcheck.h       : present <- proves the overlay IS populated
      total symlinks   : 127

  127 is exactly the count the strip predicts. Forcing the live overlay to
  regenerate produced the same 127, with `mach-o/` empty and `Availability.h`
  still absent.

**So the strip works. The 10:16:28 regeneration ran a DIFFERENT, older copy of
the script.** `137 - 127 = 10`, and the ten missing symlinks are exactly the
`mach-o/` entries, which pins the 10:16:28 overlay as the pre-strip shape.
The overlay is shared mutable state under a build that was already running,
which is the same §6.3 condition that voided that build for an unrelated
reason.

**The methodological point, and it is the one worth keeping.** Three
consecutive readings were available and all three were wrong:

1. "the overlay still has mach-o, so the strip failed" -- **no positive
   control.** The check never demonstrated it could see a strip that *had*
   applied.
2. "the cache says NOT-newer, so the cache is stale" -- the `-nt` test
   answers a question about *mtimes*, and was read as an answer about
   *content*.
3. "a clean-tree regeneration proves the condition is correct" -- correct,
   but reached only after theorising for several steps about `sh` reading
   scripts incrementally, which was **never tested** and is, on inspection,
   not the explanation: every compiler invocation is a fresh `sh`.

The generalisation, and it is the same rule as the four false probes:

> **A negative result from any probe must be accompanied by a positive
> control proving the probe CAN see the thing it is looking for. "0 hits" is
> only evidence after you have shown the probe produces non-zero hits when
> something is there.**

`Availability*` is the ideal control here because it travels the *same* `case`
statement as `mach-o/`: 0 for both means both strips fired, and `ptrcheck.h`
being present means neither reading is "the overlay is empty".

**Consequence for the record:** between 10:14:19 and the forced regeneration,
the committed strip was INERT — the script said one thing and the overlay on
disk was another. A reader trusting the commit would have been wrong. Stated
here so the interval is not mistaken for a working state.

**Why it is not simply "add `-DPLATFORM_IOSMAC=6`".** That would be a shim
in the exact class §5.5 condemns — it makes the error disappear without
making the code agree with the header, and it hard-codes a platform number
in a Makefile. The declaration exists; the fix is to let the right generation
answer, not to re-declare the name.

---

## 31. THE REAL EXPOSURE SURFACE OF THE SHIM OPT-IN — AND ICU IS NOT IN IT

The shim opt-in (sec. 20) removed a previously-**global** `-include` of 17
libc++ headers from every C++ translation unit in the project. The risk is
that some component genuinely needed it and now fails *later*, at whatever
libc++ header it was quietly relying on — a silent failure, not a loud one.

**Enumerating that surface, from the driver's own stage list rather than from
anyone's recollection** (`build_all_libsystem.sh` lines 140-195 plus the loop
at 129), the components the driver actually builds are:

    objc4  CrashReporterClient  libxpc  liblaunch  libsystem_notify
    libsystem_info  libdispatch  libmacho  copyfile  removefile
    Libsystem (libSystem.B)  dyld

Of those, the ones with C++ sources are:

| component | C++ sources | shim status |
|---|---|---|
| `dyld` | 81 (src/ + dyld3/) | **opts in** via `-DRAVYN_LIBCXX_SHIM_FORCE_INCLUDE=1` |
| `libsystem_malloc` | 55 | lost it — the largest real exposure |
| `libdispatch` | 2 | lost it; **this was the one that broke**, now green |
| `libsystem_m` | 1 | lost it |
| `CommonCrypto` | 1 | lost it — not a driver stage |

Everything else in the driver is C or Objective-C and **could not have been
affected at all**: the wrapper's own gate requires `uses_cxx=yes`, which is
only set by a `*.cpp`/`*.mm` input or `-x c++`. So the exposure is not seven
components. It is three unmeasured ones — `libsystem_malloc`, `libsystem_m`,
`CommonCrypto` — plus the two already measured.

**ICU IS NOT BUILT BY THE DRIVER.** `Libraries/ICU` has its own Makefile and
**794** C++ translation units (the figure circulating as "477" is low, though
the direction is right), and it appears **nowhere** in the driver's stage
list. Two consequences, and the second is the one that should worry:

1. ICU is not a driver risk, so it is not on the critical path.
2. **A green driver run will never say whether the shim opt-in broke ICU.**
   794 TUs of exposure, no instrument. If ICU is in scope for this project it
   needs its own build, separate from any driver work, and that is a larger
   job than the three components above. Recorded, not started.

**Order to measure when the tree is free** — largest real exposure first, so
that if time runs out the informative results already exist:

    a. libsystem_malloc   (55 C++ TUs)
    b. libsystem_m, CommonCrypto  (1 TU each, cheap)
    c. dyld               — the 16-object guard, which is the guard on EVERY
                            shared-file change in this workstream
    d. libdispatch        — confirm the fix is not order-dependent

Each on a `ps`-verified quiet tree, reporting error **signatures** and not
counts (sec. 6 lead-in), and each reported with that component's own opt-in
state stated.

---

## 32. THREE UNMEASURED CHANGES LANDED TOGETHER — THE ATTRIBUTION LIMIT

Three changes to shared state are now in the tree with **no measurement taken
after any of them**:

| commit | change | touches |
|---|---|---|
| `a2afd3728c` | libc++ shim family → per-component `-D` opt-in | every C++ TU in the project |
| `26279809fb` | `mach-o/` stripped from the `EXTERNAL_HEADERS` overlay | every `EXTERNAL_HEADERS` carrier |
| (earlier) | overlay caches self-invalidate on `$0 -nt $stamp` | every overlay |

**Consequence, stated so a future failure is not blamed on the wrong one.** If
the next dyld build moves the object count, **nothing in that number
identifies which of the three did it.** Any later bisect must start from this
paragraph, not from a guess that the most recent change is the culprit — the
most recent change is `26279809fb`, but the shim opt-in is the larger blast
radius and the overlay self-invalidation changes the *derived state* both of the
others depend on.

**Why the next measurement is a COMBINED build rather than a bisect.** The
operational question is whether dyld still builds and is further along, and one
combined clean-slate number answers it. Attribution is only worth tree time
when something **breaks**: a failure with three candidate causes is what
actually needs bisecting, a success does not. The cost profile is asymmetric
and spending a round to attribute a success is the wrong trade. **If the count
drops, or a new error signature appears, bisect immediately and say which
change was isolated first.**

**Order once the tree frees:** combined dyld clean-slate → `libsystem_malloc` →
`libsystem_m` → `CommonCrypto` → `libdispatch` order-dependence check.

## 33. A REPORT MUST BE ABOUT THE STATE, NOT THE EDIT

Third instance today of catching a claim at the moment of reporting it. The
general form, and it is the same shape as the count-versus-signature error in
one direction and as a green result that means nothing in the other:

> **Never relay a change as applied without checking that it took effect.
> A report is about the state the edit produced, not about the edit.**

- The `mach-o/` strip was committed and reported as done. It was **inert**:
  the script said one thing and the overlay on disk said another. Caught only
  because a probe was run against the live overlay instead of trusting the
  commit.
- Two "20 errors" readings were reconciled as "no change" because the counts
  matched. The error **sets** were disjoint. Same failure: reporting on a
  proxy (a count, a commit, a script) instead of on the state.
- A bare-`-x` gate test passed a `.cpp` input, so the *filename* rule answered
  the question the *flag* rule was supposed to. The probe measured something
  adjacent and the result was read as a finding.

**The corrective in all three cases is the same and it is cheap:** before
reporting, run a probe against the artifact that will actually be consumed —
the overlay on disk, the error set, the flag under test — and include a
positive control proving the probe can see a thing that is there. Committing a
change is not evidence that it is in effect, and this project's caches make
that distinction concrete rather than theoretical.

## 31. PROBE: STILL NOT MEASURED (fifth round), but the plumbing is now closed

Verdict: **still not measured.** Not "not survivable", not "survivable".

What this round DID establish, which four previous rounds could not:

    CONTROL     overlay hits = 0
    TREATMENT   overlay hits = 10 of 10 invocations

`EXTRA_INCLUDES` now reaches `isysroot-cc` through the real bmake sub-make
path. The re-export in build-libraries.sh works. Rounds 1-4 all recorded 0
hits, which is why every one of them had to report "not measured" no matter
what the object count said.

**That is plumbing and nothing more.** 10 hits in 10 invocations says the flag
arrives; it says nothing about whether libsystem_c survives a full xnu-11215
mach generation. Quote it as plumbing. A hit count that saturates immediately
is the signature of a working flag, not of a survivable configuration.

Why the arms are still void, stated as measured rather than as excuse:

  - Neither arm RAN TO COMPLETION. Both returned rc=137 (SIGKILL). The control
    reached 604 of the 693 baseline objects before it was stopped; the
    treatment reached 10 objects. A partial arm is not an arm.
  - The treatment was making no progress: 0 invocations in a 60 s window,
    stuck at 17, while a `dyld` build (`isysroot-cc.prestrip ... -DBUILDING_
    LIBDYLD`) was running in the same tree. Two builds contending for one
    generated SDK is the "0 unexpected failures made on a busy tree" lesson
    from sec. 15, arriving a third time.
  - The wrapper hash WAS stable across what ran -- 4402b3c7 before the control,
    after the control, and after the treatment. That check is now built into the
    run script and it is what let the straddle in the previous round be caught
    in seconds instead of after the fact. It is the one piece of probe
    infrastructure that has actually paid for itself.

Earlier rounds of this same probe, for the record:
  round 1-2  EXTRA_INCLUDES did not survive build-libraries.sh
  round 3    passthrough proven at the wrapper only; build path never wired
  round 4    wired; treatment was a no-op for a different reason (the probe TU
             includes no mach header)
  round 5    this one: flag demonstrably arrives; arm still did not complete

**Recommendation, and it is a change of plan rather than another attempt.** The
probe question -- can libsystem_c be built against a wholesale xnu-11215 mach
tree -- is now the SECOND question. The first is sec. 30: `mach_msg.c` cannot
compile without `mach/message.h` from the xnu-11215 generation, because
`mach_msg_option64_t` and `mach_msg_vector_t` are struct definitions of the
message ABI and exist in no SDK copy. libsystem_c and libsystem_kernel are
blocked on the SAME decision, and resolving it for one resolves it for both.
Running the survivability probe before that decision is a waste: it measures
whether libsystem_c tolerates an overlay that the final answer is unlikely to
install. Pick the mach generation deliberately, then re-run the probe against
the real thing rather than against /tmp.

## 32. DURABILITY PROVEN for sec. 28/29, by the sec. 8 method

The standard set in sec. 8 is: delete the generated file, re-sync, verify. Not
"the sync step should cover it". Done, for all seven artifacts:

    DESTROYED in the generated SDK
      usr/include/mach/{host_special_ports.h,mach_types.h,mach_host.h}
      System.framework/.../PrivateHeaders/mach/{host_special_ports.h,mach_types.h}
      IOKit.framework/Headers                       (symlink)
      IOKit.framework/Versions/Current              (symlink)
      IOKit.framework/Versions/A/Headers/IOKitLib.h

    RE-RAN the sync steps from build-libraries.sh  ->  ALL SEVEN RESTORED
      usr/include/mach/{host_special_ports.h,mach_types.h,mach_host.h}   RESTORED
      PrivateHeaders/mach/{host_special_ports.h,mach_types.h}            RESTORED
      IOKit.framework/Headers                                            RESTORED
      IOKit.framework/Versions/A/Headers/IOKitLib.h                      RESTORED

    CONTENT, not just presence
      #define HOST_MAX_SPECIAL_PORT           HOST_DOUBLEAGENTD_PORT
      typedef mach_port_t             io_main_t;
      1 occurrence of `kern_return_t host_get_io_main`

So a regenerated SDK keeps the port block, the io_main_t/host_get_io_main
rename, the IOKit framework symlinks and IOKitLib.h. The sec. 28 finding is
durable in the same sense as the sec. 8 asm_help.h fix and the sec. 13 census,
which is the only durability claim worth making in this project.

Caveat, stated rather than glossed: the sync was executed by extracting the
steps verbatim from build-libraries.sh rather than by running the whole script,
because the script always proceeds to build. The lines exercised are the
`sync_mach` pair and the IOKit block; a reader wanting the stricter form can
run `build-libraries.sh` on any component and check the same seven paths.

---

## 34. objc4 IS A BOOT-CLOSURE RISK, NOT A LATENT ONE — RE-PRIORITISED ABOVE libsystem_malloc

Checked rather than assumed, because the argument was "being in the goal
closure beats being large" and that deserves evidence.

**objc4 has 44 shim-reachable translation units.**

    .mm   43      <-- Objective-C++, matches the wrapper's *.mm rule
    .cpp   1
    .m   187      <-- plain Objective-C, NOT shim-reachable
    .c    13

And it passes `--sysroot=$RAVYN_SDKROOT` 16 times, which is the shim trigger's
precondition. **It does NOT put `c++/v1` on its own include path (0
occurrences) — and was shimmed anyway**, which is precisely the global-trigger
defect of sec. 20/31: the trigger tested the SDK's filesystem, not what the
component asked for.

**Measured, both directions, on the real wrapper:**

    pre-opt-in wrapper,  -x objective-c++   -> 17 shims
    current wrapper,     -x objective-c++   ->  0 shims

So objc4 **lost all 17** at the opt-in, across 44 TUs.

**And it is in the Phase 7 closure, which is what makes this different from
ICU.** `tools/bootlab/stage_dynamic_libs.sh` stages
`$SDK/usr/lib/libobjc.A.dylib` into the boot image, and its own header
records why:

    /usr/lib/libobjc.A.dylib is required by libsystem_symptoms.dylib
        Library not loaded: /usr/lib/libobjc.A.dylib

That missing library is the hard stop that made the `___mb_cur_max` fault
reachable at all. **If the shim removal broke objc4, that is a boot
regression, not a latent risk** — unlike ICU, which is in no closure and has
no instrument.

**REVISED PRIORITY. objc4 moves ahead of `libsystem_malloc`:**

| # | component | shim-reachable TUs | in boot closure? |
|---|---|---|---|
| 1 | **`objc4`** | **44** | **YES** |
| 2 | `libsystem_malloc` | 55 | no |
| 3 | `libsystem_m`, `CommonCrypto` | 1 each | no |
| 4 | `libdispatch` order-dependence | 2 | no |

The reordering is on the stated principle, and the counts support it rather
than merely permitting it: `libsystem_malloc` is bigger (55 vs 44) but
neither it nor `libsystem_m` nor `CommonCrypto` is in the goal closure, while
objc4 is. **A failure in the closure costs the project its goal; a failure
outside it costs a build.** Size only breaks ties within the same class.

**The full run order, unchanged in composition:**

1. combined dyld clean-slate (covers the `mach-o/` strip guard, still
   UNMEASURED)
2. **`objc4`** — promoted, boot closure
3. `libsystem_malloc`
4. `libsystem_m`, `CommonCrypto`
5. `libdispatch` order-dependence

**Not yet run.** `critical-path` holds the tree for the `libsystem_kernel`
link. objc4's 44 TUs are **unmeasured against the shim removal** and this
entry is the record of that, so it is not discovered later as a surprise.

---

## 35. RUN ORDER ONCE THE TREE IS RELEASED, AND WHY objc4 LEADS

Settled with the coordinator; recorded here so the next person does not
re-derive it. **The tree need is a few seconds, not a phase** — that is the
whole reason for the ordering, and the reason not to batch it with anything
else.

    1. combined dyld clean-slate   (also the mach-o/ strip guard — UNMEASURED)
    2. objc4                        44 shim-reachable TUs, IN THE BOOT CLOSURE
    3. libsystem_m, CommonCrypto    1 TU each, cheap
    4. libsystem_malloc             55 TUs, not in closure
    5. libdispatch order-dependence 2 TUs, confirm the fix is order-independent

**objc4 leads on closure, not size** (sec. 34): `libsystem_malloc` is larger at
55 TUs, but objc4 is staged into the boot image and the others are not. A
failure in the closure costs the project its goal; a failure outside it costs
a build. Size breaks ties only within a class.

**TREE DISCIPLINE, as now agreed.** `critical-path` is the SOLE holder until
they release it explicitly. The release goes to one named worker, and nobody
infers a release from silence. Check by hand, say "verified empty", and **do
not poll** — a poller that fires the instant the holder's build exits is
exactly how a second worker gets contaminated, and that is what nearly
happened here.

**Two readings adopted from `plan` and the coordinator, recorded because they
generalise beyond this workstream:**

- A masking error class removed (20 → 0, measured) does not "break" a
  component; it **uncovers what was behind it**. The `_Pragma` gates in
  `libsystem_darwin` only became *reachable* once the first class stopped
  firing. Restoring the flag *and* fixing the real cause is the correct
  sequence, not a retreat.
- A byte-level check answers "**did my edit land**", never "**is this
  valid**". `cat -A` showing clean `# ` lines and no `<` looked like proof
  the cause was gone, while the build said no three times running. For
  validity you compile a two-line file. And a baseline that *reads* as
  covering a component which does not build is the stub-that-quietly-does-less
  defect — so the caveat belongs **inside** the baseline number, not beside it.

---

## 36. LESSONS NEED INSTRUMENTS, NOT MEMORY — and the 2x2's limit

### 36.1 The backslash-continuation bug, reproduced within the hour of writing the lesson

Sec. 5 of this file and BOOT-PLAN lesson 1 both record that a `#` comment
inside a backslash continuation silently ends a bmake variable assignment. It
is one of the most-repeated findings in this project, and it was written into
the lessons **during the same session in which I reproduced it again**, in new
code, on the very line I was adding.

What I did: added the shim opt-in as an explanatory comment block placed
immediately above `-DRAVYN_LIBCXX_SHIM_FORCE_INCLUDE=1` — i.e. *inside* the
continued `COMMONFLAGS =` assignment. Caught on re-read, cut out, moved above
the assignment.

What caught it: `bmake -V LDFLAGS` / reading back the emitted recipe — **the
exact instrument lesson 1 names**, and the one I had skipped when the original
defect was found.

**So the lesson is not a matter of remembering. The same person who wrote it,
in the same hour, did not have it. Any lesson that depends on recall will lose
to momentum.** The durable form is a mechanical check, and the only one that
worked here was *read the variable back after editing it*:

    bmake -V COMMONFLAGS     # not "did my edit look right" -- what does bmake
                             # actually hold after parsing?

`git diff` on a Makefile shows the text you wrote. `bmake -V` shows what the
parser kept. Those differ, and only the second one is the build.

### 36.2 The 2x2: better for attribution, blind for coverage

The 2x2 (shim-opt-in × mach-o-strip) is the best experimental design anyone
has run in this project, and it has a precise limit that should be stated
wherever its numbers are quoted.

**What it was good for: attribution.** Four cells, each isolating one factor,
establishing that the two dyld changes are **jointly necessary and mutually
masking** — neither alone gets you to a compiling TU, which is exactly the
configuration in which a build looks unchanged and is not.

**What it could not do: coverage.** I predicted `APIs.cpp` would be *added* to
16. In the event, **two changes cleared a whole error class and the build ran
through ten further sources to the link.** A design that answers "which change
did this" cannot answer "how much is left" — and here it understated the
remaining work by ten translation units, because the frontier moved further
than the experiment's frame allowed it to see.

Generalised, and it applies to every A/B in this project:

> **A design that isolates a variable is blind to everything outside its
> frame.** Attribution and coverage are different questions and a single
> experiment rarely answers both. Ask which one you are asking before
> building, and never quote an A/B's numbers as a progress figure.

The 2x2 result stands as attribution evidence. It was never a coverage
measurement, and treating it as one is how "16 objects" nearly became a
project-level claim when the real answer was 27.

---

## 37. dyld's LINK FRONTIER IS 132 SYMBOLS, NONE OF THEM C++

Measured on the real archive `Libraries/dyld/libdyld.a` (4.2 MB, all 27
objects; `ar t` reports 28 because of the `__.SYMDEF` member — not a defect,
checked). **No build run; the compile side was already complete.**

    undefined across the archive       621
    defined in the archive            2248
    TRULY EXTERNAL                     132
    of which C++ (mangled _Z)             0

    $ nm -u libdyld.a | awk '{print $NF}' | sort -u > u
    $ nm -g libdyld.a | awk '$2 ~ /^[TWVBDRSUT]$/ {print $NF}' | sort -u > d
    $ comm -23 u d | grep -vE '^$|:$' | sort -u      # <- 132

**The filter in that last line is load-bearing and its absence produced a
garbage number here.** `nm` over an archive emits a `Foo.o:` header line per
member; without `grep -vE '^$|:$'` the "external" set comes back as 160, of
which 28 are member names. That is lesson 6.2 again, in a new costume.

### 37.1 libc++ IS NOT THE BLOCKER — and getting that took a false negative

**libc++ symbols are spelled `__Z...`, with a DOUBLE underscore**, because the
C name is `_`-prefixed on top of an Itanium mangling that already starts `_Z`.
The first comparison here grepped `^_Z` against libc++'s exports and returned
**0 of 440** — a confident false negative that briefly looked like "dyld needs
440 C++ symbols and libc++ supplies none".

With the spelling corrected (`s/^_/__/`), `libc++.a` (43 members, 5,258
mangled exports) supplies **7** of dyld's C++ undefineds; subtracting what
`libdyld.a` defines itself leaves the C++ residual **empty**.

**So `-lc++` failing to resolve is real for the linker and irrelevant in
effect: there are no C++ symbols left for it to satisfy.** Building
`libc++.1.dylib` is still correct — the SDK ships `libc++.a` and
`libc++abi.a` and no dylib or `.tbd` at all, so it is a genuine independent
gap — but it is **not** what blocks the dyld link, and a round that builds it
and then finds the link still failing will be a confusing round for whoever
picks it up next.

### 37.2 What the 132 actually are

| subsystem | count |
|---|---|
| libc (`str`/`mem`/`write`/`open`/`stat`/…) | 33 |
| mach / kernel / vm (`vm_*`, `mach_*`, `task_*`) | 22 |
| pthread / dispatch / os (`pthread_*`, `dispatch_*`, `os_*`) | 13 |
| other | 64 |

Distinctive members of "other": `OSAtomicCompareAndSwap32` and the other
three `OSAtomic*`, `__NSConcreteGlobalBlock`, `__NSConcreteStackBlock`,
`__NSGetMachExecuteHeader`, `__Unwind_Resume`, `CRSetCrashLogMessage`.

**This is a libsystem closure, not a C++ runtime closure.** It is the same
structural statement as the empty-`__text` re-export hub, arrived at
independently and with a number attached: **dyld cannot link until the libsystem
pieces it names exist, and the largest single contributor is libc, which means
`libsystem_c`.** Phase 1 gates Phase 4. Two workstreams have been running as
though they were independent; they are not.

### 37.3 Two dead ends, recorded because both looked alarming

- **`gPathOverrides` and the `FileSystemPhysical` vtable appeared undefined.**
  They are dyld's own, emitted as type `S` (bss) in `PathOverrides.o`, which is
  in `SRCS` and in the archive. An intermediate count of "8 truly external C++"
  was an artefact of `ar x` extracting 27 objects while the member count
  implied 28.
- **`libdyld.a` is 4.2 MB and contains every object.** There is no
  missing-object problem hiding behind the link failure. The compile side is
  genuinely finished, which is why the frontier moved from COMPILE to LINK at
  all.

### 37.4 PREDICTION for the relink, not a result

After `libc++.1.dylib` is installed and dyld relinked: the "must link with
libSystem.dylib" error clears, the libc++ resolution error clears, and the
link then fails on undefined mach/libc/pthread symbols. **132 is the number to
check that prediction against.** If the failure names a different count, the
prediction is wrong and the difference is the finding.

## 33. libsystem_kernel COMPILES ENTIRELY; THE LINK IS REACHED

Authorised after sec. 28, on the port-block terms. The `mach/message.h`
private block was sourced, and the frontier moved through five TUs to the link
stage. Compile errors by round: 20 -> 7 -> 2 -> 1 -> 12 -> 3 -> 0.

    603 objects
    libsystem_kernel.dyl NOT produced -- the link is attempted and fails:

    duplicate symbol '_host_get_multiuser_config_flags' in:
        libkernel.a[110](host.o)            libkernel.a[139](mach_hostUser.c.o)
    duplicate symbol '_host_check_multiuser_mode' in:   (same pair)
    duplicate symbol '_host_create_mach_voucher' in:    (same pair)
    duplicate symbol '_host_get_atm_diagnostic_flag' in: (same pair)
    duplicate symbol '_mach_voucher_extract_attr_recipe' in:
        libkernel.a[142](mach_voucherUser.c.o) libkernel.a[130](mach_port.o)
    ld: 5 duplicate symbols

This is a different CLASS of problem from every blocker before it, and a much
easier one: not a missing declaration but a symbol defined twice. libsyscall's
hand-written host.c and mach_port.c carry compatibility shims that the
mig-generated mach_hostUser.c and mach_voucherUser.c also define.

### What was sourced, all verbatim with the source line named in the file

    mach/message.h    :605-624   mach_msgv_index_t, MACH_MSGV_MAX_COUNT,
                                 LIBSYSCALL_MSGV_AUX_MAX_SIZE, mach_msg_vector_t
    mach/message.h    :1042-1161 __options_decl(mach_msg_option64_t,...) + MACH64_*
    mach/message.h    :1018      MACH_SEND_FILTER_NONFATAL
    mach/message.h    :240-257   mach_msg_qos_t, MACH_MSG_QOS_*, prototypes
    mach/mach_types.h :181,:188  task_read_t, ipc_space_read_t
    mach/mach_types.h :178,:179,:204,:206,:207,:229  task_policy_set_t,
                                 task_policy_get_t, ipc_eventlink_t,
                                 task_id_token_t, kcdata_object_t, mach_eventlink_t
    mach/mach_types.h (via mach_debug/ipc_info.h)  exception_handler_info_t
    mach/vm_types.h   :106       vm_map_read_t, vm_map_inspect_t
    mach/vm_types.h   :156-159,:216  mach_vm_range_flavor_t,
                                 mach_vm_range_recipes_raw_t
    mach/port.h       :449-456   mach_service_port_info_data_t

Every struct layout is cross-checked against the `.defs` that actually drives
the MIG message on the wire, so none of them is a guess that merely compiles:
`mach_service_port_info_data_t` is char[255]+uint8_t at port.h:450-455 and
`struct[256] of char` at mach_types.defs:523; `mach_vm_range_flavor_t` is
`uint32_t` at vm_types.h:156 and `type ... = uint32_t` at mach_types.defs:584.
Where a `.defs` line and a header line could disagree, the `.defs` is the one
that decides the wire format, and it is the one quoted.

### Three mistakes of my own, recorded because each cost a build

1. **A `*/` inside a comment.** My provenance comment contained the literal
   text `MACH_SEND_*/MACH_RCV_*`. That `*/` TERMINATED the comment early, and
   everything after it became live code -- which opened a runaway
   `__options_decl(` invocation that swallowed every subsequent `#include` in
   the TU. The symptom pointed nowhere near the cause:
       host_info.h:67: error: embedding a #include directive within macro
                         arguments is not supported
       note: expansion of macro '__options_decl' requested here
   Same family as the `#`-in-a-C-header lesson: the text looks fine and the
   tool is the thing that has to be read.

2. **Sourced blocks placed AFTER the include guard.** Appending below
   `#endif /* _MACH_MESSAGE_H_ */` means every re-inclusion of the header
   re-processes the block, because the guard does not cover it. That produced
   a wall of `redefinition of enumerator 'MACH64_SEND_MSG'` -- 20 errors that
   looked like a preprocessor bug and were a placement bug. Every block sourced
   in this round is INSIDE its guard. A single-include `-fsyntax-only` test
   passed while the real build failed, which is the tell: if one include is
   clean and the build is not, the header is being included more than once.

3. **Copying a struct that already existed.** I re-copied `ipc_info_port_t`
   verbatim and got `redefinition of 'ipc_info_port'` -- the SDK's own
   mach_debug/ipc_info.h:116-119 already had it, identically, along with
   exception_handler_info_array_t. Only the `exception_handler_info_t` ALIAS was
   ever missing, and the fix is an `#include` of the real definition, not a
   second copy. Verbatim-copying something that already exists is a
   redefinition, not a fix.

---

## 38. THE INTERSECTION IS SMALL — and the C library's core is missing outright

### 38.1 dyld's 132 vs libsystem_c's provisions: measured, no build

    dyld truly-external (nm over libdyld.a)                        132
    libsystem_c defines (libBase + libc + libsystem_c + libPlatform
                         + libc_dyld, deduped)                    1498
    dyld's 132 SATISFIED by libsystem_c                             22
    dyld's 132 NOT provided by libsystem_c                         110
    dyld-ext ∩ libc-ext (both EXTERNAL sets)                       34
                                                       (98 dyld-only, 225 libc-only)

**The sets are not substantially the same.** The hypothesis that closing the
libc closure would close the dyld link is **falsified**: 110 of dyld's 132 have
no provider at all in the source-built libsystem_c. Phases 1 and 4 share a
gate only in the weak sense that both need a real libsystem; dyld needs
considerably more than libc provides today. **The plan does not get shorter.**

Note on basis: the plan's "133 unprovided" is a link-time figure; mine is
external-to-all-its-own-archives, a stricter and different question. The two
are not directly comparable and this entry does not claim they contradict.

### 38.2 The larger finding: the C library's core is not there

`libsystem_c` does not define **`_memcpy`, `_memset`, `_write`, `_open`,
`_malloc`** — in *any* of its archives, nor in the SDK's own
`libsystem_c.dylib`:

    libc.a (598 members, 1475 defines)   _memcpy:0  _write:0  _malloc:0
    libBase.a (89 members)                _memcpy:0  _write:0  _malloc:0
    libsystem_c.a                         _memcpy:0  _write:0  _malloc:0
    libc_dyld.a                           _memcpy:0  _write:0  _malloc:0
    SDK libsystem_c.dylib                 _memcpy:0

**CONTROL, because a row of zeros is the exact shape of the false negative
this project keeps producing.** The probe can see them: `libc.a` has **71**
`_str*`/`_mem*`/`_bcmp*` defines, and `_strcat`, `_strncat`, `_memset_s`,
`_strtod` are all reported present. So this is not a spelling or extraction
artefact.

**And it is not an inlining story.** `libsystem_c/string/` has **no
`memcpy.c` and no `memmove.c`**, and no `#define memcpy` / `__builtin_memcpy`
shim in its headers. The directory is *partly* populated — `stpcpy.c`,
`strcat.c`, `strncat.c`, `bcopy.c` are present — so the mem\*/basic-IO core is
missing while its neighbours are not. That pattern says **dropped or never
sourced from a SRCS list**, not "not implemented yet".

**Why it reframes the wait.** The recorded `libsystem_c` state is "133
unprovided". This says the gap is not one library away from linking: the C
library's own core is incomplete. **That is larger than Phase 1's
port-numbering blocker and it is not on anyone's list.** Open question, not
diagnosed: which Makefile is meant to compile `string/mem*.c` and the basic
IO, and were they dropped from a `SRCS` list or never sourced at all. Not
investigated — reading only, and no build.

### 38.3 Decision 5: `-lSystem` is NOT forced, and the reasoning is recorded

A `plan` measurement showed `-nodefaultlibs -lSystem` producing 4,168 B and the
full set 4,120 B — i.e. **it links**. That was briefly read as "so add
`-lSystem`". It is not sufficient evidence, and the reason is worth keeping:

> The link succeeded against a **4,120-byte dylib exporting zero symbols**. A
> synthetic TU needing almost nothing will link against an empty shell. The
> link succeeding is evidence **ld64 stopped complaining**, not evidence the
> link is correct. A `libdyld.dylib` bound to that would install cleanly,
> appear in the SDK, resolve nothing at runtime, and be **indistinguishable
> from success** — exactly how the 6,856-byte `libobjc.A` stub got staged.

**The accurate statement of the blocker is narrower than the word:** the
correct libSystem does not exist yet, and the ~26 dylibs that would compose it
do not. That is what is recorded, in place of "circularity".

**Two rules from this, both about words hardening:**

> **"Circularity must not harden into "impossible", and "cheap" must not
> harden into "solved".** A measured fact is always narrower than the word
> that replaces it, and in a shared document the word is what survives.

1. An explicit `-lSystem` on a bootstrap linker **is** a design question — and
   the answer here is *yes*, because the bootstrap linker is being supplied by
   the system it names, and every other component dylib already depends on
   `libSystem.B`. But that is an argument for the design **once the library
   exists**; it is not a licence to link against a shell now.
2. The wrapper's `-lSystem` strip is a **historical fix for a real cycle** and
   **stays** for the components that need it. dyld is not that case. Recorded
   so nobody "simplifies" by removing the strip globally.

### The five duplicates: analysed, and the obvious fix is a DEAD END

Worth writing down because the obvious hypothesis is wrong and would cost a
round to discover.

    MACH_DEFS != echo ${XNU}/osfmk/mach/*.defs

feeds mig the KERNEL defs. There is also a userspace set at
`${XNU}/libsyscall/mach/*.defs`, and the obvious conclusion is "use that one
instead -- it will not declare the routines libsyscall implements by hand".
**That does not work, and the reason is one line:**

    Kernel/xnu/libsyscall/mach/mach_host.defs   30 lines, and its entire body is
        #include <mach/mach_host.defs>
        import <mach/mach_init.h>;  /* for host_page_size() */

It `#include`s the kernel's defs, so the four routines arrive transitively and
mig generates the same stubs either way. A direct grep for
`routine host_get_atm_diagnostic_flag` in the libsyscall copy returns 0, which
is exactly why the hypothesis looks right and is not: the routines are not
absent from that file, they are pulled in by the include. Same shape as the
sec. 10 `suid_cred_path_t` lesson -- grep for the bare NAME, and remember an
`#include` is an edge.

The duplicates are also NOT trivially removable. The two definitions are
genuinely different implementations of the same entry point:

  host.c:37,45,58   host_get_atm_diagnostic_flag, host_get_multiuser_config_
                    flags, host_check_multiuser_mode -- these answer from the
                    COMM PAGE, i.e. no kernel round trip at all
  host.c:84         host_create_mach_voucher -- a trap wrapper with a
                    MACH_SEND_INVALID_DEST kernelrpc fallback
  mach_port.c:736   mach_voucher_extract_attr_recipe -- trap first, kernelrpc
                    on MACH_SEND_INVALID_DEST
  mach_hostUser.c   all five, as plain MIG client stubs

So this is a real decision, not a deletion: either libsystem_kernel keeps its
hand-written fast paths and the mig run must not generate those five, or it
takes the plain MIG stubs and loses the comm-page reads and the pre-10.15
fallback. Both are defensible; they are not equivalent, and which is right is a
call about what this OS is, not a mechanical fix. NOT ATTEMPTED HERE -- the
tree was released, and guessing at it unasked is the thing this section exists
to prevent.

### Follow-up: the kernel DOES implement all five, so this is a performance
### decision rather than a correctness one

Checked, because it is the difference between "pick one" and "you must pick
one":

    host_get_atm_diagnostic_flag   declared in osfmk/mach/mach_host.defs
    host_check_multiuser_mode     declared in osfmk/mach/mach_host.defs
    host_get_multiuser_config_flags  declared in osfmk/mach/mach_host.defs
    host_create_mach_voucher      osfmk/mach/mach_host.defs, AND really
                                   implemented in osfmk/ipc/ipc_voucher.c
                                   and osfmk/kern/syscall_sw.c
    mach_voucher_extract_attr_recipe  implemented via ipc_voucher.c

So the MIG stubs are CORRECT. Choosing them costs a kernel round trip on calls
that the hand-written versions answer from the comm page; it does not produce
a wrong answer or a dead trap. That settles the correctness half of the
question and leaves only the performance half.

It also suggests where the mechanical resolution lives, without committing to
it: the collision only happens because the link does
`-Wl,-force_load,libkernel.a`, which pulls BOTH `host.o` (from
libsystem_kernel.a) and `mach_hostUser.c.o` (from libmach.a) unconditionally.
ld64 only reports a duplicate when both strong definitions are actually being
linked. Narrowing what is force-loaded, or excluding those five routines from
the mig run, would each remove the collision without touching any source.

NOT DONE, deliberately: choosing which of the two implementations this OS
should ship is a product decision about libsystem_kernel's behaviour, and it
belongs to whoever owns that. Everything else in the component now compiles,
so this is the last thing between 603 objects and a dylib.

### The five duplicates, measured to a forced choice (not a narrowing)

Applied the dyld workstream's instrument -- `nm -gU` on the archive the link
binds -- to libsystem_kernel, because it is the same question asked of a
different link. Result:

    defined (T/D/B/S) symbols in libkernel.a   1494
    undefined (U)  symbols in libkernel.a      1431
    all five duplicates:  defined=2  undefined=0

Defined twice, referenced ZERO times inside the archive. That is the same shape
dyld found on its four, and it CORRECTS what I told them: I said "narrowing
what is force-loaded is obviously correct on your side, because the five
routines are implemented in the kernel so the MIG stubs are the ones to drop."
Narrowing does not work here. These are EXPORTED entry points with no internal
referrer, so unreferenced does not mean unused -- something outside links
against them, and exactly one implementation may be exported.

Who actually consumes them, searched across the userland sources:

    host_get_multiuser_config_flags   Libraries/Libsystem/libsystem_info/
                                      lookup.subproj/muser_module.c
    host_create_mach_voucher         Libraries/Libsystem/libdispatch/src/voucher.c
    mach_voucher_extract_attr_recipe Libraries/Libsystem/libdispatch/src/voucher.c
    host_get_atm_diagnostic_flag     no external C consumer in this tree
    host_check_multiuser_mode        no external C consumer in this tree

So libdispatch genuinely calls two of them. The symbols must exist exactly
once, and the two implementations are NOT equivalent:

  * host.c / mach_port.c versions: trap first, then fall back to
    _kernelrpc_* on MACH_SEND_INVALID_DEST; the atm/multiuser ones answer from
    the COMM PAGE with no trap at all.
  * mach_*User.c versions: plain MIG client stubs, no fallback, and a round
    trip for the comm-page cases.

That makes the choice forced, and it is a real behavioural decision: keep the
hand-written ones and the fallback plus the comm-page reads, or take the stubs
and lose both. The fallback is the substantive part -- it is what lets a call
survive a kernel that returns MACH_SEND_INVALID_DEST, and libdispatch's
voucher.c is a live consumer of exactly those two routines.

NOT DECIDED HERE. This is a statement about what libsystem_kernel IS, and it
belongs to whoever owns that. It is recorded so the next person does not spend
a round discovering that force_load narrowing does not apply.

---

## 39. THE DUPLICATE-SYMBOL FRONTIER, TRACED TO ITS ROOT — no build required

The frontier is `ld` reporting duplicates between `libc++.a`'s four pulled
members and `glue.c`'s four deliberate handlers. **`glue.c` is correct and
wins** — see 39.3. What follows is *why the four members get pulled at all*,
traced with `nm` on artifacts that already existed.

### 39.1 What each member actually supplies to dyld

    member              defines   supplies to dyld            itself REQUIRES
    exception.o            76      __ZSt9terminatev            the 2 __cxxabiv1
                                                              typeinfo vtables
    new.o                  23      __ZdlPv __Znwm              bad_alloc, new_handler,
                                                              __ZSt15get_new_handlerv,
                                                              __ZSt9terminatev
    typeinfo.o               6      NOTHING                     the same 2 vtables
    verbose_abort.o          1      __libcpp_verbose_abort     CRSetCrashLogMessage

**This answers the peer's question directly.** `typeinfo.o` is dragged in by
`exception.o`, not by dyld: `exception.o` needs the two `__cxxabiv1` typeinfo
vtables and `typeinfo.o` is the member that defines them, while contributing
**zero** symbols to dyld's own undefined set. So three of the four named
members are **transitive residue of one root demand**, not four independent
needs.

### 39.2 The root: 7 TUs that lack `-fno-exceptions`

    demanding __ZSt9terminatev        NOT demanding it
    APIs.o                            Loading.o        MachOFile.o
    APIs_macOS.o                      MachOLoaded.o    MachOAnalyzer.o
    AllImages.o                       Diagnostics.o    PathOverrides.o
    dyldAPIsInLibSystem.o             Closure.o        ClosureWriter.o
    dyldLock.o                        ClosureBuilder.o ClosureFileSystemPhysical.o
    dyld_process_info.o               Tracing.o
    dyld_process_info_notify.o

That is **exactly** the 7 with no `CFLAGS.<tu>.o = -fno-exceptions` entry,
against the 11 that have one. **Perfect correlation, no exceptions in either
direction** — verified by checking all 11 `-fno-exceptions` TUs individually
and finding none of them demands `std::terminate`.

**MEASURED, on the real emitted argv for `dyld3/APIs.cpp`** (captured from
`RAVYN_CC_TRACE`, replayed verbatim, output redirected to `/tmp` so nothing is
written into the build tree):

    baseline, real argv                    rc=0   __ZSt9terminatev demanded: 1
    same argv + -fno-exceptions            rc=0   __ZSt9terminatev demanded: 0
                                                  libc++ C++ undefineds left: 0

**With `-fno-exceptions`, `APIs.o` requires nothing from libc++ at all** — zero
C++ undefineds remaining, and all of them otherwise resolved within
`libdyld.a`. The classification is therefore **EH, not `operator new`**: the
demand is not a mundane allocation but the terminate path, exactly the branch
of the peer's dichotomy that the `-fno-exceptions` evidence selects.

**On the arithmetic that decides the design:** if ld names four pulled members
and there are four duplicate symbols, then `new.o`, `typeinfo.o` and
`verbose_abort.o` are pulled *without colliding* — and indeed `typeinfo.o`
supplies nothing to dyld at all. It is in the drag chain, not in the
collision. That is why removing the root demand is the fix and deleting
members is not.

### 39.3 `glue.c` is the correct design — do not touch it

`glue.c:145-190` defines `_ZSt9terminatev`, `_ZSt10unexpectedv`,
`__cxxabiv1::__terminate`, `__cxxabiv1::__unexpected`, `std::__terminate`,
`std::__unexpected`, and the `get_*_handler` trio, each routing to
`_ZN4dyld4haltEPKc`. The rationale in the source is that a bootstrap linker
must not reach libc++'s exception runtime, which would abort through a runtime
that does not exist yet when dyld runs. **That is right and it wins.**
Deleting or commenting out these handlers to quiet the linker inverts the
finding.

### 39.4 WHY THIS IS NOT FIXED YET — a constraint, not temperament

Both candidate fixes have wide blast radius and **opposite** failure modes,
and **neither is visible to any gate this project has**:

| fix | how it fails | how bad |
|---|---|---|
| selective libc++ linking done wrong | `libdyld` **links and misbehaves at runtime on an error path** | the §5.5 class: looks like success, is not |
| supplying unwind symbols done wrong | `libdyld` **links and crashes before `main`** | worse, and much harder to attribute |

A green link is therefore **not** evidence of correctness here, which is the
same trap as the 6,856-byte `libobjc.A` stub and as `-lSystem` against a
4,120-byte dylib exporting zero symbols. **The check that catches it is the
one in Commands: `nm -gU` the library that was bound and count its exports.**

**Also still open, and NOT closed by a green link:** `ld: must link with
libSystem.dylib` is **uncovered, not solved** (see 38.3), and the
`libSystem` composition question remains behind everything here.

**The obvious next measurement**, which is cheap and is *not* a fix: add
`-fno-exceptions` to the 7 `CFLAGS.<tu>.o` lines, rebuild, and read the
duplicate list. If it shrinks to nothing, the design question is answered by
the evidence rather than by argument. That is a build, so it waits for the
tree.

### Two more of MY OWN false negatives, found by the force_load A/B

Running dyld's A/B (drop `-force_load` on libkernel.a, one flag varied) did not
reach the link, because the compile stage is not actually clean -- it is clean
only where stale .o files are masking it. Deleting nothing and changing one link
flag invalidated enough objects to expose two latent errors, both of which my
own census had already declared absent:

    mig_hdr/include/mach/mach_eventlink.h:84: error: unknown type name
        'eventlink_port_pair_t'
    mig_hdr/include/mach/processor_set.h:216: error: unknown type name
        'mach_task_flavor_t'

1. **`eventlink_port_pair_t` — I explicitly wrote it off.** The sec. 33 block
   records: "the :205 `eventlink_port_pair_t[2]` line is an array declarator, not
   a typedef, and is not needed by libsyscall." Both halves were wrong. It IS a
   typedef (of an array), and it IS needed, by the mig-generated
   mach_eventlink.h:84 and mach_eventlinkUser.c:185. My census regex matched
   typedefs whose type was a bare identifier, so an array typedef was invisible
   to it -- and I then wrote a confident sentence about the gap rather than
   leaving it unmeasured. This is sec. 17's lesson recurring inside my own work:
   a method that cannot see a form of the declaration cannot certify the form is
   absent.

2. **`mach_task_flavor_t`** is a genuine gap that was already NAMED in the tree:
   isysroot-cc's `overlay_for` records this exact error at its line 204 as the
   reason it strips mach/ from the libsystem_kernel mig_hdr overlay. So the
   diagnosis already existed and the fix was never applied, because the
   stripping hides the header that reports it while the raw
   `-I.../mig_hdr/include/mach` on CFLAGS is not stripped.

Both are now sourced verbatim (mach_types.h:205 and :362). Neither A/B result
is claimed: the experiment never reached the link, and the flag change has been
reverted. The Makefile is back to its `-force_load` form, byte-for-byte,
INCLUDING a pre-existing uncommitted working-tree change by another worker (the
"two sets of generated stubs" OBJROOT fix) which I left untouched and did not
stage.

### The honest state of the compile stage

"Every TU compiles" was true of the object set on disk and is NOT true of a
clean build. 603 objects is a real number and the link really is reached, but
the compile stage has at least two masked failures, so the correct statement is
that the link is reached WITH a stale object set, not that the component builds
from clean. A force_load A/B is a cheaper instrument for that than another
incremental build, and it is what found these.

## 29. ATTRIBUTION: commit 0134a7db04 also carries libsystem_kernel findings

Recorded because the commit message does not say so and the log is therefore
misleading, at the request of `critical-path`, whose work it contains.

Commit `0134a7db04` ("docs: libdyld.dylib links, and carries 3 symbols nothing
provides") is the dyld workstream's, and it ALSO carries `critical-path`'s
libsystem_kernel material, which landed in the shared index before either
commit completed. Nothing of theirs is lost and all of it is correct — but a
reader of the log alone would not learn any of the following:

- a `-force_load` A/B was run on `libsystem_kernel`
- two of their own census false negatives were found and corrected
- the compile stage is **stale-object-clean, not clean**: the A/B invalidated
  enough objects to expose two latent compile errors that stale `.o` files were
  masking, and their earlier "every TU compiles" was true of the object set on
  disk and not true of a clean build

The notes text itself is self-describing and names all three, so a reader who
opens the file gets the truth even though the commit message does not say it.
That is the mitigation, and it is a mitigation rather than a fix: the right
repair is a commit message that mentions both, and amending another worker's
commit with peers active is worse than an imperfect message.

**The generalisable part, and it is the third time today.** A path-scoped
`git add` scopes the PATH, not the CONTENT. `git commit` commits the INDEX,
not the paths you just added to it. All three of us have now been bitten by
this independently: the dyld worker sweeping plan's BOOT-PLAN edits, plan
sweeping critical-path's staged files, and critical-path's own commit left with
nothing to commit. **`git diff --cached` immediately before `git commit` is the
whole defence and it costs one command.**

---

## 40. MY OWN TRACE WAS RIGHT ABOUT THE MECHANISM AND WRONG ABOUT THE FIX

`libdyld.dylib` **links and installs** (994,056 B in the generated SDK, 203
exports, 10 `upward` reexports). The real cause was `-lc++`, removed in
`5106776a69`. This entry is the correction of my own work, recorded because the
error is more useful than the fix.

### 40.1 What I got right, and it was not trivial

The chain is exactly as traced in sec. 39, and it is real:

    7 TUs without -fno-exceptions -> undefined __ZSt9terminatev
      -> libc++ exception.o is the member defining it, so ld pulls it
      -> exception.o requires the 2 __cxxabiv1 typeinfo vtables
      -> typeinfo.o is dragged in, supplying dyld nothing directly
    DRAG chain, not COLLISION chain.

Measured on the real emitted argv, replayed verbatim:
`__ZSt9terminatev` demanded 1 -> 0 with `-fno-exceptions`, and all 11 TUs
already carrying the flag were checked individually and demand nothing.
Perfect correlation in both directions.

### 40.2 Where the inference broke — and it is the project's own lesson

**I never asked whether the demand was satisfied.** `glue.o` is *inside*
`libdyld.a`, and it **defines all four** colliding symbols:

    __ZSt9terminatev  __ZSt10unexpectedv  __ZSt13get_terminatev
    __ZSt14get_unexpectedv   (plus __cxxabiv1::__terminate/__unexpected)

So the 7 TUs' undefined `__ZSt9terminatev` is resolved **internally by the
archive**. It is never a link-time external. That is why the archive has **0
C++ undefined symbols** while 7 TUs demonstrably demand one — the two facts
are consistent, and I held them as if they contradicted.

**`-lc++` was the only reason `exception.o` was ever pulled.** It was
satisfying nothing. Removing the flag removed the pull; nothing about the
demand needed to change.

The error, stated generally:

> **A symbol being undefined in one object does not mean it is undefined at
> link time.** Before treating an undefined reference as a dependency, check
> whether the archive already *defines* it. `nm -u` on one member answers a
> different question from "does this link need this library".

This is the same shape as the errors this file keeps recording — a real
signal read as a conclusion it does not support. Sec. 6.2's four false
instruments, sec. 39's drag-vs-collision, and this are one family: **the
measurement was fine; the question it was used to answer was wrong.** A
mechanism that is perfectly established can still point at the wrong fix.

### 40.3 The `-fno-exceptions` change I made, and its status

I added `-fno-exceptions` to the 7 TUs (`CFLAGS.APIs.o` …) on the strength of
the trace, and **it is not required for the link**. It does not fix anything:
the link succeeds without it, because `glue.c` already provides the handlers
and libc++ is no longer linked. It changes codegen for 7 TUs on no evidence
that the change is wanted.

**Left in place, deliberately, and flagged rather than reverted**, because
reverting would be an edit to a shared Makefile while `kernel-link` is
building, and that is the straddle that voided a run earlier today. It should
be reverted on its own: it is a behaviour change to a component that links,
made on a premise now known to be wrong, and the tidy end state is a Makefile
carrying only flags that are load-bearing. **This is a real loose end, not a
finished change.**

### 40.4 Also false-negative-shaped, for the record

`nm -g glue.o | grep _ZSt9terminatev` returned **nothing**, and for a moment
that looked like "glue.c does not define it either" — which would have made
the story worse and the fix more attractive. It is a C file; the symbols are
`T` (text) but the `nm -g` invocation was run through a filter that dropped
them. Plain `nm` shows all twelve. **A probe that finds nothing where the
thing plainly exists is an instrument bug, and the cheapest way to tell is to
look at the file.**

## 30. OPEN: libdyld.dylib links and installs, but carries 3 symbols nothing provides

**This is a gate finding, not a link finding.** The link succeeds. Nothing in
the build reports this, and the build is not wrong about anything it was asked.

    $SDK/usr/lib/system/libdyld.dylib   994,056 B, 203 exported symbols,
                                          10 `upward` reexport dependencies
    undefined symbols                    128
    of which NO PROVIDER anywhere in `otool -L`:
        _Znwm                                          (operator new)
        _ZdlPv                                         (operator delete)
        _ZNSt3__122__libcpp_verbose_abortEPKcz

plan found this; I confirmed the mechanism in the source. `src/glue.c`:

    369:  extern void* _Znwm(unsigned long size);        <- DECLARATION
    370:  void* _ZnwmSt11align_val_t(...) { return _Znwm(size); }    <- CALL
    376:  extern void _ZdlPv(void* ptr);                 <- DECLARATION
    377:  void _ZdlPvSt11align_val_t(...) { _ZdlPv(ptr); }          <- CALL

glue.c declares the UNALIGNED pair, calls it from the aligned forms it DOES
define, and supplies neither. With `-lc++` gone, nothing provides them.
**A declaration is not a definition, and the intent was written where the
linker needed code.**

### The two readings, and neither is settled

  - **glue.c is meant to be self-contained** and should DEFINE the unaligned
    pair, wrapping malloc/free. Supported by the fact that it already defines
    the ALIGNED forms the same way.
  - **glue.c is meant to be backed by libc++** and we need a real libc++ dylib
    built first. Supported by the extern pair and the `__libcpp_allocate`
    comments saying the aligned variants must exist because libc++ may call the
    unaligned ones.

If the second reading is right, then "what provides libc++" and "what provides
libSystem" (Decision 5) are the SAME question and are filed together to be
decided together.

**NOT ACTIONED.** Defining `operator new`/`operator delete` in the bootstrap
linker has runtime blast radius over every allocation dyld ever makes. That is
a recorded decision, not a diff to land at the end of a long session.

### CORRECTION: my "libc++ supplies ZERO" was false

Measured properly (`ar -x` then `nm -g` on the extracted member):

    libc++.a new.o          defines _Znwm, _ZdlPv
    libc++.a verbose_abort.o defines __libcpp_verbose_abort

The intersection is 3, not 0. My original probe read members with
`nm -gU libc++.a[member]`, which returns **empty for every member** — so it
reported "no overlap" when it had reported nothing. A false negative from a
probe pointed at the wrong syntax. The REMOVAL of `-lc++` is still correct
(dyld uses libc++ headers and supplies its own runtime); the evidence I gave
for it was overstated, and `plan` is the one who caught it.

### TWO MEASUREMENTS THAT DISAGREE, UNRESOLVED

1. Clean build (`ps` verified empty, 28 objects, rc=1 on the *tool* subdir):
   the installed artifact **has** all three symbols undefined.
2. A manual re-link from the same `libdyld.a` with the same flags, minutes
   later: rc=0 and the dylib has **none** of the three.

Also unexplained: the build reports **28** Mach-O objects for a `SRCS` list of
**27** entries, and `ar -t` shows 27 objects plus `__.SYMDEF` (an archive
symbol index, not an object). I have not accounted for the 28th.

Both discrepancies are recorded rather than resolved, because resolving them by
assertion is the failure this whole section is about.

---

## 41. libsystem_kernel LINKS AND INSTALLS — the closure, measured on the artifact

Clean build, `tools/bootlab/build-libraries.sh Libsystem/libsystem_kernel`, with
every `.o`, `.a`, `obj/` and `sys/` deleted first. `ps` verified empty of
`bmake` / `build-libraries` / `isysroot-cc` / `llvm-libtool` immediately before
and after; the only other process was the editor's `clangd` indexer.

    build exited rc=0, 137 s
    603 objects (Mach-O only, `.depend.*` excluded)
    0 compile errors, 1693 warnings
    libsystem_kernel.dylib            617,080 B
    installed into the SDK            617,080 B (was an 8,064 B placeholder)

**603 is the same number the record has carried all along, and it is now a
CLEAN-BUILD number.** The old 603 was a count of the object set on disk; the two
agreeing is luck, not confirmation.

### 41.1 The gate that matters, because the link cannot fail

`BSD/share/mk/bsd.sys.mk:541` appends, for every component on Darwin:

    LDFLAGS += -lSystem -Wl,-undefined,dynamic_lookup

so **no ravynOS dylib link can fail on an unresolved symbol.** A green link
means ld64 stopped complaining, nothing more. The only meaningful gate is the
installed artifact, and that is what this section reports.

    $SDK/usr/lib/system/libsystem_kernel.dylib
      otool -L   libsystem_c.dylib, libdyld.dylib (+ self)
      exports (nm -gj, deduped)            1,483
      undefined (nm -u)                       12
      unprovided across an 18-dylib closure    0

The 12 undefined are `_mach_msg2`, `_mach_msg2_trap`, the five
`_mach_msg_priority_*_inline` helpers and the `_system_version_compat_*` trio;
all 12 are defined by `libsystem_c.dylib`. The 8,064-byte placeholder is gone.

### 41.2 THE CLOSURE — the number that had never been measured

Method, stated because a number without its method is what produced the
126-symbol attribution this section is replacing. **This is `nm`, not a link**,
and sec. 38.1 already records that the two are not comparable:

    A  = nm -u on the target dylib, symbol lines only, deduped
    P  = nm -gj (defined, external) over EVERY dylib in the transitive
         `otool -L` closure, union, deduped
    A - P = unprovided

**Resolution rule, and it is the whole correctness of the measurement:** an
install name `/usr/lib/system/X` resolves to `$SDK/usr/lib/system/X` and
**never** to the host. macOS has a real `/usr/lib/system/libsystem_kernel.dylib`,
so a resolver that takes the install name literally mixes the host's libraries
into a ravynOS closure. The first version of this script did exactly that,
resolved a 2-library "closure", and reported **0 unprovided** off a host
library. The fixed script asserts every closure path is inside the ravynOS SDK
and reports 18.

    libsystem_c.dylib  A  (undefined)                272
    libsystem_c.dylib  A satisfied by the closure   272
    libsystem_c.dylib  A NOT provided                 0

    libsystem_kernel exports                          1,483
    of libsystem_c's 272, satisfied by libsystem_kernel  143

**The residual moves: 133 unprovided -> 0.** The record's figure was
UNVERIFIED because this library had never linked; it is now measured, and the
direction of the old attribution is confirmed with a different number attached
(126 attributed, 143 actually contributed). The other 129 of the 272 are
covered by the rest of the closure — `libsystem_platform`, `libsystem_pthread`,
`libdispatch` and the rest — which is why the count that moved is not the count
that was predicted.

**The confirmed `libsystem_c` gap is still a gap, and it is not this
library's.** sec. 38.2 recorded that `libsystem_c` defines neither `_write` nor
`_open` in any archive. The residual being 0 says nothing about that: those two
names are simply not among the 272 `libsystem_c` itself leaves undefined. The
basic-IO core gap is untouched by this round and still open.

### 41.3 A REAL FINDING THE GATE SURFACED — **RETRACTED, SEE SEC. 46**

> **This subsection is WRONG and is retained only so the retraction is
> findable.** `libobjc.dylib` is NOT missing from the generated SDK. It is
> present, real, and defines 2,147 symbols. The "UNRESOLVED" lines below were a
> defect in my resolver, not a fact about the tree. Section 46 has the
> measurement and the corrected figures. Do not quote 41.3.

What I originally wrote here, kept verbatim for the record:

The transitive closure of BOTH `libsystem_kernel` and `libsystem_c` is missing
a library:

    UNRESOLVED: /usr/lib/system/libobjc.dylib   (from libxpc.dylib)
    UNRESOLVED: /usr/lib/system/libobjc.dylib   (from libdispatch.dylib)

`libobjc` is named by two libraries in the closure and is not in the generated
SDK. It does not appear in either 272-set or 12-set, so it does not affect
either number above — but it is a load-time dependency with no provider, which
is the same class as sec. 30's three unprovided `libdyld` symbols, and it is
recorded here rather than left in the script's scratch directory.

## 42. THE CLEAN-BUILD DEFECT: sourced blocks sat BELOW their include guard

The clean build's first error, and the reason the incremental builds had been
green:

    <SDK>/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/mach/coalition.h:199:8:
        error: redefinition of 'coalinfo_debuginfo'

`struct coalinfo_debuginfo` had been sourced from
`Kernel/xnu/osfmk/mach/coalition.h:171` into four SDK copies, and the sourced
block was placed **after** `#endif /* _MACH_COALITION_H_ */`. The guard does not
cover it, so every re-inclusion re-processes the struct. `posix_spawn.c`
includes `<mach/coalition.h>` twice — once directly at :42 and once via
`spawn_internal.h:50` — and dies.

This is **sec. 33's mistake #2 recurring**, in the file sec. 16 wrote. A block
below the guard is invisible to a single-include `-fsyntax-only` test, which is
the same tell sec. 33 recorded.

**It was not one file.** Sweeping both SDK mach trees for content below the
last `#endif` found **9 headers per tree, 18 files**:

    coalition.h  host_special_ports.h  mach_param.h  machine.h  message.h
    port.h  syscall_sw.h  task_special_ports.h  thread_special_ports.h

Seven of the nine carried only `#define`s, so they were latent rather than
fatal; `coalition.h` carried a struct and was the one that stopped the build.
All 18 are now fixed. Every one is proven to be a **pure reorder**: the
sorted, non-blank line multiset is byte-identical to `HEAD` for all 18
(`mach_types.h` is excluded from that check because it also carries an
unrelated in-flight edit).

Proven by A/B on the **real** compile command, replayed verbatim out of the
build log with only `-c`/`-o` swapped for `-fsyntax-only`:

    control   (block BELOW guard, struct at 199, guard at 180)   rc=1
              coalition.h:199:8: error: redefinition of 'coalinfo_debuginfo'
    treatment (block INSIDE guard, struct at 198, guard at 207)  rc=0

Both arms print the struct's line against the guard's before compiling, so a
reconstruction that failed to reproduce the old layout would show itself. The
fix is in the **source** SDK, which `build-libraries.sh`'s `sync_mach` copies
into the generated tree on every run (`cmp -s || cp -f`), so it survives SDK
regeneration — the sec. 8 / sec. 13 durability method.

### The two errors the record predicted, and where they actually were

Neither reproduced. Both are fixed in the SDK trees and neither is reachable
any more:

    mig_hdr/include/mach/mach_eventlink.h:84:  unknown type name 'eventlink_port_pair_t'
    mig_hdr/include/mach/processor_set.h:216:  unknown type name 'mach_task_flavor_t'

`eventlink_port_pair_t` is present at `usr/include/mach/mach_types.h:373` and
in the `System.framework` tree; `mach_task_flavor_t` alongside it. The clean
build compiled `mach_eventlinkUser.c` and `processor_setUser.c` with no error.
**A third latent error was the one that actually bit**, and it is sec. 42.

## 43. THE FIVE DUPLICATES: the mechanism is the .defs files' own conditional

Not a `force_load` narrowing, not a deletion, and not invented here. Measured
with the real `mig`, same flags, only `LIBSYSCALL_INTERFACE` varying, generated
into a scratch directory, with a positive control (27 stubs visible at `=1`, so
the probe can see stubs at all):

    mach_host.defs    27 stubs at =1  ->  24 stubs at =0
      lost:    host_get_atm_diagnostic_flag, host_get_multiuser_config_flags,
               host_check_multiuser_mode
      gained:  _kernelrpc_host_create_mach_voucher
    mach_voucher.defs  5 stubs       ->   5 stubs
      lost:    mach_voucher_extract_attr_recipe
      gained:  _kernelrpc_mach_voucher_extract_attr_recipe

That is `osfmk/mach/mach_host.defs:319-357` (`#if !KERNEL && LIBSYSCALL_INTERFACE
... #else skip;` around the three comm-page readers) and
`mach_host.defs:283-289` + `mach_voucher.defs:45-51` (either the public routine
or its `_kernelrpc_` twin). **The `.defs` files are written for exactly the two
implementations this library ships**: the comm-page readers are `skip`ped
because `mach/host.c:37,45,58` answer from the comm page, and the other two
are generated as `_kernelrpc_` stubs because the hand-written wrappers fall
back to them. The per-file override is deliberate — a global flip renames 43
`mach_port.defs` stubs and changes the on-the-wire type of four of them.

Verified in the installed artifact: each of the five is defined **exactly
once**, both `_kernelrpc_` fallbacks are exported, 84 `_kernelrpc_*` symbols are
exported and **0** are undefined.

### 43.1 What the OBJROOT fix was actually fixing, and the 187 it created

`mig` names its `*User.c` after the **`.defs` file**, not after `-header`. The
public pass and the internal pass therefore wrote the same five filenames into
the same directory, and the second overwrote the first. Giving the internal
pass its own OBJROOT is necessary, but archiving *both* sets wholesale is not:
measured on the real link, that produced

    187 duplicate symbols
      62  taskUser.c.o      <-> taskUser.c.o        (public vs internal)
      28  thread_actUser.c.o<-> thread_actUser.c.o  (public vs internal)
      21  vm_mapUser.c.o    <-> vm_mapUser.c.o      (public vs internal)
      15  mach_vmUser.c.o   <-> mach_vmUser.c.o     (public vs internal)
      42  mach_port.o       <-> mach_portUser.c.o   (hand-written vs public)
       8  mach_vm.o         <-> vm_mapUser.c.o      (hand-written vs public)
       8  mach_vm.o         <-> mach_vmUser.c.o     (hand-written vs public)
       3  thread_act.o      <-> thread_actUser.c.o  (hand-written vs public)

Both classes come from the same fact: **those five interfaces are the ones
libsyscall implements by hand** (`mach_port.c`, `mach_vm.c`, `thread_act.c`,
port_descriptions.c), so their public stubs are a collision rather than a
duplicate. The public `.c` for the five `MIGS_INTERNAL` defs is deleted before
the internal pass runs, which is what the section header above that pass already
said ("special headers used just for building Libsyscall"). Before the OBJROOT
split the right answer was reached by directory order and the internal pass
winning — correct by accident.

Confirmed on disk: `obj/` holds 13 public `*User.c`, `obj/internal/` holds 5,
and none of `mach_port mach_vm task thread_act vm_map` appears in `obj/`.

## 44. `-Wl,-undefined,dynamic_lookup` MAKES EVERY LINK IN THIS TREE GREEN

`BSD/share/mk/bsd.sys.mk:541`, for `.MAKE.OS == Darwin`:

    LDFLAGS += -lSystem -Wl,-undefined,dynamic_lookup

Every component. So `rc=0` from these builds is not evidence that anything
resolved — it is the default. `libdyld.dylib` linked cleanly while carrying
three symbols nothing provides (sec. 30), and this component linked cleanly
while carrying twelve that `libsystem_c` happened to supply.

**The check that catches it costs one command and no build:** `nm -u` the
INSTALLED dylib, walk `otool -L` transitively, subtract. Not the archive, not
the build directory, and not the link's exit code.

### One more false negative of my own, recorded because it nearly shipped

My first pre-clean probe asked `nm` for `_kernelrpc_host_create_mach_voucher`
and reported `defined=0 undefined=0`, i.e. "nobody needs it and nobody has it".
The C name is `_kernelrpc_host_create_mach_voucher`; the Mach-O symbol is
`__kernelrpc_host_create_mach_voucher` — a leading underscore on top of the
name's own. It is defined, and it is the fallback the hand-written
`host_create_mach_voucher` calls. Same shape as sec. 37.1's `__Z` and
sec. 40.4's filtered `nm -g`: **the probe found nothing where the thing
plainly existed.** A zero in a symbol-count probe is a question about the
spelling until proven otherwise.

---

## 45. CORRECTION OF SECTION 41: MY CLOSURE NUMBER WAS WRONG, AND THE ERROR MADE THE TREE LOOK BETTER

Section 41.1 and 41.2 report `unprovided = 0`. **That is false.** The real
figures are `libsystem_kernel` 12 and `libsystem_c` 5. The method was wrong, the
error was in the direction of a better-looking tree, and it passed a build, a
gate, an independent peer reproduction and a commit message before it was
caught. Recorded in full because the failure mode is the point.

### 45.1 The bug: `nm -g` prints undefined symbols too

    P = nm -gj  <-- what I used.  -g means "external", which INCLUDES undefined.

So `P` contained every closure library's own undefined set, and `A - P`
cancelled itself toward empty no matter what the tree contained. It is a
self-fulfilling subtraction.

Measured on the installed `libsystem_kernel.dylib`, isolated:

    nm -gj  | sort -u | wc -l      1,483     <- what I reported as "exports"
    nm -gjU | sort -u | wc -l      1,470     <- defined externals only
    nm -u   | grep -cE '^_'           12
    difference                         13     <- exactly the undefined set

    _mach_msg2_internal  (defined)   in nm -gjU : 1
    _mach_msg2           (UNDEFINED) in nm -gjU : 0
    _mach_msg2           (UNDEFINED) in nm -gj  : 1

`nm -m` agrees independently: `(undefined) external _mach_msg2 (dynamically
looked up)`. The fix is the `-U` flag, not a downstream filter.

**The tell was in the output the whole time and I read past it:** the 12
symbols `nm -u` reported undefined were exactly the 12 symbols my provider set
claimed to provide, and I attributed that to `libsystem_c` defining them
"cleanly" rather than asking why the sets were identical. A provider set that
mirrors the undefined set is not a provider set.

### 45.2 CORRECTED NUMBERS, measured against pinned artifacts

Every dylib in the SDK (35 of them) copied to a private directory and hashed
first, then measured from the copies. Two earlier runs of the same script
disagreed — 12 unprovided, then 5 — because `libdyld.dylib` was reinstalled at
11:28 by another worker between them. **A closure number is only meaningful
against a named set of bytes**, so the pins and their md5s are part of the
method now.

    pinned: libsystem_kernel 617,080 B md5 71051fb8ddb7662cbf1d610e602d04cb
            libsystem_c    1,255,496 B md5 3babd71f22bc441ee5ff6c275081703a
            libdyld          993,360 B md5 8277f4af79604ea488aa2966aec785de
    provenance control: all 35 pinned files byte-identical to an SDK dylib (35/35)

    A = nm -u, symbol lines only, sorted -u
    P = nm -gjU over the transitive otool -L closure, union, sorted -u
    unprovided = A - P

**libsystem_kernel** (18-dylib closure)

    exports (nm -gjU, defined externals)   1,470   <- NOT 1,483
    undefined (nm -u)                        12
    unprovided                               12   <- NOT 0

    __system_version_compat_check_path_suffix
    __system_version_compat_open_shim
    _mach_msg_priority_encode_inline
    _mach_msg_priority_is_pthread_priority_inline
    _mach_msg_priority_overide_qos_inline
    _mach_msg_priority_qos_inline
    _mach_msg_priority_relpri_inline
    _mach_msg2
    _mach_msg2_trap
    _system_version_compat_check_path_suffix
    _system_version_compat_mode
    _system_version_compat_open_shim

Re-tested directly: **all 12 are defined in 0 of the SDK's 35 dylibs.** Seven
are mach/VM, five are the version-compat trio. So this component links and
installs, and it does not fully resolve.

**libsystem_c** (same 18-dylib closure)

    exports (nm -gjU)                      1,342
    undefined (nm -u)                        272
    satisfied                                267
    NOT provided (RESIDUAL)                    5

    ___os_log_encode
    _open$NOCANCEL
    _openat$NOCANCEL
    _os_log_pack_fill
    _os_log_pack_size

Re-tested directly: **all 5 are defined in 0 of the SDK's 35 dylibs.** Two
distinct causes, and they are both open questions, not defects I fixed:

  - `_open$NOCANCEL` / `_openat$NOCANCEL` — `libsystem_kernel` exports `_open`
    and `_openat` but **no `$NOCANCEL` variant of either**, while it does export
    `_accept$NOCANCEL`, `_close$NOCANCEL`, `_fcntl$NOCANCEL` and 20 more. The
    `cancelable/` directory in the component's `SRCS` carries eight
    `*-cancel.c` files, so the mechanism exists; these two specific entry points
    are simply not in it. **NOT DIAGNOSED — the absence is the reportable
    result.** Adding them is a `SRCS` question, not a flag.
  - `os_log_encode` / `os_log_pack_fill` / `os_log_pack_size` — these are
    `libsystem_trace`'s, and sec. 20 already established that
    `libsystem_trace` cannot be built without inventing two struct layouts and
    one kernel-private type. `libsystem_kernel` exports 0 `os_log` symbols. This
    residual is sec. 20 arriving downstream, and it is consistent with it.

### 45.3 What did NOT change, and what survives of the old number

**Unaffected**, because none of it came from `nm`: the 603-object clean
baseline, the `coalition.h` include-guard defect and its A/B, the five-duplicate
mechanism, and the fact that the component links and installs at 617,080 B.

**The 143 survives.** It came from a comm against `libsystem_kernel`'s exports,
and it is now derived under `-gjU` from the pinned copy: of `libsystem_c`'s 272
undefined, **143 are satisfied by `libsystem_kernel` alone**. It is unchanged
because `libsystem_kernel` is not a member of its own provider set in that
comparison, so the contamination could not reach it.

**The headline inverts.** `libsystem_c`'s residual is **5**, not 0. Against the
record's 133 that is still a large move, but "133 -> 0" was false. The honest
statement is 133 -> 5, with 143 of the 272 attributable to `libsystem_kernel`
against a predicted 126. The prediction's direction held and its number did not,
and that difference is the finding — but it is a much smaller difference than
"0" implied.

### 45.4 THE GENERAL LESSON, and it is the opposite of the one I nearly wrote

I nearly recorded this as "always resolve install names inside the SDK, never
against the host" — the host-contamination trap I hit first, which produces a
*better-looking* number too. Both are real; the thing to inherit is narrower and
worse:

> **A measurement error that makes the tree look BETTER is strictly more
> dangerous than one that makes it look worse, because only the second announces
> itself.** A contaminated resolver or a contaminated `nm` flag produces a
> number indistinguishable from a good one. It survives a build, a gate, and —
> measured here — an independent peer reproducing the same method and getting the
> same wrong answer, which was corroboration mistaken for verification.

Two controls would have caught it, and both were available for the price of one
command:

  1. **Ask why the two sets have the same members.** A provider set identical to
     the undefined set is a self-fulfilling subtraction, not a result.
  2. **Print the instrument's own arithmetic.** `nm -gj | wc -l` minus
     `nm -gjU | wc -l` should equal the undefined count. It was 13 vs 12 and I
     did not run it until after the commit.

The peer's independent check failed differently and more visibly — normalising
symbols by stripping a leading underscore gave 10 where the truth was 12, caught
by inspection. Same family, opposite direction, and the dangerous one is the one
that agrees with you.

## 46. libobjc IS IN THE SDK — section 41.3 was a defect in my resolver

Found by `libdyld-load`, who read my closure walk, checked it against the tree,
and reported that `libobjc.dylib` was "not merely unbuilt but MISSING from the
SDK". They were wrong about the tree and right about me: it is present, real,
and large. Section 41.3 is retracted above.

    SDK/usr/lib/libobjc.A.dylib    1,608,088 B
    SDK/usr/lib/libobjc.dylib      -> symlink to libobjc.A.dylib
    install name it declares:      /usr/lib/system/libobjc.dylib
    defined exports (nm -gjU):        2,147

**The cause is my resolver, and it is the same class as the host contamination
sec. 45 records.** I resolved install names against `$SDK/usr/lib/system` and
`$SDK/usr/lib` only. `libobjc` is installed at `usr/lib/`, so the walk reported
it UNRESOLVED, and I reported that as a property of the tree.

> **A path missing from your search list and a file missing from the disk look
> identical in the output.** The difference is invisible unless you go and look
> for the file. Sec. 45's lesson was that a bad *input* produces a
> better-looking number; this is worse, because a bad search produces a
> **finding** — a named, plausible, actionable-looking defect that is entirely
> an artifact of the probe. I dressed an instrument failure up as a tree
> problem.

The stage script at sec. 34's neighbourhood already says `libobjc.A.dylib` is
required and is staged into the boot image. The evidence was in this file the
whole time.

### 46.1 The corrected denominator: 45 SDK-wide, not 63

Measured across all 35 SDK dylibs at once, `nm -u` and `nm -gjU`, deduped:

    A  distinct undefined across the 35 SDK dylibs      944
    P  defined exports across the 35 SDK dylibs        8,200
    unprovided across the WHOLE SDK                      45

**The 22 objc names are not in the 45**, because `libobjc` supplies them. And
`libobjc` is a **multi-family** provider, not an objc-only one: of the 944
undefined names it satisfies **31**, and the 31 include `__Unwind_Resume`,
`___gxx_personality_v0`, `___objc_personality_v0`, both `__cxxabiv1` typeinfo
vtables and five `__Unwind_*` accessors. So a bucket table that books those
under "unwind" and "libc++abi" is double-counting against an objc row that was
never real.

Two rows in the 45 are **mine**, and neither is another component's export
surface:

  `_open$NOCANCEL`, `_openat$NOCANCEL` — `libsystem_kernel` exports `_open` and
  `_openat` but **no `$NOCANCEL` variant of either**, while exporting 22 other
  `$NOCANCEL` symbols (`_accept`, `_close`, `_fcntl`, `_connect`, `_fsync`,
  `_msgrcv`, `_msgsnd`, ...). The `cancelable/` mechanism is in `SRCS` with
  eight `*-cancel.c` files; these two entry points are not in it. A `SRCS`
  question, not a flag. **NOT DIAGNOSED** — the absence is the reportable
  result.

  `os_log_encode`, `os_log_pack_fill`, `os_log_pack_size` — `libsystem_trace`'s.
  `libsystem_kernel` exports 0 `os_log` symbols. Sec. 20 already established
  that component cannot be built without inventing two struct layouts and one
  kernel-private type, so this is sec. 20 arriving downstream, consistent
  with it rather than a new discovery.

### 46.2 A shape none of us has hit yet: nine `$UNIX2003` symbols

In the 45, and a different KIND of gap from the other 36 — a symbol-versioning
surface rather than a missing implementation:

    _close$UNIX2003   _fsync$UNIX2003   _mprotect$UNIX2003   _open$UNIX2003
    _pread$UNIX2003   _write$UNIX2003
    _pthread_cond_wait$UNIX2003  _pthread_rwlock_rdlock$UNIX2003
    _pthread_rwlock_unlock$UNIX2003    _pthread_rwlock_wrlock$UNIX2003

`libsystem_pthread` owns the pthread three and `libsystem_c` the rest. Recorded
because a reader sorting the 45 by subsystem will otherwise assume all 45 are
absent implementations, and these are not.

### 46.3 The rule this adds, and it is the third instance of one shape

Sec. 45: a bad *flag* made a subtraction cancel itself. Sec. 46: a bad *search
path* manufactured a finding. Both produced numbers or claims that survived
peer review, because in each case the instrument's own output looked
self-consistent.

> **Before reporting a missing file, a missing symbol or a missing provider,
> `ls` the path yourself.** A resolver that fails to find something and a disk
> that lacks it are the same observation. One command distinguishes them, and
> skipping it converts an instrument bug into a work item that other people will
> spend a round chasing.

## 47. THE TRIE AGREES WITH nm HERE — and the load-command profile is the next blocker

`libdyld-load` challenged the whole measurement: `nm` reads the symbol table,
dyld resolves from the **export trie**, and they are not the same structure, so
every provider set computed with `nm` all session was measured against the wrong
thing. Correct in general. Tested on the pinned artifact rather than argued.

    pinned libsystem_kernel.dylib  md5 71051fb8ddb7662cbf1d610e602d04cb
    dyld_info -exports  ->  1,470
    nm -gjU             ->  1,470      identical, symbol for symbol

**So sections 45's numbers stand unchanged**: 12 / 5 / 143, on the structure dyld
actually reads. That is not luck and not a general property. It holds here
because this library has `LC_DYLD_INFO_ONLY` with a **populated** export trie:

    rebase_off 360448   rebase_size 224
    bind_off   360672   bind_size   224
    lazy_bind_off 360896 lazy_bind_size 256
    export_off 361152   export_size 30232     <- 30 KB: a real trie

`libdyld` is the case where they diverge, because `-unexported_symbol` and the
`LC_DYLD_CHAINED_FIXUPS` form of the trie are exactly where the two structures
stop agreeing. Its 1,483-vs-1,470 discrepancy was real and load-bearing.

### 47.1 The rule, with the qualifier it actually needs

Not "always use the trie" — that would have me re-derive 1,470 to get 1,470.
The rule that fits both cases:

> **Run both. If they agree, either is fine. If they disagree, the trie wins and
> the difference is the finding.** A dylib with `LC_DYLD_INFO_ONLY` and a real
> export trie is perfectly loadable; `nm` is a faithful reader of it. The failure
> mode is not "nm is wrong", it is "you never checked which structure dyld would
> read".

A third gate follows, and neither of us has it: **actually load the thing.**
Everything reported here is static. A green link is not evidence, `nm` agreeing
is not evidence, and a populated trie is not evidence.

### 47.2 RETRACTED: there is no next blocker here — and I was one source read from asserting the opposite

> **The hypothesis below was WRONG. `libsystem_kernel` does not have
> `libdyld`'s defect and needs no `-Wl,-fixup_chains`.** It is kept verbatim so
> the retraction is findable, and so nobody re-derives it. Do not run the A/B.

What I originally wrote here:

    this libsystem_kernel   LC_DYLD_CHAINED_FIXUPS: 0
    libdyld before 7b905d26f1   LC_DYLD_CHAINED_FIXUPS: 0
    libdyld after  7b905d26f1   chained + trie load commands: 2

This artifact carries the **same load-command profile that made `libdyld` link,
install, export correctly, and fail to load.** The `-Wl,-fixup_chains` fix
(commit 7b905d26f1) is not in this component's Makefile.

**NOT DEMONSTRATED.** I have verified the load-command profile and nothing
further. The demonstration is the same shape as the `-fno-exceptions` one: not
by reading load commands, but by adding the flag and observing whether
`LC_DYLD_CHAINED_FIXUPS` appears. **NOT ATTEMPTED** — deliberately. It is a
Makefile change to a component whose clean baseline was just established for the
first time, and a flag I have not justified changing is the same class of move as
the seven `-fno-exceptions` lines sitting in `Libraries/dyld/Makefile` on a
premise now known to be wrong.

One-flag A/B available to whoever takes it, and it needs no rebuild of the
compile stage: relink `libsystem_kernel.dylib` with `-Wl,-fixup_chains` and check
for the load command.

#### Why it is wrong, and the real defect

`libdyld-load` traced it to source and the trace is short. **Both binding forms
select the same trie-reading loader**, and the legacy path is a fallback, not a
deficiency:

    ImageLoaderMachO.cpp:181-186        LC_DYLD_INFO / LC_DYLD_INFO_ONLY -> compressed = true
    ImageLoaderMachO.cpp:187-192        LC_DYLD_CHAINED_FIXUPS            -> compressed = true
    ImageLoaderMachOCompressed.cpp:477  trieFileOffset = fDyldInfo ? fDyldInfo->export_off  : fExportsTrie->dataoff;
    ImageLoaderMachOCompressed.cpp:478  trieFileSize   = fDyldInfo ? fDyldInfo->export_size : fExportsTrie->datasize;

So `LC_DYLD_INFO_ONLY` is a **fully supported way to carry an export trie**, and
line 477 is precisely the case this artifact takes. Measured on the pinned copy:

    separate LC_DYLD_EXPORTS_TRIE commands : 0        <- none needed
    LC_DYLD_INFO_ONLY export_off / size    : 361152 / 30232   <- 30 KB, POPULATED
    LC_DYSYMTAB nextdefsym                 : 1470      <- matches the 1,470 exactly
    dyld_info -exports                     : 1470      <- first _NDR_record, last _writev$NOCANCEL

**The actual defect is therefore narrower than either of us had it, and it is
not about which load command carries the region:**

> **The export region must be NON-EMPTY, whichever command carries it.**

`libdyld`'s old artifact had `LC_DYLD_INFO_ONLY` with **`export_size 0`** — an
empty trie — and 205 names in its symbol table. `-Wl,-fixup_chains` did not add
a binding form; it made the linker populate a region that was otherwise empty.
**The flag was the cure for an empty region, not a requirement of the legacy
form.** Reading my own three-line table as "same profile, same defect" is the
fifth instance today of a real signal read as a conclusion it does not support.

Two things I got right by not acting, and would again:

  - I did **not** add the flag, on the grounds that I could not justify it. The
    justification turned out to be even weaker than I thought: there was no
    defect to cure.
  - I recorded it as a **hypothesis, explicitly not a result**, with the
    demonstration named in advance. A peer's source read refuted it in one
    exchange. Had I written it as a finding, it would have cost somebody a
    rebuild of a clean baseline.

The generalisable form, and it is the same conclusion as sec. 45 and 46 from a
third direction: **a table of similarities between two artifacts is not a shared
defect.** I compared three rows and the rows matched; I never checked whether the
*property those rows are supposed to indicate* held. The property here was "can
dyld read this library's exports", and it is answered by `export_size` and
`nextdefsym`, not by which load command is present.

### 47.3 A third false zero today, and the control is what caught it

My first `dyld_info -exports` parser returned **0 entries** and I was one step
from filing that as "no export trie, catastrophic". The parser required `NF>=3`;
the lines are two fields (`0x000573D8  _NDR_record`). What saved it was the
positive control printing real lines the probe had just failed to count.

Three today, same shape, all caught by a control rather than by care:
  sec. 45   bad `nm` flag       -> a subtraction that cancelled itself to 0
  sec. 46   bad search path     -> a "missing library" that was present
  sec. 47   bad field parser    -> an "empty trie" that held 1,470 entries

None was found by looking harder at the output. Each was found by asking what a
correct probe would have shown, and the answer was "something non-zero".

## 31. THE TRIE DEFECT IS PROJECT-WIDE: 1 of 26, not 1 of 3

Follows §30's discovery that `libdyld.dylib` emitted `LC_DYLD_INFO_ONLY` with
an empty export trie. `plan` found it with `dyld_info`; fixed in
`Libraries/dyld/Makefile` with `-Wl,-fixup_chains` (commit 7b905d26f1), verified
one flag at a time and on the artifact in the generated SDK.

**Census applied with the §6.1a gate (`otool -l` for a non-zero
`LC_DYLD_EXPORTS_TRIE`), across every dylib the project has built:**

    26 dylibs in $SDK/usr/lib/system:  1 with a trie, 25 without

The one with a trie is `libdyld.dylib` — the one just fixed. Every other
dylib this project produces, plus the staged extracts, emits
`LC_DYLD_INFO_ONLY` and no trie: `libsystem_c`, `libsystem_kernel`,
`libdispatch`, `libsystem_malloc`, `libsystem_pthread`, `libsystem_platform`,
`libxpc`, `libcompiler_rt`, `libmacho`, `liblaunch`, `libutil`, `libunwind`,
`libcorecrypto`, `libcommonCrypto`, `libCrashReporterClient`, and the rest.

**So `plan`'s "1 of 3" was an undercount and the real number is 1 of 26.** The
correct Phase 6 headline is "make the libraries LOADABLE (1 of 26 done)".

**Scope of the fix.** 36 Makefiles under `Libraries/` carry a `LDFLAGS`
assignment. Exactly two now have `-Wl,-fixup_chains`, both from this round.
Fixing 25 Makefiles individually is the wrong shape: the flag belongs in
`isysroot-cc`, in the branch that already fires for dylib links (the one that
supplies `-nodefaultlibs`, `-not_for_dyld_shared_cache`, and the `-lSystem`
strip). That converts 25 Makefile edits into one wrapper change, and the
wrapper's own comment already justifies owning link hygiene on this toolchain.

**NOT DONE, deliberately.** That is a global change to a file on every
component's path, and this session produced seven instances of a global change
verified against too narrow a scope. It needs a decision, not a diff at the
end of a long session, and the per-component gate is now cheap enough
(`otool -l | grep LC_DYLD_EXPORTS_TRIE`) to measure every arm.

### libsystem_c: ATTEMPTED, REVERTED, and why

`-Wl,-fixup_chains` was added to `Libraries/Libsystem/libsystem_c/Makefile`
and a full clean build run. It could not be verified: the link fails first, and
for an unrelated documented reason —

    ld: library 'system_trace' not found

which is §20's `libsystem_trace` blocker (`lck_spin_t` is KERNEL-PRIVATE,
`os_log_buffer_s` / `os_log_buffer_context_t` exist in no file anywhere). The
installed `libsystem_c.dylib` is therefore still the pre-change artifact
(1,255,496 B, TRIE=0, 1,342 exports) and the flag's effect on that link is
**unmeasured**.

The change was reverted rather than committed unverified, and rather than
leaving an unproven edit in a component I do not own. The flag is proven correct
on dyld's real link; extending it to `libsystem_c` is very likely fine and is
**not measured**, and the two should not be conflated.

## 32. ARM 1 RESULT: the classifier's blind spot is ONE link, and it is the boot-closure one

§31 proposed putting `-Wl,-fixup_chains` in `isysroot-cc`'s existing dylib
branch rather than in 25 Makefiles. That argument is conditional on the
wrapper actually SEEING each link as a dylib, and it has a blind spot.

**The classifier census (arm 1).** Scanned every Makefile and `.mk` under
`Libraries/`, identified link rules (`${CC} ... -o ${.TARGET}`, no `-c`), and
checked whether `-dylib`/`-dynamiclib` appears on the link line **or** in the
`LDFLAGS` value that reaches it, following multi-line assignments:

    dylib links whose link line never carries -dylib
    (wrapper link-hygiene branch cannot fire):                    1

        Libraries/objc4/Makefile:118
            ${CC} -fuse-ld=${LD} -shared -o ${.TARGET} ${OBJS} ${LDFLAGS} \

    sanity, both clean:
        Libraries/dyld/Makefile:291              -dylib is in LDFLAGS
        Libraries/Libsystem/libsystem_c/Makefile:144  -dylib on the line

**This is exactly the dyld defect, and it was mine.** `Libraries/dyld/Makefile`
spelled its link `-shared` and kept `-dylib` in `COMMONFLAGS`, which flows
into CFLAGS and not into the link line, so the branch never fired and dyld
reached ld64 carrying `-lSystem`. Fixed this round by putting `-dylib` in
`LDFLAGS`. `objc4` has the same shape and has not been looked at, because
nothing reports it: the link either works or it does not, and for `objc4` it
works.

**And it is the worst possible place for a blind spot.** `objc4` stages
`libobjc.A.dylib` into the boot image, and its absence is the hard stop that
made `___mb_cur_max` reachable at all. So the component with the most direct
route to the boot is the one the mechanism cannot see, and "objc4 links fine"
is a reassuring sentence about a link receiving none of the hygiene — the same
structure as §31's empty export trie: a true sentence about a thing that cannot
do the job.

**Consequence for the decision, and it is the SMALLER one.** The population is
1, so the work is "add the flag, and fix one Makefile". The classifier itself
does not need changing. `objc4` is a one-line fix of the shape already applied
to `Libraries/dyld/Makefile`. NOT DONE here — it is a component nobody has
measured in this session and the finding is better placed as a decision than
as a diff.

**Limitation of this census, stated so it is not over-read.** It is STATIC: it
reads link rules and the `LDFLAGS` values that reach them. It cannot see a link
where `-dylib` is constructed indirectly, or a rule generated at build time. It
is strictly better than grepping `-dylib` across a file — which would have
missed that dyld carries it in `LDFLAGS` rather than on the link line, and
would have miscounted — but it is not the argv capture. **Arm 2, the
invariant that every emitted dylib-link argv carries `-Wl,-fixup_chains`, is
what proves the mechanism and what stops recurrence.** The static census bounds
the population; it does not verify the outcome.
