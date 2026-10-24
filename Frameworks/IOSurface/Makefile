MK_WERROR = no
FRAMEWORK = IOSurface
FMWK_VERSION = A

SRCS = IOSurface.c
HEADERS = IOSurface.h

CFLAGS = -I${.CURDIR} -I${RAVYN_SDKROOT}/usr/include -I${ROOT_SOURCE_DIR}/Frameworks
LDFLAGS = -F${RAVYN_SDKROOT}/System/Library/Frameworks -framework CoreFoundation -lSystem

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT}/System/Library/Frameworks/ ${SYSROOT_DIR}/System/Library/Frameworks/ ${RAVYN_REPO_SDKROOT}/System/Library/Frameworks/
	mkdir -p ${dir}
	cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework ${dir}
.endfor

.include <rvn.framework.mk>
