.include <bsd.own.mk>

PROG= launchctl
MAN= launchctl.1

BASE_INCLUDE= -I${.CURDIR}/../../include/apple

CFLAGS+= ${BASE_INCLUDE} -fblocks
CFLAGS+= -I${.CURDIR}/../../lib/liblaunch
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
