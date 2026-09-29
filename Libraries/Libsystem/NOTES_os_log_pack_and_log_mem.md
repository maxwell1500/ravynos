# os_log_pack_s and os/log_mem.h — the two logging gaps

**This file is the single source of truth for these two gaps.** For the
overall state of libSystem.B and every component dylib, see
`Libraries/Libsystem/libSystem.B_STATE.md` — it points here rather than
restating, and this file deliberately does not duplicate the dylib table.

`os_log_pack_s` is absent from the whole repo and from every published Apple
source, including the host macOS SDK.

## What HAS since been done (so this record stays honest)

Option (b) was accepted for `os_log_pack_s`, with conditions. See
`Libraries/Libsystem/private/os/log.h`, which carries a prominent PROVISIONAL
banner: the layout is **ravynOS-internal, is NOT Apple's, and must not be read
as a recovered ABI**. It exists only to let `libsystem_c` compile, and it is
explicitly *not* a fix for the ABI question.

It has not been sufficient to complete `libsystem_c`, which is blocked on
unrelated bmake and header issues. `libsystem_trace` remains unbuilt and
`libSystem.B` therefore still omits it.

## Background confirmed

`os_log_pack_s` is absent from the whole repo and from every published Apple
source. I re-verified the two things the peer did not explicitly check:

- Neither the build SDK's `Kernel.framework/Versions/A/{Headers,PrivateHeaders}/os/log.h`
  nor `Kernel/xnu/libkern/os/log.h` contains `os_log_pack_s` or `olp_format`
  (grep count 0 in all three). The SDK does ship an `os/log.h`, contrary to a
  plain "no os/log.h anywhere" reading - but neither copy declares the pack.
- Vendored clang has no layout knowledge either. `clang/include/clang/AST/OSLog.h`
  defines `analyze_os_log::OSLogBufferLayout`, but that is the *inner argument*
  stream (summary byte, num-args byte, then per-item descriptor+size+data), not
  the pack header. There is no `olp_*` symbol anywhere under `llvm/`.
  `clang/test/CodeGenObjC/os_log.m` declares `void os_log_pack_send(void *)` as
  an external function rather than encoding a struct.

So the peer's conclusion stands: not importable, not derivable from a primary
source in this tree, and not obtainable without mining a binary. I did not mine
one either.

## The finding that changes the decision

`os_log_pack_send` at `libsystem_trace/log.c:267` is a **FIXME no-op**:

    void os_log_pack_send(os_log_pack_t pack, os_log_t log, os_log_type_t type)
    {
        /* FIXME: Send completed pack to ring buffer for logging */
    }

And `assumes.c:262-269` deliberately binds to the *host* implementation by name:

    _os_log_pack_send_and_compose = dlsym(RTLD_DEFAULT, "os_log_pack_send_and_compose");
    if (!_os_log_pack_send_send_and_compose) return false;
    __os_log_default = dlsym(RTLD_DEFAULT, "_os_log_default");
    if (!__os_log_default) return false;

Neither symbol exists in this tree, so on a ravynOS boot that path returns false
and the function ends. Combined with the no-op sender, **no code in this repo
ever reads a pack header back**. `log.c` writes `olp_continuous_time`,
`olp_wall_time`, `olp_mh`, `olp_pc`, `olp_format` and nothing consumes them;
`assumes.c` reads only `olp_format` and only on the dlsym path.

That means the pack header currently has **no external reader to be compatible
with** - with one exception, below.

## TASK P verdict: option (b) is viable, with one hard caveat

Option (a) as originally framed ("drop the introspection from assumes.c") is
**not sufficient on its own**, because `libsystem_trace/log.c` also needs the
struct: `os_log_pack_size` returns `sizeof(struct os_log_pack_s)` (line 213) and
`os_log_pack_fill` writes five fields (lines 252-260). `assumes.h:77` uses
`alignof(os_log_pack_s)`. So libsystem_trace cannot compile without a definition.

Option (b) - a userspace `os/log.h` - is the right shape, and because of the
finding above it does **not** require guessing an Apple layout. The correct
framing is an explicitly *private, ravynOS-internal* format that makes no
ABI-compatibility claim:

- Declare the five fields the in-tree code actually uses, in a documented order.
- State loudly in the header that this is NOT Apple's layout and that these
  bytes are never exchanged with a system libsystem_trace.

**The caveat that decides whether this is safe:** `assumes.c:274` calls
`abort_with_payload(OS_REASON_LIBSYSTEM, OS_REASON_LIBSYSTEM_CODE_FAULT, pack,
pack_size, composed, 0)`. That hands the raw pack buffer to the crash
reporter, where it is archived and can be read out of a core / by a later
analysis tool. That is a real boundary crossing. Until `abort_with_payload`'s
consumer is also understood, the private layout is *provisional* and should be
recorded as such in the header, not presented as settled.

Recommendation: implement (b) as a private header, mark it provisional because
of the `abort_with_payload` handoff, and narrow (a) so assumes.c takes the
format string by parameter rather than reaching through `pack->olp_format`.
If the team prefers zero risk, (c) - document the gap and leave libsystem_trace
unbuilt - is defensible and I would not argue hard against it. Inventing a
layout and calling it Apple's is the one option that is out.

## TASK Q verdict: PARTIALLY implementable, remainder is a real gap

The peer's chain is right: `libsystem_trace/log.h:39` does
`#include_next <os/log.h>`, which resolves to `Kernel/xnu/libkern/os/log.h`
(the SDK's copy is not on this path), and that chains through `log_private.h`
to `os/log_mem.h`, whose line 36 declares `lck_spin_t lm_lock;` while including
only `<stddef.h>`, `<stdint.h>` and `<sys/param.h>`. `lck_spin_t` is defined in
exactly one place repo-wide: `Kernel/xnu/iokit/IOKit/IOLocks.h`, kernel-only.

What `libsystem_trace/log.c` actually needs from all that is much smaller than
the chain suggests. The only log_mem types it touches are:

- `sizeof(struct os_log_buffer_s)` - lines 176, 185, 193
- `os_log_buffer_context_t` / `struct os_log_buffer_context_s` - lines 180-181
- `os_log_buffer_t` - line 184
- fields `ctx->buffer`, `ctx->content_sz`, `ctx->content_off` - lines 184-193

Split by answerability:

1. **`os_log_buffer_context_s` - IMPLEMENTABLE, honestly.** It is a purely
   private, userspace-side struct holding a buffer pointer plus two sizes, and
   every field is assigned and read inside this one file. Nothing outside
   libsystem_trace ever sees it. This can be written for real with no layout
   guessing and no ABI claim.

2. **`os_log_buffer_s` - NOT implementable here.** log.c uses it purely as a
   fixed-size prefix reserved in front of the caller's payload
   (`content_sz = buffer_size - sizeof(struct os_log_buffer_s)`). That size is
   an external contract - it must match whatever the kernel / shared-cache
   reader and Apple's own `os_log_encode` use. Declaring a size here would be
   guessing an ABI constant, which is the same class of thing as inventing the
   pack layout, and I am not doing it.

Note that item 2 is the *same* underlying gap as Task P: both are private
userspace structures whose sizes are dictated by an external contract this tree
never vendored. Solving P's header does not solve Q, and vice versa.

Recommendation: implement (1) only if it unblocks something; otherwise document
Q as a gap.

## ⛔ CORRECTION (2026-09-27) — this is NOT a fetch-a-real-header problem

The previous revision of this note ended by saying the missing `os/log_mem.h`
"has to come from Apple's actual `os/log_mem.h` (it is a public SDK header on
real macOS, so it is a fetch-a-real-header problem, not a reverse-engineering
one)". **That is false, and it would send the next person down a path that
cannot work.** Measured against the two genuine Apple SDKs installed on this
host, searching the *whole* SDK tree:

| probe | MacOSX15.4.sdk | MacOSX26.5.sdk |
|---|---|---|
| files named `log_mem.h` | **0** | **0** |
| files named `os_log.h` | **0** | **0** |
| headers **defining** `struct os_log_buffer_s` | **0** | **0** |
| headers **declaring** `os_log_encode` | **0** | **0** |

Positive control: the same `grep -rl os_log_type_t` over the same tree does
find `usr/include/os/log.h`, so the probe can see what it is looking for.

Apple's **public** `os/log.h` declares nothing named `os_log_encode` at all.
The public API takes `void *buffer` precisely so the buffer layout stays
opaque to callers. `os_log_buffer_s`, `os_log_buffer_context_t` and
`_os_log_encode` are internal to Apple's closed-source `libsystem_trace.dylib`
and appear in no shipped header.

**So `Libraries/Libsystem/libsystem_trace/log.c` is written against Apple's
private, never-published `libsystem_trace` ABI.** There is no header to fetch,
on any machine, from any SDK.

The three real ways forward, none of which is configuration:

1. **Obtain the private header** from a non-public source. An authorization
   question, not an engineering one.
2. **Re-derive `os_log_encode` against the public contract** — drop the
   `os_log_buffer_s` prefix framing entirely. A rewrite of the encode path.
3. **Declare a ravynOS-local buffer layout.** Refused: it is a
   silent-wrong-answer defect in the crash-formatting path.

Also measured, and relevant to anyone tempted to fix this by reordering
includes: `os/log_mem.h` is reached from `os/log_encode_types.h:39` via a
**quoted** `#include "log_mem.h"`, which resolves relative to the including
file and is never consulted against `-I`. No include-path reorder can move it,
and pointing the build at the SDK's `os/log.h` generation does not help —
measured to leave all three absent types unchanged *and* add a new error class
(`memory_order` and friends). See `tools/bootlab/BOOT-PLAN.md` §38.

The correct state for this gap is **documented, not guessed.** It is
deliberately not being closed tonight; the choice among the three options
above belongs to whoever owns the decision.
