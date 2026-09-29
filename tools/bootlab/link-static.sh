#!/bin/bash
# Link a statically-linked ravynOS userspace binary.
#
# The output is a MH_EXECUTE Mach-O with zero LC_LOAD_DYLIB and zero
# undefined symbols. dyld is not involved at any stage -- there is no
# dynamic loader, no shared cache, and no DYLD_* / LD_LIBRARY_PATH
# environment involved in running the result.
#
# Why a script and not a Makefile target: the Libsystem build is bmake,
# but this is a per-program link whose inputs are arbitrary .c files from
# outside the build tree (a shell, a probe, a test). It also has to
# verify its own output, which is a shell job.
#
# Usage: tools/bootlab/link-static.sh [-o OUT] [-v] SOURCE.c [SOURCE.c ...]
#
# See Libraries/Libsystem/static/README.md for what a legitimate
# static-link stub is and why the weak-marking of libsystem_pthread's
# memset/bzero/memcpy shims is load-bearing.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="${RAVYN_BUILD_DIR:-/Users/max/Projects/build}"
SDK="$BUILD/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk"
L="$ROOT/Libraries/Libsystem"
STATIC="$L/static"
BMAKE="${BMAKE:-/usr/local/bin/bmake}"

OUT="" VERBOSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        -v) VERBOSE=1; shift ;;
        --) shift; break ;;
        -*) echo "usage: $0 [-o OUT] [-v] SOURCE.c [...]" >&2; exit 2 ;;
        *)  break ;;
    esac
done
[ $# -gt 0 ] || { echo "usage: $0 [-o OUT] [-v] SOURCE.c [...]" >&2; exit 2; }
[ -n "$OUT" ] || { echo "error: -o OUT is required" >&2; exit 2; }
[ -d "$SDK" ] || { echo "missing SDK: $SDK" >&2; exit 1; }

# The stock Xcode/CLI one, for the xcrun shims. Pointing DEVELOPER_DIR at
# the ravynOS build tree breaks every xcrun lookup in the harness.
unset DEVELOPER_DIR

REAL_CC="$(xcrun -f clang)"

# ---------------------------------------------------------------------------
# 1. Make sure the static-variant pthread archive exists.
# ---------------------------------------------------------------------------
# libsystem_pthread/static is the ONLY place -DVARIANT_STATIC is defined
# for pthread. It is a separate subdirectory build precisely so that the
# shared dylib's own compile is untouched -- see the README.
#
# Rebuilt only when missing. `build` is not a dependency of a link: this
# script's job is to link what Libsystem produced, not to decide when
# Libsystem should be rebuilt.
#
# The bmake environment (RAVYN_SDKROOT, ROOT_SOURCE_DIR, the pinned host
# binutils, EXTRA_DEFINES) is NOT re-derived here. Getting it subtly wrong
# produces a build that "succeeds" without the flags that matter, which is
# the exact failure mode build-libraries.sh's comments warn about at
# length. Instead this script re-executes ITSELF with the environment that
# script exports, and only after checking what is actually missing.
PTHREAD_STATIC_A="$L/libsystem_pthread/static/libpthread_static.a"

if [ ! -f "$PTHREAD_STATIC_A" ] && [ "${RAVYN_STATIC_LINK_ENV:-0}" != 1 ]; then
    echo "link-static: $PTHREAD_STATIC_A missing; building it" >&2
    # One level of re-entry. The guard variable makes this terminate even
    # if the build below somehow does not produce the archive.
    RAVYN_STATIC_LINK_ENV=1 \
    REAL_CC="$REAL_CC" \
        "$HERE/build-libraries.sh" --static-pthread-only >&2 || true
fi

if [ ! -f "$PTHREAD_STATIC_A" ]; then
    echo "error: $PTHREAD_STATIC_A is missing and could not be built." >&2
    echo "       Build it with:" >&2
    echo "         tools/bootlab/build-libraries.sh Libsystem" >&2
    echo "       or, to avoid the unrelated libsystem_trace blocker:" >&2
    echo "         cd Libraries/Libsystem/libsystem_pthread && \\" >&2
    echo "           tools/bootlab/build-libraries.sh-env bmake -m \\" >&2
    echo "           $ROOT/BSD/share/mk static" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Compile the program and the residue stubs.
# ---------------------------------------------------------------------------
# The program's own sources are compiled freestanding against the ravynOS
# SDK: -nostdlibinc because there is no usable host libc for the target,
# and -isysroot (not --sysroot) because Apple clang's cc shim ignores a
# custom SDK passed via --sysroot for #include resolution and keeps
# searching the host CommandLineTools SDK. tools/bootlab/isysroot-cc exists
# to absorb that; it is invoked here directly rather than reinvented.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ravyn-static-link.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

CFLAGS_COMMON="-arch x86_64 -isysroot $SDK -mmacos-version-min=15.0 \
	-momit-leaf-frame-pointer -fno-stack-protector -fno-stack-check \
	-fno-builtin -std=gnu11 -Wno-implicit-function-declaration \
	-Wno-int-conversion -Wno-implicit-int"

# RAVYN_EXTRA_CFLAGS / RAVYN_EXTRA_INCLUDES exist for programs that need more
# than a single translation unit's worth of configuration. A one-file utility
# needs nothing; BSD/bin/sh needs -DSHELL (without it bltin/bltin.h runs
# `#undef main' and the echo builtin disappears), -DNO_HISTORY (libedit is not
# built), -DNO_VFORK (the kernel has no vfork), and -I paths for its own
# headers and its generated ones. Rather than re-deriving the archive list and
# the -nodefaultlibs dance in a second script, those programs call this one
# and pass the extra flags here, so there is exactly one static link recipe.
# Word-split on purpose: these are flag strings, not arguments.
CFLAGS_COMMON="$CFLAGS_COMMON ${RAVYN_EXTRA_CFLAGS:-} ${RAVYN_EXTRA_INCLUDES:-}"

OBJS=()
n=0
for src in "$@"; do
    [ -f "$src" ] || { echo "error: no such source: $src" >&2; exit 1; }
    obj="$WORK/o$n.o"
    "$HERE/isysroot-cc" -c $CFLAGS_COMMON -o "$obj" "$src" || exit 1
    OBJS+=("$obj")
    n=$((n + 1))
done

# The residue stubs. Compiled with the same flags so they cannot disagree
# with the rest of the link about types or the ABI.
"$HERE/isysroot-cc" -c $CFLAGS_COMMON -o "$WORK/stubs.o" "$STATIC/stubs.c" \
    || exit 1
OBJS+=("$WORK/stubs.o")

# ---------------------------------------------------------------------------
# 3. Link.
# ---------------------------------------------------------------------------
# -nostdlib:  there is no crt1.o and no libSystem to pick up. The program
#             supplies its own _start (see the README).
# -static:    no dylibs, so nothing to load at run time.
# -e _start:  the program's own entry point.
# -nodefaultlibs plus an explicit -L list: clang would otherwise append
#             -lSystem, which resolves to the placeholder libSystem.B.dylib
#             in the SDK and defeats the entire point of a static link.
# -Wl,-no_uuid: a static binary has no stable identity to record.
LFLAGS="-nostdlib -nostdlibinc -static -arch x86_64 -e _start -Wl,-no_uuid \
	-nodefaultlibs \
	-L$L/libsystem_c/libc_static \
	-L$L/libsystem_kernel \
	-L$L/libsystem_malloc \
	-L$L/libsystem_m \
	-L$L/libsystem_m \
	-L$L/libsystem_platform/static \
	-L$L/libsystem_pthread/static \
	-L$L/libsystem_blocks \
	-L$L/libsystem_kernel/static \
	-L$SDK/usr/lib/system"

# libsystem_m supplies the C99 <math.h> functions. libc.a's printf/gdtoa path
# (gdtoa-hexnan.o) references nan/nanf/nanl, so anything whose float
# formatting is reachable -- /usr/bin/printf, for one -- needs it. These are
# the real math implementations, not residue.
# -lsystem_kernel_static is the ravynOS static-link variant of mach_init, and
# it is listed BEFORE -lsystem_kernel on purpose. ld64 resolves left to
# right, so this archive satisfies every symbol mach_init.o defines --
# _mach_init, _mach_fork_child, _host_page_size, _bootstrap_port,
# _mach_task_self_ and the four vm page-size globals -- and the parent's
# mach_init.o is therefore never pulled. There is no duplicate because the
# variant is a complete copy, not a stub.
#
# The variant exists because upstream mach_init_doit() ends with
# `_pthread_set_self(0)`, which is safe only before libpthread is loaded (see
# static/mach_init.c). A static link has both archives present at once and
# ld64 cannot express "before", so libpthread's dereferencing definition
# wins. The dynamic libsystem_kernel.a is untouched and still has the
# original object.
LIBS="-lc -lsyscalls -lsystem_kernel_static -lsystem_kernel -lmach \
	-lsystem_malloc -lsystem_m \
	-lsystem_platform -lpthread_static -lsystem_blocks \
	-lCrashReporterClient"

# RAVYN_EXTRA_LIBS is the same passthrough for the archive list: a program
# that needs a real static archive beyond the ones above names it here
# rather than forking this script and re-deriving the -nodefaultlibs dance.
# Placed AFTER the built-in LIBS on purpose. ld64 resolves left to right, so
# the built-ins still win for anything both define -- which is what we want
# for libedit, which must not interpose a single libc.a symbol -- while a
# program archive can still resolve what the built-ins leave undefined.
# Word-split on purpose, like RAVYN_EXTRA_CFLAGS above.
LIBS="$LIBS ${RAVYN_EXTRA_LIBS:-}"

echo "link-static: $*" >&2
# shellcheck disable=SC2086
"$REAL_CC" $LFLAGS -o "$OUT" "${OBJS[@]}" $LIBS || exit 1

# ---------------------------------------------------------------------------
# 4. Verify. A link that produced the wrong shape is a failed link.
# ---------------------------------------------------------------------------
fail=0

# Duplicate symbols are a link ERROR, so reaching here means none
# occurred. The check below is therefore about the outcome, not the
# diagnostic: NOUNDEFS in the header flags is ld64's own statement that
# every symbol resolved.
#
# BINDS_TO_WEAK is equally acceptable, and is in fact the expected shape for
# any program that pulls in one of the weak interposers that the static
# pthread variant and stubs.c deliberately contain (the README explains why
# they must be weak rather than suppressed). It means the same thing about
# unresolved symbols -- there are none -- plus that the binary is permitted to
# bind to a weak definition. Rejecting it would make the weak-symbol rule the
# README calls non-optional unbuildable, which is how this check was wrong
# rather than the link.
flags="$(otool -hv "$OUT" | tail -1 | awk '{print $NF}')"
case "$flags" in
    *NOUNDEFS*) ;;
    *BINDS_TO_WEAK*) ;;
    *) echo "link-static: FAIL: Mach header flags are '$flags', expected NOUNDEFS or BINDS_TO_WEAK" >&2
       fail=1 ;;
esac

ndylib="$(otool -l "$OUT" | grep -c '^ *cmd LC_LOAD_DYLIB')"
if [ "$ndylib" -ne 0 ]; then
    echo "link-static: FAIL: $ndylib LC_LOAD_DYLIB, expected 0" >&2
    fail=1
fi

undef="$(nm -u "$OUT" 2>/dev/null | grep -c .)"
if [ "$undef" -ne 0 ]; then
    echo "link-static: FAIL: $undef undefined symbols, expected 0" >&2
    nm -u "$OUT" >&2
    fail=1
fi

if ! otool -l "$OUT" | grep -q 'cmd LC_UNIXTHREAD'; then
    echo "link-static: FAIL: no LC_UNIXTHREAD" >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    rm -f "$OUT"
    exit 1
fi

echo "link-static: OK  $OUT" >&2
echo "link-static:   $(stat -f %z "$OUT") bytes, 0 LC_LOAD_DYLIB, 0 undefined symbols" >&2
[ "$VERBOSE" -eq 1 ] && otool -hv "$OUT" >&2
exit 0
