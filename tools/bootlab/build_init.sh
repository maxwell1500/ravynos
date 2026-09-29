#!/bin/bash
# Build the persistent PID-1 init: freestanding static Mach-O, LC_UNIXTHREAD
# entry (no dyld, no LC_MAIN), x86_64. Requires Apple clang (host toolchain).
# Output: work/init  (payload for /bin/sh on the disk image)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$here/work"
xcrun clang -nostdlib -nostdlibinc -static -e _start -Wl,-no_uuid \
    -arch x86_64 -O2 -o "$here/work/init" "$here/init/init_static.c"
echo "built $here/work/init ($(stat -f%z "$here/work/init") bytes)"
