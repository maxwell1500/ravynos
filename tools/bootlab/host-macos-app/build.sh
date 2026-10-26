#!/bin/bash
# Build MacOSIntakeProbe with the host macOS toolchain.
#
# The point of building against the host SDK is that the resulting binary is a
# genuine macOS Mach-O: an LC_UUID the host dyld shared cache has never seen, a
# real @rpath/Loader-path dependency graph, and real Apple framework load
# commands.  tools/bootlab/app_stage.py then has to do the work of making it
# loadable on ravynOS, which is exactly what the intake track is for.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/MacOSIntakeProbe.app"
BUILD="${RAVYN_BUILD_DIR:-/Users/max/Projects/build}"
OUT="$BUILD/MacOSIntakeProbe"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
CLANG="${CLANG:-/usr/bin/clang}"

rm -rf "$OUT" "$APP"
mkdir -p "$OUT" \
         "$APP/Contents/MacOS" \
         "$APP/Contents/Frameworks" \
         "$APP/Contents/Resources"

# The embedded dylib: installed at @rpath/MacIntakeCore.dylib, which the app
# resolves through LC_RPATH @executable_path/../Frameworks.
"$CLANG" -isysroot "$SDKROOT" -mmacosx-version-min=13.0 -arch x86_64 \
    -dynamiclib -O2 \
    -install_name "@rpath/MacIntakeCore.dylib" \
    -o "$APP/Contents/Frameworks/MacIntakeCore.dylib" \
    "$HERE/MacOSIntakeProbe/MacIntakeCore.c"

# The application.  No -Werror: Apple's own headers are full of deprecation
# attributes for the very APIs this probe exists to exercise.
"$CLANG" -isysroot "$SDKROOT" -mmacosx-version-min=13.0 -arch x86_64 \
    -fobjc-arc -O2 -Wno-deprecated-declarations \
    -I"$HERE/MacOSIntakeProbe" \
    -o "$APP/Contents/MacOS/MacOSIntakeProbe" \
    "$HERE/MacOSIntakeProbe/ProbeMain.m" \
    "$APP/Contents/Frameworks/MacIntakeCore.dylib" \
    -Wl,-rpath,@executable_path/../Frameworks \
    -framework Cocoa \
    -framework Security \
    -framework IOKit \
    -framework CoreVideo \
    -framework SystemConfiguration \
    -framework CoreServices \
    -framework ApplicationServices

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>MacOSIntakeProbe</string>
	<key>CFBundleIdentifier</key>
	<string>com.apple.macos-intake-probe</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>macOS Intake Probe</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

echo "built $APP"
otool -L "$APP/Contents/MacOS/MacOSIntakeProbe" | sed 's/^/  /'
echo "rpaths:"
otool -l "$APP/Contents/MacOS/MacOSIntakeProbe" | awk '/LC_RPATH/{f=1} f&&/path /{print "  "$2; f=0}'
