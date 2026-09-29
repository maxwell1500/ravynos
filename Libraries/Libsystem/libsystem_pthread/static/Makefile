# libsystem_pthread, STATIC-LINK variant.
#
# This is a SEPARATE build from the one in the parent directory, and it is
# the only place -DVARIANT_STATIC is defined for pthread. The parent
# builds the shared libsystem_pthread.dylib that dyld loads; this one
# builds an archive to be linked into a -static, dyld-free executable.
#
# Why the flag is not shared: VARIANT_STATIC is not cosmetic. It selects a
# different set of definitions (see the guard at pthread.c:1700 and the
# PTHREAD_LIBC_SHIM weak marking at pthread.c:2694), and the shared dylib
# must keep the Libc-interposing ones. Defining it in the parent's CFLAGS
# would change the dylib, so it is set here, in a directory the parent's
# SUBDIR list cannot reach by accident.
#
# The relationship to ../dyld/Makefile is deliberate and NOT accidental:
# that one also sets -DVARIANT_STATIC, but it adds -DVARIANT_DYLD, which
# compiles the memset/bzero/memcpy shims out entirely (they are inside
# `#if !VARIANT_DYLD`). That is correct for dyld, which must not pull in
# Libc at all. A static *user* program does link Libc, so the shims must
# be present, and they must be weak so the real ones in libsystem_platform
# win. Hence -DVARIANT_STATIC alone here.
#
# Consumers: tools/bootlab/link-static.sh links this archive with libc.a,
# libsyscalls.a, libsystem_{kernel,malloc,platform,blocks}.a and the residue
# stubs in Libraries/Libsystem/static/. See that directory's README.md for
# what makes a static-link stub legitimate.
#
.PATH: ${.CURDIR:H}

LIB = pthread_static
SUBDIR =

.include "common.mk"

CFLAGS := ${CFLAGS:S/${.CURDIR}/${.CURDIR:H}/} -DVARIANT_STATIC
ACFLAGS := ${CFLAGS}

all: lib${LIB}.a install-static

# Not named `install`: that is a reserved bsd.subdir.mk target, and
# shadowing it makes ${.TARGET} resolve to this target's own name.
install-static: lib${LIB}.a
	mkdir -p ${RAVYN_SDKROOT}/usr/local/lib/system
	cp -f ${.OBJDIR}/lib${LIB}.a ${RAVYN_SDKROOT}/usr/local/lib/system/

.include <bsd.lib.mk>
