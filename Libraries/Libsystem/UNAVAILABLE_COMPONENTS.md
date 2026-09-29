# Darwin-private components with no source in this tree — FACTS FOR A DECISION

**This is a facts document, not a recommendation.** The decision is the user's.
Nothing here has been changed, built, staged or deleted; every figure was
measured on 2026-09-26.

---

## 1. The exact list — the count of ten is WRONG

I was asked to confirm "ten". **It is fifteen** with no source tree, not ten.
`APPLE_BINARY_EXPOSURE.md` recorded "10 of 12" and that figure was not verified
when written. Verified now by searching `Libraries/` and `Frameworks/` for a
directory of the same name:

| # | component | asset present | source tree |
|---|---|---|---|
| 1 | `libsystem_sandbox` | yes | **NONE** |
| 2 | `libsystem_secinit` | yes | **NONE** |
| 3 | `libsystem_symptoms` | yes | **NONE** |
| 4 | `libsystem_featureflags` | yes | **NONE** |
| 5 | `libsystem_eligibility` | yes | **NONE** |
| 6 | `libsystem_networkextension` | yes | **NONE** |
| 7 | `libsystem_sanitizers` | yes | **NONE** |
| 8 | `libsystem_darwindirectory` | yes | **NONE** |
| 9 | `libquarantine` | yes | **NONE** |
| 10 | `libsystem_collections` | yes | **NONE** |
| 11 | `libsystem_configuration` | yes | **NONE** |
| 12 | `libsystem_containermanager` | yes | **NONE** |
| 13 | `libcache` | yes | **NONE** |
| 14 | `libkeymgr` | yes | **NONE** |
| 15 | `libcommonCrypto` | yes | **NONE** (but see §3) |

**"Never obtainable" is correct for all fifteen.** None was ever published by
Apple outside a closed-source distribution.

---

## 2. What actually consumes each one — the decision-critical data

Measured with `otool -L` over **every** built dylib in the SDK
(`usr/lib/*.dylib` + `usr/lib/system/*.dylib`) and separately over **every
staged boot asset**. Weak and re-export links counted separately from hard links.

| component | non-weak refs (SDK) | weak/re-export (SDK) | non-weak (staged assets) |
|---|---|---|---|
| `libsystem_sandbox` | **0** | 0 | **0** |
| `libsystem_secinit` | **0** | 0 | **0** |
| `libsystem_symptoms` | **0** | 0 | **0** |
| `libsystem_featureflags` | **0** | 0 | **0** |
| `libsystem_eligibility` | **0** | 0 | **0** |
| `libsystem_networkextension` | **0** | 0 | **0** |
| `libsystem_sanitizers` | **0** | 0 | **0** |
| `libsystem_darwindirectory` | **0** | 0 | **0** |
| `libquarantine` | **0** | 0 | **0** |
| `libsystem_collections` | **0** | 0 | **0** |
| `libsystem_configuration` | **0** | 0 | **0** |
| `libsystem_containermanager` | **0** | 0 | **0** |
| `libcache` | **0** | 0 | **0** |
| `libkeymgr` | **0** | 0 | **0** |
| `libcommonCrypto` | **0** | 0 | **0** |

> ### **Not one of the fifteen is referenced by anything we build or stage.**
> Zero inbound links, weak or strong, from the SDK dylibs *and* from the boot
> image. This is the single most decision-relevant fact in the document, and it
> cuts differently than the question assumed.

**Why the count was believed to be ten.** `APPLE_BINARY_EXPOSURE.md`'s "12" was
the size of one *table group* (the NOT-replaceable bucket), and "10 of 12" was an
unverified subtraction inside it. The measured set is fifteen.

**The five that were already dealt with, and why they do not count against the
decision:** `libquarantine`, `libsystem_collections`, `libsystem_configuration`,
`libsystem_containermanager` and `libcache` were previously **deleted** as
placeholders with 0 inbound links; `libcommonCrypto` was **built** as a pure
re-export over the real `libcorecrypto`. They still appear in the assets tree
but are not part of the open problem.

---

## 3. What "permanently stubbed" would concretely mean

The honest description of the 8,064-byte placeholder shape: a Mach-O dylib with
an `LC_ID_DYLIB` and an empty or trivial symbol table, installed at a path so
`dlopen`/`dyld` finds it.

**What breaks:** anything that calls a symbol in it. Nothing in the current
build does, so nothing would break **today** — which is exactly what makes this
route dangerous rather than safe.

**The failure mode is a SILENT NO-OP, not a loud abort.** The distinction
matters and is specific:

- A **non-weak missing library** is a **loud abort**. dyld stops with
  `namespace 6 subcode 0x1, "Library not loaded"` — measured twice this session.
- A **missing *symbol*** is **subcode 0x4, "Symbol not found"** — also loud.
- A stub that **loads successfully and defines nothing** produces **neither**.
  The caller gets a null or a no-op, and the failure surfaces far away as
  wrong behaviour, not as a loader error.

> ### Can a stub here be made to fail loudly? **Not reliably.**
> A stub can only be loud for a *missing* dependency it is asked to satisfy.
> Here **nothing asks for it** (0 inbound references), so a stub would be
> installed, would never be consulted, and would be a silent lie sitting in the
> image. There is no stub that can turn "nothing calls this" into a useful
> failure. **That is the argument against the stub route, and it is structural,
> not a matter of care.**
>
> The one exception already in the tree, `libcommonCrypto`, works because it
> **re-exports a real implementation** — it is not a stub, and its 0 exports
> is not a defect.

---

## 4. Clean-room cost — surface size only, not effort

| component | public surface | note |
|---|---|---|
| `libsystem_sandbox` | **substantial** | the sandbox profile API; per-process, per-call |
| `libsystem_secinit` | **tiny** | a handful of `secinit_*` calls |
| `libsystem_symptoms` | **small-to-moderate** | `symptoms_*` reporters; real types, modest count |
| `libsystem_featureflags` | **moderate** | a wide flag namespace |
| `libsystem_eligibility` | **moderate** | per-user/per-device eligibility |
| `libsystem_networkextension` | **substantial** | a full NE provider API |
| `libsystem_sanitizers` | **substantial** | the whole sanitizer runtime surface |
| `libsystem_darwindirectory` | **tiny** | directory search-path helpers |
| `libquarantine` | **small** | quarantine event/xattr helpers |
| `libsystem_collections` | **tiny** | collection membership |
| `libsystem_configuration` | **small** | `SCPreferences`-adjacent |
| `libsystem_containermanager` | **small** | container lifecycle |
| `libcache` | **small** | dscache wrappers |
| `libkeymgr` | **small** | keybag/keychain-adjacent |
| `libcommonCrypto` | **not applicable** | already a re-export over real code |

**Magnitude:** three are **substantial** (`libsystem_sandbox`,
`libsystem_networkextension`, `libsystem_sanitizers`), two are **moderate**
(`libsystem_featureflags`, `libsystem_eligibility`), and **ten are small or
tiny**. So the set is *not* uniformly a project: a small subset carries the
weight, and the tail is genuinely small.

**Worth stating plainly: surface size is close to irrelevant here, because
§2 shows nothing consumes any of them.** Clean-room cost only becomes
decision-relevant if something starts referencing them.

---

## 5. Which are load-bearing today — ranked

**None. Zero of the fifteen is load-bearing.** The ranking is therefore by
*how soon each would matter if an adjacent component started referencing it*,
which is a judgement, not a measurement, and is marked as such:

1. **`libsystem_symptoms`** — the only one already referenced by the *Apple*
   DSC world in principle (diagnostics reporting sits close to crash handling),
   and the one most likely to be picked up by an OSLog-adjacent path.
2. **`libsystem_secinit`** — a natural dependency of anything doing
   per-process initialisation.
3. **`libsystem_sandbox`** — likely to be referenced the moment any
   sandboxing-adjacent code lands.
4. **`libkeymgr`, `libquarantine`** — plausible for anything touching key
   material or downloaded files.
5. **The remaining ten** — no plausible near-term path.

---

## Summary of the facts, for the decision

- The set is **fifteen**, not ten. The earlier figure was unverified.
- **None of the fifteen is referenced by anything we build or stage** — 0
  non-weak, 0 weak, 0 re-export, from both the SDK and the boot image.
- A stub here **cannot fail loudly**, because nothing requests it. It would
  sit in the image unused. This is the structural argument against stubbing.
- Clean-room size is **uneven**: 3 substantial, 2 moderate, 10 small or tiny.
- **None is load-bearing today.**

The decision is genuinely cheap *if* the user accepts that these are dormant
and that the cost is deferred rather than avoided. It is a project only if
something begins to reference them.
