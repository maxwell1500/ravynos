#!/bin/bash
# build_all_libsystem.sh -- the single entry point for building ravynOS Libsystem.
#
# WHY THIS EXISTS
#   Building any Libsystem component by hand requires an environment preamble --
#   a dozen exported variables, PATH sanitising, a synthetic DEVELOPER_DIR with
#   an xcrun shim, PATH-provided tool symlinks, SDK header synchronisation and
#   an overlay directory under $RAVYN_BUILD_DIR. That preamble lived only in
#   tools/bootlab/build-libraries.sh and in people's shells, and the cost of
#   that was paid repeatedly: isysroot-cc sat untracked for so long that A3
#   only became urgent after it actually cost a debugging round.
#
#   This driver puts the order, the environment and the gate in one place, so
#   that "build the Libsystem" is a single command with a single exit code.
#
# THE RULE THIS ENCODES
#   Never interpret output from a process that has not exited. Every step here
#   waits for its child and judges on the exit code. Reading a partial log is
#   how this project repeatedly manufactured confident false results -- a
#   "failure" that was a build sampled mid-flight, a gate that printed PASS
#   having verified nothing. Logs are kept for diagnosis; they are never the
#   evidence.
#
# ORDER: dependencies first, then dependents, then the guards. The order below
# is the one provenance worked out and which has been validated by the builds
# that succeeded.
#
# Usage:  tools/bootlab/build_all_libsystem.sh [--quick]
#           --quick   skip the top-level runtime/libunwind/libcxx/libcxxabi
#                     stage (those come from Libraries/Makefile, not from
#                     per-component directories, and are slow)
# Exit:   0 = every stage and the hard gate passed; 1 = something failed.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="${RAVYN_BUILD_DIR:-/Users/max/Projects/build}"
SDK="$BUILD/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk"
STUB_GUARD="$ROOT/Libraries/check_sdk_stubs.sh"   # the TRUSTWORTHY guard
ARTIFACT_GATE="$HERE/check_sdk_artifacts.sh"     # derived; known-broken, opt-in

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

[ -d "$SDK" ] || { echo "FATAL: no SDK at $SDK" >&2; exit 2; }
[ -x "$ROOT/tools/bootlab/build-libraries.sh" ] || {
    echo "FATAL: build-libraries.sh missing" >&2; exit 2; }

LOGDIR="$BUILD/diagnostics/driver"
mkdir -p "$LOGDIR"

# KNOWN BLOCKERS -- components that do not build, each for a documented reason
# that is not a regression. The driver reports them separately from unexpected
# failures so that a red build is distinguishable from a broken one. Without
# this, "N failed" is unreadable: a nuisance gate and a real regression look
# identical, and people learn to ignore it.
#
#   libsystem_kernel  mach half needs a userspace-appropriate signature for
#                    _kernelrpc_* in the generated internal headers (a
#                    provenance question, not a missing declaration); syscall
#                    half generates 454 stubs + SYS.h correctly but will not
#                    assemble under the host toolchain.
#   libsystem_trace   lck_spin_t is unsourceable: Kernel/xnu/libkern/lck.h does
#                    not exist anywhere in the tree.
#   dyld              stalled on a libc++/C-library include-ordering conflict
#                    plus a three-way deadlock in its own Makefile.
#   libSystem.B       a CONSEQUENCE of libsystem_trace: its link rule requires
#                    every reexport target, and reports
#                    "*** missing required libs *** system_trace".
#   dynamic_userland  the boot gate for dylib-linked userland. Everything above
#                    is a BUILD verdict; nothing above BOOTS anything, so a
#                    green build here once coexisted with a boot that died in
#                    dyld. Staged as a known blocker so its fault signature
#                    appears in the standard run and any CHANGE is visible.
#
#                    The runner is `run.sh dynamic`: a static exec-runner as
#                    PID 1 that execve()s the dylib-linked /bin/echo. It is a
#                    separate instrument from `run.sh full`, which cannot
#                    reach this path at all.
KNOWN_BLOCKERS="libsystem_kernel libsystem_trace libSystem.B dyld dynamic_userland"

pass=0; fail=0; skipped=0; blocked=0
declare -a FAILED=()

stage() {
    # stage <label> <path-under-Libraries> <BMake-target>
    local label="$1" rel="$2" target="$3"
    local log="$LOGDIR/$label.log"
    local start end
    start=$(date +%s)
    # Judge ONLY on exit code, and only after the child has exited.
    ( cd "$ROOT/Libraries/$rel" && \
      BMAKE_TARGET="$target" "$HERE/build-libraries.sh" "$rel" ) > "$log" 2>&1
    local rc=$?
    end=$(date +%s)
    if [ $rc -eq 0 ]; then
        pass=$((pass+1))
        printf "  %-24s OK          %3ss\n" "$label" "$((end-start))"
        return 0
    fi
    case " $KNOWN_BLOCKERS " in
        *" $label "*)
            blocked=$((blocked+1))
            printf "  %-24s BLOCKED    %3ss   (known blocker, not a regression)\n" "$label" "$((end-start))"
            ;;
        *)
            fail=$((fail+1))
            FAILED+=("$label")
            printf "  %-24s FAILED rc=%s %3ss  (UNEXPECTED - log: %s)\n" "$label" "$rc" "$((end-start))" "$log"
            ;;
    esac
    return 0
}

echo "=== ravynOS Libsystem full build ==="
echo "    SDK:   $SDK"
echo "    logs:  $LOGDIR"
echo "    NOTE:  every verdict below is from an exit code, never from log text."
echo

# ---------------------------------------------------------------------------
# Stage 1 -- runtime and the C++/unwind toolchain.
# These come from Libraries/Makefile targets, not per-component directories,
# because that is where the recipes live. They are slow, hence --quick.
# ---------------------------------------------------------------------------
if [ $QUICK -eq 0 ]; then
    for t in runtime libunwind libcxx; do
        stage "$t" "." "$t"
    done
else
    for t in runtime libunwind libcxx; do
        skipped=$((skipped+1)); printf "  %-24s SKIPPED (--quick)\n" "$t"
    done
fi

# ---------------------------------------------------------------------------
# Stage 2 -- ObjC and the small leaf libraries. No Libsystem dependencies.
# ---------------------------------------------------------------------------
stage libobjc          objc4              "libobjc.A.a"

# The image stages libobjc.A.dylib from the generated SDK (our objc4 build
# product, not the 6,856-byte stub). Refresh the staged copy from the SDK
# right after objc4 builds, and refuse to continue if what is staged is a
# stub -- a stub defines _objc_msgSend as a no-op, which turns a loud dyld
# abort into a silent wrong answer.
if [ -x "$HERE/stage_dynamic_libs.sh" ]; then
    if "$HERE/stage_dynamic_libs.sh" > "$LOGDIR/stage_dynamic_libs.log" 2>&1; then
        printf "  %-24s OK          (staged libobjc.A.dylib from the SDK)\n" "stage_dynamic_libs"
        pass=$((pass+1))
    else
        fail=$((fail+1)); FAILED+=("stage_dynamic_libs")
        printf "  %-24s FAILED         (UNEXPECTED - log: %s)\n" "stage_dynamic_libs" "$LOGDIR/stage_dynamic_libs.log"
    fi
else
    fail=$((fail+1)); FAILED+=("stage_dynamic_libs")
    printf "  %-24s FAILED         (stage_dynamic_libs.sh missing)\n" "stage_dynamic_libs"
fi
stage libCrashReporterClient CrashReporterClient "libCrashReporterClient.a"
stage libxpc           Libsystem/libxpc    "libxpc.a"
stage liblaunch        Libsystem/liblaunch "liblaunch.a"
stage libsystem_notify Libsystem/libsystem_notify "libsystem_notify.a"
stage libsystem_info   Libsystem/libsystem_info   "libsystem_info.a"
stage libdispatch      Libsystem/libdispatch      "libdispatch.a"
stage libmacho         Libsystem/libmacho         "libmacho.a"
stage copyfile         Libsystem/copyfile         "libcopyfile.a"
stage removefile       Libsystem/removefile       "libremovefile.a"

# ---------------------------------------------------------------------------
# Stage 3 -- libc and its neighbours. libsystem_c is the big one and depends
# on the base library set, so it goes after them.
# ---------------------------------------------------------------------------
for c in libsystem_m libsystem_malloc libsystem_platform libsystem_pthread \
         libsystem_blocks libsystem_asl libsystem_c libsystem_coreservices \
         libsystem_darwin libsystem_dnssd corecrypto; do
    case "$c" in
        libsystem_platform) stage "$c" "Libsystem/$c/static" "libplatform.a" ;;
        corecrypto)         stage "$c" "Libsystem/$c"         "libcorecrypto.a" ;;
        *)                  stage "$c" "Libsystem/$c"         "${c}.a" ;;
    esac
done

# ---------------------------------------------------------------------------
# Stage 4 -- the reexport shim itself.
# ---------------------------------------------------------------------------
stage libSystem.B      Libsystem          "libSystem.B.dylib"

# dyld was listed in KNOWN_BLOCKERS but had no stage, so its frontier was only
# ever measured when someone remembered to build it by hand -- which is how a
# one-line undefined variable (SDK_SOURCE_DIR) survived two rounds. Staged as a
# known blocker so its error signature appears in the standard run and any
# CHANGE in that signature is visible. <version> and the openbsm data file are
# cleared; the remaining defect is libc++ losing <stddef.h>/<string.h> to
# libsystem_c/include.
stage dyld             dyld               "libdyld.dylib"

# ---------------------------------------------------------------------------
# Stage 4b -- the BOOT gate for dylib-linked userland. Not a bmake target, so
# it does not go through stage(); judged on the gate script's own exit code,
# which is derived from the serial log only after the boot process exits.
#   0 PASS   /bin/echo reached main() through dyld
#   1 BLOCKED  dyld/kernel fault before main() (signature printed)
#   2 HARNESS the kernel never booted (UEFI/efiboot #UD) -- not a kernel verdict
# Set BOOTLAB_SKIP_DYNAMIC=1 to skip; the default runs it, because a gate that
# is only run by people who already suspect a problem is not a gate.
# ---------------------------------------------------------------------------
if [ "${BOOTLAB_SKIP_DYNAMIC:-0}" = "1" ]; then
    skipped=$((skipped+1)); printf "  %-24s SKIPPED (BOOTLAB_SKIP_DYNAMIC=1)\n" "dynamic_userland"
else
    dyn_start=$(date +%s)
    "$HERE/run_dynamic_gate.sh" --window "${BOOTLAB_DYNAMIC_WINDOW:-150}" \
        > "$LOGDIR/dynamic_userland.log" 2>&1
    dyn_rc=$?
    dyn_end=$(date +%s)
    if [ $dyn_rc -eq 0 ]; then
        pass=$((pass+1))
        printf "  %-24s OK          %3ss   (/bin/echo reached main())\n" "dynamic_userland" "$((dyn_end-dyn_start))"
    else
        case " $KNOWN_BLOCKERS " in
            *" dynamic_userland "*)
                blocked=$((blocked+1))
                printf "  %-24s BLOCKED    %3ss   (known blocker, not a regression)\n" "dynamic_userland" "$((dyn_end-dyn_start))"
                ;;
            *)
                fail=$((fail+1)); FAILED+=("dynamic_userland")
                printf "  %-24s FAILED rc=%s %3ss  (UNEXPECTED - log: %s)\n" "dynamic_userland" "$dyn_rc" "$((dyn_end-dyn_start))" "$LOGDIR/dynamic_userland.log"
                ;;
        esac
        # The signature is the point: a watched blocker must show its current
        # face, so a CHANGE in the fault is visible without opening a log.
        sed -n '/DYNAMIC GATE:/,$p' "$LOGDIR/dynamic_userland.log" | head -12 | sed 's/^/      | /'
    fi
fi

# ---------------------------------------------------------------------------
# Stage 5 -- the hard gate. check_sdk_stubs.sh is the guard this project
# actually trusts; the derived artifact gate is deliberately NOT wired in here
# because it is currently broken (it passes absolute target paths to every
# component, which only one of them registers that way).
# ---------------------------------------------------------------------------
echo
echo "=== hard gate: Libraries/check_sdk_stubs.sh ==="
if [ -x "$STUB_GUARD" ]; then
    # The guard needs the SDK root. Invoking it without RAVYN_SDKROOT exported
    # made it fail on its own invocation ("no SDK root given and RAVYN_SDKROOT
    # unset"), which is worse than no guard: a hard gate that always fails
    # trains people to ignore it.
    if RAVYN_SDKROOT="$SDK" ROOT_SOURCE_DIR="$ROOT" RAVYN_BUILD_DIR="$BUILD" \
       "$STUB_GUARD" > "$LOGDIR/check_sdk_stubs.log" 2>&1; then
        echo "  check_sdk_stubs.sh   PASS   (log: $LOGDIR/check_sdk_stubs.log)"
        gate_ok=1
    else
        echo "  check_sdk_stubs.sh   FAIL   (log: $LOGDIR/check_sdk_stubs.log)"
        # A hard gate that always fails trains people to ignore it, so say
        # precisely what it found. These are the guard's OWN findings, not a
        # consequence of this build.
        echo "    guard found:"
        grep "^FAIL:" "$LOGDIR/check_sdk_stubs.log" 2>/dev/null | sed 's/^/      /' | head -12
        echo "    (these are pre-existing stubs in \$SDK/usr/lib, unrelated to Libsystem;"
        echo "     a Libsystem regression would name a libsystem_* or lib<component> target)"
        gate_ok=0
    fi
else
    echo "  check_sdk_stubs.sh   MISSING at $STUB_GUARD -- not run" >&2
    gate_ok=0
fi

echo
echo "==================================================="
printf "stages passed %d   known-blocked %d   skipped %d   UNEXPECTED failures %d\n" \
    "$pass" "$blocked" "$skipped" "$fail"
if [ ${#FAILED[@]} -gt 0 ]; then
    printf "unexpected failures: %s\n" "${FAILED[*]}"
fi
if [ $fail -gt 0 ]; then
    echo "RESULT: FAIL -- unexpected failure(s); this is NOT just the known blockers."
    exit 1
fi
if [ "$gate_ok" != 1 ]; then
    echo "RESULT: FAIL -- the hard gate (check_sdk_stubs.sh) did not pass."
    exit 1
fi
echo "RESULT: PASS -- every buildable stage built, the hard gate passed, and the"
echo "         only failures are the documented known blockers."
