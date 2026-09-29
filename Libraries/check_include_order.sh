#!/bin/bash
# Verify the include-ordering invariant that private/os/assumes.h depends on.
#
# WHY THIS EXISTS
#
# private/os/assumes.h MUST use `#include <os/log.h>` (angled), not
# `#include "log.h"` (quoted). `#include_next` only advances when the current
# file was itself found BY POSITION in the -I list. A quoted include resolves
# relative to the including file's own directory, so the shim's os/log.h is
# entered with NO position, and its own `#include_next <os/log.h>` then has
# nothing to advance from -- clang considers ZERO candidates and fails with
#
#   fatal error: 'os/log.h' file not found
#
# even though several -I entries remain and Kernel/xnu/libkern does contain
# os/log.h. That exact failure was breaking libsystem_asl.
#
# With the angled form the chain is entered by position, and it only terminates
# correctly if the generated OVERLAY directory is on the -I list BEFORE every
# other os/log.h provider. That ordering is produced by tools/bootlab/isysroot-cc
# (the include-overlay mechanism), which is owned by another worker.
#
# A guard that cannot prove it is active is the same as no guard -- that is the
# same lesson as the CrashReporterClient stub-writer, the undefined $HERE, and
# the eventlink shim gated behind the wrong flag. So this script MEASURES the
# resolved path rather than assuming it.
#
# USAGE:  Libraries/check_include_order.sh
# Exits non-zero if the shim pair is not resolving as designed.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${RAVYN_SDKROOT:-/Users/max/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk}"
CC="$ROOT/tools/bootlab/isysroot-cc"
[ -x "$CC" ] || { echo "check_include_order: $CC not executable" >&2; exit 2; }
[ -d "$SDK" ] || { echo "check_include_order: no SDK at $SDK" >&2; exit 2; }

fail=0
TMP="$(mktemp -d)"
printf '#include <os/assumes.h>\nint main(void){return 0;}\n' > "$TMP/t.c"

# The -I list libsystem_c/libsystem_asl actually use. Mirrors their Makefiles.
set -- -isysroot"$SDK" -w -DXNU_PLATFORM_MacOSX -DPRIVATE -D__DARWIN_UNIX03 \
  -I "$ROOT/Libraries/Libsystem/private" \
  -I "$ROOT/Kernel/xnu/libkern" -I "$ROOT/Kernel/xnu/bsd" \
  -I "$SDK/usr/local/include" -I "$SDK/usr/local/include/kernel" \
  -I "$SDK/usr/include" \
  -I "$SDK/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders"

echo "== include-order check: private/os shim pair =="

# 1. the shim must use the angled form
if grep -q '^#include "log\.h"' "$ROOT/Libraries/Libsystem/private/os/assumes.h"; then
  echo "FAIL: private/os/assumes.h uses a QUOTED #include \"log.h\"."
  echo "      That enters os/log.h with no -I position, so its #include_next has"
  echo "      nothing to advance from and fails with 'os/log.h file not found'."
  fail=1
else
  echo "  ok: assumes.h does not use a quoted log.h include"
fi

# 2. the pair must both exist
for f in private/os/assumes.h private/os/log.h; do
  [ -f "$ROOT/Libraries/Libsystem/$f" ] || { echo "FAIL: missing $f"; fail=1; }
done
[ "$fail" = 1 ] && exit 1

# 3. PROVE the chain resolves: compile it and record where each header came from
if "$CC" -E -H "$@" "$TMP/t.c" > "$TMP/out" 2>"$TMP/err"; then
  echo "  ok: <os/assumes.h> compiles through the shim pair"
else
  echo "FAIL: <os/assumes.h> does not compile. First errors:"
  grep -m3 "error:" "$TMP/err" | sed 's/^/      /'
  fail=1
fi

# 4. VERIFY the resolved paths, not just that it compiled. The provisional
#    header must come from the overlay (position-resolved), and the real one
#    from a later -I entry.
prov=$(grep -m1 "os/log\.h$" "$TMP/err" | sed 's/^[*[:space:]]*//')
real=$(grep "os/log\.h$" "$TMP/err" | sed 's/^[*[:space:]]*//' | tail -1)
echo "  provisional os/log.h resolved from: ${prov:-<none>}"
echo "  real        os/log.h resolved from: ${real:-<none>}"

case "$prov" in
  */Tools/inc-*/os/log.h|*/Libraries/Libsystem/private/os/log.h)
    echo "  ok: the provisional header is the shim's own copy" ;;
  *)
    echo "FAIL: the provisional os/log.h did not resolve to the shim's copy."
    echo "      If this is the SDK's or xnu's copy, the ordering invariant is broken."
    fail=1 ;;
esac

case "$real" in
  */Kernel/xnu/libkern/os/log.h|*/System.framework/*/os/log.h)
    echo "  ok: the chain terminated on a real os/log.h provider" ;;
  *)
    echo "FAIL: the chain did not terminate on a real os/log.h provider."
    fail=1 ;;
esac

rm -rf "$TMP"
if [ "$fail" = 0 ]; then
  echo "== OK: the shim pair is resolving as designed =="
else
  echo "== FAILED: the include-order invariant is not satisfied =="
fi
exit $fail
