# Firefox blockers (Phase 4)

One line per blocker: what fails, the measurement, and the fix. Firefox is the
compatibility oracle, so the fix never lands in the bundle.

## 4.1 Staging — done, but opt-in

- Acquired `tests/apps/Firefox ESR.app`, version **115.15.0esr**, Mozilla's own
  build, `LSMinimumSystemVersion 10.12.0`, universal (x86_64 + arm64). This is
  the ESR 115 line the plan names as the last 10.13-compatible build; the
  installed `/Applications/Firefox.app` on the development host is 159.0 with a
  10.15 minimum and was rejected for that reason.
- Bundle contents are staged verbatim — no patch, no re-sign, no strip, no
  thinning of the arm64 slices.
- Staging is behind `RAVYN_FIREFOX=1` in `tools/bootlab/make_gui_manifest.py`
  because the bundle is 367 MB, which does not fit the 512 MiB template, and a
  grown image currently exposes the guest bug below. A default build records
  `not staged (set RAVYN_FIREFOX=1 to include)` rather than `MISSING`, so the
  closure gate stays meaningful for both modes.

## Blocker: a grown image loses every file the guest writes

Measured on a 1 GiB image built with `mkimage.py --size-mib 1024`:

- The desktop comes up (`PRESENT front=com.ravynos.Filer` appears 7 times) and
  the compat job spawns (`SPAWN: exec=/bin/sh argv0=/bin/sh`), and
  `CocoaProbe` is launched by the runner.
- Every file the guest creates is present in the directory but **zero bytes**:
  `/var/log/SYSTEM.LOG` 0, `/var/log/WS-APPS.LOG` 0, `/var/log/COMPAT.LOG` 0.
  Because the runner's output goes to `compat.log`, `verify_compat.py` sees no
  report and the whole suite reports FAIL even though the programs ran.
- `mkimage.py` itself writes the same files correctly at 512 MiB, so this is the
  guest's FAT driver, not the image builder: at 1 GiB the FAT is 2040 sectors per
  copy and the data area starts at 0x302000, both derived from the BPB the guest
  already trusts for reading (the desktop's binaries load fine).

Next measurement: have the guest create a small file and read it back in the
same boot, then compare the FAT entry the guest wrote with the one `fat32img.py`
sees; the zero length points at the directory-entry update rather than at data
allocation. The reader side is already fixed — `fat32img.Fat32Img` used to
assume the 512 MiB geometry for any image and now derives it from the file size
(without that, every `read_path()` on a grown image returned None).

## First launch, measured

A `launchd` job (`com.ravynos.firefoxtest`) starts
`/Applications/Firefox.app/Contents/MacOS/firefox -CreateProfile ...` with
`RAVYN_DYLD_DIAG=1` and `HOME` inside the image. Result, from the serial log:

- dyld loads the bundle's own `libmozglue.dylib` from `@rpath`, then
  CoreFoundation, libc++.1, libSystem.B, libsystem_kernel/_c/malloc, libdyld,
  libicucore, libobjc and libicudata. A 367 MB universal Mozilla build is
  therefore being mapped by our loader, not rejected up front.
- The process then dies with SIGSEGV, `rc=139`, with **no dyld diagnostic at
  all**: `rip = libmozglue + 0x16168`, `fault = 0`. `nm` puts 0x16168 inside
  `_free` (0x160f0), which is mozjemalloc's zone free; the instruction is
  `movq (%rdx), %rcx` after masking the pointer to a 1 MiB page and indexing
  the page's arena table, i.e. jemalloc tried to free a pointer it does not
  own. The candidate is `find_registered_zone()` in
  `Libraries/Libsystem/libsystem_malloc/malloc.c`: it asks every registered
  zone `zone->size(zone, ptr)` in turn, so a zone whose `size()` does not
  reject foreign pointers will claim one and then fault in its `free`.
- The same crash happens for `-CreateProfile`, so it is before any window or
  profile work, not a UI problem.

Blocker 1: zone ownership dispatch in `free()`.
Blocker 2: the image cannot write at all (below), so even a surviving
Firefox could not create a profile.

## The image cannot write — fixed

Root cause was not msdosfs. `Kernel/xnu/bsd/dev/i386/ahci_block.c` answered
`DKIOCGETBLOCKCOUNT` with hardcoded template numbers (disk0 1 048 576 sectors,
disk0s1 1 044 480) and offset disk0s1 by a hardcoded LBA 2048. On a 1 GiB image
the real volume is 2 093 056 sectors, so msdosfs mounted with:

    msdosfs_mount: device sector count (1044480) is less than volume sector
    count (2093056); limiting maximum cluster to 130047 (was 261119)

The first free cluster in an mkimage-built volume is around 141 380, i.e. above
the capped maximum, so every allocation returned `ENOSPC` and every guest file
stayed a zero-byte directory entry. Fixed by parsing the disk's GPT at attach:

    AHCI: GPT partition at LBA 2048, 2093056 sectors; disk 2097152 sectors

Proof after the fix, from a boot that then shut down cleanly:
`/var/tmp/WTEST.TXT` is 6 bytes and contains `hello\n`; `/var/tmp/FF` exists as
a directory; the msdosfs "limiting maximum cluster" warning is gone.

## Blocker 1 — solved: flat binding sent libobjc's free() to jemalloc

The crash was not zone dispatch. libmozglue exports `malloc`/`free`, and it is
loaded before libSystem because it is the application's own dependency. Our
in-tree `libobjc.dylib` was linked with no `LC_LOAD_DYLIB` commands at all
(`otool -L` lists only its own install name), so its undefined symbols carry
flat-lookup ordinals. Flat lookup searched images in load order, found
libmozglue's `_free` first, and libobjc freed its own pointer through
jemalloc's destructor — the fault at `libmozglue + 0x16168`, fault 0.

Fixed in `Libraries/dyld/src/ImageLoaderMachOCompressed.cpp`: when the image
asking is itself a system library (`/usr/lib/...` or `/System/Library/...`),
resolve flat symbols against system images first
(`flatFindExportedSymbolInSystem` in `dyld2.cpp`), then fall back to the normal
flat search. An application dylib loaded earlier can no longer capture a libc
symbol from a system library.

Measured after the fix: the crash moved out of jemalloc entirely. Firefox now
reaches the ObjC runtime:

    rip 0x1080ec15d = libobjc + 0x515d = objc_msgSend + 0x1d
    fault 0x18, rdi 0x107651b68

`objc_msgSend + 0x1d` is `andl 0x18(%r10), %r11d`, the isa fast path — the
receiver's `isa` is not a class pointer. The frames below it are
CoreFoundation (`0x1074bb000-0x107642000`), so a CF object whose isa should
name `__NSCFConstantString` (a class pointer stored in CF's `__DATA` and
rebased/bound by dyld) is dispatching through a null or junk isa.

## Blocker 2 — solved: constant CFStrings were ObjC-messaged with isa 0

`objc_msgSend+0x1d` with `fault 0x18` and `rdi->[0] == 0` inside
`_parseXMLElement` was a CoreFoundation bug, not a Firefox one:

- `CFRetain()`/`CFRelease()` decide "ObjC object" with `CFTYPE_IS_OBJC()` and
  then with `_cfinfo[CF_INFO_BITS] == 0`. `CFTYPE_IS_OBJC` compares the
  object's first word (its isa) with `__CFRuntimeObjCClassTable[...]`, which is
  all zeroes until Foundation installs the toll-free bridging classes — so a
  static CF object with isa 0 compared equal to entry 0 and was messaged.
- The XML parser calls `CFRetain(kCFBooleanTrue)` for `<true/>`; that static's
  info bits only become nonzero once `CFBooleanGetTypeID()` has run, and
  Firefox parses its plist before Foundation exists to initialize anything.
- The parser now calls `CFBooleanGetTypeID()` before retaining the boolean, and
  `CFTYPE_IS_OBJC` plus both `_cfinfo == 0` tests refuse to message an object
  whose isa is 0 (no class lives at address 0).

Result: `rc=139` became `rc=255` with an actual loader diagnostic. Firefox now
loads NSS (`libnss3.dylib`, `liblgpllibs.dylib`) and reaches XPCOM loading.

## Blocker 3 — missing frameworks, one at a time

`XUL` cannot be `dlopen`ed because its dependencies are not all present:

    dlopen(.../XUL, 265): Library not loaded:
      /System/Library/Frameworks/IOSurface.framework/Versions/A/IOSurface
      Referenced from: XUL. Reason: image not found
    Couldn't load XPCOM.

IOSurface was in the tree but not staged; it is staged now. dyld names the
next missing framework in load order each run, so this is a stepping loop.
`otool -L XUL` names the whole set up front; 17 are still absent:

    AVFoundation  AddressBook  AudioToolbox  AudioUnit  Carbon  CoreAudio
    CoreLocation  CoreMIDI  CoreMedia  ImageIO  LocalAuthentication
    MediaPlayer  Metal  OpenGL  ServiceManagement  VideoToolbox  Vision

Audio is the next one dyld asks for. Per plan 4.3(e) audio is out of scope
until Phase 8.1, so the frameworks must exist with honest "unavailable"
behavior rather than fake success.

## Next measurement

Stage the next named framework and read the next line. The library that dyld
reports is authoritative; `otool -L` only gives the eventual set.

## Progress through the loader (this round)

Every library XUL records now loads. The failures are per-symbol, and each
fix below is in the framework that owns the symbol, never in the bundle:

| measure | before | now |
|---|---|---|
| distinct unresolved symbols in the staged bundle | 647 | 378 |
| missing dylibs named by dyld | 18 | 0 |

- **16 compatibility frameworks** built from the symbols the bundle actually
  imports (measured against the SDK's `.tbd` exports): AVFoundation, Carbon,
  AudioUnit, CoreAudio, AudioToolbox, CoreMedia, CoreMIDI, ServiceManagement,
  VideoToolbox, ImageIO, AddressBook, CoreLocation, MediaPlayer, Metal,
  Vision, plus ObjC `LocalAuthentication` with a real `LAContext` that answers
  "Touch ID is not available". Private frameworks `CoreUI` (CUIDraw) and
  `CoreSymbolication` exist as well.
- **IOSurface**: `IOSurfaceLookup` (NULL -- no surface registry),
  `IOSurfaceGetPropertyMaximum` (0 -- no known maximum) and a real
  `kIOSurfaceIsGlobal` CFString property key.
- **Security**: `SecCertificateCopyPublicKey`, `SecIdentityCopyCertificate`,
  `SecIdentityCopyPrivateKey`, `SecIdentityCopyPreferred` (all NULL -- no
  keychain/identity support) and 17 key/algorithm constants.
- **Foundation**: `NSProgressKindFile` and the file-operation keys,
  `NSUserActivityTypeBrowsingWeb`, `NSUserNotificationDefaultSoundName`,
  `NSFileGroupOwnerAccountID`.
- **AppKit**: 23 accessibility, appearance, speech and notification constants.

Current symbol: `_OBJC_CLASS_$_NSAppleEventDescriptor` -- Foundation has no
Apple Events class. Next in line, by the same measurement: the remaining data
symbols in CoreText (29), CoreGraphics (22), CoreServices (12), CoreVideo (9),
SystemConfiguration (4), QuartzCore (1), CoreFoundation (3), and then the
lazily-bound functions those frameworks do not implement yet.

The loop is mechanical: `closure_gate.py` lists every unresolved symbol before
a boot; dyld names the one that blocks loading now. Both agree because the
gate reads the same manifest the image was built from.

## Load-time symbol work, continued

After the libraries existed, dyld moved to symbols. Every fix is in the
framework dyld names in "Expected in:", never in the bundle:

- **AppKit / Foundation / AVFoundation / QuartzCore / CoreLocation /
  MediaPlayer / Vision**: 37 Objective-C classes that XUL binds eagerly
  (`_OBJC_CLASS_$_...`), each declared with its documented superclass so
  type checks behave. `NSVisualEffectView` is an `NSView`,
  `NSTitlebarAccessoryViewController` is an `NSViewController`.
- **AppKit**: 23 accessibility/appearance/speech constants.
- **Foundation**: `NSProgressKindFile` and file-operation keys,
  `NSUserActivityTypeBrowsingWeb`, `NSUserNotificationDefaultSoundName`,
  `NSFileGroupOwnerAccountID`.
- **CoreFoundation**, which on macOS exports a large block of NS* constants
  and is what XUL's bindings name: `NSDefaultRunLoopMode`,
  `NSRunLoopCommonModes`, the fourteen `NS*Exception` names, nineteen
  `NSLocale*` keys, `NSSystemTimeZoneDidChangeNotification`.
- **IOSurface / Security**: see above.

The loop is now: boot, read the one line dyld prints, add the symbol to the
named library, rebuild that framework, rebind the image. Each cycle is a few
minutes and every cycle moves the failure later.

Current line:

    Symbol not found: _OBJC_EHTYPE_$_NSException
    Expected in: /System/Library/Frameworks/CoreFoundation.framework/...

`NSException`'s EH type is defined in Foundation today (`nm` shows
`_OBJC_EHTYPE_$_NSException D`), but XUL's two-level binding asks
CoreFoundation for it, so CF must export an EH type for the same class. The
clean way is one Objective-C translation unit in CoreFoundation whose
`@catch (NSException *)` makes the linker emit the EH type there, with the
class reference resolved flat (dyld already prefers system images for system
libraries). Defining a bare data symbol would let XUL load but would break
exception matching, so it is not an option.

## Milestone: XUL loads and runs

After the loader surface was completed (frameworks, classes, constants, EH
type, empty-collection singletons), dyld resolves every symbol XUL references.
The proof is in the log: no "Symbol not found", and dyld's class substitution
lines show every CF-bridged class resolved from Foundation:

    dyld: _OBJC_CLASS_$_NSData not in CoreFoundation; using Foundation
    dyld: _OBJC_CLASS_$_NSDictionary not in CoreFoundation; using Foundation
    ... NSLocale, NSMutableArray, NSRunLoop, NSTimer, NSURL, NSUserDefaults ...

Firefox now starts executing. `-CreateProfile` exits 139 (SIGSEGV) at runtime,
not at load:

    rip 0x1020dd4f2  fault 0
    rdi->[0] 0x56415741e5894855

That qword is a function prologue (`push %rbp; mov %rsp,%rbp; push %r15`),
so an Objective-C message is being sent to a pointer to code rather than to an
object.  The frame chain crosses three images, one of them a large bundle
mapping.  This is the first Firefox runtime bug, and the next measurement is
to symbolicate the three frames against the DYLD-IMAGE bases (the same
technique that found the jemalloc and CoreFoundation bugs).

Everything up to this point is loader/compat work in ravynOS's own libraries:
no Firefox bundle file was modified, re-signed or rebuilt.

## Blocker 4 — CFURLEnumerator crashed while enumerating a directory

`-CreateProfile` exited 139 with

    frame[0] libsystem_c  _readdir$INODE64 + 0x19
    frame[1] CoreFoundation _CFURLEnumeratorGetNextURL + 0x1a4

`readdir()` locks `dirp + 0x40`, so this is a NULL DIR*: `opendir()` had failed
(permission or missing directory) and the enumerator called `readdir(NULL)`.
While fixing that, a second bug in the same function surfaced: it had **no
return statement at the end**, so a successful call returned whatever was in
the return register. Both are fixed in
`Frameworks/CoreFoundation/CFURLEnumerator.c`: a NULL `_dirp` returns
`kCFURLEnumeratorError`, end-of-directory returns `kCFURLEnumeratorEnd`, and
success returns `kCFURLEnumeratorSuccess`.

## Blocker 5 — running as root, then the next lazy symbol

With the crash gone, Firefox ran its startup and exited cleanly with its own
message:

    Running Firefox as root in a regular user's session is not supported.
    ($HOME is /var/tmp/ff which is owned by uid 99.)

launchd's `UserName` key does not drop privileges in this tree yet, so the job
now uses a small `runas <uid> <gid> <program>` helper (tests/compat/runas.c,
staged at /usr/local/compat/runas) and runs the browser as `ravyn` (501/20).
The corpse audit confirms it: `val=[... 501 20 501 20 ...]`.

Firefox then executed far enough to reach its own startup functions (the
backtrace names XUL frames) and aborted on the next missing lazy binding:

    dyld: lazy symbol binding failed: Symbol not found: _FSFindFolder
    Referenced from: XUL
    Expected in: /System/Library/Frameworks/CoreServices.framework/...

That is the Carbon File Manager API (`FSFindFolder`, `FSPathMakeRef`,
`FSRefMakePath`, `FSGetCatalogInfo`, ...), which CoreServices stubs today.
Lazy bindings are the right kind of failure: the loader is done, and each one
names exactly which framework function Firefox actually used.

## Blocker 6 — Carbon File Manager

With the loader work done, XUL's next lazy binding was

    Symbol not found: _FSFindFolder
    Expected in: /System/Library/Frameworks/CoreServices.framework/...

`Frameworks/CoreServices/FileManagerCompat.c` now implements `FSFindFolder`,
`FSPathMakeRef`, `FSPathMakeRefWithOptions` and `FSRefMakePath`.  FSRef is the
documented 80-byte opaque value and this implementation stores the POSIX path
inside it, so the three functions round-trip consistently.  Folders that are
not mapped (an unknown FourCC, or a domain we do not know) return the domain
root and say so once on stderr; they never pretend to be the requested
folder.  Firefox got past this binding.

## Blocker 7 — every non-root bootstrap lookup hung

After running as uid 501, Firefox printed its bundle id and then stopped
silently, with no window and no exit.  AppKit's next call is
`bootstrap_look_up("com.ravynos.WindowServer")`.  A probe
(`tests/compat/bootstrap_probe.c`) reproduced it:

    bootstrap: uid=0   port=1799 ... look_up kr=0x0 port=2563
    bootstrap: uid=501 port=1799 ... (no result; killed by the alarm)

Cause: launchd redirects non-root lookups to a per-user launchd
(`VPROC_ERR_TRY_PER_USER`).  That per-user job was created, but
`setaudit_addr()` returns ENOSYS in this kernel (auditing is Phase 5.6), so
launchd removed the job and returned a null port; the client then waited
forever in a MIG call to `MACH_PORT_NULL`.

Two changes in `BSD/sbin/launchd/core.c`:
* a failed `setaudit_addr()` no longer aborts the per-user job — it logs and
  continues without an audit session;
* non-root lookups are served by the single system bootstrap for now
  (per-user domains arrive with loginwindow, plan 5.3).  A genuinely absent
  service still returns `BOOTSTRAP_UNKNOWN_SERVICE`.

Also new: `tools/bootlab/launchd-compat/sandbox_stub.c`, so launchd links now
that the SDK sandbox constants exist; `sandbox_check` allows and `sandbox_init`
logs the profile as a no-op (plan 4.3d).

Measured after the fix: `bootstrap: uid=501 ... look_up kr=0x0 port=7683`,
and Firefox proceeds to

    [AppKit] WindowServer service located
    [AppKit] registered with WS OK
    [AppKit] display isReady OK!

## Blocker 8 — NSAppleEventManager

Firefox aborted with

    +[NSAppleEventManager sharedAppleEventManager]: unrecognized selector

`Frameworks/Foundation/FoundationClasses.m` had the class but no methods.
It now returns a singleton and accepts `setEventHandler:andSelector:
forEventClass:andEventID:` (registration is recorded and logged; WindowServer
does not deliver Apple Events yet).  Firefox then reached its main startup.

## Blocker 9 — use-after-free during pool drain (open)

Current failure, after the Apple Event registration:

    CORPSE: tid 335 rip ... fault 0x000065e5e5e5e600
    regs rdi 0x000065e5e5e5e600
    rdi->[0] 0xe5e5e5e5e5e5e5e5 (isa)
    frame[0] libobjc _objc_release
    frame[1] libobjc AutoreleasePoolPage::releaseUntil
    frame[2] libobjc AutoreleasePoolPage::popPage
    frame[3] libobjc AutoreleasePoolPage::pop
    frame[4] libobjc _objc_autoreleasePoolPop

`releaseUntil` calls `objc_release` on an object whose memory has already
been freed and filled with jemalloc's 0xe5 pattern; the release path reads
that poisoned isa and faults.  It is a dangling object in the pool (owner
released it while it was still autoreleased), not a corrupted pool page and
not a junk pointer handed to `objc_release`: an entry-pointer range guard in
`objc_release`/`objc_autorelease` never fired on either crash (pid 55
`-CreateProfile` and pid 67 `-profile`), because the pointer itself is a
normal heap address.

### The runtime build is now real (4.2i, fixed)

`Libraries/objc4/Makefile` no longer has the Darwin-host branch that only
`touch`ed the prebuilt dylibs, and it includes `bsd.lib.mk`, so
`build-libraries.sh objc4` compiles the runtime and produces a fresh
`libobjc.A.dylib`.  Two host-specific requirements were measured:

- `libunwind.h` and `__libunwind_config.h` must be present in the SDK
  (`Developer/Default.xctoolchain/include`); `objc-exception.mm` includes
  them.
- The dylib must not record an `LC_LOAD_DYLIB` on libc++ (the shipped
  1.6 MB runtime records none).  A build that links `-lc++` dynamically
  makes launchd load libc++ at boot, and libc++'s `run_libcxx_init`
  constructor calls `__libcxx_init` too early: it dies in
  `std::__stdinbuf<char>::imbue` with a null `codecvt` facet before
  launchd reaches `main`.  The working link is `-nostdlib -weak-lSystem`
  plus the static archives `libc++.a` and `libc++abi.a`, which is also how
  the shipped runtime carries `__cxa_throw`, `std::terminate` and
  `std::nothrow` internally.

With that build the desktop boots normally (Filer and WindowServer present);
the Firefox job still dies at this blocker.

### Second measurement (isa guard + autorelease ring)

A guard that reads the isa word in `objc_release` and rejects a class pointer
above 16 TB, plus a 1024-entry ring of `(object, caller)` recorded in
`objc_autorelease`, also never fired on either crash.  The faulting
instruction is `class_data_bits_t::getBit` (libobjc offset 0x2ad2f), not
`objc_release`; the pool-drain frames below it are real, but the poisoned
value reaches class-bit inspection without passing through the guarded
entry.  The crash is therefore a **class pointer overwritten on a live or
just-freed object** (isa == 0x000065e5e5e5e600, pointing at 0xe5-filled
memory), and the next instrument must check the isa at the point
`objc_msgSend`/`hasCustomRR` consumes it, or watch the isa word of the
specific pool entry rather than the entry pointer.

### Third measurement (e5-fill guard + class ring)

Guarding the raw isa for the jemalloc fill `0xe5e5e5e5e5e5e5e5` (and only
that pattern; non-pointer isa encodings are legitimate) fires on the real
case and names the object:

    [objc] release of freed object 0x10884aa90 isa=0xe5e5e5e5e5e5e5e5
           (ret0 releaseUntil, ret1 popPage)
    [objc]   autoreleased at 0x10848808f class NSData_concrete
    [objc]   autoreleased at 0x108498125 class NSMutableArray_concrete

The autorelease site resolves to `-[NSString UTF8String]` (Foundation);
the NSMutableArray record is the same address reused after the NSData was
freed, so the ring match there is stale.  The NSData was autoreleased
**once** and then released **twice**: an inner pool drain frees it, and a
later `AutoreleasePoolPage::releaseUntil` releases the same entry again.
Skipping the duplicate release lets the `-profile` process get past the
crash (`exec rc=1` instead of 139), which confirms the second release is
spurious.

That points at the pool bookkeeping, not at Foundation's retain balance:
the same object appears in two pools, or a page is walked by two pops.
The next step is a deterministic fixture with nested pools (including
enough autoreleases to allocate a child page) that asserts one dealloc per
autorelease; then fix `AutoreleasePoolPage::pop`/`releaseUntil`/`kill`
page ownership.

### Root cause and fix (4.2h)

The fixture (`tests/compat/autorelease.m`, now part of the gate) passes:
nested pools and child pages release each object exactly once, so the pool
bookkeeping is sound.  A release ring on the failing address named the
culprit:

    seq=34 autoreleased class NSMutableArray_concrete
    seq=56 autoreleased class NSData_concrete
    release seq=39 at Foundation+0x144fd

The first release, five releases after the array was autoreleased, is in
`-[NSException raise]`, which did:

    NSArray *stackTrace = [NSThread callStackSymbols];
    ...
    [stackTrace release];

`+[NSThread callStackSymbols]` returns `[NSMutableArray array]`, already
autoreleased.  The explicit release freed the array while its pool entry
remained; the address was then reused by an NSData, and the pool drain
released the stale entry and crashed in `class_data_bits_t::getBit`.

Fix: remove the `[stackTrace release]` (`Frameworks/Foundation/NSException/
NSException.m`).  Firefox `-CreateProfile` now returns 1 instead of dying
with SIGSEGV, and the browser process no longer crashes in the pool.

The next selector gap exposed by the same run,
`+[NSURL fileURLWithPath:isDirectory:]`, is implemented in
`Frameworks/Foundation/NSURL/NSURL.m`; `-CreateProfile` no longer aborts
with `rc=134`.

### Version reporting and the next library gaps (4.2h follow-up)

With the pool crash fixed, Firefox exposed its platform checks:

* `Minimum OS version requirement not met!` came from the compatibility
  version, not from the kernel: `SystemVersion.plist` carried ravynOS
  0.7.1, and `NSProcessInfo` had no `-operatingSystemVersion`.  The image
  now installs `SystemVersion.plist` with `ProductVersion 10.13.6`, the
  kernel defaults `kern.osproductversion` to `10.13.6`, and
  `NSProcessInfo` implements `operatingSystemVersion`,
  `isOperatingSystemAtLeastVersion:` and the Darwin version string.
* `_SCDynamicStoreCreate` was imported from **IOKit**, which re-exports
  SystemConfiguration on macOS.  IOKit now links with
  `-reexport_framework,SystemConfiguration`.
* `_CFURLGetFSRef` / `_CFURLCreateFromFSRef` are implemented in
  CoreFoundation using the same 80-byte path encoding as CoreServices.
* `_CFNotificationCenterGetLocalCenter` and the observer API are now a
  real in-process notification center; distributed/Darwin centers alias
  it and do not claim cross-process delivery.

After these, `-CreateProfile` no longer aborts in the version check and
the browser process reaches its event loop instead of dying in dyld; it
was still running when the 190-second probe ended.

### Corrupt CFURL reaching CFURLCopyFileSystemPath

`-CreateProfile` next faulted at `_CFGetTypeID+0x1b` (fault 0xc): a call
to `CFStringCreateWithSubstring` received `str=0x4` and a garbage range.
`dladdr` named the caller as CoreFoundation's own
`_retainedComponentString`, reached from `CFURLCopyFileSystemPath` with a
CFURL whose `_string` field was `0x4` or NULL.  The URL object itself was
otherwise plausible, so the field was either never set by a failed
constructor or the URL was freed and its slot reused.

`_retainedComponentString` and `CFURLGetFSRef` now validate the URL and
its `_string` before dereferencing; the fault is gone, but
`-CreateProfile` now stays alive instead of returning.  The next step is
to find which constructor/owner produces the URL with `_string` 0x4,
rather than papering over it with a NULL path.

### String passed where a CFURL is expected

With the URL field guarded, the remaining `-CreateProfile` stall logs the
real classes: one caller passes an **NSCFString** (a POSIX path) and one
passes an **NSURL whose `_string` is NULL**.  Both reach
`_retainedComponentString` through `CFURLCopyPath`; on a stock system
this is a caller type error, so the producer, not the consumer, is wrong.

Trying to make `CFURLCopyPath` accept the string is not enough by
itself.  `CFStringCreateCopy` treats the ObjC string as a CF object and
corrupts it; converting through `-[NSString UTF8String]` gets past that
call but the next Foundation frame still faults on a freed object
(`rdi=0xe5e5…`).  A direct `object_getClassName` is also unsafe because a
CF object's first word is `_cfinfo`, not an isa, and one caller passes a
code pointer.

The tree is back at the last good state (guards only, no string
acceptance) so the fixture gate stays green.  The next attempt needs a
real CF/ObjC bridge: register `NSURL`/`NSCFString` under their live
`CF*GetTypeID()` values, implement `-_cfTypeID`/`-_cfurl` on them, and
then delete the guards rather than growing them.

## 2026-11-01 — crash resolved; scheduler stops ~90 s into startup

Fixed in `ef8477385d`, `cf0b2f8307`:

- `__CFISAForTypeID` stamped C-allocated CF instances with the bridge
  class (NSURL).  `CF_IS_OBJC` then said "ObjC" for C structs and
  `CFURLCopyAbsoluteURL` returned NULL through the `CF_OBJC_CALLV` `(0)`
  stub, so `_CFBundleCopyResolvedURLForExecutableURL` produced no bundle
  URL and `CFBundleGetBundleWithIdentifier` released a stale entry
  (fault 0x4, `CFRelease(4)`).
- x86_64 objc4 uses packed isas, so `*(uintptr_t*)obj` is the class
  pointer OR'd with extra_rc/magic bits.  CF now masks with ISA_MASK
  before comparing in `CF_IS_OBJC` and `_CFIsRegisteredObjCClass`.
- The NSURL-accessor ObjC branches (`CFURLCopyAbsoluteURL`, `GetString`,
  scheme/host/port/user/password/parameterString/query/fragment,
  `IsFileReferenceURL`) send the message explicitly; `CF_OBJC_CALLV` is
  still a `(0)` stub for the multi-argument callers elsewhere.

Result: 0 CORPSE, `[AppKit] exe=firefox bundleID=org.mozilla.firefox`,
WindowServer activates the app, `[CF] invalid url` guard hits gone.

### Next blocker: vCPU0 spins in `_lapic_send_ipi`, no CPU is woken

Reproduced on the 2048 MiB Firefox image (8 vCPUs, HVF).  At ~75 s into
`firefox -CreateProfile` the guest stops scheduling: serial output stops,
Firefox stays state `R` forever, `kill(SIGKILL)` returns 0 but the
process never dies, and no CORPSE prints (killed by signal, not faulted).

QEMU monitor `info registers -a` sampled five times, two seconds apart:

```
CPU#0  RIP=ffffff800040dff7  CPL=0 HLT=0   (inside _lapic_send_ipi)
CPU#1..7  RIP=000000007ed65af1  HLT=1     (halted, never wake)
```

`ffffff800040dff7` is the x2APIC MSR-write helper (`0x800 + index`) called
from `_lapic_send_ipi` (`ffffff800040db40`).  The boot prints
`x2APIC supported and will be enabled` / `x2APIC mode enabled`.  The IPI
targets stay halted across every sample, i.e. the interrupts are not being
delivered; anything waiting on an IPI ACK (TLB shootdown, AST poke) waits
forever with interrupts disabled, which also explains why SIGKILL cannot
land and why the desktop stops repainting.

Not the cause: the twelve
`vm_map_locate_space_anywhere: KERN_NO_SPACE (max <= hint ...)` lines.
Checked on the macOS host: `mmap()` with those hints maps elsewhere, but
`mach_vm_map(ANYWHERE, hint > max)` also returns `KERN_NO_SPACE` (kr=3),
so the guest matches Darwin here and Firefox tolerates it.

Fixed during this investigation (kept):

- `tests/compat/spinkill.c` — a userspace spinner with no syscalls is
  SIGKILLed and must report `FIXTURE spinkill rc=0`; it passes, so the
  signal path itself is healthy and the Firefox thread is stuck in kernel.
- `runas -t` now forks a root watcher that SIGABRTs then SIGKILLs the
  target (alarm/SIGALRM never fired: Gecko handles or masks it) and logs
  the target pid and kill results.

Next: compare `_lapic_send_ipi` against Darwin's (destination/ICR write,
delivery-status poll, `is_x2apic` gate) and check whether QEMU/HVF's
userspace APIC accepts the x2APIC ICR MSR here; a boot with
`-accel tcg` (x2APIC MSR handling differs) or with x2APIC disabled is
the cheap A/B.

### A/B: x2APIC is not the cause

The guest boots with x2APIC enabled (CPUID advertises it and the kernel
auto-enabled it under any VMM).  Forcing legacy MMIO LAPIC
(`x2APIC supported but will not be enabled`, commit `4f3584bec2`) and
booting the same Firefox image gives an identical wedge: `-CreateProfile`
reaches `[AppKit] exe=firefox`, ps shows pid `R` at 45 s and 75 s, the
watchdog's SIGABRT and SIGKILL are accepted (`-> 0`) and the process
never dies, no CORPSE and no rc line.  So IPI delivery is not what stops
the system, and the earlier `_lapic_send_ipi` sample was the normal
legacy-timer/IPI traffic of the one running vCPU.

What is proven so far about the wedge:

- Signal delivery to a busy userspace process works (`spinkill`).
- The wedged process has at least one thread that never reaches a
  userspace AST; killing the process cannot complete until that thread
  exits the kernel.
- The rest of the system stays alive (WindowServer traffic continues),
  so it is not a global kernel deadlock.

Next probe: `ps -M`/per-thread wait channel is not implemented in the
tree's ps (no `wmesg` keyword), so either add that keyword (thread state
and wait message from `proc_info`) or add a temporary kernel printf in
`wait4`/`task_terminate` naming the thread that refuses to exit.

### Profile creation never starts

With probes in the job (`ls` at 60 s, `ps` at 75 s), the wedge is before
any file work: `/var/tmp/ff` contains only `.` and `..` and
`/var/tmp/ff/profile` does not exist.  Firefox has consumed AppKit
(`[AppKit] exe=firefox`), run the Carbon modifier query, produced the
twelve `KERN_NO_SPACE` diagnostics from its allocator probes, and then
spins at 100% CPU without touching the filesystem.  ps at 75 s shows it
`R`; the zombie `/bin/sh` entries are just the job's finished background
probes waiting for a shell that is blocked in `wait`.

So the stuck work is pre-profile: allocator/JIT setup right after toolkit
initialization.  The next probe must show which thread never leaves the
kernel — the tree's ps has no per-thread or wait-channel output, so add
`ps -M`/`wmesg` from `proc_info(PROC_PIDLISTTHREADS)`/`PROC_PIDTHREADINFO`
first (it is also a Phase 7 tool gap).

### Root cause of the wedge: CFURLEnumerator never finished

tsample (task_for_pid + task_threads + thread_get_state, RIP resolved via
the target's dyld_all_image_infos) showed the 100% CPU thread inside
`CFURLEnumeratorGetNextURL`, at the same instruction across samples, while
the main thread sat in `kevent`.

Two bugs in the enumerator:

1. Descend was a one-shot: after returning a directory the parent kept
   `_entry` pointing at it, so every call re-descended and returned the
   *first* entry of that subdirectory forever.  The sub-enumerator was
   never stored.  The enumerator now keeps a `_child` cursor, returns the
   directory itself, descends on the next call, releases the child when it
   ends, and skips `.` and `..` (descending into them recursed forever).
2. A directory that `opendir()` could not open returned
   `kCFURLEnumeratorError` on every call.  Firefox enumerating a missing
   font directory (fresh HOME) loops until End, so it never terminated.
   A missing directory has no URLs: the enumerator now returns
   `kCFURLEnumeratorEnd`.

Result on the Firefox image: the process no longer wedges; it exits by
itself within seconds with `[fftest] create rc=134` (a normal SIGABRT in
libobjc, the classic "message sent to a code pointer" signature
`rdi->[0]=0x56415741e5894855`), and the watchdog reports `alive=0` before
firing.  The next triage step is this abort, not the scheduler.

New tools (staged in the image): `tdump <pid>` prints per-thread run
state/CPU time/name via `proc_info`, `tsample <pid>` prints each thread's
user RIP resolved to `image+offset`; both are wired into the Firefox job.

### Platform UUID: gethostuuid could never return

With the enumerator fixed, the main thread was the last stuck one, in
`__gethostuuid` (`libsystem_kernel+0x4b88a`) in state 4
(`TH_STATE_UNINTERRUPTIBLE`), which is why SIGKILL never completed.  The
kernel path is `gethostuuid(2)` -> `IOBSDGetPlatformUUID()` ->
`IOService::waitForService(resourceMatching(IOPlatformUUID))`.

`IOPlatformExpertDevice::generatePlatformUUID()` only produced a UUID
when the firmware supplied `system-id` (x86) or `platform-uuid`; QEMU's
EFI platform has neither, so nothing was ever published, and a zero
timeout made `waitForService` wait forever.

Fixes:
- `generatePlatformUUID()` falls back to a UUID derived (SHA-1) from the
  platform `serial-number`, or a random one when no serial exists, and
  sets the property on the provider as well (the publisher reads it
  there).
- `IOBSDGetPlatformUUID()` reads the property directly first; a zero
  timeout no longer waits forever — it reports the missing UUID.

Result: `gethostuuid` returns promptly, Firefox no longer wedges there
(`[runas] watchdog: target 11 alive=0`), and the next blocker is a plain
SIGABRT (`create rc=134`) inside XUL after the font manager call.

### Modern nib loader and the next crash

`objc[16]: -[NSBundle loadNibNamed:owner:topLevelObjects:]: unrecognized
selector` killed the process next.  AppKit's NSBundle nib category only
had the 10.7 `+loadNibNamed:owner:` and the `NSNib` instance methods, so
the 10.8 API is now implemented on top of
`-[NSNib instantiateNibWithOwner:topLevelObjects:]`.

With that in place the abort becomes a SIGSEGV (`create rc=139`) in
`objc_msgSend+0x29`: receiver 0x7ff3e1407be0 has isa 0x10bb7c850, and the
cache lookup faults at 0x8281ab00.  Frames below it are Foundation
(+0x5421, +0x4a65, +0x4344) called from XUL, i.e. the nib load path
sends a message to an object whose class is not a realized ObjC class.
The next step is to identify 0x10bb7c850 in the image list (it is in
Foundation's data range) and make that class a real objc class, the same
class of fix as the packed-isa work in CoreFoundation.

Follow-up on the SIGSEGV after the nib fix: the receiver's isa resolves
to `___CFStringClass` (CoreFoundation+0x190850), i.e. Foundation's nib
path sends a message straight to a CoreFoundation string.  On macOS that
is legal because CF's classes are ObjC classes; here a CF instance's isa
is the `CFRuntimeClass` record, so `objc_msgSend` faults in the cache
lookup (fault 0x8281ab00, `objc_msgSend+0x29`).  This is the remaining
half of the toll-free bridge: either CF's classes must become real ObjC
classes (allocateClassPair-based, as on macOS) or every Foundation call
site that messages a CFString/CFURL must go through the CF functions.
The nib loader path exercises the first option via `NSNib`/`NSKeyedUnarchiver`.

### Container boundary bridging and the CFBasicHash crash

Foundation containers used ObjC callbacks (`objectKeyCallBacks`,
`objectValueCallbacks`) whose retain/copy callbacks message the value, so
a CoreFoundation object that reached a Foundation dictionary through CF
(CFBundle Info.plist keys, for example) crashed in `objc_msgSend` on
`-copyWithZone:`/`-retain`.  `objectCopyCallBack`/`objectRetainCallBack`/
`objectReleaseCallBack` now bridge: a C CFString becomes a real
`NSString` (characters copied through `CFStringGetCharacters`), other CF
objects keep their CF lifetime.  "Is this ObjC?" comes from the new
`_CFIsObjCType()` (CF's registered-class table) — the first-word-pointer
heuristic is wrong because C CF instances carry the CF class in `_cfisa`
as well.

The crash then moves to `__CFBasicHashFindBucket_Linear` calling an ObjC
method on a `__CFRunLoopObserver` (isa `___CFRunLoopObserverClass`): some
CF container is built with Objective-C callbacks and receives a CF
run-loop observer as a key.  That is the same bridging question one level
down — the callbacks for CF collections must either handle CF objects or
the observers must be ObjC objects.

### Static symbol inventory (2026-11-02)

`tests/compat/symbol-coverage.py` walks every Mach-O image in the bundle,
takes the undefined symbols and subtracts what the bundle itself and the
ravynOS SDK export.  Firefox ESR today: 20 images, 3,245 undefined, 242
not provided.  By owner: CoreText 63, CoreGraphics 57, IOKit 31 (HID
manager, power sources), LaunchServices 12, PrintCore 12, CoreFoundation
16, Accessibility 7, Carbon 5, Pasteboard 3, plus CUPS, Metal,
VideoToolbox, QuartzCore.  The baseline is `firefox-symbol-gap.json`;
`--baseline` fails when a bundle starts needing a symbol we still lack.
This replaces one-400-second-boot-per-symbol discovery with a host-side
list, the way Wine's conformance report drives its API work.

### Volume info, aliases, and wakeup of a dead run loop

After the run-loop observer crash, dyld stopped aborting on missing
symbols and Firefox got as far as NSUserDefaults (the argument-domain
plist parse is caught) and CFRunLoopWakeUp.  Two more gaps surfaced:

- `_FSGetVolumeInfo` was missing from CoreServices, so dyld's lazy bind
  aborted the process (SIGABRT after printing "Symbol not found").
  `FileManagerCompat.c` now implements it over `statfs("/")` with the
  CarbonCore 128-byte FSVolumeInfo layout, plus `FSCompareFSRefs`
  ((device, inode) identity, `errFSRefsDifferent` = -1420) and
  `FSResolveAlias` (plain files resolve to themselves).
- `CFRunLoopWakeUp` crashed reading `_perRunData->ignoreWakeUps`: the
  loop passed by Gecko has no per-run data, i.e. it is not running (the
  run loop pushes that state around every `CFRunLoopRunSpecific`, and the
  owning thread may already have exited).  WakeUp now ignores such a
  loop and logs `[CF] CFRunLoopWakeUp: rl=... not running` once.

### Window surface (2026-11-02, later)

Firefox's own window classes are NSWindow/NSView subclasses, so every
AppKit method they inherit must exist on the superclass or the message
aborts the process.  Fixed in order, each found by the runtime oracle:
`+[NSWindow setAllowsAutomaticWindowTabbing:]` (remembered statically),
`-[NSWindow setTitlebarAppearsTransparent:]` plus `titleVisibility`,
`restorable`, `titlebarSeparatorStyle` and a `toggleFullScreen:` that
zooms, and `-[NSView setMaterial:]` (Gecko's MOZTitlebarView uses
NSVisualEffectView materials; the value is stored, compositing is not
implemented).  `-FSGetVolumeInfo` was missing from CoreServices and made
dyld abort the process; it is implemented over `statfs` in
FileManagerCompat.c with the CarbonCore FSVolumeInfo layout.

### %@ on Objective-C objects (2026-11-02)

Firefox now creates its browser window.  The next crash was in the
shm-failure NSLog: CFString's %@ formatting called
__CFCopyFormattingDescription, which read a CF type ID out of the
object's second word.  That word is _cfinfo in a CF object but the first
ivar in an ObjC object, so the class lookup went out of range and the
wild callback messaged address 8.  CFCopyDescription and
__CFCopyFormattingDescription now use -description when _CFIsObjCType()
says the argument is ObjC.  NSWindow also stops mapping a 0x0 window:
mmap(0) is EINVAL, the window gets its context on the first real resize.

### Window behaviors and NSWorkspace accessibility (2026-11-02)

Two more AppKit gaps from the runtime oracle, both after the window is
created: `-[NSWorkspace accessibilityDisplayShouldReduceMotion]` (and the
contrast/transparency/invert/differentiate flags) did not exist; they
now answer NO, the system defaults.  `-[NSWindow collectionBehavior]`
and `setCollectionBehavior:` were stubs that set nothing and logged
through NSUnimplementedMethod; they now store the value, as does
setContentMinSize: (which set the value and then logged anyway).

### Native theme surface (2026-11-02, continuing)

After the window is up, Gecko's nsNativeThemeCocoa asks AppKit for theme
data: NSAppearance (named lookups, current appearance, effective
appearance down the view hierarchy), NSWorkspace accessibility display
flags, and system colors.  Implemented from the runtime oracle:
+[NSAppearance appearanceNamed:]/currentAppearance/setCurrentAppearance:
and bestMatchFromAppearancesWithNames:, -[NSView/NSWindow
effectiveAppearance] with stored appearance, NSWorkspace's five
accessibilityDisplayShould* flags (all NO, the system defaults),
+[NSColor currentControlTint] (blue), windowFrameTextColor (control text
color), and sRGB/controlAccent/link/systemPurple constructors.

### The fake CFRunLoopRef (2026-11-02, root cause)

`-[NSRunLoop getCFRunLoop]` answered `self`, but this tree's NSRunLoop is a
plain NSObject with its own mode/perform ivars, not a toll-free bridged
CFRunLoop.  Gecko asks its NSRunLoop for the CF run loop and passes the
result to CFRunLoopAddSource/CFRunLoopWakeUp, so CoreFoundation read an
NSRunLoop's fields as a run loop: `CFRunLoopWakeUp` saw a null per-run
pointer, `CFRunLoopAddCommonMode` saw `_commonModeItems == 1`, and
CFSetCreateCopy faulted dereferencing it.  getCFRunLoop now returns
CFRunLoopGetCurrent(), the loop CoreFoundation actually runs for the
thread.  (The earlier null-per-run guard stays: it is correct for a loop
whose thread has exited.)

### Container bridging must not guess (2026-11-02)

The first CF/NSDictionary bridge asked `_CFIsObjCType`, which only knows
CF's *bridge* classes.  Ordinary Foundation and application objects are
not in that table, so they were treated as C CF objects: CFGetTypeID read
an ivar as `_cfinfo`, and CFRetain then crashed on a pointer whose "isa"
was the object's own interior (Foundation `objectRetainCallBack` ->
`ravyn_bridge_retain` -> `__CFRetain+0x6c`).  `_CFIsCFInstance()` answers
the question directly: the first word is one of the registered
CFRuntimeClass records.  The dictionary callbacks use CF lifetime only
for such instances; everything else is an Objective-C object.

### The FAT dev image has one owner (2026-11-02)

The bring-up image is FAT: msdosfs has no on-disk owner or mode, so every
node reports the mount owner (`pm_uid`/`pm_gid`) and the mount mask
(`0755`).  With the mount owned by root, a process running as `ravyn`
(501) cannot create `/var/tmp/ff/profile` — `mkdir` returns `EACCES` —
and the oracle sat in its normal event loop because it could not write a
profile.  Rendering every node as `99:99` did not help either: the
authorization path still saw uid 0 and denied non-root writes.  The
Firefox job therefore runs as root with a root-owned `$HOME` on this
image; Firefox itself refuses to start as root when `$HOME` belongs to
another uid, which is now consistent.  `runas` still arms the 90 s
watchdog.  The per-user run (`501:20`) remains the gate for the
installed HFS+ system, where the profile lives in a home the user owns
and write permission comes from real per-file ownership.

### The content process never reaches the rendezvous (2026-11-02)

With the profile fixed, the browser itself launches and stays alive for
the full watchdog window (20 threads, run loop idle).  No window is
created because the first `GeckoChildProcessHost` launch never
completes:

    [Parent 58, IPC Launch #1] WARNING: parent MachReceivePortSendRight
      failed: 0x10004003 (ipc/rcv) timed out
    xpc_pipe_try_receive: reply send failed, kr=268435472
    [Parent 58, IPC I/O Parent] WARNING: Failed to launch socket subprocess

`0x10004003` is `MACH_RCV_TIMED_OUT`: the parent waits for the child's
Mach port handoff and the child never sends it.  XUL binds `posix_spawnp`
and the spawn attr calls, not `posix_spawnattr_set*ports*`, so the
handoff is not the registered-ports path.  Forcing
`MOZ_FORCE_DISABLE_E10S=1 MOZ_DISABLE_SOCKET_PROCESS=1` leaves the main
thread busy with four threads and still no window, so single-process
mode is not a route around it.  Next: a `posix_spawn`/Mach-rendezvous
fixture to determine whether the child is not spawned, exits before
sending, or the port handoff is dropped.

### The child's Mach port set was a missing export (2026-11-02)

The rendezvous timeout had a concrete cause, found with the spawnprobe
fixture: a plain `posix_spawn` worked, but a spawn with a registered
receive right died in the child at dyld's first lazy bind:

    dyld: lazy symbol binding failed: Symbol not found: _mach_ports_lookup

`task.c` in xnu's libsyscall implements `mach_ports_lookup`,
`mach_ports_register` and `mach_task_is_self`, but it was not in
libsystem_kernel's SRCS, so only the `_kernelrpc_*` traps were exported.
With `task.c` built, the child sends and the parent receives its port
(the probe now reports `id=7`; the parent asked for a 24-byte buffer and
gets MACH_RCV_TOO_LARGE, so the probe now uses a 512-byte buffer), and
`GeckoChildProcessHost` no longer logs `MachReceivePortSendRight failed`
— the IPC/socket child threads come up.  The browser still creates no
window: it finishes launching and idles with 19 threads (HTML5 Parser,
Socket Thread, IPC I/O Parent, StreamTrans), which is the next problem.

Building all of `Libraries/Libsystem` also regenerated
`libSystem.B.dylib` as a 35 KB reexport stub whose initializer never
runs; images staged with it panicked before initproc (`initializer in
image (/usr/lib/libc++.1.dylib) that does not link with
libSystem.dylib`).  The full ~1.1 MB stub is kept as
`tools/bootlab/assets/libSystem.B.dylib` and build-libraries.sh puts it
back after (and again after sync_sdk) a Libsystem build.

### The event loop never ran the run loop (2026-11-02)

`-[NSApplication nextEventMatchingMask:untilDate:inMode:dequeue:]` polled the
WindowServer pipe and the display queue, but never executed the current
CFRunLoop.  Gecko drives its own XPCOM event queue from a CFRunLoop source and
its startup waits in `ProcessNextNativeEvent`; with the source never fired,
the browser sat in `nextEventMatchingMask:distantFuture` forever, never called
`-[NSApplication run]`, never ran `finishLaunching`, and created no window.
Running `CFRunLoopRunInMode(mode, 0.02, true)` once per poll iteration fixed
startup: Firefox now calls `-run`, completes `finishLaunching`, sends its
menu, and creates windows.

Also fixed on the way: `-[NSString containsString:]` (unrecognized selector),
`+[NSScroller preferredScrollerStyle]`, and the LaunchServices scheme-handler
entry points (`LSCopyAllHandlersForURLScheme`,
`LSCopyDefaultHandlerForURLScheme`, `LSCopyDefaultApplicationURLForURL`,
`LSCopyDefaultApplicationURLForContentType`), exported from both
LaunchServices and the CoreServices umbrella with C linkage.

`finishLaunching` now also calls the delegate's
`applicationWillFinishLaunching:` / `applicationDidFinishLaunching:` methods;
previously it only posted the notifications.

Current first crash: after `finishLaunching` and menu registration, Firefox
builds a small 2x32 window, then dies with SIGSEGV whose backtrace is entirely
inside XUL (`rip 0x...` in the 123 MB XUL text segment).  The kernel's
"Text page corruption detected" line is the exit-time code-signature
revalidation failing on unsigned images, not evidence of real corruption.
Next: symbolize that address or bisect Gecko's post-launch window setup; the
0-width window frames (0x3, 0x176) suggest a widget/size path is also wrong.

### First SIGSEGV after the window exists (2026-11-02)

With `-run` and `finishLaunching` finally reached, Firefox creates
`BorderlessWindow` (0x3), `MOZCellDrawWindow` (0x176) and `ToolbarWindow`
(style 0x800f), sets their content views, sends its menu, and then dies with
SIGSEGV.  The crash PC is consistently at XUL __TEXT + `0x26e059e`; that
offset is two bytes into a `jmp rel32` stub when the file image is
disassembled, and the saved frame pointer chain is not a valid call chain, so
the process is executing from corrupt or misaligned code.  The kernel's
exit-time "Text page corruption detected" is the code-signature revalidation
failing on these unsigned images, not proof of the fault.

Ruled out by test: socket process and e10s disabled
(`MOZ_DISABLE_SOCKET_PROCESS=1 MOZ_FORCE_DISABLE_E10S=1`), SpiderMonkey JIT
off, WebRender software, native animations off (prefs verified present in
`user.js`, 285 bytes).  The socket subprocess still times out separately
(`parent MachReceivePortSendRight failed 0x10004003`) even though
`mach_ports_lookup` is exported by the image's libsystem_kernel.

Next: capture the bytes at the faulting PC from the corpse dump (to confirm
whether the page really differs from the file), or make dyld verify XUL's
chained-fixup stubs against the file; the mid-instruction PC points at code
corruption rather than a bad C++ vtable alone.

### The crash is a null-`this` call with a host name in rsi

The corpse dump now prints the bytes at the faulting PC and a printable string
at rsi.  The bytes match XUL's file image exactly (runtime address maps to
file offset 0x26e159e with XUL's __TEXT fileoff 0x1000), so this is not text
corruption: the PC sits at the start of a null-object virtual call sequence
(`mov rax,[rbx]` with rbx=0), and **rsi points at the string "example.org"**.
Nothing in the app bundle or profile contains that literal, so it is a
runtime-built host name passed to a networking object that is null.  The next
step is to identify which XPCOM/networking object should have handled it
(the caller frames are all in XUL, so symbolization of XUL+0x… is still the
missing tool).
