.include <src.opts.mk>

CFLAGS = -Wno-int-conversion

PROG=	sysctl

MK_WERROR = no
MAN=	sysctl.8
CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -Wno-nullability-completeness
LDFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -fuse-ld=${LD}

HAS_TESTS=

.include <bsd.prog.mk>
