#!/bin/bash
# Build the ravynOS base utilities as static, dyld-free Mach-O binaries.
#
# These are the programs BSD/bin/sh's builtins.def deliberately does NOT make
# builtins (expr, kill, printf, test and [ are all commented out there), so the
# shell resolves them from PATH. Without them in /usr/bin, every non-trivial
# script dies with "not found" -- and `test`/`[` in particular gate every while
# and if loop. builtins.def is the authoritative statement of intent, so the
# answer is to build the real programs, not to re-enable the builtins.
#
# The same applies to the text/file utilities below: an end-to-end shell script
# test found that a script could not run at all because sed, grep, cat, ls, ...
# were not in the image. They are the real FreeBSD bases already in this tree.
#
# Every program is linked by tools/bootlab/link-static.sh, which owns the
# archive list, the residue stubs, the -DVARIANT_STATIC pthread archive, and
# the post-link shape verification. The entry point is
# tools/bootlab/static-start.c, shared by every static ravynOS program.
#
# Completeness of each source tree was checked before relying on it: the
# Makefile's own SRCS list was resolved against the directory and every file
# counted. Programs whose tree is missing or whose link needs something ravynOS
# genuinely does not have are NOT here; see the report for the per-program
# verdicts and the exact reason for each omission.
#
# Usage:
#   ./build-ravynos-utils.sh            # build the ravynOS static binaries
#   ./build-ravynos-utils.sh --host-only  # host links, so they can be RUN
set -euo pipefail

R=$(cd "$(dirname "$0")/../.." && pwd)
B=$R/BSD
SDK=${RAVYN_SDKROOT:-$HOME/Projects/build/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk}
UTILDIR=${UTILDIR:-/tmp/ravyn-utils}
HOSTUTILDIR=${HOSTUTILDIR:-/tmp/ravyn-utils-host}
GENDIR=${UTILDIR:-/tmp/ravyn-utils}/gen
HOSTGENDIR=${HOSTUTILDIR:-/tmp/ravyn-utils-host}/gen
SHBINDIR=${SHBINDIR:-/tmp/ravyn-sh-build}
LINK_STATIC=${LINK_STATIC:-$R/tools/bootlab/link-static.sh}
STATIC_START=${STATIC_START:-$R/tools/bootlab/static-start.c}
ISYSROOT_CC=${ISYSROOT_CC:-$R/tools/bootlab/isysroot-cc}
MACAR=${MACAR:-$R/tools/bootlab/macar}
ZDIR=$R/Libraries/zlib
MD5DIR=$B/lib/libjpeg/md5

unset DEVELOPER_DIR || true
XCRUN=${XCRUN:-xcrun}
HOST_CC=${HOST_CC:-$XCRUN clang}

# test.c, printf.c and kill.c include the shell's bltin/bltin.h, which is why
# this build needs -I BSD/bin/sh. bltin.h without -DSHELL takes its #else
# branch: `#undef NULL', re-include <stdio.h>, `#undef main' -- correct for a
# standalone program, and it makes the `#define main echocmd' trick in the
# shell's own bltin/echo.c irrelevant here. That header is why these are
# ordinary programs rather than shell builtins.
COMMON_CFLAGS="-D__unused= -Wno-nullability-completeness -Wno-implicit-int \
 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-unused \
 -Wno-parentheses -Wno-format -Wno-sign-compare -Wno-deprecated-non-prototype"

# The ravynOS SDK's sys/cdefs.h lacks the ABI-neutral no-op pointer-attribute
# macros that its own sys/socket.h uses (struct msghdr uses __sized_by).
# Transcribed verbatim from MacOSX.sdk/usr/include/sys/cdefs.h:1004-1012.
PTRATTR="-D__has_ptrcheck=0 -D__single -D__unsafe_indexable \
 -D__counted_by(N)= -D__counted_by_or_null(N)= -D__sized_by(N)= \
 -D__sized_by_or_null(N)= -D__ended_by(E)= -D__terminated_by(T)= \
 -D__null_terminated"

# name:source files. `[` is a link to test, as BSD/bin/test/Makefile declares
# (LINKS= ${BINDIR}/test ${BINDIR}/[).
#
# The text/file utilities are the FreeBSD bases in this tree, NOT rewritten
# here: BSD/usr.bin/{sed,grep,head,tail,sort,basename,dirname} and
# BSD/bin/{cat,mkdir,ln}. Their Makefiles' own SRCS lists are reproduced
# exactly -- nothing was added to or removed from any of them.
PROGS=(
	"test:$B/bin/test/test.c"
	"printf:$B/usr.bin/printf/printf.c"
	"echo:$B/bin/echo/echo.c"
	"true:$B/usr.bin/true/true.c"
	"false:$B/usr.bin/false/false.c"
	"env:$B/usr.bin/env/env.c $B/usr.bin/env/envopts.c"
	"uname:$B/usr.bin/uname/uname.c"
	"kill:$B/usr.bin/kill/kill.c"
	"expr:$GENDIR/expr.c"
	"sed:$B/usr.bin/sed/compile.c $B/usr.bin/sed/main.c $B/usr.bin/sed/misc.c $B/usr.bin/sed/process.c"
	"grep:$B/usr.bin/grep/file.c $B/usr.bin/grep/grep.c $B/usr.bin/grep/queue.c $B/usr.bin/grep/util.c"
	"cat:$B/bin/cat/cat.c"
	"mkdir:$B/bin/mkdir/mkdir.c"
	"ln:$B/bin/ln/ln.c"
	"head:$B/usr.bin/head/head.c"
	"tail:$B/usr.bin/tail/forward.c $B/usr.bin/tail/misc.c $B/usr.bin/tail/read.c $B/usr.bin/tail/reverse.c $B/usr.bin/tail/tail.c"
	"basename:$B/usr.bin/basename/basename.c"
	"dirname:$B/usr.bin/dirname/dirname.c"
	"sort:$B/usr.bin/sort/bwstring.c $B/usr.bin/sort/coll.c $B/usr.bin/sort/file.c $B/usr.bin/sort/mem.c $B/usr.bin/sort/radixsort.c $B/usr.bin/sort/sort.c $B/usr.bin/sort/vsort.c"
	# Fresh implementations, NOT ports. These two are the only programs
	# here whose correctness rests on a POSIX spec reading rather than an
	# audited upstream tree; both source files say so in their headers, and
	# verify-ravyn-wc-tr.sh is their test suite. See the provenance note
	# in wc.c.
	"wc:$B/usr.bin/wc/wc.c"
	"tr:$B/usr.bin/tr/tr.c"
	# ls and rm need the passwd/grp lookup subsystem, which is why they
	# could not be built before libsystem_pwdgrp existed. See the ls_libs
	# and rm_libs notes below for exactly which archives each needs.
	"ls:$B/bin/ls/cmp.c $B/bin/ls/ls.c $B/bin/ls/print.c $B/bin/ls/util.c"
	"rm:$B/bin/rm/rm.c"
)

# ---------------------------------------------------------------------------
# Per-program configuration.
#
# Most programs need nothing beyond COMMON_CFLAGS. The ones that do are
# configuring, not rewriting: a -D that names a constant ravynOS already has
# under a different spelling, or an -I to a header that IS in this tree but
# is not installed in the SDK. Every one is explained where it is used.
# ---------------------------------------------------------------------------

# head includes <libutil.h> (BSD/usr.bin/head/Makefile adds the same -I) but
# uses nothing from it. The header is real and is in the tree at
# BSD/lib/libutil; the ravynOS SDK simply does not install it.
head_includes() { echo "-isystem $B/lib/libutil"; }

# grep's Makefile already sets -DWITHOUT_LZMA -DWITHOUT_FASTMATCH
# -DWITHOUT_NLS and links -lbz2 -lz. ravynOS has no liblzma and no installed
# bzlib.h/zlib.h, so WITHOUT_BZIP2 is added as well: the bz2 decoder in
# file.c is already behind that guard upstream. That leaves the zlib reader
# (gzdopen/gzread in grep_refill/grep_open), which is the real one, built from
# the real zlib 1.3.2 in Libraries/zlib.
grep_cflags() { echo "-DWITHOUT_LZMA -DWITHOUT_FASTMATCH -DWITHOUT_NLS -DWITHOUT_BZIP2"; }
# grep.h includes <bzlib.h> unconditionally even when the code is compiled
# WITHOUT_BZIP2, so the header still has to be found; BSD/lib/bzip2/src is
# where this tree's bzlib.h lives (grep/Makefile: -I${ROOT_SOURCE_DIR}/BSD/
# lib/bzip2/src, the same path).
grep_includes() { echo "-isystem $ZDIR -isystem $B/lib/bzip2/src"; }
grep_libs() { echo "-L$GENDIR/zlib -lz"; }

# sort needs three things ravynOS does not spell the way FreeBSD does, plus the
# MD5 it hashes its random seed with. See the shim header generated below.
sort_cflags() { echo "-include ${SORT_SHIM:-$GENDIR/ravyn-sort-compat.h}"; }
sort_includes() { echo "-isystem $MD5DIR -isystem $B/usr.bin/sort"; }
sort_libs() {
	if [ -n "${HOST_MD5_LIB:-}" ]; then
		echo "$HOST_MD5_LIB"          # host libSystem provides MD5
	else
		echo "-L$GENDIR/md5 -lmd5 -L$R/Libraries/Libsystem/corecrypto -lcorecrypto"
	fi
}

# --- ls and rm: the passwd/grp lookup path -------------------------------
#
# Both call user_from_uid / group_from_gid (rm to decide whether it may
# unlink, ls to print an owner name for `ls -l`). Those live in
# libsystem_pwdgrp, which is why neither could link before it existed.
#
# ls additionally calls the mbr_* membership entry points, used to turn a
# uid into the UUID an ACL refers to. Those four symbols (mbr_uid_to_uuid,
# mbr_gid_to_uuid, mbr_uuid_to_id, mbr_identifier_translate) are defined in
# exactly one member of libsystem_info.a -- membership.o -- and that member
# is SELF-SUFFICIENT: `nm -u membership.o` shows its only undefined symbols
# are libc plus getgr*/getpw*, all of which the link already has by the time
# it reaches it. The rest of libsystem_info.a is NOT self-sufficient:
# libinfo.o is self-referential onto ~50 si_* symbols in the
# SystemInformation framework, which has no build target in this tree (see
# libsystem_info/MISSING_DEPS.md, a pre-existing blocker that explicitly
# does not claim to be fixed).
#
# A note on whether the WHOLE archive could be named instead, because the
# honest answer is that it also links today, and it is worth knowing why.
# `ls` references exactly four symbols (mbr_uid_to_uuid, mbr_gid_to_uuid,
# mbr_uuid_to_id, mbr_identifier_translate) and all four live in membership.o.
# Naming the whole -lsystem_info happens to succeed, and does so ONLY because
# ld64 pulls archive members lazily: nothing ls references lives in
# libinfo.o, so libinfo.o is never extracted and its self-reference onto ~50
# si_* symbols in the SystemInformation framework never comes into play.
# Naming a 1.4 MB archive to get one 24 KB member, and depending on link
# order not to trip over the other 1.4 MB, is not a dependency worth
# expressing. Extracting the member makes the real requirement explicit and
# makes the build immune to anything later adding an ls-side reference that
# would drag libinfo.o in. The bytes are the archive's own: the extraction is
# byte-identical (shasum c1efb2db...), nothing is rewritten or stubbed.
#
# This is the last coupling in ls. It is not a stub and not a workaround: the
# SystemInformation framework that libinfo.o needs still has no build target
# in this tree, exactly as libsystem_info/MISSING_DEPS.md documents, and
# nothing in ls depends on that path.
#
PWDGRP_STATIC=$R/Libraries/Libsystem/libsystem_pwdgrp/static

ls_libs() {
	echo "-L$PWDGRP_STATIC -lsystem_pwdgrp_static"
	echo "${MEMBERSHIP_LIB:--L$GENDIR/membership -lmembership}"
}

# rm additionally calls removefile(3) on its unlink path. It does NOT need
# the membership member: `nm -u` on rm.o shows no mbr_* reference, and a link
# with only these two archives succeeds, which is the check that settles it.
rm_libs() {
	echo "-L$PWDGRP_STATIC -lsystem_pwdgrp_static -L$R/Libraries/Libsystem/removefile -lremovefile"
}

# Two includes that resolve on the target but not on the macOS Command Line
# Tools SDK, both needed only by BSD/bin/ls:
#   System/sys/fsctl.h  -- included at ls.c:78, no symbol from it is used
#                          (F_FULLFSSTAT, ffsctl: zero references in the ls
#                          sources). gen_host_includes symlinks System to the
#                          ravynOS System.framework's PrivateHeaders.
#   membershipPriv.h   -- provides ID_TYPE_UUID / ID_TYPE_NAME, which
#                          print.c:219 passes to mbr_identifier_translate.
#                          The ravynOS SDK installs it under usr/local/include.
ls_includes() {
	echo "-isystem $GENDIR/hostinc -isystem $SDK/usr/local/include"
}

# ---------------------------------------------------------------------------
# Generated inputs.
#
# These are written into the build directory, never into the source tree: the
# tree never ran configure, and BSD/bin/sh's nodes.c/syntax.c are in exactly
# the same position. Every generator is wired in here so the build is
# reproducible from a clean checkout.
# ---------------------------------------------------------------------------

# expr is a yacc grammar in the tree (BSD/usr.bin/expr/expr.y) with no
# generated expr.c. /usr/bin/yacc is a shim that needs full Xcode, so byacc
# from the Command Line Tools is used directly.
gen_expr() {
	mkdir -p "$GENDIR"
	if [ ! -f "$GENDIR/expr.c" ] || [ "$B/usr.bin/expr/expr.y" -nt "$GENDIR/expr.c" ]; then
		echo "==> generating expr.c from expr.y (byacc)"
		(cd "$GENDIR" && "${BYACC:-/Library/Developer/CommandLineTools/usr/bin/byacc}" \
			-d "$B/usr.bin/expr/expr.y" && mv -f y.tab.c expr.c)
	fi
}

# sort's md5.h, the FreeBSD stream/flag API and the FreeBSD mmap flags.
#
#   MD5_DIGEST_LENGTH  BSD/usr.bin/sort/coll.c uses it. ravynOS has no
#       installed <md5.h>; the value is 16 (CC_MD5_DIGEST_LENGTH in the SDK's
#       own CommonCrypto/CommonDigest.h:129), and the implementation linked
#       is the real RFC 1321 one in BSD/lib/libjpeg/md5, compiled below.
#
#   MAP_NOSYNC / MAP_NOCORE  BSD/usr.bin/sort/file.c:612 asks for an unsynced,
#       non-core-dumping mapping under `sort -M`. ravynOS sys/mman.h has no
#       such flags -- nor does macOS's, and nor does ravynOS's kernel. 0 is
#       the request for the DEFAULT behaviour (fully synced, dumped to core),
#       which is a conservative superset of what the flag asked for, and it is
#       the only honest encoding: there is no ravynOS flag that means "don't
#       sync", so asking for one would be asking the kernel for something that
#       does not exist.
#
#   sys/random.h  getentropy() is declared there and the definition is in
#       libsyscalls.a, but BSD/usr.bin/sort/sort.c does not include it.
gen_sort_shim() {
	mkdir -p "$GENDIR"
	cat > "$GENDIR/ravyn-sort-compat.h" <<'EOF'
/* Generated by BSD/usr.bin/build-ravynos-utils.sh. Do not edit; do not commit. */
#include <sys/random.h>	/* getentropy() */
#define MD5_DIGEST_LENGTH 16
#define MAP_NOSYNC 0
#define MAP_NOCORE 0
EOF
}

# The real MD5 that sort links. BSD/lib/libjpeg/md5 is the one MD5 in this
# tree exporting exactly the MD5Init/MD5Update/MD5Final API sort calls.
gen_md5_lib() {
	mkdir -p "$GENDIR/md5"
	if [ ! -f "$GENDIR/md5/libmd5.a" ] || [ "$MD5DIR/md5.c" -nt "$GENDIR/md5/libmd5.a" ]; then
		rm -f "$GENDIR/md5/md5.o"
		"$ISYSROOT_CC" -c -arch x86_64 -isysroot "$SDK" -mmacos-version-min=15.0 \
			-O2 -std=gnu11 -I "$MD5DIR" -o "$GENDIR/md5/md5.o" "$MD5DIR/md5.c"
		"$MACAR" crs "$GENDIR/md5/libmd5.a" "$GENDIR/md5/md5.o"
	fi
}

# The real zlib 1.3.2 that grep links. All 15 translation units in
# Libraries/zlib, compiled with the target's own -isysroot, archived with
# tools/bootlab/macar (macOS ar rejects the -D flag FreeBSD ar accepts).
gen_zlib_lib() {
	mkdir -p "$GENDIR/zlib"
	if [ ! -f "$GENDIR/zlib/libz.a" ] || [ "$ZDIR/zlib.h" -nt "$GENDIR/zlib/libz.a" ]; then
		rm -f "$GENDIR/zlib"/*.o
		local f
		for f in "$ZDIR"/*.c; do
			"$ISYSROOT_CC" -c -arch x86_64 -isysroot "$SDK" -mmacos-version-min=15.0 \
				-O2 -std=gnu11 -I "$ZDIR" -o "$GENDIR/zlib/$(basename "$f" .c).o" "$f"
		done
		"$MACAR" crs "$GENDIR/zlib/libz.a" "$GENDIR/zlib"/*.o
	fi
}

# The one real member of libsystem_info.a that ls needs, extracted and
# archived on its own. See the ls_libs comment above for why the whole
# archive cannot be linked: the rest of it is self-referential onto the
# SystemInformation framework's si_* symbols.
#
# Extraction, not compilation: the object is the archive's own bytes, so this
# cannot drift from what libsystem_info would have produced.
gen_membership_lib() {
	mkdir -p "$GENDIR/membership"
	local info=$R/Libraries/Libsystem/libsystem_info/libsystem_info.a
	[ -f "$info" ] || { echo "missing $info" >&2; return 1; }
	if [ ! -f "$GENDIR/membership/libmembership.a" ] || \
	    [ "$info" -nt "$GENDIR/membership/libmembership.a" ]; then
		rm -f "$GENDIR/membership/membership.o"
		(cd "$GENDIR/membership" && ar -x "$info" membership.o)
		[ -f "$GENDIR/membership/membership.o" ] || {
			echo "  membership.o not found in $info" >&2; return 1; }
		"$MACAR" crs "$GENDIR/membership/libmembership.a" \
			"$GENDIR/membership/membership.o"
	fi
}

# A `System` -> System.framework PrivateHeaders symlink, so that an
# `#include <System/sys/fsctl.h>` resolves on the host exactly as it does on
# the target. Only the host build calls this.
gen_host_includes() {
	mkdir -p "$GENDIR/hostinc"
	local priv="$SDK/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders"
	[ -d "$priv" ] || { echo "missing $priv" >&2; return 1; }
	rm -f "$GENDIR/hostinc/System"
	ln -s "$priv" "$GENDIR/hostinc/System"
}

gen_all() {
	gen_expr
	gen_sort_shim
	gen_md5_lib
	gen_zlib_lib
	gen_membership_lib
}

# Per-program lookup helpers. An undefined function is an empty expansion,
# which is what "needs nothing extra" has to mean.
prog_cflags()  { case $1 in grep) grep_cflags;; sort) sort_cflags;; esac; }
prog_includes() {
	case $1 in
	head) head_includes;;
	grep) grep_includes;;
	sort) sort_includes;;
	ls) ls_includes;;
	esac
}

prog_libs() {
	case $1 in
	grep) grep_libs;;
	sort) sort_libs;;
	ls) ls_libs;;
	rm) rm_libs;;
	esac
}

build_target() {
	local name srcs
	mkdir -p "$UTILDIR"
	gen_all
	for entry in "${PROGS[@]}"; do
		name=${entry%%:*}
		srcs=${entry#*:}
		echo "==> $name"
		# Word-split on purpose: these are flag and source strings.
		# shellcheck disable=SC2086
		RAVYN_EXTRA_CFLAGS="$COMMON_CFLAGS $PTRATTR $(prog_cflags "$name")" \
		RAVYN_EXTRA_INCLUDES="-isystem $SDK/usr/include -isystem $B/bin/sh $(prog_includes "$name")" \
		RAVYN_EXTRA_LIBS="$(prog_libs "$name")" \
		"$LINK_STATIC" -o "$UTILDIR/$name" "$STATIC_START" $srcs \
			|| { echo "  FAILED: $name" >&2; exit 1; }
	done
	# `[` is the same program as test (BSD/bin/test/Makefile: LINKS).
	cp "$UTILDIR/test" "$UTILDIR/["
	# `link` is the same program as ln (BSD/bin/ln/Makefile: LINKS).
	cp "$UTILDIR/ln" "$UTILDIR/link"
	# `unlink` is the same program as rm (BSD/bin/rm/Makefile: LINKS).
	cp "$UTILDIR/rm" "$UTILDIR/unlink"
	echo "built $UTILDIR"
}

build_host() {
	local name srcs src
	mkdir -p "$HOSTUTILDIR"
	# Mirrors gen_all for the target; the host build must exercise the same
	# generated inputs or the execution checks prove nothing.
	# gen_expr/gen_sort_shim write to $GENDIR, so reassign it for the two
	# calls: the host build compiles from $HOSTGENDIR (see the srcs rewrite
	# below) and must generate byte-identical inputs.
	GENDIR=$HOSTGENDIR gen_expr
	GENDIR=$HOSTGENDIR gen_sort_shim
	# The macOS Command Line Tools SDK ships no fsctl.h at any path, while
	# ls.c includes <System/sys/fsctl.h> and uses nothing from it. Rather
	# than delete upstream's include or fabricate a header that could mask
	# a real use, point the host compile at the ravynOS System.framework
	# copy through a `System -> PrivateHeaders` symlink, so the include
	# resolves to the genuine header and the compiler does the checking.
	gen_host_includes
	LS_EXTRA_INCLUDES="-isystem $GENDIR/hostinc"
	export LS_EXTRA_INCLUDES
	# ls and rm link the extracted membership member, so the host build has
	# to generate it too. A `VAR=x func` prefix applies inside the function
	# and is undone on return, so GENDIR is already correct afterwards; the
	# path is passed to ls_libs/rm_libs explicitly so they do not have to
	# guess which build they are in.
	GENDIR=$HOSTGENDIR gen_membership_lib
	MEMBERSHIP_LIB="-L$HOSTGENDIR/membership -lmembership"
	export MEMBERSHIP_LIB
	SORT_SHIM=$HOSTGENDIR/ravyn-sort-compat.h
	export SORT_SHIM
	# On the host, MD5Init/MD5Update/MD5Final and _ccrng all come from the
	# host's own libSystem, so no ravynOS archive is named here -- but the
	# header is still this tree's BSD/lib/libjpeg/md5, because the host SDK
	# has no <md5.h> and sort.c includes one.
	HOST_MD5_LIB=""
	export HOST_MD5_LIB
	echo "==> host build (runnable verification binaries)"
	# No -isysroot and no -isystem $SDK: the point of this build is to produce
	# something the Darwin host can actually EXECUTE, so it uses the host's
	# own headers. macOS headers are self-consistent, so PTRATTR is not needed
	# either -- it exists only because the ravynOS SDK's socket.h and sysctl.h
	# use pointer attributes its cdefs.h never defines. Same sources, same
	# -D switches, different libc, so running these exercises the code.
	for entry in "${PROGS[@]}"; do
		name=${entry%%:*}
		srcs=${entry#*:}
		echo "  $name"
		# Per-program object dir: a shared one would accumulate every
		# program's objects and collide on main().
		rm -rf "$HOSTUTILDIR/obj.$name"
		mkdir -p "$HOSTUTILDIR/obj.$name"
		# expr.c is generated into the TARGET GENDIR; the host build reuses
		# that same file rather than generating a second copy, so both builds
		# run byte-identical generated source.
		srcs=${srcs//$GENDIR\//$HOSTGENDIR/}
		for src in $srcs; do
			# shellcheck disable=SC2086
			$HOST_CC -c -arch x86_64 $COMMON_CFLAGS $(prog_cflags "$name") \
				-I"$B/bin/sh" $(prog_includes "$name") \
				-o "$HOSTUTILDIR/obj.$name/$(basename "$src" .c).o" "$src"
		done
		# shellcheck disable=SC2086
		$HOST_CC -arch x86_64 -o "$HOSTUTILDIR/$name" \
			"$HOSTUTILDIR/obj.$name"/*.o $(prog_libs "$name")
	done
	cp "$HOSTUTILDIR/test" "$HOSTUTILDIR/["
	cp "$HOSTUTILDIR/ln" "$HOSTUTILDIR/link"
	cp "$HOSTUTILDIR/rm" "$HOSTUTILDIR/unlink"
	echo "built $HOSTUTILDIR"
}

# --stage copies the built binaries to where manifest_userspace.json expects
# them. It writes to tools/bootlab/staged/, which is new; tools/bootlab/assets/
# is off limits to this task and is left untouched.
stage() {
	local d=$R/tools/bootlab/staged name f
	echo "==> staging to $d (manifest_userspace.json)"
	rm -rf "$d"
	mkdir -p "$d/usr/bin" "$d/bin"
	for name in test printf echo true false env uname kill expr sed grep head tail sort basename dirname wc tr; do
		[ -f "$UTILDIR/$name" ] || { echo "  missing $name, build first" >&2; exit 1; }
		cp -f "$UTILDIR/$name" "$d/usr/bin/$name"
	done
	# `[` is the same program as test (BSD/bin/test/Makefile: LINKS).
	cp -f "$UTILDIR/test" "$d/usr/bin/["
	# These five are staged to /bin by their own Makefiles' `to-sysroot'.
	for name in cat mkdir ln ls rm; do
		[ -f "$UTILDIR/$name" ] || { echo "  missing $name, build first" >&2; exit 1; }
		cp -f "$UTILDIR/$name" "$d/bin/$name"
	done
	# `link` is the same program as ln (BSD/bin/ln/Makefile: LINKS).
	cp -f "$UTILDIR/ln" "$d/bin/link"
	# `unlink` is the same program as rm (BSD/bin/rm/Makefile: LINKS).
	cp -f "$UTILDIR/rm" "$d/bin/unlink"
	if [ -f "$SHBINDIR/sh" ]; then
		cp -f "$SHBINDIR/sh" "$d/bin/sh"
	else
		echo "  note: no shell at $SHBINDIR/sh" >&2
	fi
	find "$d" -type f | sort | while read -r f; do
		printf '  %-16s %s bytes\n' "${f#$d/}" "$(stat -f %z "$f")"
	done
}

case "${1:-}" in
--host-only) build_host ;;
--both)      build_target; build_host ;;
--stage)     stage ;;
*)           build_target ;;
esac
