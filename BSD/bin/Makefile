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

# The host is Darwin, but these programs are cross-built against RAVYN_SDKROOT
# like every other tree component; the old "Darwin builds nothing" guard left
# /bin nearly empty in the staged image even though the sources compile.
SUBDIR = cat cp cpdup date dd df echo ed expr hostname kill launchctl ln \
         login ls mkdir mv nproc open pax pwait pkill pwd realpath ps rm \
         rmdir sh sleep stty test

.include <bsd.subdir.mk>
