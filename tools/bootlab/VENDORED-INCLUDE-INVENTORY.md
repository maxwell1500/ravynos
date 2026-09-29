# Vendored-include inventory — ravynOS Libsystem

Measured, not argued. Every path here was taken from a component Makefile's `-I`
list and checked against the SDK's `usr/include`. Produced while determining
whether the include-shadowing class found in `libsystem_kernel`, `dyld` and
`libsystem_c` was one systemic problem or several narrow ones.

## The question, and the answer

**Is the vendored-include shadowing live (currently causing wrong headers to be
compiled against) or latent (a hazard for whichever components carry the path)?**

**Latent.** Verified by `clang -H` on a real `libsystem_c/libBase` translation
unit (`emulated/lchflags.c`, compiled from a cleaned tree, 183 header opens):

    87   Kernel/xnu/bsd/sys/...              vendored BSD sys/ layer   intended
    26   <SDK>/usr/include                   the SDK's own
    11   Libraries/Libsystem/libsystem_c/... its own os/, fbsdcompat/  intended
     2   Kernel/xnu/libkern
     0   Kernel/xnu/EXTERNAL_HEADERS       NOT ON libBase's PATH AT ALL

The libc is compiled against the right headers. `libsystem_c/include` is *the
libc being built*, so its headers winning there is correct, and the
content-divergent shadows live only in components that actually add their paths.

## The eleven paths

| vendored `-I` path | libc headers it holds | differs from SDK? | carriers | verdict |
|---|---|---|---|---|
| `Libraries/Libsystem/libsystem_c/include` | stdint, stddef, string, stdio, stdlib, unistd, sys/ | n/a — this **is** the libc | libsystem_c, dyld | **intended**; measured as not winning the libc build |
| `Libraries/openbsm` (5 paths, one per component) | `version` | n/a — **not a header** | dyld, liblaunch, libsystem_asl, libsystem_info, libxpc | **defect** |
| `Kernel/xnu/EXTERNAL_HEADERS` | stdint, stddef, stdlib | **YES** | libsystem_darwin | **live hazard** |
| `Libraries/Libsystem/libsystem_darwin/h` | string, stdio, stdlib | **YES** | libsystem_darwin | **live hazard** |
| `Kernel/xnu/libsyscall/mach` | string | not compared | dyld | unmeasured |
| `$BUILD/Kernel/xnu/EXPORT_HDRS/osfmk` | string | n/a — doubled-path artefact | libsystem_darwin | exists only because the build tree mirrors the source tree |

## The five content-divergent shadows

Sizes, vendored vs SDK:

| header | SDK | vendored | carrier |
|---|---|---|---|
| `stdint.h` | 5,556 B | 2,517 B | EXTERNAL_HEADERS |
| `stddef.h` | 3,816 B | 2,688 B | EXTERNAL_HEADERS |
| `stdlib.h` | **14,705 B** | **381 B** | EXTERNAL_HEADERS |
| `string.h` | 7,611 B | 5,409 B | libsystem_darwin/h |
| `stdio.h` | 16,210 B | 11,346 B | libsystem_darwin/h |

`stdlib.h` — a 381-byte copy winning over a 14,705-byte one — is the
`mach_types.h` complementarity trap in its purest form, and is the first thing
to fix in that component.

## The openbsm case is different in kind

`Libraries/openbsm/version` is a **19-byte ASCII data file** containing the
single line `OPENBSM_1_2_alpha5`. It is not a header and can never be one. It is
picked up as a header by `libsystem_c/include/stddef.h`'s `#include <version>`
(line 81, inside `#if !defined(_ANSI_SOURCE) && ...`), because the component
carries `-I .../openbsm` ahead of the SDK.

Measured: stripping that `-I` **does not** fix dyld. It removes
`OPENBSM_1_2_alpha5` and the failure moves immediately to
`<SDK>/usr/include/c++/v1/cstddef:46` — the `stddef.h` sibling of the `cstdint`
one. So it is one of several, and no single include-path change clears the class.

## Deliberately not done

No overlay has been adopted, and `libsystem_darwin` and the five openbsm carriers
have not been touched. The measurement showed the libc is clean, so an overlay
applied to the inventory alone would have disturbed a sound build while hiding
these two defects behind it. Remediation scope is the five openbsm components
plus `libsystem_darwin` — bounded, and separate from the libc.

## The lesson, in both directions

This pass is the mirror image of the mach-shim episode. There, a test too weak
to fail the way the build fails let a bad change through, and a synthetic TU was
mistaken for evidence about the real build. Here, a test too broad — the
eleven-path inventory — would have caused a bad change, by motivating an overlay
across a sound libc.

**Measurement is not the problem; it is the only tool. A measurement of one
thing does not license a conclusion about another, and the gap between them is
where every one of these stalls lived.**

## Correction: "intended" for the libc build is not a general licence

Measured 2026-09-26 while advancing the dyld frontier: the same
`Libraries/Libsystem/libsystem_c/include` path rated "intended" above is
**actively harmful in the dyld context**. `cstddef:46` and `cstring:66` both
report that libc++ cannot find **its own** `<stddef.h>` / `<string.h>` because
that directory wins them - two independent instances.

The "intended" verdict remains correct **for building libsystem_c**, where
`Kernel/xnu/bsd/sys` is the libc. It is not a statement about every consumer.
Components that compile C++ must be re-examined separately.
