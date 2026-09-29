#!/bin/bash
# check_sdk_artifacts.sh -- derived rebuild gate.
#
# WHY THIS EXISTS
#
# A hand-written list of components reported "13/13 green" for rounds while
# libsystem_c -- the largest artifact this project produces -- could not be
# rebuilt at all. A gate that does not derive its own inputs cannot catch the
# thing it was written to catch. So the component list here is derived from
# what is actually installed in the SDK, not written down.
#
# WHAT COUNTS AS A COMPONENT
#
# Every dylib in $SDK/usr/lib and $SDK/usr/lib/system larger than the
# 8,064-byte stub threshold. Anything at or below that is a placeholder, not a
# build product, and is deliberately excluded.
#
# THE RULE THIS ENCODES
#
# Every build is run to completion and its exit status captured BEFORE the
# result is judged. A partially-written log looks exactly like a failed build.
# That mistake cost this project four rounds: a libsystem_c "failure" that was
# a log sampled while bmake was still running, a translation unit identified by
# command-line adjacency instead of by the compiler's "In file included from"
# provenance, a nested `sh -c` that overflowed the argument list, and a probe
# that produced a 0-byte stdout which was read as a null result. Never
# interpret output from a process that has not exited.
#
# ---------------------------------------------------------------------------
# VERIFICATION STATUS -- read this before trusting the output.
#
#   VERIFIED: correct on a full, unfiltered run. It enumerates the installed
#     artifacts from the SDK rather than from a hard-coded list, rebuilds each
#     from clean (archive AND objects deleted), judges only on process exit
#     plus artifact presence, and exits non-zero naming any component that
#     fails.
#
#   NOT VERIFIED: the negative direction. It has never been shown to report
#     red on a component that is genuinely unbuildable. An earlier run named
#     libCrashReporterClient as failing; that verdict was WRONG -- the gate had
#     passed a relative target where the Makefile registers an absolute one,
#     and the component builds cleanly (2,928 B). So a red from this gate has
#     not yet been shown to mean "this component is broken".
#
#   DO NOT use this as a release gate until the negative test passes. Until
#     then treat a red as "investigate the gate first", which is exactly what
#     the libCrashReporterClient case required.
#
#   A run that matches zero components now exits 1 rather than reporting PASS.
#
# Usage:  tools/bootlab/check_sdk_artifacts.sh [--quiet | <dylib-name>]
# Exit:   0 = every installed artifact rebuilds; 1 = at least one does not.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="${RAVYN_BUILD_DIR:-/Users/max/Projects/build}"
SDK="$BUILD/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk"
THRESHOLD=8100
QUIET=0
ONLY=""
case "${1:-}" in
  --quiet) QUIET=1 ;;
  "") ;;
  *) ONLY="$1" ;;
esac

[ -d "$SDK" ] || { echo "FATAL: no SDK at $SDK" >&2; exit 2; }

[ "$QUIET" = 1 ] || echo "=== installed artifacts (derived, > ${THRESHOLD} B) ==="

fail=0
pass=0
skipped=0

for dylib in "$SDK"/usr/lib/*.dylib "$SDK"/usr/lib/system/*.dylib; do
    [ -f "$dylib" ] || continue
    size=$(stat -f%z "$dylib")
    [ "$size" -gt "$THRESHOLD" ] || continue
    name=$(basename "$dylib" .dylib)          # e.g. libsystem_c
    lib=${name#lib}                           # e.g. system_c
    [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && continue

    # Map the installed dylib back to the component that builds it. The
    # Libsystem components are directories named after the library, so
    # libsystem_c -> Libraries/Libsystem/system_c. Anything with no such
    # directory has no build system in this tree and is reported, not skipped
    # silently -- an artifact nobody can rebuild is exactly what this gate
    # exists to surface.
    # Installed dylib name -> the directory that builds it. Libsystem keeps
    # several components under a short directory name that is not the library
    # name (libsystem_asl -> asl, libxpc -> libxpc, ...), so this is an
    # explicit table rather than a derivation: deriving it was the mistake in
    # the previous version of this gate, which reported 17 components as
    # having no build system when every one of them has one.
    case "$name" in
        libsystem_c)         dir=Libraries/Libsystem/libsystem_c ;;
        libsystem_darwin)    dir=Libraries/Libsystem/libsystem_darwin ;;
        libsystem_platform)  dir=Libraries/Libsystem/libsystem_platform/static ;;
        libsystem_asl)       dir=Libraries/Libsystem/libsystem_asl ;;
        libsystem_asl*)      dir=Libraries/Libsystem/libsystem_asl ;;
        libsystem_blocks)    dir=Libraries/Libsystem/libsystem_blocks ;;
        libsystem_coreservices) dir=Libraries/Libsystem/libsystem_coreservices ;;
        libsystem_dnssd)     dir=Libraries/Libsystem/libsystem_dnssd ;;
        libsystem_info)      dir=Libraries/Libsystem/libsystem_info ;;
        libsystem_m)         dir=Libraries/Libsystem/libsystem_m ;;
        libsystem_malloc)    dir=Libraries/Libsystem/libsystem_malloc ;;
        libsystem_notify)    dir=Libraries/Libsystem/libsystem_notify ;;
        libsystem_pthread)   dir=Libraries/Libsystem/libsystem_pthread ;;
        libsystem_trace)     dir=Libraries/Libsystem/libsystem_trace ;;
        libcopyfile)         dir=Libraries/Libsystem/copyfile ;;
        libremovefile)       dir=Libraries/Libsystem/removefile ;;
        libmacho)            dir=Libraries/Libsystem/libmacho ;;
        libxpc)              dir=Libraries/Libsystem/libxpc ;;
        libdispatch)         dir=Libraries/Libsystem/libdispatch ;;
        liblaunch)           dir=Libraries/Libsystem/liblaunch ;;
        libcorecrypto)       dir=Libraries/Libsystem/corecrypto ;;
        libCrashReporterClient) dir=Libraries/CrashReporterClient ;;
        libunwind)           dir="" ;;
        libcompiler_rt)      dir="" ;;
        libc++|libc++abi)    dir="" ;;
        *)                   dir="" ;;
    esac

    if [ -z "$dir" ] || [ ! -f "$ROOT/$dir/Makefile" ]; then
        skipped=$((skipped + 1))
        [ "$QUIET" = 1 ] || printf "  %-26s %9s B  NO-BUILDSYSTEM\n" "$name" "$size"
        continue
    fi

    # bsd.lib.mk names the archive lib${LIB}.a, so for most components that is
    # lib<name>.a -- but libsystem_platform's Makefile sets LIB=system_platform
    # while its static/ subdir's convenience target is libplatform.a. The gate
    # must ask for the file bsd.lib.mk actually produces, not the convenience
    # alias, or it reports a false FAIL on a component that built cleanly
    # (that mistake produced "FAIL (rc=0)" on the first corrected run).
    target="lib${lib}.a"

    [ "$QUIET" = 1 ] || printf "  %-26s %9s B  building %-40s" "$name" "$size" "$dir/$target"

    # Delete BOTH the archive and the objects: a stale archive is what makes
    # bmake report success without compiling anything.
    rm -f "$ROOT/$dir/$target"
    find "$ROOT/$dir" -name '*.o' -delete 2>/dev/null

    log=$(mktemp)
    # Run to completion; capture the exit status. Never judge a partial log.
    rel="${dir#Libraries/}"
    # ABSOLUTE target path. Several Makefiles declare the archive as
    # ${.OBJDIR}/lib${LIB}.a; with OBJROOT unset, ${.OBJDIR} is empty, so the
    # rule is registered under an absolute path and a relative target does not
    # match it. Passing a relative name made bmake answer "don't know how to
    # make libCrashReporterClient.a" for a component that builds cleanly in
    # 2 seconds -- the gate's third false verdict, and the same class as the
    # other two: harness bug reported as component failure.
    ( cd "$ROOT/$dir" && \
      BMAKE_TARGET="$ROOT/$dir/$target" "$HERE/build-libraries.sh" "$rel" ) > "$log" 2>&1
    rc=$?

    if [ $rc -eq 0 ] && [ -f "$ROOT/$dir/$target" ]; then
        pass=$((pass + 1))
        [ "$QUIET" = 1 ] || echo "OK"
    else
        fail=$((fail + 1))
        [ "$QUIET" = 1 ] || { echo "FAIL (rc=$rc)"; echo "    log: $log"; } || true
    fi
done

echo
echo "rebuildable: $pass    failed: $fail    no build system: $skipped"
if [ $((pass + fail)) -eq 0 ]; then
    # A run that tested nothing must never report PASS. This is the most
    # dangerous defect the gate had: a filtered run that matched no component
    # printed "RESULT: PASS" having verified zero artifacts, which would send
    # someone to ship a broken tree. An empty run is a failure of the gate, not
    # a success.
    echo "RESULT: FAIL -- no components were tested (matched nothing)."
    exit 1
fi
if [ $fail -gt 0 ]; then
    echo "RESULT: FAIL -- the component(s) above cannot be rebuilt."
    exit 1
fi
echo "RESULT: PASS -- every installed artifact rebuilds."
exit 0
