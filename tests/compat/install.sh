#!/bin/bash
# install.sh -- stage the conformance fixtures where make_gui_manifest.py
# picks them up, and prove they were built by Apple's toolchain.
#
#   tests/compat/build-fixtures.sh     # once per change to the fixtures
#   tests/compat/install.sh            # stage into tools/bootlab/work/compat
#
# The staged tree is a *copy*: work/ is scratch, and the manifest's freshness
# rule compares the staged copy against this directory's sources, so a stale
# fixture is caught by closure_gate.py instead of being run silently.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/out"
STAGE="$ROOT/tools/bootlab/work/compat"

[ -x "$OUT/posix" ] || { echo "missing $OUT/posix -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/tcp" ] || { echo "missing $OUT/tcp -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/malloczone" ] || { echo "missing $OUT/malloczone -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/autorelease" ] || { echo "missing $OUT/autorelease -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/backup" ] || { echo "missing $OUT/backup -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/sandbox" ] || { echo "missing $OUT/sandbox -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/perms" ] || { echo "missing $OUT/perms -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/runas" ] || { echo "missing $OUT/runas -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/passwd" ] || { echo "missing $OUT/passwd -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/bootstrap_probe" ] || { echo "missing $OUT/bootstrap_probe -- run build-fixtures.sh" >&2; exit 1; }
[ -x "$OUT/CocoaProbe.app/Contents/MacOS/CocoaProbe" ] || {
    echo "missing CocoaProbe -- run build-fixtures.sh" >&2; exit 1; }

for f in "$OUT/posix" "$OUT/tcp" "$OUT/malloczone" "$OUT/autorelease" "$OUT/backup" "$OUT/sandbox" "$OUT/perms" "$OUT/runas" "$OUT/passwd" "$OUT/bootstrap_probe" "$OUT/CocoaProbe.app/Contents/MacOS/CocoaProbe"; do
    if ! file "$f" | grep -q "Mach-O 64-bit executable x86_64"; then
        echo "$f is not an x86_64 Mach-O executable" >&2
        exit 1
    fi
done

rm -rf "$STAGE"
mkdir -p "$STAGE/CocoaProbe.app/Contents/MacOS"
cp -p "$OUT/posix" "$STAGE/posix"
cp -p "$OUT/tcp" "$STAGE/tcp"
cp -p "$OUT/pasteboard" "$STAGE/pasteboard"
cp -p "$OUT/malloczone" "$STAGE/malloczone"
cp -p "$OUT/autorelease" "$STAGE/autorelease"
cp -p "$OUT/backup" "$STAGE/backup"
cp -p "$OUT/sandbox" "$STAGE/sandbox"
cp -p "$OUT/perms" "$STAGE/perms"
cp -p "$OUT/runas" "$STAGE/runas"
cp -p "$OUT/passwd" "$STAGE/passwd"
cp -p "$OUT/bootstrap_probe" "$STAGE/bootstrap_probe"
cp -p "$OUT/CocoaProbe.app/Contents/MacOS/CocoaProbe" \
      "$STAGE/CocoaProbe.app/Contents/MacOS/CocoaProbe"
cp -p "$OUT/CocoaProbe.app/Contents/Info.plist" \
      "$STAGE/CocoaProbe.app/Contents/Info.plist"
cp -p "$HERE/run-fixtures.sh" "$STAGE/run-fixtures.sh"

echo "staged fixtures in $STAGE"
