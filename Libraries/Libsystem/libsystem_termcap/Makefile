# libsystem_termcap, shared dylib.
#
# The termcap interface (tgetent/tgetnum/tgetflag/tgetstr/tgoto/tputs) for
# the DYNAMIC userland. It exists because BSD/lib/libedit/src/terminal.c
# calls all six unconditionally from terminal_set() and has no non-termcap
# path, and ravynOS had no termcap at all: no <termcap.h> anywhere in the SDK
# and no tget* symbol in any Libsystem archive. Without this component
# libedit cannot build, so no line editing anywhere.
#
# See README.md for what the entries contain, what they deliberately do not,
# and why tgetent() here never returns -1.
#
# The static-link half is the subdirectory build below; see static/Makefile.
LIB = system_termcap

# `static` builds too, so `all` in this directory is the whole component and
# nothing has to remember to go and build the archive separately. The archive
# is what BSD/bin/sh/build-ravynos.sh consumes.
SUBDIR = static

SRCS = termcap.c
MK_WERROR = no

CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-momit-leaf-frame-pointer -fno-stack-protector -fno-stack-check \
	-fno-builtin -fvisibility=default \
	-Wno-implicit-function-declaration -Wno-nullability-completeness \
	-Wno-int-conversion -Wno-implicit-int
CFLAGS += -I${.CURDIR} -I${RAVYN_SDKROOT}/usr/include \
	-I${RAVYN_SDKROOT}/usr/local/include

# The same two decisions libsystem_pwdgrp/Makefile makes, for the same two
# reasons, which are restated here because a reader should not have to go
# looking:
#
#   -nodefaultlibs
#       clang appends -lSystem to EVERY Darwin dylib link, and appends it
#       AFTER the command line, so no amount of filtering an explicit
#       -lSystem out of LDFLAGS removes it. In this SDK
#       /usr/lib/libSystem.dylib is a symlink to the 4 KB libSystem.B.dylib,
#       which is a pure LC_REEXPORT shim: linking it here would make this
#       dylib depend on the aggregate that is about to depend on it.
#
#   NO -umbrella System
#       It resolves "System" to that same shim and reintroduces the cycle.
#       It is not needed: a dylib records the libraries it actually imports,
#       which is what dyld has to load.
#
# -lsystem_c supplies getenv/strtol; -lsystem_platform supplies the string and
# memory primitives. Both were confirmed with `dyld_info -exports`, not guessed
# from where they "should" live.
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
# libsystem_c's 1353 would be a lie about which implementation a program is
# calling.
all: ${.OBJDIR}/lib${LIB}.dylib

${.OBJDIR}/lib${LIB}.dylib: lib${LIB}.a
	${CC} -o ${.TARGET} ${OBJS} ${LDFLAGS}
	mkdir -p ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/system/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/system/
	# termcap.h is installed under the name a program includes. BSD/lib/
	# libedit/src/terminal.c:58 does `#include <termcap.h>' behind
	# HAVE_TERMCAP_H, and config.h defines it, so without this header the
	# component that needs this one cannot even compile. See README.md,
	# "The header name".
	cp -f ${.CURDIR}/termcap.h ${RAVYN_SDKROOT}/usr/include/
	cp -f ${.CURDIR}/termcap.h ${SYSROOT_DIR}/usr/include/

lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.dylib

.include <bsd.lib.mk>
.include <bsd.subdir.mk>
