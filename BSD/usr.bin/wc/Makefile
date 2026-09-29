# PROVENANCE: wc here is a FRESH implementation written against the POSIX
# specification for wc(1), not a port of FreeBSD wc. See the header comment
# in wc.c, which is the authoritative statement; this Makefile deliberately
# matches the shape of its neighbours so it builds through exactly the same
# machinery.
#
# Note there is no `-l` for a locale library, and no source for one. The
# platform cannot provide a usable multibyte locale (no crt1.o, so nothing
# calls setlocale(LC_ALL, ""); no locale data in the SDK), which is why wc
# refuses -m rather than counting bytes and calling them characters.
PROG=	wc
SRCS=	wc.c

all: to-sysroot

to-sysroot: ${PROG}
	mkdir -p ${SYSROOT_DIR}/usr/bin
	cp -f ${PROG} ${SYSROOT_DIR}/usr/bin/

.include <bsd.prog.mk>
