.include <bsd.own.mk>

PROG= launchctl
MAN= launchctl.1

# The SDK already ships sys/resource.h with rusage_info; the in-tree copy
# redefines it and dies under -Werror. Only the mach headers below are needed.
BASE_INCLUDE=

CFLAGS+= ${BASE_INCLUDE} -fblocks
CFLAGS+= -I${.CURDIR}/../../lib/liblaunch -I${ROOT_SOURCE_DIR}/Libraries/Libsystem/liblaunch -I${ROOT_SOURCE_DIR}/BSD/lib/libutil
CFLAGS+= -I${.CURDIR}/../../include/mach
LDFLAGS+= -llaunch -ldispatch
LDFLAGS+= -pthread
# DPADD referenced ${LIBJANSSON}, which nothing in this tree defines: FreeBSD
# gets it from src.libnames.mk, whose _LIBRARIES here carries only the
# Kerberos stubs.  Point it at the dylib that -ljansson below resolves
# against, built by BSD/lib/libjansson into the SDK.
LIBJANSSON= ${RAVYN_SDKROOT}/usr/lib/libjansson.dylib
DPADD+= ${LIBJANSSON}
LDFLAGS+= -lutil
LDFLAGS+= -ljansson
SRCS= launchctl.c

.include <bsd.prog.mk>

# liblaunch ships in /usr/lib/system on ravynOS, not /usr/lib.
LDFLAGS+=	-L${RAVYN_SDKROOT}/usr/lib/system
