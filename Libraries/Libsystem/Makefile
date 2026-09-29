MK_WERROR = no

LIB = System.B
SRCS = init.c CompatibilityHacks.c stubs.c

CFLAGS = --sysroot=${RAVYN_SDKROOT} -w \
	-mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wno-implicit-function-declaration \
	-Wno-int-conversion -Wno-implicit-int -fno-common \
	-I${.CURDIR}/libsystem_c/darwin \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS \
	-I${RAVYN_SDKROOT}/usr/include/pthread -I${.CURDIR}/private \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/mach \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/wrappers \
	-I${.CURDIR}/libsystem_c/include \
	-I${ROOT_BINARY_DIR}/Kernel/xnu/bsd \
	-I${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk \
	-I${ROOT_BINARY_DIR}/${CpuArch} \
	-I${RAVYN_SDKROOT}/usr/include \
	-I${RAVYN_SDKROOT}/usr/local/include \
	-D__DARWIN_UNIX03 \
	-include${.OBJDIR}/config.${CpuArch}.normal.h

# The order of the -reexport- flags below is load-bearing, and putting
# libsystem_pwdgrp ahead of libsystem_info is the whole point of it.
#
# A re-export dylib from this ld64 carries no per-symbol attribution at
# all. Measured, not assumed: dyld_info -exports on the resulting
# libSystem.B lists no re-exported name whatsoever -- not _getpwnam, and
# not _printf either, which is certainly re-exported from libsystem_c.
# Ownership is therefore decided at load time, by the first
# LC_REEXPORT_DYLIB in the list that exports the symbol.
#
# libsystem_info.dylib still exports getpwnam/getpwuid/...; it has always
# carried its own implementation, and that is the component
# MISSING_DEPS.md records as blocked. A libSystem.B that lists it first
# therefore keeps serving the passwd database from the blocked component,
# and this wiring would look complete while changing nothing at all.
# Listing libsystem_pwdgrp first makes it the owner. libsystem_info is
# still re-exported, for getaddrinfo, gethostbyname and the rest of its
# non-passwd surface.

LDFLAGS = -mmacos-version-min=${MACOS_VERSION_MIN} \
	--sysroot=${RAVYN_SDKROOT} \
	-Wl,-syslibroot,${RAVYN_SDKROOT}/usr/lib \
	-L${RAVYN_SDKROOT}/usr/lib/system \
	-L${RAVYN_SDKROOT}/usr/local/lib/system \
	-L${RAVYN_SDKROOT}/usr/lib -Wl,-no_warn_inits \
	-Wl,-install_name,/usr/lib/libSystem.B.dylib \
	-Wl,-current_version,1254 \
	-Wl,-compatibility_version,1.0.0 \
	-nodefaultlibs -dylib -Wl,-search_paths_first \
	-Wl,-reexport-lsystem_c -Wl,-reexport-lsystem_blocks \
	-Wl,-reexport-lsystem_asl -Wl,-reexport-lCrashReporterClient \
	-Wl,-reexport-lsystem_malloc -Wl,-reexport-lsystem_platform \
	-Wl,-reexport-lsystem_darwin -Wl,-reexport-lsystem_pthread \
	-Wl,-reexport-lsystem_kernel -Wl,-reexport-lcompiler_rt \
	-Wl,-reexport-lunwind -Wl,-reexport-lxpc -Wl,-reexport-ldyld \
	-Wl,-reexport-llaunch -Wl,-reexport-ldispatch \
	-Wl,-reexport-lsystem_m -Wl,-reexport-lsystem_coreservices \
	-Wl,-reexport-lsystem_notify \
	-Wl,-reexport-lsystem_pwdgrp -Wl,-reexport-lsystem_info \
	-Wl,-reexport-lsystem_termcap \
	-Wl,-reexport-lcopyfile -Wl,-reexport-lmacho \
	-Wl,-reexport-lremovefile -Wl,-reexport-lsystem_trace \
	-Wl,-reexport-lsystem_dnssd -Wl,-reexport-lcorecrypto \
	-lcompiler_rt -ldyld -lsystem_c -lc++ -lCrashReporterClient\
	-lsystem_platform -lsystem_kernel -lsystem_blocks -lsystem_malloc \
	-lsystem_info -lsystem_notify -lsystem_trace -lsystem_asl \
	-lsystem_blocks -lsystem_pthread -ldispatch -lxpc -llaunch -lsystem_m \
	-lsystem_pwdgrp -lsystem_termcap

all: lib${LIB}.dylib

${.OBJDIR}/config.${CpuArch}.normal.h:
	DEVELOPER_DIR=${ROOT_BINARY_DIR}/Developer \
	RUNTIME_SPEC_PATH=${TOOLCHAIN}/Library/Xcode/Specifications \
	PATH=${TOOLS}:${PATH} \
	${.CURDIR}/xcodescripts/linker_arguments.sh \
	${CpuArch} normal ${.OBJDIR} ${RAVYN_SDKROOT} ${.CURDIR}

${OBJS}: ${.OBJDIR}/config.${CpuArch}.normal.h ${SRCS}

libunwind.dylib: ${.OBJDIR}/../llvm_target/libunwind/lib/libunwind.a
	mkdir -p ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
	${CC} -umbrella System -Wl,-all_load -fuse-ld=${LD} -shared \
	  -dylib -o ${RAVYN_SDKROOT}/usr/lib/system/libunwind.dylib \
	  -Wl,-install_name,/usr/lib/system/libunwind.dylib \
	  -Wl,-compatibility_version,1.0.0 -Wl,-current_version,35.4 \
	  -L${RAVYN_SDKROOT}/usr/lib -L${RAVYN_SDKROOT}/usr/lib/system \
	  -mmacosx-version-min=${MACOS_VERSION_MIN} ${.ALLSRC} \
	  -lsystem_c -lsystem_pthread -lsystem_platform -lcompiler_rt \
	  -lsystem_malloc -ldyld
	cp -f ${RAVYN_SDKROOT}/usr/lib/system/libunwind.dylib \
		${SYSROOT_DIR}/usr/lib/system/

${.OBJDIR}/lib${LIB}.dylib: ${.OBJDIR}/config.${CpuArch}.normal.h \
lib${LIB}.a libunwind.dylib copyfile
	${CC} -fuse-ld=${LD} -shared -dylib -o ${.TARGET} ${OBJS} ${LDFLAGS}
	${.CURDIR}/xcodescripts/create_dylib_symlinks.sh \
	  ${RAVYN_SDKROOT} install normal
	${.CURDIR}/xcodescripts/create_dylib_symlinks.sh \
	  ${SYSROOT_DIR} install normal
	${.CURDIR}/xcodescripts/create_system_framework.sh \
	  ${SYSROOT_DIR} - - - normal
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/
	mkdir -p \
	  ${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/Resources \
	  ${SYSROOT_DIR}/System/Library/Frameworks/System.framework/Versions/B/Resources
	cp -f ${.CURDIR}/Info.plist \
	  ${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/Resources/
	cp -f ${.CURDIR}/Info.plist \
	  ${SYSROOT_DIR}/System/Library/Frameworks/System.framework/Versions/B/Resources/

lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.dylib

SUBDIR = copyfile removefile libdispatch libsystem_blocks libsystem_kernel \
	libsystem_platform libsystem_malloc libsystem_pthread libsystem_notify \
	libsystem_info libsystem_c libsystem_asl libsystem_trace \
	libsystem_dnssd libxpc liblaunch libsystem_m libsystem_darwin \
	libsystem_coreservices libmacho libsystem_pwdgrp libsystem_termcap \
	#CommonCrypto

# Why libsystem_termcap is wired the same way libsystem_pwdgrp is, and the one
# way it is not.
#
# The same: both are components this tree has to own because the archive that
# used to export the symbols is not reachable. pwdgrp's libinfo.o is
# self-referential onto a framework with no build target (see
# libsystem_info/MISSING_DEPS.md); termcap simply did not exist in ravynOS at
# all -- no <termcap.h> in the SDK and no tget* in any Libsystem archive --
# and BSD/lib/libedit/src/terminal.c calls all six entry points
# unconditionally from terminal_set(), so nothing that uses line editing could
# build without it.
#
# NOT the same, and deliberately: the -reexport flag's POSITION is not
# load-bearing for termcap. It is for pwdgrp, because libsystem_info.dylib
# still exports getpwnam and friends and the first LC_REEXPORT_DYLIB that has
# a symbol owns it (see the long note above). Nothing else in this tree
# exports tgetent/tgetflag/tgetnum/tgetstr/tgoto/tputs, so there is no
# competitor to order against. The flag sits next to pwdgrp's for
# readability, not because a symbol resolves differently either way.
#
# One thing this component does that no other does: its Makefile installs
# <termcap.h> into the SDK's usr/include. That is not an extra, it is the half
# that makes the component usable. libedit's src/sys.h includes config.h into
# every translation unit and config.h has HAVE_TERMCAP_H 1, so
# src/terminal.c:57 does `#include <termcap.h>' -- and terminal.c declares the
# six prototypes itself only under `#if defined(__sun)' (src/terminal.c:71-78),
# so without the header the ravynOS build takes an IMPLICIT `int tgetstr()'
# and truncates the returned pointer to 32 bits on x86_64. That is not a
# warning; it is a wrong library.
#
# See libsystem_termcap/README.md.

# Library versions within libsystem were taken from Monterey System.tbd
# libcache.dylib 83
# libcommonCrypto.dylib 60165
# libcompiler_rt.dylib 101.2
# libcorecrypto.dylib 866.0.10
# libdispatch.dylib 1173.0.3
# libdyld.dylib 732.2
# libkeymgr.dylib 30
# liblaunch.dylib 1738.0.17
# libmacho.dylib 949.0.1
# libquarantine.dylib 110.0.3
# libremovefile.dylib 48
# libsystem_asl.dylib 377.0.1
# libsystem_blocks.dylib 74
# libsystem_c.dylib 1353.0.10
# libsystem_configuration.dylib 1061.0.2
# libsystem_coreservices.dylib 114
# libsystem_dnssd.dylib 1096.0.2
# libsystem_featureflags.dylib 17
# libsystem_kernel.dylib 6153.0.168
# libsystem_m.dylib 3178
# libsystem_malloc.dylib 283
# libsystem_notify.dylib 241
# libsystem_platform.dylib 220
# libsystem_pthread.dylib 416.0.6
# libsystem_sandbox.dylib 1217.0.27
# libsystem_secinit.dylib 62.0.2
# libsystem_trace.dylib 1147.0.3
# libunwind.dylib 35.4
# libxpc.dylib 1738.0.17
# libSystem.B.dylib 1281

.include <bsd.lib.mk>
.include <bsd.subdir.mk>
