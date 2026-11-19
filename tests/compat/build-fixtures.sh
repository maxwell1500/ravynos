#!/bin/bash
# build-fixtures.sh -- build the ABI conformance fixtures with Apple's tools.
#
# Run on the development Mac, not in the guest.  The resulting binaries are
# Mach-O for x86_64 macOS 10.13, built from Apple's SDK by Apple's clang: they
# contain no ravynOS code and no ravynOS headers.  Running them in the guest
# is therefore a test of ravynOS's compatibility, not of our SDK agreeing
# with itself.
#
# Output:
#   tests/compat/out/posix
#   tests/compat/out/CocoaProbe.app/Contents/MacOS/CocoaProbe
#   tests/compat/out/CocoaProbe.app/Contents/Info.plist

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
CC="$(xcrun -f clang)"
TARGET="x86_64-apple-macos10.13"

rm -rf "$OUT"
mkdir -p "$OUT/CocoaProbe.app/Contents/MacOS"

echo "building posix fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -o "$OUT/posix" "$HERE/posix.c"

# Foundation correctness (Phase 1): NSFileManager modern API, NSDecimalNumber,
# NSInvocation and NSProcessInfo.
echo "building foundation fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -framework Foundation -o "$OUT/foundation" "$HERE/foundation.m"

# File-backed mmap: Firefox renders glyphs from a mapped font file, so an
# mmap that serves stale or zero pages would look exactly like a text
# rendering bug.  The probe compares mmap bytes against pread().
echo "building filemmap fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -o "$OUT/filemmap" "$HERE/filemmap.c"

# PS/2 mouse delivery: the WS cursor must move under injected motion; this
# probe separates "no packets reach /dev/mouse" from "the consumer drops
# them" by counting bytes on the device itself.
echo "building mousetest fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -o "$OUT/mousetest" "$HERE/mousetest.c"

# The zone-dispatch fixture: free() must return each pointer to the zone that
# owns it, even when another registered zone claims everything.
echo "building malloczone fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -Wno-nullability-completeness -Wno-unused-command-line-argument \
    -o "$OUT/malloczone" "$HERE/malloczone.c"

echo "building bootstrap probe ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/bootstrap_probe" "$HERE/bootstrap_probe.c"

echo "building spawn rendezvous probe ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/spawnprobe" "$HERE/spawnprobe.c"

echo "building passwd fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/passwd" "$HERE/passwd.c"

echo "building layertest fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -framework Cocoa -framework QuartzCore \
    -o "$OUT/layertest" "$HERE/layertest.m"

echo "building screeninfo fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -framework Cocoa -framework ApplicationServices \
    -o "$OUT/screeninfo" "$HERE/screeninfo.m"

echo "building tsample fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/tsample" "$HERE/tsample.c"

echo "building tdump fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/tdump" "$HERE/tdump.c"

echo "building spinkill fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/spinkill" "$HERE/spinkill.c"

echo "building runas fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/runas" "$HERE/runas.c"

echo "building pasteboard fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/pasteboard" "$HERE/pasteboard.m" -framework Cocoa

echo "building backup fixture ($TARGET)"
$CC -target $TARGET -isysroot "$SDK" -O2 -Wall -o "$OUT/backup" "$HERE/backup.c"

echo "building autorelease fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/autorelease" "$HERE/autorelease.m" -framework Foundation

echo "building plist fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/plist" "$HERE/plist.m" -framework Foundation

echo "building perms fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/perms" "$HERE/perms.c"

echo "building sandbox fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/sandbox" "$HERE/sandbox.c"

echo "building tcp fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -o "$OUT/tcp" "$HERE/tcp.c"
echo "building dnstest fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -o "$OUT/dnstest" "$HERE/dnstest.c"

# printf conversion set: %zu and %g were printing "<UNSUPPORTED-CONVERSION>"
# in WindowServer and Dock diagnostics.
echo "building printfprobe fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -o "$OUT/printfprobe" "$HERE/printfprobe.c"


echo "building cocoa fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/CocoaProbe.app/Contents/MacOS/CocoaProbe" "$HERE/cocoa.m" \
    -framework Cocoa

echo "building openurl fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/openurl" "$HERE/openurl.m" \
    -framework Cocoa

echo "building download fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/download" "$HERE/download.m" -framework Foundation


echo "building homechain fixture ($TARGET)"
# NSPlatform exists only in the guest Foundation; leave it undefined and let
# the guest's dynamic lookup bind it at load, like the SDK frameworks do.
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -Wl,-undefined,dynamic_lookup \
    -o "$OUT/homechain" "$HERE/homechain.m" -framework Foundation
# Click routing oracle: proves which view (not just which window) receives a
# press, so a click that lands on the wrong control is distinguishable from
# one that never reaches the app.
echo "building clickprobe fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/clickprobe" "$HERE/clickprobe.m" -framework Cocoa

cat > "$OUT/CocoaProbe.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CocoaProbe</string>
    <key>CFBundleIdentifier</key>
    <string>com.ravynos.compat.CocoaProbe</string>
    <key>CFBundleName</key>
    <string>CocoaProbe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>
</dict>
</plist>
PLIST

# Proof of what was built, recorded next to it so a stale fixture cannot be
# mistaken for a fresh one.
file "$OUT/posix" "$OUT/tcp" "$OUT/CocoaProbe.app/Contents/MacOS/CocoaProbe"
echo "fixtures built in $OUT"
