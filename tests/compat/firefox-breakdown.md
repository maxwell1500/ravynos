# Why Firefox does not launch — a dependency breakdown

Firefox is the conformance oracle, not the product. The point of this document is
to separate the layers a stock macOS application needs, show which ones already
work, and name the one that currently stops Firefox. The same failure will stop
TextEdit, Preview, or any other AppKit application that touches a file URL.

## Current result (fresh trace, 2026-11-01)

`tools/bootlab/work/firefox_trace.log` and `firefox_caller.log`:

```
[fftest] start
[fftest] create profile
...
[AppKit] exe=firefox bundleID=org.mozilla.firefox
[AppKit] WindowServer service located
[AppKit] registered with WS OK
[AppKit] display isReady OK!
[CF] CFURLCreateStringWithFileSystemPath entry url=0x105a14660 caller=... CFURLGetFileSystemRepresentation
[CF] CFURLCreateStringWithFileSystemPath entry url=0x10572cb38 caller=... CFURLCreateStringWithFileSystemPath
[CF] CFURLCopyPath entry url=0x10572cb38 caller=... CFURLCreateStringWithFileSystemPath
[CF] invalid url=0x10572cb38 class=NSCFString string=0x4 flag=32 caller=... CFURLCopyPath
[CF] CFURLCopyPath entry url=0x105a14660 caller=... CFURLCreateStringWithFileSystemPath
[CF] invalid url=0x105a14660 class=NSURL string=0x0 flag=32 caller=... CFURLCopyPath
```

No `[fftest] create rc=` line follows. The process has not crashed; it is stuck
in the profile-creation path. The earlier `SIGSEGV` in `free()` and the
`NSException raise` over-release are gone.

## Root cause of the current hang

CoreFoundation and Foundation disagree about what an `NSURL` is.

`CFURL` is a C struct:

```
struct __CFURL {
    CFRuntimeBase _cfBase;      // 8 bytes
    UInt32 _flags;              // offset 8
    CFStringEncoding _encoding; // offset 12
    CFStringRef _string;        // offset 16
    CFURLRef _base;             // offset 24
    ...
};
```

`NSURL` is an Objective-C object:

```
isa          offset 0
_baseURL     offset 8
_string      offset 16
_scheme      offset 24
_host        offset 32
...
```

The toll-free bridge is the only thing that makes these layouts interchangeable.
In this tree it is not registered for `NSURL`:

```
__CFRuntimeObjCClassTable[CFURLGetTypeID()] == 0
```

Therefore `CF_IS_OBJC(CFURLGetTypeID(), nsurl)` is false, `_CFURLFromNSURL()`
returns the `NSURL` unchanged, and CFURL reads NSURL fields at CFURL offsets:

- `CFURLGetBaseURL(nsurl)` reads NSURL `_scheme` (offset 24) as `_base`.
  That is the `NSCFString` `0x10572cb38` in the trace.
- `CFURLCreateStringWithFileSystemPath` then recursively treats that scheme
  string as a base URL.
- `_retainedComponentString(nsurl)` reads NSURL `_string` (nil) as CFURL
  `_string`, and `_retainedComponentString(schemeString)` reads the string's
  first payload word as a pointer (`0x4`).
- Both calls return NULL. `-CreateProfile` never gets a usable path.

This is not a Firefox bug and not memory corruption. It is a layout mismatch
caused by a missing bridge registration. The guards in `CFURL.c` turned the
crash into a log, but they cannot invent the correct URL.

The earlier attempt to fix it by adding `-_cfurl`/`-_cfTypeID` and registering
`NSURL` globally regressed early boot (desktop clients faulted in
CoreFoundation before `[fftest]`). That means the registration was too broad or
`_cfurl` was re-entered during CFURL initialization; it does not mean the bridge
is the wrong fix. It needs to be isolated with a fixture and a recursion guard.

## What we tried, and what it proved

1. **Global registration from `CFSetupFoundationBridging`.** Crashed early boot:
   `__CFRuntimeSetInstanceTypeID` dereferenced a NULL
   `__CFRuntimeClassTable[0]`. The bridge call ran before the CoreFoundation
   runtime constructor installed the table, so `CFURLGetTypeID()` registered
   CFURL at index 0.
2. **Registration from `+[NSURL load]`.** Same crash, now in WindowServer:
   `__CFRuntimeSetInstanceTypeID` at `CoreFoundation+0xcbd50`. `+load` is
   still before the CF constructor in this dyld ordering.
3. **Post-initialization registration inside `CFURLGetTypeID`.** The default
   image boots with `CORPSE=0` and the 12-fixture gate green. Firefox gets
   past profile creation and crashes later, so the registration timing is now
   correct.
4. **Explicit `NSURL -> CFURL` conversion** in `_CFURLFromNSURL`,
   `CFURLGetBaseURL`, `CFURLCopyFileSystemPath`, and
   `CFURLCreateStringWithFileSystemPath`, plus a UTF-8 path constructor and
   `_cfurl = NULL` in the initializers. Firefox now crashes in `_CFRelease`
   with `rdi=0xe5e5e5e5e5e5e5e5`, i.e. an object was already freed and
   poisoned. The CFURL type mismatch is gone; the ownership rule is not.

The ownership failure is the next layer: `_cfurl` returns a +1 CFURL, but
Foundation callers treat the result as autoreleased, or a CFURL result is
released by both the bridge and its creator. A standalone fixture must assert
retain counts before this is committed.

## A second bridge bug: `CF_OBJC_FUNCDISPATCHV` discards results

`Frameworks/CoreFoundation/CFInternal.h` defines:

```c
#define CF_OBJC_FUNCDISPATCHV(typeID, rettype, obj, ...)     do { if (CF_IS_OBJC(typeID, obj)) { [((id)obj) __VA_ARGS__]; } } while(0)
```

It sends the Objective-C message and **throws away the return value**. Every
CF function that uses it (`CFStringGetLength`, `CFNumberGetType`, `CFErrorGetCode`,
`CFTimeZoneGetName`, ...) then continues to read the object as a CF struct.
That is why CFString bridging is unreliable and why `CFURLCreateWithFileSystemPath`
could not consume an `NSString` path.

Changing the macro to `return [((id)obj) __VA_ARGS__];` is the correct shape,
but it does not compile for the `CFRange`-returning `CFCalendar` calls: the
compiler does not know the ObjC method's return type. The fix needs typed
method declarations (or a typed `objc_msgSend` dispatch), not a blind cast.
This is a framework-wide bug, not a Firefox workaround.

## The dependency stack

| Layer | What a stock macOS app needs | State in ravynOS | Evidence |
|---|---|---|---|
| 0. Mach-O loader | `LC_LOAD_DYLIB`, `@rpath`, weak symbols, re-exports, flat namespace | Working | XUL is 266 MB, 43 images, 2,956 undefined symbols, 30 frameworks, 136 ObjC classes; dyld reports no unresolved symbol |
| 1. Objective-C runtime | classes, categories, selectors, exceptions, autorelease, associated objects | Working for the tested surface | autorelease fixture PASS; `-[NSException raise]` over-release fixed; XUL executes |
| 2. CoreFoundation | `CFString`, `CFURL`, `CFBundle`, `CFPreferences`, `CFRunLoop`, `CFNotificationCenter`, `CFNetwork` | Partial; **CFURL↔NSURL bridge is the wall** | invalid URL trace above; `CFURLEnumerator` fixed earlier |
| 3. Foundation | `NSURL`, `NSFileManager`, `NSUserDefaults`, `NSBundle`, `NSProcessInfo`, `NSThread`, `NSException` | Partial | `NSUserDefaults` vintage-plist parse error; `NSURL` file URLs have `_string == nil`; `NSAppleEventManager` records but does not dispatch |
| 4. AppKit / WindowServer | `NSApplication`, `NSWindow`, `NSMenu`, `NSPasteboard`, `NSGraphicsContext`, events | Basic works | CocoaProbe window PASS; Firefox registers with WindowServer and reports `display isReady` |
| 5. Graphics/text | CoreGraphics, CoreText, Onyx2D, ImageIO, QuartzCore | Basic drawing works; Firefox rendering untested | CocoaProbe draws; CoreText/CoreGraphics build and load |
| 6. Security | ad-hoc/Developer ID signatures, entitlements, `SecTask`, keychain, trust evaluation | Mostly stubs; not reached | Security framework exports constants and a few APIs |
| 7. XPC / launchd | `xpc_connection_create_mach_service`, bootstrap names, content processes | System bootstrap only; per-user domains ENOSYS | Firefox has not reached content-process creation |
| 8. VM / JIT | `mmap`, `MAP_JIT`, `mprotect`, W^X, executable memory | Not validated; kernel logs non-canonical `mmap` hints | 12 × `vm_map_locate_space_anywhere: KERN_NO_SPACE ... hint=0xbc...` after the URL failure |
| 9. Networking/TLS | CFNetwork/NSURLSession, Security trust, NSS | Not reached | network fixtures pass; TLS gate not exercised |
| 10. Audio | CoreAudio/AudioToolbox | Absent by design in Phase 4 | Firefox can start with audio disabled; not a launch blocker |

## What this means for “real macOS apps”

The loader is no longer the problem. A 266 MB XUL with 2,956 external symbols
loads and runs. The remaining failures are **semantic**: the frameworks are
present but their object models do not agree.

The highest-leverage work is therefore not adding more framework names. It is:

1. **One object model for CF and ObjC.** `CFString`, `CFURL`, `CFArray`,
   `CFDictionary`, `CFData`, `CFNumber` must all agree on type IDs, isa
   registration, and ownership. A wrong offset in `CFURL` becomes a wrong
   `NSUserDefaults` key, a wrong `NSBundle` path, and a wrong `NSFileManager`
   operation in every app.
2. **File URL semantics.** `NSURL` must keep its `_string` non-NULL (or CFURL
   must be able to derive it), and `fileURLWithPath:` must produce the same
   path as `CFURLCreateWithFileSystemPath`. TextEdit/Preview open panels depend
   on this more than on any drawing API.
3. **Defaults and bundles.** `NSUserDefaults` must parse the argument domain
   without throwing; `NSBundle` must find `Info.plist`, resources, and
   `@rpath` dylibs. These are the first things every app does.
4. **Process and IPC.** Once the app starts, content processes, XPC, and
   launchd domains determine whether it can stay alive.
5. **JIT and signing.** These are browser-class requirements; ordinary apps
   need signing only for library validation and keychain access.

## Recommended order

1. **Build a CFURL bridge fixture** (`tests/compat/cfurl.m`) that exercises:
   - `CFURLCopyPath((CFURLRef)[NSURL fileURLWithPath:@"/tmp"])`
   - `CFURLGetBaseURL` on an `NSURL` with a base
   - `CFURLCreateStringWithFileSystemPath` on an `NSURL`
   - an `NSString` passed where a `CFURLRef` is expected (must return NULL,
     never recurse or crash)
   This reproduces the Firefox failure without the 266 MB app and runs in the
   normal boot gate.
2. **Fix the bridge narrowly.** Add `-_cfTypeID` and `-_cfurl` to `NSURL`;
   `_cfurl` should build the CFURL from `_scheme`/`_host`/`_path` directly,
   not from `absoluteString`, and must not call back into CFURL for an object
   that is already being converted. Add a per-thread recursion guard.
3. **Register lazily and test the desktop first.** Register `NSURL` from
   `CFSetupFoundationBridging`, then boot the default image and require Filer,
   Dock, and CocoaProbe to stay alive before running Firefox.
4. **Harden CFURL entry points.** `CFURLCreateStringWithFileSystemPath`,
   `CFURLCopyPath`, and `CFURLGetBaseURL` must validate the object before
   reading `_base`/`_string`; a non-CFURL must produce NULL, not a recursive
   call on a string.
5. **Fix `NSUserDefaults` argument parsing.** The vintage plist parser throws
   on the empty argument-domain string; log the input and make the empty case
   return an empty dictionary.
6. **Add a supervisor for triage.** `runas -t` uses `alarm(2)`, which the
   target can reset. Fork a parent that sleeps and `SIGKILL`s the child, so a
   hang always produces a `rc=` line.
7. **Then JIT/XPC/security.** Do not tune `MAP_JIT` until the app can create a
   profile and reach its own main loop; otherwise the VM logs are noise from a
   process that was already lost.

## Solved blockers (kept for context)

- `free()` zone ownership (`find_registered_zone` claimed foreign pointers).
- dyld flat binding for system libraries and re-exported symbols.
- CF constants treated as ObjC objects; `CFBooleanGetTypeID` before retain.
- Missing frameworks and ObjC classes (16 compat frameworks, 37 classes).
- `-[NSException raise]` over-release of `+[NSThread callStackSymbols]`.
- `+[NSURL fileURLWithPath:isDirectory:]` missing selector.
- Version check (`SystemVersion.plist`, `NSProcessInfo operatingSystemVersion`).
- `CFURLEnumerator` NULL/end-of-directory handling.
- Carbon `FSFindFolder`/FSRef round-trip.
- launchd non-root bootstrap hang.

The next commit should make the CFURL fixture pass and keep the 12-fixture
`compat_check` green. Only then does Firefox move on to JIT/XPC/signing.
