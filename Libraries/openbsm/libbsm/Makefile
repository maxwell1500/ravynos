# /usr/lib/libbsm.0.dylib from the in-tree OpenBSM sources.
#
# Chrome links this library for the audit-token API (two symbols on its path)
# and records the versioned name.  The sources and their generated config.h
# were already in the tree; only the recipe was missing.
LIB=		bsm
MK_WERROR=	no
SRCS=		bsm_audit.c bsm_class.c bsm_control.c bsm_domain.c bsm_errno.c \
		bsm_event.c bsm_fcntl.c bsm_flags.c bsm_io.c bsm_mask.c \
		bsm_notify.c bsm_socket_type.c bsm_token.c bsm_user.c \
		bsm_wrappers.c endian_support.c
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${ROOT_SOURCE_DIR}/Libraries/openbsm \
		-I${ROOT_SOURCE_DIR}/Libraries/openbsm/sys \
		-I${ROOT_SOURCE_DIR}/Libraries/openbsm/compat \
		-I${ROOT_SOURCE_DIR}/Libraries/openbsm/config \
		-DHAVE_AUDIT_SYSCALLS=1 \
		-DHAVE_IPC_PERM__SEQ=1 -DHAVE_IPC_PERM__KEY=1 \
		-Wno-implicit-function-declaration \
		-Wno-int-conversion -Wno-sign-conversion -Wno-format

.include <bsd.lib.mk>

all: ${.OBJDIR}/lib${LIB}.a ${.OBJDIR}/lib${LIB}.0.dylib

${.OBJDIR}/lib${LIB}.0.dylib: ${.OBJDIR}/lib${LIB}.a
	${CC} -shared -dylib -o ${.TARGET} \
	  -Wl,-force_load,${.OBJDIR}/lib${LIB}.a -nodefaultlibs \
	  -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libbsm.0.dylib \
	  -Wl,-compatibility_version,1.0.0 -Wl,-current_version,1.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include/bsm"; \
	  cp -f ${.TARGET} "$$sdk/usr/lib/lib${LIB}.0.dylib"; \
	  ln -sf lib${LIB}.0.dylib "$$sdk/usr/lib/lib${LIB}.dylib"; \
	  cp -f ${ROOT_SOURCE_DIR}/Libraries/openbsm/sys/bsm/*.h "$$sdk/usr/include/bsm/"; \
	done
