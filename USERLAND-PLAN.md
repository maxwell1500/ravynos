# Userland completion and OS completeness — measured inventory (2026-10-19)

Scope: what this OS still needs, in two parts — (A) finishing the userland frameworks well enough to run a real
third-party app (Chrome 155.0.8059.82 as the current test case), and (B) the wider short-term vs long-term gap list.
Every number below is measured with the commands printed here; nothing is estimated. Cross-references point at the
existing trackers (`tools/bootlab/BOOT-PLAN.md`, `DARWIN24_PLAN.md`, `Libraries/Libsystem/REMEDIATION_PLAN.md`,
`tools/bootlab/PROVENANCE-PLAN.md`) so this file stays the one place that ranks work by evidence.

How it was measured:
- `work/chrome_plan.json` from `tools/bootlab/chrome_stage.py` — 67 dependency edges, **1,353 trapped symbols** total,
  of which **53 trap-only families carry 991 symbols** (no implementation anywhere: repo source nor SDK binary).
- `Developer/ravynOS.sdk` vs `${RAVYN_BUILD_DIR}/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk`:
  15 framework trees built; sizes separate real implementations from stubs — Onyx2D 3,553,848 B, CoreFoundation
  2,654,696 B, AppKit 2,531,304 B, Foundation 2,289,568 B are substantial; CoreGraphics 123,536 B, LaunchServices
  87,096 B, CoreText 23,560 B, IOSurface 21,720 B, CoreServices 4,480 B, System 43 B are thin.
- `tools/bootlab/manifest_gui.json`: 297 file entries + 14 dirs staged; **12 framework families** at their install
  paths (AppKit, Cocoa, CoreData, CoreFoundation, CoreGraphics, CoreServices, CoreText, Foundation, IOSurface,
  LaunchServices, Onyx2D, QuartzCore, plus PreferencePanes) and **38 `usr/lib` entries** (dyld, libSystem.B,
  libedit/expat/fontconfig/icucore/icudata/jansson/sqlite3 and 28 `usr/lib/system/*` members).

## A. Getting the frameworks over the line for Chrome

The previous "wall" claim was wrong and is corrected in BOOT-PLAN.md §22: `nm -gU` lists *undefined* globals only, so
it reported zero ObjC class exports for both CoreFoundation and Foundation. Plain `nm -g` on the staged Foundation
dylib shows it defines `_OBJC_CLASS_$_NSArray / _NSDictionary / _NSData / _NSDate / _NSSet / _NSURL / _NSUserDefaults`,
`_OBJC_EHTYPE_$_NSException`, `_OBJC_METACLASS_$_NSInputStream` — 642 ObjC class refs total. **24 of CoreFoundation's
51 trapped names are already implemented in this repo, inside Foundation**, reached on real macOS through
CoreFoundation's own REEXPORT edge to Foundation. `chrome_stage.py` now encodes that rule (drop our stub for any name
another staged image defines, and link `-Wl,-reexport_library,<that image>`; the `-Wl,-reexport-l<stem>` spelling I
tried first silently does nothing). Frameworks/CoreFoundation itself is still pure C, so the edge must point at
Foundation, not CF — attribution decides the target.

Two staging rules this session had to learn from real dyld failures, both now in `chrome_stage.py`:

- **Weak load commands still need an image.** Chrome's framework weak-links SkyLight
  (`/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight`) and ScreenCaptureKit; the guest's staged
  dyld2 printed "could not find image <path>" for exactly those two and then rc=139. Only *weak import symbols* may stay
  unresolved -- the image itself must exist, so `parse_lcs` now matches LC_LOAD_WEAK_DYLIB and those deps get trap-only
  stubs like every other absent dep (no repo sources exist for either family).
- **A trapped name that another staged dylib defines is a provider edge, not a stub.** Six closures fired: CoreFoundation
  24 names (`_OBJC_CLASS_$_NSArray/_NSDictionary/_NSData/...`, `_OBJC_EHTYPE_$_NSException`) from Foundation/AppKit/Onyx2D,
  libSystem side-shim 39 (`__Unwind_*`, `___NSGetExecutablePath`), CFNetwork 3 (`_OBJC_CLASS_$_NSHTTPURLResponse/...`),
  CoreVideo 3, CoreImage 1 (`_OBJC_CLASS_$_CIImage`), CoreServices 1 (`_LSRegisterURL`) -- **71 trap slots replaced by
  re-export edges**; the CoreFoundation shim now carries LC_REEXPORT_DYLIB to Foundation, AppKit and Onyx2D and defines
  29 names instead of 51.

Ordering that follows the numbers, not taste:

1. **In-repo frameworks to build first** (`tools/bootlab/build-libraries.sh --frameworks <Name>`; sources exist in
   `Frameworks/`): Security 131 trapped symbols, IOKit 78, CoreVideo 75, ApplicationServices 73, SystemConfiguration
   36, CFNetwork 17, plus OpenDirectory 12 and OpenGL (Accelerate 12). These are decision-rule 1 of the push loop: a
   built dylib becomes the real target and its shim re-exports it, so trap counts fall.
2. **Grow the existing real implementations** rather than stub them: AppKit still traps 98 names, CoreText 59,
   CoreGraphics 56, Foundation 28, libSystem side-shim 19 — all five have repo sources with ObjC bodies (AppKit 255
   `.m`, Foundation 299 `@implementation`s), so their missing surface is unfinished code, not absent code. CoreGraphics
   at 123 KB vs AppKit at 2.5 MB shows how much is missing.
3. **Families with no source in this repo at all** (new code or trim the app): Metal 28, DiskArbitration 28, Carbon 25,
   AVFoundation 24, Network 22, CoreMIDI 22, Vision 20, libcups.2 51, VideoToolbox 52, CoreMedia 55, AudioToolbox 13 /
   CoreAudio 16 / AVFAudio 5 / AudioUnit 12, GameController 12, CoreBluetooth 10 / IOBluetooth 8, CoreHaptics 9 /
   ForceFeedback 9, CoreML 5, CoreWLAN/CoreMediaIO/CoreLocation/ServiceManagement/SafariServices/CryptoTokenKit/
   LocalAuthentication*/Accessibility/SecurityInterface ≤ 1 each, libresolv 3, libbz2 3, libbsm 2, libsandbox 6,
   pmenergy/pmenergy 0. Chrome links all of them unconditionally, so dyld needs *images* for every one (the trap-only
   stubs already satisfy that) — the question is which symbols sit on the startup path.
4. **Startup-path gate**: `--version` must print before any window exists; it needs CF/Foundation/AppKit/CoreText class
   and text paths only. The GPU/Media/Network families can stay trap-backed until M2/M3 ask for them.

## B. Short term (blocks the next milestone or the current desktop)

- **libSystem load closure unverified** — `Libraries/Libsystem/REMEDIATION_PLAN.md` B0 calls this "THE ACTUAL BOOT
  BLOCKER": the BUILD is reproducible but the LOAD graph was never proven complete; our libSystem side-shim still traps
  19 names for Chrome. Verify by resolving every staged Mach-O's imports against the staged image, not by eye.
- **libsystem_kernel blocked on two independent things** (same file, §"blocked on TWO"): finish both, then the umbrella
  re-export chain closes and per-dep shims shrink.
- **Shell/tool surface**: base manifest stages 38 `usr/lib` entries and a small `/bin`; earlier sections record real gaps
  found by use — no `[` builtin in the staged shell (`/bin/test` instead), `bin/sleep` added via
  `tools/bootlab/build_dynutils.sh`. Enumerate by running the app set and diffing missing commands, not by guessing.
- **Only one third-party-style bundle exercised so far**: Chrome's `.app` is staged with its whole framework tree; Dock,
  Filer, Terminal, SystemUIServer, WindowServer are repo-built apps. Anything expecting Apple's service daemons
  (only `com.ravynos.WindowServer.json` + LaunchServices are staged) has nothing to talk to.
- **No network/audio/printing path** in the staged image: Network/CFNetwork/libresolv/libcups families are trap-only, so
  any app that dials out or prints dies at those stubs — visible as `[CHROME-STUB]` lines, which is evidence, not a
  crash cause until control flow depends on the return value.

## C. Long term (structural, not fixable by adding one symbol)

- **Driver model**: compiled-in kexts only (`Kernel/Extensions/Makefile` SUBDIR: AppleFileSystemDriver, RavynAHCIPort,
  IOGOPFramebuffer renamed from IOGraphics). BOOT-PLAN §18 lists three routes for real hardware and notes the set of
  ports is unbounded; the Linux-driver API shim (`linuxkpi` precedent) plus the in-tree `Frameworks/OpenGL/libdrm`
  headers are the cheapest wedge.
- **GPU/compositing**: Onyx2D + IOGOPFramebuffer give software compositing; Metal/Accelerate/VideoToolbox families are
  trap-only, so GPU-backed Chrome (and any GL client beyond the stub GL renderers already recorded as "no working
  OpenGL renderer") needs a real graphics stack — the long pole, and the reason push-loop wall class (c) exists.
- **Security model de-permissiving** (`DARWIN24_PLAN.md` Phase 5): Security 131 / AuthenticationServices 14 /
  LocalAuthentication / CryptoTokenKit traps are all one family of unfinished policy work.
- **Process/services parity** (`DARWIN24_PLAN.md` Phases 2–6): fork/exec + console, real launchd + single-user, storage/
  filesystems + Mach services surface, multi-CPU/timers — each is its own milestone, already tracked there.
- **Legal/provenance debt**: `tools/bootlab/PROVENANCE-PLAN.md` P0 (clean manifest) and P1 (host-extracted purge to
  `assets-quarantine/`) are marked CLOSED/EXECUTED 2026-10-02; keep new binaries repo-built or host-free so the policy
  stays enforced by `.gitignore` rather than review.
- **Toolchain fragility**: `Libraries/Libsystem` and friends need bmake + the platform clang-17 (host clang 21 segfaults
  on this tree's ObjC, documented in `build-libraries.sh` header); a missing toolchain binary silently selects the host
  compiler (BOOT-PLAN §16 "Toolchain selection"). Pin it before adding more ObjC frameworks.

## D. The class-provider fix changed what the failures MEAN (2026-10-20)

Chrome's `__objc_classrefs` used to bind to zero-quad data slots, and the guest runtime died dereferencing
them (`objc_class::isRealized()`, libobjc `base+0x328ee`). Those slots are gone: the 145 class names Chrome
binds and no staged image provides are now REAL modern-ABI classes in one shared image
(`/usr/lib/chrome/ObjCClassProvider.dylib`, 145 class + 145 metaclass symbols, all S-type), re-exported by all
29 Objective-C-trapping dependencies because Chrome's binds are library-scoped. Details and the measured gates
are in `tools/bootlab/BOOT-PLAN.md` §22.1; the static gate script is
`tools/bootlab/verify_class_provider.py` (6/6 PASS).

What that changes for THIS file's ranking:

- **§A item 1 (the provider-edge rule) is DONE and is now a class-provider rule too.** Trapped symbols fell
  1,353 → 1,130 effective; the 223 class/metaclass slots became re-export edges instead of stubs. The 22 names
  staged Foundation/QuartzCore really define keep resolving through the real images — they are deliberately
  not redefined, because two class objects with one name make the runtime warn and keep the older mapping.
- **The failure mode moved from "the runtime crashes" to "the repo's frameworks do not implement what Chrome
  calls".** That is a *better* failure — it is diagnosable and it is this file's work — but it means §A's
  numbers below are now the binding constraint on Chrome, not the packaging.
- **Two gaps the fix exposed are already closed in the repo** (standard macOS API, both added to
  `Frameworks/Foundation`): Objective-C subscripting (`objectForKeyedSubscript:`,
  `setObject:forKeyedSubscript:`, `objectAtIndexedSubscript:`, `setObject:atIndexedSubscript:`) and
  `+[NSBundle bundleWithURL:]`. Before them Chrome died with
  `-[NSDictionary_mapTable objectForKeyedSubscript:]: unrecognized selector`; that abort is gone.
- **The next blocker is §A item 3's top entry: the trap-only Security family.** The last stub Chrome called
  before it died was `_SecTaskCreateFromSelf` (Security: 131 trapped symbols, no repo source), and the crash
  is now in the runtime's inline-cache fast path rather than in class lookup. Nothing in that path involves the
  provider: the runtime realized 122 classes in Chrome's process and none of them was a provider class.
- **The provider's own classes are still behaviourless**, exactly as planned: any Chrome path that messages one
  of the 145 hits an unimplemented selector. That is §A's item 2/3 work (Metal 28, AVFoundation 24, Vision 20,
  CoreML 5, GameController 12, CoreBluetooth 10 / IOBluetooth 8, CoreHaptics 9) and the provider does not change
  that ranking — it changes which failure arrives first.

## Next actions, ranked by measured cost/benefit

1. **Implement enough of Security for Chrome's startup path** (`SecTask*`, then whatever the next stubbed call
   names): it is now the first thing Chrome's `--version` path hits, it is 131 trapped symbols with no repo
   source, and a trap that returns 0 where the real API returns an object is what the current crash follows.
   Keep `--version` as the regression check — it is the only measured end-to-end gate.
2. `build-libraries.sh --frameworks Security IOKit ApplicationServices SystemConfiguration CoreVideo CFNetwork OpenGL`
   one at a time, re-staging after each success (record failures; do not stall).
3. Grow AppKit/CoreText/CoreGraphics surfaces against their trapped-name lists (largest in-repo counts: 98/59/56).
4. Close libSystem B0/B1 in REMEDIATION_PLAN so the umbrella graph stops needing per-dep stubs.
5. Re-measure §A's counts after each of the above: `tools/bootlab/chrome_stage.py` now reports
   `traps` and `traps_effective` separately, and a dep whose `traps_effective` still contains a
   `_OBJC_CLASS_$_`/`_OBJC_METACLASS_$_` name is a bug in the provider-edge rule, not a missing symbol.

## E. Objective-C Block Runtime & Desktop Fleet Gate Completion (2026-10-25)

The Objective-C block runtime on x86_64 Darwin 24 is now fully operational and verified:
- Block classes (`__NSStackBlock__`, `__NSMallocBlock__`, `__NSGlobalBlock__`, etc.) are constructed in-place at the exported `_NSConcrete*Block` storage symbols in `libsystem_blocks` using `objc_initializeClassPair` and registered via `objc_registerClassPair`.
- `copy`, `copyWithZone:`, `retain`, `release`, `autorelease`, and `retainCount` are wired with standard reference counting semantics.
- Direct binding: `_Block_object_assign` and `_Block_object_dispose` are resolved directly from `libSystem` via `-L${RAVYN_SDKROOT}/usr/lib/system` in `CoreServices/dailydrivertest/Makefile`.
- Verified in guest: `Objective-C blocks execute and support copy/release` passes cleanly with 0 crashes.
- Global screen capture (`kWSRequestCapture`, Cmd+Shift+3/4/5) and window picking (`kWSDragHitTest`) are implemented and verified.
- Daily-driver verification gate: 91/91 checks pass, 0 CORPSE, 0 uncaught exceptions, all 14 fleet application screenshots verified frontmost.

## F. Application Intake & Source Porting (2026-10-26)

Two permanent intake tracks replace hand-writing applications. Both are verified end-to-end in the guest by
`verify_daily_driver.py --all --boot` (100 checks, 0 failed), and each proof target writes its own PASS line
that the gate reads back out of the image.

### F1. SDK sysroot, cross-toolchain, CMake, pkg-config
- `tools/bootlab/sync_sdk.py` makes `Developer/ravynOS.sdk` self-contained: `/usr/lib/system/*`, `libobjc`,
  `libz`, `libc++`, `libedit`, the Onyx2D static archives (freetype, libpng16, libjpeg, libtiff), public
  headers for zlib/expat/sqlite3/fontconfig/freetype2/libpng/libjpeg/libtiff, Linux userland shims
  (`sys/endian.h`, `byteswap.h`, `sys/epoll.h`, `sys/eventfd.h`, `linux/input*.h`), and `usr/lib/pkgconfig/*.pc`.
  It runs at the end of `build-libraries.sh` and standalone. CoreServices and LaunchServices are copied from the
  build-tree SDK so the image manifest stays repo-relative.
- `tools/sdk/bin/{ravynos-cc,ravynos-c++,ravynos-pkg-config,sdl2-config}` are standalone wrappers usable from
  any source tree, `./configure`, or CMake. `ravynos-c++` links `libc++.a`/`libc++abi.a` directly because the
  SDK's `libc++.1.dylib` is a zero-byte stub.
- `Developer/cmake/ravynos.toolchain.cmake` plus the `Version/Paths/Tools/framework` modules that
  `PrivateFrameworks/CMakeLists.txt` already included but did not have.
- `SDKSettings.json` now reports 15.0, matching `SDKSettings.plist`.

### F2. SDL2.framework (2.32.10 ABI) on AppKit/Onyx2D
`Frameworks/SDL2` implements the SDL 2.32 C ABI against `NSWindow` + the window's Onyx2D shared-memory surface:
core/error/hints/log, video/window/display, surfaces and blits, a software 2D renderer, events/keyboard/mouse/
clipboard, timers/threads/sync/RWops/dlfcn, and a pacing audio backend. Device subsystems (joystick, game
controller, sensor, haptic) are generated from the public headers by `tools/bootlab/gen_sdl_device_stubs.py`,
so the entry points exist with exactly the declared signatures instead of drifting by hand.

Two AppKit findings that came out of building it, both fixed at the source:
- `-[NSEvent isARepeat]` had an ivar and no accessor; it is now declared and implemented.
- A process that drives its own event loop must call `-[NSApplication finishLaunching]` before ordering a
  window, and a *titled* window's ordering pass (NSThemeFrame display) does not complete for such a process:
  the window appears and the process stops inside `-orderFront:`. Borderless windows work. SDL2 therefore
  creates borderless windows for its own surfaces, and the limitation is recorded here rather than papered over.

### F3. The six macOS runtime frameworks
`Security`, `IOKit`, `CoreVideo`, `SystemConfiguration`, `CFNetwork` and `ApplicationServices` are real
framework dylibs in the SDK, built by `build-libraries.sh --frameworks` (now in the default list).
Each declares only what it implements, so a missing facility fails to compile instead of returning a plausible
zero at run time:
- **Security**: SecTask entitlements/signing identity, SecCode/SecStaticCode/SecRequirement, SecItem on a
  process-local generic-password store, SecTrust/SecPolicy, SecRandomCopyBytes, Authorization. No keychain
  daemon, so `SecItemCopyMatching` reports `errSecItemNotFound` and entitlements are honestly absent.
- **IOKit**: registry iteration and notification with an empty registry (a valid empty iterator, never a
  bogus handle), IOServiceOpen/IOConnect*, power assertions, plus the IOFireWire/IOUSB/IONetwork plugin headers.
- **CoreVideo**: CVBuffer/CVPixelBuffer/PixelBufferPool as CF objects with real storage, and CVDisplayLink.
- **SystemConfiguration**: a dynamic store with a process-local backing dictionary (set/copy round-trips),
  SCPreferences, and `SCNetworkReachabilityGetFlags` answered by a real UDP route lookup.
- **CFNetwork**: proxy settings and `CFNetworkCopyProxiesForURL`, `CFHost` resolution through `getaddrinfo`,
  and `CFHTTPMessage` request/response building and parsing.
- **ApplicationServices**: Process Manager identity/foregrounding, accessibility (reports "not trusted"),
  PrintCore and HIShape stubs.
- `BSD/share/mk/rvn.framework.mk` now defaults `-compatibility_version`/`-current_version`, copies resource
  *directories* as well as files, and accepts `INCS`/`RESOURCES` spellings. Every framework an imported
  application links carries at least Apple's compatibility version (AppKit 45.0.0, CoreVideo 1.2.0, the rest
  1.0.0) -- dyld refuses to load an image whose library reports a lower one, and most of the tree reported 0.0.0.

### F4. Generic macOS bundle intake
`tools/bootlab/app_stage.py` generalizes `chrome_stage.py`: it reads `CFBundleExecutable` instead of assuming
the bundle name, parses `LC_RPATH` and resolves `@rpath/`, `@executable_path/` and `@loader_path/`
dependencies, flattens framework symlinks onto the file they point at, thins to x86_64, ad-hoc signs, rewrites
load commands, and emits flat manifest entries. A dependency neither the bundle nor the SDK can satisfy is
reported as a failure rather than silently staged as a trap. `--dry-run` on `/Applications/Transmission.app`
resolves the real bundle's frameworks and names its genuine gaps (libc++, UserNotifications, Carbon, WebKit).

Bundle-launch bugs fixed for imported applications:
- `NSBundle -lookInDirectories` now searches `Base.lproj` first; without it a nib built by any current Xcode is
  not found and the application starts with no menu bar.
- `NSNib` accepts `keyedobjects-110000.nib` and `keyedobjects-101300.nib`, not only the unversioned name.
- `Filer` opens bundles through `WindowServer` (`openBundlePath:`), so the child inherits launchd's bootstrap
  context; the fork/exec fallback now passes the environment instead of an empty one.
- `AppKit.framework/Versions/C` exists as an install-time alias of `A`, because every prebuilt macOS binary
  records AppKit at `Versions/C`.

Proof target: `tools/bootlab/host-macos-app` compiles `MacOSIntakeProbe.app` with the *host* macOS SDK,
linking `@rpath/MacIntakeCore.dylib` through `LC_RPATH @executable_path/../Frameworks` and the real
Security/IOKit/CoreVideo/SystemConfiguration/CFNetwork/ApplicationServices/Cocoa frameworks. Staged by
`app_stage.py`, it launches, resolves the rpath dylib, exercises all seven frameworks and writes
`PASS macos-intake: rpath=1 sec=1 iokit=1 cv=1 sc=1 cfnet=1 apps=1`.

### F5. Source porting
`tools/ports/build_port.py` builds a port from its own build system (cmake, autotools or make) against the SDK,
strips, signs, and packages the result as an `.app`. `tools/ports/sdl2-blocks` is an ordinary CMake + pkg-config
SDL2 program with no ravynOS-specific code; it builds with `cmake --toolchain ravynos.toolchain.cmake`, finds
SDL2 and zlib through `ravynos-pkg-config`, and in the guest creates a 640x480 window, renders a block grid
through the software renderer, presents three frames and writes
`PASS sdl2-port: video=ravynOS renderer=software surface=640x480 zlib=1.3.2`.
