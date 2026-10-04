#!/bin/bash
# Build the ravynOS userland libraries (Libsystem, dyld, ...) on a Darwin host.
#
# Why this wrapper exists:
#   * These Makefiles are FreeBSD bmake scripts, not GNU make.
#   * Apple clang's `cc` shim ignores a custom SDK passed as --sysroot when
#     resolving #include <...>; isysroot-cc rewrites it to -isysroot.
#   * Several Makefiles read environment variables that nothing in the repo
#     exports, and each one is a hard build failure (see below).
#
# Usage: tools/bootlab/build-libraries.sh [subdir ...]
#
#   --static-pthread-only
#         Build ONLY Libraries/Libsystem/libsystem_pthread/static, the
#         -DVARIANT_STATIC pthread archive that statically-linked userspace
#         binaries link (see Libraries/Libsystem/static/README.md). This
#         exists because the top-level `Libsystem` target also requires
#         libsystem_trace, which does not build, so a caller that only
#         needs the static archive cannot get it through the normal entry
#         point. Invoked by tools/bootlab/link-static.sh.

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUILD="${RAVYN_BUILD_DIR:-/Users/max/Projects/build}"
SDK="$BUILD/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk"
BMAKE="${BMAKE:-/usr/local/bin/bmake}"
# The compiler this build targets is the ravynOS platform toolchain's clang,
# NOT the host's.  These are different compilers and the difference is not
# cosmetic: host clang 21 (Apple clang version 21.0.0, clang-2100.1.1.101)
# SEGFAULTS compiling this tree's Objective-C, reproducibly, in
# CGObjCRuntime::ComputeIvarBaseOffset on the very first Foundation file it
# reaches:
#   Frameworks/Foundation/NSObject/NSObject.m:112
#   PLEASE ATTACH THE FOLLOWING FILES TO THE BUG REPORT
# so `build-libraries.sh --frameworks Foundation` died with no diagnostic at
# all.  The same command line under clang-17 (Apple clang version 17.0.6) from
# $PLATFORM_TOOLCHAIN_BIN compiles it with 3 warnings and no errors.
#
# Preferring it also matches the rest of this script, which already takes
# llvm-libtool-darwin and llvm-objcopy from that same peer toolchain because
# the host Command Line Tools does not ship them at all.  The sysroot question
# that made clang-17 unusable for C sub-builds does not arise: every -I this
# build needs is supplied by isysroot-cc and by the per-project CFLAGS, and
# clang-17 has no default sysroot to fall back on, so it simply uses the
# -isysroot it is given.
#
# Still overridable: REAL_CC=... on the command line wins, as before.
PLATFORM_TOOLCHAIN_BIN="$BUILD/Developer/Platforms/ravynOS.platform/Developer/Toolchains/Default.xctoolchain/usr/bin"
if [ -z "${REAL_CC:-}" ] && [ -x "$PLATFORM_TOOLCHAIN_BIN/clang" ]; then
    REAL_CC="$PLATFORM_TOOLCHAIN_BIN/clang"
fi
REAL_CC="${REAL_CC:-$(xcrun -f clang)}"
# MUST be exported, and this was the silent part: a plain assignment here is a
# shell variable of THIS script, and isysroot-cc is a separate process that
# reads $REAL_CC from its own environment.  Un-exported, it fell back to its
# own default of /usr/bin/cc -- the host compiler this whole block exists to
# avoid -- and the setting looked perfectly in effect while changing nothing.
# (A REAL_CC=... given on the command line arrives already exported, which is
# why passing it by hand worked and relying on the default never did.)
export REAL_CC

[ -d "$SDK" ] || { echo "missing SDK: $SDK" >&2; exit 1; }
[ -x "$BMAKE" ] || { echo "missing bmake: $BMAKE (brew install bmake)" >&2; exit 1; }

unset DEVELOPER_DIR   # must stay the stock Xcode/CLI one for the xcrun shims

# Several Makefiles interpolate ${PATH} into an *unquoted* recipe prefix
# (`PATH=${TOOLS}:${PATH} ... mach_install_mig.sh`). A PATH entry containing a
# space -- on this host "/Applications/VMware Fusion.app/Contents/Public" --
# makes /bin/sh field-split the assignment and try to exec the tail of the
# PATH as a command:
#   line 1: Fusion.app/Contents/Public:/usr/local/bin: No such file or directory
# Drop space-bearing entries before bmake ever sees PATH.
export PATH="$(echo "$PATH" | tr ':' '\n' | grep -v ' ' | paste -sd: -)"

export RAVYN_SDKROOT="$SDK" SYSROOT_DIR="$SDK"
export ROOT_SOURCE_DIR="$ROOT" ROOT_BINARY_DIR="$BUILD"
export CpuArch="${CpuArch:-x86_64}" MACOS_VERSION_MIN="${MACOS_VERSION_MIN:-15.0}"

# bmake ships its own copy of the FreeBSD mk files, and its bundled
# bsd.subdir.mk predates ravynOS's (different SUBDIR target names), which
# silently disables subdirectory recursion. -m forces the ravynOS versions.
MKMODULES="$ROOT/BSD/share/mk"
# cdefs.h only defines the __DARWIN_ONLY_* feature macros under an
# XNU_PLATFORM_* guard, which userspace never sets. Injected centrally by
# isysroot-cc so every sub-make inherits it.
export EXTRA_DEFINES="-DXNU_PLATFORM_MacOSX"
# EXTRA_INCLUDES is the include-path passthrough isysroot-cc honours (see the
# block in that script). It has to be RE-EXPORTED here, not merely inherited:
# bmake re-exports this script's own environment to the sub-makes, and a
# variable set in the caller's environment does not survive into them. That is
# the whole reason the mach-generation probe's treatment arm once came out
# byte-identical to its control (LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 19) --
# the flag reached the wrapper in a direct test and never reached it in the
# real build path.
# Forwarded verbatim and split on whitespace exactly as isysroot-cc consumes
# it (`for i in ${EXTRA_INCLUDES:-}`). Unset or empty adds nothing.
export EXTRA_INCLUDES="${EXTRA_INCLUDES:-}"
export CC="$HERE/isysroot-cc"   # wrapper: --sysroot -> -isysroot

# ---------------------------------------------------------------------------
# Environment variables the per-project Makefiles read but that nothing in the
# repo exports. Each one was a hard build failure.
# ---------------------------------------------------------------------------
#   DEVEL           -> Libraries/Libsystem/libmacho/Makefile uses it in .PATH;
#                      unset it resolved to "/Default.xctoolchain/...", and
#                      `cp: /Default.xctoolchain/include/stuff: No such file
#                      or directory` killed the libmacho dylib.
#   SDK_SOURCE_DIR  -> Libraries/dyld/Makefile and libsystem_c/libBase use it
#                      for -I/-include; unset it became "-I/usr/include", i.e.
#                      the *host* macOS headers, and
#                      "<built-in>:1:10: fatal error: '/usr/include/
#                      AvailabilityInternal.h' file not found" killed dyld.
#   TOOLS           -> prefix of the unquoted PATH= recipe prefix above.
#   PROD_VERSION    -> libsystem_info's link flags end in
#                      "-Wl,-current_version,${PROD_VERSION}", so empty gave
#                      "ld: -current_version: malformed version number
#                      '-compatibility_version' cannot fit in 32-bit xxxx.yy.zz".
export DEVEL="$ROOT/Developer"
export SDK_SOURCE_DIR="$SDK"
# TOOLS must be a *directory*, not a PATH-style list. libc_static's rule is
#     ${TOOLS}/llvm-libtool-darwin -o ${.OBJDIR}/libc.a -static ...
# so a colon list produced
#     /usr/bin:/bin:/usr/sbin:/sbin/llvm-libtool-darwin
# which is not a path, and libc_static died with "*** Error code 1" after all
# 14 subprojects had already compiled. It is also used as the prefix of the
# unquoted `PATH=${TOOLS}:${PATH}` recipe prefix, which a single directory
# satisfies just as well as a list.
# The peer-built llvm-libtool-darwin (7,338,024 B, LLVM 17.0.6) lives under the
# ravynOS platform toolchain; the host CLT does not ship it at all, so
# xcrun -f cannot find it.
# (PLATFORM_TOOLCHAIN_BIN is set above, where REAL_CC is resolved from it.)
# Assemble one directory holding every tool a recipe may name, so that the
# unquoted `PATH=${TOOLS}:${PATH}` prefix puts *our* xcrun ahead of the system
# one. libsystem_kernel's mach_install_mig.sh does `xcrun -sdk $SDKROOT -find
# mig` and the system xcrun cannot answer that here: it is a shim that dlopens
# libxcsdk.dylib out of $DEVELOPER_DIR/usr/lib, and that library ships only with
# a full Xcode. Symptom: "Reason: tried: '$ORIGIN/../lib/libxcsdk.dylib' (no such
# file)" then "*** Error code 134" with MIG= empty, before anything is generated.
TOOLS_DIR="$BUILD/Tools/bin"
mkdir -p "$TOOLS_DIR"
[ -x "$PLATFORM_TOOLCHAIN_BIN/llvm-libtool-darwin" ] &&
    ln -sf "$PLATFORM_TOOLCHAIN_BIN/llvm-libtool-darwin" "$TOOLS_DIR/llvm-libtool-darwin"
[ -x "$BUILD/Developer/usr/bin/xcrun" ] &&
    ln -sf "$BUILD/Developer/usr/bin/xcrun" "$TOOLS_DIR/xcrun"
# sys.mk:266 sets `OBJCOPY ?= ${TOOLS}/llvm-objcopy`, and bsd.prog.mk:205 /
# bsd.lib.mk:275 run `${OBJCOPY} --only-keep-debug ${PROG_FULL} ${.TARGET}`
# as the LAST step of a successful link. Same defect as llvm-libtool-darwin
# above, one tool later in the build: the host CLT ships llvm-objdump but no
# llvm-objcopy, so xcrun -f cannot find it and the peer toolchain does have it
# (4,804,560 B, LLVM 17.0.6). Symptom is narrow and misleading because it
# arrives only AFTER the link has already succeeded --
#   bmake[1]: exec(.../Tools/bin/llvm-objcopy): No such file or directory
#   *** Error code 1
# i.e. chroot_util.cpp compiled clean and `chroot_util` LINKED, and the
# failure is purely the debug-file extraction step.
[ -x "$PLATFORM_TOOLCHAIN_BIN/llvm-objcopy" ] &&
    ln -sf "$PLATFORM_TOOLCHAIN_BIN/llvm-objcopy" "$TOOLS_DIR/llvm-objcopy"

# Libraries/ICU/Makefile rewrites its own data library's install name through
# ${TOOLS}/install_name_tool, so that -licudata resolves to /usr/lib at run
# time.  The tool is in the host CLT, not in the peer toolchain (which ships
# LLVM tools only), so it is staged from there.  Without it ICU dies at the
# last step, after a complete build:
#   bmake[1]: exec(.../Tools/bin/install_name_tool): No such file or directory
[ -x "/usr/bin/install_name_tool" ] &&
    ln -sf "/usr/bin/install_name_tool" "$TOOLS_DIR/install_name_tool"
export TOOLS="$TOOLS_DIR"
export PROD_VERSION="${PROD_VERSION:-1229.100.1}"

# ---------------------------------------------------------------------------
# Toolchain resolution
# ---------------------------------------------------------------------------
# bsd.*.mk resolves tool names off ${TOOLCHAIN}, and BSD/share/mk/sys.mk:113
# hardcodes `/Library/Developer/Toolchains/Default.xctoolchain` -- a full-Xcode
# path that does not exist on a Command-Line-Tools-only host. Everything
# derived from it then points at nothing:
#   /Library/Developer/Toolchains/Default.xctoolchain/usr/bin/mig: No such file
#     (liblaunch, libsystem_notify, libsystem_info, libdispatch)
#   /Library/Developer/Toolchains/Default.xctoolchain/usr/bin/clang++: No such
#     file (MIGCC, which libdispatch/Makefile .exports as ${CC})
# Build a coherent mini-Developer tree under $BUILD so the hardcoded path
# resolves from both sides: point TOOLCHAIN at it, and put real tools where
# xcrun searches.
TOOLCHAIN_DIR="$BUILD/Developer/Toolchains/Default.xctoolchain"
DEVBIN="$BUILD/Developer/usr/bin"
mkdir -p "$TOOLCHAIN_DIR/usr/bin" "$DEVBIN"
export TOOLCHAIN="$TOOLCHAIN_DIR"

# The system xcrun refuses to start when DEVELOPER_DIR does not contain an
# xcrun of its own ("invalid DEVELOPER_DIR path (...), missing xcrun at:
# .../usr/bin/xcrun"), and libsystem_kernel's mach_install_mig.sh recipe sets
# DEVELOPER_DIR=${ROOT_BINARY_DIR}/Developer before calling
# `xcrun -sdk $SDKROOT -find mig`. Shim it, clearing DEVELOPER_DIR so we
# forward to the stock xcrun instead of recursing into this file.
cat > "$DEVBIN/xcrun" <<EOF
#!/bin/sh
# Shim installed by tools/bootlab/build-libraries.sh. See that script.
#
# "xcrun -sdk <sdk> -find <tool>" is answered locally for the tools this tree
# owns. Delegating is not an option: the real xcrun is itself a shim that
# dlopens libxcsdk.dylib out of \$DEVELOPER_DIR/usr/lib, and that library ships
# only with a full Xcode. On a Command-Line-Tools-only host it is absent, so
# forwarding produced
#   Reason: tried: '\$ORIGIN/../lib/libxcsdk.dylib' (no such file)
# and mach_install_mig.sh aborted with 134 before generating anything. We
# already know where mig/cc/c++ live, so answer -find directly and only
# delegate for anything else.
for t in mig cc c++; do
    if [ -x "$TOOLCHAIN_DIR/usr/bin/\$t" ] || [ -x "\$DEVBIN/\$t" ]; then
        for a in "\$@"; do
            if [ "\$a" = "-find" ]; then found=1; fi
            if [ -n "\${found:-}" ] && [ "\$a" = "\$t" ]; then
                if [ -x "\$DEVBIN/\$t" ]; then echo "\$DEVBIN/\$t"; else
                    echo "$TOOLCHAIN_DIR/usr/bin/\$t"; fi
                exit 0
            fi
        done
    fi
done
unset DEVELOPER_DIR
exec $(command -v xcrun) "\$@"
EOF
chmod +x "$DEVBIN/xcrun"

# Tools `xcrun -find` has to resolve. Prefer a real built tool when the tree
# already has one (Libraries/ builds mig into $TOOLCHAIN_DIR), else the host
# Command Line Tools, which ships a working mig.
#
# migcom is not optional: the CLT mig re-invokes itself through it, as
#   M=${MIGCOM-$(realpath "${scriptRoot}/../libexec/migcom")}
#   ... | "$M" "${migflags[@]}"
# Symlinking mig alone into $TOOLCHAIN_DIR/usr/bin moves scriptRoot, so
# ../libexec/migcom no longer resolves and every run dies with
#   mig: line 183: : command not found
#   cc: error: unable to execute command: Broken pipe: 13
# Lay the toolchain out the way mig expects, with libexec alongside.
for t in mig cc c++; do
    [ -x "$TOOLCHAIN_DIR/usr/bin/$t" ] && continue
    p="$(xcrun -f "$t" 2>/dev/null)"
    [ -x "$p" ] && ln -sf "$p" "$TOOLCHAIN_DIR/usr/bin/$t"
done
if [ ! -x "$TOOLCHAIN_DIR/usr/libexec/migcom" ]; then
    for p in "$(xcrun -f migcom 2>/dev/null)" \
             "$(dirname "$(xcrun -f mig 2>/dev/null)")/../libexec/migcom" \
             /Library/Developer/CommandLineTools/usr/libexec/migcom \
             /Applications/Xcode.app/Contents/Developer/usr/libexec/migcom; do
        if [ -n "$p" ] && [ -x "$p" ]; then
            mkdir -p "$TOOLCHAIN_DIR/usr/libexec"
            ln -sf "$p" "$TOOLCHAIN_DIR/usr/libexec/migcom"
            break
        fi
    done
fi
[ -e "$DEVBIN/mig" ] || ln -sf "$TOOLCHAIN_DIR/usr/bin/mig" "$DEVBIN/mig"
[ -e "$DEVBIN/cc" ]  || ln -sf "$TOOLCHAIN_DIR/usr/bin/cc"  "$DEVBIN/cc"

export MIG="$TOOLCHAIN_DIR/usr/bin/mig"
export MIGCC="$TOOLCHAIN_DIR/usr/bin/cc"
export MIGCOM="$TOOLCHAIN_DIR/usr/libexec/migcom"
# CXX must be the *wrapper*, not a bare compiler. bsd.*.mk resolves CXX from
# ${TOOLCHAIN}, which does not exist, so it has to be pointed somewhere; but
# pointing it at $TOOLCHAIN_DIR/usr/bin/c++ routes every C++ translation unit
# around isysroot-cc, and --sysroot then stays --sysroot, so clang falls back
# to the host Command Line Tools SDK and its headers leak in ahead of ours.
# That is exactly the chain Libraries/objc4 hit, because its Makefile compiles
# .mm files with ${CXX} directly:
#   /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/_stdlib.h:70
#   -> Kernel/xnu/bsd/sys/wait.h:110
#   -> Kernel/xnu/bsd/sys/resource.h:209: error: unknown type name 'uint8_t'
# The wrapper is clang++-compatible, so C++ and Objective-C++ work through it.
export CXX="$HERE/isysroot-cc"

# Developer/Default.xctoolchain in the source tree is a source layout with no
# built tools, so bsd.*.mk resolves ar/nm/strip/etc. to nonexistent paths. Point
# them at the host Command Line Tools. LD is left alone: it is passed to
# clang as -fuse-ld=<name>, not used as a path.
export REAL_AR="/usr/bin/ar"
for t in ranlib nm otool strip libtool dsymutil; do
    p="$(xcrun -f "$t" 2>/dev/null)"
    [ -x "$p" ] || p="/usr/bin/$t"
    [ -x "$p" ] && export "$(echo "$t" | tr a-z A-Z)=$p"
done
export AR="$HERE/macar"        # drops the -D that Darwin ar rejects
export LD="ld"

# bison: CoreServices/WindowServer/libxkbcommon/src/xkbcomp/parser.y uses
# %define api.pure, which needs bison >= 2.7. The Command Line Tools bison is
# 2.3 and dies at parser.y:88 with
#   syntax error, unexpected identifier, expecting string
# Homebrew's bison is keg-only (never on PATH); point the Makefiles' ${BISON}
# at it when it is present. Unset falls back to the Makefile default "bison".
for b in /usr/local/opt/bison/bin/bison /opt/homebrew/opt/bison/bin/bison; do
    [ -x "$b" ] && export BISON="$b" && break
done

# ---------------------------------------------------------------------------
# SDK header synchronization
# ---------------------------------------------------------------------------
# The build SDK is missing AvailabilityInternalPrivate.h, which
# Kernel/xnu/bsd/sys/resource_private.h and mach/exclaves.h include
# unconditionally for userspace. Install ours if absent.
for h in AvailabilityInternalPrivate.h; do
    [ -f "$ROOT/Developer/ravynOS.sdk/usr/include/$h" ] || continue
    [ -f "$SDK/usr/include/$h" ] || cp -f "$ROOT/Developer/ravynOS.sdk/usr/include/$h" "$SDK/usr/include/$h"
done

# mach/message.h is the header the SDK has the most of and the least of. The
# SDK copy is 35,792 B against osfmk/mach/message.h's 62,286 B, and it has NO
# `#if PRIVATE` region at all -- the whole private block was stripped. That is
# the entire mach_msg.c failure:
#   mach_msg.c:75:15:  error: unknown type name 'mach_msg_option64_t'
#   mach_msg.c:78:18:  error: use of undeclared identifier 'MACH64_SEND_MSG'
#   mach_msg.c:205:2:   error: use of undeclared identifier 'mach_msg_vector_t'
#
# SOURCED verbatim from osfmk/mach/message.h in three pieces, each with its
# source line named beside it in the file:
#   :1018       MACH_SEND_FILTER_NONFATAL (the one prerequisite the SDK lacks)
#   :605-624    mach_msgv_index_t, MACH_MSGV_MAX_COUNT,
#               LIBSYSCALL_MSGV_AUX_MAX_SIZE, mach_msg_vector_t
#   :1042-1161  __options_decl(mach_msg_option64_t, ...) and every MACH64_* bit
# :625-630 is deliberately omitted: it redefines mach_msg_aux_header_t, which
# this file already carries from the original sourcing further down.
#
# Same source as the port block, and for the same reason --
# LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 28 and 33. This project builds the
# kernel these types describe; Kernel/xnu is pristine from 394fe3eac3
# "Transplant Darwin 24.0 (xnu-11215) kernel" and the built kernel's banner is
# "Darwin Kernel Version 24.3.0". A wrong struct layout would corrupt
# silently, so the block is copied rather than reconstructed -- and 22 of the
# 23 MACH64_* values are aliases of mach_msg_option_t bits the SDK already
# defines, with MACH_SEND_FILTER_NONFATAL (0x00010000) being the same bit the
# SDK already assigns to MACH_SEND_ALWAYS.
#
# The census (LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 13) found 15 constants,
# across 7 headers, that Kernel/xnu/libsyscall references and the SDK mach
# tree does not define. They are SOURCED verbatim from in-tree xnu in the
# source SDK and synced here with cp -f, so a regenerated SDK keeps them.
for h in coalition.h machine.h host_special_ports.h message.h mach_param.h \
         port.h task_special_ports.h thread_special_ports.h; do
    [ -f "$ROOT/Developer/ravynOS.sdk/usr/include/mach/$h" ] || continue
    mkdir -p "$SDK/usr/include/mach"
    cp -f "$ROOT/Developer/ravynOS.sdk/usr/include/mach/$h" "$SDK/usr/include/mach/$h"
done

for h in usr/include/mach/message.h \
         System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/mach/message.h; do
    [ -f "$ROOT/Developer/ravynOS.sdk/$h" ] || continue
    mkdir -p "$SDK/$(dirname "$h")"
    cp -f "$ROOT/Developer/ravynOS.sdk/$h" "$SDK/$h"
done

# architecture/i386/asm_help.h had UNWIND_PROLOGUE and UNWIND_EPILOGUE stripped
# out of its #ifdef __ASSEMBLER__ block, in the SOURCE SDK as well as the
# generated one. SYS.h expands UNWIND_EPILOGUE, so every generated syscall
# stub died with
#   error: invalid instruction mnemonic 'unwind_epilogue'
# (the assembler lowercases the token in its diagnostic, which is why the
# string could not be found by searching for what the error said).
# The source copy is the ravynOS x86_64 port, not Apple's, so it must be
# refreshed IN PLACE rather than replaced from Apple's header.
# Synced unconditionally: -f, so a stale generated copy is overwritten rather
# than skipped by the -f "only if absent" logic above.
for h in architecture/i386/asm_help.h architecture/i386/reg_help.h \
         architecture/arm/asm_help.h architecture/arm64/asm_help.h; do
    [ -f "$ROOT/Developer/ravynOS.sdk/usr/include/$h" ] || continue
    mkdir -p "$SDK/usr/include/$(dirname "$h")"
    cp -f "$ROOT/Developer/ravynOS.sdk/usr/include/$h" "$SDK/usr/include/$h"
done

# IOKit.framework in the SDK is structurally incomplete: it has
# Versions/A/{Headers,PrivateHeaders} and nothing else -- no Versions/Current
# and no top-level Headers symlink. clang's framework-style include lookup
# needs those two, so every `#include <IOKit/...>` failed with
#   Kernel/xnu/libsyscall/mach/err_iokit.sub:31:10: fatal error:
#       'IOKit/IOReturn.h' file not found
#   note: did not find header 'IOReturn.h' in framework 'IOKit'
# even though IOReturn.h is present and correct. The header CONTENT is not the
# problem: `diff -rq` between the SDK's IOKit.framework/Versions/A/Headers and
# Kernel/xnu/BUILD/dst/System/Library/Frameworks/IOKit.framework/Versions/A/
# Headers reports no differences at all, so the SDK already carries the right
# generation. Only the two symlinks are missing.
#
# The symlink form is copied from System.framework, which resolves correctly:
#   Versions/Current -> A          (System.framework has -> B)
#   Headers         -> Versions/Current/Headers
# Idempotent, and it repairs structure rather than inventing content.
IOK="$SDK/System/Library/Frameworks/IOKit.framework"
if [ -d "$IOK/Versions/A" ]; then
    [ -e "$IOK/Versions/Current" ] || ln -s A "$IOK/Versions/Current"
    [ -e "$IOK/Headers" ] || ln -s Versions/Current/Headers "$IOK/Headers"
    [ -e "$IOK/PrivateHeaders" ] ||
        ln -s Versions/Current/PrivateHeaders "$IOK/PrivateHeaders"
fi

# System.framework has the same structural gap as IOKit had, and it is the one
# that blocks the dyld loader. Versions/B/PrivateHeaders/ is present and
# complete (186 headers under sys/, 18,015 B event.h among them), and
# Versions/Current -> B plus top-level PrivateHeaders/Resources/System
# symlinks all exist -- but there is no Headers directory and no top-level
# Headers symlink. clang's framework-style include lookup resolves
# `#include <System/sys/event.h>` through Headers/, so every <System/...>
# include in dyld failed with:
#   fatal error: 'System/sys/event.h' file not found
# even though the header is present and correct. Header CONTENT was never the
# problem; the same is true here.
#
# Repaired structurally, in the SDK rather than in dyld's makefile, so that
# every consumer of <System/...> is repaired rather than each one adding its
# own -I. Two links are needed, and the form is the one already used for
# IOKit above: Versions/B/Headers points at the real PrivateHeaders tree, and
# the top-level Headers points through Versions/Current. Idempotent, and it
# repairs structure rather than inventing content.
SYSF="$SDK/System/Library/Frameworks/System.framework"
if [ -d "$SYSF/Versions/B/PrivateHeaders" ]; then
    [ -e "$SYSF/Versions/B/Headers" ] || ln -s PrivateHeaders "$SYSF/Versions/B/Headers"
    [ -e "$SYSF/Headers" ] || ln -s Versions/Current/Headers "$SYSF/Headers"
fi

# libCrashReporterClient.a -- the dyld LOADER cannot use the .dylib.
# ld64 in -dylinker mode searches -L but will not accept a dylib, so with only
# usr/lib/system/libCrashReporterClient.dylib present the loader link dies with
#   ld: library 'CrashReporterClient' not found
# even though the dylib is present, valid, x86_64, and named on an -L path
# that is in the final argument list. This is not a broken library: putting a
# real .a on the same -L changes the error to "symbol(s) not found", i.e. the
# library is then located. It is also not a defect -- a dylinker is a
# self-contained image and is meant to link archives, which is why
# libunwind.a, libkernel.a, libc.a, libpthread.a, libplatform.a, libc++.a and
# libc++abi.a are ALL already present as .a in this SDK. This one archive was
# built and simply never installed.
if [ -f "$ROOT/Libraries/CrashReporterClient/libCrashReporterClient.a" ]; then
    mkdir -p "$SDK/usr/lib/system"
    cp -f "$ROOT/Libraries/CrashReporterClient/libCrashReporterClient.a" \
          "$SDK/usr/lib/system/libCrashReporterClient.a"
fi

# IOKitLib.h is NOT in the SDK, and not in xnu either -- xnu does not ship the
# IOKit userspace library, so the IOKit.framework copy above is complete for
# xnu's purposes and still short of what libsyscall's err_iokit.sub reaches:
#   Frameworks/IOKit/firewire/IOFireWireLib.h:224 -> <IOKit/IOCFPlugIn.h>
#   Frameworks/IOKit/IOCFPlugIn.h:37            -> <IOKit/IOKitLib.h>
# We own a genuine Apple copy of it, twice and byte-identical:
#   Kernel/IOKitUser/IOKitLib.h                    76,961 B
#   Kernel/kext_tools/FILES/3rd/IOKit/IOKitLib.h   76,961 B
# Copied from the former, not invented and not taken from the host macOS SDK.
# Checked for a generation clash before installing: the 21 k*-symbols
# IOKitLib.h names that come from IOKitKeys.h/IOTypes.h/IOReturn.h are all
# present in the SDK's IOKit headers. The four that are not (kIOMasterPortDefault,
# kIORegistryIterateParents, kIORegistryIterateRecursively,
# kIOServiceInteractionAllowed) are declared inside IOKitLib.h itself, so their
# absence elsewhere is expected rather than a gap.
IOKLIB_SRC="$ROOT/Kernel/IOKitUser/IOKitLib.h"
if [ -f "$IOKLIB_SRC" ] && [ -d "$IOK/Versions/A/Headers" ]; then
    cmp -s "$IOKLIB_SRC" "$IOK/Versions/A/Headers/IOKitLib.h" 2>/dev/null ||
        cp -f "$IOKLIB_SRC" "$IOK/Versions/A/Headers/IOKitLib.h"
fi


# The SDK carries several mach/ header trees, and whichever comes first on the
# include path wins -- they share an include guard, so only the first is ever
# read. Refresh them all. Copy-only, so headers that exist solely in the build
# SDK are left alone.
sync_mach() {
    [ -d "$1" ] && [ -d "$2" ] || return 0
    ( cd "$1" && find . -name '*.h' -exec sh -c \
        'for f do cmp -s "$f" "$0/$f" 2>/dev/null || cp -f "$f" "$0/$f"; done' \
        "$2" {} + ) 2>/dev/null
    return 0
}

# Source of truth for mach/: Developer/ravynOS.sdk, i.e. this project's own SDK
# tree. It is internally consistent (mach_types.h and task.h both carry the
# suid_cred_* family) and it is what produced the 154 libsystem_platform and
# 212 libsystem_info objects.
#
# Do NOT substitute the in-tree xnu mach trees here, even though they are a
# different generation. Measured, both ways:
#   - Kernel/xnu/BUILD/dst/.../PrivateHeaders/mach (114 files) supplies
#     mach_msg_aux_header_t (message.h:629) and LIBSYSCALL_MSGV_AUX_MAX_SIZE
#     (:615), which the SDK's 902-line message.h lacks -- but its mach_types.h
#     has no suid_cred_*, so mach/task.h:846 dies with
#     "unknown type name 'suid_cred_path_t'".
#   - Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/mach (107 files, has task.h)
#     replaces both consistently, and then
#     "libsyscall/mach/mach/mach_init.h:79:18: error: conflicting types for
#     'mach_task_is_self'" -- the xnu's own mach.h and the SDK's disagree.
# Both substitutions are strictly worse than the one missing type, which
# isysroot-cc supplies directly (see the compat header it force-includes).
#
# Note this cannot fix libxpc / libsystem_asl / libsystem_dnssd either: they
# also put ${SLF}/Kernel.framework/Versions/A/{,Private}Headers on the include
# path, and that tree is the *kernel-internal* mach generation -- it declares
# io_main_t and ipc_space_read_t, which exist only under KERNEL, so it fails
# with "unknown type name 'io_main_t'". Developer/ravynOS.sdk has no
# Kernel.framework at all, so there is nothing to refresh it from.
SRV="$ROOT/Developer/ravynOS.sdk"
sync_mach "$SRV/usr/include/mach" "$SDK/usr/include/mach"
sync_mach "$SRV/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/mach" \
          "$SDK/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/mach"

# fbio.h and consio.h are kernel-private headers that WindowServer needs.
# They live in Kernel/xnu/bsd/sys/ and are listed in PRIVATE_DATAFILES, whose
# xnu install target is System.framework/PrivateHeaders/sys
# (INSTALL_SF_MI_LCL_LIST = ${DATAFILES} ${PRIVATE_DATAFILES}). WindowServer,
# however, includes them as <sys/fbio.h>/<sys/consio.h>, and an angle-bracket
# include resolves through the sysroot's usr/include, not through a framework
# path -- CoreServices/WindowServer/BSDFramebuffer.h:42-43 does exactly that.
# So install into BOTH SDK sys trees, the same way sync_mach refreshes both
# mach trees above. Neither tree has a sync mechanism for bsd/sys headers, so
# this is the only place they are staged.
for h in fbio.h consio.h; do
    [ -f "$ROOT/Kernel/xnu/bsd/sys/$h" ] || continue
    for d in "$SDK/usr/include/sys" \
             "$SDK/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/sys"; do
        mkdir -p "$d"
        cp -f "$ROOT/Kernel/xnu/bsd/sys/$h" "$d/$h"
    done
done

# login_cap.h is the public half of the login_cap(3) subsystem vendored into
# BSD/lib/libutil (login_cap.c, login_class.c, login_auth.c, _secure_path.c).
# WindowServer.h:43 includes <login_cap.h> and WindowServer.m:548-554 calls
# login_getpwclass/login_close/setusercontext to drop privileges before
# exec'ing the desktop session, so the header has to be in the SDK like any
# other system header.  There is no bsd/sys install rule for it -- the
# library's own Makefile installs only the dylib -- so stage it here, from the
# source SDK copy, the same way the fbio.h/consio.h block above stages bsd/sys
# headers.  Unconditional cp -f so an edit to the vendored header reaches the
# build SDK instead of being masked by a stale copy.
if [ -f "$SRV/usr/include/login_cap.h" ]; then
    mkdir -p "$SDK/usr/include"
    cp -f "$SRV/usr/include/login_cap.h" "$SDK/usr/include/login_cap.h"
fi

# sys/cdefs.h is the other split-brain header. The SDK's copy (1,010 lines) is
# missing 60 macros that Kernel/xnu/bsd/sys/cdefs.h defines, two of which were
# hard build failures because headers in both trees use them unconditionally:
#   Kernel/xnu/bsd/sys/cdefs.h:167  __stateful_pure
#       used by the SDK's own Kernel.framework/.../PrivateHeaders/string.h:276
#         string.h:276:21: error: unknown type name '__stateful_pure'
#   Kernel/xnu/bsd/sys/cdefs.h:451  __osloglike
#       used by Kernel/xnu/libkern/os/log.h:69
#         os/log.h:69:1: error: expected function body after function declarator
#
# Add those two, and ONLY those two, rather than overwriting the SDK's copy.
# Copying xnu's cdefs wholesale is a regression: it is a different generation
# that does not carry the libc variant macros, and libsystem_pthread (which has
# no -I for libsystem_c/include and so reads the SDK's cdefs) then compiled both
# variants/*.c to the same symbol:
#   ld: duplicate symbol '_pthread_cond_wait$NOCANCEL' in:
#       libsystem_pthread.a(pthread_cancelable.o)
#       libsystem_pthread.a(pthread_cancelable_cancel.o)
# Each is #ifndef-guarded, so this is idempotent and cannot affect a tree that
# already has them.
CDEFS_TAIL='
/* --- BEGIN ravynOS cdefs shim (tools/bootlab/build-libraries.sh) --- */
#ifndef __stateful_pure
#define __stateful_pure __attribute__((__pure__))
#endif
#ifndef __osloglike
#define __osloglike(fmtarg, firstvararg) \
	__attribute__((__format__ (__os_log__, fmtarg, firstvararg)))
#endif

/*
 * Three more macros that the cdefs.h in this SDK predates and that headers
 * in the SAME tree use unconditionally, each with the same failure: undefined,
 * they are parsed as identifiers.
 *
 *   System.framework/.../PrivateHeaders/sys/kdebug_private.h:476
 *       uintptr_t thread __kernel_data_semantics;
 *     -> error: expected semicolon at end of declaration list  (libdispatch)
 *   generated <string.h>:864  __kpi_deprecated_arm64_macos_unavailable
 *     -> error: unknown type name                              (libxpc, asl, dnssd)
 *
 * Definitions are the userspace ones from Kernel/xnu/bsd/sys/cdefs.h: the
 * kalloc-type annotations expand to nothing outside the kernel, which has no
 * xnu_usage_semantics attribute, and __kpi_deprecated_arm64_macos_unavailable
 * is empty for "!KERNEL || !XNU_PLATFORM_MacOSX" (cdefs.h:258,260). All are
 * ABI-neutral, so nothing here can change a symbol.
 */
#ifndef __kernel_ptr_semantics
#define __kernel_ptr_semantics
#endif
#ifndef __kernel_data_semantics
#define __kernel_data_semantics
#endif
#ifndef __kernel_dual_semantics
#define __kernel_dual_semantics
#endif
#ifndef __kpi_deprecated_arm64_macos_unavailable
#define __kpi_deprecated_arm64_macos_unavailable
#endif

/*
 * The ABI-neutral pointer attributes. The cdefs.h in this SDK is an older
 * generation that predates them, but the headers in that same SDK use them
 * unconditionally -- there is no repository-side socket.h/sysctl.h/if.h
 * to fix, these only exist in the generated tree:
 *   usr/include/sys/socket.h:561,565   void *__sized_by(msg_namelen) msg_name;
 *   usr/include/sys/sysctl.h:795-799   __sized_by / __counted_by
 *   usr/include/net/if.h:75,367        __counted_by
 *   usr/include/kern/kcdata.h:1468      __sized_by
 * so a bare include of sys/socket.h could not compile:
 *   sys/socket.h:561:30: error: a parameter list without types is only
 *                             allowed in a function definition
 *   sys/socket.h:561:42: error: expected ; at end of declaration list
 * Two command lines were masking this. Both paper over the gap rather
 * than close it, and neither reaches a consumer outside them:
 *   BSD/share/mk/bsd.sys.mk:539  -D__sized_by(x)= -- function-like, so it
 *       does not even match the __sized_by(msg_namelen) use site
 *   BSD/bin/sh/build-ravynos.sh:71  PTRATTR, added by a worker who
 *       correctly refused to fix it at source and worked around it here
 *
 * The block is the one from the sys/cdefs.h of the host SDK, verbatim:
 * every macro in it is defined to nothing or to an identity cast precisely
 * because it must not change the ABI. __indexable and __bidi_indexable
 * are deliberately absent -- they are an ABI break, and omitting them
 * leaves the diagnostic in place instead of silently degrading it.
 * __ASSUME_PTR_ABI_SINGLE_BEGIN/END and __unsafe_forge_single are included
 * because the headers in that same SDK use them (os/base.h, sys/queue.h and
 * friends); dropping them would just move the same failure one header on.
 *
 * Guarded per-macro with #ifndef, exactly as the two macros above are, so
 * this is idempotent and cannot affect a tree that already has them -- for
 * instance the System.framework PrivateHeaders copy, which is a newer xnu
 * generation and already carries the block at its own :1126-1135.
 */
#ifndef __has_ptrcheck
#define __has_ptrcheck 0
#define __single
#define __unsafe_indexable
#define __counted_by(N)
#define __counted_by_or_null(N)
#define __sized_by(N)
#define __sized_by_or_null(N)
#define __ended_by(E)
#define __terminated_by(T)
#define __null_terminated
/* __unsafe_forge intrinsics are ordinary C casts. */
#define __unsafe_forge_bidi_indexable(T, P, S) ((T)(P))
#define __unsafe_forge_single(T, P) ((T)(P))
#define __unsafe_forge_terminated_by(T, P, E) ((T)(P))
#define __unsafe_forge_null_terminated(T, P) ((T)(P))
#define __terminated_by_to_indexable(P) (P)
#define __unsafe_terminated_by_to_indexable(P) (P)
#define __null_terminated_to_indexable(P) (P)
#define __unsafe_null_terminated_to_indexable(P) (P)
#define __unsafe_terminated_by_from_indexable(T, P, ...) (P)
#define __unsafe_null_terminated_from_indexable(P, ...) (P)
/* No pointer checking, so decay is already normal and write-once is moot. */
#define __array_decay_dicards_count_in_parameters
#define __unsafe_late_const
#define __ptrcheck_unavailable
#define __ptrcheck_unavailable_r(REPLACEMENT)
#define __ptrcheck_abi_assume_single()
#define __ptrcheck_abi_assume_unsafe_indexable()
#define __ASSUME_PTR_ABI_SINGLE_BEGIN       __ptrcheck_abi_assume_single()
#define __ASSUME_PTR_ABI_SINGLE_END         __ptrcheck_abi_assume_unsafe_indexable()
#if __has_ptrcheck
#define __header_indexable                  __indexable
#define __header_bidi_indexable             __bidi_indexable
#else
#define __header_indexable
#define __header_bidi_indexable
#endif
#endif /* !__has_ptrcheck */
/* --- END ravynOS cdefs shim --- */
'
sync_cdefs() {
    # The SDK headers arrive mode 0444, as everything under a CommandLineTools
    # or platform SDK does. ">> file" needs write permission on the file
    # itself and fails with "Permission denied" -- and it kept failing, once
    # per stage, with the error buried at the top of each stage log where
    # nobody reads it. The System.framework copy is the one that matters:
    # <sys/kdebug_private.h> lives beside it and includes <sys/cdefs.h>, and a
    # framework's PrivateHeaders precedes usr/include on the search path, so
    # the copy this function DOES patch is never the one that gets read.
    # That is why libdispatch died on
    #   kdebug_private.h:476:18: error: expected ';' at end of declaration list
    # while usr/include/sys/cdefs.h sat next to it already carrying the shim.
    #
    # Build the new content beside the file and cp -f it into place. cp -f
    # unlinks a destination it cannot open for writing, and the directory is
    # writable, so this works where the append did not. Every other SDK
    # refresh in this script already uses cp -f for the same reason.
    local f tmp patched=0 failed=0
    tmp="$(mktemp "${TMPDIR:-/tmp}/cdefs.XXXXXX")" || return 1
    printf '%s' "$CDEFS_TAIL" > "$tmp"
    for d in "$SDK/usr/include/sys" \
             "$SDK/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/sys"; do
        f="$d/cdefs.h"
        [ -f "$f" ] || continue
        # Strip any previous shim block, then append the current one, so a
        # header refreshed here gains macros added since it was last patched.
        # The old guard was a single grep for the marker and `continue`d, so
        # once a tree was patched it was NEVER patched again -- which is how
        # four macros added later were silently not applied and libdispatch,
        # libxpc, libsystem_asl and libsystem_dnssd kept failing with the very
        # errors the shim was extended to fix.
        if sed -e '/^\/\* --- BEGIN ravynOS cdefs shim/,/^\/\* --- END ravynOS cdefs shim/d' \
               "$f" > "$tmp.stripped" 2>/dev/null \
           && cat "$tmp.stripped" "$tmp" > "$tmp.new" 2>/dev/null \
           && cmp -s "$f" "$tmp.new"; then
            continue                      # already identical, nothing to do
        elif cat "$tmp.stripped" "$tmp" > "$tmp.new" 2>/dev/null \
             && cp -f "$tmp.new" "$f" 2>/dev/null; then
            patched=$((patched+1))
            echo "note: patched $(basename "$d")/cdefs.h with the build-libraries.sh shim" >&2
        else
            failed=$((failed+1))
            echo "ERROR: could not patch $f -- headers will fail to compile." >&2
            echo "ERROR:   (mode $(stat -f '%Sp' "$f" 2>/dev/null), dir writable: $([ -w "$d" ] && echo yes || echo no))" >&2
        fi
    done
    rm -f "$tmp" "$tmp.new" "$tmp.stripped"
    # Never fail the build over this, but do not let it pass unnoticed either.
    [ "$failed" -eq 0 ] || echo "WARNING: $failed cdefs.h shim(s) failed" >&2
    return 0
}
sync_cdefs

# mach_msg_aux_header_t / LIBSYSCALL_MSGV_AUX_MAX_SIZE live in this xnu's
# osfmk/mach/message.h but in no header the SDK ships, and
# Kernel/xnu/libsyscall uses both unconditionally. Detect that once here and
# let isysroot-cc force-include the shim -- a whole-tree mach swap is not an
# option, see the note above sync_mach.
MACH_COMPAT="$HERE/ravynos-mach-compat.h"
if [ -f "$MACH_COMPAT" ] && \
   ! grep -q mach_msg_aux_header_t "$SDK/usr/include/mach/message.h" 2>/dev/null; then
    export RAVYN_COMPAT_MAC_AUX="$MACH_COMPAT"
    echo "note: mach/message.h lacks mach_msg_aux_header_t; force-including $(basename "$MACH_COMPAT")" >&2
else
    unset RAVYN_COMPAT_MAC_AUX
fi


# Pre-generate mig output for any .defs in the component being built.
#
# The per-project Makefiles declare the mig rules, but the static-archive
# targets do not depend on them: libsystem_asl's .a lists asl_ipcUser.c in
# SRCS but only the *dylib* target names asl_ipcUser.c, so building the
# archive compiles asl.c against a header that was never generated:
#   asl.c:60:10: fatal error: 'asl_ipc.h' file not found
# Generate here so the static targets are self-sufficient. Existing outputs are
# left alone.
DEFS_ROOTS=""
for r in "$ROOT/Kernel/xnu/BUILD/dst/usr/include" \
         "$ROOT/Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk" \
         "$ROOT/Kernel/xnu/osfmk/mach" \
         "$ROOT/Kernel/xnu/libsyscall/mach"; do
    [ -d "$r" ] && DEFS_ROOTS="$DEFS_ROOTS -I$r"
done

generate_mig() {
    dir="$1"
    [ -n "${MIG:-}" ] && [ -x "${MIG}" ] || return 0
    for defs in "$dir"/*.defs; do
        [ -f "$defs" ] || continue
        base="${defs%.defs}"
        b="${base##*/}"
        [ -f "$base.h" ] && continue
        # Some components also need the server-side header (-sheader), e.g.
        # liblaunch's helper.defs -> helper.h + helperServer.h, and libvproc.c
        # includes both:
        #   libvproc.c:61: #include "helper.h"
        #   libvproc.c:62: #include "helperServer.h"
        if [ "$b" = helper ]; then
            shhdr="-sheader ${b}Server.h"
        else
            shhdr=""
        fi
        # shellcheck disable=SC2086
        ( cd "$dir" && "$MIG" -arch "$CpuArch" -cc "$MIGCC" $DEFS_ROOTS \
              -header "$b.h" $shhdr "$b.defs" ) >/dev/null 2>&1 \
            && echo "  mig: generated $b.h / ${b}User.c / ${b}Server.c" >&2
    done
    return 0
}

# --static-pthread-only: build just the static-variant pthread archive.
# The path is spelled out rather than reusing DIRS because the target is
# a SUBDIR of libsystem_pthread, not a top-level Libraries/ entry, and
# because the top-level Libsystem target would drag in libsystem_trace.
if [ "${1:-}" = "--static-pthread-only" ]; then
    echo "=== building Libraries/Libsystem/libsystem_pthread/static ==="
    ( cd "$ROOT/Libraries/Libsystem/libsystem_pthread/static" && \
      "$BMAKE" -m "$MKMODULES" "${BMAKE_TARGET:-all}" )
    exit $?
fi

# --pwdgrp-only: build just Libraries/Libsystem/libsystem_pwdgrp, which
# produces both libsystem_pwdgrp.dylib and libsystem_pwdgrp_static.a.
#
# Same reasoning as --static-pthread-only above: the top-level Libsystem
# target cannot be used to build it, because Libraries/Libsystem/Makefile
# generates config.${CpuArch}.normal.h through xcodescripts/linker_arguments.sh,
# and that script refuses to run while any name in `requiredlibs' is missing
# from the SDK's usr/lib/system. `system_pwdgrp' is in requiredlibs (it has to
# be, or the generated re-export list omits the passwd database and the
# dynamic linker keeps serving getpwnam from libsystem_info), so on a tree
# where libsystem_pwdgrp.dylib has not been installed yet the Libsystem build
# aborts before it ever descends into the SUBDIR that would install it.
# Building the component first breaks that cycle for this component, exactly
# as --static-pthread-only does for pthread.
if [ "${1:-}" = "--pwdgrp-only" ]; then
    echo "=== building Libraries/Libsystem/libsystem_pwdgrp ==="
    ( cd "$ROOT/Libraries/Libsystem/libsystem_pwdgrp" && \
      "$BMAKE" -m "$MKMODULES" "${BMAKE_TARGET:-all}" )
    exit $?
fi

# --top <target ...>: drive the repository's top-level Makefile with this
# environment.
#
# Why: the top-level Makefile is what establishes the object-directory layout
# (SRCTOP/OBJTOP/MAKEOBJDIRPREFIX are computed there and exported to every
# SUBDIR), and it is the only place the per-component bmake invocations used
# elsewhere in this script differ from a real build. Running components
# directly (as the plain loop and --frameworks do) leaves .OBJDIR at the source
# directory, so objects are written beside the sources; going through the
# top-level Makefile puts them under $BUILD/Users/... as intended.
#
# TOOLS and TOOLCHAIN are forced on the command line: the top-level Makefile
# assigns them unconditionally, which would otherwise replace the wrapper's
# $BUILD/Tools/bin (holding llvm-libtool-darwin/llvm-objcopy/xcrun) and the
# synthetic toolchain this script builds.
if [ "${1:-}" = "--top" ]; then
    shift
    cd "$ROOT" && "$BMAKE" -m "$MKMODULES" -f Makefile \
        TOOLS="$TOOLS" TOOLCHAIN="$TOOLCHAIN" MK_TOOLCHAIN=no "$@"
    exit $?
fi

# --frameworks [subdir ...]: build the Frameworks/ tree and the CoreServices
# applications with the same environment the Libraries/ build uses.
#
# Why this mode exists: the Frameworks/ and CoreServices/ Makefiles assume the
# environment this script establishes (CC/CXX wrappers, TOOLCHAIN, TOOLS,
# RAVYN_SDKROOT, EXTRA_DEFINES, ...), and the top-level Makefile's SUBDIR
# recursion does not go through it. Driving bmake from here keeps one
# environment definition for every component built on this host.
#
# Subdirs may be given bare (resolved under Frameworks/) or as a path relative
# to the repository root, so the CoreServices applications can be named too:
#   build-libraries.sh --frameworks CoreServices
#   build-libraries.sh --frameworks CoreServices/WindowServer
if [ "${1:-}" = "--frameworks" ]; then
    shift
    DIRS=("$@")
    [ ${#DIRS[@]} -eq 0 ] && DIRS=(CoreFoundation Foundation CoreServices \
        Onyx2D CoreGraphics AppKit CoreText)
    rc=0
    # ---------------------------------------------------------------------
    # Framework staging paths.
    #
    # The Makefiles in Frameworks/ and CoreServices/ spell their framework
    # references as ${OBJTOP}/Frameworks/<F>/<F>.framework and their header
    # search paths as ${OBJTOP}/Frameworks/Foundation/Headers. With the
    # OBJTOP this harness sets ($BUILD) both resolve under $BUILD/Frameworks,
    # but MAKEOBJDIR (auto.obj.mk) places every component at
    # MAKEOBJDIRPREFIX + the absolute source path, i.e. $BUILD$ROOT/Frameworks.
    # Without the bridge, clang finds no ravynOS framework under
    # $BUILD/Frameworks/... and silently falls back to the *host* macOS SDK
    # framework of the same name, mixing Apple headers into the build (seen
    # as AppKit/NSColor.h resolving to
    # /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/...).
    #
    # Two things are bridged, and only structure is created:
    #   * $BUILD/Frameworks -> the real objdir Frameworks/ tree, so every
    #     -L${OBJTOP}/Frameworks/<F>/<F>.framework resolves.
    #   * ${OBJTOP}/Frameworks/Foundation/Headers -> the source header tree,
    #     which is the layout <Foundation/NSObject.h> expects and which no
    #     rule in the build creates (upstream only resolves this because its
    #     in-tree build has OBJTOP == SRCTOP).
    # Idempotent: existing paths are left alone.
    [ -e "$BUILD/Frameworks" ] || \
        ln -sfn "$BUILD$ROOT/Frameworks" "$BUILD/Frameworks"
    [ -e "$BUILD$ROOT/Frameworks/Foundation/Headers" ] || \
        ln -sfn "$ROOT/Frameworks/Foundation/Headers" \
                "$BUILD$ROOT/Frameworks/Foundation/Headers"
    #
    #   * ${OBJTOP}/Frameworks/AppKit/Headers/AppKit/*.h -- AppKit's public
    #     headers are scattered across its subdirectories (NSColor.h lives in
    #     NSColor.subproj/), so <AppKit/NSColor.h> resolves only through this
    #     flat tree. The repository's own Frameworks/setup rule is what builds
    #     it, and that rule is broken: it first calls a `marshalheaders` target
    #     that Foundation/Makefile does not define, so it aborts before the
    #     copy. Stage the same tree here, from headers that already exist.
    #     Without it clang silently takes <AppKit/NSColor.h> from the host
    #     macOS SDK and then mixes host and ravynOS AppKit headers.
    APPKIT_HDRS="$BUILD$ROOT/Frameworks/AppKit/Headers/AppKit"
    if [ ! -d "$APPKIT_HDRS" ]; then
        mkdir -p "$APPKIT_HDRS"
        find "$ROOT/Frameworks/AppKit" -name '*.h' \
            -exec cp -f {} "$APPKIT_HDRS/" \;
    fi
    for d in "${DIRS[@]}"; do
        if [ -d "$ROOT/Frameworks/$d" ]; then
            base="$ROOT/Frameworks/$d"
        elif [ -d "$ROOT/$d" ]; then
            base="$ROOT/$d"
        else
            echo "no such framework/app dir: $d" >&2
            rc=1
            continue
        fi
        echo "=== building ${base#$ROOT/} ==="
        # MAKEOBJDIR in the *environment* is what auto.obj.mk honours: bmake
        # picks .OBJDIR before the Makefile is read, so MAKEOBJDIRPREFIX and
        # command-line assignments are too late (measured: both left .OBJDIR at
        # the source directory). The path mirrors the top-level layout, which
        # is MAKEOBJDIRPREFIX + the absolute source path. OBJTOP is what the
        # framework Makefiles spell their -L paths against.
        ( cd "$base" && MAKEOBJDIR="$BUILD$base" OBJTOP="$BUILD" MK_AUTO_OBJ=yes \
          "$BMAKE" -m "$MKMODULES" "${BMAKE_TARGET:-all}" ) || rc=1
    done
    exit $rc
fi

DIRS=("$@")
[ ${#DIRS[@]} -eq 0 ] && DIRS=(MiscLibs libfirehose_kernel objc4 dyld Libsystem)

rc=0
for d in "${DIRS[@]}"; do
    [ -d "$ROOT/Libraries/$d" ] || { echo "no such subdir: $d" >&2; rc=1; continue; }
    generate_mig "$ROOT/Libraries/$d"
    echo "=== building Libraries/$d ==="
    ( cd "$ROOT/Libraries/$d" && "$BMAKE" -m "$MKMODULES" "${BMAKE_TARGET:-all}" ) || rc=1
done
exit $rc
