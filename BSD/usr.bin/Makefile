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

SUBDIR = apply basename chroot cut date dirname env false find getopt grep 
SUBDIR += head kill killall patch pfetch printf sed sw_vers 
SUBDIR += tail tee time touch true uname users whereis which xargs yes
SUBDIR += netstat passwd route su
SUBDIR += chmod chown chgrp stat mktemp logger tty mkfifo nice nohup
SUBDIR += du cmp uniq seq cksum comm paste
SUBDIR += split strings uuidgen getconf file iconv strip join more
SUBDIR += sort wc tr defaults plutil dscl diff
#SUBDIR += fetch id sort who

.include <bsd.subdir.mk>
