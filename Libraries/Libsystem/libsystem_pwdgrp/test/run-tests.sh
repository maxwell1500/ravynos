#!/bin/bash
# Build and RUN the libsystem_pwdgrp test suite.
#
# Two builds, because the two halves of the evidence need different
# databases:
#
#   host    the same pwdgrp.c compiled for the Darwin host, so the test
#           binary can actually be EXECUTED. A ravynOS Mach-O cannot be run
#           here, so "it compiled" is not evidence; "it ran and printed the
#           right answers" is.
#   target  pwdgrp.c compiled with the ravynOS SDK's own headers and
#           archived, then linked by tools/bootlab/link-static.sh, which
#           fails the link unless the result has zero LC_LOAD_DYLIB and zero
#           undefined symbols.
#
# The real-database test runs against /etc/passwd and /etc/group. The
# fixture test runs against a generated database holding the cases a real
# one cannot be asked for: a comment, a blank line, a too-short line, a
# non-numeric id, '+' and '-' NIS lines, and a line longer than the read
# buffer.
#
# Usage: test/run-tests.sh [host|target|all]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$HERE/.." && pwd)"
R="$(cd "$TOP/../../.." && pwd)"
WORK=${WORK:-/tmp/ravyn-pwdgrp-test}
SDK=${RAVYN_SDKROOT:-$HOME/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk}
LINK_STATIC=${LINK_STATIC:-$R/tools/bootlab/link-static.sh}
ISYSROOT_CC=${ISYSROOT_CC:-$R/tools/bootlab/isysroot-cc}
# `xcrun clang`, not `$(xcrun -f clang)`. The wrapper is what supplies the
# macOS SDK: invoked by bare path, clang searches only /usr/local/include and
# the CommandLineTools directories, and even <sys/types.h> is not found.
# Same reason BSD/usr.bin/build-ravynos-utils.sh uses `$XCRUN clang`.
CC=${HOST_CC:-xcrun clang}
MACAR=${MACAR:-$R/tools/bootlab/macar}
STATIC_START=${STATIC_START:-$R/tools/bootlab/static-start.c}

unset DEVELOPER_DIR || true


mkdir -p "$WORK"

# ---------------------------------------------------------------------------
# The fixture database.
#
# Written here rather than committed as data because one of the cases is a
# line whose length is defined in terms of the parser's read buffer: the
# over-long line is padded so that its 1024th byte is the start of a second,
# syntactically valid entry. Get that boundary wrong and the test would pass
# for the wrong reason -- it would look like the drain works when in fact
# there was no tail to drain.
# ---------------------------------------------------------------------------
gen_fixture() {
	local pw="$WORK/fixture-passwd" gr="$WORK/fixture-group"
	local head tail n longname

	# A long name: "flongname" followed by 291 'z', 300 characters in all.
	# Longer than the 256-byte field buffer that used to truncate it, so a
	# lookup by the full name has to still find it. test-pwdgrp.c builds
	# the same string from the same rule; it is stated on both sides so
	# the two cannot drift apart.
	longname="flongname$(printf 'z%.0s' $(seq 1 291))"

	# The over-long line. `head' is padded to exactly _RAV_LINEMAX-1
	# bytes so that fgets() fills its buffer and leaves `tail' -- itself a
	# well-formed entry -- as the apparent start of the next line.
	head='overlong:*:4008:4008:Overlong User:/home/'
	tail='ftail:9999:9999:Tail:/home/tail:/bin/sh'
	n=$(( 1023 - ${#head} ))

	{
		echo '# ravynOS libsystem_pwdgrp test fixture -- passwd database'
		echo '# comments and blank lines are not entries'
		echo
		printf '%s\n' 'froot:*:4000:4000:Froot User:/home/froot:/bin/sh'
		printf '%s\n' 'fdaemon:*:4001:4001:Daemon:/var/empty:/usr/bin/false'
		# Fewer than the mandatory four fields.
		printf '%s\n' 'short:x:4002'
		printf '%s\n' 'badsid:x:notanumber:4003:Bad:/home/badsid:/bin/sh'
		printf '%s\n' 'nagid:x:4004:notanumber:Nag:/home/nagid:/bin/sh'
		# NIS directives. Seven fields each, so without the '+'/'-'
		# skip these parse as an entry named "+" with uid 0.
		printf '%s\n' '+::::::'
		printf '%s\n' '-nisuser:::::'
		# The gecos/dir/shell fields are optional.
		printf '%s\n' 'fempty:*:4005:4005:'
		printf '%s\n' "$longname:*:4006:4006:Long:/home/long:/bin/sh"
		printf '%s\n' 'fmember:*:4007:4007:Member:/home/member:/bin/sh'
		printf '%s\n' 'fnomembers:*:4008:4008:Nomem:/home/nomem:/bin/sh'
		# The over-long line. Its tail is a valid entry, which is the
		# point: if the drain were missing, getpwnam("ftail") would hit.
		printf '%s%s%s\n' "$head" "$(printf 'x%.0s' $(seq 1 $n))" "$tail"
	} > "$pw"

	{
		echo '# ravynOS libsystem_pwdgrp test fixture -- group database'
		printf '%s\n' '+:::'
		printf '%s\n' '-:x:5010:'
		printf '%s\n' 'fgroup:*:5000:fa,fb'
		printf '%s\n' 'fnomembers:*:5001:'
		printf '%s\n' 'gshort:*:5002'
		printf '%s\n' 'gbadgid:*:notanumber:fc'
	} > "$gr"

	echo "  fixture: $pw ($(wc -l < "$pw" | tr -d ' ') lines, longest $(awk '{ if (length($0) > m) m = length($0) } END { print m }' "$pw") bytes)"
	echo "  fixture: $gr ($(wc -l < "$gr" | tr -d ' ') lines)"
}

# ---------------------------------------------------------------------------
# host: compile for the Darwin host and execute. These are the results.
# ---------------------------------------------------------------------------
build_host() {
	local name defs
	echo "==> host build (executed)"
	for name in real fixture; do
		defs="-D_RAVYN_TEST_PW_PATH=\"/etc/passwd\" -D_RAVYN_TEST_GR_PATH=\"/etc/group\""
		if [ "$name" = fixture ]; then
			defs="-D_RAVYN_TEST_FIXTURE"
			defs="$defs -D_RAVYN_PASSWD_FILE=\"$WORK/fixture-passwd\""
			defs="$defs -D_RAVYN_GROUP_FILE=\"$WORK/fixture-group\""
			defs="$defs -D_RAVYN_TEST_PW_PATH=\"$WORK/fixture-passwd\""
			defs="$defs -D_RAVYN_TEST_GR_PATH=\"$WORK/fixture-group\""
		fi
		# shellcheck disable=SC2086
		$CC -std=gnu11 -g -O0 -Wall -Wno-unused-parameter \
			-I"$TOP" $defs \
			-o "$WORK/test-pwdgrp-$name" \
			"$HERE/test-pwdgrp.c" "$TOP/pwdgrp.c"
	done
	echo "  built $WORK/test-pwdgrp-real, $WORK/test-pwdgrp-fixture"
}

run_host() {
	local rc=0
	for name in real fixture; do
		echo
		echo "=============================================================="
		echo "== $name database"
		echo "=============================================================="
		"$WORK/test-pwdgrp-$name" || rc=1
	done
	return $rc
}

# The same suite again, with pwdgrp.c built as a SHARED library and the test
# linked against it -- the way the dynamic ravynOS userland gets it. Same
# source, same -D set, same expectations. If the two builds ever diverge,
# this is what notices, not a reader comparing two outputs by eye.
build_host_dylib() {
	echo "==> host build, as a dylib (dynamic-side regression)"
	local name defs soname
	for name in real fixture; do
		defs="-D_RAVYN_TEST_PW_PATH=\"/etc/passwd\" -D_RAVYN_TEST_GR_PATH=\"/etc/group\""
		soname="libsystem_pwdgrp-$name.dylib"
		if [ "$name" = fixture ]; then
			defs="-D_RAVYN_TEST_FIXTURE"
			defs="$defs -D_RAVYN_PASSWD_FILE=\"$WORK/fixture-passwd\""
			defs="$defs -D_RAVYN_GROUP_FILE=\"$WORK/fixture-group\""
			defs="$defs -D_RAVYN_TEST_PW_PATH=\"$WORK/fixture-passwd\""
			defs="$defs -D_RAVYN_TEST_GR_PATH=\"$WORK/fixture-group\""
		fi
		# shellcheck disable=SC2086
		$CC -std=gnu11 -g -O0 -Wall -Wno-unused-parameter \
			-fPIC -I"$TOP" $defs -dynamiclib \
			-install_name "@rpath/$soname" \
			-o "$WORK/$soname" "$TOP/pwdgrp.c"
		# shellcheck disable=SC2086
		$CC -std=gnu11 -g -O0 -Wall -Wno-unused-parameter \
			-I"$TOP" $defs -L"$WORK" -l"system_pwdgrp-$name" \
			-Wl,-rpath,"@loader_path" \
			-o "$WORK/test-pwdgrp-dylib-$name" "$HERE/test-pwdgrp.c"
	done
	echo "  built $WORK/test-pwdgrp-dylib-real, $WORK/test-pwdgrp-dylib-fixture"
	# Proved loaded, not assumed: the binary must record a dependency on
	# the dylib, and nm -m must show the two-level bind going through it.
	echo "  load command:"
	otool -L "$WORK/test-pwdgrp-dylib-real" | grep -i pwdgrp | sed 's/^/    /'
	echo "  two-level bind:"
	nm -m "$WORK/test-pwdgrp-dylib-real" | grep -E "_getpwnam \(|_user_from_uid \(" | sed 's/^/    /'
}

run_host_dylib() {
	local rc=0 name
	for name in real fixture; do
		echo
		echo "=============================================================="
		echo "== $name database, linked against the dylib"
		echo "=============================================================="
		"$WORK/test-pwdgrp-dylib-$name" || rc=1
	done
	return $rc
}

# ---------------------------------------------------------------------------
# target: compile with the ravynOS SDK, archive, and prove link-static.sh
# accepts it.
# ---------------------------------------------------------------------------
build_target() {
	local objdir="$WORK/target"
	rm -rf "$objdir"
	mkdir -p "$objdir"

	echo "==> target build (ravynOS SDK headers)"
	# shellcheck disable=SC2086
	"$ISYSROOT_CC" -c -arch x86_64 -isysroot "$SDK" \
		-std=gnu11 -O2 -fno-builtin -Wall -Wno-unused-parameter \
		-o "$objdir/pwdgrp.o" "$TOP/pwdgrp.c"

	# macOS ar rejects the -D flag FreeBSD ar accepts, hence tools/bootlab/macar.
	rm -f "$objdir/libsystem_pwdgrp_static.a"
	"$MACAR" crs "$objdir/libsystem_pwdgrp_static.a" "$objdir/pwdgrp.o"
	echo "  archive: $objdir/libsystem_pwdgrp_static.a"

	# The test itself is compiled with the target's own headers too: the
	# SDK's <pwd.h>/<grp.h> differ from the host's, so compiling the test
	# is itself a check that the component matches the ravynOS API.
	echo "==> target: compiling the test with the ravynOS SDK headers"
	# shellcheck disable=SC2086
	"$ISYSROOT_CC" -c -arch x86_64 -isysroot "$SDK" \
		-std=gnu11 -O2 -fno-builtin -Wall -Wno-unused-parameter \
		-Wno-implicit-function-declaration \
		-I"$TOP" -D_RAVYN_TEST_PW_PATH=\"/etc/passwd\" \
		-D_RAVYN_TEST_GR_PATH=\"/etc/group\" \
		-o "$objdir/test-pwdgrp.o" "$HERE/test-pwdgrp.c"
	echo "  ok: the test compiles against the ravynOS SDK headers too"
}

# A static ravynOS program that calls every entry point. This is the
# acceptance criterion: link-static.sh verifies its own output and fails the
# link unless the result has zero LC_LOAD_DYLIB and zero undefined symbols.
link_target() {
	local lib="$WORK/target"
	echo
	echo "==> link-static.sh, linking probe.c against -lsystem_pwdgrp_static"
	RAVYN_EXTRA_INCLUDES="-I$TOP" \
	RAVYN_EXTRA_LIBS="-L$lib -lsystem_pwdgrp_static" \
	    "$LINK_STATIC" -o "$WORK/pwdgrp-probe" \
	    "$STATIC_START" "$HERE/probe.c"

	echo "  independent re-check of what link-static.sh verified:"
	printf '    LC_LOAD_DYLIB count:   %s\n' \
	    "$(otool -l "$WORK/pwdgrp-probe" | grep -c '^ *cmd LC_LOAD_DYLIB')"
	printf '    undefined symbols:     %s\n' \
	    "$(nm -u "$WORK/pwdgrp-probe" 2>/dev/null | wc -l | tr -d ' ')"
	printf '    Mach-O header flags:   %s\n' \
	    "$(otool -hv "$WORK/pwdgrp-probe" | tail -1 | awk '{print $NF}')"
	echo "    the pwd/grp symbols it pulled out of the archive:"
	nm "$WORK/pwdgrp-probe" | grep -E '_(getpwnam|getpwuid|getpwent|getgrnam|getgrgid|getgrent|user_from_uid|group_from_gid|fgetpwent|fgetgrent|setgrfile)' |
	    sed 's/^/      /'
}


case "${1:-all}" in
host)   gen_fixture; build_host; run_host ;;
target) gen_fixture; build_target; link_target ;;
all)    gen_fixture; build_host; run_host
        build_host_dylib; run_host_dylib
        build_target; link_target ;;
*)      echo "usage: $0 [host|target|all]" >&2; exit 2 ;;
esac
