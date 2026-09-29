# libsystem_pwdgrp, STATIC-LINK variant.
#
# The passwd and group database for a -static, dyld-free ravynOS executable.
# Same shape as libsystem_pthread/static: a separate subdirectory build whose
# only product is an archive to link into a static program, leaving the
# component's own dylib build untouched.
#
# Why it is needed at all: the real getpwnam/getpwuid/... implementations in
# libsystem_info/libinfo.a cannot be linked, because libinfo.o is
# self-referential onto the SystemInformation framework and that component is
# documented as blocked (libsystem_info/MISSING_DEPS.md). See ../README.md.
#
# Consumers: tools/bootlab/link-static.sh, through RAVYN_EXTRA_LIBS:
#
#   RAVYN_EXTRA_LIBS="-L.../libsystem_pwdgrp/static -lsystem_pwdgrp_static"
#
.PATH: ${.CURDIR:H}

LIB = system_pwdgrp_static
SUBDIR =

MK_WERROR = no

# One translation unit, reached through .PATH above rather than a subdir.
SRCS = pwdgrp.c

# Self-contained rather than .include "common.mk": pthread's common.mk drags
# in its own include paths and -D__LIBC__, none of which this one source file
# needs, and inheriting them is how a build ends up compiling with flags
# nobody chose.
CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-momit-leaf-frame-pointer -fno-stack-protector -fno-stack-check \
	-fno-builtin \
	-Wno-implicit-function-declaration -Wno-nullability-completeness \
	-Wno-int-conversion -Wno-implicit-int
CFLAGS += -I${.CURDIR:H} -I${RAVYN_SDKROOT}/usr/include \
	-I${RAVYN_SDKROOT}/usr/local/include

all: lib${LIB}.a install-static

# Not named `install`: that is a reserved bsd.subdir.mk target, and
# shadowing it makes ${.TARGET} resolve to this target's own name. Same
# reason, same wording, as libsystem_pthread/static.
install-static: lib${LIB}.a
	mkdir -p ${RAVYN_SDKROOT}/usr/local/lib/system
	cp -f ${.OBJDIR}/lib${LIB}.a ${RAVYN_SDKROOT}/usr/local/lib/system/

.include <bsd.lib.mk>
