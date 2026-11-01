PROG = route
SRCS = route.c
MAN =
MK_WERROR = no

CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wno-nullability-completeness -D_DARWIN_C_SOURCE

LDFLAGS = -Wl,-platform_version -Wl,macos \
	  -Wl,${MACOS_VERSION_MIN} -Wl,${MACOS_VERSION_MIN} \
	  -Wl,-syslibroot,${RAVYN_SDKROOT}/usr/lib -lSystem

all: ${PROG}

${.OBJDIR}/${PROG}:
	mkdir -p ${.TARGET:H}

${PROG}: ${.OBJDIR}/${PROG}

install: ${PROG}

.include <bsd.prog.mk>
