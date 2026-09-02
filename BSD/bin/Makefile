MK_TESTS = no
CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -Wno-nullability-completeness
LDFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -fuse-ld=${LD}
.export CFLAGS LDFLAGS MK_TESTS

.if "${.MAKE.OS}" == "Darwin"
SUBDIR =
.else
SUBDIR = cat echo hostname ls ps pwd realpath rm sleep sh test
.endif

.include <bsd.subdir.mk>
