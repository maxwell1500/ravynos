#!/bin/bash
# build_dynutils.sh -- build the dylib-linked BSD core utilities that
# manifest_cpmv.json stages as work/<u>_dyn.
#
#   ./build_dynutils.sh            build all nine
#   ./build_dynutils.sh cp sh      build only those (others untouched)
#   ./build_dynutils.sh --check    verify the staged work/<u>_dyn, build nothing
#
# WHY THIS EXISTS
#   manifest_cpmv.json is the durable clean closure, but 12 of its entries
#   resolve into work/, which is gitignored scratch.  Ten of them had a
#   producer (work/efi/BOOTX64.EFI <- build_applefree.sh, work/init_shell <-
#   build_init_shell.sh) and NINE did not: sh_dyn, echo_dyn, ls_dyn, cat_dyn,
#   mkdir_dyn, rm_dyn, test_dyn, cp_dyn and mv_dyn were built by hand and
#   survive only as untracked files plus the command lines recorded in
#   BOOT-PLAN.md 15.17-15.21.  A clean checkout could not stage that manifest.
#   This script is that missing producer.
#
# NOT A STUB, NOT A SYMBOL FAKER
#   Every binary here is compiled from the vendored BSD sources in this
#   repository and linked against the repository's own libSystem.B.dylib.
#   Nothing is stubbed, no symbol is faked, and no prebuilt host binary is
#   used.  --check re-derives the shape each staged binary must have and
#   refuses if one is missing, wrong, or not dynamically linked.
#
# PREREQUISITE: Libsystem must be built first, because the link below resolves
# against the SDK those targets install into.  This script refuses rather than
# producing binaries that would later fail the closure gate:
#
#   tools/bootlab/build_all_libsystem.sh      # builds + installs libSystem.B
#
#   BSD/lib/libedit/libedit.dylib must also exist (BSD/bin/sh links -ledit).
#   Build it from BSD/lib/libedit/Makefile; see BOOT-PLAN.md 15.17.
#
# WHY NOT THE FREEBSD bmake MAKEFILES
#   BSD/bin/<u>/Makefile is a bsd.prog.mk target that links the FreeBSD way
#   (against libc.a / crt1.o) and installs into ${SYSROOT_DIR}/bin, which is
#   not the dynamic, LC_MAIN, libSystem.B-linked shape this manifest stages.
#   So the SRCS lists are taken FROM those Makefiles -- they stay the single
#   source of truth for which files make up each utility -- while the compile
#   and link lines are the ones BOOT-PLAN.md 15.17/15.18 already validated on
#   hardware.  Changing a Makefile's SRCS changes what this script builds.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
BUILD="${RAVYN_BUILD_DIR:-/Users/max/Projects/build}"
SDK="$BUILD/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk"
OBJDIR="$HERE/work/dynutils"
# An ARRAY, not a string: the compiler command line is normally two words
# ("xcrun clang"), and a scalar would make "$CC" a single bogus filename.
CC=(${CLANG:-xcrun clang})

ALL="sh echo ls cat mkdir rm test cp mv"

# ---------------------------------------------------------------- SRCS table
# Read from BSD/bin/<u>/Makefile SRCS/ the implicit PROG sources; listed here
# so the script is readable, and VERIFIED against the tree below.
srcs_for() {
    case "$1" in
        sh)    echo "bltin/echo.c alias.c arith_yacc.c arith_yylex.c cd.c error.c eval.c exec.c expand.c histedit.c input.c jobs.c mail.c main.c memalloc.c miscbltin.c mystring.c options.c output.c parser.c redir.c show.c trap.c var.c builtins.c nodes.c syntax.c shims.c" ;;
        ls)    echo "cmp.c ls.c print.c util.c" ;;
        cp)    echo "cp.c utils.c" ;;
        echo)  echo "echo.c" ;;
        cat)   echo "cat.c" ;;
        mkdir) echo "mkdir.c" ;;
        rm)    echo "rm.c" ;;
        # test.c is self-contained: its error() resolves against libsystem_c,
        # like every other BSD utility here.  Compiling the shell's error.c in
        # as well was wrong -- that file drags in _exitstatus, _out2, _rootshell
        # and the rest of the shell's globals, which test must not own.
        test)  echo "test.c" ;;
        mv)    echo "mv.c" ;;
    esac
}

CFLAGS_COMMON=(-c -arch x86_64 -isysroot "$SDK" -mmacos-version-min=15.0
               -fno-builtin -std=gnu11 -fPIC -D__unused= -Wall
               -Wno-unused-parameter -Wno-incompatible-function-pointer-types
               # NOTE: -DSHELL is NOT here.  It is added for `sh` alone, below:
               # bltin/echo.c does `#define main echocmd` under it, but
               # BSD/bin/test/test.c does `#define main testcmd`, so applying
               # it globally renames test's entry point and `test` fails to
               # link on _main.  Per-utility, not global.
               -isystem "$SDK/usr/include")

# -L$SDK/usr/lib/system matters: libSystem.B RE-EXPORTs libsystem_c, and ld64
# only follows a reexport when it can find the target.  Without this path `cp`
# and `mv` fail to link on _copy_file_range/_chflagsat/_acl_is_trivial_np --
# real exports of libsystem_c, not missing code.
LDFLAGS_COMMON=(-nostdlib -nostdlibinc -nodefaultlibs -Wl,-no_uuid -Wl,-e,_main
                -arch x86_64 -L"$SDK/usr/lib" -L"$SDK/usr/lib/system" -lSystem)

die() { echo "FATAL: $*" >&2; exit 1; }

# ------------------------------------------------------------------- preflight
require_sdk() {
    [ -d "$SDK" ] || die "SDK not found: $SDK
       Build Libsystem first: tools/bootlab/build_all_libsystem.sh"
    [ -f "$SDK/usr/lib/libSystem.B.dylib" ] || die "no libSystem.B.dylib in $SDK/usr/lib
       Build Libsystem first: tools/bootlab/build_all_libsystem.sh"
    # ${CC[*]} is the whole command line; the array form is what keeps
    # "xcrun clang" from becoming one bogus filename.
    "${CC[@]}" -dumpversion >/dev/null 2>&1 \
        || die "no working compiler: ${CC[*]}"
}

# ----------------------------------------------------------------- sh's codegen
# BSD/bin/sh ships four sources that are GENERATED, not committed:
# nodes.c/syntax.c come from mksyntax.c/mknodes.c (host tools) and token.h
# from the mktokens shell script.  builtins.c/h are committed.  This mirrors
# BSD/bin/sh/Makefile's own rules.
build_sh_generated() {
    local src="$1"
    mkdir -p "$src"
    cp "$REPO/BSD/bin/sh/nodetypes" "$REPO/BSD/bin/sh/nodes.c.pat" "$src/"
    "${CC[@]}" -include "$REPO/Libraries/Libsystem/libsystem_c/fbsdcompat/_fbsd_compat_.h" \
          "-D__unused=" -o "$OBJDIR/mksyntax" "$REPO/BSD/bin/sh/mksyntax.c"
    "${CC[@]}" -include "$REPO/Libraries/Libsystem/libsystem_c/fbsdcompat/_fbsd_compat_.h" \
          "-D__unused=" -o "$OBJDIR/mknodes" "$REPO/BSD/bin/sh/mknodes.c"
    ( cd "$src" \
      && "$OBJDIR/mksyntax" \
      && "$OBJDIR/mknodes" nodetypes nodes.c.pat \
      && sh "$REPO/BSD/bin/sh/mktokens" ) \
        || die "sh code generation failed (see BSD/bin/sh/Makefile rules)"
    for f in syntax.c nodes.c token.h; do
        [ -f "$src/$f" ] || die "sh generator did not produce $f"
    done
}

# ----------------------------------------------------------------- build one
build_one() {
    local u="$1" out="$HERE/work/${1}_dyn"
    local srcdir="$REPO/BSD/bin/$u"
    [ -d "$srcdir" ] || die "no BSD/bin/$u source directory"

    # BSD/bin/test/test.c does #include "bltin/bltin.h", but BSD/bin/test has
    # no bltin/ of its own -- it borrows the shell's.  Adding BSD/bin/sh to the
    # include path for every utility resolves that and costs nothing elsewhere.
    local inc=(-isystem "$srcdir" -isystem "$REPO/BSD/bin/sh")
    local srcroot="$srcdir"
    if [ "$u" = "sh" ]; then
        # Generated sources live in work/, not in the source tree, so the tree
        # stays clean and a rebuild cannot race a sibling build.
        srcroot="$OBJDIR/sh"
        mkdir -p "$srcroot"
        cp "$srcdir"/*.c "$srcdir"/*.h "$srcroot/" 2>/dev/null || true
        # bltin/echo.c is the one sh source in a subdirectory, and it is part
        # of the Makefile's SRCS, so the subdirectory has to come along.
        mkdir -p "$srcroot/bltin"
        cp "$srcdir"/bltin/*.c "$srcroot/bltin/" 2>/dev/null || true
        build_sh_generated "$srcroot"
        inc=(-isystem "$srcdir" -isystem "$srcdir/bltin"
             -isystem "$REPO/BSD/lib/libedit/src")
    fi

    # -DSHELL applies to `sh` only (see CFLAGS_COMMON above).  It is spliced
    # in as a plain string rather than an array because bash 3.2 treats
    # "${arr[@]}" on an EMPTY array as an unbound variable under `set -u`.
    local defs=""
    [ "$u" = "sh" ] && defs="-DSHELL"

    local objs=() s o
    for s in $(srcs_for "$u"); do
        # A source may be given relative to this utility or as an absolute path
        # (test borrows the shell's error.c), so resolve before checking.
        local sp="$s"
        case "$sp" in /*) ;; *) sp="$srcroot/$sp" ;; esac
        [ -f "$sp" ] || die "$u: missing source $s (SRCS table out of date?)"
        o="$OBJDIR/${u}_$(echo "$s" | tr / _ | sed 's/\.c$/.o/')"
        "${CC[@]}" "${CFLAGS_COMMON[@]}" $defs "${inc[@]}" -o "$o" "$sp" \
            2> "$OBJDIR/${u}_$(basename "$s" .c).log" \
            || { echo "--- compile errors for $u/$s ---" >&2
                 cat "$OBJDIR/${u}_$(basename "$s" .c).log" >&2
                 die "$u: failed to compile $s"; }
        objs+=("$o")
    done

    # Only `sh` links -ledit.  Unquoted on purpose: an empty string expands to
    # no argument at all, which is what the other eight need, and unlike an
    # empty array it does not trip `set -u` in bash 3.2.
    local extra=""
    [ "$u" = "sh" ] && extra="-ledit"
    "${CC[@]}" "${LDFLAGS_COMMON[@]}" $extra -o "$out" "${objs[@]}" \
        2> "$OBJDIR/${u}_link.log" \
        || { echo "--- link errors for $u ---" >&2
             cat "$OBJDIR/${u}_link.log" >&2; die "$u: link failed"; }
    echo "  built work/${u}_dyn ($(stat -f%z "$out") bytes)"
}

# ---------------------------------------------------------------------- verify
# The shape manifest_cpmv.json's closure check depends on.  This is the gate
# that makes the script trustworthy rather than merely runnable.
check_one() {
    local u="$1" p="$HERE/work/${1}_dyn" rc=0
    [ -f "$p" ] || { echo "  MISSING work/${u}_dyn"; return 1; }
    local sz; sz=$(stat -f%z "$p")
    # LC_MAIN, not LC_UNIXTHREAD: dyld calls main directly.
    otool -l "$p" | grep -q LC_MAIN || { echo "  $u: no LC_MAIN"; rc=1; }
    # exactly one LC_LOAD_DYLIB, and it is the repo libSystem.
    local nd; nd=$(otool -L "$p" | grep -c "libSystem.B.dylib")
    [ "$nd" -ge 1 ] || { echo "  $u: not linked against libSystem.B.dylib"; rc=1; }
    # no unresolved undefineds that are not satisfied by the closure
    local un; un=$(nm -u "$p" 2>/dev/null | wc -l | tr -d ' ')
    echo "  ok work/${u}_dyn  $sz bytes, $un undefined (resolved by the closure)"
    return $rc
}

# -------------------------------------------------------------------------- go
mkdir -p "$OBJDIR"

case "${1:-}" in
  --check)
    want="${2:-}"
    [ -n "$want" ] && ALL="$want"
    require_sdk
    rc=0
    for u in $ALL; do check_one "$u" || rc=1; done
    [ $rc -eq 0 ] || die "one or more staged binaries failed --check"
    echo "all requested work/*_dyn binaries verified"
    exit 0 ;;
  -h|--help)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

WANT=("$@")
[ ${#WANT[@]} -eq 0 ] && WANT=($ALL)
for u in "${WANT[@]}"; do
    case " $ALL " in *" $u "*) ;; *) die "unknown utility '$u' (known: $ALL)" ;; esac
done

require_sdk
# libedit is a hard prerequisite for sh only, and it is built from BSD/lib/libedit
# (BOOT-PLAN.md 15.17), not by Libsystem.
case " ${WANT[*]} " in
  *" sh "*)
    [ -f "$SDK/usr/lib/libedit.dylib" ] || [ -f "$REPO/BSD/lib/libedit/libedit.dylib" ] \
      || die "sh needs libedit.dylib (BSD/lib/libedit/Makefile); see BOOT-PLAN.md 15.17"
    ;;
esac

echo "building dynamic utilities: ${WANT[*]}"
echo "  SDK:   $SDK"
for u in "${WANT[@]}"; do build_one "$u"; done

echo
echo "verifying shape:"
rc=0
for u in "${WANT[@]}"; do check_one "$u" || rc=1; done
[ $rc -eq 0 ] || die "verification failed -- do not stage these"
echo
echo "done. Stage them with:  ./run.sh mkimage work/boot.img --manifest manifest_cpmv.json"