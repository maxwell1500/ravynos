#!/bin/bash
# Build and RUN ls and rm against libsystem_pwdgrp. This is the payoff.
#
# Two builds per program:
#
#   target  a static, dyld-free ravynOS Mach-O via tools/bootlab/link-static.sh,
#           which fails the link unless the result has zero LC_LOAD_DYLIB and
#           zero undefined symbols. This is the shape the boot image needs.
#
#   host    the SAME sources compiled for the Darwin host, so the binaries can
#           actually be EXECUTED. A ravynOS Mach-O cannot be run here, so
#           "it linked" is not evidence -- "it ran and printed the right
#           owner and group" is.
#
# In the host build pwdgrp.c is compiled straight into the program. The
# linker therefore binds ls's and rm's calls to user_from_uid/group_from_gid
# to THIS library rather than to libSystem's, which is the point: the group
# column ls -l prints is read from the database file this library opened.
# build-usr.sh proves that by pointing the group database at an empty file and
# watching the name turn into a number.
#
# Usage: test/build-ls-rm.sh [target|host|all]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$HERE/.." && pwd)"
R="$(cd "$TOP/../../.." && pwd)"
W=${WORK:-/tmp/ravyn-pwdgrp-lsrm}
SDK=${RAVYN_SDKROOT:-$HOME/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk}
LINK_STATIC=${LINK_STATIC:-$R/tools/bootlab/link-static.sh}
STATIC_START=${STATIC_START:-$R/tools/bootlab/static-start.c}
PWDGRP_LIB=${PWDGRP_LIB:-$TOP/static}

unset DEVELOPER_DIR || true

mkdir -p "$W/obj" "$W/inc"

# The Command Line Tools SDK installs no System.framework headers at all and
# no membershipPriv.h, both of which BSD/bin/ls/ls.c and print.c include by
# their macOS paths. Both headers exist in the ravynOS SDK, so they are exposed
# at the paths the unmodified sources ask for rather than being stubbed. This
# affects the host build only; the target build finds them in the SDK.
ln -sfn "$SDK/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders" \
	"$W/inc/System"
ln -sfn "$SDK/usr/local/include/membershipPriv.h" "$W/inc/membershipPriv.h"

# The same warning set BSD/usr.bin/build-ravynos-utils.sh uses: the ravynOS
# SDK's headers are not warning-clean under clang's default set, and none of
# these warnings are about this library.
CFLAGS_COMMON="-D__unused= -Wno-nullability-completeness -Wno-implicit-int \
 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-unused \
 -Wno-parentheses -Wno-format -Wno-sign-compare -Wno-deprecated-non-prototype \
 -Wno-unknown-pragmas"

LS_SRCS="cmp.c ls.c print.c util.c"	# BSD/bin/ls/Makefile: SRCS
RM_SRCS="rm.c"				# BSD/bin/rm/Makefile: PROG=rm

# ---------------------------------------------------------------------------
build_target() {
	local srcs lib
	for lib in "$PWDGRP_LIB/libsystem_pwdgrp_static.a" \
		   /tmp/ravyn-pwdgrp-test/target/libsystem_pwdgrp_static.a; do
		[ -f "$lib" ] && break
	done
	if [ ! -f "$lib" ]; then
		echo "error: no libsystem_pwdgrp_static.a. Build it with" >&2
		echo "  (cd $TOP/static && bmake -m $R/BSD/share/mk all)" >&2
		echo "or run $HERE/run-tests.sh target first." >&2
		exit 1
	fi
	echo "==> archive: $lib"

	# rm needs _removefile, from Libraries/Libsystem/removefile.
	#
	# ls additionally needs the Open Directory membership functions
	# (mbr_uid_to_uuid, mbr_gid_to_uuid, mbr_uuid_to_id,
	# mbr_identifier_translate). They live in libsystem_info.a's
	# membership.o, which IS linkable on its own: the blocked part of
	# libsystem_info is libinfo.o and its si_* closure, which nothing here
	# references. acl_translate.o inside libc.a is what pulls two of them
	# in, via ls's ACL support. That the linked ls contains zero si_*
	# symbols is printed below rather than asked for on faith.
	local extra="-L$PWDGRP_LIB -lsystem_pwdgrp_static"
	extra="$extra -L$R/Libraries/Libsystem/removefile -lremovefile"
	[ -f "$R/Libraries/Libsystem/libsystem_info/libsystem_info.a" ] &&
		extra="$extra -L$R/Libraries/Libsystem/libsystem_info -lsystem_info"

	local name
	echo "==> target: static ravynOS binaries"
	echo "    ls"
	# shellcheck disable=SC2086
	RAVYN_EXTRA_CFLAGS="$CFLAGS_COMMON" \
	RAVYN_EXTRA_INCLUDES="-isystem $SDK/usr/include -isystem $SDK/usr/local/include" \
	RAVYN_EXTRA_LIBS="$extra" \
	"$LINK_STATIC" -o "$W/ls-ravyn" "$STATIC_START" \
		$R/BSD/bin/ls/cmp.c $R/BSD/bin/ls/ls.c \
		$R/BSD/bin/ls/print.c $R/BSD/bin/ls/util.c 2>&1 |
	    grep -v 'incompatible-sysroot' || true
	echo "    rm"
	# shellcheck disable=SC2086
	RAVYN_EXTRA_CFLAGS="$CFLAGS_COMMON" \
	RAVYN_EXTRA_INCLUDES="-isystem $SDK/usr/include -isystem $SDK/usr/local/include" \
	RAVYN_EXTRA_LIBS="$extra" \
	"$LINK_STATIC" -o "$W/rm-ravyn" "$STATIC_START" \
		$R/BSD/bin/rm/rm.c 2>&1 | grep -v 'incompatible-sysroot' || true

	for name in ls-ravyn rm-ravyn; do
		[ -f "$W/$name" ] || { echo "  $name: NOT BUILT"; return 1; }
		printf '  %-10s %8s bytes  LC_LOAD_DYLIB=%s  undefined=%s  flags=%s\n' \
		    "$name" "$(stat -f %z "$W/$name")" \
		    "$(otool -l "$W/$name" | grep -c '^ *cmd LC_LOAD_DYLIB')" \
		    "$(nm -u "$W/$name" 2>/dev/null | wc -l | tr -d ' ')" \
		    "$(otool -hv "$W/$name" | tail -1 | awk '{print $NF}')"
	done
	printf '  ls si_* symbols: %s -- the blocked libinfo closure is not pulled in\n' \
	    "$(nm "$W/ls-ravyn" | grep -cE ' [Tt] _si_')"
	echo "  the pwd/grp symbols rm got from this library:"
	nm "$W/rm-ravyn" | grep -E ' T _(getpwnam|getpwuid|getpwent|setpwent|endpwent|setgrfile|user_from_uid|group_from_gid)$' |
	    sed 's/^/    /'
}

# ---------------------------------------------------------------------------
build_host() {
	local cc=${HOST_CC:-xcrun clang}
	echo "==> host build (executable)"
	local f
	for f in $LS_SRCS; do
		# shellcheck disable=SC2086
		$cc -c -arch x86_64 $CFLAGS_COMMON -I"$W/inc" \
			-o "$W/obj/ls-$f.o" "$R/BSD/bin/ls/$f"
	done
	# shellcheck disable=SC2086
	$cc -c -arch x86_64 $CFLAGS_COMMON -I"$W/inc" -o "$W/obj/rm.o" \
	    "$R/BSD/bin/rm/rm.c"
	# shellcheck disable=SC2086
	$cc -c -arch x86_64 -Wall -o "$W/obj/pwdgrp.o" "$TOP/pwdgrp.c"
	# shellcheck disable=SC2086
	$cc -arch x86_64 -o "$W/ls" $W/obj/ls-*.o $W/obj/pwdgrp.o
	# shellcheck disable=SC2086
	$cc -arch x86_64 -o "$W/rm" $W/obj/rm.o $W/obj/pwdgrp.o
	echo "  built $W/ls and $W/rm"
	echo "  user_from_uid / group_from_gid come from libsystem_pwdgrp, not libSystem:"
	nm "$W/ls" | grep -E ' T _(user_from_uid|group_from_gid|getpwnam|getgrgid)$' |
	    sed 's/^/    /'
}

# ---------------------------------------------------------------------------
run_host() {
	local D=$W/scratch
	rm -rf "$D" && mkdir -p "$D/sub"
	echo one   > "$D/alpha.txt"
	echo two   > "$D/beta.log"
	echo three > "$D/sub/gamma.txt"

	echo
	echo "== ls -l  (owner/group resolved through libsystem_pwdgrp)"
	"$W/ls" -l "$D"

	echo
	echo "== the same ls, with the group database pointed at a file that has"
	echo "   no entry for this gid. group_from_gid() then returns the decimal"
	echo "   id, which is libinfo.c:3374's own fallback -- and can only"
	echo "   happen if the group file being read is the one this library"
	echo "   opened, because nothing else in the process knows about it."
	printf '# an empty group database\n' > "$W/empty-group"
	# shellcheck disable=SC2086
	xcrun clang -c -arch x86_64 -Wall -D_RAVYN_GROUP_FILE="\"$W/empty-group\"" \
		-o "$W/obj/pwdgrp-nogroup.o" "$TOP/pwdgrp.c"
	# shellcheck disable=SC2086
	xcrun clang -arch x86_64 -o "$W/ls-nogroup" $W/obj/ls-*.o \
		$W/obj/pwdgrp-nogroup.o
	"$W/ls-nogroup" -l "$D/alpha.txt"

	echo
	echo "== ls with -1, -a, -R and a column sort, to exercise more of it"
	"$W/ls" -1 "$D"
	"$W/ls" -R "$D"
	"$W/ls" -l "$D" | sort -k9

	local R2=$W/rmtest
	rm -rf "$R2" && mkdir -p "$R2/a/b/c"
	echo x > "$R2/file1"; echo x > "$R2/a/file2"; echo x > "$R2/a/b/c/file4"
	mkdir -p "$R2/emptydir"
	echo
	echo "== rm -v on two files"
	"$W/rm" -v "$R2/file1" "$R2/a/file2"
	echo "   exit=$?  left: $(ls -A "$R2" | tr '\n' ' ')"
	echo
	echo "== rm without -r on a directory (the refusal path)"
	"$W/rm" "$R2/emptydir" || echo "   exit=$? (refused, as it should)"
	echo
	echo "== rm -rf the whole tree"
	"$W/rm" -rf "$R2" && echo "   exit=0"
	[ -e "$R2" ] && echo "   STILL THERE" || echo "   gone"
}

case "${1:-all}" in
host)   build_host; run_host ;;
target) build_target ;;
all)    build_target; build_host; run_host ;;
*)      echo "usage: $0 [host|target|all]" >&2; exit 2 ;;
esac
