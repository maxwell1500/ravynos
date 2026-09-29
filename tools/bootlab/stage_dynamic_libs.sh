#!/bin/bash
# stage_dynamic_libs.sh -- put OUR source-built dylibs where the image can
# stage them, and refuse to stage a stub in their place.
#
# WHY THIS EXISTS
#   /usr/lib/libobjc.A.dylib is required by libsystem_symptoms.dylib, which
#   every dynamic userland binary pulls in. Until 2026-09-27 nothing staged
#   it, and the dynamic-userland boot died with
#       Library not loaded: /usr/lib/libobjc.A.dylib
#   The file that sat in assets/usr/lib/ was a 6,856-byte build_stubs.sh
#   placeholder with 45 defined symbols. It is NOT interchangeable with the
#   real artifact: it defines _objc_msgSend and _objc_msgSendSuper2 as
#   no-ops at 0x540/0x550, so staging it would convert a loud dyld abort into
#   a silent wrong answer the first time anything called an Objective-C
#   method. That is the exact class of failure this project exists to kill,
#   so the copy is verified rather than trusted.
#
# WHERE THE FILE COMES FROM -- a deliberate decision, stated once
#   It is a BUILD PRODUCT of our own objc4, not an Apple-derived blob, and
#   assets/usr/lib/ is gitignored (see the untrack-Apple-assets decision).
#   So it is COPIED BY THIS SCRIPT from the generated SDK on every run, and
#   never committed. A committed blob would rot silently against objc4.
#
# Usage: tools/bootlab/stage_dynamic_libs.sh [--check]
#          --check   verify what is staged, copy nothing; non-zero if not real
# Exit:  0 staged/verified real; 1 stub or missing; 2 no source artifact
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="${RAVYN_BUILD_DIR:-/Users/max/Projects/build}"
SDK="$BUILD/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk"
# The build product of Libraries/objc4, as installed into the generated SDK.
SRC="$SDK/usr/lib/libobjc.A.dylib"
DST="$HERE/assets/usr/lib/libobjc.A.dylib"
# dyld loads /usr/lib/system/libobjc.dylib -- a DIFFERENT path from the
# usr/lib/libobjc.A.dylib staged above. Measured 2026-09-26 from the dynamic
# gate: "Library not loaded: /usr/lib/system/libobjc.dylib", and the only
# libobjc under the manifest's usr/lib/system/ glob was the 6,856-byte
# build_stubs.sh placeholder. So the same real artifact is staged at both
# paths. One script, two destinations, both verified by the same check.

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# A real libobjc is ~1.6 MB and defines ~2100 symbols. The placeholder is
# under 10 KB and defines 45. Size alone separates them, and the export
# check is independent of size, so both are asserted.
MIN_SIZE=1000000
REQUIRED_EXPORT=_objc_msgSend

verify_real() {
    # verify_real <file> -> 0 if it is the real artifact, 1 otherwise
    local f="$1" size defs
    [ -f "$f" ] || return 1
    size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null) || return 1
    if [ "$size" -lt "$MIN_SIZE" ]; then
        echo "  NOT REAL: $f is $size bytes (< $MIN_SIZE): that is the stub" >&2
        return 1
    fi
    defs=$(nm -gU "$f" 2>/dev/null | grep -cE '^[0-9a-f]+ [TSDB] ')
    if [ "${defs:-0}" -lt 500 ]; then
        echo "  NOT REAL: $f defines $defs symbols (< 500)" >&2
        return 1
    fi
    if ! nm -gU "$f" 2>/dev/null | grep -qE "^[0-9a-f]+ T $REQUIRED_EXPORT\$"; then
        echo "  NOT REAL: $f does not define $REQUIRED_EXPORT" >&2
        return 1
    fi
    echo "  real: $f ($size bytes, $defs defined symbols, $REQUIRED_EXPORT present)"
    return 0
}

if [ $CHECK_ONLY -eq 0 ]; then
    if [ ! -f "$SRC" ]; then
        if verify_real "$DST"; then
            echo "  no SDK artifact at $SRC; keeping the verified staged copy"
            exit 0
        fi
        echo "FATAL: no libobjc build product at $SRC and nothing real staged." >&2
        echo "       Build it: tools/bootlab/build_all_libsystem.sh (stage libobjc)" >&2
        exit 2
    fi
    verify_real "$SRC" || { echo "FATAL: refusing to stage a non-real $SRC" >&2; exit 2; }
    mkdir -p "$(dirname "$DST")"
    cp -f "$SRC" "$DST"
    echo "  staged $DST <- $SRC"
fi

verify_real "$DST" || {
    echo "FATAL: $DST is missing or is a stub. The image must not ship a stub." >&2
    exit 1
}

# Second destination: /usr/lib/system/libobjc.dylib, which is the path dyld
# actually resolves. Same source, same verification, same idempotent copy --
# the manifest's usr/lib/system/ glob stages whatever sits in that directory,
# and until now that was the 6,856-byte build_stubs.sh placeholder.
DST_SYSTEM="$HERE/assets/usr/lib/system/libobjc.dylib"
if [ "$CHECK_ONLY" = 0 ]; then
    verify_real "$SRC" || { echo "FATAL: refusing to stage a non-real $SRC" >&2; exit 2; }
    mkdir -p "$(dirname "$DST_SYSTEM")"
    cp -f "$SRC" "$DST_SYSTEM"
    echo "  staged $DST_SYSTEM <- $SRC"
fi
verify_real "$DST_SYSTEM" || {
    echo "FATAL: $DST_SYSTEM is missing or is a stub. dyld loads this exact path." >&2
    exit 1
}
exit 0
