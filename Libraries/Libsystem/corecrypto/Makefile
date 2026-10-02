# libcorecrypto.dylib -- built from the in-tree corecrypto primitives.
#
# ============================================================================
# READ THIS BEFORE RECORDING "CORECRYPTO DONE"
# ============================================================================
#
# This library is NOT a drop-in replacement for the prebuilt
# libcorecrypto.dylib. The two export near-DISJOINT symbol sets:
#
#   prebuilt (tools/bootlab/assets/usr/lib/system/libcorecrypto.dylib, from
#   Apple's dyld shared cache) exports 9 symbols, ALL of them CC* *constants*:
#       _CCEC_FAULT_CANARY  _CCMLDSA_FAULT_CANARY  _CCRSA_PKCS1_FAULT_CANARY
#       _CCRSA_PSS_FAULT_CANARY  _CCSS_PRIME_P192 .. _CCSS_PRIME_P521
#
#   this library exports 68 symbols, ALL of them cc_* *functions*:
#       _cc_clear  _cc_cmp_safe  _cc_print  _ccdigest_init  ...
#   CC* constant exports: 0
#
# It satisfies the libSystem.B reexport only because ld64 requires an upward /
# reexported library to be *findable*, not because it provides its contents.
# Anyone expecting _CCSS_PRIME_P256, or any of the fault canaries, from
# libcorecrypto.dylib will NOT get them. Do not treat this component as a
# completed corecrypto; it is a primitives library occupying the slot.
#
# ============================================================================
# SOURCE PROVENANCE -- and a trap
# ============================================================================
#
# Two corecrypto trees exist in this repo and they are NOT the same generation.
# The .c files under Kernel/Extensions/corecrypto/ are written against the
# kext's OWN headers:
#     Kernel/Extensions/corecrypto/include/corecrypto/   48 headers  <-- correct
# and NOT against:
#     Kernel/xnu/EXTERNAL_HEADERS/corecrypto/            42 headers  <-- stale
# which is missing cc_abort.h, ccmd5.h, cc_debug.h and ccrc4.h. Pointing -I at
# the XNU export tree instead of the kext's own drops the build from 16/22
# files compiling to 12/22, for reasons that have nothing to do with this
# Makefile. That is the same shape of problem as the Availability.h and mach/
# trees: the question is never "is the source there" but "which generation of
# headers is the source written against".
#
# ============================================================================
# WHAT IS DELIBERATELY NOT BUILT, AND WHY -- do not re-chase these
# ============================================================================
#
# 16 of the 22 files under Kernel/Extensions/corecrypto compile. The 6 that do
# not fall into three groups:
#
#  1. cc_abort.h -- RESOLVED, and it is worth recording how.
#     The genuine 10-line header exists at
#         Kernel/Extensions/corecrypto/cc_abort.h
#     but it is MISFILED: the sources include <corecrypto/cc_abort.h>, which
#     resolves to Kernel/Extensions/corecrypto/include/corecrypto/, where it is
#     absent. The kext keeps 48 headers under include/corecrypto/ and this one
#     sits at the kext root.
#     Fixed with include-shim/corecrypto/cc_abort.h, which defines nothing and
#     forwards to the real file by relative path. That unblocked cc_functions.c
#     and cc_digest.c, which are in SRCS and now build.
#
#     BUT the shim only cleared HALF the group, and this is the
#     first-error-masks-a-second case worth keeping on record:
#         algorithms/aes_cbc.c:33:9: error: call to undeclared library
#             function 'abort' with type 'void ()'
#     The real header's non-kernel branch is
#         #include <stdio.h> / #include <stdlib.h>
#         #define cc_abort(msg, ...) do { fprintf(stderr, msg, __VA_ARGS__); abort(); } while (0)
#     so the SDK's <stdlib.h> is reached but does not declare abort() under
#     this project's flags. Verified it is NOT an include-ordering artefact:
#     ...the same <stdlib.h> resolution.
#     The real cause was an include SHADOW, found with clang -H:
#         Kernel/xnu/EXTERNAL_HEADERS/stdlib.h      <-- wins, does not declare abort()
#         $SDK/usr/include/stdlib.h                 <-- the real one, declares abort() at :131
#     EXTERNAL_HEADERS contains a one-line FBSD shim stdlib.h, and with
#     -I Kernel/xnu/EXTERNAL_HEADERS on the path it pre-empts the SDK's header
#     for every translation unit in this component. That -I has been removed.
#     aes_cbc.c and aes_ecb.c are back in SRCS.
#
#     CORRECTION to an earlier claim of mine: I reported this was NOT include
#     ordering. That test was invalid -- it ran before the cc_abort.h shim
#     resolved, so both arms failed for the unrelated reason. Re-tested with the
#     shim in place, ordering was the cause after all.
#
#  2. Kext-only glue that hits kernel-only declarations in userspace:
#         cc_kext_main.c  algorithms/yarrow/smf.c
#     both die on "socket.h:561:30: error: a parameter list without types is
#     only allowed in a function definition" -- a KERNEL-guarded socket.h
#     declaration parsed in a userspace context. These are kext entry points and
#     are not wanted in a userspace dylib regardless of how the header is fixed.
#
#  3. Version skew between the kext source and the header set:
#         algorithms/cckprng.c
#     expects cckprng_init(struct cckprng_ctx *, unsigned, size_t, const void *,
#     ...) and touches bytes_generated / bytes_since_entropy, none of which
#     exist in this tree's cckprng.h. Source and headers are from different
#     corecrypto generations. No include path fixes this; it needs a matching
#     header set.

MK_WERROR = no
SUBDIR =
LIB = corecrypto

CCROOT = ${ROOT_SOURCE_DIR}/Kernel/Extensions/corecrypto
.PATH: ${CCROOT} ${CCROOT}/algorithms ${CCROOT}/algorithms/yarrow ${CCROOT}/kext

SRCS = \
	aes128.c \
	cckprng.c \
	md5.c \
	sha1.c \
	comp.c \
	prng.c \
	sha1mod.c \
	yarrowUtils.c \
	cc_clear.c \
	cc_cmp_safe.c \
	cc_debug.c \
	pdcrypto_digest_final.c \
	pdcrypto_digest_init.c \
	pdcrypto_digest_update.c \
	cc_functions.c \
	cc_digest.c \
	aes_cbc.c \
	aes_ecb.c \
	pdcrypto_dummy.c \
	sha256.cc \
	sha512.cc \
	md5_impl.cpp \
	sha1_impl.cc

SLF = /System/Library/Frameworks
CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-w -Wno-nullability-completeness -DPRIVATE -D_LIBCPP_VISIBLE="" \
	-I${.CURDIR}/include-shim \
	-I${CCROOT}/include \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern \
	-I${RAVYN_SDKROOT}/usr/local/include \
	-I${RAVYN_SDKROOT}/usr/local/include/kernel \
	-I${RAVYN_SDKROOT}/usr/include
ACFLAGS = ${CFLAGS}

# Established recipe for a standalone sub-dylib of libSystem: install under
# /usr/lib/system/ so ld64 treats it as shared-cache eligible, and rely on
# isysroot-cc to add -nodefaultlibs -undefined dynamic_lookup
# -Wl,-not_for_dyld_shared_cache (ld64 refuses -undefined dynamic_lookup for
# shared-cache-eligible dylibs without that last flag).
LDFLAGS = -mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wl,-current_version,1 -Wl,-compatibility_version,1.0.0 \
	-Wl,-install_name,/usr/lib/system/lib${LIB}.dylib \
	-L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib

all: ${.OBJDIR}/lib${LIB}.dylib
lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.dylib

${.OBJDIR}/lib${LIB}.dylib: lib${LIB}.a
	${CC} -fuse-ld=${LD} -shared -dylib -o ${.TARGET} \
	  -Wl,-force_load,${.OBJDIR}/lib${LIB}.a ${LDFLAGS}
	mkdir -p ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/system/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/system/

.include <bsd.lib.mk>
