.include <src.opts.mk>

.if "${.MAKE.OS}" == "Darwin"
all:
	@echo "stub ls for Darwin host"
	mkdir -p ${SYSROOT_DIR}/bin
	touch ${SYSROOT_DIR}/bin/ls
.else
SUBDIR =
MK_WERROR = no
PROG=	ls
SRCS=	cmp.c ls.c print.c util.c

HAS_TESTS=

all: to-sysroot

to-sysroot: ${PROG}
	mkdir -p ${SYSROOT_DIR}/bin
	cp -f ${PROG} ${SYSROOT_DIR}/bin/
.endif

.include <bsd.prog.mk>
