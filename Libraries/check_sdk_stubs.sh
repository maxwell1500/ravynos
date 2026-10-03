#!/bin/bash
# Guard against stub artifacts silently replacing real libraries in the SDK.
#
# WHY THIS EXISTS
#
# A real artifact was silently destroyed during the libSystem effort.
# Libraries/CrashReporterClient/Makefile had a `.if Darwin` branch that ran
# `touch` (creating 0-byte files) and then `cp -f` them into the SDK. Because
# CrashReporterClient is a SUBDIR of Libraries/, that branch fired on every
# recursive Darwin build and overwrote a working 8,704-byte
# libCrashReporterClient.dylib with 0 bytes, and left a 0-byte
# libCrashReporterClient.a behind. A 0-byte archive is also rejected by ld64
# ("file is empty"), so it was never a usable substitute. That branch has been
# removed; the real sources now build.
#
# tools/bootlab/build_stubs.sh was checked as a suspect and CLEARED: it
# hardcodes an output path under tools/bootlab/assets/, so it cannot reach the
# SDK, and nothing in the build flow invokes it.
#
# A second suspected incident was a measurement error, recorded so it is not
# re-investigated: `stat -f%z` does NOT follow symlinks, so libobjc.dylib (a
# symlink to libobjc.A.dylib) was reported as 15 bytes -- the length of the
# string "libobjc.A.dylib" -- and briefly mistaken for a stub. This script
# resolves symlinks before measuring so it cannot repeat that.
#
# USAGE:  Libraries/check_sdk_stubs.sh [SDK_ROOT]
#         Default SDK_ROOT is $RAVYN_SDKROOT. Exits non-zero on regression.

set -uo pipefail
SDK="${1:-${RAVYN_SDKROOT:-}}"
[ -n "$SDK" ] || { echo "check_sdk_stubs: no SDK root given and RAVYN_SDKROOT unset" >&2; exit 2; }
[ -d "$SDK" ] || { echo "check_sdk_stubs: no such SDK: $SDK" >&2; exit 2; }

# Smallest real dylib we build is libCrashReporterClient.dylib at 8,704 B.
MIN_SIZE=8192

# The four re-export targets that are KNOWN not to be real. Listed so a
# regression on the other 21 is still caught, and so these are reported as
# KNOWN rather than as new failures. Keep in step with
# Libraries/Libsystem/libSystem.B_STATE.md.
KNOWN_STUB="system_kernel dyld corecrypto system_trace"

measure() {  # resolve symlinks; never report a link string length as a size
  if [ -L "$1" ]; then ls -lL "$1" 2>/dev/null | awk '{print $5}'
  else stat -f%z "$1" 2>/dev/null; fi
}

fail=0
echo "== SDK stub check: $SDK =="

# --- 1. the 21 re-export targets that MUST be real --------------------------
for l in system_c system_blocks system_asl CrashReporterClient system_malloc \
         system_platform system_darwin system_pthread compiler_rt unwind xpc \
         launch dispatch system_m system_coreservices system_notify \
         system_info copyfile macho removefile system_dnssd; do
  found=""
  for d in usr/lib/system usr/lib usr/local/lib/system; do
    [ -e "$SDK/$d/lib$l.dylib" ] && { found="$SDK/$d/lib$l.dylib"; break; }
  done
  if [ -z "$found" ]; then
    echo "FAIL: -l$l : ABSENT (was real before)"
    fail=1
  else
    sz=$(measure "$found")
    if [ "${sz:-0}" -lt "$MIN_SIZE" ]; then
      echo "FAIL: -l$l : ${sz} bytes (< $MIN_SIZE) - a stub has replaced it"
      fail=1
    fi
  fi
done

# --- 2. the four known blockers, reported not failed ------------------------
for l in $KNOWN_STUB; do
  found=""
  for d in usr/lib/system usr/lib usr/local/lib/system; do
    [ -e "$SDK/$d/lib$l.dylib" ] && { found="$SDK/$d/lib$l.dylib"; break; }
  done
  if [ -z "$found" ]; then
    echo "KNOWN: -l$l : absent (documented blocker)"
  else
    sz=$(measure "$found")
    if [ "${sz:-0}" -lt "$MIN_SIZE" ]; then
      echo "KNOWN: -l$l : ${sz} bytes (documented blocker, still a stub)"
    else
      echo "  ok: -l$l : ${sz} bytes - no longer a stub"
    fi
  fi
done

# --- 3. libobjc must be a symlink to the real libobjc.A.dylib ---------------
o="$SDK/usr/lib/libobjc.dylib"
if [ ! -e "$o" ]; then
  echo "FAIL: libobjc.dylib is missing entirely"; fail=1
elif [ -L "$o" ]; then
  t=$(readlink "$o")
  if [ "$t" != "libobjc.A.dylib" ]; then
    echo "FAIL: libobjc.dylib -> '$t', expected libobjc.A.dylib"; fail=1
  fi
  sz=$(measure "$o")
  if [ "${sz:-0}" -lt "$MIN_SIZE" ]; then
    echo "FAIL: libobjc.dylib resolves to ${sz} bytes (< $MIN_SIZE)"; fail=1
  fi
else
  echo "FAIL: libobjc.dylib is a regular file, not a symlink to libobjc.A.dylib"
  fail=1
fi

# --- 4. libSystem.B must exist and actually re-export -----------------------
# Its own size is NOT checked: it contains no code, only LC_REEXPORT_DYLIB, so
# ~4,120 bytes is correct. Checking the reexport count is the meaningful test.
sb="$SDK/usr/lib/libSystem.B.dylib"
if [ ! -e "$sb" ]; then
  echo "FAIL: libSystem.B.dylib is missing"; fail=1
else
  n=$(otool -l "$sb" 2>/dev/null | grep -c LC_REEXPORT_DYLIB)
  echo "  libSystem.B.dylib: $(measure "$sb") bytes, $n LC_REEXPORT_DYLIB"
  if [ "${n:-0}" -lt 20 ]; then
    echo "FAIL: libSystem.B.dylib re-exports only $n targets, expected >= 20"
    fail=1
  fi
fi

# --- 4b. DELETED, deliberately. Recorded so nobody re-creates them ---------
# Five 8,064-byte placeholders were removed from usr/lib/system after being
# measured: 0 inbound LC_LOAD_DYLIB references, 0 -l references in any
# Makefile, absent from the libSystem.B re-export list, absent from the bootlab
# runtime (mkimage.py, manifest.json, kernel_build.py, assets/rc) by NAME as
# well as by link, and with no source anywhere in the tree.
#
#   libcache.dylib                  no source
#   libquarantine.dylib             no source
#   libsystem_collections.dylib     no source
#   libsystem_configuration.dylib   no source
#   libsystem_containermanager.dylib no source
#
# Deleting is the correct outcome, not a shortfall: a placeholder nothing links
# is an active liability, because a future consumer will link against it and get
# a silent no-op at run time. DO NOT re-create these by inventing a source
# tree. If one is genuinely needed, implement it and its build system.
#
# This section also detects the REGRESSION in the other direction: if one of
# these names reappears, that is a stub being re-installed and it fails.
DELIBERATELY_ABSENT="libcache.dylib libquarantine.dylib \
  libsystem_collections.dylib libsystem_configuration.dylib \
  libsystem_containermanager.dylib"

for b in $DELIBERATELY_ABSENT; do
  if [ -e "$SDK/usr/lib/system/$b" ] || [ -e "$SDK/usr/lib/$b" ]; then
    echo "FAIL: $b has reappeared as a stub (deliberately removed)"
    fail=1
  else
    echo "ABSENT (deliberate): $b"
  fi
done

# --- 5. nothing anywhere in the library dirs may be 0 bytes ----------------
# This section used to carry a RECORDED_ZERO_BYTE_STUBS allow-list:
#
#   RECORDED_ZERO_BYTE_STUBS="libedit.dylib libncurses.dylib libncurses.6.dylib"
#
# All three entries are now GONE, and the allow-list with them. Nothing is
# excused here any more: a 0-byte file in these directories is a hard failure,
# full stop. Each entry was retired against a measurement, not a preference:
#
#   libedit.dylib     BUILT. 247,072 bytes, from BSD/lib/libedit (36 .c) via
#                     that directory's Darwin branch, which no longer touches.
#   libutil.dylib     BUILT. 18,936 bytes. It was never allow-listed -- the
#                     comment below records why -- and it is now real too.
#   libncurses.dylib  REMOVED, not built. Nothing references it: measured
#   libncurses.6.dylib 2026-10-02, zero LC_LOAD_DYLIB references to either name
#                     exist anywhere in the SDK or in the staged bootlab
#                     closure. Their producer, BSD/lib/ncurses/Makefile, was a
#                     `touch` on the Darwin branch -- the same silent-stub
#                     defect this script exists to catch -- and that branch now
#                     fails loudly instead of writing the files.
#
# Why removal rather than a real build: ncurses' own build runs its configure
# plus gmake, is not on the Libsystem or dynamic-userland critical path, and
# building it would add a large unverified dependency to satisfy a link that
# does not exist. If a BSD utility ever needs it, the loud failure at
# BSD/lib/ncurses names exactly that prerequisite. A loud failure beats a
# silent stub -- but a *recorded* stub is nearly as bad, because the list is
# what let two of these survive for weeks.
#
# libutil.dylib is recorded here because it is the counter-example worth
# keeping: it was the one zero-byte file deliberately NOT allow-listed, because
# it is libSystem-adjacent, so it had to be built rather than excused. Building
# it required removing the `touch` from BSD/lib/libutil/Makefile, which carried
# the same Darwin branch that destroyed libCrashReporterClient. That is now
# done, which is why it is not in this section at all.

# --- 5b. the retired stubs must STAY gone ---------------------------------
# The other direction matters as much: if one of these names reappears, that is
# a stub being re-installed by a build path nobody has re-audited, and it must
# fail rather than pass unnoticed. Same reasoning as DELIBERATELY_ABSENT above.
DELIBERATELY_ABSENT_STUBS="libncurses.dylib libncurses.6.dylib"

for b in $DELIBERATELY_ABSENT_STUBS; do
  found=""
  for d in usr/lib usr/lib/system usr/local/lib/system; do
    [ -e "$SDK/$d/$b" ] && { found="$SDK/$d/$b"; break; }
  done
  if [ -n "$found" ]; then
    sz=$(measure "$found")
    if [ "${sz:-0}" -eq 0 ]; then
      echo "FAIL: $found is 0 bytes -- a retired stub has returned"
      fail=1
    else
      echo "FAIL: $found has returned. If ncurses was built for real, delete"
      echo "      this name from DELIBERATELY_ABSENT_STUBS once, deliberately."
      fail=1
    fi
  fi
done

for dir in usr/lib usr/lib/system usr/local/lib/system; do
  [ -d "$SDK/$dir" ] || continue
  for f in "$SDK/$dir"/*.dylib "$SDK/$dir"/*.a; do
    [ -e "$f" ] || continue
    sz=$(measure "$f")
    [ "${sz:-0}" -eq 0 ] || continue
    b=$(basename "$f")
    echo "FAIL: $dir/$b is 0 bytes"
    fail=1
  done
done

if [ "$fail" = 0 ]; then
  echo "== OK: no stub regressions =="
else
  echo "== FAILED: a real library has been replaced by a stub, or is missing =="
fi
exit $fail
