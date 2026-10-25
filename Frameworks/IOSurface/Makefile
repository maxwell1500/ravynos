MK_WERROR = no
FRAMEWORK = IOSurface
FMWK_VERSION = A

SRCS = IOSurface.c
HEADERS = IOSurface.h

CFLAGS = -I${.CURDIR} -I${RAVYN_SDKROOT}/usr/include -I${ROOT_SOURCE_DIR}/Frameworks
LDFLAGS = -F${RAVYN_SDKROOT}/System/Library/Frameworks -framework CoreFoundation -lSystem

# The in-repo SDK is an install product, not a source tree.  Copy the bundle
# into every SDK that is configured; the empty-string guard keeps a manual
# build with no RAVYN_* variable set from trying to install into the host's
# /System/Library/Frameworks.
fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
