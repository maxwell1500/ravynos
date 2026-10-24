PROG=	pasteboardd
SRCS=	pasteboardd.c
# There is no pasteboardd(8) man page in this tree; bsd.prog.mk's "all" target
# would otherwise fail trying to install one.
MAN= 

MK_WERROR=	no
MK_PIE=		no
WARNS=		1

CFLAGS+=	-g -O2 -D__MACH__ -D__RAVYNOS__ -pthread \
		-I${.CURDIR} \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel

# The mach_* and bootstrap_* entry points live in libSystem on ravynOS (there
# is no separate libmach), so -lmach does not resolve here.
LDFLAGS+=	-L${RAVYN_SDKROOT}/usr/lib -L${RAVYN_SDKROOT}/usr/lib/system \
		-lSystem -pthread

.include <bsd.prog.mk>
