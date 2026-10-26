MK_WERROR = no
FRAMEWORK = CoreVideo
FMWK_VERSION = A
FMWK_COMPAT_VERSION = 1.2.0
FMWK_CURRENT_VERSION = 1605.1
INFO_PLIST = Info.plist

SRCS = CVDisplayLink.m CVPixelBuffer.m
HEADERS = Headers/CoreVideo.h

CFLAGS += -I${.CURDIR}/Headers -I${ROOT_SOURCE_DIR}/Frameworks/CoreFoundation \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreFoundation.framework/Headers \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/Foundation.framework/Headers \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreGraphics.framework/Headers \
	-I${RAVYN_SDKROOT}/usr/include \
	-F${RAVYN_SDKROOT}/System/Library/Frameworks

LDFLAGS += -F${RAVYN_SDKROOT}/System/Library/Frameworks \
	-Wl,-framework,Foundation \
	-Wl,-framework,CoreFoundation \
	-Wl,-framework,CoreGraphics \

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
