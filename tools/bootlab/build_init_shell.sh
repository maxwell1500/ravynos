#!/bin/bash
# Build the shell-as-PID-1 init: freestanding static Mach-O, LC_UNIXTHREAD
# entry (no dyld, no LC_MAIN), x86_64. Same build shape as build_init.sh, so
# it inherits everything already proven to boot; the only difference is that
# this one hands the console to /bin/sh instead of ticking.
#
# Output: work/init_shell
#
# KNOWN BLOCKER (not a bug in this file): this binary execs /bin/sh, and no
# target static shell exists yet. BSD/bin/sh/build-ravynos.sh cannot produce
# one because BSD/lib/libedit's src/terminal.c calls tgetent/tgetflag/... from
# terminal_set() with no non-termcap path, and ravynOS has no termcap at all:
# no <termcap.h>/<curses.h> in the SDK, no tget* symbol in any Libsystem
# archive, and no termcap database in the SDK tree. That gap is documented in
# build-ravynos.sh and was deliberately left unstubbed upstream -- a fabricated
# termcap entry would make the editor emit escape sequences the target
# terminal was never told it understands.
#
# So this builds and is correct, but staging it into an image only produces a
# working terminal once the target shell links. Use
# make_shell_manifest.py to build the image that pairs the two.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$here/work"
xcrun clang -nostdlib -nostdlibinc -static -e _start -Wl,-no_uuid \
    -arch x86_64 -O2 -Wall -Wno-unused-but-set-variable \
    -o "$here/work/init_shell" "$here/init/init_shell.c"
echo "built $here/work/init_shell ($(stat -f%z "$here/work/init_shell") bytes)"
# Prove the shape the loader needs: dyld-free, no undefined symbols, and the
# LC_UNIXTHREAD entry rather than LC_MAIN.
if otool -L "$here/work/init_shell" | grep -q dylib; then
    echo "ERROR: init_shell has an LC_LOAD_DYLIB; it must be dyld-free" >&2
    exit 1
fi
if [ -n "$(nm -u "$here/work/init_shell")" ]; then
    echo "ERROR: init_shell has undefined symbols" >&2
    exit 1
fi
otool -l "$here/work/init_shell" | grep -q LC_UNIXTHREAD || {
    echo "ERROR: init_shell has no LC_UNIXTHREAD entry" >&2
    exit 1; }
echo "verified: freestanding, no dylibs, no undefined syms, LC_UNIXTHREAD"
