SUBDIR =
MK_WERROR = no

# The old Darwin branch ran `touch` on the SDK dylib and on libutil.a, which
# produced two 0-byte files. That is the same defect that destroyed
# libCrashReporterClient: a 0-byte archive is rejected by ld64 outright, and a
# 0-byte dylib loads and does nothing. This branch now BUILDS. It must never
# touch.
LIB = util
SRCS =	getmntopts.c \
	humanize_number.c \
	_secure_path.c \
	login_auth.c \
	login_cap.c \
	login_class.c \
	pidfile.c \
	realhostname.c \
	reexec_to_match_kernel.c \
	trimdomain.c \
	tzlink.c \
	wipefs.cpp \
	ExtentManager.cpp


MAN = getmntopts.3 \
      humanize_number.3 \
      pidfile.3 \
      realhostname.3 \
      realhostname_sa.3 \
      reexec_to_match_kernel.3 \
      trimdomain.3 \
      wipefs.3


CFLAGS = -ObjC --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -I${.CURDIR} -I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/wrappers/spawn \
        -I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern ${CFLAGS.${.TARGET}}
CXXFLAGS = -ObjC++ --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -I${.CURDIR} -I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/wrappers/spawn \
        -I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern
LDFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -fuse-ld=${LD}

# ${RAVYN_SDKROOT}/usr/include/os/object.h does not exist in this SDK; the
# kernel flavour lives under usr/local/include/kernel/os/. Pointed at the real
# file rather than forcing one in blindly.
CFLAGS.tzlink.o = -I${ROOT_SOURCE_DIR}/Libraries/Libsystem/liblaunch \
        -include${RAVYN_SDKROOT}/usr/local/include/kernel/os/object.h

#SUBDIR = tzlinkd

.include <bsd.lib.mk>
.include <bsd.subdir.mk>

# Install the built library. bsd.lib.mk produces lib${LIB}.a; the dylib is the
# standalone form the SDK expects, built with the established recipe.
all: ${.OBJDIR}/lib${LIB}.a ${.OBJDIR}/lib${LIB}.dylib

${.OBJDIR}/lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.a
	${CC} -shared -dylib -o ${.TARGET} \
	  -Wl,-force_load,${.OBJDIR}/lib${LIB}.a -nodefaultlibs \
	  -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/system/lib${LIB}.dylib \
	  -Wl,-current_version,1 -Wl,-compatibility_version,1.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib
	mkdir -p ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/system/
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/system/
