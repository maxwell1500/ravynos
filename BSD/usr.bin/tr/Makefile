# PROVENANCE: tr here is a FRESH implementation written against the POSIX
# specification for tr(1), not a port of FreeBSD tr. See the header comment
# in tr.c, which is the authoritative statement; that header also records the
# divergences from macOS /usr/bin/tr found by adversarial testing, and names
# verify-ravyn-wc-tr.sh as the test suite.
PROG=	tr
SRCS=	tr.c

all: to-sysroot

to-sysroot: ${PROG}
	mkdir -p ${SYSROOT_DIR}/usr/bin
	cp -f ${PROG} ${SYSROOT_DIR}/usr/bin/

.include <bsd.prog.mk>
