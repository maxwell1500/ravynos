#!/bin/sh
# require_real_archive.sh <path> <upstream-component-name>
#
# Refuse to let a MISSING or ZERO-BYTE archive pass as a successful build.
#
# WHY THIS EXISTS
#   These targets used to be, in full:
#
#       touch ${RAVYN_SDKROOT}/usr/lib/libc++.a
#       @echo "stubbed libcxx for Darwin host"
#
#   `touch` on a populated tree is invisible -- it does not even truncate an
#   existing file.  But in a FRESH or wiped build tree it CREATES a zero-byte
#   archive, and ld64 accepts a zero-byte archive.  Nothing fails.  The link
#   either loses a library silently or blows up somewhere far from the cause.
#
#   That is the same defect class as the zero-export libSystem stub this
#   workstream has been eliminating, except here it is load-bearing: the
#   MH_DYLINKER links -lunwind -lc++ -lc++abi by explicit intent
#   (Libraries/dyld/dyld/Makefile), so an empty archive means a loader with no
#   unwinder and no C++ runtime.
#
#   A loud failure is strictly better than a silent stub, so this is the
#   deliberate choice for the components whose real build is not yet wired up.
#   libunwind, whose real cmake build IS wired up, does not use this script.
#
# EXIT STATUS
#   0  the archive exists and is non-empty
#   1  it is missing or empty -- message names the real prerequisite

set -eu

archive="${1:-}"
component="${2:-the component}"

if [ -z "$archive" ]; then
	echo "FATAL: require_real_archive.sh: no archive path given" >&2
	exit 1
fi

if [ -s "$archive" ]; then
	exit 0
fi

echo "FATAL: $archive is missing or empty." >&2
echo "       This build no longer writes a 0-byte stub here: ld64 accepts a" >&2
echo "       zero-byte archive, so the stub would turn a missing dependency" >&2
echo "       into a link that fails far from the real cause." >&2
echo "       Build $component from Developer/Default.xctoolchain/llvm/$component" >&2
echo "       and install it to:" >&2
echo "         $archive" >&2
exit 1
