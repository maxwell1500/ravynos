#!/bin/bash
# Build and RUN the libsystem_termcap test suite.
#
# Three builds, each answering a different question:
#
#   host    termcap.c compiled for the Darwin host, so the suite can actually
#           be EXECUTED. A ravynOS Mach-O cannot be run here, so "it compiled"
#           is not evidence; "it ran and printed 160 PASS lines" is.
#
#   dylib   the same termcap.c as a shared library, linked against through a
#           two-level bind -- the shape the dynamic ravynOS userland gets it
#           in, and the shape libsystem_pwdgrp/test/run-tests.sh also checks.
#
#   target  termcap.c compiled with the ravynOS SDK's own headers, archived,
#           and linked by tools/bootlab/link-static.sh, which fails the link
#           unless the result has zero LC_LOAD_DYLIB and zero undefined
#           symbols.
#
# The negative control is separate and not optional: test/negative-control.sh
# breaks the implementation on purpose and requires the suite to notice.
#
# Usage: test/run-tests.sh [host|dylib|target|all]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$HERE/.." && pwd)"
R="$(cd "$TOP/../../.." && pwd)"
WORK=${WORK:-/tmp/ravyn-termcap-test}
SDK=${RAVYN_SDKROOT:-$HOME/Projects/build/Developer/ravynOS.sdk}
SDK_FALLBACK=$HOME/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk
[ -d "$SDK" ] || SDK="$SDK_FALLBACK"
LINK_STATIC=${LINK_STATIC:-$R/tools/bootlab/link-static.sh}
ISYSROOT_CC=${ISYSROOT_CC:-$R/tools/bootlab/isysroot-cc}
# `xcrun clang`, not `$(xcrun -f clang)`. The wrapper is what supplies the
# macOS SDK: invoked by bare path, clang searches only /usr/local/include and
# the CommandLineTools directories, and even <stdio.h> is not found.
CC=${HOST_CC:-xcrun clang}
MACAR=${MACAR:-$R/tools/bootlab/macar}
STATIC_START=${STATIC_START:-$R/tools/bootlab/static-start.c}

unset DEVELOPER_DIR || true
mkdir -p "$WORK"

HOST_CFLAGS="-std=gnu11 -g -O0 -Wall -Wextra -Wno-unused-parameter -I$TOP -I$HERE"

# ---------------------------------------------------------------------------
run_host() {
	local name
	echo "==> host build (executed)"
	# shellcheck disable=SC2086
	$CC $HOST_CFLAGS -o "$WORK/test-termcap" "$HERE/test-termcap.c" "$TOP/termcap.c" || return 1
	echo "  built $WORK/test-termcap"
	echo
	"$WORK/test-termcap"
}

# ---------------------------------------------------------------------------
build_dylib() {
	echo "==> host build, as a dylib (dynamic-side regression)"
	# shellcheck disable=SC2086
	$CC $HOST_CFLAGS -fPIC -dynamiclib -install_name "@rpath/libsystem_termcap-test.dylib" \
		-o "$WORK/libsystem_termcap-test.dylib" "$TOP/termcap.c" || return 1
	# shellcheck disable=SC2086
	$CC $HOST_CFLAGS -L"$WORK" -lsystem_termcap-test -Wl,-rpath,"@loader_path" \
		-o "$WORK/test-termcap-dylib" "$HERE/test-termcap.c" || return 1
	echo "  built $WORK/test-termcap-dylib"
	# Proved loaded, not assumed: the binary must record a dependency on
	# the dylib and the calls must go through a two-level bind.
	echo "  load command:"
	otool -L "$WORK/test-termcap-dylib" | grep -i termcap | sed 's/^/    /'
	echo "  two-level bind:"
	nm -m "$WORK/test-termcap-dylib" | grep -E '_tget(ent|num|flag|str) \(' | sed 's/^/    /'
	echo
	"$WORK/test-termcap-dylib"
}

# ---------------------------------------------------------------------------
build_target() {
	local objdir="$WORK/target"
	rm -rf "$objdir"; mkdir -p "$objdir"

	echo "==> target build (ravynOS SDK headers)"
	# shellcheck disable=SC2086
	"$ISYSROOT_CC" -c -arch x86_64 -isysroot "$SDK" \
		-std=gnu11 -O2 -fno-builtin -Wall -Wno-unused-parameter \
		-I"$TOP" -o "$objdir/termcap.o" "$TOP/termcap.c" || return 1
	# macOS ar rejects the -D flag FreeBSD ar accepts, hence tools/bootlab/macar.
	rm -f "$objdir/libsystem_termcap_static.a"
	"$MACAR" crs "$objdir/libsystem_termcap_static.a" "$objdir/termcap.o" || return 1
	echo "  archive: $objdir/libsystem_termcap_static.a ($(stat -f %z "$objdir/libsystem_termcap_static.a") bytes)"

	# The suite itself, compiled with the ravynOS SDK's headers too. It is
	# compiled but NOT run: a ravynOS Mach-O cannot execute here.
	echo "==> target: compiling the suite with the ravynOS SDK headers"
	# shellcheck disable=SC2086
	"$ISYSROOT_CC" -c -arch x86_64 -isysroot "$SDK" \
		-std=gnu11 -O2 -fno-builtin -Wall -Wno-unused-parameter \
		-Wno-implicit-function-declaration -I"$TOP" \
		-o "$objdir/test-termcap.o" "$HERE/test-termcap.c" || return 1
	echo "  ok: the suite compiles against the ravynOS SDK headers too"

	# probe.c includes <termcap.h> with no -I of its own, so it only
	# compiles if the header really is installed in the SDK. Do that here
	# rather than trusting a previous bmake run.
	echo "==> target: installing termcap.h into $SDK/usr/include"
	cp -f "$TOP/termcap.h" "$SDK/usr/include/termcap.h"
}

link_target() {
	local lib="$WORK/target"
	echo
	echo "==> link-static.sh, linking probe.c against -lsystem_termcap_static"
	# No -I for the header on purpose: probe.c's <termcap.h> must resolve
	# through the ravynOS SDK, which is how libedit will resolve it.
	RAVYN_EXTRA_LIBS="-L$lib -lsystem_termcap_static" \
	    "$LINK_STATIC" -o "$WORK/termcap-probe" \
	    "$STATIC_START" "$HERE/probe.c" 2>&1 | grep -v 'incompatible-sysroot' || return 1

	echo "  independent re-check of what link-static.sh verified:"
	printf '    LC_LOAD_DYLIB count: %s\n' \
	    "$(otool -l "$WORK/termcap-probe" | grep -c '^ *cmd LC_LOAD_DYLIB')"
	printf '    undefined symbols:   %s\n' \
	    "$(nm -u "$WORK/termcap-probe" 2>/dev/null | grep -c .)"
	printf '    Mach-O header flags: %s\n' \
	    "$(otool -hv "$WORK/termcap-probe" | tail -1 | awk '{print $NF}')"
	echo "    the termcap symbols it pulled out of the archive:"
	nm "$WORK/termcap-probe" | grep -E ' [TDBR] _(tgetent|tgetnum|tgetflag|tgetstr|tgoto|tputs)$' | sed 's/^/      /'
}

rc=0
case "${1:-all}" in
host)   run_host || rc=1 ;;
dylib)  build_dylib || rc=1 ;;
target) build_target && link_target || rc=1 ;;
all)
	run_host || rc=1
	build_dylib || rc=1
	build_target && link_target || rc=1
	;;
*) echo "usage: $0 [host|dylib|target|all]" >&2; exit 2 ;;
esac

echo
if [ "$rc" -eq 0 ]; then
	echo "run-tests: PASS"
else
	echo "run-tests: FAIL"
fi
exit "$rc"
