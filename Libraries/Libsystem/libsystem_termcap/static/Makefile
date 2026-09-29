# libsystem_termcap, STATIC-LINK variant.
#
# The termcap interface for a -static, dyld-free ravynOS executable. Same
# shape as libsystem_pwdgrp/static and libsystem_pthread/static: a separate
# subdirectory build whose only product is an archive to link into a static
# program, leaving the component's own dylib build untouched.
#
# Why it is needed at all: BSD/lib/libedit/src/terminal.c calls
# tgetent/tgetflag/tgetnum/tgetstr/tgoto/tputs unconditionally from
# terminal_set() and has no non-termcap path. ravynOS had none of them, so the
# target libedit.a could not be built and BSD/bin/sh had to be compiled with
# -DNO_HISTORY. See ../README.md and BSD/bin/sh/build-ravynos.sh.
#
# Consumers: BSD/bin/sh/build-ravynos.sh, through RAVYN_EXTRA_LIBS:
#
#   RAVYN_EXTRA_LIBS="-L.../libsystem_termcap/static -lsystem_termcap_static"
#
.PATH: ${.CURDIR:H}

LIB = system_termcap_static
SUBDIR =

MK_WERROR = no

# One translation unit, reached through .PATH above rather than a subdir.
SRCS = termcap.c

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

# Not named `install`: that is a reserved bsd.subdir.mk target, and shadowing
# it makes ${.TARGET} resolve to this target's own name. Same reason, same
# wording, as libsystem_pwdgrp/static.
install-static: lib${LIB}.a
	mkdir -p ${RAVYN_SDKROOT}/usr/local/lib/system \
		${RAVYN_SDKROOT}/usr/include
	cp -f ${.OBJDIR}/lib${LIB}.a ${RAVYN_SDKROOT}/usr/local/lib/system/
	# The header goes in too, and not only as a convenience: libedit's
	# terminal.c includes <termcap.h> when HAVE_TERMCAP_H is defined
	# (src/terminal.c:57-58) and declares the six prototypes itself only
	# under #if defined(__sun) (src/terminal.c:71-78). Without the header
	# the ravynOS build compiles terminal.c with an IMPLICIT `int
	# tgetstr()', which on x86_64 truncates the returned pointer to 32
	# bits. That is not a warning, it is a wrong library. See README.md,
	# "Why the header is not optional".
	cp -f ${.CURDIR:H}/termcap.h ${RAVYN_SDKROOT}/usr/include/

.include <bsd.lib.mk>
