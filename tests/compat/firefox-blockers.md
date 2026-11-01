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
