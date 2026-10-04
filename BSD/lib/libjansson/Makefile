PACKAGE=lib${LIB}
LIB=	jansson
MK_WERROR=	no

# SRCS are every translation unit the upstream src/Makefile.am builds.
# src/dtoa.c is included because the release's own configure defaults
# DTOA_ENABLED to 1 (see contrib/jansson/PROVENANCE.md), and strconv.c then
# calls jsonp_dtostr from it.
SRCS=	dtoa.c \
	dump.c \
	error.c \
	hashtable.c \
	hashtable_seed.c \
	load.c \
	memory.c \
	pack_unpack.c \
	strbuffer.c \
	strconv.c \
	utf.c \
	value.c \
	version.c

# jansson.h is the public header; jansson_config.h is the configure-generated
# header it includes, and must be installed beside it. jansson_private_config.h
# is build-private and is NOT installed.
INCS=	jansson.h jansson_config.h

# ROOT_SOURCE_DIR is this tree's spelling for the repository root (see
# BSD/lib/libsqlite3/Makefile) and is exported by tools/bootlab/build-libraries.sh.
JANSSON=	${ROOT_SOURCE_DIR}/contrib/jansson
.PATH:	${JANSSON}/src

WARNS?=	3
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${JANSSON}/src \
		-DHAVE_CONFIG_H \
		-D_REENTRANT=1

# The build SDK's <math.h> omits the C99 isnan()/isinf() macros, which
# jansson's value.c re-defines under `#ifndef isnan` and thereby clashes with
# the SDK declaration.  See jansson-math-compat.h.
CFLAGS+=	-include ${.CURDIR}/jansson-math-compat.h

.include <bsd.lib.mk>

# The FreeBSD original built a .so through bsd.lib.mk's shared path. On Darwin
# every ravynOS BSD library is a static archive from bsd.lib.mk plus a
# standalone .dylib with an explicit install name (see BSD/lib/libsqlite3,
# BSD/lib/libutil and BSD/lib/libedit). The install name MUST be absolute:
# ld64 would otherwise default LC_ID_DYLIB to the -o path and record the build
# directory in every client's LC_LOAD_DYLIB. -ldyld is required because
# isysroot-cc strips -lSystem from dylib links and ld64 refuses a dylib that
# links neither libSystem nor libdyld.
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
	# `#include <jansson.h>` finds no header and jansson.h's own
	# `#include <jansson_config.h>` resolves nowhere.
	mkdir -p ${RAVYN_SDKROOT}/usr/include ${SYSROOT_DIR}/usr/include
.for h in ${INCS}
	cp -f ${JANSSON}/src/${h} ${RAVYN_SDKROOT}/usr/include/
	cp -f ${JANSSON}/src/${h} ${SYSROOT_DIR}/usr/include/
.endfor
