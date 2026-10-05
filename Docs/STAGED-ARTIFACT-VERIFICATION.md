# Verifying staged artifacts on the ravynOS toolchain

## Read this first: exit 0 means nothing here

This toolchain has exited `0` while being wrong in six distinct ways in a single
night. Not one of them was caught by an exit status. Every real finding came
from reading bytes or source.

1. A MDEP syscall handler reported "absent" from a `grep` — the dispatch was in
   `idt64.s` assembly the grep did not cover.
2. `Foundation` reported "missing" because the lookup ran from the wrong cwd.
3. A staged artifact was stale relative to its source; the build had succeeded.
4. A framework build installed only into the build-tree SDK, not the repo SDK
   the image stages from.
5. The build is not byte-reproducible, so "the file changed" was unfalsifiable
   by hash.
6. The shipped binary set had silently diverged from the build tree.

If a check here has not read bytes or symbols, it has not checked anything.

## The comparison rule

**A sha256 mismatch proves nothing on this toolchain.** Two builds of identical
source differ in 606 bytes across 304 runs even with `LC_UUID` masked, because
the linker lays down relocated pointers that shift between link runs. Those
runs could not be localised to any declared section, so `__TEXT` byte-equality
is **not** a sound gate either.

Compare in this order:

```
# 1. defined symbol set  — must match exactly
diff <(nm -g "$A" | awk '{$1="";print}' | sort -u) \
     <(nm -g "$B" | awk '{$1="";print}' | sort -u)

# 2. load commands / sections — must match
diff <(otool -l "$A" | grep -E '^\s+cmd |^  (segname|sectname) ') \
     <(otool -l "$B" | grep -E '^\s+cmd |^  (segname|sectname) ')

# 3. bytes — only meaningful once 1 and 2 have matched
cmp "$A" "$B"
```

Verdicts:

| verdict | meaning |
|---|---|
| `MATCH` | sha equal, or symbols+commands equal and bytes equal |
| `REBUILD-EQUIVALENT` | sha differs, symbols **and** commands identical — **the normal case here, not a fault** |
| `CONTENT-DIFFERENT` | symbols or commands differ — a real finding |

Do not open an investigation for `REBUILD-EQUIVALENT`. Two shipped artifacts
were investigated on the strength of a sha difference in one night; both turned
out to be rebuilds of identical content.

## Current state of the shipped set

Measured across the 46 shipped Mach-O artifacts named by
`tools/bootlab/manifest_gui.json`, comparing `Developer/ravynOS.sdk` against the
build-tree SDK:

| count | verdict |
|---|---|
| 14 | `MATCH` |
| 1 | `REBUILD-EQUIVALENT` (`usr/lib/libSystem.B.dylib`) |
| 1 | `CONTENT-DIFFERENT` (`usr/lib/libutil.dylib`) |
| 30 | one-sided — **unverified, not wrong** |

The 30 one-sided artifacts are mostly `libsystem_*`: they have not been rebuilt
into the build-tree SDK since 2026-10-04, so there is nothing to compare
against. That is an absence of evidence and is recorded as such.

## The one real finding

`usr/lib/libutil.dylib` was `CONTENT-DIFFERENT`: the staged copy exported 6
`_ExtentManager` symbols, the freshly built copy exported 4. The staged copy
agreed with the `BSD/lib/libutil` build product; the build-tree SDK copy did
not.

Owner: `BSD/lib/libutil/Makefile`, whose install loop named only
`${RAVYN_SDKROOT}` and `${SYSROOT_DIR}` — both of which resolve to the
**build-tree** SDK. Nothing named `${RAVYN_REPO_SDKROOT}`, the in-repo SDK that
`manifest_gui.json` stages from. Fixed by adding the repo path to that loop,
additively, matching the shape already used in `Frameworks/*/Makefile`,
`Libraries/ICU/Makefile` and `Frameworks/CoreServices/LaunchServices/Makefile`.

**Status: Makefile fixed, NOT yet rebuilt or verified.** `build-libraries.sh`
has no entry point for `BSD/`, and `BSD/lib/libutil/Makefile` carries
root-relative include paths (`-I/Kernel/xnu/...`) plus a toolchain expectation
that only a purpose-built harness supplies. The convergence has therefore not
been demonstrated. Treat the gate as **not met**.

## Watch-list: install loops that omit the repo SDK

Eight Makefiles already name `${RAVYN_REPO_SDKROOT}`:
`Libraries/ICU`, `Frameworks/{Foundation,AppKit,CoreText,CoreGraphics,Onyx2D,CFNetwork}`,
`Frameworks/CoreServices/LaunchServices`.

Twelve have an install or copy loop and do not:
`Libraries/Libsystem`, `Libraries/Libsystem/libmacho`, `Libraries/zlib`,
`Libraries/ICU/{native,target,build_qnx}`, `Frameworks/CoreFoundation`,
`Frameworks/CoreServices`, `Frameworks/Onyx2D/freetype`,
`Frameworks/CoreText/{gperf,fontconfig}`, `Frameworks/AppKit/xkeyboard-config`,
`CoreServices/WindowServer/libinput`.

This is a **watch-list, not a fix-list.** None of the twelve has been shown to
ship a divergent binary; they are latent conditions, and several are
vendored-source or header trees that ship nothing binary at all. Fix them as
they are proven, under the rule above — not speculatively.

### Resolution — FIXED AND VERIFIED

`BSD/` now has an entry point: `build-libraries.sh --bsd BSD/lib/<name>`, in
the same shape as `--frameworks`, exporting the same environment and invoking
bmake from the repo root so the BSD Makefiles' root-relative includes resolve.
Hand-invoking bmake on those Makefiles fails three ways before the link (CC/LD
from a nonexistent `${TOOLCHAIN}`, an empty `-mmacos-version-min=`, and
root-relative `-I/Kernel/...` paths), which is why `BSD/` was previously
buildable only by hand — and being hand-buildable *was* the defect.

After `build-libraries.sh --bsd BSD/lib/libutil`, `_ExtentManager` symbol
count is **6 at all three locations** (repo SDK, build-tree SDK, BSD build
product) and the full defined-symbol sets are identical.

Re-running the comparison over the shipped set: **14 MATCH, 1
REBUILD-EQUIVALENT (`usr/lib/libSystem.B.dylib`), 0 CONTENT-DIFFERENT, 31
one-sided.** The gate is met.

`BSD/lib/libutil` is **not** among the twelve above: it is a thirteenth
Makefile, it was the only one proven to ship a divergent binary, and it is now
fixed and verified. Its remedy also differed from the rest — the defect there
was not a missing repo path alone but that `BSD/` had no build entry point at
all, so nothing refreshed the staged binary. The remaining eleven entries are
latent.
