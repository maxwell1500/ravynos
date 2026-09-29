# libsystem_pwdgrp — the passwd and group database

A self-contained, real implementation of the POSIX passwd/group database
API, reading `/etc/passwd` and `/etc/group` directly.

## Why this is not `libsystem_info`

`getpwnam`, `getpwuid`, `getpwent`, `getgrnam`, `getgrgid`, `getgrent`,
`user_from_uid` and `group_from_gid` all *are* implemented in this tree, in
`Libraries/Libsystem/libsystem_info/libinfo.a`. The problem is not that they
are missing; it is that `libinfo.o` is self-referential onto ~50 `si_*`
symbols in the `SystemInformation` framework, which has no build target here,
and `libsystem_info/MISSING_DEPS.md` already records that component as blocked
on absent libxpc / libsystem_trace / libsystem_notify. Pulling eight working
functions out of it would mean building the whole blocked closure.

So this is a separate component. It owns the passwd and group database and
nothing else: no dispatch, no notify, no mach ports, no search modules. It
depends on `stdio`, `string` and `strtoul`, all of which a static ravynOS
program already links.

**This is the single owner of these functions.** `BSD/bin/sh/ravynos_port.c`
carries a private copy of the same passwd parser for the shell. Two
definitions of one symbol is a link error — that is the `openat$NOCANCEL`
experience — so a program that links both must not. See "Handover" below.

## The parser

The passwd parser is the one `BSD/bin/sh/ravynos_port.c` already proved out
against a real database, carried over with its three verified fixes intact:

* trailing `\n` / `\r` are stripped before parsing, so `pw_shell` is
  `"/bin/sh"` and not `"/bin/sh\n"`;
* a line that fills the read buffer is drained to the next newline, so the
  tail of an over-long line is never parsed as an entry of its own;
* field buffers are sized at the line length, so a name longer than any
  fixed smaller bound is still reachable by a lookup.

On top of that, three things this library needs that the shell's copy does
not:

* **A minimum field count.** `name:passwd:uid:gid` must be present. A line
  with fewer fields is not an entry, and the numeric fields must be entirely
  decimal — `atoi("root")` is 0, and accepting that would fabricate a uid-0
  entry out of a malformed line. This is FreeBSD's `getpwent.c` minimum-colon
  rule.
* **NIS `+` / `-` lines are skipped.** A line starting with `+` or `-` is a
  netgroup/NIS directive, not an entry, and must be skipped rather than
  misparsed into a user named `+` with uid 0. Note that Darwin's own
  `libsystem_info/lookup.subproj/file_module.c` has no such check and does
  exactly that misparse; ravynOS has no NIS (`libsystem_info/nis.subproj` is
  not built), so a `+` line can never be resolved anyway and skipping it is
  the only reading that is not a fabrication.
* **The group database**, which is the same shape one column shorter:
  `name:passwd:gid:members`. `gr_mem` is a `NULL`-terminated array of
  pointers into static storage; a group with no members gets an empty array
  rather than a `NULL`, because a `NULL` `gr_mem` is a crash in every caller
  that walks it.

A line that fails any of these is skipped and the stream continues to the
next line. A rejected line never corrupts the stream.

## The iteration model

This is the part the `_r` variants exist to generalise, and the part that is
easy to get wrong.

    setpwent()  opens (or rewinds) the file and remembers the FILE *
    getpwent()  returns successive entries; NULL at end of file
    endpwent()  closes the file and forgets the FILE *

A call to `getpwent()` **after** a `NULL` return rewinds to the start of the
database and starts over. That is what POSIX specifies and what callers
depend on; it is FreeBSD's `needsetpwent` flag, implemented here the same
way. `getpwnam()` is a `setpwent()` + scan + `endpwent()`, so it does not
disturb the caller's iteration.

`fgetpwent(FILE *)` is the same parse over a caller-supplied stream: no
opening, no rewinding, no closing, `NULL` at that stream's end of file.

## The `_r` convention

    entry found            -> 0, *result = the caller's struct
    entry NOT found        -> 0, *result = NULL      <-- success, not an error
    result == NULL         -> EINVAL
    name NULL or empty     -> EINVAL
    entry/buffer NULL      -> EINVAL
    buflen == 0            -> EINVAL
    buffer too small       -> ERANGE, buffer and struct left UNTOUCHED

A not-found lookup returns 0 and does **not** touch `errno`. POSIX specifies
the error as the *return value* for the `_r` functions; a polluted `errno`
would invite a caller that checks it to read a normal miss as a failure.

The caller-visible buffer is untouched on not-found, and untouched on
`ERANGE`. That is what makes a not-found result distinguishable from an
empty entry: the caller reads `*result`, never the buffer.

One difference from `BSD/bin/sh/ravynos_port.c`: there, a `NULL` buffer
falls out of `_pw_copy_out()` as `ERANGE`. Here `buffer == NULL` is `EINVAL`,
alongside the other bad arguments, because "too small" is not what a null
pointer means. Both are non-zero, so no caller that only tests "is it an
error" can tell the difference.

## Ownership notes

* `user_from_uid(uid, nouser)` / `group_from_gid(gid, nogroup)` follow
  `libsystem_info/lookup.subproj/libinfo.c:3356` exactly: the name if the id
  is known, `NULL` if not and the second argument is non-zero, otherwise the
  decimal id in a `static char buf[16]`. The name returned is the parser's
  own static field, so it is overwritten by the next lookup — that is the
  real behaviour, not an approximation of it. `ls` and `rm` call these with
  `0`, so they get a name for an unknown id rather than `NULL`.
* `setgrfile(const char *)` is declared by the ravynOS SDK's own
  `<grp.h>` and defined by *no* archive in this tree. It is the runtime form
  of the same redirection the `_RAVYN_GRP_FILE` macro gives at compile time,
  and it is implemented for real rather than left as a link failure.
* `setpassent()` and `setgroupent()` are declared by the SDK's `<pwd.h>` and
  `<grp.h>` and likewise defined nowhere reachable. `libinfo.c:382,559`
  defines each as a synonym for `setpwent()` / `setgrent()`; that is what
  they do here.

## What is deliberately NOT here

`initgroups`, `setgroups` and `getgroups` are **not** implemented. `ls`,
`rm`, `cp` and `mv` do not call any of them — checked in `BSD/bin/ls/*.c`,
`BSD/bin/rm/rm.c`, `BSD/bin/cp` and `BSD/bin/mv` — so implementing them
would be code nothing calls. `getgroups` is already defined in
`libsystem_c/libc_static/libc.a` (`getgroups.o`), which is the real one.

`getgrouplist`, `getpwuuid`, `getgruuid` and the async `*_async_*` family
stay in `libsystem_info`, which is still blocked. Nothing in `ls` or `rm`
reaches them.

## Handover

`BSD/bin/sh/ravynos_port.c` sections 1 and 1b -- the shell's private passwd
parser and its `_pw_stow` / `_pw_copy_out` reentrant wrappers -- should be
deleted, and the shell should link this library instead. This component is a
superset of what that file provides: the same parser with the same three
verified fixes, and on top of that the group database, the `fget*` forms,
the iteration `_r` forms and `user_from_uid`. The compile-time database
override is spelled `_RAVYN_PASSWD_FILE` / `_RAVYN_GROUP_FILE` here; the
shell's copy spells its one `_RAV_PASSWD_FILE`.

One owner for the passwd database is better than two, and two definitions of
`getpwnam` in one link is an error -- the `openat$NOCANCEL` experience. That
file belongs to another worker and this component does not touch it.

## Building

`static/Makefile` builds `libsystem_pwdgrp_static.a` with bmake, in the same
shape as `libsystem_pthread/static` and with the same reason for existing
(a static-link archive that leaves the component's own dylib build alone):

    cd Libraries/Libsystem/libsystem_pwdgrp/static
    bmake -m "$REPO/BSD/share/mk" all

It also installs into `$RAVYN_SDKROOT/usr/local/lib/system/`. Note that
`BSD/share/mk/bsd.sys.mk:539` puts `-D'__counted_by(x)='` and friends on the
command line, which collide with the same macros in the SDK's `sys/cdefs.h`
and produce four `-Wmacro-redefined` warnings. That is pre-existing for every
component built through `bsd.sys.mk`, and both definitions are empty, so
nothing is miscompiled; it is noise, not a defect in this build.

`tools/bootlab/link-static.sh` takes the archive through `RAVYN_EXTRA_LIBS`:

    RAVYN_EXTRA_LIBS="-L$Libraries/Libsystem/libsystem_pwdgrp/static \
                      -lsystem_pwdgrp_static" \
    tools/bootlab/link-static.sh -o /tmp/prog prog.c

`test/run-tests.sh` builds and runs the test suite twice: for the host, so
the results are executed evidence, and for the ravynOS target, so the
archive that actually gets linked is the one that is proven.
`test/build-ls-rm.sh` builds and runs `ls` and `rm`, both ways.

## Header

`libsystem_pwdgrp.h` declares the entry points that neither the SDK's
`<pwd.h>` / `<grp.h>` nor any archive in this tree provides: the historical
BSD `fgetpwent` / `fgetgrent` family and the `*ent_r` iteration forms. A
program includes it alongside the SDK's own headers; the POSIX names are
deliberately not repeated, so each still has exactly one declaration.

## What it unblocked

`ls` and `rm` were both stuck here. Both are now built and running; see
`test/build-ls-rm.sh`, which does the whole thing.

**`rm`** links clean with nothing but this library and
`removefile/libremovefile.a` (for `_removefile`):

    rm-ravyn   1367344 bytes  LC_LOAD_DYLIB=0  undefined=0

**`ls`** links clean with this library plus `libsystem_info.a`, and the
`libsystem_info` it needs is *not* the blocked part. `ls` references four
Open Directory membership functions --
`mbr_uid_to_uuid`, `mbr_gid_to_uuid`, `mbr_uuid_to_id`,
`mbr_identifier_translate` -- which live in `libsystem_info.a`'s
`membership.o`. Two of them are dragged in by `acl_translate.o` inside
`libc.a` (via `ls`'s ACL support) and two by `print.c`'s own
`mbr_identifier_translate` call. `membership.o` is self-contained: the
blocked closure is `libinfo.o` and its `si_*` references, and the linked `ls`
contains **zero** `si_*` symbols, which the script prints.

The host build proves the link is not the whole story. `ls` compiled for the
Darwin host with `pwdgrp.c` in the link binds to *this* `group_from_gid`, and
`ls -l` prints the group name this library read out of the file it opened:

    -rw-r--r--  1 501  wheel   4 ... alpha.txt     <- real /etc/group
    -rw-r--r--  1 501  0       4 ... alpha.txt     <- _RAVYN_GROUP_FILE
                                                        pointed elsewhere

The second line is `libinfo.c:3374`'s own fallback for an id with no name,
and it can only happen if the group file being read is the one this library
opened. Nothing else in that process knows the path.

## The dynamic half

`libsystem_pwdgrp.dylib` is a real MH_DYLIB, built by this directory's
`Makefile`. Verified with `dyld_info -exports` rather than `nm`, because
`nm` has repeatedly let a non-loadable dylib look fine in this project:

    25 exported symbols
    _endgrent _endpwent _fgetgrent _fgetgrent_r _fgetpwent _fgetpwent_r
    _getgrent _getgrent_r _getgrgid _getgrgid_r _getgrnam _getgrnam_r
    _getpwent _getpwent_r _getpwnam _getpwnam_r _getpwuid _getpwuid_r
    _group_from_gid _setgrent _setgrfile _setgroupent _setpassent
    _setpwent _user_from_uid

Its load commands are `libsystem_c.dylib` and `libsystem_platform.dylib` and
nothing else. In particular **not** `libSystem.dylib`, which in this SDK is a
symlink to the 4 KB `libSystem.B.dylib` re-export shim: linking that here
would make this dylib depend on the aggregate that is about to depend on it.
That is why the component's `LDFLAGS` carries `-nodefaultlibs` and does *not*
carry `-umbrella System`, both of which are the opposite of what the sibling
components next door do. See the comments in `Makefile`.

### How it is wired into libSystem.B

Four places, all of which are load-bearing. The first three were the obvious
ones; the fourth was not, and is the reason the generated flag list matters:

1. `Libraries/Libsystem/libsystem_pwdgrp/Makefile` — the new dylib.
2. `Libraries/Libsystem/Makefile`, `SUBDIR` — so the component is built.
3. `Libraries/Libsystem/Makefile`, `LDFLAGS` — `-lsystem_pwdgrp` beside
   `-lsystem_info`, and `-Wl,-reexport-lsystem_pwdgrp` beside the sibling
   re-exports.
4. `Libraries/Libsystem/requiredlibs` — `system_pwdgrp`.

(4) is the one that is easy to miss. `xcodescripts/linker_arguments.sh`
*generates* the re-export flags and the `HAVE_*` config header from what is
actually installed, validated against `requiredlibs`. A name absent from
`requiredlibs` is absent from the generated list no matter what the Makefile
says by hand. With `system_pwdgrp` added, the generated
`linker_arguments.x86_64.normal.txt` now contains `-Wl,-reexport-lsystem_pwdgrp`
and the generated config contains `HAVE_SYSTEM_PWDGRP 1` — the wiring
confirmed by the project's own generator rather than by my assertion.

### The re-export ORDER is the part that matters

`-Wl,-reexport-lsystem_pwdgrp` placed *after* `-Wl,-reexport-lsystem_info`
would have looked complete and changed nothing.

The reason is measured, not assumed. A re-export dylib from this ld64 carries
**no per-symbol attribution at all**: `dyld_info -exports` on the resulting
`libSystem.B` lists no re-exported name whatsoever — not `_getpwnam`, and not
`_printf` either, which is certainly re-exported from `libsystem_c`. The
symbols are not in the export trie and not in the symbol table, because
`libSystem.B`'s own objects never reference them.

Ownership is therefore decided at load time, by the first `LC_REEXPORT_DYLIB`
in the list that exports the symbol. And `libsystem_info.dylib` *does* still
export `getpwnam`/`getpwuid`/… — it has always carried its own
implementation, and that is the component `MISSING_DEPS.md` records as
blocked. So the flag is written **before** the `libsystem_info` one, and the
emitted order was checked to confirm it took:

     18: /usr/lib/system/libsystem_notify.dylib
     19: /usr/lib/system/libsystem_pwdgrp.dylib     <- first
     20: /usr/lib/system/libsystem_info.dylib

`libsystem_info` is still re-exported, for `getaddrinfo`, `gethostbyname` and
the rest of its non-passwd surface.

### Proof that the chain reaches this component

`setgrfile` is declared by the SDK's own `<grp.h>` and was defined by **no**
archive or dylib in this tree before this component. A sweep of
`dyld_info -exports` over every dylib in `$SDK/usr/lib/system` finds it in
exactly one: `libsystem_pwdgrp.dylib`.

So a program that calls only `setgrfile`, linked against a `libSystem.B`,
resolves it through the re-export chain or not at all:

    linked against the NEW libSystem.B:   LINKED
    linked against the CURRENT libSystem.B:  Undefined symbols: "_setgrfile"

`getpwnam` additionally has a second definition in `libsystem_info.dylib`, so
it cannot be tested that way — which is exactly why the ordering above is
the thing that decides it, and why the ordering was fixed rather than
assumed sufficient.

### The dynamic build's own blockers

`libSystem.B` itself does not build today, for a reason that predates and is
unrelated to this component:

* **`libsystem_trace` does not build, and is in `requiredlibs`.** Its
  `log.c` needs the private os_log packing ABI — `struct os_log_pack_s` and
  `_os_log_arg_header` — which lives in xnu-private headers its `-I` list does
  not include and which no SDK header exposes:

      log.c:213: error: invalid application of 'sizeof' to an incomplete
                          type 'struct os_log_pack_s'
      log.c:214: error: use of undeclared identifier '_os_log_arg_header'

  `linker_arguments.sh` refuses to emit anything while a `requiredlibs` name
  is missing, so the failure surfaces twice: as `*** missing required libs ***
  system_trace` from the script, and as the same from the parent
  `Libraries/Libsystem` target. The fix is to vendor the os_log packing
  headers, which is a different task and touches Kernel/xnu; it is named
  here rather than worked around.

So the link was verified by a **control link**: the exact command `bmake`
would run, with only the two `system_trace` tokens removed, written to
`/tmp` so the SDK's working `libSystem.B.dylib` was not clobbered. It links
clean (the only warnings are pre-existing: a duplicate `-lsystem_blocks` that
was already in `LDFLAGS`, and `-lc++` pulling the host's `libc++.a`).

## Regression

`test/run-tests.sh` runs the same suite **four** times:

| build | real database | fixture database |
|---|---|---|
| static object | 89 checks, 0 failures | 120 checks, 0 failures |
| dylib, linked through it | 89 checks, 0 failures | 120 checks, 0 failures |

The dylib run is not a second opinion, it is the same `test-pwdgrp.c` linked
against a shared build of the same `pwdgrp.c` with the same `-D` set. Every
behavioural claim in this README is asserted identically in both: the trailing
`\n`/`\r` strip, the over-long-line drain, the line-length field buffers, the
NIS `+`/`-` skip, empty-vs-not-found distinguishability, `gr_mem` never NULL,
and the rewind-after-EOF that nothing else exercises. The script prints the
two-level bind so the dylib is shown to be loaded rather than assumed:

    (undefined) external _getpwnam      (from libsystem_pwdgrp-real)
    (undefined) external _user_from_uid  (from libsystem_pwdgrp-real)

## Still owed elsewhere

* `BSD/usr.bin/build-ravynos-utils.sh` (utils-batch2) has no `ls`/`rm` entries
  yet. `rm` wants `-lsystem_pwdgrp_static -lremovefile`; `ls` wants
  `-lsystem_pwdgrp_static -lsystem_info`; both want
  `-isystem $SDK/usr/local/include` for `print.c`'s `membershipPriv.h`.
* `libsystem_trace` needs the os_log packing headers vendored before the
  parent `Libraries/Libsystem` target can link at all. Until then the
  dynamic `libSystem.B` in the SDK is a previously-built artifact, not
  something this tree can currently reproduce.
