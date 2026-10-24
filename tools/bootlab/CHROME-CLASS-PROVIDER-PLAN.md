# Chrome's ObjC classrefs: the class-provider plan (2026-10-20)

Companion to `BOOT-PLAN.md` §22 ("Chrome's whole framework tree, and where it stops being a packaging problem").
BOOT-PLAN §22 is the tracker for the packaging work; this file is the tracker for the one defect that is **not** a
packaging defect: Chrome's `__objc_classrefs` bind to zero-quad stubs, and the guest runtime crashes dereferencing
them. Everything below is measured; the commands are the ones that produced the numbers.

## 0. The defect, in one paragraph

The modern ObjC ABI requires that the exported symbol `_OBJC_CLASS_$_X` **be** the `objc_class` structure — its
*address* is the class object, and its *value* is the class object's `isa` slot. `chrome_stage.py` currently emits
class traps as **`.quad 0` data slots** (`gen_stub`, `chrome_stage.py:865-867`) plus a constructor that calls
`objc_allocateClassPair`/`objc_registerClassPair`. So Chrome's classref binds resolve to a slot whose contents are
zero, and the runtime reads `isa == 0`, `bits == 0`, so `data()` returns null and `isRealized()` faults:

```
rip at /usr/lib/system/libobjc.dylib base+0x328ee = objc_class::isRealized calling objc_class::data() (base+0x140b0) with rax=0
```

(BOOT-PLAN §22, "Crash chain across iterations".) The fix is **not** to keep stubbing those symbols: it is to give
Chrome real class objects. This plan builds one provider image that defines all the missing classes as genuine
modern-ABI classes, and re-exports it from every framework Chrome binds a class symbol from.

## 1. What Chrome actually needs (measured, not assumed)

`work/chrome-payload/Frameworks/Google Chrome Framework.framework/Versions/155.0.8059.82/Google Chrome Framework`:

| measurement | value |
|---|---|
| distinct `_OBJC_CLASS_$_` names bound | **263** |
| strong (non-weak-import) | 240 |
| weak-import only | 23 |
| distinct `_OBJC_METACLASS_$_` binds | 321 (mostly `libobjc/_OBJC_METACLASS_$_NSObject`) |
| libraries a class symbol is bound *from* | 30 (`AppKit` 65 strong, `Foundation` 51, `Metal` 21, `CoreFoundation` 20, …) |

Two properties of these binds drive the whole design:

1. **They are library-scoped (two-level namespace).** Chrome binds `Metal/_OBJC_CLASS_$_MTLTextureDescriptor`,
   `Foundation/_OBJC_CLASS_$_NSNumber`, `AppKit/_OBJC_CLASS_$_NSApplication`. dyld2 resolves such a bind against the
   *named* library's export list (`ImageLoaderMachOClassic.cpp:1080-1130` → `target = libImage(ord-1)` →
   `findExportedSymbolAddress`; `ImageLoader.cpp:308-318` → `findExportedSymbol(name, true, foundIn)`;
   `ImageLoaderMachO.cpp:1690-1713` walks `libReExported` chains). **Consequence: the symbol must be reachable from the
   library Chrome names** — not merely present somewhere in the process.
2. **The class's own `__objc_classlist` does not help.** Chrome's framework binary defines **zero** classes; all 263
   are imports. Its `__objc_classlist` (0x570 bytes = 174 entries) holds *rebases of class refs*, not definitions.

All 30 binding libraries are present in the staged closure (`work/chrome_plan.json` → `deps`), except `libobjc`,
which is the runtime itself and exports `_OBJC_CLASS_$_NSObject` natively.

## 2. Which names must be synthesized, and which must not (measured)

Two independent censuses were run and cross-checked:

- **Trapped set** — `work/chrome_plan.json` → `deps[*].traps`: **167** distinct `_OBJC_CLASS_$_` names and
  **6** `_OBJC_METACLASS_$_` names are trapped across the **29** deps that trap ObjC symbols
  (22 `trap-only`, 4 `at-path-shim`, 3 `side-shim`).
- **Provided set** — `nm -g` over every staged Mach-O (`Developer/ravynOS.sdk`, 22 images; plus the 104
  manifest-listed images = **126** images total): **673** distinct class names are exported by some staged image.

Subtracting gives the synthesis set:

| set | count | source |
|---|---|---|
| provided by a staged image | **22** | `Foundation` (21: `NSArray`, `NSData`, `NSDate`, `NSDictionary`, `NSURL`, `NSUserDefaults`, …) and `QuartzCore` (`CIImage`) |
| **must be synthesized** | **145** | everything else |
| metaclass names to synthesize | **5** | `ASAuthorizationController`, `CAMetalLayer`, `CAOpenGLLayer`, `NSAccessibilityElement`, `NSTitlebarAccessoryViewController` |
| metaclass name already provided | 1 | `NSInputStream` (exported by staged `Foundation`) |

The 6th trapped metaclass, `NSInputStream`, is already exported by staged Foundation, so it needs nothing.

**Collision checks (all negative, all measured):**
- synth ∩ staged-image class-list names = ∅ — over **2951** distinct class names defined across the **126** staged images.
- synth ∩ Chrome-payload-defined names = ∅ — over **3681** distinct class names defined across Chrome's **25** payload images.
- synth ∩ staged-image *exported* names = ∅.
- The only name trapped by two deps is `NSURLSession` / `NSURLSessionConfiguration` (both `CFNetwork` and `Foundation`).
  A **single shared provider image** resolves this: one class object, one name, reachable from both libraries.

## 3. The provider image

### 3.1 Why one shared image, not one per dep

A per-dep provider would define `NSURLSession` twice under two library scopes — two distinct class objects with the
same name. The guest runtime's `addNamedClass` warns on duplicates and **keeps the old mapping**
(`objc-runtime-new.mm:1736-1744`), so one of the two binds would silently point at the wrong object. One image,
re-exported from all 29 deps, gives one class object per name. (The same reasoning rules out defining the 22 provided
names in the provider: they would collide with the staged `Foundation`/`QuartzCore` definitions at runtime.)

### 3.2 Build recipe — validated end-to-end this session

```
TC=/Users/max/Projects/build/Developer/Platforms/ravynOS.platform/Developer/Toolchains/Default.xctoolchain/usr/bin
SDK=/Users/max/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk
REPO=/Users/max/Projects/ravynos

$TC/clang-17 -c -arch x86_64 -isysroot $SDK -mmacos-version-min=15.0 -fPIC \
  -DAPPLE_RUNTIME_4 -DDARWIN -DNULL=0 -DTARGET_OS_IOSMAC=0 -DPLATFORM_IS_POSIX \
  -DPLATFORM_USES_BSD_SOCKETS -DTOLL_FREE_BRIDGING \
  -I$REPO/Developer/ravynOS.sdk/usr/local/include/kernel \
  -I$REPO/Developer/ravynOS.sdk/System/Library/Frameworks/Foundation.framework/Headers \
  -I$REPO/Libraries/objc4 -I$REPO/Frameworks/Foundation \
  -o provider.o provider.m

$TC/clang-17 -arch x86_64 -isysroot $SDK -dynamiclib -mmacos-version-min=15.0 -nostdlib -nodefaultlibs \
  -install_name /usr/lib/chrome/ObjCClassProvider.dylib \
  -Wl,-compatibility_version,65535.255.255 -Wl,-current_version,65535.255.255 \
  -L$SDK/usr/lib -lobjc -lSystem \
  -o provider.dylib provider.o
```

Notes that are **not** optional:
- **`clang-17` from the platform toolchain**, not `xcrun clang` (host clang 21 segfaults on this tree's ObjC — see
  `build-libraries.sh` header). `tools/bootlab/chrome_stage.py` currently uses `CLANG = "xcrun clang"`; the provider
  build must pin the toolchain explicitly.
- **`-nostdlib -nodefaultlibs`** plus explicit `-lobjc -lSystem`, matching `gen_stub`'s link flags.
- **`-Wl,-compatibility_version,65535.255.255`** — dyld2 refuses an image whose compatibility version is lower than
  the importer's requirement, and Chrome demands real macOS versions (150.0.0, 1195.14.4, …). 65535.255.255 is the
  packed 0xFFFFFFFF wildcard. Same reason as `gen_stub`.
- **`-lobjc` from `$SDK/usr/lib`** (not `usr/lib/system`) — the build SDK has no `usr/lib/system/libobjc.dylib`;
  `usr/lib/libobjc.dylib` is the one whose `LC_ID_DYLIB` is `/usr/lib/system/libobjc.dylib`, which is what the guest
  loads. Linking the wrong path fails outright (`library ... not found`).
- **No `-fobjc-runtime` flag.** Measured: the default and `macosx-10.8/10.15/11.0/13.0` variants produce byte-identical
  output; `gnustep-2.0` fails to compile on Mach-O.

### 3.3 Source shape

One `@interface`/`@implementation` pair per synthesized name, superclass `NSObject`:

```objc
#import <objc/NSObject.h>
@interface MTLTextureDescriptor : NSObject
@end
@implementation MTLTextureDescriptor
@end
```

Empty bodies are correct and sufficient: the runtime needs a *realizable* class object, not behaviour. Real behaviour
belongs to the repo frameworks (see §7).

### 3.4 What the built provider must look like (the gate)

Measured on the prototype built with the recipe above:

```
$ nm -g provider.dylib | grep OBJC
0000000000002028 S _OBJC_CLASS_$_MTLTextureDescriptor      ← S-type: the address IS the class object
0000000000002078 S _OBJC_CLASS_$_NSAccessibilityElement
0000000000002000 S _OBJC_METACLASS_$_MTLTextureDescriptor
0000000000002050 S _OBJC_METACLASS_$_NSAccessibilityElement
                 U _OBJC_CLASS_$_NSObject
```

```
$ dyld_info -fixups provider.dylib | grep __objc_data
0x00002000  bind libobjc/_OBJC_METACLASS_$_NSObject     ← metaclass isa
0x00002008  bind libobjc/_OBJC_METACLASS_$_NSObject     ← metaclass superclass
0x00002010  bind libobjc/__objc_empty_cache             ← cache buckets
0x00002020  rebase 0x00001018                           ← bits → class_ro_t
0x00002028  bind <this-image>/_OBJC_METACLASS_$_MTLTextureDescriptor   ← class isa
0x00002030  bind libobjc/_OBJC_CLASS_$_NSObject         ← class superclass
0x00002038  bind libobjc/__objc_empty_cache
0x00002048  rebase 0x00001060                           ← bits → class_ro_t
```

This is **byte-shape-identical** to the guest's own `NSObject` class in `Libraries/objc4/libobjc.A.dylib`
(class @0xbbae8: isa → metaclass, superclass nil as root, cache → `__objc_empty_cache`, bits → ro_t), and to an
Apple-built x86_64 reference (`/tmp/hostcls.dylib`, built by `xcrun clang -arch x86_64`): same slot semantics,
same 40-byte stride, same `ro_t` shape.

`otool -ov` on the provider prints the canonical modern shape:

```
0000000000001000 0x2028 _OBJC_CLASS_$_MTLTextureDescriptor
    isa        0x2000 _OBJC_METACLASS_$_MTLTextureDescriptor
    superclass 0x0 _OBJC_CLASS_$_NSObject
    cache      0x0 __objc_empty_cache
    vtable     0x0
    data       0x1060 __OBJC_CLASS_RO_$_MTLTextureDescriptor
```

**Acceptance for the provider build:** `nm -g` shows all 145 class symbols + all 145 metaclass symbols as `S`-type;
`dyld_info -fixups` shows each class's isa → its own metaclass and superclass → `libobjc/_OBJC_CLASS_$_NSObject`;
`otool -ov` prints the shape above for a sample.

### 3.5 Runtime-visibility requirements (all verified)

- The guest dyld2 sets `fNotifyObjC` for an image when a `__DATA*` segment contains `__objc_imageinfo`
  (`ImageLoaderMachO.cpp:779` computes `isDataSeg = strncmp(seg->segname, "__DATA", 6) == 0`, and
  `__DATA_CONST` matches that 6-char prefix; the provider's `__objc_imageinfo` lands in `__DATA_CONST`). So the
  runtime is notified about the provider image and `map_images` runs on it.
- The provider's `__objc_classlist` (in `__DATA_CONST`) is read by `objc-file.mm`'s `getDataSection`, which searches
  `__DATA`, then `__DATA_CONST`, then `__DATA_DIRTY` — so the section placement above is fine.
- The provider's `__objc_classlist` entries **bind** to `<this-image>/_OBJC_CLASS_$_X` rather than rebasing. That is
  correct and is what the guest runtime expects (it re-reads the class list through `readClass`).

## 4. Wiring it to Chrome (the `chrome_stage.py` change)

Four edits, all in `tools/bootlab/chrome_stage.py`:

1. **Build the provider** once per staging run, into `work/chrome-shims/usr/lib/chrome/ObjCClassProvider.dylib`,
   with `-install_name /usr/lib/chrome/ObjCClassProvider.dylib`. Emit it before the dep shims so the shims can
   link against it.
2. **Drop the zero-quad class traps.** In `gen_stub` (`chrome_stage.py:809-880`), the `classes` bucket must **not**
   emit `.quad 0` class/metaclass slots nor the `objc_allocateClassPair` constructor for the 145 synthesized names.
   The constructor approach is exactly what produced the crash: it registers a *runtime* class and stores it in a
   data slot, but Chrome's classref binds to the **address** of the symbol, not to the slot's contents.
   Every class trap whose name is in the provider's export set is deleted from `traps` before `gen_stub` runs.
3. **Add the re-export edge to every dep that traps a class symbol.** For each of the **29** ObjC-trapping deps, add
   `-Wl,-reexport_library,<abs path to provider.dylib>` to the link flags. This is the *same* mechanism already used
   for the provider-edge rule (BOOT-PLAN §22), so the spelling is settled: the full-path
   `-Wl,-reexport_library,<path>` works; the `-Wl,-reexport-l<stem>` form silently does nothing.
   ld64 records the re-exported dylib's `LC_ID_DYLIB`, so the guest resolves `/usr/lib/chrome/ObjCClassProvider.dylib`.
4. **Keep the 22 provided names as re-export edges, not stubs.** `Foundation`'s 21 and `QuartzCore`'s `CIImage`
   already resolve through the existing provider-edge rule (`data_providers`, `chrome_stage.py:605-618`) — the
   `Foundation` dep re-exports staged `Foundation`, `CoreFoundation` re-exports `Foundation`, and `CoreImage`
   re-exports `QuartzCore`. Verify after the change that `traps_effective` for these deps no longer lists them.

**Why the re-export edge is required, not merely convenient:** Chrome binds `Metal/_OBJC_CLASS_$_MTLTextureDescriptor`.
dyld2 resolves a two-level bind against the *named* library's export list and walks its `libReExported` chain
(`ImageLoaderMachO.cpp:1690-1713`). A symbol exported only by an unrelated image in the same process would **not**
satisfy it. This is the same reason the staged `Foundation` classes do not help Chrome's `AppKit` binds.

**Ordering constraint:** the provider must be staged *before* the shims that re-export it, and the shims must be
staged before Chrome's binaries (which is already how `chrome_stage.py` works: `build_payload` → `Closure` →
`gen_stub` → `rewrite_binaries`).

## 5. Manifest staging

- The provider ships in the `work/chrome-shims` tree, which `make_chrome_manifest.py` mounts at the filesystem root.
  So the guest path is `/usr/lib/chrome/ObjCClassProvider.dylib`, matching the `LC_ID_DYLIB` the shims record.
- `make_chrome_manifest.py` asserts no case-insensitive path collision between the base manifest, the payload tree
  and the shims tree (FAT32 cannot tell the two apart). `/usr/lib/chrome/` already holds the side-shims
  (`CoreFoundation.dylib`, `Foundation.dylib`, `QuartzCore.dylib`, …), so the new name must not collide with those.
- The provider is a **new guest file** and must be adhoc-signed like every other staged image
  (`codesign --force --sign -`, then assert `flags=0x2(adhoc)` — the check that BOOT-PLAN §22 records as mandatory).
- `make_chrome_manifest.py` prunes stray `_CodeSignature` directories after the rewrite phase; the provider must be
  signed *after* that prune, or re-pruned.

## 6. Boot verification (the acceptance gate)

The plan is complete when a boot produces all four of these:

| # | check | pass criterion |
|---|---|---|
| V1 | no libobjc CORPSE | serial log contains no `libobjc` CORPSE / `objc_class::isRealized` fault at `base+0x328ee` |
| V2 | no unresolved symbols | serial log contains no `Symbol not found:` for any `_OBJC_CLASS_$_` / `_OBJC_METACLASS_$_` name |
| V3 | M1 | `Google Chrome --version` exits **rc=0** and prints a version string |
| V4 | class objects realized | the provider's classes are realized in-guest, i.e. no `inform_duplicate` warnings for the 145 names and no `Class 'X' realized twice` |

Supporting evidence to collect in the same run:
- `DYLD-IMAGE-LOADING: /usr/lib/chrome/ObjCClassProvider.dylib` in the serial log (the provider really loaded).
- Chrome's `[CHROME-STUB] class X` lines must **disappear** for the 145 names (they were the old trap constructor
  announcing itself) — their absence is direct evidence the zero-quad path is gone.
- Chrome's `DYLD-IMAGE` list must show the provider before the framework binary.

**Known non-gate:** V3 exercises the `--version` path only. That path needs `Foundation`/`CoreFoundation`/`AppKit`
classes (real, staged) and a handful of the synthesized ones. It does **not** prove that e.g. `Metal` or
`AVFoundation` classes behave — those are still empty stubs with no methods, so a Chrome code path that *calls* them
will hit an unimplemented selector. §7 covers that.

## 7. What this plan does *not* fix (and where that work lives)

The provider gives Chrome **real, realizable class objects**; it does not give them **behaviour**. The 145 synthesized
classes have empty implementations. Any Chrome code path that sends a message to one of them will fail on an
unimplemented selector — a *different* failure from the one fixed here, and one that must not be confused with a
regression.

Growing the real implementations is the existing §A work in `USERLAND-PLAN.md` (Metal 28, AVFoundation 24,
Vision 20, CoreML 5, GameController 12, CoreBluetooth 10 / IOBluetooth 8, CoreHaptics 9, …). The provider does not
change that ranking; it changes *which* failure appears first: a crash in the runtime's class lookup (now fixed)
instead of a clean "unimplemented selector" trap.

Two classes deserve a note because the runtime has special handling for them:
- `NSURLSession` / `NSURLSessionConfiguration` are trapped by **two** deps; the single shared provider is what keeps
  them one object (§3.1).
- The 5 metaclass-only names (`CAMetalLayer`, `CAOpenGLLayer`, `NSAccessibilityElement`, `NSTitlebarAccessoryViewController`,
  `ASAuthorizationController`) are each trapped by the *same* dep as their class symbol — so a single class
  definition in the provider covers both the class and its metaclass. No separate metaclass stubs are needed.

## 8. A measurement caveat worth recording

`dyld_info -fixups` and `otool -ov` **disagree** about the slot contents of the staged `Foundation` image:
`dyld_info` reports `__objc_data` binds to `libobjc/_OBJC_EHTYPE_id` / `_objc_ehtype_vtable` / `___objc_personality_v0`
where `otool -ov` prints the ordinary modern shape (`superclass _OBJC_CLASS_$_NSObject`, `cache __objc_empty_cache`).

**`otool -ov` is authoritative**, and the arithmetic settles it: `Foundation`'s `LC_DYLD_INFO_ONLY` declares
`bind_size = 1096` and `rebase_size = 5112`, but `dyld_info` reports **1979** bind rows and **9450** rebase rows from
those streams. 1979 binds cannot fit in 1096 bytes (each needs at least a `SET_SYMBOL` + `DO_BIND`, i.e. ≥2 bytes
plus the symbol name), so **`dyld_info`'s output for this image is not a faithful decode of its own bind stream**.
`otool -ov` reads the same bytes and prints the shape that also matches (a) the guest's own `libobjc.A.dylib`
`NSObject` class and (b) an Apple-built x86_64 reference. Practical consequence for this plan: **gate the provider on
`otool -ov` and on `nm -g`, not on `dyld_info -fixups` target names**, and re-verify staged `Foundation` with
`otool -ov` before relying on its 21 provided classes.

## 9. Step-by-step execution order

1. Add a provider builder to `tools/bootlab/chrome_stage.py` (new function, called from `main()` before the dep loop):
   generate `provider.m` with 145 `@interface`/`@implementation` pairs, compile with platform `clang-17` per §3.2, link
   with `-install_name /usr/lib/chrome/ObjCClassProvider.dylib`, adhoc-sign, verify per §3.4, and place it in
   `work/chrome-shims/usr/lib/chrome/ObjCClassProvider.dylib`.
2. In `gen_stub`, stop emitting `.quad 0` class/metaclass slots and the `objc_allocateClassPair` constructor for the
   145 + 5 provider-covered names; add the `-Wl,-reexport_library,<provider>` edge to the 29 ObjC-trapping deps.
3. Re-run `chrome_stage.py`; confirm in `work/chrome_plan.json` that no dep's `traps` still contains a provider-covered
   class name, and that the 22 provided names still resolve via the existing provider-edge rule.
4. Re-run `make_chrome_manifest.py`; confirm the provider appears in the manifest and that the FAT32 collision
   assertion passes.
5. Build the image, boot, and evaluate V1–V4 from §6 against the serial log.
6. Record the outcome in `BOOT-PLAN.md` §22 (the tracker) and update `USERLAND-PLAN.md` §A's ranking if the 145 names
   now show up as unimplemented-selector failures rather than a crash.

---

## 10. OUTCOME (2026-10-20) — executed; V1/V2/V4 pass, V3 open on a different defect

The plan above was executed as written. Full measurements, the gates and the boot evidence are in
**`BOOT-PLAN.md` §22.1**; the ranking change is in **`USERLAND-PLAN.md` §D**. Summary:

- **Implemented as specified.** One shared provider image (`/usr/lib/chrome/ObjCClassProvider.dylib`, 145 classes,
  145 class + 145 metaclass S-type symbols, 120,672 bytes), built by the platform `clang-17` per §3.2 and
  re-exported by all **29** ObjC-trapping deps per §4. `gen_stub` no longer emits class or metaclass slots at all
  (a class symbol reaching the stub generator is a hard error now, not a `.quad 0`), and the
  `objc_allocateClassPair` constructor is gone. The synthesis set is **computed**, not hardcoded: trapped names
  minus names a staged image exports = **145**; the 22 provided names keep resolving through the real staged
  Foundation/QuartzCore images. Trapped symbols 1,353 → 1,130 effective.
- **V1 PASS** — the `objc_class::data()`/`isRealized` fault at libobjc `base+0x328ee` is gone; the process now gets
  much further before it dies.
- **V2 PASS** — 0 × `Symbol not found:`.
- **V4 PASS** — no duplicate-class warning; 0 × `[CHROME-STUB] class X` (the old trap constructor's announcements
  are gone, exactly as §6 predicted). The provider loads: `DYLD-IMAGE-LOADING: /usr/lib/chrome/ObjCClassProvider.dylib`.
- **V3 still open, and it is NOT the class-provider path.** `Google Chrome --version` exits 139 at libobjc
  `base+0x5169` = `objc_msgSend+41`, the inline-cache load — a different fault. Two repo-side Foundation gaps that
  the fix exposed were closed on the way (Objective-C subscripting; `+[NSBundle bundleWithURL:]`); the remaining
  blocker is the trap-only **Security** family (the last stub Chrome called was `_SecTaskCreateFromSelf`), i.e.
  `USERLAND-PLAN.md` §A item 3, not this plan. No provider class appears anywhere in the failure path: the runtime
  realized 122 classes in Chrome's process and none of them was a provider class.
- **Two deltas from the plan's own text**, both from the environment moving under it: the installed Chrome
  auto-updated (155.0.8059.82 → 155.0.8059.85), so `chrome_stage.py` now derives the staged version from the
  launcher's own hardcoded framework path, re-thins the launcher when the installed one changed, and regenerates
  `work/chrome_info.plist` from the host plist; and §3.4's `dyld_info -fixups` acceptance line is superseded by
  `otool -ov` + `nm -g` (§8 already says so), because `dyld_info` does not faithfully decode staged images.
- **Reproducible gates:** `python3 tools/bootlab/verify_class_provider.py` → 6/6 PASS.
