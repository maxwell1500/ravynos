# Apple-binary exposure — DECISION DOCUMENT

**STATUS: THE DECISION HAS BEEN TAKEN AND EXECUTED (2026-09-26).**
Option B was chosen — **local-only, no history rewrite.**

- `12077f1638` — the 41 Apple-derived files were untracked with `git rm --cached`
  and an ignore rule added at `tools/bootlab/assets/.gitignore`. **They remain
  on disk**; nothing was deleted. Fully reversible with `git add`.
- `ef9608b0c7` — `dsc_rebase.py`, `dsc_normalize.py`, `dsc_flagfix.py` and
  `build_stubs.sh` were **archived** (not deleted) to
  `tools/bootlab/interop-archive/`, with a README recording why.

**Tracked files remaining under `tools/bootlab/assets/`: 14** — the 13 that are
ours or open source, plus the new `.gitignore`. The 41 Apple-derived files are
on disk and untracked.

This document is retained as the **decision record and rationale**, not as an
open question. The facts below were measured as of 2026-09-26.

> **Correction to an earlier figure.** The remediation plan (Category A1) records
> "45 tracked binary files totalling 11,727,752 bytes". **That was wrong** — it
> came from a narrow `grep -E '\.dylib$|/dyld$|/bin/'` filter. The correct totals
> are **54 tracked files, 35,706,769 bytes**. Both figures are broken out below.

## 1. What is actually in `tools/bootlab/assets/`

**54 tracked files, 35,706,769 bytes.** They are **not all the same kind of
thing**, and lumping them together materially overstates the legal exposure.

### 1a. Apple-derived — this is the actual exposure

**41 files, 11,470,256 bytes:**

| what | count | bytes |
|---|---|---|
| extracted Apple dylibs | 40 | 8,945,664 |
| extracted Apple `usr/lib/dyld` | 1 | 2,524,592 |

These are binaries taken out of a macOS dyld shared cache. They are Apple's
compiled product and are the only files here the standing commitment plainly
covers.

### 1b. NOT Apple-derived — third-party firmware and project artifacts

**13 files, 24,236,513 bytes:**

| what | bytes | whose it is |
|---|---|---|
| `kernel.development` | 19,023,960 | **Ours** — built by this project |
| `template_head.bin` | 2,107,392 | **Ours** — FAT32 template |
| `template_tail.bin` | 17,408 | **Ours** — FAT32 template |
| `BOOTX64.EFI` | 1,565,376 | **OVMF / EDK2**, open source, BSD-licensed |
| `boot.efi` | 723,512 | **OVMF / EDK2** |
| `vars.fd` | 540,672 | **QEMU** generated variable store |
| `bin/{ls,echo,cat,sh}` | 257,496 | **Ours** — these are the *gold* binaries the project replaces, see §4 |
| `com.apple.Boot.plist`, `etc/rc`, `hello.txt` | 697 | Config/text |

**OVMF is not Apple's intellectual property**, and neither is a QEMU `vars.fd`.
Rewriting history to remove them would be pure loss with no legal benefit.

## 2. What a history rewrite would actually cost

This is the part that changes the decision, and it is **much cheaper than the
plan assumed.**

- **First asset commit:** `3987554127`, dated **2026-09-06** — *"tools/bootlab:
  reproducible build -> FAT32 image -> QEMU boot pipeline"*.
- **Depth from that commit to HEAD: 9 commits.** Not 756. The repository has 756
  commits total, but the assets entered only **9 commits ago**.
- **It is NOT pushed.** `git branch -r --contains 3987554127` returns nothing.
  No remote branch contains it. **No tag contains it** (`git tag --contains` is
  empty).
- **Unpushed work on `darwin`: 9 commits**, which include the six local commits
  (`1f0e802`, `4a37c54`, `3a27bba`, `f6f3df2`, `f435475`, `8b1203c`) plus three
  older ones.

**What a rewrite carries with it:** those same 9 commits also contain the bootlab
tooling, the kernel fix commits, and the `e6b7f5d595` gitignore work. Removing
only the Apple binaries means filtering 9 commits, not rewriting 756 — but it
also means those 9 commits get rewritten and **the 6 unpushed commits would need
reapplying on top of the rewritten base.**

**There is no `main` on `darwin` to worry about** — the local branch is `darwin`,
and `upstream` has separate `main`/`staging`/`feat/objc_fwd` branches that do not
contain the assets.

## 3. The untracked six — still present, still untracked, still not ignored

All six confirmed: **UNTRACKED, not ignored.** One `git add -A` away from
joining the other 40.

| file | bytes | note |
|---|---|---|
| `libcorecrypto_noasm.dylib` | 933,888 | Apple DSC; **no source-built equivalent** |
| `libcorecrypto_trace.dylib` | 1,114,112 | Apple DSC; **no source-built equivalent** |
| `libkxld.dylib` | 147,456 | Apple DSC; **no source-built equivalent** |
| `liblaunch.dylib` | 49,152 | Apple DSC — **superseded**: a source-built `liblaunch.dylib` (91,720 B) exists in the build SDK |
| `libunc.dylib` | 32,768 | Apple DSC; **no source-built equivalent** |
| `libobjc.A.dylib` | 6,856 | **Not the Apple library** — this is a 6.8 KB stub produced by `tools/bootlab/build_stubs.sh`. The real thing is the 1,608,088 B source-built `libobjc.A.dylib`. |

**This is the important nuance in the question as posed:** for `liblaunch` and
`libobjc.A` the question is no longer "keep the Apple one" but **"delete the
Apple one"** — a source-built artifact has superseded them. For `libcorecrypto_*`,
`libkxld` and `libunc` there is **no** source-built equivalent, so deleting them
removes the only copy.

## 4. Clean-cutover: is any of it still load-bearing?

**Yes — and this is the part that argues against a rewrite today.**

- The **QEMU interop test still needs the Apple dyld.** `assets/usr/lib/dyld`
  (2,524,592 B, the only extracted dyld) is the binary the boot test runs.
  `libsystem_kernel.dylib` does not build, so the userspace cannot load our own
  dyld yet. **Deleting the Apple dyld ends the ability to run the boot test at
  all.**
- `assets/bin/{ls,echo,cat,sh}` are the **gold** binaries — the *targets* the
  project is trying to replace. They are ours, and they are the comparison
  baseline. Not removable.
- The **DSC/rebaser path** (`dsc_rebase.py` and friends) exists to make those
  Apple binaries loadable by dyld3. It has no consumer for anything we build —
  but it is the only reason the interop test works at all.

> **The distinction the user should make deliberately:** an **interop lab** that
> keeps Apple binaries *locally, untracked, and unpushed* is a materially
> different thing from a **repository that ships them**. Right now the project is
> accidentally in the second state for 40 files. It can be moved to the first
> state cheaply, without any history rewrite.

## 5. The decision, with costs

### Option A — history rewrite now — **NOT TAKEN, SUPERSEDED by execution of Option B**

- Removes 11.4 MB of Apple binaries from local history. **Not from any remote** —
  they were never pushed.
- **Costs:** rewrites 9 local commits; the 6 unpushed commits must be reapplied;
  every local clone is invalidated. The 13 non-Apple files (24.2 MB, including
  OVMF and our own kernel) must be **carefully preserved** — a naive purge of
  `tools/bootlab/assets/` would delete the boot firmware and break the harness
  permanently.
- **Benefit:** the committed state becomes clean.

### Option B — move to local-only, no rewrite — **TAKEN AND EXECUTED, 2026-09-26**

Because the binaries were **never pushed**, a rewrite protects nobody: no remote,
no fork, no third party ever received them. The risk being managed is
"someone runs `git add -A` on this machine", not "the world already has them".

Concretely: add `tools/bootlab/assets/**/*.dylib` and `assets/usr/lib/dyld` to
`.gitignore`, then `git rm --cached` the 41 Apple files so they stop being tracked
while remaining on disk. History is untouched, the interop test keeps working,
and the exposure drops from **41 tracked files to 0 tracked / 41 local-only**.

- **Costs:** history still contains them locally. Anyone auditing the local
  repository still finds them. Mitigated by recording this decision here.
- **Benefit:** preserves the boot harness, costs nothing, reversible, and removes
  the actual ongoing risk.

### Option C — delete the Apple binaries outright — **NOT TAKEN; still not viable**

- Ends the QEMU interop test. Only viable once `libsystem_kernel` builds and
  a source-built dyld exists. **That is not today.**

## 6. Recommendation as executed

**Option B was executed on 2026-09-26.** Revisit Option A only if the repository
is ever pushed with those binaries in it.

The decisive facts are that the binaries **were never pushed** and that the
boot test **still needs the Apple dyld** to run at all. A rewrite now would
invalidate 9 local commits, risk deleting OVMF and our own kernel along with the
Apple files, and protect against a threat that has not materialised. Moving the
41 files to local-only removes the live risk — one `git add -A` — at no cost to
the harness.

Two things to do alongside it, regardless of which option is chosen:
1. **Fix the plan's stated figure** (Category A1): 54 files / 35,706,769 bytes,
   not 45 / 11,727,752.
2. **Make the "ours vs Apple's" split explicit** so a future purge cannot
   silently take BOOTX64.EFI, `vars.fd`, `kernel.development` or the
   `template_*.bin` files with it.

## Are the Apple binaries replaceable with legal ones?  (added 2026-09-26)

**Direct answer: 21 of 41 are already replaced today, 8 more are replaceable in
principle, and 12 are not replaceable at all.** The one that matters most —
`dyld` — is in the last group, and it is the one the project is building anyway.

### How the boot actually consumes them

`tools/bootlab/manifest.json` stages **all 41**: `usr/lib/dyld` and
`usr/lib/libSystem.B.dylib` explicitly, plus a **glob of the whole
`usr/lib/system/` asset directory** (44 dylibs currently on disk). So "staged" is
true for every one of them. **Staged is not the same as load-bearing**: the image
carries them, but at runtime the Apple `libSystem.B` re-exports the Apple
components, so the set is internally consistent and none of them can be removed
individually without breaking that closure.

### Per-file

`asset bytes` = the Apple file on disk. `source build` = the legal artifact in the
generated SDK, and its `T` symbol count.

| file | status | asset bytes | source build | syms |
|---|---|---|---|---|
| `dyld` | NO-SOURCE-BUILD | 2562000 | 0 | 0 |
| `libSystem.B` | SUPERSEDED* | 71948 | 4120 | 0 |
| `libcache` | stub-only | 53068 | 8064 | 93 |
| `libcommonCrypto` | stub-only | 108752 | 8064 | 93 |
| `libcompiler_rt` | SUPERSEDED | 71556 | 151960 | 211 |
| `libcopyfile` | SUPERSEDED | 88868 | 74496 | 11 |
| `libcorecrypto` | SUPERSEDED | 1020748 | 53608 | 43 |
| `libdispatch` | SUPERSEDED | 550562 | 912240 | 247 |
| `libdyld` | stub-only | 385783 | 8064 | 93 |
| `libkeymgr` | NO-SOURCE-BUILD | 33992 | 0 | 0 |
| `libmacho` | SUPERSEDED | 37004 | 35856 | 72 |
| `libquarantine` | stub-only | 56268 | 8064 | 93 |
| `libremovefile` | SUPERSEDED | 35660 | 26552 | 12 |
| `libsystem_asl` | SUPERSEDED | 173480 | 239536 | 221 |
| `libsystem_blocks` | SUPERSEDED | 78975 | 22288 | 14 |
| `libsystem_c` | SUPERSEDED | 691936 | 1255496 | 1273 |
| `libsystem_collections` | stub-only | 56696 | 8064 | 93 |
| `libsystem_configuration` | stub-only | 73667 | 8064 | 93 |
| `libsystem_containermanager` | stub-only | 335700 | 8064 | 93 |
| `libsystem_coreservices` | SUPERSEDED | 93596 | 13832 | 2 |
| `libsystem_darwin` | SUPERSEDED | 110212 | 96640 | 65 |
| `libsystem_darwindirectory` | NO-SOURCE-BUILD | 73372 | 0 | 0 |
| `libsystem_dnssd` | SUPERSEDED | 105740 | 57992 | 48 |
| `libsystem_eligibility` | NO-SOURCE-BUILD | 85848 | 0 | 0 |
| `libsystem_featureflags` | NO-SOURCE-BUILD | 69095 | 0 | 0 |
| `libsystem_info` | SUPERSEDED | 299483 | 408160 | 523 |
| `libsystem_kernel` | stub-only | 377848 | 8064 | 93 |
| `libsystem_m` | SUPERSEDED | 535784 | 39512 | 187 |
| `libsystem_malloc` | SUPERSEDED | 470860 | 263736 | 84 |
| `libsystem_networkextension` | NO-SOURCE-BUILD | 191598 | 0 | 0 |
| `libsystem_notify` | SUPERSEDED | 137048 | 93488 | 82 |
| `libsystem_platform` | SUPERSEDED | 145572 | 88456 | 200 |
| `libsystem_pthread` | SUPERSEDED | 118674 | 164208 | 185 |
| `libsystem_sandbox` | NO-SOURCE-BUILD | 95476 | 0 | 0 |
| `libsystem_sanitizers` | NO-SOURCE-BUILD | 86120 | 0 | 0 |
| `libsystem_secinit` | NO-SOURCE-BUILD | 54896 | 0 | 0 |
| `libsystem_symptoms` | NO-SOURCE-BUILD | 89412 | 0 | 0 |
| `libsystem_trace` | SOURCE-BUT-NOT-BUILDABLE | 219902 | 0 | 0 |
| `libsystem_trial` | NO-SOURCE-BUILD | 33296 | 0 | 0 |
| `libunwind` | SUPERSEDED | 89099 | 91424 | 47 |
| `libxpc` | SUPERSEDED | 559470 | 132672 | 241 |

`SUPERSEDED*` — `libSystem.B` is genuinely source-built, but at 4,120 B with
0 defined symbols it is a **re-export-only** dylib. That is correct and real, not
a stub; it just has no code of its own, so a size test would misjudge it.

### 1. Replaceable TODAY (21)

These have a real source-built artifact in the SDK providing the same symbols.
`libmacho`, `libdispatch`, `libxpc`, `liblaunch`, `libsystem_notify`,
`libsystem_info`, `libcompiler_rt`, `libobjc.A`, `libsystem_m`,
`libsystem_malloc`, `libsystem_pthread`, `libsystem_platform`,
`libsystem_coreservices`, `libsystem_dnssd`, `libsystem_blocks`,
`libsystem_c`, `libremovefile`, `libcopyfile`, `libcorecrypto`, `libSystem.B`.

**Why they are still there:** leftovers from the DSC pipeline. The manifest's
`usr/lib/system` glob stages whatever is in the directory, and nobody has
narrowed it. **Not needed by any specific test.** Deleting them is safe **only if
the source-built ones are put in their place in the image** — which is precisely
what the build driver does not yet do.

**Caveat that matters:** `libobjc.A.dylib` in the assets tree is a **6,856-byte
`build_stubs.sh` stub**, not the Apple library; the real counterpart is the
1,608,088 B source build. It should be deleted regardless of the rest.

### 2. Replaceable IN PRINCIPLE (8)

`libcache`, `libcommonCrypto`, `libkeymgr`, `libquarantine`,
`libsystem_collections`, `libsystem_configuration`, `libsystem_containermanager`,
`libsystem_kernel`. Source exists in this tree for all of them; the SDK copy is
still an 8,064-byte stub, so they are not replaced yet. `libsystem_kernel` is
the known critical-path item.

### 3. NOT replaceable at all (12) — today

`dyld`, `libsystem_trace`, `libsystem_darwindirectory`, `libsystem_eligibility`,
`libsystem_featureflags`, `libsystem_networkextension`, `libsystem_sandbox`,
`libsystem_sanitizers`, `libsystem_secinit`, `libsystem_symptoms`, and
`libdyld`.

Most of these have **no source tree in this repository at all** — libquarantine,
libsystem_sandbox, libsystem_secinit and libsystem_symptoms are Darwin-private
and were never published. For those the answer is not "replaceable"; it is
"never obtainable".

**`dyld` is the special case, and it is the one to be clear about.** There is no
source-built substitute today *because `libsystem_kernel` does not build* — that
is the whole reason. But a real `libdyld.dylib` is already on the plan (B3), so
`dyld` is **replaceable in principle once the blocker in front of it clears**. It
is not a permanent gap; it is a queued one.

### What that means for the interop test

The QEMU interop test **cannot** be made Apple-free today, and no amount of
deleting the other 40 changes that. Two things stand in the way, and both are
already on the plan:

1. `libsystem_kernel` does not build (one `std_types.defs` parse failure).
2. `libdyld` is unbuilt (an SDK header-configuration sequence, `stdint.h` done).

**So the decision for the other 40 is separate from `dyld`.** They can be removed
from the image and replaced by their source-built counterparts without touching
the interop test's ability to run — but only once a real dyld exists, because
until then the boot still needs the Apple dyld, and the Apple dyld's
`libSystem.B` re-exports the Apple components. **The 40 are the payload of the
dyld, not an independent problem.** Removing them while keeping the Apple dyld
would break the closure.

**Recommended order, when the work lands:**
1. `libsystem_kernel` builds -> 2. `libdyld` builds -> 3. stage the source-built
set, drop the Apple `libSystem.B` and `dyld` -> 4. only then delete the 40.

**Nothing in this analysis authorises deleting the Apple files today.** The
honest position is that they are the *load-bearing payload of the one component
still unbuilt*, and the 12 in group 3 include 10 that are not obtainable at all.

---

## CORRECTION (final consolidation round) -- see tools/bootlab/STATUS-AND-OPEN-DECISIONS.md

Three claims in this document were wrong and are corrected here rather than
rewritten, so the reasoning history stays visible.

1. **The count is FIFTEEN, not ten.** "10 of 12" was an unverified
   subtraction and was wrong. `libsystem_trace` was filed in this table as
   NO-SOURCE-BUILD; that was wrong too -- it HAS source, 1,004 lines of C in
   `Libraries/Libsystem/libsystem_trace/` (log.c, signpost.c, init.c, three
   headers, Makefile). Three further components with no source exist and were
   missing from the table: `libkxld`, `libsystem_trial`, `libunc`. The row
   above is now `SOURCE-BUT-NOT-BUILDABLE`, which is the accurate category and
   is explained in the consolidation document.

2. **"0 references from anything we stage" was WRONG, not stale.** All fifteen
   are referenced by the boot image: 32 non-weak, 1 weak, 15 re-export, 3
   upward. The mechanism is that the staged Apple `libSystem.B.dylib`
   re-exports all fifteen, and `/bin/echo` has a single load command naming
   that dylib, so every one of them is reachable at run time.

3. **The SDK half of that claim WAS correct.** None of the fifteen exists in
   the SDK at all. "Unreachable" was a statement about the SDK tree, not about
   the boot image, and the two were conflated.
