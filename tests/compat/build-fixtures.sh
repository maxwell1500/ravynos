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

# The zone-dispatch fixture: free() must return each pointer to the zone that
# owns it, even when another registered zone claims everything.
echo "building malloczone fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -Wno-nullability-completeness -Wno-unused-command-line-argument \
    -o "$OUT/malloczone" "$HERE/malloczone.c"

echo "building bootstrap probe ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/bootstrap_probe" "$HERE/bootstrap_probe.c"

echo "building passwd fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/passwd" "$HERE/passwd.c"

echo "building runas fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/runas" "$HERE/runas.c"

echo "building pasteboard fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/pasteboard" "$HERE/pasteboard.m" -framework Cocoa

echo "building autorelease fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/autorelease" "$HERE/autorelease.m" -framework Foundation

echo "building tcp fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall -Wextra \
    -o "$OUT/tcp" "$HERE/tcp.c"

echo "building cocoa fixture ($TARGET)"
"$CC" -target "$TARGET" -isysroot "$SDK" -O1 -Wall \
    -o "$OUT/CocoaProbe.app/Contents/MacOS/CocoaProbe" "$HERE/cocoa.m" \
    -framework Cocoa

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
