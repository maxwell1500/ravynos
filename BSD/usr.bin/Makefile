MK_TESTS = no
CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -Wno-nullability-completeness
LDFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -fuse-ld=${LD}
.export CFLAGS LDFLAGS MK_TESTS

SUBDIR = basename dirname env false sw_vers 
SUBDIR += tail tee time touch true uname users whereis which xargs yes
#SUBDIR += sort who

.include <bsd.subdir.mk>
