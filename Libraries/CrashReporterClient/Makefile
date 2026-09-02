MK_WERROR = no
LIB = CrashReporterClient
.if "${.MAKE.OS}" == "Darwin"
SRCS =
OBJS =
CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} -Wno-nullability-completeness -D__kernel_ptr_semantics=
LDFLAGS =
SUBDIR =
all:
	mkdir -p ${.OBJDIR} ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
	touch ${.OBJDIR}/lib${LIB}.a ${.OBJDIR}/lib${LIB}.dylib
	cp -f ${.OBJDIR}/lib${LIB}.a ${RAVYN_SDKROOT}/usr/lib/system/ 2>/dev/null || true
	cp -f ${.OBJDIR}/lib${LIB}.dylib ${RAVYN_SDKROOT}/usr/lib/system/ 2>/dev/null || true
	cp -f ${.OBJDIR}/lib${LIB}.dylib ${SYSROOT_DIR}/usr/lib/system/ 2>/dev/null || true
.else
SRCS = CRClient.c CRClientCPP.cpp
OBJS = ${SRCS:S/.c$/.o/:S/.cpp$/.o/}
CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} -Wno-nullability-completeness
LDFLAGS =
SUBDIR =

.include <bsd.lib.mk>
.endif
