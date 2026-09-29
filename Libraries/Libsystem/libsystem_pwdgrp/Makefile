# libsystem_pwdgrp, shared dylib.
#
# The passwd and group database for the DYNAMIC userland. This is the half
# that matters most: without it, a dynamically linked ravynOS program
# resolves getpwnam/getpwuid/... from libsystem_info/libsystem_info.dylib,
# whose libinfo.o is self-referential onto the SystemInformation framework.
# libsystem_info/MISSING_DEPS.md records that component as blocked on absent
# libxpc / libsystem_trace / libsystem_notify, so a dynamic program that
# touches the passwd database cannot link at all. Adding this component to
# libSystem.B is what removes that.
#
# The static-link half is the subdirectory build below; see static/Makefile.
# See README.md for why this is a component of its own rather than more of
# libsystem_info.
LIB = system_pwdgrp

# `static` builds too, so `all` in this directory is the whole component and
# nothing has to remember to go and build the archive separately. The archive
# is what tools/bootlab/link-static.sh consumes.
SUBDIR = static

SRCS = pwdgrp.c
MK_WERROR = no

CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-momit-leaf-frame-pointer -fno-stack-protector -fno-stack-check \
	-fno-builtin -fvisibility=default \
	-Wno-implicit-function-declaration -Wno-nullability-completeness \
	-Wno-int-conversion -Wno-implicit-int
CFLAGS += -I${.CURDIR} -I${RAVYN_SDKROOT}/usr/include \
	-I${RAVYN_SDKROOT}/usr/local/include

# Two flags here are load-bearing, and both are the opposite of what the
# sibling Makefiles around this tree do. That is deliberate:
#
#   -nodefaultlibs
#       clang appends -lSystem to EVERY Darwin dylib link, and it appends it
#       after the command line, so no amount of filtering an explicit -lSystem
#       out of LDFLAGS removes it. In this SDK /usr/lib/libSystem.dylib is a
#       symlink to the 4 KB libSystem.B.dylib, which is a pure LC_REEXPORT
#       shim: linking it here would make this dylib depend on the very
#       aggregate that is about to depend on this dylib, and the re-export
#       would resolve to nothing. The same reasoning that makes
#       Libraries/Libsystem/Makefile pass -nodefaultlibs applies here.
#
#   NO -umbrella System
#       Several sibling components put it in LDFLAGS. It resolves "System" to
#       the SDK's libSystem.dylib, which is the same shim, and reintroduces
#       exactly the cycle -nodefaultlibs exists to break. It is also not
#       needed: a dylib records the libraries it actually imports, which is
#       what dyld has to load.
#
# -lsystem_c supplies fopen/fgets/fclose/fgetc/rewind and the _chk forms;
# -lsystem_platform supplies strchr/strcmp/strlen. Both were confirmed with
# `dyld_info -exports`, not guessed from where they "should" live: this tree
# puts the string and memory primitives in libsystem_platform, not
# libsystem_c.
LDFLAGS = -nodefaultlibs -shared -Wl,-dylib -fuse-ld=${LD} \
	-mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wl,-syslibroot,${RAVYN_SDKROOT}/usr/lib \
	-L${RAVYN_SDKROOT}/usr/lib -L${RAVYN_SDKROOT}/usr/lib/system \
	-L${RAVYN_SDKROOT}/usr/local/lib/system \
	-Wl,-install_name,/usr/lib/system/lib${LIB}.dylib \
	-Wl,-compatibility_version,1 -Wl,-current_version,1 \
	-lsystem_c -lsystem_platform

# current_version 1 rather than a number copied from a macOS counterpart:
# this library has no released history, and a version that claims to be
# libsystem_info's 1254 would be a lie about which implementation a
# program is calling.

all: ${.OBJDIR}/lib${LIB}.dylib

${.OBJDIR}/lib${LIB}.dylib: lib${LIB}.a
	${CC} -o ${.TARGET} ${OBJS} ${LDFLAGS}
	mkdir -p ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/system/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/system/
	cp -f ${.CURDIR}/libsystem_pwdgrp.h ${RAVYN_SDKROOT}/usr/include/
	cp -f ${.CURDIR}/libsystem_pwdgrp.h ${SYSROOT_DIR}/usr/include/

lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.dylib

.include <bsd.lib.mk>
.include <bsd.subdir.mk>
