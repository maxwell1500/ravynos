# Cross-build flags.  -mmacos-version-min is deliberately absent: combined
# with a ravynOS sysroot clang reports "using sysroot for 'ravynOS' but
# targeting 'MacOSX'", and the target triple already comes from isysroot-cc.
MK_TESTS = no
MK_WERROR = no
CFLAGS = --sysroot=${RAVYN_SDKROOT} -Wno-nullability-completeness \
         -Wno-incompatible-sysroot -Wno-expansion-to-defined -Wno-deprecated-declarations -Wno-incompatible-function-pointer-types \
         -I${ROOT_SOURCE_DIR}/BSD/compat/include -I${ROOT_SOURCE_DIR}/BSD/lib/libutil
LDFLAGS = --sysroot=${RAVYN_SDKROOT} -fuse-ld=${LD}
.export CFLAGS LDFLAGS MK_TESTS

SUBDIR = aslmanager dmesg sysctl syslogd tmutil usermgmt

.include <bsd.subdir.mk>
