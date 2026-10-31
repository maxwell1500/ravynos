MK_WERROR = no
FRAMEWORK = LocalAuthentication
FMWK_COMPAT_VERSION = 1.0.0
FMWK_VERSION = A

SRCS = LAContext.m

CFLAGS = -fobjc-arc -I${.CURDIR} -I${RAVYN_SDKROOT}/usr/include \
	-I${ROOT_SOURCE_DIR}/Frameworks -I${ROOT_SOURCE_DIR}/Frameworks/Foundation/Headers
LDFLAGS = -F${RAVYN_SDKROOT}/System/Library/Frameworks -framework Foundation -lSystem

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
