MK_TESTS = no
CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -Wno-nullability-completeness
LDFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -fuse-ld=${LD}
.export CFLAGS LDFLAGS MK_TESTS

SUBDIR = env true false basename dirname sw_vers 
SUBDIR += time touch uname users whereis which xargs yes
#SUBDIR += who

.include <bsd.subdir.mk>
