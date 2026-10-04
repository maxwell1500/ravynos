#!/bin/bash
# build_launchd.sh -- build BSD/sbin/launchd as a DYNAMIC x86_64 Mach-O
# executable linked against this repository's own Libsystem (libSystem.B.dylib
# in the ravynOS SDK), and then verify the resulting shape.
#
# WHY THIS EXISTS
#   BSD/sbin/launchd/Makefile is a bsd.prog.mk target that:
#     - links -static against FreeBSD libc.a / crt1.o, not -lSystem;
#     - expects the FreeBSD library set (auditd bsm util dispatch mach
#       BlocksRuntime launch osxsupport xpc nv sbuf pthread), of which this
#       tree has none in that form;
#     - runs `mig` with -I${MACHINE_INCLUDES} and BSD/include on the path,
#       which shadows the SDK's own mach/ and sys/ headers with FreeBSD ones
#       that then fail on vm/vm.h and friends.
#   So this script takes the SRCS list FROM that Makefile -- it stays the
#   single source of truth for which files make up launchd -- and supplies the
#   compile/link lines that actually work against our SDK.
#
# PREREQUISITE
#   tools/bootlab/build_all_libsystem.sh      # builds + installs libSystem.B
#
# WHAT IS ACTUALLY A STUB:  nothing.  Every object here is compiled from the
# vendored BSD/sXin/launchd sources in this repository.  No symbol is faked
# and no prebuilt host binary is used.  The `compat/` directory below holds
# HEADERS ONLY -- they are the private Apple headers the SDK does not ship.
# They declare; they do not implement.  Every symbol those headers declare is
# still resolved at link time from the real dylibs or reported as undefined.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
BUILD="${RAVYN_BUILD_DIR:-/Users/max/Projects/build}"
SDK="$BUILD/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk"
SRCDIR="$REPO/BSD/sbin/launchd"
OUT="${LAUNCHD_OUT:-$HERE/work/launchd}"
WORK="$HERE/work/launchd-build"

CC=(${CLANG:-xcrun clang})
MIG="$REPO/Developer/Default.xctoolchain/usr/bin/mig"

# SRCS, verbatim from BSD/sbin/launchd/Makefile lines 44-48.  The *Server.c /
# *User.c files are NOT listed because they are mig output, generated below
# into $WORK/gen by the same rules as the Makefile's lines 25-40.
SRCS_HAND="launchd.c core.c kill2.c ktrace.c ipc.c log.c runtime.c init/init.c"
SRCS_MIG="jobServer mach_excServer internalServer job_forwardUser job_replyUser \
          job_replyServer notifyServer internalUser"

die() { echo "FATAL: $*" >&2; exit 1; }

# ------------------------------------------------------------------- preflight
require_sdk() {
    [ -d "$SDK" ] || die "SDK not found: $SDK
       Build Libsystem first: tools/bootlab/build_all_libsystem.sh"
    [ -f "$SDK/usr/lib/libSystem.B.dylib" ] || die "no libSystem.B.dylib in $SDK/usr/lib
       Build Libsystem first: tools/bootlab/build_all_libsystem.sh"
    [ -x "$MIG" ] || die "mig not found/executable: $MIG"
    "${CC[@]}" -dumpversion >/dev/null 2>&1 || die "no working compiler: ${CC[*]}"
}

# ------------------------------------------------------------------ comp.flags
# SDK include order matters and is the single most load-bearing decision here.
#
#   -isystem $COMPAT/bsm   FIRST, so the repo's Libraries/openbsm bsm/ headers
#                          win over the SDK's older copies.  The SDK's
#                          bsm/audit.h predates au_evname_map_t, which
#                          openbsm/bsm/libbsm.h uses at its :1306-1307.
#   -isystem $SDK/usr/include  next: the authoritative system headers.
#   -isystem $COMPAT       next: the five headers the SDK genuinely lacks.
#   -isystem liblaunch     last: launch.h/vproc.h/bootstrap.h.
#
# BSD/include is NOT on the path.  It must not be: its mach/ and sys/ headers
# are FreeBSD and shadow the SDK's, then fail on vm/vm.h.
CFLAGS_COMMON=(-c -arch x86_64 -isysroot "$SDK" -mmacos-version-min=15.0
               -std=gnu11 -fPIC -fblocks
               -D__APPLE__ -DPRIVATE -D__unused= -DHAVE_INTTYPES_H
               -DLIBC_NO_LIBCRASHREPORTERCLIENT
               # Makefile line 16.  Without it mig emits a `kr` use in the
               # reply server that it never declares:
               #   job_replyServer.c:169:74: error: use of undeclared
               #                                     identifier 'kr'
               -D__MigTypeCheck
               -Wall -Wno-unused-parameter -Wno-macro-redefined
               -include "$WORK/compat/force_compat.h"
               -I"$SRCDIR" -I"$WORK/gen"
               -isystem "$WORK/compat-bsm"
               -isystem "$SDK/usr/include"
               -isystem "$WORK/compat"
               -isystem "$REPO/Libraries/Libsystem/liblaunch")

# log.c's boolean_t collision is handled in force_compat.h, not on the command
# line: `-Dboolean_t='unsigned int'` cannot survive this script's
# space-splicing of the per-file extra flags, and reached clang as the two
# arguments `-Dboolean_t=unsigned` and `int`.

# -L$SDK/usr/lib/system matters for the same reason as in build_dynutils.sh:
# libSystem.B RE-EXPORTs libsystem_c and libxpc, and ld64 only follows a
# reexport when it can find the target.
LDFLAGS_COMMON=(-nostdlib -nostdlibinc -nodefaultlibs
                -Wl,-no_uuid -Wl,-e,_main -arch x86_64
                -L"$SDK/usr/lib" -L"$SDK/usr/lib/system" -lSystem)

# ------------------------------------------------------------------ compat tree
# Headers ONLY, all symlinks into this repository.  Nothing here defines a
# function body; see the header comment above.
make_compat() {
    local c="$WORK/compat"
    mkdir -p "$c/sys/mach" "$c/sys/bsm" "$c/os" "$c/bsm" "$WORK/compat-bsm/bsm"
    mk() { ln -sfn "$2" "$c/$1"; }
    local A="$REPO/BSD/include/apple" SDKH="$SDK/usr/include" MH="$SDK/usr/include/mach"

    # --- headers the SDK does not ship at all
    mk os/object.h              "$REPO/BSD/include/os/object.h"
    mk _simple.h                 "$REPO/Libraries/Libsystem/private/_simple.h"
    mk spawn.h                   "$A/spawn.h"
    mk spawn_private.h           "$A/spawn_private.h"
    mk libproc.h                 "$A/libproc.h"
    mk libproc_internal.h        "$A/libproc_internal.h"
    mk sys/endian.h              "$REPO/Libraries/Libsystem/libsystem_c/fbsdcompat/sys/endian.h"
    mk sys/fileport.h            "$A/sys/fileport.h"
    mk sys/kern_memorystatus.h   "$A/sys/kern_memorystatus.h"
    mk sys/spawn_internal.h      "$A/sys/spawn_internal.h"
    mk bsm/audit_session.h       "$REPO/BSD/include/bsm/audit_session.h"

    # sys/mach/* is a FreeBSD-ism: BSD's own headers include <sys/mach/port.h>
    # where Apple uses <mach/port.h>.  Repoint, do not copy.
    for h in port.h boolean.h vm_types.h mach.h; do mk "sys/mach/$h" "$MH/$h"; done
    mk sys/mach/host_special_ports.h "$MH/host_special_ports.h"
    mk sys/mach/thread_status.h       "$MH/thread_status.h"

    # --- openbsm: the repo's copy is newer than the SDK's and is the one
    # openbsm/bsm/libbsm.h is written against.
    for h in libbsm.h auditd_lib.h audit_filter.h audit_uevents.h; do
        mk "bsm/$h" "$REPO/Libraries/openbsm/bsm/$h"
    done
    for h in audit.h audit_domain.h audit_errno.h audit_fcntl.h audit_internal.h \
             audit_kevents.h audit_record.h audit_socket_type.h; do
        mk "bsm/$h"      "$REPO/Libraries/openbsm/sys/bsm/$h"
        mk "sys/bsm/$h"  "$REPO/Libraries/openbsm/sys/bsm/$h"
    done

    # --- bsm shadow.  It needs its OWN -isystem root searched BEFORE the SDK's.
    # openbsm/bsm/libbsm.h includes <bsm/audit.h> and needs the repo's newer
    # copy (the one with au_evname_map_t).  Pointing -isystem at $c does not
    # achieve that: $c is searched AFTER $SDK/usr/include, so the SDK's older
    # audit.h still wins and libbsm.h:1306-1307 fails on the unknown type.
    for h in libbsm.h auditd_lib.h audit_filter.h audit_uevents.h \
             audit.h audit_domain.h audit_errno.h audit_fcntl.h \
             audit_internal.h audit_kevents.h audit_record.h \
             audit_socket_type.h audit_session.h; do
        [ -e "$c/bsm/$h" ] && ln -sfn "$(readlink "$c/bsm/$h")" \
                                       "$WORK/compat-bsm/bsm/$h"
    done

    # sys/proc_info.h needs the same treatment: the SDK's copy predates
    # struct proc_uniqidentifierinfo / PROC_PIDUNIQIDENTIFIERINFO, which
    # core.c:4564 and runtime.c:1384 use.  BSD/include/apple/sys/proc_info.h
    # has them.  It has to land in the pre-SDK root, not $c, for the same
    # reason the bsm headers do.
    mkdir -p "$WORK/compat-bsm/sys"
    ln -sfn "$A/sys/proc_info.h" "$WORK/compat-bsm/sys/proc_info.h"
}

# ------------------------------------------------------- SDK defect workarounds
# Gaps closed here because the SDK does not carry Apple's private half of the
# headers launchd was written against, plus two names launchd expects the
# platform to supply.  Each is a real, verified defect, not a guess; see the
# comments in force_compat.h.
make_force_compat() {
    mkdir -p "$WORK/compat"
    cat > "$WORK/compat/force_compat.h" <<'EOF'
/* Force-included ahead of every translation unit.  Closes three gaps between
 * this SDK and the private Apple headers BSD/sbin/launchd was written against.
 * Declarations only -- no symbol is defined or faked here.
 *
 * 1. __ASSUME_PTR_ABI_SINGLE_BEGIN/END.
 *    tools/bootlab/build-libraries.sh appends a shim block to
 *    $SDK/usr/include/sys/cdefs.h to supply these and friends, but guards it
 *    with `#ifndef __has_ptrcheck`.  clang defines __has_ptrcheck as a
 *    BUILTIN macro (it expands to 0), so `#ifndef` is never true and the
 *    whole block is dead.  Any consumer reaching sys/protosw.h -- launchd
 *    does, via netinet/in_var.h in runtime.h -- then fails:
 *      sys/protosw.h:72:1: error: unknown type name
 *                              '__ASSUME_PTR_ABI_SINGLE_BEGIN'
 *    The correct guard is `#if !__has_ptrcheck`.  This is a one-character
 *    fix in build-libraries.sh and should be made there; until then, supply
 *    the macros here.
 */
#ifndef __ASSUME_PTR_ABI_SINGLE_BEGIN
#define __ptrcheck_abi_assume_single()
#define __ptrcheck_abi_assume_unsafe_indexable()
#define __ASSUME_PTR_ABI_SINGLE_BEGIN  __ptrcheck_abi_assume_single()
#define __ASSUME_PTR_ABI_SINGLE_END    __ptrcheck_abi_assume_unsafe_indexable()
#endif
#ifndef __ptrcheck_unavailable
#define __ptrcheck_unavailable
#define __ptrcheck_unavailable_r(REPLACEMENT)
#endif

/* 2. LOG_CONSOLE.  A launchd-private syslog bit (1<<31) that Apple defines in
 *    a private syslog.h.  launchd/log.h carries it under `#ifdef notyet`,
 *    i.e. upstream expects the platform header to supply it, and log.c:163
 *    masks it back off the priority -- so only "a single distinct high bit"
 *    matters.  Absent from this SDK's sys/syslog.h and from every host SDK.
 */
#ifndef LOG_CONSOLE
#define LOG_CONSOLE (1 << 31)
#endif

/* 3. RB_POWEROFF / RB_PAUSE.  The private half of <sys/reboot.h>.  This SDK's
 *    copy -- like the host SDK's, like BSD/include/sys/reboot.h and like
 *    xnu's bsd/sys/reboot.h -- stops at RB_PANIC_FORCERESET 0x2000.  Apple
 *    carries these two in the private copy, which the SDK does not ship.
 *    runtime.c:276 uses RB_POWEROFF; shim.h derives RB_UPSDELAY, RB_SAFEBOOT,
 *    RB_UNIPROC and RB_ALTBOOT from RB_PAUSE.  Values are Apple's.
 */
#ifndef RB_POWEROFF
#define RB_POWEROFF    0x4000   /* power off instead of reboot */
#endif
#ifndef RB_PAUSE
#define RB_PAUSE       0x8000   /* pause for the debugger */
#endif

/* 3b. TASK_SEATBELT_PORT.  core.c:8688 compares ms->special_port_num against
 *     it, but this SDK's usr/include/mach/task_special_ports.h carries it only
 *     as a "Was ..." comment (xnu removed port 7).  The SDK's own private copy
 *     at System.framework/Versions/B/PrivateHeaders/mach/task_special_ports.h:85
 *     still defines it as 7, which is the value used here.  Needed only so
 *     core.c compiles; it selects a log level for an anonymous job's failed
 *     special-port setup.
 */
#ifndef TASK_SEATBELT_PORT
#define TASK_SEATBELT_PORT 7
#endif

/* 4. boolean_t.  log.c opens with
 *      #ifndef boolean_t
 *      typedef int boolean_t;
 *      #endif
 *    before including anything, betting that a Mach header it has not reached
 *    yet will supply boolean_t.  On x86_64 the SDK's mach/i386/boolean.h says
 *    `unsigned int`, so that bet loses and clang rejects the redefinition:
 *      mach/i386/boolean.h:69:25: error: typedef redefinition with different
 *                               types ('unsigned int' vs 'int')
 *    Both the guard AND the typedef have to be settled here.  Claiming
 *    _MACH_I386_BOOLEAN_H_ alone is not enough -- it suppresses the header's
 *    typedef without supplying one, so mach/port.h then fails on
 *    "unknown type name 'boolean_t'".  Defining the type first, in the exact
 *    form the SDK header uses, satisfies both the header and log.c's guard.
 *    `unsigned int` is also the type libsystem_c was compiled with, so this
 *    agrees with the library rather than merely silencing the diagnostic.
 */
/* boolean_t must be a MACRO, not a typedef.  log.c's guard is `#ifndef
 * boolean_t`, and #ifndef only ever sees macros -- a typedef leaves the
 * guard satisfied-by-luck and log.c re-emits its own `typedef int`.  As a
 * macro the guard is false and log.c's typedef is skipped entirely.
 *
 * Only the ARCH guard is claimed.  mach/boolean.h -- the file that also
 * defines TRUE and FALSE -- must still run: the mig-generated *Server.c
 * files use TRUE (jobServer.c:1145) and claiming _MACH_BOOLEAN_H_ here
 * suppresses that header and leaves them undefined.
 */
#define boolean_t unsigned int
#ifndef _MACH_I386_BOOLEAN_H_
#define _MACH_I386_BOOLEAN_H_
#endif

/* 5. VQ_FLAG0100.  launchd/shim.h:35 writes
 *        #define VQ_UPDATE VQ_FLAG0100
 *    i.e. it reaches Apple's PRIVATE name for the bit rather than the public
 *    one.  Apple's private sys/mount.h supplies VQ_FLAG0100; the SDK's public
 *    sys/mount.h does not, so shim.h's alias expands to an undeclared
 *    identifier at every use (core.c:4334, :7055, runtime.c:562).
 *
 *    The value is not a guess: this SDK's own sys/mount.h already defines the
 *    public spelling of that same bit, as 0x0100 with the comment
 *    "filesystem information has changed" -- so VQ_FLAG0100 is 0x0100.
 *    Defining it makes shim.h's alias agree with the public header instead of
 *    contradicting it.
 */
#ifndef VQ_FLAG0100
#define VQ_FLAG0100 0x0100
#endif

/* 6. be64toh / be32toh.  The FreeBSD byte-order conversions.  core.c:6452 uses
 *    them to store a program-name hash into a mach port context:
 *        ctx = be64toh(ctx);
 *
 *    Neither name exists anywhere in this SDK.  core.c includes <sys/endian.h>,
 *    which the compat tree points at libsystem_c's fbsdcompat/sys/endian.h ->
 *    <machine/endian.h> -> <i386/endian.h> -> <sys/_endian.h> ->
 *    <machine/_endian.h>.  That chain defines ntohll/htonll and the
 *    __DARWIN_OSSwapInt* primitives, but never the FreeBSD `be*toh` family.
 *
 *    These are FreeBSD's definitions: a byte swap on a little-endian host,
 *    identity on a big-endian one.
 *
 *    The endian test MUST be clang's __BYTE_ORDER__, not the SDK's
 *    __DARWIN_BYTE_ORDER.  This header is force-included ahead of every other
 *    header, so <sys/_endian.h> -- the only thing that defines
 *    __DARWIN_BYTE_ORDER -- has not been read yet, and testing it here would
 *    silently select the IDENTITY arm on a little-endian host, turning the
 *    conversion into a no-op.  clang's __BYTE_ORDER__ is a builtin and is
 *    always defined.
 *
 *    __builtin_bswap* is used rather than __DARWIN_OSSwapInt* for the same
 *    reason: the latter also comes from <sys/_endian.h>.
 */
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define __launchd_be16toh(x) __builtin_bswap16(x)
#define __launchd_be32toh(x) __builtin_bswap32(x)
#define __launchd_be64toh(x) __builtin_bswap64(x)
#else
#define __launchd_be16toh(x) (x)
#define __launchd_be32toh(x) (x)
#define __launchd_be64toh(x) (x)
#endif

#ifndef be16toh
#define be16toh(x) __launchd_be16toh(x)
#endif
#ifndef be32toh
#define be32toh(x) __launchd_be32toh(x)
#endif
#ifndef be64toh
#define be64toh(x) __launchd_be64toh(x)
#endif

/* The matching FreeBSD STORE/LOAD half of the same family: be16enc/be32enc/
 * be64enc write a big-endian value through a pointer, be16dec/be32dec/be64dec
 * read one back.  Libraries/openbsm/libbsm/bsm_token.c and bsm_io.c use them
 * throughout to lay out audit records on disk.  Same missing header, same
 * fix.  __builtin_memcpy is what FreeBSD's own <sys/endian.h> uses here: the
 * destination may be unaligned, and a typed store through it would be UB. */
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define __launchd_be16enc(p, v) __builtin_memcpy((p), &(uint16_t){ __builtin_bswap16((uint16_t)(v)) }, 2)
#define __launchd_be32enc(p, v) __builtin_memcpy((p), &(uint32_t){ __builtin_bswap32((uint32_t)(v)) }, 4)
#define __launchd_be64enc(p, v) __builtin_memcpy((p), &(uint64_t){ __builtin_bswap64((uint64_t)(v)) }, 8)
#define __launchd_be16dec(p)    __builtin_bswap16(*(const uint16_t *)(p))
#define __launchd_be32dec(p)    __builtin_bswap32(*(const uint32_t *)(p))
#define __launchd_be64dec(p)    __builtin_bswap64(*(const uint64_t *)(p))
#else
#define __launchd_be16enc(p, v) __builtin_memcpy((p), &(uint16_t){ (uint16_t)(v) }, 2)
#define __launchd_be32enc(p, v) __builtin_memcpy((p), &(uint32_t){ (uint32_t)(v) }, 4)
#define __launchd_be64enc(p, v) __builtin_memcpy((p), &(uint64_t){ (uint64_t)(v) }, 8)
#define __launchd_be16dec(p)    (*(const uint16_t *)(p))
#define __launchd_be32dec(p)    (*(const uint32_t *)(p))
#define __launchd_be64dec(p)    (*(const uint64_t *)(p))
#endif

#ifndef be16enc
#define be16enc(p, v) __launchd_be16enc(p, v)
#endif
#ifndef be32enc
#define be32enc(p, v) __launchd_be32enc(p, v)
#endif
#ifndef be64enc
#define be64enc(p, v) __launchd_be64enc(p, v)
#endif
#ifndef be16dec
#define be16dec(p) __launchd_be16dec(p)
#endif
#ifndef be32dec
#define be32dec(p) __launchd_be32dec(p)
#endif
#ifndef be64dec
#define be64dec(p) __launchd_be64dec(p)
#endif
EOF
}

# ------------------------------------------------------------------------ mig
# All seven .defs.  The rules are the Makefile's own (lines 25-40).
#
# mig needs <mach/std_types.defs>, which BSD/include/mach/std_types.defs
# forwards to <sys/mach/std_types.defs> -- a path that exists ONLY in the
# kernel tree.  So the mig include path gets a shim/ tree that symlinks
# Kernel/xnu/osfmk/mach as both sys/mach and mach/machine.  Verified: without
# it mig aborts with "'sys/mach/std_types.defs' file not found" and then
# cascades into "type 'int' not defined".
make_mig_shim() {
    local m="$WORK/miginc"
    mkdir -p "$m/sys" "$m/mach"
    ln -sfn "$REPO/Kernel/xnu/osfmk/mach"     "$m/sys/mach"
    ln -sfn "$REPO/Kernel/xnu/osfmk/mach/machine" "$m/mach/machine"
}

run_mig() {
    local base="$1"; shift
    ( cd "$SRCDIR" && "$MIG" \
        -I. -I"$REPO/BSD/include/apple" -I"$REPO/BSD/include" -I"$REPO/BSD/sys" \
        -I"$WORK/miginc" \
        -D__APPLE__ -DPRIVATE \
        -header "$WORK/gen/$base.h" -sheader "$WORK/gen/${base}Server.h" \
        "$@" "$SRCDIR/$base.defs" ) >> "$WORK/mig.log" 2>&1 \
        || { echo "--- mig failed for $base.defs ---" >&2
             tail -20 "$WORK/mig.log" >&2; die "mig $base"; }
}

generate_mig() {
    mkdir -p "$WORK/gen"
    : > "$WORK/mig.log"
    # helper.defs: headers only, both stubs to /dev/null (Makefile line 26).
    ( cd "$SRCDIR" && "$MIG" \
        -I. -I"$REPO/BSD/include/apple" -I"$REPO/BSD/include" -I"$REPO/BSD/sys" \
        -I"$WORK/miginc" -D__APPLE__ -DPRIVATE \
        -user /dev/null -server /dev/null \
        -header "$WORK/gen/helper.h" -sheader "$WORK/gen/launchd_helperServer.h" \
        "$SRCDIR/helper.defs" ) >> "$WORK/mig.log" 2>&1 \
        || { tail -20 "$WORK/mig.log" >&2; die "mig helper"; }

    run_mig job         -sheader "$WORK/gen/jobServer.h"
    run_mig job_reply   -header "$WORK/gen/job_reply.h" -sheader "$WORK/gen/job_replyServer.h"
    run_mig job_forward -header "$WORK/gen/job_forward.h" -sheader "$WORK/gen/job_forwardServer.h"
    run_mig notify      -header "$WORK/gen/notify.h" -sheader "$WORK/gen/notifyServer.h"
    run_mig mach_exc    -sheader "$WORK/gen/mach_excServer.h"
    run_mig internal    -header "$WORK/gen/internal.h" -sheader "$WORK/gen/internalServer.h"
}

# --------------------------------------------------------------------- compile
compile_one() {
    local src="$1" extra="${2:-}"
    local o="$WORK/obj/$(echo "$src" | tr / _ | sed 's/\.c$/.o/')"
    mkdir -p "$(dirname "$o")"
    local log="$WORK/logs/$(basename "$src" .c).log"
    mkdir -p "$WORK/logs"
    if "${CC[@]}" "${CFLAGS_COMMON[@]}" $extra -o "$o" "$SRCDIR/$src" 2> "$log"; then
        echo "  OK   $src"
    else
        echo "  FAIL $src" >&2
        grep -E 'error:' "$log" | head -10 >&2
        return 1
    fi
    OBJS+=("$o")
}

# ------------------------------------------------------------------ openbsm
# launchd needs two symbols from OpenBSM that nothing in this tree currently
# provides: audit_quick_stop() (Libraries/openbsm/libauditd/auditd_lib.c) and
# audit_token_to_au32() (Libraries/openbsm/libbsm/bsm_wrappers.c).  The SDK
# ships no libbsm/libauditd at all, so `-lbsm` has nothing to resolve to --
# the Makefile's LIBADD entry "auditd bsm" is genuinely unsatisfiable as
# written.  The sources ARE vendored here, so they are compiled from source
# and linked in directly.  Nothing is stubbed: these are the real OpenBSM
# translation units.
#
# They compile against the SAME compat roots the launchd sources use, which is
# what makes this work without a second header strategy:
#   * compat-bsm supplies openbsm's own newer bsm/ and sys/bsm/ headers, ahead
#     of the SDK's older copies -- without it bsm/libbsm.h:1306 fails on
#     au_evname_map_t (see make_compat).
#   * compat supplies the five headers the SDK lacks, incl. os/object.h, which
#     <dispatch/dispatch.h> pulls in.
#   * force_compat.h supplies the FreeBSD endian family that bsm_token.c and
#     bsm_io.c use to lay out audit records.
OPENBSM="$REPO/Libraries/openbsm"
compile_openbsm() {
    local f b o log rc=0
    for f in "$OPENBSM"/libbsm/*.c "$OPENBSM"/libauditd/*.c; do
        b="$(basename "$f" .c)"
        o="$WORK/obs/$b.o"; log="$WORK/logs/obs_$b.log"
        mkdir -p "$WORK/obs" "$WORK/logs"
        # HAVE_IPC_PERM__SEQ / __KEY: openbsm probes these with autoconf's
        # AC_CHECK_MEMBERS and ships config/config.h with all four spellings
        # undefined (it was configured against FreeBSD's ipc_perm, which uses
        # bare `seq`/`key`).  The struct this build actually sees --
        # Kernel/xnu/bsd/sys/ipc.h:107 -- spells them `_seq`/`_key`, which is
        # the branch HAVE_IPC_PERM__SEQ selects.  Without them bsm_token.c
        # falls through to perm->seq/perm->key and fails to compile.
        if "${CC[@]}" -c -arch x86_64 -isysroot "$SDK" -mmacos-version-min=15.0 \
            -std=gnu11 -fPIC -w \
            -DHAVE_IPC_PERM__SEQ=1 -DHAVE_IPC_PERM__KEY=1 \
            -include "$WORK/compat/force_compat.h" \
            -isystem "$WORK/compat-bsm" -isystem "$SDK/usr/include" \
            -isystem "$WORK/compat" -I"$OPENBSM" \
            -o "$o" "$f" 2> "$log"; then
            OBJS+=("$o")
        else
            echo "  FAIL openbsm/$b.c" >&2
            grep -E 'error:' "$log" | head -5 >&2
            rc=1
        fi
    done
    return $rc
}

# ----------------------------------------------------------------------- link
# NOTE on -lSystem only: launchd's Makefile lists LIBADD as a dozen FreeBSD
# libraries (auditd bsm util dispatch mach BlocksRuntime launch osxsupport xpc
# nv sbuf pthread).  Under libSystem.B every one of those is already a
# re-exported dylib -- util, xpc, dispatch, pthread and mach are all reached
# through -lSystem -- so listing them again would be redundant at best.
#
# The exceptions are OpenBSM (auditd bsm), which the SDK does not ship at all
# and which is therefore compiled from the vendored sources by
# compile_openbsm() above and linked in as ordinary objects; and any future
# real libbsm.dylib, which would be preferred over those objects.
link_it() {
    local extra=""
    [ -f "$SDK/usr/lib/libbsm.dylib" ] && extra="-lbsm"
    "${CC[@]}" "${LDFLAGS_COMMON[@]}" $extra -o "$OUT" "${OBJS[@]}" \
        2> "$WORK/link.log" \
        || { echo "--- link errors ---" >&2; cat "$WORK/link.log" >&2
             die "link failed"; }
}

# --------------------------------------------------------------------- verify
# The shape a dynamic launchd must have.  This is what makes the script
# trustworthy rather than merely runnable.
#
# Note what is NOT checked: LC_ID_DYLIB.  That load command belongs to MH_DYLIB
# and MH_BUNDLE only -- an MH_EXECUTE can never carry one, so asserting it
# would fail a correct binary.  "DYNAMIC" for an executable means MH_EXECUTE
# with DYLDLINK set and an LC_MAIN entry, which is what is asserted below.
# libSystem.B is likewise checked by INSTALL NAME (/usr/lib/libSystem.B.dylib),
# not by the $SDK build path: that path is a -L search path and is correctly
# absent from the linked output.
verify_one() {
    local out="$1" rc=0
    check() { if eval "$2"; then echo "  ok   $1"; else echo "  BAD  $1"; rc=1; fi; }
    check "is Mach-O 64 x86_64"  "[ \"\$(lipo -archs $out)\" = x86_64 ]"
    check "is MH_EXECUTE"        "otool -hv $out | grep -q 'EXECUTE'"
    check "is DYNAMIC (DYLDLINK)" \
          "otool -hv $out | grep -q DYLDLINK"
    check "has LC_MAIN"         "otool -l $out | grep -q 'LC_MAIN'"
    check "not static (no MH_PRELOAD)" \
          "! otool -hv $out | grep -q MH_PRELOAD"
    check "links libSystem.B.dylib" \
          "otool -L $out | grep -q '^[[:space:]]*/usr/lib/libSystem.B.dylib'"
    return $rc
}

# -------------------------------------------------------------------------- go
require_sdk
mkdir -p "$WORK"
make_mig_shim
make_compat
make_force_compat
generate_mig
echo "generated: $(ls "$WORK/gen" | wc -l | tr -d ' ') files"

OBJS=()
echo "compiling:"
for s in $SRCS_HAND; do compile_one "$s" || true; done
for s in $SRCS_MIG; do compile_one "$s.c" || true; done
echo
echo "compiling openbsm (libbsm + libauditd):"
compile_openbsm || die "openbsm failed to compile"
echo
echo "objects: ${#OBJS[@]}"
[ ${#OBJS[@]} -gt 0 ] || die "nothing compiled"
link_it

echo
echo "verifying shape:"
verify_one "$OUT" || die "shape verification failed"
echo
echo "built $OUT ($(stat -f%z "$OUT") bytes)"