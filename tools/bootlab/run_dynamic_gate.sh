#!/bin/bash
# run_dynamic_gate.sh -- the dynamic-userland acceptance gate.
#
# WHAT IT IS FOR
#   `run.sh full` boots to userland, PID 1 ticks, verdict clean -- and proves
#   nothing about dyld, because its PID 1 execs nothing. Every dylib-linked
#   binary is untested by the headline gate. This gate is the instrument that
#   closes that hole: it stages a static exec-runner as PID 1, which
#   execve()s the dylib-linked /bin/echo, and judges on whether that binary
#   reached main().
#
# HOW IT JUDGES
#   Only three outcomes count, and each is read from the serial log AFTER the
#   boot process has exited:
#     PASS   /bin/echo ran: it printed RAVYN-DYNAMIC-USERLAND-OK.
#     BLOCKED the kernel panicked or dyld aborted before main(). The fault
#             signature is printed verbatim so a CHANGE in it is visible.
#     HARNESS the kernel never started (UEFI/efiboot stage, no PID 1 banner).
#             That is the known #UD-at-0xB0000 firmware trap, not a kernel
#             verdict, and it must never be reported as a kernel failure.
#
# Usage: tools/bootlab/run_dynamic_gate.sh [--window SECONDS] [--no-build]
# Exit:  0 PASS, 1 BLOCKED (dyld/kernel fault), 2 HARNESS problem
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# WINDOW is the KERNEL's boot budget, not a total for the run. boot.py arms
# its clock at the instant it sends the boot command (see the comment there),
# so this number means one thing: seconds the kernel gets.
#
# 600 is chosen for MARGIN, not to hit a discovered value. The measurements
# behind it, 2026-09-27:
#   - The one run that reached PID 1 had 137.6s of kernel budget (window 150
#     counted from QEMU launch, boot command at 12.4s -> 150 - 12.4).
#   - A run given a FULL 150s of kernel budget did NOT reach PID 1. It stopped
#     at 'bsd_init: calling mbinit', the same absolute position as the
#     successful run, having produced 518 of that run's 777 lines.
#   - So the old 150s default was NOT an order of magnitude too small; it sat
#     about 9% under the one budget that had worked.
#
# ⚠️ RETRACTED, and left visible because the error is the lesson. An earlier
# version of this comment also said the kernel "ran about 39% slower" on the
# failing runs (3.45 lines/s against 5.65) and extrapolated an absolute
# minimum near 225s from it. THAT WAS WRONG, and it was refuted by direct
# measurement: with 300s and with 600s of kernel budget the run produced
# 39,330 and 39,343 serial bytes respectively -- THIRTEEN BYTES and zero extra
# lines for double the time. The two logs are functionally identical once
# addresses are normalised. The system was not slow, it was HUNG, at the same
# point in both. Do not reason about boot cost from serial-byte rate on this
# harness; a run that stops moving produces no bytes no matter how long it is
# given, and that looks identical to "slow" if you only compare totals.
#
# What is actually established: 150s genuinely truncated (that run is still
# recorded), and giving the kernel its own budget took it from 0 bsd_init
# calls to 37. What is NOT established: what a COMPLETED run needs, because
# the completed case is now a hang in dyld rather than a run that runs out of
# time. 600 is therefore margin, not a derived threshold.
# The failure mode 150s causes is the expensive one: two consecutive runs
# returned exit 2 (HARNESS) rather than a verdict, because the kernel was
# healthy and still coming up when the window closed. That reads exactly like
# "the kernel did not boot" and is not a kernel result.
#
# Underlying variance worth knowing about: firmware Shell-prompt latency has
# been observed at both ~12.4s and ~57s in one session on the same image with a
# freshly-copied vars.fd, and across four runs it split the outcomes perfectly
# (12.4s reached PID 1; 55.7s and 57.1s both truncated). That correlation is
# NOT established as a mechanism -- n=3 with a possible common cause -- but a
# harness variable nobody was measuring was deciding whether a boot was
# readable at all, which is why the margin here is generous.
WINDOW=600
BUILD=1
while [ $# -gt 0 ]; do
    case "$1" in
        --window) WINDOW="$2"; shift 2 ;;
        --no-build) BUILD=0; shift ;;
        *) echo "usage: $0 [--window N] [--no-build]" >&2; exit 2 ;;
    esac
done

IMG="work/boot_dynamic.img"
LOG="work/serial_dynamic.log"
# boot.py re-copies assets/vars.fd on every run, which is required: a stale
# pflash file faults at handoff. (It is NOT sufficient -- see README gotchas.)
PASS_SIG="RAVYN-DYNAMIC-USERLAND-OK"

# Never ship the stub: this gate is meaningless if the dylib it loads is a
# placeholder that defines two entry points and no-ops them.
if ! ./stage_dynamic_libs.sh; then
    echo "DYNAMIC GATE: ABORT -- libobjc.A.dylib is missing or is a stub"
    exit 2
fi

if [ $BUILD -eq 1 ]; then
    ./build_init_exec.sh || { echo "DYNAMIC GATE: ABORT -- runner build failed"; exit 2; }
    # P1 (2026-10-02): manifest_dynamic.json stages work/echo_dyn and
    # work/sh_dyn, not the Apple product binaries that used to sit in
    # assets/bin/ (quarantined; see assets-quarantine/QUARANTINE_INVENTORY.txt).
    # The manifest therefore depends on work/ products, so this gate must build
    # them or it would be gating an unbuildable tree.  build_dynutils.sh is the
    # producer; it is skipped when the products are already present so a rerun
    # costs nothing.
    if [ ! -f work/echo_dyn ] || [ ! -f work/sh_dyn ]; then
        ./build_dynutils.sh || { echo "DYNAMIC GATE: ABORT -- dynutils build failed"; exit 2; }
    fi
    if [ ! -f work/stripped_kernel.development ]; then
        echo "FATAL: no kernel payload; run tools/bootlab/run.sh build first" >&2
        exit 2
    fi
    # THE BUILD GATE (PROVENANCE-PLAN P2).  Judged on the same manifest
    # mkimage.py is about to be given, so gating a tree cannot diverge from
    # building it.  This is the second line of defence, not the first: it
    # exists because 31 host-extracted dylibs are still in assets/, and five
    # runner scripts can put them on a disk.  Every one of those five runs
    # this same gate on its own manifest.
    python3 closure_gate.py manifest_dynamic.json || {
        echo "DYNAMIC GATE: ABORT -- closure/provenance gate refused"; exit 2; }
    python3 mkimage.py "$IMG" --manifest manifest_dynamic.json || {
        echo "DYNAMIC GATE: ABORT -- image build failed"; exit 2; }
else
    # --no-build: the image already exists, so judge the IMAGE rather than
    # the manifest.  closure_check.py --image reads each staged path back out
    # of the finished FAT32 image and scans those bytes, which is the only
    # form of the question that is about what is about to boot.  A manifest
    # edited after the build would otherwise pass while a borrowed dylib sat
    # in the image.
    [ -f "$IMG" ] || { echo "DYNAMIC GATE: ABORT -- --no-build but no $IMG"; exit 2; }
    python3 closure_gate.py manifest_dynamic.json --image "$IMG" || {
        echo "DYNAMIC GATE: ABORT -- closure/provenance gate refused $IMG"; exit 2; }
fi

echo "--- dynamic-userland gate: booting $IMG (window ${WINDOW}s) ---"
python3 boot.py --img "$IMG" --mode full --window "$WINDOW" --out "$LOG"
# boot.py exits 1 whenever there are no "alive tick" lines, which is expected
# here: the gate's PID 1 execs and does not tick. The verdict below comes from
# the log, never from that exit code.

[ -f "$LOG" ] || { echo "DYNAMIC GATE: HARNESS -- no serial log produced"; exit 2; }

banner=$(grep -c "RAVYNOS DYNAMIC-USERLAND GATE: execve" "$LOG")
passed=$(grep -c "$PASS_SIG" "$LOG")

# HARNESS first: if PID 1 never announced itself, nothing after it means
# anything, and a panic line from a run that never booted would be a fiction.
if [ "$banner" -eq 0 ]; then
    echo
    echo "DYNAMIC GATE: HARNESS PROBLEM -- PID 1 never ran; the kernel did not boot."
    echo "  (known: UEFI/efiboot '#UD at RIP 0xB0000 / Can't find image information'."
    echo "   Re-run: it is a firmware-stage fault, not a kernel verdict.)"
    echo "  last line: $(tail -1 "$LOG")"
    exit 2
fi

if [ "$passed" -gt 0 ]; then
    echo
    echo "DYNAMIC GATE: PASS -- /bin/echo reached main() through dyld"
    echo "  signature: $PASS_SIG"
    echo "  log: $LOG"
    exit 0
fi

echo
echo "DYNAMIC GATE: BLOCKED -- /bin/echo did not reach main(). Fault signature:"
# Quote the fault verbatim: the point of a watched blocker is that its
# signature is visible and any change in it is obvious.
grep -nE "Library not loaded|dyld-exc|dyld-fault|exit reason namespace|initproc failed to start|DYNAMIC-GATE-FAIL|panicked|Exception Type|cr2 *=" "$LOG" | head -20
echo "  full log: $LOG"
exit 1
