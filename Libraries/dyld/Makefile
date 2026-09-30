MK_WERROR = no

# SDK_SOURCE_DIR was used by the -include/-I lines below but DEFINED NOWHERE in
# this tree, so every use expanded to a root-absolute /usr/include/... and the
# -include forms failed with
#   <built-in>:1:10: fatal error: '/usr/include/AvailabilityInternal.h' file not found
# The headers do exist under the build SDK's usr/include, so this is a plain
# undefined-variable defect, not a header-shadowing or ordering problem.
SDK_SOURCE_DIR = ${RAVYN_SDKROOT}
SUBDIR =

LIB = dyld
SRCS = ./src/start_glue.s \
	./src/glue.c \
	./dyld3/Tracing.cpp \
	./dyld3/Closure.cpp \
	./src/dyldLock.cpp \
	./src/dyld_stub_binder.s \
	./dyld3/ClosureFileSystemPhysical.cpp \
	./src/dyldLibSystemGlue.c \
	./src/dyldAPIsInLibSystem.cpp \
	./src/threadLocalVariables.c \
	./src/threadLocalHelpers.s \
	./src/dyld_process_info.cpp \
	./src/dyld_process_info_notify.cpp \
	./dyld3/Diagnostics.cpp \
	./dyld3/shared-cache/DyldSharedCache.cpp \
	./dyld3/AllImages.cpp \
	./dyld3/APIs.cpp \
	./dyld3/APIs_macOS.cpp \
	./dyld3/Logging.cpp \
	./dyld3/Loading.cpp \
	./dyld3/MachOFile.cpp \
	./dyld3/MachOLoaded.cpp \
	./dyld3/MachOAnalyzer.cpp \
	./dyld3/PathOverrides.cpp \
	./dyld3/ClosureBuilder.cpp \
	./dyld3/ClosureWriter.cpp \
	./dyld3/libdyldEntryVector.cpp

	# The openbsm root IS on the include path, because
	# Libraries/Libsystem/liblaunch/vproc_priv.h:31 includes <sys/bsm/audit.h>
	# and that resolves to Libraries/openbsm/sys/bsm/audit.h and nowhere else.
	#
	# It was absent between a6e2c35015 and now, because the same root also
	# exposes a 19-byte ASCII DATA FILE named `version` (entire content:
	# OPENBSM_1_2_alpha5). libc++ includes <version> for its C++20 feature-test
	# macros - bitset, ranges, ostream, strstream, forward_list all do - and the
	# data file WINS that include, giving
	#   "unknown type name 'OPENBSM_1_2_alpha5'"
	# Removing the whole -I cured that and cost this component every sys/bsm
	# header in the same stroke: one directory, one -I, two unrelated needs.
	#   (The -isystem-beats--I hypothesis was tested and REFUTED: all these
	#    paths arrive as plain -I. What remains unexplained is the ordering
	#    itself; clang's only hint is -Wnonportable-include-path, "specified
	#    path differs in case from file name on disk". Excluding the data file
	#    from the search path is the fix regardless of that mechanism.)
	#
	# The exclusion is done by isysroot-cc, which mirrors this tree into a
	# symlink overlay and drops `version` alone -- the same treatment
	# Availability* already gets in the EXTERNAL_HEADERS overlay. This -I is
	# rewritten to that overlay on its way to the compiler; do not add a second
	# -I for the openbsm subdirectories to work around it.

	# Ask isysroot-cc to force-include libc++'s C-header shim family
	# (c++/v1/<name>.h) for this component's C++ TUs. See the long comment at
	# that block for the mechanism; the short version:
	#
	# libc++'s c++/v1/<name>.h forwards to the C header and only THEN defines
	# _LIBCPP_<NAME>_H. Its first branch declines to define that guard when the
	# C header is already open:
	#     #if defined(__need_ptrdiff_t) || defined(__need_size_t) || ...
	#       #include_next <stddef.h>
	#     #elif !defined(_LIBCPP_STDDEF_H)
	# Some earlier header in our include chain (sys/param.h, the machine/*
	# headers) opens the C <stddef.h> first, so the guard is never set, and
	# cstddef's own `#include <stddef.h>` is then a no-op under the C header's
	# guard. cstddef then fires:
	#     cstddef:46:5: error: <cstddef> tried including <stddef.h> but didn't
	#         find libc++'s <stddef.h> header.
	# Reordering cannot fix this (measured: 20 -> 7 errors, cstddef:46 still
	# fires) because the failure is the guard collision, not the search order.
	# The shims have to be force-included ahead of everything.
	#
	# WHY IT IS PER-COMPONENT AND NOT GLOBAL. Measured on real builds of both
	# components, comparing error SIGNATURES rather than error counts:
	#     dyld         with the family: 16 objects   without:  8 objects
	#     libdispatch  with the family: 19 libc++ errors   without: 0 libc++
	#                  errors (it then hits a different, PRE-EXISTING stdint.h
	#                  fault that predates any of this work)
	# No subset of the family separates them -- stddef.h is required by dyld
	# and harmful to libdispatch by itself. libdispatch needs the opposite
	# setting, so a global rule cannot serve both and the component asks by
	# name instead. Default is off: any component that has not opted in emits
	# nothing.
COMMONFLAGS = -w --target=${CpuArch}-apple-darwin -dylib \
	-mmacos-version-min=${MACOS_VERSION_MIN} \
	--sysroot=${RAVYN_SDKROOT} -DPRIVATE  \
	-DBUILDING_LIBDYLD -DWITHOUT_SANDBOX -DBROKEN_VECTOR_BASE \
	-D__USING_SJLJ_EXCEPTIONS__=0 -D_USE_EXTENDED_LOCALES_ \
	-D__DARWIN_C_LEVEL=__DARWIN_C_FULL -DTARGET_OS_BRIDGE=0 \
	-DSUPPORT_ZERO_COST_EXCEPTIONS -DSUPPORT_ACCELERATE_TABLES \
	-DRAVYN_LIBCXX_SHIM_FORCE_INCLUDE=1 \
	-D__MAC_OS_X_VERSION_MIN_REQUIRED=101300 \
	-Wno-nullability-completeness -Wno-incompatible-sysroot \
	-Wno-availability -I${SDK_SOURCE_DIR}/usr/include/c++/v1 \
	-I${.CURDIR}/src -I${.CURDIR}/dyld3/shared-cache \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd -I${.CURDIR}/dyld3 \
	-I${.CURDIR}/../Libsystem/libsystem_c/include \
	-I${.CURDIR}/../Libsystem/libsystem_c/locale \
	-I${.CURDIR}/../Libsystem/libsystem_c/locale/FreeBSD \
	-I${.CURDIR}/../Libsystem/libsystem_c/stdtime \
	-I${.CURDIR}/../Libsystem/libsystem_c/stdtime/FreeBSD \
	-I${.CURDIR}/../Libsystem/private \
	-I${.CURDIR}/../Libsystem/liblaunch \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/wrappers/libproc \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS \
	-I${ROOT_SOURCE_DIR}/Libraries/openbsm

C_INCS= \
	-include${SDK_SOURCE_DIR}/usr/include/AvailabilityInternal.h \
	-include${SDK_SOURCE_DIR}/usr/include/AvailabilityVersions.h \
	-include${SDK_SOURCE_DIR}/usr/include/AvailabilityMacros.h \
	-include${SDK_SOURCE_DIR}/usr/include/Availability.h \
	-include${SDK_SOURCE_DIR}/usr/include/mach.h \
	-include${ROOT_SOURCE_DIR}/Libraries/Libsystem/libsystem_c/include/xlocale/_stdlib.h

CFLAGS.Loading.o = -fvisibility=hidden -fno-exceptions
CFLAGS.MachOFile.o = -fno-exceptions
CFLAGS.MachOLoaded.o = -fno-exceptions
CFLAGS.MachOAnalyzer.o = -fno-exceptions
CFLAGS.Diagnostics.o = -fno-exceptions
CFLAGS.PathOverrides.o = -fno-exceptions
CFLAGS.Closure.o = -fno-exceptions
CFLAGS.ClosureWriter.o = -fno-exceptions
CFLAGS.ClosureBuilder.o = -fno-exceptions
CFLAGS.ClosureFileSystemPhysical.o = -fno-exceptions
CFLAGS.Tracing.o = -fno-exceptions

# The remaining 7 C++ TUs get -fno-exceptions for the same reason, and the
# reason is a measured MECHANISM rather than a correlation.
#
# A TU built WITH exceptions emits an undefined reference to
# std::terminate (__ZSt9terminatev). libc++'s exception.o is the archive
# member that defines it, so ld pulls that member in -- and exception.o in
# turn requires the two __cxxabiv1 typeinfo vtables, which drags in
# typeinfo.o as well. typeinfo.o supplies dyld NOTHING directly; it is in the
# DRAG chain, not the COLLISION chain. Getting that distinction wrong points
# at the wrong member.
#
# Those pulled members then collide with glue.c's four deliberate handlers
# (_ZSt9terminatev, _ZSt10unexpectedv, __cxxabiv1::__terminate,
# __cxxabiv1::__unexpected, ...). glue.c is CORRECT and stays: a bootstrap
# linker must not reach libc++'s exception runtime, because it aborts through
# a runtime that does not exist yet when dyld runs. The fix is to remove the
# DEMAND, not to delete the handlers and not to narrow the archive.
#
# Measured on the real emitted argv for dyld3/APIs.cpp (captured from
# RAVYN_CC_TRACE, replayed verbatim):
#     baseline                     __ZSt9terminatev demanded: 1
#     same argv + -fno-exceptions  __ZSt9terminatev demanded: 0
#                                  libc++ C++ undefineds left: 0
# And the correlation is exact in both directions: these 7 were the only TUs
# demanding std::terminate, and all 11 TUs already carrying -fno-exceptions
# were checked individually and demand nothing from libc++.
CFLAGS.APIs.o = -fno-exceptions
CFLAGS.APIs_macOS.o = -fno-exceptions
CFLAGS.AllImages.o = -fno-exceptions
CFLAGS.dyldAPIsInLibSystem.o = -fno-exceptions
CFLAGS.dyldLock.o = -fno-exceptions
CFLAGS.dyld_process_info.o = -fno-exceptions
CFLAGS.dyld_process_info_notify.o = -fno-exceptions
# DyldSharedCache.o was the LAST TU still demanding the C++ exception runtime,
# and it is the sole source of TWO of libdyld.dylib's six remaining unprovided
# symbols: __Unwind_Resume and ___gxx_personality_v0. Both were measured by
# scanning the undefined sets of all 28 members of libdyld.a:
#     DyldSharedCache.o -> _Unwind_Resume, __gxx_personality_v0
#     APIs.o / AllImages.o / ClosureFileSystemPhysical.o -> the two typeinfo
#         vtables ONLY (they already carry -fno-exceptions and still ask)
# -fno-exceptions here is pure demand-removal, the same fix as the 16 TUs
# above, and it is safe without qualification: DyldSharedCache.cpp contains no
# try/catch/throw/__try/__except at all (grepped, zero matches), so there is no
# exception handling for the flag to disable.
#
# This is DELIBERATELY not done with a link-line change. -Wl,-upward-lunwind
# would close __Unwind_Resume and nothing else: ___gxx_personality_v0 is
# defined by NO dylib in the SDK, and libunwind.dylib carries 5 unprovided
# symbols of its own (including that same personality routine). Removing the
# demand closes 2 of 6 and adds no edge to the load graph; adding libunwind
# closes 1 of 6 and adds one.
CFLAGS.DyldSharedCache.o = -fno-exceptions
CFLAGS.glue.o = -fno-builtin ${C_INCS}
CFLAGS.ImageLoaderMachOCompressed.o = -O3

ACFLAGS = ${COMMONFLAGS}
CFLAGS = ${COMMONFLAGS} ${CFLAGS.${.TARGET:T}}
CXXFLAGS = ${COMMONFLAGS} -std=c++20 ${C_INCS} ${CFLAGS.${.TARGET:T}}
# -dylib below is REQUIRED, not cosmetic. isysroot-cc keys its whole
# link-hygiene branch on seeing -dylib / -dynamiclib, and with -shared alone
# that branch never fires. The link then reaches ld64 with bsd.sys.mk:541's
# `-lSystem -Wl,-undefined,dynamic_lookup` still attached and `-umbrella
# System` unstripped, and ld64 refuses:
#   ld: Shared cache eligible dylibs cannot use '-undefined dynamic_lookup'
#       or '-U' to find symbols. Remove these options or opt out of the shared
#       cache using ... '-not_for_dyld_shared_cache'
# With -dylib the existing, already-proven branch fires and supplies exactly
# what ld64 asks for. Verified by argv capture on the real link line, both ways:
#   without -dylib: -lSystem PRESENT, -umbrella PRESENT, -nodefaultlibs absent,
#                   -not_for_dyld_shared_cache absent
#   with    -dylib: -lSystem absent,  -umbrella absent,  -nodefaultlibs
#                   PRESENT, -not_for_dyld_shared_cache PRESENT
# Do not inline those flags here instead. The wrapper already owns them.
#
# NB this comment is ABOVE the assignment on purpose. A comment inside the
# backslash continuation silently ends the variable — the same defect as
# 37f7cd727f, which I reproduced here while fixing an unrelated line and caught
# with `bmake -V LDFLAGS` (6 tokens instead of ~60). Check the token count, not
# the file, when you add a flag here.
# -Wl,-upward-lc++ WAS HERE AND HAS BEEN REMOVED. It is unsatisfiable in this
# SDK, and it is the sole cause of the frontier
#   ld: library 'c++' not found
# `-upward-X` means "re-export libX from the dylib above me", so it requires
# libX to EXIST AS A DYLIB. Measured across the SDK:
#   libsystem_malloc / pthread / platform / kernel / c, libxpc, libdispatch,
#   libcompiler_rt   -> all present as dylibs in usr/lib/system/  (fine)
#   libc++            -> usr/lib/libc++.a ONLY. No .dylib, no .tbd.  (fatal)
# SECOND LINK DEFECT, AND THE ONE THAT ACTUALLY BLOCKED THE LINK. There is no
# -lc++ here, and that is correct. dyld uses libc++ HEADERS at compile time and
# does not link libc++ at run time. Measured: libdyld.a has 593 undefined
# symbols and libc++.a supplies ZERO of them, so libc++ was never needed.
# Adding -lc++ pulled four members in (exception.o, new.o, typeinfo.o,
# verbose_abort.o) and collided with glue.c's deliberate handlers:
#   ld: 4 duplicate symbols   std::terminate, std::get_terminate,
#                              std::unexpected, std::get_unexpected
# glue.c defines those four on purpose ("std::terminate called by C++
# unwinding code", each calling dyld::halt()) because a bootstrap linker must
# not abort through a C++ runtime that does not exist yet. Most dyld TUs also
# build -fno-exceptions, which is the same intent.
#
# A/B on the real link line, one flag varied:
#   with    -lc++ -lc++abi   4 members pulled, 4 duplicates, rc=1
#   without -lc++ -lc++abi   0 members pulled,               rc=0, LINKS
# and produces a real 1,013,064-byte Mach-O dylib, install name
# /usr/lib/system/libdyld.dylib, current version 732.2.0, with ten `upward`
# reexport dependencies on the real libsystem_* dylibs.
#
# Isolated repro for the first defect, synthetic dylib link in /tmp:
#   core flags + -Wl,-upward-lc++      -> ld: library 'c++' not found
#   core flags, -upward-lc++ removed   -> ld: dynamic executables or dylibs
#                                         must link with libSystem.dylib
# -Wl,-fixup_chains IS LOAD-BEARING, NOT COSMETIC. Without it this link emits
# the LEGACY `LC_DYLD_INFO_ONLY` and NO `LC_DYLD_EXPORTS_TRIE` at all:
#     baseline                  TRIE=0  CHAINED=0  LC_DYLD_INFO_ONLY=1  nm=205
#     with -Wl,-fixup_chains   TRIE=1  CHAINED=1  LC_DYLD_INFO_ONLY=0  nm=205
# Same 205 exports either way.
#
# WHAT IS MEASURED: the baseline emitted the LEGACY `LC_DYLD_INFO_ONLY` with
# no `LC_DYLD_EXPORTS_TRIE`; with the flag it emits `LC_DYLD_EXPORTS_TRIE` and
# `LC_DYLD_CHAINED_FIXUPS`. Same 205 exports. That is the whole observation.
#
# WHAT IS INFERRED, and is weaker: that a library with no export trie cannot be
# loaded. That is APPLE's modern dyld's behaviour, applied to a ravynOS dyld
# that has never booted once. Nothing here demonstrates it, and
# `stage_dynamic_libs.sh` has put a trie-less `libsystem_c` into the image and
# moved the boot fault, which is evidence AGAINST treating it as settled. Keep
# the flag — the modern encoding is the right target and this is the direction
# of travel — but do not cite "unloadable" as a measurement.
#
# The gate in 6.1a is still right, and for a reason that does not need the
# inference: `nm` counts symbols and does not care which structure they live
# in, so it passes either way. Checking that the structure dyld is documented
# to read is present costs one `otool -l` and catches an encoding regression
# regardless of what any particular dyld does with it.
#
# Found by `plan` checking dyld_info across the staged dylibs and finding this
# one had an empty trie too, then by measuring the flag here. Do not remove it
# on the grounds that the link succeeds.

# WHY THE -Wl,-upward-* FLAGS ARE GONE, AND WHY THIS IS STILL NOT A DYLINKER
#
# Linking this as an ordinary dylib produces an image the kernel refuses to use
# as a dynamic linker, and the refusal is only visible at execve:
#
#   filetype DYLIB  ->  filetype DYLINKER
#   LC_ID_DYLIB    ->  LC_ID_DYLINKER
#   (no entry)     ->  LC_UNIXTHREAD, via -Wl,-e,_start (src/start_glue.s)
#   9 x LC_LOAD_UPWARD_DYLIB -> none
#
# Symptom: bsd/kern/kern_exec.c:1359 load_machfile() returns LOAD_BADMACHO,
# which becomes OS_REASON_EXEC / EXEC_EXIT_REASON_BAD_MACHO
# (bsd/sys/reason.h:276, value 1). Because that SIGKILLs initproc,
# bsd/kern/kern_sig.c:2117 turns it into the boot-ending panic
#
#   panic(cpu 0 ...): unexpected SIGKILL of launchd with reason --
#   namespace 9 code 0x1 description none
#
# The upward links were a real error on their own and are now removed: dyld is
# the BOTTOM of the dependency graph -- it loads before everything it pulls in
# -- so nothing can be upward of it, and LC_LOAD_UPWARD_DYLIB on a dyld is a
# contradiction. Removing them is correct on its own terms.
#
# WHAT IS STILL MISSING, and why -dylinker is not simply switched on:
# the image must become MH_DYLINKER with an LC_UNIXTHREAD entry point, or the
# kernel keeps rejecting it with the panic above. Switching -dylib to -dylinker
# (plus -Wl,-e,_start) was tried and does NOT link:
#
#   ld: library 'system_malloc' not found
#
# ...even though -L${RAVYN_SDKROOT}/usr/lib/system is passed and
# libsystem_malloc.dylib is present there. That is ld64 behaviour, not a
# mistake in the -L: an MH_DYLINKER image does not resolve its dependencies
# from -L search paths the way a dylib does. Verified by linking one trivial
# object both ways with identical flags -- with -dylib the link reaches symbol
# resolution ("symbol(s) not found"), with -dylinker it never finds the library
# at all. So the dependency search domain for a dylinker image has to be worked
# out before this flag can be turned on; it is not a one-line change.
#
# isysroot-cc already recognises -dylinker (link-hygiene case list), so the
# -umbrella System / -lSystem stripping would still fire when this is finished.
#
LDFLAGS = --target=${CpuArch}-apple-darwin --sysroot=${RAVYN_SDKROOT} \
	-L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib \
	-Wl,-no_inits -Wl,-no_warn_unused_dylibs -fuse-ld=${LD} -shared -dylib \
	-Wl,-fixup_chains \
	-umbrella System "-Wl,-unexported_symbol,__ZNSt3*" \
	-mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wl,-install_name,/usr/lib/system/libdyld.dylib \
	-Wl,-current_version,732.2 \
	-lsystem_malloc -lsystem_pthread -lsystem_platform -lsystem_kernel

all: lib${LIB}.dylib

mkdirs: .PHONY
	mkdir -p ${.OBJDIR}/src ${.OBJDIR}/dyld3/shared-cache

lib${LIB}.dylib: mkdirs lib${LIB}.a
	${CC} -o ${.TARGET} -Wl,-force_load,lib${LIB}.a ${LDFLAGS}
	mkdir -p ${RAVYN_SDKROOT}/usr/lib/system
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/system/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/system/
	cp -f ${.OBJDIR}/lib${LIB}.a ${RAVYN_SDKROOT}/usr/lib/system/
	cp -f ${.OBJDIR}/lib${LIB}.a ${SYSROOT_DIR}/usr/lib/system/

libdyld: ${.OBJDIR}/lib${LIB}.dylib

SUBDIR = dyld libdsc libslc_builder chroot_util #dyld_closure_util dyldinfo \
        #dsc_extractor dyld_shared_cache_util \
        #update_dyld_shared_cache_root_mode_tool
        #update_dyld_shared_cache_tool -- needs private Bom and dscsyms fmwks
        #dyld_usage -- needs private ktrace.framework

.include <bsd.subdir.mk>
.include <bsd.lib.mk>

