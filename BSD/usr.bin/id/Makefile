# ravynOS id(1).  Mirrors BSD/bin/open's Makefile: the platform clang
# through isysroot-cc against the SDK, linked against the dynamic libSystem
# (the static-link path in tools/bootlab/link-static.sh currently collides on
# _mach_msg2_trap with libsystem_kernel.a's mach_traps.o, so a static id is
# not buildable in this tree).
PROG=	id
SRCS=	id.c
MAN=	id.1 groups.1 whoami.1

MK_WERROR=	no
MK_PIE=		no
WARNS=		1

CFLAGS+=	-g -O2 --sysroot=${RAVYN_SDKROOT} -D__RAVYNOS__ -D__MACH__ \
		-Wno-nullability-completeness -I${RAVYN_SDKROOT}/usr/include

LDFLAGS+=	-L${RAVYN_SDKROOT}/usr/lib -lSystem

.include <bsd.prog.mk>
