#!/bin/bash
# build_init_exec.sh -- build the dynamic-userland gate's PID 1.
#
# Same freestanding/static shape as build_init.sh (LC_UNIXTHREAD entry, no
# dyld, raw syscalls), so the only dynamic process in the gate boot is the
# one it execve()s. Output: work/init_exec, staged as /sbin/launchd by
# manifest_dynamic.json.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$here/work"
xcrun clang -nostdlib -nostdlibinc -static -e _start -Wl,-no_uuid \
    -arch x86_64 -O2 -o "$here/work/init_exec" "$here/init/init_exec_dynamic.c"
echo "built $here/work/init_exec ($(stat -f%z "$here/work/init_exec") bytes)"
