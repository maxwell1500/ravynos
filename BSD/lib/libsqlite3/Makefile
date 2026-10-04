PACKAGE=lib${LIB}
LIB=	sqlite3
MK_WERROR=	no

SRCS=	sqlite3.c
INCS=	sqlite3.h sqlite3ext.h

# SRCTOP is the BSD subtree in a standalone bmake run (src.sys.env.mk sets it
# from the share/mk location), so it cannot name a top-level contrib/ path.
# ROOT_SOURCE_DIR is this tree's spelling for the repository root (see
# BSD/lib/libutil/Makefile) and is exported by tools/bootlab/build-libraries.sh.
SQLITE=	${ROOT_SOURCE_DIR}/contrib/sqlite3
.PATH:	${SQLITE}

WARNS?=	3
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${SQLITE} \
		-DUSE_PREAD=1 \
		-DSTDC_HEADERS=1 \
		-DHAVE_SYS_TYPES_H=1 \
		-DHAVE_SYS_STAT_H=1 \
		-DHAVE_STDLIB_H=1 \
		-DHAVE_STRING_H=1 \
		-DHAVE_MEMORY_H=1 \
		-DHAVE_STRINGS_H=1 \
		-DHAVE_INTTYPES_H=1 \
		-DHAVE_STDINT_H=1 \
		-DHAVE_UNISTD_H=1 \
		-DHAVE_DLFCN_H=1 \
		-DHAVE_USLEEP=1 \
		-DHAVE_LOCALTIME_R=1 \
		-DHAVE_GMTIME_R=1 \
		-DHAVE_DECL_STRERROR_R=1 \
		-DHAVE_STRERROR_R=1 \
		-D_REENTRANT=1 \
		-DSQLITE_THREADSAFE=1

# posix_fallocate does not exist on Darwin: the SDK declares it nowhere and
# libSystem exports no such symbol (verified by grepping the SDK headers and
# `nm -gU /usr/lib/libSystem.B.dylib`). Defining HAVE_POSIX_FALLOCATE makes
# sqlite3.c reference an undeclared identifier. FreeBSD does have it, so keep
# the define there only.
.if ${.MAKE.OS} != "Darwin"
CFLAGS+=	-DHAVE_POSIX_FALLOCATE=1
.endif

.if ${MACHINE_ARCH} == "powerpc64le"
CFLAGS+=	-DSQLITE_BYTEORDER=1234
.endif

.include <bsd.lib.mk>

# The FreeBSD original built libprivatesqlite3.so.0 through bsd.lib.mk's
# shared-library path, with `LIBADD+= pthread`. Neither works on this tree:
# src.libnames.mk's _LIBRARIES carries only the Kerberos stubs, so LIBADD
# pthread is rejected outright, and a .so.0 is not a Mach-O dylib. On Darwin
# every ravynOS BSD library is a static archive built by bsd.lib.mk plus a
# standalone .dylib with an explicit install name (see BSD/lib/libutil and
# BSD/lib/libedit). Do the same here. The install name MUST be absolute:
# ld64 defaults LC_ID_DYLIB to the -o path, which would record the build
# directory in every client's LC_LOAD_DYLIB and resolve nowhere on the target
# (the trap rvn.framework.mk documents for frameworks). -ldyld is required for
# the same reason rvn.framework.mk adds it: isysroot-cc strips -lSystem from
# every dylib link (the SDK's libSystem is assembled from these libraries), and
# ld64 then refuses a dylib that links neither libSystem nor libdyld. pthread_*
# resolve at load time out of libSystem, so no -lpthread is needed.
all: ${.OBJDIR}/lib${LIB}.a ${.OBJDIR}/lib${LIB}.dylib

${.OBJDIR}/lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.a
	${CC} -shared -dylib -o ${.TARGET} \
	  -Wl,-force_load,${.OBJDIR}/lib${LIB}.a -nodefaultlibs \
	  -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/lib${LIB}.dylib \
	  -Wl,-current_version,1 -Wl,-compatibility_version,1.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	mkdir -p ${RAVYN_SDKROOT}/usr/lib ${SYSROOT_DIR}/usr/lib
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/
	# INCS are the public headers bsd.incs.mk would install; with the dylib
	# staged by hand they must be staged here too, or a client that does
	# `#include <sqlite3.h>` (LaunchServices.mm does) finds no header: the
	# build SDK's usr/include has no copy and nothing else puts one there.
	mkdir -p ${RAVYN_SDKROOT}/usr/include ${SYSROOT_DIR}/usr/include
.for h in ${INCS}
	cp -f ${SQLITE}/${h} ${RAVYN_SDKROOT}/usr/include/
	cp -f ${SQLITE}/${h} ${SYSROOT_DIR}/usr/include/
.endfor
