MK_WERROR = no
FRAMEWORK = CoreUI
FMWK_COMPAT_VERSION = 1.0.0
FMWK_VERSION = A

SRCS = CoreUI.c

CFLAGS = -I${.CURDIR} -I${RAVYN_SDKROOT}/usr/include -I${ROOT_SOURCE_DIR}/Frameworks
LDFLAGS = -lSystem

# Private frameworks live under /System/Library/PrivateFrameworks, not
# Frameworks, so this hook cannot reuse the common one.
fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/PrivateFrameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/PrivateFrameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
