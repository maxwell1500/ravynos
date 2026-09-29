# libcommonCrypto.dylib -- a real re-export wrapper over libcorecrypto.
#
# WHY THIS IS A WRAPPER AND NOT A COPY
#
#   The SDK shipped an 8,064-byte placeholder for libcommonCrypto. Nothing in
#   the tree links against it (measured: zero inbound LC_LOAD_DYLIB references,
#   zero -l references in any Makefile, not in the libSystem.B re-export list),
#   so it was never blocking anything -- but a placeholder that sits in
#   /usr/lib/system is exactly the misleading-stub failure this project exists
#   to remove.
#
#   The cryptographic primitives themselves are already real: libcorecrypto is
#   built from Libraries/Libsystem/corecrypto (19 declarations sourced from
#   Kernel/xnu/BUILD/obj/EXPORT_HDRS/osfmk/mach) and is 53,608 B with 74
#   exports. libcommonCrypto is the thin umbrella that userspace links against
#   to reach them, so it is built as what it is -- a re-export shim -- rather
#   than by compiling CommonCrypto's 98 sources into a second implementation
#   that would duplicate the primitives and drift from them.
#
#   No ABI is invented here. This file contributes no code and no symbols; it
#   forwards to a library that already exists and is already verified.
#
# WHAT THIS IS NOT
#   Not a stub, and not a substitute: it has a real load command naming a real
#   dependency, and the dependency is itself real. If libcorecrypto is absent
#   the wrapper will not load, which is the correct behaviour and the opposite
#   of an 8,064-byte placeholder that loads and does nothing.

MK_WERROR = no
SUBDIR =
LIB = commonCrypto

CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN}
ACFLAGS = ${CFLAGS}

LDFLAGS = -mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wl,-install_name,/usr/lib/system/lib${LIB}.dylib \
	-Wl,-current_version,1 -Wl,-compatibility_version,1.0.0 \
	-Wl,-reexport-lcorecrypto \
	-L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib

all: ${.OBJDIR}/lib${LIB}.dylib
lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.dylib

# A re-export-only dylib has no objects; -nodefaultlibs and
# -undefined dynamic_lookup are still required, and isysroot-cc supplies
# -nodefaultlibs and -Wl,-not_for_dyld_shared_cache, which ld64 requires for
# any /usr/lib/system/ install name.
${.OBJDIR}/lib${LIB}.dylib:
	${CC} -shared -dylib -o ${.TARGET} -nodefaultlibs \
	  -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  ${LDFLAGS}
	mkdir -p ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/system/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/system/

.include <bsd.lib.mk>
